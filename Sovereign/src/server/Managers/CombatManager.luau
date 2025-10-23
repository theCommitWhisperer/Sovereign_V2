--!strict
-- CombatManager: Core combat system for Irish RTS
-- Handles unit combat, damage calculation, and battle flow

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local CombatDebug = DebugManager.createChannel("Combat", true)
local DamageDebug = DebugManager.createChannel("Damage", false)

local CombatManager = {}

-- Combat constants
local COMBAT_TICK_RATE = 0.5 -- How often combat calculations run
local MELEE_RANGE = 8 -- studs
local CHARGE_DAMAGE_BONUS = 1.5
local FLANKING_DAMAGE_BONUS = 1.3
local HIGH_GROUND_BONUS = 1.2

-- Irish faction bonuses
local CELTIC_FURY_THRESHOLD = 80 -- morale threshold for damage bonus
local CELTIC_FURY_BONUS = 1.15
local IRISH_CHARGE_BONUS = 1.2 -- Irish units get better charge bonus

export type CombatUnit = {
	model: Model,
	owner: number,
	unitType: string,
	health: number,
	maxHealth: number,
	attackDamage: number,
	attackSpeed: number,
	attackRange: number,
	armor: number,
	morale: number,
	stance: "Aggressive" | "Defensive" | "Hold" | "Charge",
	target: Model?,
	formation: string?,
	lastAttackTime: number,
	isCharging: boolean,
	faction: string,
}

local ActiveCombatUnits: { [Model]: CombatUnit } = {}
local CombatEngagements: { { attacker: Model, defender: Model } } = {}

-- Initialize combat stats for a unit
function CombatManager.initializeCombatUnit(unitModel: Model, owner: Player)
	local unitType = unitModel:GetAttribute("UnitType")
	local unitData = GameData.Units[unitType]

	if not unitData then
		CombatDebug:warn("No combat data for unit type", { unitType = unitType })
		return
	end

	local playerData = PlayerManager.get(owner)
	local faction = playerData and playerData.Faction or "Kingdom"

	local combatUnit: CombatUnit = {
		model = unitModel,
		owner = owner.UserId,
		unitType = unitType,
		health = unitData.hit_points,
		maxHealth = unitData.hit_points,
		attackDamage = unitData.attack_damage,
		attackSpeed = unitData.attack_cooldown or 2,
		attackRange = unitData.attack_range_meters * 3, -- Convert to studs
		armor = unitData.armor_rating or 0,
		morale = 75, -- Start with decent morale
		stance = "Defensive",
		target = nil,
		formation = nil,
		lastAttackTime = 0,
		isCharging = false,
		faction = faction,
	}

	ActiveCombatUnits[unitModel] = combatUnit

	-- Set up health display
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = unitData.hit_points
		humanoid.Health = unitData.hit_points
	end

	CombatDebug:info("Initialized combat unit", {
		unitType = unitType,
		owner = owner.Name,
		faction = faction,
	})
end

-- Calculate damage with all modifiers
local function calculateDamage(attacker: CombatUnit, defender: CombatUnit): number
	local baseDamage = attacker.attackDamage

	-- Apply armor reduction
	local damageReduction = defender.armor * 0.05 -- 5% reduction per armor point
	local damage = baseDamage * (1 - damageReduction)

	-- Celtic Fury bonus for Irish units with high morale
	if attacker.faction == "Irish" and attacker.morale >= CELTIC_FURY_THRESHOLD then
		damage = damage * CELTIC_FURY_BONUS
		DamageDebug:info("Celtic Fury activated!", { bonus = CELTIC_FURY_BONUS })
	end

	-- Charge bonus
	if attacker.isCharging then
		local chargeBonus = attacker.faction == "Irish" and IRISH_CHARGE_BONUS or CHARGE_DAMAGE_BONUS
		damage = damage * chargeBonus
		DamageDebug:info("Charge bonus applied", { bonus = chargeBonus })
	end

	-- Formation bonuses/penalties
	if attacker.formation == "Wedge" and attacker.isCharging then
		damage = damage * 1.3
	elseif defender.formation == "ShieldWall" and not attacker.isCharging then
		damage = damage * 0.7 -- Shield wall strong against normal attacks
	end

	-- Stance modifiers
	if attacker.stance == "Aggressive" then
		damage = damage * 1.2
	elseif defender.stance == "Defensive" then
		damage = damage * 0.8
	end

	-- Morale effect
	local moraleFactor = (attacker.morale / 100) * 0.3 + 0.85 -- 85% to 115% based on morale
	damage = damage * moraleFactor

	-- Check for flanking
	if isFlankingAttack(attacker, defender) then
		damage = damage * FLANKING_DAMAGE_BONUS
		DamageDebug:info("Flanking bonus!", { bonus = FLANKING_DAMAGE_BONUS })
	end

	-- Terrain advantages (simplified - check Y position difference)
	if attacker.model.PrimaryPart and defender.model.PrimaryPart then
		local heightDiff = attacker.model.PrimaryPart.Position.Y - defender.model.PrimaryPart.Position.Y
		if heightDiff > 5 then
			damage = damage * HIGH_GROUND_BONUS
			DamageDebug:info("High ground advantage!", { bonus = HIGH_GROUND_BONUS })
		end
	end

	return math.max(1, math.floor(damage))
end

-- Check if attack is from behind or side
function isFlankingAttack(attacker: CombatUnit, defender: CombatUnit): boolean
	if not (attacker.model.PrimaryPart and defender.model.PrimaryPart) then
		return false
	end

	local toAttacker = (attacker.model.PrimaryPart.Position - defender.model.PrimaryPart.Position).Unit
	local defenderFacing = defender.model.PrimaryPart.CFrame.LookVector

	local dotProduct = toAttacker:Dot(defenderFacing)
	return dotProduct < -0.5 -- Attack from behind or side
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
	defender.health = math.max(0, defender.health - damage)

	-- Update humanoid health
	local humanoid = defender.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = defender.health
	end

	-- Morale impact
	defender.morale = math.max(0, defender.morale - 5)
	attacker.morale = math.min(100, attacker.morale + 2)

	CombatDebug:info("Attack executed", {
		attacker = attacker.unitType,
		defender = defender.unitType,
		damage = damage,
		remainingHealth = defender.health,
	})

	-- Check if defender died
	if defender.health <= 0 then
		handleUnitDeath(defender)
	end
end

-- Handle unit death
function handleUnitDeath(unit: CombatUnit)
	CombatDebug:info("Unit killed", { unitType = unit.unitType })

	-- Remove from active units
	ActiveCombatUnits[unit.model] = nil

	-- Morale penalty to nearby allies
	local deathPos = unit.model.PrimaryPart and unit.model.PrimaryPart.Position
	if deathPos then
		for allyModel, allyUnit in pairs(ActiveCombatUnits) do
			if allyUnit.owner == unit.owner and allyUnit.health > 0 then
				local allyPos = allyModel.PrimaryPart and allyModel.PrimaryPart.Position
				if allyPos and (allyPos - deathPos).Magnitude < 50 then
					allyUnit.morale = math.max(0, allyUnit.morale - 10)
				end
			end
		end
	end

	-- Destroy the model after a delay
	task.wait(2)
	if unit.model and unit.model.Parent then
		unit.model:Destroy()
	end
end

-- Main combat update loop
local function updateCombat()
	local currentTime = tick()

	for unitModel, unit in pairs(ActiveCombatUnits) do
		if unit.health <= 0 then
			continue
		end

		-- Check if unit has a target
		if not unit.target or not unit.target.Parent or not ActiveCombatUnits[unit.target] then
			-- Find new target based on stance
			if unit.stance == "Aggressive" then
				unit.target = findNearestEnemy(unit, unit.attackRange * 2)
			elseif unit.stance == "Defensive" then
				unit.target = findNearestEnemy(unit, unit.attackRange)
			elseif unit.stance == "Hold" then
				unit.target = findNearestEnemy(unit, unit.attackRange * 0.8)
			end
		end

		-- Attack if target in range and attack cooldown ready
		if unit.target and ActiveCombatUnits[unit.target] then
			local targetUnit = ActiveCombatUnits[unit.target]
			local unitPos = unit.model.PrimaryPart and unit.model.PrimaryPart.Position
			local targetPos = unit.target.PrimaryPart and unit.target.PrimaryPart.Position

			if unitPos and targetPos then
				local distance = (targetPos - unitPos).Magnitude

				if distance <= unit.attackRange then
					-- Stop charging when in range
					unit.isCharging = false

					-- Attack if cooldown ready
					if currentTime - unit.lastAttackTime >= unit.attackSpeed then
						executeAttack(unit, targetUnit)
						unit.lastAttackTime = currentTime
					end
				elseif distance <= unit.attackRange * 3 and unit.stance == "Aggressive" then
					-- Start charging if aggressive and enemy is within charge range
					unit.isCharging = true
				end
			end
		end
	end
end

-- Set unit stance
function CombatManager.setUnitStance(unitModel: Model, stance: string)
	local unit = ActiveCombatUnits[unitModel]
	if unit then
		unit.stance = stance
		CombatDebug:info("Stance changed", {
			unit = unit.unitType,
			newStance = stance,
		})
	end
end

-- Set unit formation
function CombatManager.setFormation(units: { Model }, formation: string)
	for _, unitModel in ipairs(units) do
		local unit = ActiveCombatUnits[unitModel]
		if unit then
			unit.formation = formation
		end
	end

	CombatDebug:info("Formation set", {
		unitCount = #units,
		formation = formation,
	})
end

-- Manual attack order
function CombatManager.attackTarget(attackerModel: Model, targetModel: Model)
	local attacker = ActiveCombatUnits[attackerModel]
	local target = ActiveCombatUnits[targetModel]

	if attacker and target and target.owner ~= attacker.owner then
		attacker.target = targetModel
		CombatDebug:info("Attack order", {
			attacker = attacker.unitType,
			target = target.unitType,
		})
	end
end

-- Initialize the combat loop
function CombatManager.init()
	RunService.Heartbeat:Connect(function()
		if tick() % COMBAT_TICK_RATE < 0.1 then
			updateCombat()
		end
	end)

	CombatDebug:info("Combat system initialized")
end

return CombatManager
