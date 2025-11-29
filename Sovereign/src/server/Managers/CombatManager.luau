--!strict
-- CombatManager: Advanced Irish-themed combat system
-- Features: Celtic Fury, Shield Walls, War Cries, Formations, Morale-based combat
-- Designed for Sovereign - An Irish RTS Game

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MoraleManager = require(script.Parent.MoraleManager)
local FactionManager = require(script.Parent.FactionManager)
local RevoltManager = require(script.Parent.RevoltManager)

-- Lazy-load to avoid circular dependencies
local AchievementManager = nil
local QuestManager = nil

local CombatDebug = DebugManager.createChannel("Combat", false)
local DamageDebug = DebugManager.createChannel("Damage", false)

local CombatManager = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════════════════

local COMBAT_TICK_RATE = 0.1 -- Update 10 times per second for responsive combat
local MELEE_RANGE = 8 -- studs (approx 2.6m)
local RANGED_MULTIPLIER = 3 -- Ranged units get 3x their range in studs
local SEARCH_RANGE = 60 -- How far units look for enemies (studs)

-- Combat bonuses
local CHARGE_DISTANCE = 30
local CHARGE_DAMAGE_BONUS = 1.5
local FLANKING_DAMAGE_BONUS = 1.4
local HIGH_GROUND_BONUS = 1.25
local REAR_ATTACK_BONUS = 1.6

-- Irish faction special abilities
local CELTIC_FURY_THRESHOLD = 80 -- morale threshold
local CELTIC_FURY_DAMAGE = 1.2
local CELTIC_FURY_SPEED = 1.3
local IRISH_CHARGE_BONUS = 1.3 -- Better than normal charge
local WAR_CRY_MORALE_BOOST = 15
local WAR_CRY_RADIUS = 25
local SHIELD_WALL_DAMAGE_REDUCTION = 0.4
local SHIELD_WALL_FORMATION_BONUS = 0.3

-- Stance modifiers
local STANCE_MODIFIERS = {
	Aggressive = { damage = 1.25, defense = 0.85 },
	Defensive = { damage = 0.75, defense = 1.4 },
	Hold = { damage = 1.0, defense = 1.2 },
	Charge = { damage = 1.5, defense = 0.7 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════════════

export type Stance = "Aggressive" | "Defensive" | "Hold" | "Charge"

export type CombatUnit = {
	model: Model,
	unitData: GameData.UnitData,
	owner: number,
	unitType: string,
	health: number,
	maxHealth: number,
	attackDamage: number,
	attackSpeed: number,
	attackRange: number,
	armor: number,
	morale: number,
	stance: Stance,
	targetModel: Model?,
	formation: string?,
	lastAttackTime: number,
	isCharging: boolean,
	faction: string,
	-- Irish special abilities
	celticFuryActive: boolean,
	lastWarCryTime: number,
	inShieldWall: boolean,
	shieldWallAllies: { Model },
}

local ActiveCombatUnits: { [Model]: CombatUnit } = {}
local lastUpdateTime = 0

-- ═══════════════════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

-- Convert meters to studs (Roblox uses studs, game data uses meters)
local function metersToStuds(meters: number): number
	return meters * 3
end

-- Get attack range in studs based on unit type
local function getAttackRangeStuds(unitData: GameData.UnitData): number
	if not unitData.combat then
		return MELEE_RANGE
	end

	local baseRange = unitData.combat.attack_range or 2
	local rangeInStuds = metersToStuds(baseRange)

	-- Ranged units get bonus range
	if unitData.subtype == "Ranged" or unitData.subtype == "Ranged Infantry" then
		rangeInStuds = rangeInStuds * 1.5
	end

	return rangeInStuds
end

-- Check if unit is Irish faction
local function isIrish(unit: CombatUnit): boolean
	return unit.faction == "Irish" or unit.faction == "Kingdom"
end

-- Check if two units are enemies
local function areEnemies(unit1: CombatUnit, unit2: CombatUnit): boolean
	return FactionManager.areEnemies(unit1.faction, unit2.faction)
end

-- Calculate distance between two models
local function getDistance(model1: Model, model2: Model): number?
	if not model1.PrimaryPart or not model2.PrimaryPart then
		return nil
	end
	return (model1.PrimaryPart.Position - model2.PrimaryPart.Position).Magnitude
end

-- ═══════════════════════════════════════════════════════════════════════════
-- VISUAL EFFECTS
-- ═══════════════════════════════════════════════════════════════════════════

local function createHitEffect(position: Vector3, damageAmount: number)
	local hitEffect = Instance.new("Part")
	hitEffect.Size = Vector3.new(0.5, 0.5, 0.5)
	hitEffect.Position = position
	hitEffect.Anchored = true
	hitEffect.CanCollide = false
	hitEffect.Color = Color3.fromRGB(255, 100, 100)
	hitEffect.Material = Enum.Material.Neon
	hitEffect.Transparency = 0.3
	hitEffect.Parent = Workspace

	-- Tween fade out
	local tween = TweenService:Create(hitEffect, TweenInfo.new(0.3), {
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
	})
	tween:Play()

	task.delay(0.3, function()
		hitEffect:Destroy()
	end)
end

local function createCelticFuryEffect(model: Model)
	if not model.PrimaryPart then
		return
	end

	-- Create glowing aura
	local aura = Instance.new("Part")
	aura.Size = Vector3.new(6, 8, 6)
	aura.CFrame = model.PrimaryPart.CFrame
	aura.Anchored = true
	aura.CanCollide = false
	aura.Color = Color3.fromRGB(0, 255, 100)
	aura.Material = Enum.Material.Neon
	aura.Transparency = 0.7
	aura.Shape = Enum.PartType.Cylinder
	aura.Parent = Workspace

	-- Rotate aura
	local rotateConnection
	rotateConnection = RunService.Heartbeat:Connect(function(dt)
		if aura and aura.Parent then
			aura.CFrame = aura.CFrame * CFrame.Angles(0, dt * 2, 0)
		else
			rotateConnection:Disconnect()
		end
	end)

	task.delay(2, function()
		if rotateConnection then
			rotateConnection:Disconnect()
		end
		if aura and aura.Parent then
			aura:Destroy()
		end
	end)
end

local function createWarCryEffect(position: Vector3, radius: number)
	local wave = Instance.new("Part")
	wave.Size = Vector3.new(1, 0.5, 1)
	wave.Position = position
	wave.Anchored = true
	wave.CanCollide = false
	wave.Color = Color3.fromRGB(255, 200, 0)
	wave.Material = Enum.Material.Neon
	wave.Transparency = 0.5
	wave.Shape = Enum.PartType.Cylinder
	wave.Orientation = Vector3.new(0, 0, 90)
	wave.Parent = Workspace

	-- Expand wave
	local tween = TweenService:Create(wave, TweenInfo.new(0.5), {
		Size = Vector3.new(radius * 2, 0.5, radius * 2),
		Transparency = 1,
	})
	tween:Play()

	task.delay(0.5, function()
		wave:Destroy()
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COMBAT UNIT REGISTRATION
-- ═══════════════════════════════════════════════════════════════════════════

function CombatManager.registerCombatUnit(unitModel: Model, combatUnit: CombatUnit)
	-- Add Irish special ability fields if not present
	if combatUnit.celticFuryActive == nil then
		combatUnit.celticFuryActive = false
		combatUnit.lastWarCryTime = 0
		combatUnit.inShieldWall = false
		combatUnit.shieldWallAllies = {}
	end

	ActiveCombatUnits[unitModel] = combatUnit

	-- Set up health display
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = combatUnit.maxHealth
		humanoid.Health = combatUnit.health
	end

	CombatDebug:info("Registered combat unit", {
		unitType = combatUnit.unitType,
		owner = combatUnit.owner,
		faction = combatUnit.faction,
		attackRange = combatUnit.attackRange,
	})
end

function CombatManager.initializeCombatUnit(unitModel: Model, owner: Player)
	local unitType = unitModel:GetAttribute("UnitType")

	CombatDebug:info("Initializing combat unit", {
		modelName = unitModel.Name,
		unitType = unitType,
		hasUnitType = unitType ~= nil,
	})

	local unitData = GameData.Units[unitType]

	if not unitData then
		CombatDebug:warn("No unit data for type", { unitType = unitType })
		return
	end

	if not unitData.combat then
		CombatDebug:warn("No combat data for unit type", { unitType = unitType })
		return
	end

	local playerData = PlayerManager.get(owner)
	local faction = playerData and playerData.Faction or "Kingdom"
	local startingMorale = MoraleManager.getMorale(unitModel) or 75

	local combatUnit: CombatUnit = {
		model = unitModel,
		unitData = unitData,
		owner = owner.UserId,
		unitType = unitType,
		health = unitModel:GetAttribute("CurrentHealth") or unitData.health.max_health,
		maxHealth = unitData.health.max_health,
		attackDamage = unitData.combat.attack_damage,
		attackSpeed = unitData.combat.attack_speed,
		attackRange = getAttackRangeStuds(unitData),
		armor = unitData.combat.armor,
		morale = startingMorale,
		stance = "Aggressive",
		targetModel = nil,
		formation = nil,
		lastAttackTime = 0,
		isCharging = false,
		faction = faction,
		-- Irish abilities
		celticFuryActive = false,
		lastWarCryTime = 0,
		inShieldWall = false,
		shieldWallAllies = {},
	}

	CombatManager.registerCombatUnit(unitModel, combatUnit)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TARGET ACQUISITION
-- ═══════════════════════════════════════════════════════════════════════════

local function findNearestEnemy(unit: CombatUnit, maxRange: number): Model?
	if not unit.model.PrimaryPart then
		return nil
	end

	local unitPos = unit.model.PrimaryPart.Position
	local nearestEnemy: Model? = nil
	local nearestDistance = maxRange

	for enemyModel, enemyUnit in ActiveCombatUnits do
		-- Skip if not an enemy or dead
		if not areEnemies(unit, enemyUnit) or enemyUnit.health <= 0 then
			continue
		end

		-- Skip if no valid position
		if not enemyModel.PrimaryPart then
			continue
		end

		local distance = (enemyModel.PrimaryPart.Position - unitPos).Magnitude

		if distance < nearestDistance then
			nearestEnemy = enemyModel
			nearestDistance = distance
		end
	end

	-- Only log for King units to avoid spam
	if unit.unitType == "King" then
		CombatDebug:info("Target search", {
			unit = unit.unitType,
			foundTarget = nearestEnemy ~= nil,
			distance = nearestDistance,
			maxRange = maxRange,
		})
	end

	return nearestEnemy
end

-- ═══════════════════════════════════════════════════════════════════════════
-- IRISH SPECIAL ABILITIES
-- ═══════════════════════════════════════════════════════════════════════════

-- Celtic Fury: High morale Irish units deal bonus damage and move faster
local function updateCelticFury(unit: CombatUnit)
	if not isIrish(unit) then
		return
	end

	local shouldBeActive = unit.morale >= CELTIC_FURY_THRESHOLD

	-- Activate Celtic Fury
	if shouldBeActive and not unit.celticFuryActive then
		unit.celticFuryActive = true
		createCelticFuryEffect(unit.model)
		CombatDebug:info("Celtic Fury activated!", { unit = unit.unitType })

		-- Speed boost
		local humanoid = unit.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = humanoid.WalkSpeed * CELTIC_FURY_SPEED
		end
	-- Deactivate Celtic Fury
	elseif not shouldBeActive and unit.celticFuryActive then
		unit.celticFuryActive = false
		CombatDebug:info("Celtic Fury faded", { unit = unit.unitType })

		-- Remove speed boost
		local humanoid = unit.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = humanoid.WalkSpeed / CELTIC_FURY_SPEED
		end
	end
end

-- War Cry: Irish units can rally nearby allies, boosting morale
local function tryWarCry(unit: CombatUnit, currentTime: number)
	if not isIrish(unit) then
		return
	end

	-- Can only war cry every 30 seconds
	if currentTime - unit.lastWarCryTime < 30 then
		return
	end

	-- Only war cry if morale is good and in combat
	if unit.morale < 60 or not unit.targetModel then
		return
	end

	unit.lastWarCryTime = currentTime

	if not unit.model.PrimaryPart then
		return
	end

	local position = unit.model.PrimaryPart.Position
	createWarCryEffect(position, WAR_CRY_RADIUS)

	-- Boost morale of nearby allies
	local boostedCount = 0
	for allyModel, allyUnit in ActiveCombatUnits do
		if allyUnit.owner == unit.owner and allyModel ~= unit.model then
			local distance = getDistance(unit.model, allyModel)
			if distance and distance <= WAR_CRY_RADIUS then
				MoraleManager.modifyMorale(allyModel, WAR_CRY_MORALE_BOOST, "War Cry")
				boostedCount += 1
			end
		end
	end

	CombatDebug:info("War Cry!", {
		unit = unit.unitType,
		alliesBoosted = boostedCount,
	})
end

-- Shield Wall: Defensive formation that reduces damage when allies nearby
local function updateShieldWall(unit: CombatUnit)
	if unit.stance ~= "Defensive" then
		unit.inShieldWall = false
		unit.shieldWallAllies = {}
		return
	end

	if not unit.model.PrimaryPart then
		return
	end

	-- Count nearby defensive allies
	local nearbyAllies = {}
	for allyModel, allyUnit in ActiveCombatUnits do
		if allyUnit.owner == unit.owner and allyModel ~= unit.model and allyUnit.stance == "Defensive" then
			local distance = getDistance(unit.model, allyModel)
			if distance and distance <= 10 then
				table.insert(nearbyAllies, allyModel)
			end
		end
	end

	-- Need at least 2 allies for shield wall
	unit.inShieldWall = #nearbyAllies >= 2
	unit.shieldWallAllies = nearbyAllies

	if unit.inShieldWall then
		CombatDebug:info("Shield Wall formed", {
			unit = unit.unitType,
			allies = #nearbyAllies,
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DAMAGE CALCULATION
-- ═══════════════════════════════════════════════════════════════════════════

local function calculateDamage(attacker: CombatUnit, defender: CombatUnit): number
	local baseDamage = attacker.attackDamage

	-- Apply armor reduction (5% per armor point, capped at 75%)
	local armorReduction = math.min(defender.armor * 0.05, 0.75)
	local damage = baseDamage * (1 - armorReduction)

	-- Stance modifiers
	local stanceMod = STANCE_MODIFIERS[attacker.stance]
	if stanceMod then
		damage = damage * stanceMod.damage
	end

	-- Defensive stance on defender
	local defenseStanceMod = STANCE_MODIFIERS[defender.stance]
	if defenseStanceMod then
		damage = damage / defenseStanceMod.defense
	end

	-- Celtic Fury bonus (Irish units with high morale)
	if attacker.celticFuryActive then
		damage = damage * CELTIC_FURY_DAMAGE
	end

	-- Charge bonus
	if attacker.isCharging then
		local chargeBonus = isIrish(attacker) and IRISH_CHARGE_BONUS or CHARGE_DAMAGE_BONUS
		damage = damage * chargeBonus
	end

	-- Shield Wall damage reduction
	if defender.inShieldWall then
		local reduction = SHIELD_WALL_DAMAGE_REDUCTION
		-- More allies = more reduction
		reduction = reduction + (#defender.shieldWallAllies * SHIELD_WALL_FORMATION_BONUS)
		reduction = math.min(reduction, 0.7) -- Cap at 70% reduction
		damage = damage * (1 - reduction)
	end

	-- Positional bonuses (flanking, rear attacks, high ground)
	if attacker.model.PrimaryPart and defender.model.PrimaryPart then
		local attackerPos = attacker.model.PrimaryPart.Position
		local defenderPos = defender.model.PrimaryPart.Position
		local defenderLook = defender.model.PrimaryPart.CFrame.LookVector

		-- Calculate attack direction
		local attackDir = (attackerPos - defenderPos).Unit
		local dotProduct = attackDir:Dot(defenderLook)

		-- Rear attack (behind defender)
		if dotProduct < -0.7 then
			damage = damage * REAR_ATTACK_BONUS
		-- Flanking (side attack)
		elseif dotProduct < -0.3 then
			damage = damage * FLANKING_DAMAGE_BONUS
		end

		-- High ground advantage
		local heightDiff = attackerPos.Y - defenderPos.Y
		if heightDiff > 5 then
			damage = damage * HIGH_GROUND_BONUS
		end
	end

	-- Morale effect (affects both offense and defense)
	local attackerMoraleBonus = (attacker.morale / 100) * 0.25 + 0.875 -- 87.5% to 112.5%
	local defenderMoralePenalty = 2 - ((defender.morale / 100) * 0.25 + 0.875) -- Inverse
	damage = damage * attackerMoraleBonus * defenderMoralePenalty

	return math.max(1, math.floor(damage))
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COMBAT EXECUTION
-- ═══════════════════════════════════════════════════════════════════════════

local function executeAttack(attacker: CombatUnit, defender: CombatUnit)
	local damage = calculateDamage(attacker, defender)

	-- Apply damage
	defender.health = math.max(0, defender.health - damage)
	defender.model:SetAttribute("CurrentHealth", defender.health)

	-- Update humanoid health for visual feedback
	local humanoid = defender.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = defender.health
	end

	-- Visual feedback
	if defender.model.PrimaryPart then
		createHitEffect(defender.model.PrimaryPart.Position, damage)
	end

	-- Morale changes
	MoraleManager.modifyMorale(defender.model, -5, "Took damage")
	MoraleManager.modifyMorale(attacker.model, 2, "Dealt damage")

	DamageDebug:info("Attack!", {
		attacker = attacker.unitType,
		defender = defender.unitType,
		damage = damage,
		defenderHP = defender.health,
		celticFury = attacker.celticFuryActive,
		shieldWall = defender.inShieldWall,
	})

	-- Handle death
	if defender.health <= 0 then
		handleUnitDeath(defender)
	end
end

function handleUnitDeath(unit: CombatUnit)
	CombatDebug:info("Unit killed!", {
		unitType = unit.unitType,
		faction = unit.faction,
	})

	-- Remove from combat system
	ActiveCombatUnits[unit.model] = nil

	-- Make the body fall over (visual feedback)
	local humanoid = unit.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0 -- Triggers death state
		humanoid:ChangeState(Enum.HumanoidStateType.Dead)
	end

	-- Make parts transparent/fade
	for _, part in unit.model:GetDescendants() do
		if part:IsA("BasePart") then
			local tween = TweenService:Create(part, TweenInfo.new(2), {
				Transparency = 1,
			})
			tween:Play()
		end
	end

	-- Morale impact on nearby allies
	MoraleManager.evaluateCombatSituation(unit.model)

	-- Record unit loss for revolt risk
	local owner = game.Players:GetPlayerByUserId(unit.owner)
	if owner then
		RevoltManager.recordUnitLoss(owner)
	end

	-- Morale boost for enemies and track kills
	for enemyModel, enemyUnit in ActiveCombatUnits do
		if areEnemies(unit, enemyUnit) then
			local distance = getDistance(unit.model, enemyModel)
			if distance and distance <= 30 then
				MoraleManager.modifyMorale(enemyModel, 5, "Enemy killed")

				-- Track achievement/quest for the killer (lazy-load to avoid circular deps)
				local killerPlayer = game.Players:GetPlayerByUserId(enemyUnit.owner)
				if killerPlayer then
					-- Lazy-load managers on first use
					if not AchievementManager then
						AchievementManager = require(script.Parent.AchievementManager)
					end
					if not QuestManager then
						QuestManager = require(script.Parent.QuestManager)
					end

					AchievementManager.incrementStat(killerPlayer, "EnemiesKilled", 1)

					-- Track Viking kills specifically
					if unit.unitType == "Viking" then
						AchievementManager.incrementStat(killerPlayer, "VikingsKilled", 1)
						QuestManager.updateQuestProgress(killerPlayer, "KillEnemies", "Viking", 1)
					end
				end
			end
		end
	end

	-- Destroy after fade animation
	task.delay(2, function()
		if unit.model and unit.model.Parent then
			CombatDebug:info("Destroying dead unit", {
				unitType = unit.unitType,
				modelName = unit.model.Name,
			})
			unit.model:Destroy()
		else
			CombatDebug:warn("Unit model already destroyed or not parented", {
				unitType = unit.unitType,
				hasModel = unit.model ~= nil,
				hasParent = unit.model and unit.model.Parent ~= nil,
			})
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN COMBAT UPDATE LOOP
-- ═══════════════════════════════════════════════════════════════════════════

local function updateCombat(currentTime: number)
	for unitModel, unit in ActiveCombatUnits do
		-- Validate unit still exists
		if not unitModel or not unitModel.Parent or unit.health <= 0 then
			ActiveCombatUnits[unitModel] = nil
			continue
		end

		-- Must have PrimaryPart for position
		if not unitModel.PrimaryPart then
			continue
		end

		-- Skip combat AI if unit has a manual movement order (player commanded movement)
		local hasManualMovement = unitModel:GetAttribute("IsMoving") and unit.targetModel == nil
		if hasManualMovement then
			-- Let movement system handle it, don't interfere with combat
			continue
		end

		-- Update Irish special abilities
		updateCelticFury(unit)
		tryWarCry(unit, currentTime)
		updateShieldWall(unit)

		-- Get or find target
		local targetModel = unit.targetModel

		-- Validate existing target
		if targetModel then
			local targetUnit = ActiveCombatUnits[targetModel]
			if not targetModel.Parent or not targetUnit or targetUnit.health <= 0 then
				unit.targetModel = nil
				targetModel = nil
			end
		end

		-- Find new target if needed
		if not targetModel and unit.stance ~= "Hold" then
			local searchRange = SEARCH_RANGE
			if unit.stance == "Aggressive" then
				searchRange = SEARCH_RANGE * 1.5
			end

			targetModel = findNearestEnemy(unit, searchRange)
			unit.targetModel = targetModel
		end

		-- No target - check if unit has manual movement order
		if not targetModel then
			-- Only clear movement if it was combat-initiated
			-- If player gave a manual move order, don't interfere
			local hasManualOrder = unitModel:GetAttribute("IsMoving") and unitModel:GetAttribute("TargetPosition")
			if not hasManualOrder then
				unit.isCharging = false
			end
			continue
		end

		-- Get target data
		local targetUnit = ActiveCombatUnits[targetModel]
		if not targetUnit or not targetModel.PrimaryPart then
			continue
		end

		local targetPos = targetModel.PrimaryPart.Position
		local distance = (targetPos - unitModel.PrimaryPart.Position).Magnitude

		-- In attack range?
		if distance <= unit.attackRange then
			-- Stop movement
			unitModel:SetAttribute("IsMoving", false)
			unitModel:SetAttribute("TargetPosition", nil)
			unit.isCharging = false

			-- Face target
			local lookAt = CFrame.lookAt(unitModel.PrimaryPart.Position, targetPos)
			unitModel.PrimaryPart.CFrame = CFrame.new(unitModel.PrimaryPart.Position)
				* CFrame.Angles(0, lookAt.Rotation.Y, 0)

			-- Attack if cooldown ready
			if currentTime - unit.lastAttackTime >= unit.attackSpeed then
				executeAttack(unit, targetUnit)
				unit.lastAttackTime = currentTime
			end
		else
			-- Move to target
			unitModel:SetAttribute("TargetPosition", targetPos)
			unitModel:SetAttribute("IsMoving", true)

			-- Charging?
			if unit.stance == "Aggressive" or unit.stance == "Charge" then
				unit.isCharging = distance <= CHARGE_DISTANCE and distance > unit.attackRange
			else
				unit.isCharging = false
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function CombatManager.setTarget(attackerModel: Model, targetModel: Model)
	local attacker = ActiveCombatUnits[attackerModel]
	local target = ActiveCombatUnits[targetModel]

	if not attacker then
		CombatDebug:warn("Attacker not in combat system", { model = attackerModel.Name })
		return
	end

	if not target then
		CombatDebug:warn("Target not in combat system", { model = targetModel.Name })
		return
	end

	if not areEnemies(attacker, target) then
		CombatDebug:warn("Cannot attack ally", {
			attacker = attacker.unitType,
			target = target.unitType,
		})
		return
	end

	-- Set target and clear movement
	attacker.targetModel = targetModel
	attacker.stance = "Aggressive"
	attackerModel:SetAttribute("IsMoving", false)
	attackerModel:SetAttribute("TargetPosition", nil)

	CombatDebug:info("Manual attack order", {
		attacker = attacker.unitType,
		target = target.unitType,
	})
end

function CombatManager.setStance(unitModel: Model, stance: Stance)
	local unit = ActiveCombatUnits[unitModel]

	if not unit then
		CombatDebug:warn("Unit not in combat system for stance change")
		return
	end

	unit.stance = stance

	-- Clear target if Hold stance
	if stance == "Hold" then
		unit.targetModel = nil
		unitModel:SetAttribute("IsMoving", false)
		unitModel:SetAttribute("TargetPosition", nil)
	end

	CombatDebug:info("Stance changed", {
		unit = unit.unitType,
		stance = stance,
	})
end

function CombatManager.getActiveCombatUnits(): { [Model]: CombatUnit }
	return ActiveCombatUnits
end

function CombatManager.clearTarget(unitModel: Model)
	local unit = ActiveCombatUnits[unitModel]
	if unit then
		unit.targetModel = nil
		unit.isCharging = false
		CombatDebug:info("Combat target cleared for manual movement", {
			unit = unit.unitType,
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

function CombatManager.init()
	-- Use a proper timer-based update loop
	lastUpdateTime = tick()

	RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		local deltaTime = currentTime - lastUpdateTime

		-- Only update at fixed rate
		if deltaTime >= COMBAT_TICK_RATE then
			updateCombat(currentTime)
			lastUpdateTime = currentTime
		end
	end)

	CombatDebug:info("Combat system initialized with Irish features", {
		tickRate = COMBAT_TICK_RATE,
		features = { "Celtic Fury", "War Cry", "Shield Wall", "Formations" },
	})
end

return CombatManager
