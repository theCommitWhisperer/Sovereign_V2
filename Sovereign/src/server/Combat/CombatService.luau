--!strict
-- CombatService: Core combat v2 engine for Sovereign.
--
-- Replaces the monolithic CombatManager loop with:
--   • SpatialGrid target acquisition (no more O(n²) scans)
--   • Counter-matrix damage via DamageResolver (pure, testable)
--   • Real projectile flight for ranged units (ProjectileSystem)
--   • Expanded ability roster (AbilitySystem)
--   • Batched client VFX replication (CombatReplication)
--   • Building targeting + siege damage
--
-- The public API mirrors the legacy CombatManager so GameManager/UnitManager
-- call sites keep working through the CombatManager facade.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local CombatTypes = require(script.Parent.CombatTypes)
local SpatialGrid = require(script.Parent.SpatialGrid)
local DamageResolver = require(script.Parent.DamageResolver)
local ProjectileSystem = require(script.Parent.ProjectileSystem)
local AbilitySystem = require(script.Parent.AbilitySystem)
local CombatReplication = require(script.Parent.CombatReplication)

local Managers = script.Parent.Parent.Managers
local MoraleManager = require(Managers.MoraleManager)
local FactionManager = require(Managers.FactionManager)
local RevoltManager = require(Managers.RevoltManager)
local PlayerManager = require(Managers.PlayerManager)

-- Lazy-loaded to avoid circular dependencies (legacy pattern preserved)
local AchievementManager = nil :: any
local QuestManager = nil :: any

local CombatDebug = DebugManager.createChannel("Combat", false)
local DamageDebug = DebugManager.createChannel("Damage", false)

type CombatUnit = CombatTypes.CombatUnit
type CombatBuilding = CombatTypes.CombatBuilding
type Stance = CombatTypes.Stance

local Engine = CombatConfig.Engine
local Positional = CombatConfig.Positional
local MoraleCfg = CombatConfig.Morale

local CombatService = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════

local ActiveCombatUnits: { [Model]: CombatUnit } = {}
local ActiveBuildings: { [Model]: CombatBuilding } = {}
local unitGrid = SpatialGrid.new(Engine.GRID_CELL_SIZE)
local buildingGrid = SpatialGrid.new(Engine.GRID_CELL_SIZE)

local moraleEnabled = true
local lastUpdateTime = 0
local heartbeatConnection: RBXScriptConnection? = nil

local killListeners: { (victim: CombatUnit, killer: CombatUnit?) -> () } = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function metersToStuds(meters: number): number
	return meters * Engine.METERS_TO_STUDS
end

local function getAttackRangeStuds(unitData: GameData.UnitData): number
	if not unitData.combat then
		return Engine.MELEE_RANGE
	end
	local combat = unitData.combat :: any
	local rangeInStuds = metersToStuds(combat.attack_range or 2)
	if unitData.subtype == "Ranged" or unitData.subtype == "Ranged Infantry" then
		rangeInStuds *= Engine.RANGED_RANGE_MULT
	end
	return math.max(rangeInStuds, Engine.MELEE_RANGE)
end

local function isIrish(unit: CombatUnit): boolean
	return unit.faction == "Irish" or unit.faction == "Kingdom"
end

local function areEnemies(a: CombatUnit, b: CombatUnit): boolean
	return FactionManager.areEnemies(a.faction, b.faction)
end

local function getPosition(model: Model): Vector3?
	local part = model.PrimaryPart
	return part and part.Position or nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- REGISTRATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Normalizes any legacy-shaped combat unit table into the v2 shape.
function CombatService.registerCombatUnit(unitModel: Model, combatUnit: any)
	local unitData = combatUnit.unitData :: GameData.UnitData
	local profile = CombatConfig.getProfile(combatUnit.unitType, unitData and unitData.subtype or nil)

	-- Legacy fields
	if combatUnit.celticFuryActive == nil then
		combatUnit.celticFuryActive = false
		combatUnit.lastWarCryTime = 0
		combatUnit.inShieldWall = false
		combatUnit.shieldWallAllies = {}
	end

	-- v2 fields
	combatUnit.profile = profile
	combatUnit.attackType = profile.attackType
	-- Normalize attack range (legacy AI-spawn path used raw meters * 3 with no
	-- melee floor or ranged bonus)
	if unitData then
		combatUnit.attackRange = getAttackRangeStuds(unitData)
	end
	combatUnit.inFormationCohesion = false
	combatUnit.stunnedUntil = 0
	combatUnit.lastAbilityTimes = {}
	combatUnit.berserkActive = false
	combatUnit.battleSongMult = 1
	combatUnit.battleSongUntil = 0
	combatUnit.ambushSpentOn = nil
	combatUnit.damageDealt = 0
	combatUnit.kills = 0
	combatUnit.lastScanTime = 0
	combatUnit.scanJitter = math.random() * CombatConfig.Targeting.SCAN_JITTER_MAX
	combatUnit.slotAngle = math.random() * 2 * math.pi

	ActiveCombatUnits[unitModel] = combatUnit :: CombatUnit

	local position = getPosition(unitModel)
	if position then
		unitGrid:update(unitModel, position)
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = combatUnit.maxHealth
		humanoid.Health = combatUnit.health
	end

	CombatDebug:info("Registered combat unit", {
		unitType = combatUnit.unitType,
		faction = combatUnit.faction,
		damageType = profile.damageType,
		armorClass = profile.armorClass,
		attackType = profile.attackType,
	})
end

function CombatService.initializeCombatUnit(unitModel: Model, owner: Player)
	local unitType = unitModel:GetAttribute("UnitType") :: string?
	if not unitType then
		CombatDebug:warn("Unit has no UnitType attribute", { modelName = unitModel.Name })
		return
	end

	local unitData = GameData.Units[unitType]
	if not unitData or not unitData.combat then
		CombatDebug:warn("No combat data for unit type", { unitType = unitType })
		return
	end
	local combat = unitData.combat :: any

	local playerData = PlayerManager.get(owner)
	local faction = (playerData and playerData.Faction) or "Kingdom"
	local startingMorale = MoraleManager.getMorale(unitModel) or 75

	local combatUnit = {
		model = unitModel,
		unitData = unitData,
		owner = owner.UserId,
		unitType = unitType,
		health = (unitModel:GetAttribute("CurrentHealth") :: number?) or unitData.health.max_health,
		maxHealth = unitData.health.max_health,
		attackDamage = combat.attack_damage,
		attackSpeed = combat.attack_speed,
		attackRange = getAttackRangeStuds(unitData),
		armor = combat.armor,
		morale = startingMorale,
		stance = "Aggressive",
		targetModel = nil,
		formation = nil,
		lastAttackTime = 0,
		isCharging = false,
		faction = faction,
	}

	CombatService.registerCombatUnit(unitModel, combatUnit)
end

-- Buildings become combat entities lazily (first time targeted or registered).
function CombatService.registerBuilding(buildingModel: Model): CombatBuilding?
	local existing = ActiveBuildings[buildingModel]
	if existing then
		return existing
	end

	local buildingType = buildingModel:GetAttribute("BuildingType") :: string?
	if not buildingType then
		return nil
	end

	local ownerId = (buildingModel:GetAttribute("OwnerId") :: number?) or 0
	local maxHealth = CombatConfig.getBuildingMaxHealth(buildingType)
	local currentHealth = (buildingModel:GetAttribute("CurrentHealth") :: number?) or maxHealth

	-- Faction from owning player, else neutral-hostile default
	local faction = "Kingdom"
	local ownerPlayer = Players:GetPlayerByUserId(ownerId)
	if ownerPlayer then
		local playerData = PlayerManager.get(ownerPlayer)
		if playerData and playerData.Faction then
			faction = playerData.Faction
		end
	elseif ownerId == 1000000 then
		faction = "Viking"
	end

	buildingModel:SetAttribute("MaxHealth", maxHealth)
	buildingModel:SetAttribute("CurrentHealth", currentHealth)

	local building: CombatBuilding = {
		model = buildingModel,
		owner = ownerId,
		buildingType = buildingType,
		faction = faction,
		health = currentHealth,
		maxHealth = maxHealth,
	}
	ActiveBuildings[buildingModel] = building

	local position = buildingModel:GetPivot().Position
	buildingGrid:update(buildingModel, position)

	-- Clean up if another system removes the building
	buildingModel.Destroying:Connect(function()
		ActiveBuildings[buildingModel] = nil
		buildingGrid:remove(buildingModel)
	end)

	return building
end

-- Register every existing building and watch for new ones so siege targeting
-- can find them via the building grid.
local function watchBuildingsFolder()
	task.spawn(function()
		local buildingsFolder = Workspace:WaitForChild("Buildings", 30)
		if not buildingsFolder then
			CombatDebug:warn("No workspace.Buildings folder found; siege targeting disabled")
			return
		end
		for _, child in buildingsFolder:GetChildren() do
			if child:IsA("Model") then
				CombatService.registerBuilding(child)
			end
		end
		buildingsFolder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				-- Defer: attributes are set after parenting in BuildingManager
				task.defer(function()
					if child.Parent then
						CombatService.registerBuilding(child :: Model)
					end
				end)
			end
		end)
	end)
end

local function unregisterUnit(unitModel: Model)
	ActiveCombatUnits[unitModel] = nil
	unitGrid:remove(unitModel)
end

local function unregisterBuilding(buildingModel: Model)
	ActiveBuildings[buildingModel] = nil
	buildingGrid:remove(buildingModel)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TARGET ACQUISITION (spatial grid, scored for organic group fights)
-- ═══════════════════════════════════════════════════════════════════════════

local Targeting = CombatConfig.Targeting

-- How many units are currently attacking each target. Rebuilt every combat
-- tick (cheap at ~200 units) so it never drifts, no matter who clears targets.
local engagementCounts: { [Model]: number } = {}

local function rebuildEngagementCounts()
	table.clear(engagementCounts)
	for _, unit in ActiveCombatUnits do
		local target = unit.targetModel
		if target then
			engagementCounts[target] = (engagementCounts[target] or 0) + 1
		end
	end
end

-- Lower score = better target. Blends distance, crowding, and counters so an
-- army fans out into separate melees instead of blobbing onto one enemy.
local function scoreEnemy(unit: CombatUnit, enemy: CombatUnit, distance: number): number
	local score = distance

	-- Crowding: avoid piling onto targets that are already swarmed
	local attackers = engagementCounts[enemy.model] or 0
	local crowdingMult = if unit.attackType == "Ranged" then Targeting.RANGED_CROWDING_MULT else 1
	score += attackers * Targeting.CROWDING_PENALTY * crowdingMult
	if attackers >= Targeting.SOFT_CAP_ATTACKERS then
		score += Targeting.OVERCROWD_PENALTY * crowdingMult
	end

	-- Counters: prefer matchups we're strong in (spears seek cavalry, etc.)
	local matrixRow = CombatConfig.CounterMatrix[unit.profile.damageType]
	local counterMult = (matrixRow and matrixRow[enemy.profile.armorClass]) or 1
	local bonuses = unit.profile.bonusVsTags
	if bonuses and enemy.profile.tags then
		for _, tag in enemy.profile.tags :: { string } do
			counterMult *= bonuses[tag] or 1
		end
	end
	score -= (counterMult - 1) * Targeting.COUNTER_WEIGHT

	-- Noise: identical units shouldn't all make the same choice
	score += math.random() * Targeting.SCORE_JITTER

	return score
end

local function findBestEnemyTarget(unit: CombatUnit, maxRange: number): (Model?, number)
	local unitPos = getPosition(unit.model)
	if not unitPos then
		return nil, math.huge
	end

	local best: Model? = nil
	local bestScore = math.huge

	unitGrid:query(unitPos, maxRange, function(enemyModel, enemyPos)
		if enemyModel == unit.model then
			return nil
		end
		local enemy = ActiveCombatUnits[enemyModel]
		if not enemy or enemy.health <= 0 or not areEnemies(unit, enemy) then
			return nil
		end
		local score = scoreEnemy(unit, enemy, (enemyPos - unitPos).Magnitude)
		if score < bestScore then
			best = enemyModel
			bestScore = score
		end
		return nil
	end)

	return best, bestScore
end

local function findNearestEnemyBuilding(unit: CombatUnit, maxRange: number): Model?
	local unitPos = getPosition(unit.model)
	if not unitPos then
		return nil
	end

	local nearest: Model? = nil
	local nearestDistSq = maxRange * maxRange

	buildingGrid:query(unitPos, maxRange, function(buildingModel, buildingPos)
		local building = ActiveBuildings[buildingModel]
		if not building or building.health <= 0 then
			return nil
		end
		if not FactionManager.areEnemies(unit.faction, building.faction) then
			return nil
		end
		local distSq = (buildingPos - unitPos).Magnitude ^ 2
		if distSq < nearestDistSq then
			nearest = buildingModel
			nearestDistSq = distSq
		end
		return nil
	end)

	return nearest
end

-- Ally/enemy radius visitors used by AbilitySystem + cohesion checks
local function forEachAllyInRadius(unit: CombatUnit, radius: number, visitor: (CombatUnit) -> ())
	local pos = getPosition(unit.model)
	if not pos then
		return
	end
	unitGrid:query(pos, radius, function(model, _modelPos)
		if model ~= unit.model then
			local other = ActiveCombatUnits[model]
			if other and other.health > 0 and not areEnemies(unit, other) then
				visitor(other)
			end
		end
		return nil
	end)
end

local function forEachEnemyInRadius(unit: CombatUnit, radius: number, visitor: (CombatUnit) -> ())
	local pos = getPosition(unit.model)
	if not pos then
		return
	end
	unitGrid:query(pos, radius, function(model, _modelPos)
		if model ~= unit.model then
			local other = ActiveCombatUnits[model]
			if other and other.health > 0 and areEnemies(unit, other) then
				visitor(other)
			end
		end
		return nil
	end)
end

local function countAlliesInRadius(unit: CombatUnit, radius: number): number
	local count = 0
	forEachAllyInRadius(unit, radius, function()
		count += 1
	end)
	return count
end

local abilityContext: AbilitySystem.AbilityContext = {
	units = ActiveCombatUnits,
	moraleEnabled = true,
	forEachAllyInRadius = forEachAllyInRadius,
	forEachEnemyInRadius = forEachEnemyInRadius,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- DEATH HANDLING
-- ═══════════════════════════════════════════════════════════════════════════

local function handleUnitDeath(victim: CombatUnit, killer: CombatUnit?)
	CombatDebug:info("Unit killed", { unitType = victim.unitType, faction = victim.faction })

	local deathPos = getPosition(victim.model)
	unregisterUnit(victim.model)

	if killer then
		killer.kills += 1
	end

	for _, listener in killListeners do
		task.spawn(listener, victim, killer)
	end

	if deathPos then
		CombatReplication.death(deathPos)
	end

	local humanoid = victim.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
		humanoid:ChangeState(Enum.HumanoidStateType.Dead)
	end

	-- Fade out corpse
	for _, part in victim.model:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(2), { Transparency = 1 }):Play()
		end
	end

	MoraleManager.evaluateCombatSituation(victim.model)

	local ownerPlayer = Players:GetPlayerByUserId(victim.owner)
	if ownerPlayer then
		RevoltManager.recordUnitLoss(ownerPlayer)
	end

	-- Nearby enemies gain morale; killer's owner gets achievement/quest credit
	forEachEnemyInRadius(victim, MoraleCfg.NEARBY_DEATH_RADIUS, function(enemy)
		MoraleManager.modifyMorale(enemy.model, MoraleCfg.NEARBY_DEATH_ENEMY_BONUS, "Enemy killed")
	end)

	if killer then
		local killerPlayer = Players:GetPlayerByUserId(killer.owner)
		if killerPlayer then
			if not AchievementManager then
				AchievementManager = require(Managers.AchievementManager) :: any
			end
			if not QuestManager then
				QuestManager = require(Managers.QuestManager) :: any
			end
			AchievementManager.incrementStat(killerPlayer, "EnemiesKilled", 1)
			if victim.unitType == "Viking" then
				AchievementManager.incrementStat(killerPlayer, "VikingsKilled", 1)
				QuestManager.updateQuestProgress(killerPlayer, "KillEnemies", "Viking", 1)
			end
		end
	end

	task.delay(2, function()
		if victim.model and victim.model.Parent then
			victim.model:Destroy()
		end
	end)
end

local function handleBuildingDestroyed(building: CombatBuilding)
	CombatDebug:info("Building destroyed", { buildingType = building.buildingType })
	local pos = building.model:GetPivot().Position
	unregisterBuilding(building.model)
	CombatReplication.buildingDestroyed(pos)

	-- Fade + remove
	for _, part in building.model:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(1.5), { Transparency = 1 }):Play()
		end
	end
	task.delay(1.5, function()
		if building.model and building.model.Parent then
			building.model:Destroy()
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DAMAGE APPLICATION
-- ═══════════════════════════════════════════════════════════════════════════

local function applyDamageToUnit(attacker: CombatUnit, defender: CombatUnit, damage: number)
	defender.health = math.max(0, defender.health - damage)
	defender.model:SetAttribute("CurrentHealth", defender.health)

	local humanoid = defender.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = defender.health
	end

	attacker.damageDealt += damage

	local pos = getPosition(defender.model)
	if pos then
		CombatReplication.hit(pos, damage)
	end

	if moraleEnabled then
		MoraleManager.modifyMorale(defender.model, MoraleCfg.DAMAGE_TAKEN_MORALE_LOSS, "Took damage")
		MoraleManager.modifyMorale(attacker.model, MoraleCfg.DAMAGE_DEALT_MORALE_GAIN, "Dealt damage")
	end

	if defender.health <= 0 then
		handleUnitDeath(defender, attacker)
	end
end

-- Resolve one attack instance (melee hit or projectile impact)
local function resolveHit(attacker: CombatUnit, defender: CombatUnit, now: number)
	if defender.health <= 0 or ActiveCombatUnits[defender.model] == nil then
		return
	end

	local attackerPos = getPosition(attacker.model)
	local defenderPos = getPosition(defender.model)
	local positionalMult = 1
	if attackerPos and defenderPos and defender.model.PrimaryPart then
		positionalMult = DamageResolver.getPositionalMult(
			attackerPos,
			defenderPos,
			(defender.model.PrimaryPart :: BasePart).CFrame.LookVector
		)
	end

	-- Pack Hunter cares about packmates (other beasts), not all allies
	local attackerAllyCount: number
	if CombatConfig.hasTag(attacker.profile, "beast") then
		attackerAllyCount = 0
		forEachAllyInRadius(attacker, Positional.FORMATION_RADIUS, function(ally)
			if CombatConfig.hasTag(ally.profile, "beast") then
				attackerAllyCount += 1
			end
		end)
	else
		attackerAllyCount = countAlliesInRadius(attacker, Positional.FORMATION_RADIUS)
	end

	local ctx: DamageResolver.DamageContext = {
		attackerAllyCount = attackerAllyCount,
		defenderAllyCount = countAlliesInRadius(defender, Positional.FORMATION_RADIUS),
		isIrish = isIrish(attacker),
		moraleEnabled = moraleEnabled,
	}

	local breakdown = DamageResolver.calculate(attacker, defender, positionalMult, ctx)

	-- Braced spears counter-strike chargers before damage lands
	if breakdown.braced then
		attacker.isCharging = false
		local matrixRow = CombatConfig.CounterMatrix[defender.profile.damageType]
		local counterMult = (matrixRow and matrixRow[attacker.profile.armorClass]) or 1
		local counterDamage = math.max(1, math.floor(defender.attackDamage * Positional.BRACE_COUNTER_BONUS * counterMult))
		applyDamageToUnit(defender, attacker, counterDamage)
		if attacker.health <= 0 then
			return
		end
	end

	local onHitFx = AbilitySystem.onHit(attacker, defender, now)
	if onHitFx.stunTarget then
		defender.stunnedUntil = now + (onHitFx.stunTarget :: number)
	end

	applyDamageToUnit(attacker, defender, breakdown.final)

	DamageDebug:info("Attack", {
		attacker = attacker.unitType,
		defender = defender.unitType,
		damage = breakdown.final,
		counter = breakdown.counterMult,
		positional = breakdown.positionalMult,
	})

	-- Volley: fire extra projectiles at nearby enemies
	if onHitFx.extraShots and attacker.profile.projectile then
		local shotsLeft = onHitFx.extraShots :: number
		forEachEnemyInRadius(attacker, attacker.attackRange, function(enemy)
			if shotsLeft <= 0 or enemy == defender then
				return
			end
			shotsLeft -= 1
			local fromPos = getPosition(attacker.model)
			if fromPos then
				ProjectileSystem.fire(
					attacker.profile.projectile :: string,
					fromPos,
					enemy.model,
					enemy.model:GetAttribute("IsMoving") == true,
					function(hitModel)
						local hitUnit = ActiveCombatUnits[hitModel]
						if hitUnit then
							resolveHit(attacker, hitUnit, os.clock())
						end
					end
				)
			end
		end)
	end
end

local function executeAttackOnUnit(attacker: CombatUnit, defender: CombatUnit, now: number)
	if attacker.attackType == "Ranged" and attacker.profile.projectile then
		local fromPos = getPosition(attacker.model)
		if not fromPos then
			return
		end
		ProjectileSystem.fire(
			attacker.profile.projectile :: string,
			fromPos,
			defender.model,
			defender.model:GetAttribute("IsMoving") == true,
			function(hitModel)
				local hitUnit = ActiveCombatUnits[hitModel]
				if hitUnit and attacker.health > 0 then
					resolveHit(attacker, hitUnit, os.clock())
				end
			end
		)
	else
		CombatReplication.swing(attacker.model)
		resolveHit(attacker, defender, now)
	end
end

local function executeAttackOnBuilding(attacker: CombatUnit, building: CombatBuilding)
	if attacker.attackType ~= "Ranged" then
		CombatReplication.swing(attacker.model)
	end
	local damage = DamageResolver.calculateVsBuilding(attacker)
	building.health = math.max(0, building.health - damage)
	building.model:SetAttribute("CurrentHealth", building.health)
	attacker.damageDealt += damage

	local pos = building.model:GetPivot().Position
	CombatReplication.buildingHit(pos, damage)

	if building.health <= 0 then
		handleBuildingDestroyed(building)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN UPDATE LOOP
-- ═══════════════════════════════════════════════════════════════════════════

local function faceTarget(unitModel: Model, targetPos: Vector3)
	local part = unitModel.PrimaryPart
	if not part then
		return
	end
	local flatTarget = Vector3.new(targetPos.X, part.Position.Y, targetPos.Z)
	if (flatTarget - part.Position).Magnitude > 0.01 then
		part.CFrame = CFrame.lookAt(part.Position, flatTarget)
	end
end

-- Broken units rout: drop combat and run from the nearest threats.
-- MoraleManager owns the IsFleeing state (flee threshold + rally recovery);
-- this makes the routing actually move the unit.
local function updateFleeing(unitModel: Model, unit: CombatUnit, now: number)
	unit.targetModel = nil
	unit.isCharging = false

	if now - unit.lastScanTime < 0.5 then
		return
	end
	unit.lastScanTime = now

	local unitPos = getPosition(unitModel)
	if not unitPos then
		return
	end

	-- Run directly away from the average position of nearby enemies
	local threatSum = Vector3.zero
	local threatCount = 0
	forEachEnemyInRadius(unit, 50, function(enemy)
		local enemyPos = getPosition(enemy.model)
		if enemyPos then
			threatSum += enemyPos
			threatCount += 1
		end
	end)

	local fleeDir: Vector3
	if threatCount > 0 then
		local away = unitPos - threatSum / threatCount
		away = Vector3.new(away.X, 0, away.Z)
		fleeDir = if away.Magnitude > 0.5
			then away.Unit
			else Vector3.new(math.cos(unit.slotAngle), 0, math.sin(unit.slotAngle))
	else
		-- No visible threats: keep running in this unit's own panic direction
		fleeDir = Vector3.new(math.cos(unit.slotAngle), 0, math.sin(unit.slotAngle))
	end

	unitModel:SetAttribute("TargetPosition", unitPos + fleeDir * 30)
	unitModel:SetAttribute("IsMoving", true)
end

local function updateUnit(unitModel: Model, unit: CombatUnit, now: number)
	-- Stunned units do nothing
	if now < unit.stunnedUntil then
		return
	end

	-- Routing overrides everything — including player orders. Rally is handled
	-- by MoraleManager clearing IsFleeing when morale recovers.
	if unitModel:GetAttribute("IsFleeing") == true then
		updateFleeing(unitModel, unit, now)
		return
	end

	-- Manual movement precedence: player-ordered moves suppress combat AI
	local hasManualMovement = unitModel:GetAttribute("IsMoving") == true and unit.targetModel == nil
	if hasManualMovement then
		return
	end

	-- Abilities (auras, fury, heals, etc.)
	AbilitySystem.update(unit, now, abilityContext)

	-- Formation cohesion flag (cheap: allies close by)
	unit.inFormationCohesion = countAlliesInRadius(unit, Positional.FORMATION_RADIUS)
		>= Positional.FORMATION_MIN_ALLIES

	-- ── Validate existing target ─────────────────────────────────────────
	local targetModel = unit.targetModel
	if targetModel then
		local targetUnit = ActiveCombatUnits[targetModel]
		local targetBuilding = ActiveBuildings[targetModel]
		local valid = targetModel.Parent ~= nil
			and ((targetUnit ~= nil and targetUnit.health > 0)
				or (targetBuilding ~= nil and targetBuilding.health > 0))
		if not valid then
			unit.targetModel = nil
			targetModel = nil
		end
	end

	-- ── Acquire a new target (LOD-throttled, desynced per unit) ──────────
	if not targetModel and unit.stance ~= "Hold" then
		if now - unit.lastScanTime >= Engine.IDLE_SCAN_RATE + unit.scanJitter then
			unit.lastScanTime = now
			local searchRange = Engine.SEARCH_RANGE
			if unit.stance == "Aggressive" then
				searchRange *= Engine.AGGRESSIVE_SEARCH_MULT
			end
			targetModel = findBestEnemyTarget(unit, searchRange)

			-- No enemy units around: aggressive units siege enemy buildings
			if not targetModel and unit.stance == "Aggressive" then
				targetModel = findNearestEnemyBuilding(unit, Engine.BUILDING_SEARCH_RANGE)
			end
			unit.targetModel = targetModel
		end
	end

	if not targetModel then
		local hasManualOrder = unitModel:GetAttribute("IsMoving") == true
			and unitModel:GetAttribute("TargetPosition") ~= nil
		if not hasManualOrder then
			unit.isCharging = false
		end
		return
	end

	-- ── Engage ───────────────────────────────────────────────────────────
	local targetUnit = ActiveCombatUnits[targetModel]
	local targetBuilding = if targetUnit then nil else ActiveBuildings[targetModel]

	local unitPos = getPosition(unitModel)
	if not unitPos then
		return
	end

	local targetPos: Vector3
	local effectiveRange = unit.attackRange
	if targetUnit then
		local p = getPosition(targetModel)
		if not p then
			return
		end
		targetPos = p
	elseif targetBuilding then
		targetPos = targetModel:GetPivot().Position
		-- Buildings are big; approximate footprint so melee can reach them
		local _, size = targetModel:GetBoundingBox()
		effectiveRange += math.max(size.X, size.Z) * 0.5
	else
		return
	end

	local distance = (targetPos - unitPos).Magnitude

	if distance <= effectiveRange then
		unitModel:SetAttribute("IsMoving", false)
		unitModel:SetAttribute("TargetPosition", nil)
		unit.isCharging = false
		faceTarget(unitModel, targetPos)

		if now - unit.lastAttackTime >= unit.attackSpeed then
			unit.lastAttackTime = now
			if targetUnit then
				executeAttackOnUnit(unit, targetUnit, now)
			elseif targetBuilding then
				executeAttackOnBuilding(unit, targetBuilding)
			end
		end
	else
		-- Still chasing: occasionally re-evaluate so units peel off toward
		-- better fights (nearby brawls, favourable counters, lonely enemies)
		-- instead of tunnel-chasing across the whole battle.
		if targetUnit and now - unit.lastScanTime >= Targeting.RETARGET_INTERVAL then
			unit.lastScanTime = now
			local searchRange = Engine.SEARCH_RANGE
			if unit.stance == "Aggressive" then
				searchRange *= Engine.AGGRESSIVE_SEARCH_MULT
			end
			local best, bestScore = findBestEnemyTarget(unit, searchRange)
			if best and best ~= targetModel then
				local currentScore = scoreEnemy(unit, targetUnit, distance)
				if bestScore < currentScore - Targeting.RETARGET_MARGIN then
					unit.targetModel = best
					return -- engage the new target next tick
				end
			end
		end

		-- Close the distance (MovementSystem consumes these attributes).
		-- Melee units aim for a personal ring slot around the target so
		-- attackers surround it instead of stacking on one point.
		local moveDest = targetPos
		if targetUnit and unit.attackType == "Melee" then
			moveDest = targetPos
				+ Vector3.new(math.cos(unit.slotAngle), 0, math.sin(unit.slotAngle))
					* Targeting.SURROUND_RADIUS
		end
		unitModel:SetAttribute("TargetPosition", moveDest)
		unitModel:SetAttribute("IsMoving", true)

		if unit.stance == "Aggressive" or unit.stance == "Charge" then
			unit.isCharging = distance <= Positional.CHARGE_DISTANCE and distance > effectiveRange
		else
			unit.isCharging = false
		end
	end
end

local function updateCombat(now: number)
	abilityContext.moraleEnabled = moraleEnabled
	rebuildEngagementCounts()

	for unitModel, unit in ActiveCombatUnits do
		if not unitModel.Parent or unit.health <= 0 then
			unregisterUnit(unitModel)
			continue
		end

		local position = getPosition(unitModel)
		if not position then
			continue
		end
		unitGrid:update(unitModel, position)

		-- Sync morale from MoraleManager (it owns the value)
		unit.morale = MoraleManager.getMorale(unitModel) or unit.morale

		updateUnit(unitModel, unit, now)
	end

	ProjectileSystem.update(now)
	CombatReplication.flush()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API (mirrors legacy CombatManager)
-- ═══════════════════════════════════════════════════════════════════════════

function CombatService.setMoraleEnabled(enabled: boolean)
	moraleEnabled = enabled
end

function CombatService.isMoraleEnabled(): boolean
	return moraleEnabled
end

function CombatService.setTarget(attackerModel: Model, targetModel: Model)
	local attacker = ActiveCombatUnits[attackerModel]
	if not attacker then
		CombatDebug:warn("Attacker not in combat system", { model = attackerModel.Name })
		return
	end

	local target = ActiveCombatUnits[targetModel]
	if target then
		if not areEnemies(attacker, target) then
			CombatDebug:warn("Cannot attack ally", { attacker = attacker.unitType, target = target.unitType })
			return
		end
	else
		-- Maybe it's a building
		local building = CombatService.registerBuilding(targetModel)
		if not building then
			CombatDebug:warn("Target is neither unit nor building", { model = targetModel.Name })
			return
		end
		if not FactionManager.areEnemies(attacker.faction, building.faction) then
			CombatDebug:warn("Cannot attack allied building", { building = building.buildingType })
			return
		end
	end

	attacker.targetModel = targetModel
	attacker.stance = "Aggressive"
	attackerModel:SetAttribute("IsMoving", false)
	attackerModel:SetAttribute("TargetPosition", nil)
end

function CombatService.setStance(unitModel: Model, stance: Stance)
	local unit = ActiveCombatUnits[unitModel]
	if not unit then
		CombatDebug:warn("Unit not in combat system for stance change")
		return
	end
	unit.stance = stance
	if stance == "Hold" then
		unit.targetModel = nil
		unitModel:SetAttribute("IsMoving", false)
		unitModel:SetAttribute("TargetPosition", nil)
	end
end

function CombatService.clearTarget(unitModel: Model)
	local unit = ActiveCombatUnits[unitModel]
	if unit then
		unit.targetModel = nil
		unit.isCharging = false
	end
end

function CombatService.getActiveCombatUnits(): { [Model]: CombatUnit }
	return ActiveCombatUnits
end

function CombatService.getActiveBuildings(): { [Model]: CombatBuilding }
	return ActiveBuildings
end

function CombatService.getUnit(model: Model): CombatUnit?
	return ActiveCombatUnits[model]
end

function CombatService.onUnitKilled(listener: (victim: CombatUnit, killer: CombatUnit?) -> ()): () -> ()
	table.insert(killListeners, listener)
	return function()
		local index = table.find(killListeners, listener)
		if index then
			table.remove(killListeners, index)
		end
	end
end

-- Instantly remove every active combat unit (sandbox /killall)
function CombatService.clearAllUnits()
	for unitModel in ActiveCombatUnits do
		unitModel:Destroy()
	end
	table.clear(ActiveCombatUnits)
	unitGrid:clear()
	ProjectileSystem.clear()
end

function CombatService.init()
	lastUpdateTime = os.clock()
	CombatReplication.init()
	watchBuildingsFolder()
end

function CombatService.startLoop()
	if heartbeatConnection then
		return
	end
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastUpdateTime >= Engine.COMBAT_TICK_RATE then
			lastUpdateTime = now
			updateCombat(now)
		end
	end)

	CombatDebug:info("Combat v2 engine started", {
		tickRate = Engine.COMBAT_TICK_RATE,
		features = { "CounterMatrix", "Projectiles", "Abilities", "Siege", "SpatialGrid" },
	})
end

function CombatService.stopLoop()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

return CombatService
