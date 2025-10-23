--!strict
-- CombatManager: Core combat system for Irish RTS
-- Handles unit combat, damage calculation, and battle flow

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MoraleManager = require(script.Parent.MoraleManager) -- ADDED: Needed for Morale calls

local CombatDebug = DebugManager.createChannel("Combat", true)
local DamageDebug = DebugManager.createChannel("Damage", true)

local CombatManager = {}

-- Combat constants
local COMBAT_TICK_RATE = 0.5 -- How often combat calculations run
local MELEE_RANGE_STUD = 8 -- Minimum distance for melee combat (approx 2.6m)
local CHARGE_DISTANCE_STUD = 30 -- Distance at which a unit initiates a charge
local CHARGE_DAMAGE_BONUS = 1.5
local FLANKING_DAMAGE_BONUS = 1.3
local HIGH_GROUND_BONUS = 1.2

-- Irish faction bonuses
local CELTIC_FURY_THRESHOLD = 80 -- morale threshold for damage bonus
local CELTIC_FURY_BONUS = 1.15
local IRISH_CHARGE_BONUS = 1.2 -- Irish units get better charge bonus

export type Stance = "Aggressive" | "Defensive" | "Hold" | "Charge"

export type CombatUnit = {
	model: Model,
	unitData: GameData.UnitData,
	owner: number,
	unitType: string,
	health: number,
	maxHealth: number,
	attackDamage: number,
	attackSpeed: number, -- Cooldown in seconds
	attackRange: number, -- In studs (converted from meters)
	armor: number,
	morale: number,
	stance: Stance,
	targetModel: Model?,
	formation: string?,
	lastAttackTime: number,
	isCharging: boolean,
	faction: string,
}

local ActiveCombatUnits: { [Model]: CombatUnit } = {}

-- Utility: Convert game unit range (meters) to Roblox studs (approx 1m = 3 studs)
local function getAttackRangeStuds(unitData: GameData.UnitData): number
	return (unitData.combat and unitData.combat.attack_range or 5) * 3
end

-- Initialize combat stats for a unit
function CombatManager.initializeCombatUnit(unitModel: Model, owner: Player)
	local unitType = unitModel:GetAttribute("UnitType")
	local unitData = GameData.Units[unitType]

	if not unitData or not unitData.combat then
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
		stance = "Aggressive", -- Default to aggressive
		targetModel = nil,
		formation = nil,
		lastAttackTime = 0,
		isCharging = false,
		faction = faction,
	}

	ActiveCombatUnits[unitModel] = combatUnit

	CombatDebug:info("Initialized combat unit", {
		unitType = unitType,
		owner = owner.Name,
		faction = faction,
	})
end

-- Calculate damage with all modifiers
local function calculateDamage(attacker: CombatUnit, defender: CombatUnit): number
	local baseDamage = attacker.attackDamage

	-- Apply armor reduction (simplified: 5% reduction per armor point)
	local damageReduction = defender.armor * 0.05
	local damage = baseDamage * (1 - damageReduction)

	-- Celtic Fury bonus
	if attacker.faction == "Irish" and attacker.morale >= CELTIC_FURY_THRESHOLD then
		damage = damage * CELTIC_FURY_BONUS
	end

	-- Charge bonus
	if attacker.isCharging then
		local chargeBonus = attacker.faction == "Irish" and IRISH_CHARGE_BONUS or CHARGE_DAMAGE_BONUS
		damage = damage * chargeBonus
	end

	-- Flanking check (simplified)
	if attacker.model.PrimaryPart and defender.model.PrimaryPart then
		local toAttacker = (attacker.model.PrimaryPart.Position - defender.model.PrimaryPart.Position).Unit
		local defenderFacing = defender.model.PrimaryPart.CFrame.LookVector
		local dotProduct = toAttacker:Dot(defenderFacing)

		if dotProduct < -0.5 then -- Attack from behind or side
			damage = damage * FLANKING_DAMAGE_BONING_BONUS
		end

		-- High ground check
		local heightDiff = attacker.model.PrimaryPart.Position.Y - defender.model.PrimaryPart.Position.Y
		if heightDiff > 5 then
			damage = damage * HIGH_GROUND_BONUS
		end
	end

	-- Stance modifiers
	if attacker.stance == "Aggressive" then
		damage = damage * 1.2
	elseif defender.stance == "Defensive" then
		damage = damage * 0.8
	end

	-- Morale effect (simplified)
	local moraleFactor = (attacker.morale / 100) * 0.3 + 0.85 -- 85% to 115% based on morale
	damage = damage * moraleFactor

	return math.max(1, math.floor(damage))
end

-- Find nearest enemy within range
local function findNearestEnemy(unit: CombatUnit, range: number): Model?
	local unitPos = unit.model.PrimaryPart and unit.model.PrimaryPart.Position
	if not unitPos then
		return nil
	end

	local nearestEnemy: Model? = nil
	local nearestDistance = math.huge

	for enemyModel, enemyUnit in pairs(ActiveCombatUnits) do
		if enemyUnit.owner ~= unit.owner and enemyUnit.health > 0 then
			local enemyPos = enemyModel.PrimaryPart and enemyModel.PrimaryPart.Position
			if enemyPos then
				local distance = (enemyPos - unitPos).Magnitude
				if distance <= range and distance < nearestDistance then
					nearestEnemy = enemyModel
					nearestDistance = distance
				end
			end
		end
	end

	return nearestEnemy
end

-- Execute attack
local function executeAttack(attacker: CombatUnit, defender: CombatUnit)
	local damage = calculateDamage(attacker, defender)

	-- Apply damage
	defender.health = math.max(0, defender.health - damage)

	-- Update model attributes (HealthBarManager subscribes to this)
	defender.model:SetAttribute("CurrentHealth", defender.health)

	-- Morale impact (simplified)
	MoraleManager.modifyMorale(defender.model, -5, "Took damage")
	MoraleManager.modifyMorale(attacker.model, 2, "Dealt damage")

	CombatDebug:info("Attack executed", {
		attacker = attacker.unitType,
		defender = defender.unitType,
		damage = damage,
		remainingHealth = defender.health,
	})

	-- Check if defender died
	if defender.health <= 0 then
		-- Clean up the CombatUnit data, the death logic is in handleUnitDeath
		ActiveCombatUnits[defender.model] = nil
		handleUnitDeath(defender)
	end
end

-- Handle unit death
local function handleUnitDeath(unit: CombatUnit)
	CombatDebug:info("Unit killed", { unitType = unit.unitType })

	-- Morale penalty to nearby allies
	MoraleManager.evaluateCombatSituation(unit.model) -- This implicitly handles ally morale penalties

	-- Remove from Units folder (handled by PlayerManager.removeUnit in a real game flow, but destroyed explicitly here)
	-- The UnitManager will clean up unit data when the model is destroyed.
	task.wait(2)
	if unit.model and unit.model.Parent then
		unit.model:Destroy()
	end
end

-- Main combat update loop
local function updateCombat(deltaTime: number)
	local currentTime = tick()

	for unitModel, unit in pairs(ActiveCombatUnits) do
		-- Check if model is still valid
		if not unitModel or not unitModel.Parent or unit.health <= 0 then
			ActiveCombatUnits[unitModel] = nil
			continue
		end

		local unitHRP = unitModel.PrimaryPart
		if not unitHRP then
			continue
		end

		local targetModel = unit.targetModel

		-- 1. Validate / Find Target
		if not targetModel or not targetModel.Parent or not ActiveCombatUnits[targetModel] then
			-- Find new target based on stance
			local rangeForSearch = unit.attackRange
			if unit.stance == "Aggressive" then
				rangeForSearch = CHARGE_DISTANCE_STUD * 2 -- Search wider if aggressive
			end
			unit.targetModel = findNearestEnemy(unit, rangeForSearch)
			targetModel = unit.targetModel

			if not targetModel then
				-- No target, stop movement
				unitModel:SetAttribute("IsMoving", false)
				unitModel:SetAttribute("TargetPosition", nil)
				unit.isCharging = false
				continue
			end
		end

		local targetUnit = ActiveCombatUnits[targetModel]
		local targetPos = targetModel.PrimaryPart and targetModel.PrimaryPart.Position
		if not targetPos then
			continue
		end

		local distance = (targetPos - unitHRP.Position).Magnitude

		-- 2. Movement/Attack Logic
		local attackRange = unit.attackRange

		if distance <= attackRange + MELEE_RANGE_STUD * 0.5 then -- In attack range
			-- Stop Movement
			unitModel:SetAttribute("IsMoving", false)
			unitModel:SetAttribute("TargetPosition", nil)
			unit.isCharging = false

			-- Attack if cooldown ready
			if currentTime - unit.lastAttackTime >= unit.attackSpeed then
				executeAttack(unit, targetUnit)
				unit.lastAttackTime = currentTime
			end
		else
			-- Out of range, initiate movement/charge

			-- Set target position to move to
			if not unitModel:GetAttribute("IsMoving") or unitModel:GetAttribute("TargetPosition") ~= targetPos then
				unitModel:SetAttribute("TargetPosition", targetPos)
				unitModel:SetAttribute("IsMoving", true)
			end

			-- Check for charge distance if aggressive or manually set
			if unit.stance == "Aggressive" and distance < CHARGE_DISTANCE_STUD and distance > attackRange then
				unit.isCharging = true
			else
				unit.isCharging = false
			end
		end
	end
end

-- PUBLIC FUNCTIONS exposed for GameManager to call

-- Manual attack order from client
function CombatManager.setTarget(attackerModel: Model, targetModel: Model)
	local attacker = ActiveCombatUnits[attackerModel]

	if attacker and targetModel:GetAttribute("Owner") ~= attacker.owner then
		-- Clear unit's movement so combat system takes over
		attackerModel:SetAttribute("IsMoving", false)
		attackerModel:SetAttribute("TargetPosition", nil)

		attacker.targetModel = targetModel
		CombatDebug:info("Attack order received", {
			attacker = attacker.unitType,
			target = targetModel.Name,
		})
	end
end

-- Manual stance change from client
function CombatManager.setStance(unitModel: Model, stance: Stance)
	local unit = ActiveCombatUnits[unitModel]
	if unit then
		unit.stance = stance

		-- If Hold, clear target to force them to stop and auto-engage only in range
		if stance == "Hold" then
			unit.targetModel = nil
			unitModel:SetAttribute("IsMoving", false)
			unitModel:SetAttribute("TargetPosition", nil)
		end

		CombatDebug:info("Stance changed", {
			unit = unit.unitType,
			newStance = stance,
		})
	end
end

-- Initialize the combat loop
function CombatManager.init()
	RunService.Heartbeat:Connect(function(deltaTime)
		-- Only run the combat loop periodically to save performance
		if tick() % COMBAT_TICK_RATE < 0.1 then
			updateCombat(deltaTime)
		end
	end)

	CombatDebug:info("Combat system initialized")
end

return CombatManager
