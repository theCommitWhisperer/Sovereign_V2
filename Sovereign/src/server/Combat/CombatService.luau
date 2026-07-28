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
local GloryManager = nil :: any

local CombatDebug = DebugManager.createChannel("Combat", false)
local DamageDebug = DebugManager.createChannel("Damage", false)

type CombatUnit = CombatTypes.CombatUnit
type CombatBuilding = CombatTypes.CombatBuilding
type Stance = CombatTypes.Stance

local Engine = CombatConfig.Engine
local Positional = CombatConfig.Positional
local MoraleCfg = CombatConfig.Morale
local HeroCfg = CombatConfig.Hero

local CONFIG_DEFAULT_SPEED = 16 -- fallback march speed (studs/sec) if none known

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
	local rangeInStuds = metersToStuds(unitData.attack_range or 2)
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
	combatUnit.guardPost = nil
	combatUnit.retreatUntil = 0
	-- Hero fields: explicitly cleared rather than left absent. Callers hand us
	-- recycled/legacy-shaped tables (initializeCombatUnit, the AI spawn path,
	-- registerPlayerFighter), and a stale heroState pointer on a re-registered
	-- character would route an AI unit's incoming damage through the hero
	-- mitigation hook.
	combatUnit.killCreditAttackType = nil
	if combatUnit.playerControlled ~= true then
		combatUnit.playerControlled = nil
		combatUnit.heroState = nil
	end
	-- Migrate any legacy stance value to the new vocabulary
	if not CombatConfig.StanceBehavior[combatUnit.stance] then
		combatUnit.stance = CombatConfig.DefaultStance
	end

	ActiveCombatUnits[unitModel] = combatUnit :: CombatUnit
	unitModel:SetAttribute("Stance", combatUnit.stance) -- for client UI

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
	if not unitData then
		CombatDebug:warn("No unit data for unit type", { unitType = unitType })
		return
	end

	local playerData = PlayerManager.get(owner)
	local faction = (playerData and playerData.Faction) or "Kingdom"
	local startingMorale = MoraleManager.getMorale(unitModel) or 75

	local combatUnit = {
		model = unitModel,
		unitData = unitData,
		owner = owner.UserId,
		unitType = unitType,
		health = (unitModel:GetAttribute("CurrentHealth") :: number?) or unitData.max_health,
		maxHealth = unitData.max_health,
		attackDamage = unitData.attack_damage,
		attackSpeed = unitData.attack_speed,
		attackRange = getAttackRangeStuds(unitData),
		armor = unitData.armor,
		morale = startingMorale,
		stance = CombatConfig.DefaultStance,
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
	-- A unit that leaves combat mid-charge must not keep the charge gait, or a
	-- survivor would run everywhere for the rest of its life. Cleared here rather
	-- than in syncGait because syncGait no longer runs for an unregistered unit.
	if unitModel:GetAttribute(GameData.UnitAnimations.GAIT_ATTRIBUTE) == "charge" then
		unitModel:SetAttribute(GameData.UnitAnimations.GAIT_ATTRIBUTE, nil)
	end
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

-- ── FRIENDLY FIRE (AI-vs-AI sandbox aid) ───────────────────────────────────
--
-- OFF by default and deliberately not reachable from normal gameplay: it is
-- toggled only by the admin "/ff" chat command (TestCommandManager). It exists
-- so allied formations can be made to fight each other in the sandbox without
-- staging a real two-faction battle.
--
-- It NO LONGER gates the player's own attacks — see below.
local friendlyFire = false

function CombatService.setFriendlyFire(enabled: boolean)
	friendlyFire = enabled == true
end

function CombatService.getFriendlyFire(): boolean
	return friendlyFire
end

-- Targets for a player-aimed attack: EVERY living unit in the radius except the
-- attacker himself — enemies, allied troops, and his own peasants alike.
--
-- WHY THIS IS UNCONDITIONAL (and why it stopped reading `friendlyFire`):
-- the project owner's design decision is that the Lord's sword hits whatever it
-- swings through. The alternative — filtering the arc by faction — means a
-- peasant standing between the Lord and a Viking eats nothing while the Viking
-- behind him takes full damage, which reads as a broken hitbox every time. The
-- griefing tradeoff (a Lord can walk into his own army and cut it down, and the
-- server cannot tell intent from accident) is documented in full at
-- CombatConfig.Hero.playerAttacksHitAllies and is accepted.
--
-- This is data, not a hardcoded decision: flip
-- CombatConfig.Hero.playerAttacksHitAllies to false and player attacks fall
-- back to enemies-only (still honouring /ff, so the old test workflow survives).
--
-- Scope is unchanged in the important direction: this widens the PLAYER'S aimed
-- attacks ONLY. The autonomous combat loop still calls forEachEnemyInRadius, so
-- AI units never friendly-fire each other.
local function forEachPlayerTargetInRadius(unit: CombatUnit, radius: number, visitor: (CombatUnit) -> ())
	if not (HeroCfg.playerAttacksHitAllies or friendlyFire) then
		forEachEnemyInRadius(unit, radius, visitor)
		return
	end
	local pos = getPosition(unit.model)
	if not pos then
		return
	end
	unitGrid:query(pos, radius, function(model, _modelPos)
		if model ~= unit.model then
			local other = ActiveCombatUnits[model]
			if other and other.health > 0 then
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
		-- Match-stats counter (Victory/Defeat screen summary)
		if not AchievementManager then
			AchievementManager = require(Managers.AchievementManager) :: any
		end
		AchievementManager.incrementStat(ownerPlayer, "UnitsLost", 1)
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

			-- Glory: renown per kill, scaled by victim value. Melee earns full
			-- value, ranged half; the first-person Lord's melee kills double.
			if not GloryManager then
				GloryManager = require(Managers.GloryManager) :: any
			end
			GloryManager.awardForKill(killerPlayer, {
				victimType = victim.unitType,
				victimCost = victim.unitData and victim.unitData.cost or nil,
				victimMaxHealth = victim.maxHealth,
				-- killCreditAttackType lets a single unit score kills by the attack
				-- it ACTUALLY used rather than by its profile. The hero is seeded
				-- from a melee profile, so without this his bow kills would claim
				-- the 2.0x Lord-melee bonus instead of the 0.5x ranged rate.
				attackType = killer.killCreditAttackType or killer.attackType,
				killerIsLord = killer.playerControlled == true,
			})
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

-- ═══════════════════════════════════════════════════════════════════════════
-- INCOMING DAMAGE HOOK
-- ═══════════════════════════════════════════════════════════════════════════
-- HeroCombat installs a hook here so a blocking / parrying / dodging player can
-- actually mitigate damage. It lives on this side of the boundary to keep the
-- dependency acyclic: HeroCombat requires CombatService, never the reverse.
--
-- The hook receives the resolved damage and returns the damage to actually
-- apply — 0 means fully negated (a parry or an i-frame). It is only consulted
-- for `playerControlled` defenders: this function is the funnel for EVERY hit in
-- a battle of hundreds of units, so an unconditional call would put a function
-- call plus a table lookup on the hottest path in the combat engine for the
-- benefit of the one or two models that can ever block.
type IncomingDamageHook = (attacker: CombatUnit, defender: CombatUnit, damage: number) -> number

local incomingDamageHook: IncomingDamageHook? = nil

function CombatService.setIncomingDamageHook(hook: IncomingDamageHook?)
	incomingDamageHook = hook
end

--- Applies damage and returns the amount ACTUALLY applied — 0 when the incoming
--- damage hook negated it (parry / dodge i-frames). Callers use the return value
--- to decide whether a hit "landed"; before this returned anything, the hero
--- pipeline compared a nil against 0 and threw.
local function applyDamageToUnit(attacker: CombatUnit, defender: CombatUnit, damage: number): number
	if defender.playerControlled and incomingDamageHook then
		-- pcall'd: a bug in the hero mitigation logic must not be able to abort
		-- damage application engine-wide and leave units immortal.
		local ok, mitigated = pcall(incomingDamageHook, attacker, defender, damage)
		if ok and typeof(mitigated) == "number" then
			-- NaN is a `number` and would survive the typeof test. It also poisons
			-- everything downstream: `defender.health - nan` is nan, `nan <= 0` is
			-- false, so a single NaN would make a unit permanently unkillable with
			-- a health bar showing nothing. Relying on math.max(0, nan) to clamp is
			-- implementation detail, not a guarantee — reject it explicitly.
			if mitigated ~= mitigated then
				CombatDebug:warn("incoming damage hook returned NaN; treating as fully negated")
				return 0
			end
			damage = math.max(0, mitigated)
		elseif not ok then
			CombatDebug:warn("incoming damage hook errored", { err = mitigated })
		end
		-- Fully negated (parry / dodge i-frames). Return before touching health,
		-- morale or damageDealt so a parried blow leaves no trace in the stats.
		if damage <= 0 then
			return 0
		end
	end

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

	return damage
end

-- Extra knobs the hero pipeline needs on top of a normal attack resolution.
-- AI attacks pass nil and behave exactly as before.
export type HitOptions = {
	-- Scales the FINAL resolved damage (post counter-matrix, armor, stance,
	-- positional and morale). The hero's combo-step multiplier rides here rather
	-- than being folded into attackDamage, so DamageResolver stays pure and no
	-- math is duplicated.
	damageMult: number?,
	-- Overrides the attack type reported to GloryManager on a kill. See
	-- CombatUnit.killCreditAttackType.
	attackTypeCredit: CombatConfig.AttackType?,
	-- Overrides the DAMAGE type this one attack resolves as against the counter
	-- matrix. Needed because a single fighter can swing two different weapons: the
	-- hero is registered from a melee profile (Gallowglass / Slash) but can draw a
	-- bow, and a bow is Pierce. Without this his arrows took the Slash row —
	-- 0.85x vs Heavy armour where Pierce gets 1.15x, i.e. archery was worse than
	-- his own sword against exactly the targets a bow is meant to answer.
	-- Threaded down as DamageContext.damageTypeOverride rather than written onto
	-- attacker.profile, which is a shared CombatConfig table.
	damageTypeOverride: CombatConfig.DamageType?,
}

-- Resolve one attack instance (melee hit or projectile impact).
-- Returns the damage that landed (0 if the hit was negated), so the hero
-- pipeline can decide whether to fire a hit-confirm beat.
local function resolveHit(attacker: CombatUnit, defender: CombatUnit, now: number, opts: HitOptions?): number
	if defender.health <= 0 or ActiveCombatUnits[defender.model] == nil then
		return 0
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
		damageTypeOverride = opts and opts.damageTypeOverride or nil,
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
			-- The charger died on the brace. No damage of his own ever landed, so
			-- report 0 rather than falling out with a bare `return` (which yielded
			-- nil and crashed every caller that reads the landed damage).
			return 0
		end
	end

	local onHitFx = AbilitySystem.onHit(attacker, defender, now)
	if onHitFx.stunTarget then
		defender.stunnedUntil = now + (onHitFx.stunTarget :: number)
	end

	-- Apply the caller's multiplier LAST, on top of the fully resolved number, so
	-- the hero's combo-step scaling rides over the counter matrix, armor, stance,
	-- positional and morale maths instead of duplicating any of it. AI attacks
	-- pass no opts and are completely unaffected.
	local finalDamage = breakdown.final
	local damageMult = opts and opts.damageMult
	if damageMult and damageMult ~= 1 then
		finalDamage = math.max(1, math.floor(finalDamage * damageMult))
	end

	-- Kill credit for Glory. The hero is seeded from a melee profile, so without
	-- this override a bow kill would score as a Lord MELEE kill and pay the 2.0x
	-- hero bonus instead of the 0.5x ranged rate. Set immediately before the
	-- damage lands (handleUnitDeath reads it synchronously) and always restored
	-- after, so it can never leak onto this attacker's next, unrelated swing.
	local previousCredit = attacker.killCreditAttackType
	attacker.killCreditAttackType = opts and opts.attackTypeCredit or nil

	local dealt = applyDamageToUnit(attacker, defender, finalDamage)

	attacker.killCreditAttackType = previousCredit

	DamageDebug:info("Attack", {
		attacker = attacker.unitType,
		defender = defender.unitType,
		damage = dealt,
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

	-- The damage this hit actually landed (0 if a parry / i-frame ate it). The
	-- hero pipeline reads this to decide whether to fire a hit-confirm beat;
	-- returning nothing here is what threw "attempt to compare nil with number".
	return dealt
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
	-- Player-controlled fighters (first-person "fight alongside your men") are
	-- driven by the player, never by the combat AI. They stay registered so enemies
	-- target them and allies count them as friendly, and the tick loop keeps their
	-- grid cell fresh — but we run no movement/targeting/abilities for them. Health
	-- is mirrored from the Humanoid so heals/regen and enemy hits stay consistent.
	if unit.playerControlled then
		local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			unit.health = humanoid.Health
			unit.maxHealth = humanoid.MaxHealth
		end
		return
	end

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

	-- Stance behaviour drives targeting, chasing, charging and kiting
	local behavior = CombatConfig.StanceBehavior[unit.stance] or CombatConfig.StanceBehavior.Attack

	local unitPos = getPosition(unitModel)
	if not unitPos then
		return
	end

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
		-- Defend: abandon targets dragged beyond the guard-post leash
		if valid and unit.stance == "Defend" and unit.guardPost then
			local tp = getPosition(targetModel) or (targetBuilding and targetModel:GetPivot().Position)
			if tp and (tp - unit.guardPost).Magnitude > behavior.leash then
				valid = false
			end
		end
		if not valid then
			unit.targetModel = nil
			targetModel = nil
		end
	end

	-- ── Acquire a new target (LOD-throttled, desynced per unit) ──────────
	if not targetModel and behavior.autoEngage then
		if now - unit.lastScanTime >= Engine.IDLE_SCAN_RATE + unit.scanJitter then
			unit.lastScanTime = now
			local searchRange = Engine.SEARCH_RANGE * math.max(behavior.searchMult, 1)
			local candidate = findBestEnemyTarget(unit, searchRange)

			-- Defend: ignore enemies outside the guard-post leash
			if candidate and unit.stance == "Defend" and unit.guardPost then
				local cp = getPosition(candidate)
				if cp and (cp - unit.guardPost).Magnitude > behavior.leash then
					candidate = nil
				end
			end

			-- No enemy units around: only Attack stance sieges buildings
			if not candidate and unit.stance == "Attack" then
				candidate = findNearestEnemyBuilding(unit, Engine.BUILDING_SEARCH_RANGE)
			end
			targetModel = candidate
			unit.targetModel = targetModel
		end
	end

	if not targetModel then
		-- Defend: drift back to the guard post if we've wandered off it
		if unit.stance == "Defend" and unit.guardPost then
			local flatBack = Vector3.new(unit.guardPost.X - unitPos.X, 0, unit.guardPost.Z - unitPos.Z)
			if flatBack.Magnitude > 5 then
				unitModel:SetAttribute("TargetPosition", unit.guardPost)
				unitModel:SetAttribute("IsMoving", true)
				unit.isCharging = false
				return
			end
		end

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

	-- ── Skirmish kiting: back off, don't stand and trade ─────────────────
	if behavior.kite and targetUnit then
		local tooClose
		if unit.attackType == "Ranged" then
			tooClose = distance < unit.attackRange * CombatConfig.Skirmish.RANGED_KEEP_DISTANCE
		else
			tooClose = now < unit.retreatUntil -- melee hit-and-run window
		end
		if tooClose then
			local away = Vector3.new(unitPos.X - targetPos.X, 0, unitPos.Z - targetPos.Z)
			away = if away.Magnitude > 0.1
				then away.Unit
				else Vector3.new(math.cos(unit.slotAngle), 0, math.sin(unit.slotAngle))
			unitModel:SetAttribute("TargetPosition", unitPos + away * CombatConfig.Skirmish.RETREAT_DISTANCE)
			unitModel:SetAttribute("IsMoving", true)
			unit.isCharging = false
			-- Ranged skirmishers still loose a shot while backpedalling
			if unit.attackType == "Ranged" and now - unit.lastAttackTime >= unit.attackSpeed then
				unit.lastAttackTime = now
				faceTarget(unitModel, targetPos)
				executeAttackOnUnit(unit, targetUnit, now)
			end
			return
		end
	end

	if distance <= effectiveRange then
		unitModel:SetAttribute("IsMoving", false)
		unitModel:SetAttribute("TargetPosition", nil)
		unit.isCharging = false

		if now - unit.lastAttackTime >= unit.attackSpeed then
			unit.lastAttackTime = now
			-- Face the target once per attack. Writing the root CFrame every
			-- tick fought humanoid physics and made units jitter/hover.
			faceTarget(unitModel, targetPos)
			if targetUnit then
				executeAttackOnUnit(unit, targetUnit, now)
				-- Melee skirmishers hit then peel away
				if behavior.kite and unit.attackType == "Melee" then
					unit.retreatUntil = now + CombatConfig.Skirmish.MELEE_RETREAT_TIME
				end
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
			local searchRange = Engine.SEARCH_RANGE * math.max(behavior.searchMult, 1)
			local best, bestScore = findBestEnemyTarget(unit, searchRange)
			if best and best ~= targetModel then
				local currentScore = scoreEnemy(unit, targetUnit, distance)
				if bestScore < currentScore - Targeting.RETARGET_MARGIN then
					unit.targetModel = best
					return -- engage the new target next tick
				end
			end
		end

		-- Combat movement supersedes any stale formation-move state
		if unitModel:GetAttribute("FormationFacing") ~= nil then
			unitModel:SetAttribute("FormationFacing", nil)
		end
		if unitModel:GetAttribute("ArrivalDistance") ~= nil then
			unitModel:SetAttribute("ArrivalDistance", nil)
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

		unit.isCharging = behavior.canCharge
			and distance <= Positional.CHARGE_DISTANCE
			and distance > effectiveRange
	end
end

-- Publish `isCharging` to the client as the `Gait` attribute, which is what
-- makes UnitAnimator play the run cycle instead of the walk.
--
-- `isCharging` is assigned in a dozen places across this file, so rather than
-- stamping the attribute at every one of them (and inevitably missing one) this
-- reconciles once per unit per tick from the authoritative field.
--
-- It writes ONLY on a transition, so a charging unit costs two attribute
-- replications for the whole charge rather than one per frame.
--
-- It also clears only the reason it owns. A peasant hurrying back to the Keep
-- carries Gait = "hurry", set by a completely different system; if this cleared
-- unconditionally it would cancel that the moment the peasant registered with
-- the combat system. See the Gait contract in UnitAnimationsData.
local GAIT_ATTRIBUTE = GameData.UnitAnimations.GAIT_ATTRIBUTE
local GAIT_CHARGE = "charge"

local function syncGait(unitModel: Model, unit: CombatUnit)
	local current = unitModel:GetAttribute(GAIT_ATTRIBUTE)
	if unit.isCharging then
		if current ~= GAIT_CHARGE then
			unitModel:SetAttribute(GAIT_ATTRIBUTE, GAIT_CHARGE)
		end
	elseif current == GAIT_CHARGE then
		unitModel:SetAttribute(GAIT_ATTRIBUTE, nil)
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
		syncGait(unitModel, unit)
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
	attacker.stance = "Attack" -- a manual attack order is aggressive intent
	attacker.guardPost = nil
	attackerModel:SetAttribute("Stance", "Attack")
	attackerModel:SetAttribute("Marching", nil)
	attackerModel:SetAttribute("IsMoving", false)
	attackerModel:SetAttribute("TargetPosition", nil)
end

-- Restore a unit's individual walk speed after a group march
local function restoreMarchSpeed(unitModel: Model)
	if unitModel:GetAttribute("Marching") then
		local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
		local base = unitModel:GetAttribute("BaseWalkSpeed") :: number?
		if humanoid and base then
			humanoid.WalkSpeed = base
		end
		unitModel:SetAttribute("Marching", nil)
	end
end

function CombatService.setStance(unitModel: Model, stance: Stance)
	local unit = ActiveCombatUnits[unitModel]
	if not unit then
		CombatDebug:warn("Unit not in combat system for stance change")
		return
	end
	if not CombatConfig.StanceBehavior[stance] then
		CombatDebug:warn("Unknown stance", { stance = stance })
		return
	end
	unit.stance = stance
	unitModel:SetAttribute("Stance", stance)

	if stance == "March" then
		-- Passive: stop fighting, hold no post
		unit.targetModel = nil
		unit.guardPost = nil
		unit.isCharging = false
	elseif stance == "Defend" then
		-- Hold the current position as the guard post
		unit.guardPost = getPosition(unitModel)
		restoreMarchSpeed(unitModel)
	else
		-- Attack / Skirmish: mobile combat, no fixed post
		unit.guardPost = nil
		restoreMarchSpeed(unitModel)
	end
end

-- Order a group to march to a shared destination: passive stance, everyone
-- capped to the slowest member's speed so the formation travels as one body.
-- (Movement itself is issued separately, e.g. via MovementSystem.moveGroup or
-- the formation move handler.)
function CombatService.applyGroupMarch(units: { Model })
	local minSpeed = math.huge
	for _, u in units do
		if u and u.Parent then
			local base = u:GetAttribute("BaseWalkSpeed") :: number?
			if not base then
				local h = u:FindFirstChildOfClass("Humanoid")
				base = h and h.WalkSpeed or CONFIG_DEFAULT_SPEED
			end
			if base < minSpeed then
				minSpeed = base
			end
		end
	end
	if minSpeed == math.huge then
		minSpeed = CONFIG_DEFAULT_SPEED
	end

	for _, u in units do
		if u and u.Parent then
			local combatUnit = ActiveCombatUnits[u]
			if combatUnit then
				combatUnit.stance = "March"
				combatUnit.targetModel = nil
				combatUnit.guardPost = nil
				combatUnit.isCharging = false
				u:SetAttribute("Stance", "March")
			end
			local humanoid = u:FindFirstChildOfClass("Humanoid")
			if humanoid then
				if not u:GetAttribute("BaseWalkSpeed") then
					u:SetAttribute("BaseWalkSpeed", humanoid.WalkSpeed)
				end
				humanoid.WalkSpeed = minSpeed
			end
			u:SetAttribute("Marching", true)
		end
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

-- ═══════════════════════════════════════════════════════════════════════════
-- PLAYER FIGHTER (first-person "fight alongside your men")
-- ═══════════════════════════════════════════════════════════════════════════

-- Register a player's CHARACTER as a combat unit on `faction`. Enemies target and
-- damage it via the normal combat loop, allies treat it as friendly, but the AI
-- never drives it — the player does. `opts` may override maxHealth / attackDamage /
-- armor / baseType (baseType only seeds the combat profile used for damage-type
-- interactions; the stats below are what actually apply).
function CombatService.registerPlayerFighter(character: Model, faction: string, ownerId: number, opts: any?)
	opts = opts or {}
	-- Defaults come from CombatConfig.Hero.fighter so the Lord (GameManager) and
	-- the arena hero (ArenaMode) cannot drift apart by editing one call site.
	local fighterCfg = HeroCfg.fighter
	local baseType = opts.baseType or fighterCfg.baseType
	local unitData = GameData.Units[baseType] or GameData.Units.Peasant
	local maxHealth = opts.maxHealth or fighterCfg.maxHealth

	local combatUnit = {
		model = character,
		unitData = unitData,
		owner = ownerId,
		unitType = baseType,
		health = maxHealth,
		maxHealth = maxHealth,
		attackDamage = opts.attackDamage or fighterCfg.attackDamage,
		attackSpeed = (unitData and unitData.attack_speed) or 1,
		-- Reach used by ENEMIES deciding whether they can hit him, not by his own
		-- swings (those carry their own per-combo-step range).
		attackRange = Engine.MELEE_RANGE,
		armor = opts.armor or fighterCfg.armor,
		morale = 100,
		stance = CombatConfig.DefaultStance,
		targetModel = nil,
		formation = nil,
		lastAttackTime = 0,
		isCharging = false,
		faction = faction,
		playerControlled = true,
	}

	character:SetAttribute("OwnerId", ownerId)
	character:SetAttribute("Faction", faction)
	character:SetAttribute("PlayerFighter", true)
	CombatService.registerCombatUnit(character, combatUnit)
end

function CombatService.unregisterPlayerFighter(character: Model)
	if ActiveCombatUnits[character] then
		unregisterUnit(character)
	end
end

-- Look up a registered player fighter. HeroCombat uses this to confirm the
-- character is actually in the combat roster before accepting any action.
function CombatService.getPlayerFighter(character: Model): CombatUnit?
	local unit = ActiveCombatUnits[character]
	if unit and unit.playerControlled then
		return unit
	end
	return nil
end

-- Attach/detach the hero state machine's table to the registered fighter so the
-- damage funnel can reach it without a Players lookup per hit.
function CombatService.setHeroState(character: Model, state: CombatTypes.HeroState?)
	local unit = ActiveCombatUnits[character]
	if unit then
		unit.heroState = state
	end
end

-- Stun any unit (used by the hero's parry riposte). `stunnedUntil` is the
-- existing mechanism — see Abilities.ShieldBash.
function CombatService.stunUnit(unitModel: Model, seconds: number)
	local unit = ActiveCombatUnits[unitModel]
	if unit and unit.health > 0 and seconds > 0 then
		unit.stunnedUntil = math.max(unit.stunnedUntil, os.clock() + seconds)
		unit.isCharging = false -- a stunned unit is not mid-charge any more
	end
end

-- ── HERO ATTACK PIPELINE ────────────────────────────────────────────────────

export type ComboAttackResult = {
	hits: number,
	damage: number, -- total damage dealt across every unit caught in the arc
	firstHitPosition: Vector3?, -- where to put the hit-confirm flash
	killedAny: boolean,
}

-- Is `targetPos` inside the flat forward cone of half-angle acos(arcCos) around
-- `flatAim`, measured from `origin`?
--
-- BUGFIX: the old inline version read
--     if to.Magnitude < 1e-3 or to.Unit:Dot(flatAim) >= arcCos then hit()
-- so a target at (near) zero horizontal distance short-circuited the OR and was
-- counted as a HIT regardless of where the player was aiming — swinging directly
-- away from a unit standing on top of you still killed it. Degenerate geometry
-- has to be resolved deliberately, not by falling out of a short-circuit:
-- something occupying your own space is inside every arc, so it is a hit, but we
-- say so explicitly instead of leaking it through the aim test.
local function isInsideArc(origin: Vector3, targetPos: Vector3, flatAim: Vector3, arcCos: number): boolean
	local to = Vector3.new(targetPos.X - origin.X, 0, targetPos.Z - origin.Z)
	local distance = to.Magnitude
	if distance < 1e-3 then
		-- Overlapping the attacker: no meaningful direction exists. Treat it as a
		-- hit (you cannot miss something you are standing inside) but never as an
		-- automatic pass of the aim test.
		return true
	end
	return to.Unit:Dot(flatAim) >= arcCos
end

-- Normalize a client-supplied aim vector to a flat unit vector, or nil if the
-- vector is unusable. Callers must treat nil as "reject the request".
local function flattenAim(aimDir: Vector3): Vector3?
	-- NaN check: NaN ~= NaN. A hostile client can send Vector3.new(0/0, 0/0, 0/0)
	-- and every comparison below would silently pass.
	if aimDir.X ~= aimDir.X or aimDir.Y ~= aimDir.Y or aimDir.Z ~= aimDir.Z then
		return nil
	end
	local flat = Vector3.new(aimDir.X, 0, aimDir.Z)
	local magnitude = flat.Magnitude
	if magnitude < 1e-3 or magnitude > 1e6 then
		return nil
	end
	return flat / magnitude
end

CombatService.flattenAim = flattenAim

-- The hero's melee sweep, through the REAL damage pipeline.
--
-- Previously playerMeleeAttack called applyDamageToUnit with a flat number,
-- which meant the Lord's sword ignored the counter matrix, armor class,
-- flank/rear positional bonuses and morale entirely — the one attack in the game
-- that bypassed every combat rule was the player's own. This routes through
-- resolveHit with the combo step's multiplier folded in as HitOptions.damageMult,
-- so a hero swing is resolved by exactly the same code as a Gallowglass swing,
-- and emits the swing replication event that was also missing.
function CombatService.playerComboAttack(
	character: Model,
	aimDir: Vector3,
	range: number,
	arcCos: number,
	damageMult: number,
	comboStep: number,
	kind: string
): ComboAttackResult
	local result: ComboAttackResult = { hits = 0, damage = 0, firstHitPosition = nil, killedAny = false }

	local unit = ActiveCombatUnits[character]
	if not unit or not unit.playerControlled then
		return result
	end
	local origin = getPosition(character)
	if not origin then
		return result
	end
	local flatAim = flattenAim(aimDir)
	if not flatAim then
		return result
	end

	-- Tell every client to animate the swing on this character. Fired before the
	-- sweep so the visual arrives even if the sweep hits nothing.
	CombatReplication.heroSwing(character, comboStep, kind)

	local now = os.clock()
	-- Collect first, resolve second. resolveHit can kill a unit, and
	-- handleUnitDeath calls unregisterUnit -> unitGrid:remove, which mutates the
	-- structure forEachPlayerTargetInRadius is iterating. Buffering the arc keeps
	-- the sweep off a container being modified underneath it.
	local caught: { CombatUnit } = {}
	forEachPlayerTargetInRadius(unit, range, function(target)
		if target.health <= 0 then
			return
		end
		local targetPos = getPosition(target.model)
		if not targetPos then
			return
		end
		if isInsideArc(origin, targetPos, flatAim :: Vector3, arcCos) then
			table.insert(caught, target)
		end
	end)

	for _, target in caught do
		-- Re-check liveness: an earlier target in this same sweep may have been a
		-- cleave that already killed this one (Volley/extraShots can chain).
		if target.health > 0 and ActiveCombatUnits[target.model] then
			local hitPos = getPosition(target.model)
			local dealt = resolveHit(unit, target, now, { damageMult = damageMult, attackTypeCredit = "Melee" })
			if dealt > 0 then
				result.hits += 1
				result.damage += dealt
				if not result.firstHitPosition then
					result.firstHitPosition = hitPos
				end
				if target.health <= 0 then
					result.killedAny = true
				end
			end
		end
	end

	return result
end

-- The hero's bow shot, through the real pipeline. Picks the best-aimed target in
-- the cone and fires a real projectile; damage resolves on impact.
--
-- The arrow used to resolve with the hero's PROFILE damage type — Slash, because
-- the fighter is seeded from a Gallowglass — so a bow shot was scored as a sword
-- cut against armour (0.85x into Heavy where Pierce gets 1.15x). It now carries
-- HitOptions.damageTypeOverride = CombatConfig.Hero.ranged.damageType. The
-- override is per-attack on purpose: attacker.profile is a table SHARED by every
-- unit of that type, so writing the bow's type onto it would turn every
-- Gallowglass on the map into a spearman for the arrow's flight time.
-- Kill CREDIT is separate and already correct — attackTypeCredit = "Ranged" — so
-- Glory scores bow kills at 0.5x, not the Lord's 2.0x melee rate.
function CombatService.playerBowShot(
	character: Model,
	aimDir: Vector3,
	maxRange: number,
	arcCos: number,
	damageMult: number,
	projectileKey: string
): boolean
	local unit = ActiveCombatUnits[character]
	if not unit or not unit.playerControlled then
		return false
	end
	local origin = getPosition(character)
	if not origin then
		return false
	end
	local flatAim = flattenAim(aimDir)
	if not flatAim then
		return false
	end

	local best: CombatUnit? = nil
	local bestScore = -math.huge
	forEachPlayerTargetInRadius(unit, maxRange, function(target)
		if target.health <= 0 then
			return
		end
		local targetPos = getPosition(target.model)
		if not targetPos then
			return
		end
		local to = Vector3.new(targetPos.X - origin.X, 0, targetPos.Z - origin.Z)
		local dist = to.Magnitude
		if dist < 1e-3 then
			return
		end
		local aligned = to.Unit:Dot(flatAim :: Vector3)
		if aligned >= arcCos then
			local score = aligned - dist * 0.001 -- prefer well-aimed, then nearest
			if score > bestScore then
				bestScore = score
				best = target
			end
		end
	end)

	-- Release the bow animation regardless of whether anything was in the cone:
	-- the player pressed the button, he should see the draw and release.
	CombatReplication.heroSwing(character, -1, "ranged")

	if not best then
		return false
	end
	local target = (best :: CombatUnit)
	local fromPos = origin + Vector3.new(0, 2, 0)
	local moving = target.model:GetAttribute("IsMoving") == true
	ProjectileSystem.fire(projectileKey, fromPos, target.model, moving, function(hitModel)
		local hitUnit = ActiveCombatUnits[hitModel]
		-- The hero may have died, been unregistered (left hero mode) or the target
		-- may already be dead during the arrow's flight time — all normal.
		if hitUnit and hitUnit.health > 0 and unit.health > 0 and ActiveCombatUnits[character] then
			resolveHit(unit, hitUnit, os.clock(), {
				damageMult = damageMult,
				attackTypeCredit = "Ranged",
				damageTypeOverride = HeroCfg.ranged.damageType,
			})
		end
	end)
	return true
end

-- ── LEGACY ALIASES ──────────────────────────────────────────────────────────
--
-- Kept so anything still calling the pre-combo API keeps working (saved Studio
-- test scripts, the old "PlayerMeleeAttack"/"PlayerRangedAttack" remote actions).
-- They now go through the real pipeline too, converting their flat `damage`
-- argument into the equivalent multiplier against the fighter's attackDamage —
-- the numbers move slightly, and that is the point: they were bypassing armor.

function CombatService.playerMeleeAttack(character: Model, aimDir: Vector3, range: number, arcCos: number, damage: number): number
	local unit = ActiveCombatUnits[character]
	if not unit then
		return 0
	end
	local mult = if unit.attackDamage > 0 then damage / unit.attackDamage else 1
	return CombatService.playerComboAttack(character, aimDir, range, arcCos, mult, 1, "light").hits
end

function CombatService.playerRangedAttack(character: Model, aimDir: Vector3, maxRange: number, arcCos: number, damage: number, projectileKey: string): boolean
	local unit = ActiveCombatUnits[character]
	if not unit then
		return false
	end
	local mult = if unit.attackDamage > 0 then damage / unit.attackDamage else 1
	return CombatService.playerBowShot(character, aimDir, maxRange, arcCos, mult, projectileKey)
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
