--!strict
-- CombatManager: Handles unit combat, damage, and death

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local CombatDebug = DebugManager.createChannel("Combat", true)

local CombatManager = {}

-- Units currently in combat
type CombatState = {
	unit: Model,
	target: Model?,
	lastAttackTime: number,
	isInCombat: boolean,
}

local CombatStates: { [Model]: CombatState } = {}

-- Deal damage to a unit
function CombatManager.dealDamage(attacker: Model, target: Model, damage: number): boolean
	if not target or not target.Parent then
		return false
	end

	local currentHealth = target:GetAttribute("CurrentHealth") or 0
	local maxHealth = target:GetAttribute("MaxHealth") or 100
	local armor = 0

	-- Get target's armor
	local targetType = target:GetAttribute("UnitType")
	if targetType then
		local unitInfo = GameData.Units[targetType]
		if unitInfo and unitInfo.combat then
			armor = unitInfo.combat.armor or 0
		end
	end

	-- Calculate damage after armor
	local actualDamage = math.max(1, damage - armor)
	local newHealth = math.max(0, currentHealth - actualDamage)

	target:SetAttribute("CurrentHealth", newHealth)

	CombatDebug:info("Damage dealt", {
		attacker = attacker.Name,
		target = target.Name,
		damage = actualDamage,
		remainingHealth = newHealth,
		maxHealth = maxHealth,
	})

	-- Check if unit died
	if newHealth <= 0 then
		CombatManager.killUnit(target)
		return true
	end

	return false
end

-- Kill a unit
function CombatManager.killUnit(unit: Model)
	if not unit or not unit.Parent then
		return
	end

	CombatDebug:info("Unit killed", {
		unit = unit.Name,
		unitType = unit:GetAttribute("UnitType"),
		owner = unit:GetAttribute("Owner"),
		currentHealth = unit:GetAttribute("CurrentHealth"),
	})

	-- Remove from combat states
	if CombatStates[unit] then
		CombatStates[unit] = nil
	end

	-- Remove from player's units
	local owner = unit:GetAttribute("Owner")
	if owner then
		local player = game.Players:GetPlayerByUserId(owner)
		if player then
			PlayerManager.removeUnit(player, unit)
		end
	end

	-- Play death effect (simple for now)
	local explosion = Instance.new("Explosion")
	explosion.Position = unit.PrimaryPart and unit.PrimaryPart.Position or unit:GetPivot().Position
	explosion.BlastRadius = 5
	explosion.BlastPressure = 0 -- No physics force
	explosion.Parent = workspace

	-- Destroy the unit
	unit:Destroy()
end

-- Set a unit's attack target
function CombatManager.setTarget(unit: Model, target: Model?)
	if not unit or not unit.Parent then
		return
	end

	-- Initialize combat state if needed
	if not CombatStates[unit] then
		CombatStates[unit] = {
			unit = unit,
			target = nil,
			lastAttackTime = 0,
			isInCombat = false,
		}
	end

	CombatStates[unit].target = target
	CombatStates[unit].isInCombat = target ~= nil

	if target then
		CombatDebug:info("Target set", {
			unit = unit.Name,
			target = target.Name,
		})
	else
		CombatDebug:info("Target cleared", { unit = unit.Name })
	end
end

-- Get nearest enemy unit
local function getNearestEnemy(unit: Model, maxRange: number): Model?
	if not unit or not unit.PrimaryPart then
		return nil
	end

	local unitOwner = unit:GetAttribute("Owner")
	local unitPosition = unit.PrimaryPart.Position

	local nearestEnemy: Model? = nil
	local nearestDistance = maxRange

	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return nil
	end

	for _, potentialEnemy in unitsFolder:GetChildren() do
		if potentialEnemy:IsA("Model") and potentialEnemy ~= unit and potentialEnemy.PrimaryPart then
			local enemyOwner = potentialEnemy:GetAttribute("Owner")

			-- Check if it's an enemy (different owner)
			if enemyOwner and enemyOwner ~= unitOwner then
				local distance = (potentialEnemy.PrimaryPart.Position - unitPosition).Magnitude

				if distance < nearestDistance then
					nearestEnemy = potentialEnemy
					nearestDistance = distance
				end
			end
		end
	end

	return nearestEnemy
end

-- Update combat for all units
local function updateCombat(deltaTime: number)
	for unit, state in CombatStates do
		-- Check if unit still exists
		if not unit or not unit.Parent or not unit.PrimaryPart then
			CombatStates[unit] = nil
			continue
		end

		-- Get unit combat stats
		local unitType = unit:GetAttribute("UnitType")
		if not unitType then
			continue
		end

		local unitInfo = GameData.Units[unitType]
		if not unitInfo or not unitInfo.combat then
			continue
		end

		local attackDamage = unitInfo.combat.attack_damage or 5
		local attackSpeed = unitInfo.combat.attack_speed or 1.0
		local attackRange = unitInfo.combat.attack_range or 2

		-- Check if target is still valid
		if state.target and (not state.target.Parent or state.target:GetAttribute("CurrentHealth") <= 0) then
			CombatManager.setTarget(unit, nil)
		end

		-- If no target, look for nearby enemies
		if not state.target then
			local enemy = getNearestEnemy(unit, attackRange * 2)
			if enemy then
				CombatManager.setTarget(unit, enemy)
			end
		end

		-- If we have a target, attack it
		if state.target and state.target.Parent then
			local targetPosition = state.target.PrimaryPart and state.target.PrimaryPart.Position
			local unitPosition = unit.PrimaryPart.Position

			if targetPosition then
				local distance = (targetPosition - unitPosition).Magnitude

				-- Move towards target if out of range
				if distance > attackRange then
					-- Set movement target
					unit:SetAttribute("TargetPosition", targetPosition)
					unit:SetAttribute("IsMoving", true)
				else
					-- Stop moving
					unit:SetAttribute("IsMoving", false)
					unit:SetAttribute("TargetPosition", nil)

					-- Attack if cooldown is ready
					local currentTime = tick()
					if currentTime - state.lastAttackTime >= attackSpeed then
						state.lastAttackTime = currentTime

						-- Deal damage
						local killed = CombatManager.dealDamage(unit, state.target, attackDamage)

						if killed then
							CombatManager.setTarget(unit, nil)
						end
					end
				end
			end
		end
	end
end

-- Start combat update loop
RunService.Heartbeat:Connect(function(deltaTime)
	updateCombat(deltaTime)
end)

CombatDebug:info("Initialized")

return CombatManager
