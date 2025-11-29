--!strict
-- AbilityManager: Handles hero abilities with cooldowns and effects
-- Features: Rally Troops, Charge, Battle Cry, Divine Protection, etc.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MoraleManager = require(script.Parent.MoraleManager)

local AbilityDebug = DebugManager.createChannel("Abilities", false)

local AbilityManager = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- TYPES & CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

export type Ability = {
	id: string,
	name: string,
	description: string,
	cooldown: number,
	duration: number?,
	radius: number?,
	effect: (player: Player, character: Model) -> (),
}

type AbilityCooldown = {
	abilityId: string,
	readyTime: number,
}

local PlayerAbilityCooldowns: { [number]: { [string]: number } } = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- ABILITY DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

local ABILITIES: { [string]: Ability } = {
	Rally = {
		id = "Rally",
		name = "Rally Troops",
		description = "Boost morale of nearby allies by 20 for 15 seconds",
		cooldown = 45,
		duration = 15,
		radius = 40,
		effect = function(player: Player, character: Model)
			if not character.PrimaryPart then
				return
			end

			local position = character.PrimaryPart.Position
			local unitsFolder = workspace:FindFirstChild("Units")
			if not unitsFolder then
				return
			end

			local boostedCount = 0
			for _, unit in unitsFolder:GetChildren() do
				if unit:IsA("Model") and unit:GetAttribute("Owner") == player.UserId then
					if unit.PrimaryPart then
						local distance = (unit.PrimaryPart.Position - position).Magnitude
						if distance <= 40 then
							MoraleManager.modifyMorale(unit, 20, "Rally Troops")
							boostedCount += 1
						end
					end
				end
			end

			AbilityDebug:info(`Rally Troops boosted {boostedCount} units for {player.Name}`)

			-- Send notification to client
			local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if remoteEvents then
				local gameEvent = remoteEvents:FindFirstChild("GameEvent")
				if gameEvent and gameEvent:IsA("RemoteEvent") then
					gameEvent:FireClient(player, "AbilityUsed", {
						abilityId = "Rally",
						message = `Rallied {boostedCount} troops!`,
					})
				end
			end
		end,
	},

	Charge = {
		id = "Charge",
		name = "Heroic Charge",
		description = "Increase damage by 50% for nearby troops for 10 seconds",
		cooldown = 60,
		duration = 10,
		radius = 35,
		effect = function(player: Player, character: Model)
			if not character.PrimaryPart then
				return
			end

			local position = character.PrimaryPart.Position
			local unitsFolder = workspace:FindFirstChild("Units")
			if not unitsFolder then
				return
			end

			local chargedUnits = {}
			for _, unit in unitsFolder:GetChildren() do
				if unit:IsA("Model") and unit:GetAttribute("Owner") == player.UserId then
					if unit.PrimaryPart then
						local distance = (unit.PrimaryPart.Position - position).Magnitude
						if distance <= 35 then
							unit:SetAttribute("DamageBoost", 1.5)
							table.insert(chargedUnits, unit)
						end
					end
				end
			end

			-- Remove boost after duration
			task.delay(10, function()
				for _, unit in chargedUnits do
					if unit and unit.Parent then
						unit:SetAttribute("DamageBoost", nil)
					end
				end
			end)

			AbilityDebug:info(`Heroic Charge activated for {#chargedUnits} units`)

			local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if remoteEvents then
				local gameEvent = remoteEvents:FindFirstChild("GameEvent")
				if gameEvent and gameEvent:IsA("RemoteEvent") then
					gameEvent:FireClient(player, "AbilityUsed", {
						abilityId = "Charge",
						message = `{#chargedUnits} troops charged into battle!`,
					})
				end
			end
		end,
	},

	BattleCry = {
		id = "BattleCry",
		name = "Battle Cry",
		description = "Increase attack speed by 30% for nearby troops for 12 seconds",
		cooldown = 50,
		duration = 12,
		radius = 30,
		effect = function(player: Player, character: Model)
			if not character.PrimaryPart then
				return
			end

			local position = character.PrimaryPart.Position
			local unitsFolder = workspace:FindFirstChild("Units")
			if not unitsFolder then
				return
			end

			local affectedUnits = {}
			for _, unit in unitsFolder:GetChildren() do
				if unit:IsA("Model") and unit:GetAttribute("Owner") == player.UserId then
					if unit.PrimaryPart then
						local distance = (unit.PrimaryPart.Position - position).Magnitude
						if distance <= 30 then
							local humanoid = unit:FindFirstChildOfClass("Humanoid")
							if humanoid then
								humanoid.WalkSpeed = humanoid.WalkSpeed * 1.3
								table.insert(affectedUnits, { unit = unit, humanoid = humanoid })
							end
						end
					end
				end
			end

			-- Restore speed after duration
			task.delay(12, function()
				for _, data in affectedUnits do
					if data.unit and data.unit.Parent and data.humanoid then
						data.humanoid.WalkSpeed = data.humanoid.WalkSpeed / 1.3
					end
				end
			end)

			AbilityDebug:info(`Battle Cry activated for {#affectedUnits} units`)

			local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if remoteEvents then
				local gameEvent = remoteEvents:FindFirstChild("GameEvent")
				if gameEvent and gameEvent:IsA("RemoteEvent") then
					gameEvent:FireClient(player, "AbilityUsed", {
						abilityId = "BattleCry",
						message = "Battle Cry echoes across the battlefield!",
					})
				end
			end
		end,
	},

	DivineProtection = {
		id = "DivineProtection",
		name = "Divine Protection",
		description = "Reduce damage taken by 40% for nearby troops for 8 seconds",
		cooldown = 75,
		duration = 8,
		radius = 25,
		effect = function(player: Player, character: Model)
			if not character.PrimaryPart then
				return
			end

			local position = character.PrimaryPart.Position
			local unitsFolder = workspace:FindFirstChild("Units")
			if not unitsFolder then
				return
			end

			local protectedUnits = {}
			for _, unit in unitsFolder:GetChildren() do
				if unit:IsA("Model") and unit:GetAttribute("Owner") == player.UserId then
					if unit.PrimaryPart then
						local distance = (unit.PrimaryPart.Position - position).Magnitude
						if distance <= 25 then
							unit:SetAttribute("DamageReduction", 0.4)
							table.insert(protectedUnits, unit)
						end
					end
				end
			end

			-- Remove protection after duration
			task.delay(8, function()
				for _, unit in protectedUnits do
					if unit and unit.Parent then
						unit:SetAttribute("DamageReduction", nil)
					end
				end
			end)

			AbilityDebug:info(`Divine Protection activated for {#protectedUnits} units`)

			local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if remoteEvents then
				local gameEvent = remoteEvents:FindFirstChild("GameEvent")
				if gameEvent and gameEvent:IsA("RemoteEvent") then
					gameEvent:FireClient(player, "AbilityUsed", {
						abilityId = "DivineProtection",
						message = "Divine light shields your troops!",
					})
				end
			end
		end,
	},

	Heal = {
		id = "Heal",
		name = "Healing Aura",
		description = "Restore 30% health to nearby troops instantly",
		cooldown = 90,
		radius = 30,
		effect = function(player: Player, character: Model)
			if not character.PrimaryPart then
				return
			end

			local position = character.PrimaryPart.Position
			local unitsFolder = workspace:FindFirstChild("Units")
			if not unitsFolder then
				return
			end

			local healedCount = 0
			for _, unit in unitsFolder:GetChildren() do
				if unit:IsA("Model") and unit:GetAttribute("Owner") == player.UserId then
					if unit.PrimaryPart then
						local distance = (unit.PrimaryPart.Position - position).Magnitude
						if distance <= 30 then
							local humanoid = unit:FindFirstChildOfClass("Humanoid")
							if humanoid and humanoid.Health < humanoid.MaxHealth then
								local healAmount = humanoid.MaxHealth * 0.3
								humanoid.Health = math.min(humanoid.Health + healAmount, humanoid.MaxHealth)

								-- Update attribute if it exists
								local currentHealth = unit:GetAttribute("CurrentHealth")
								if currentHealth then
									unit:SetAttribute("CurrentHealth", humanoid.Health)
								end

								healedCount += 1
							end
						end
					end
				end
			end

			AbilityDebug:info(`Healing Aura healed {healedCount} units`)

			local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if remoteEvents then
				local gameEvent = remoteEvents:FindFirstChild("GameEvent")
				if gameEvent and gameEvent:IsA("RemoteEvent") then
					gameEvent:FireClient(player, "AbilityUsed", {
						abilityId = "Heal",
						message = `Healed {healedCount} troops!`,
					})
				end
			end
		end,
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function AbilityManager.useAbility(player: Player, abilityId: string): boolean
	local ability = ABILITIES[abilityId]
	if not ability then
		AbilityDebug:warn(`Unknown ability: {abilityId}`)
		return false
	end

	-- Check cooldown
	local currentTime = tick()
	local playerCooldowns = PlayerAbilityCooldowns[player.UserId]
	if playerCooldowns and playerCooldowns[abilityId] then
		if currentTime < playerCooldowns[abilityId] then
			local remaining = math.ceil(playerCooldowns[abilityId] - currentTime)
			AbilityDebug:info(`Ability {abilityId} on cooldown for {player.Name} ({remaining}s remaining)`)

			-- Notify client
			local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if remoteEvents then
				local gameEvent = remoteEvents:FindFirstChild("GameEvent")
				if gameEvent and gameEvent:IsA("RemoteEvent") then
					gameEvent:FireClient(player, "AbilityCooldown", {
						abilityId = abilityId,
						remaining = remaining,
					})
				end
			end
			return false
		end
	end

	-- Get player's character (King)
	local character = player.Character
	if not character or not character.PrimaryPart then
		AbilityDebug:warn(`No character for {player.Name}`)
		return false
	end

	-- Use ability
	ability.effect(player, character)

	-- Set cooldown
	if not PlayerAbilityCooldowns[player.UserId] then
		PlayerAbilityCooldowns[player.UserId] = {}
	end
	PlayerAbilityCooldowns[player.UserId][abilityId] = currentTime + ability.cooldown

	AbilityDebug:info(`{player.Name} used ability: {ability.name}`)
	return true
end

function AbilityManager.getAbilities(): { [string]: Ability }
	return ABILITIES
end

function AbilityManager.getAbilityCooldown(player: Player, abilityId: string): number
	local currentTime = tick()
	local playerCooldowns = PlayerAbilityCooldowns[player.UserId]

	if not playerCooldowns or not playerCooldowns[abilityId] then
		return 0
	end

	local remaining = playerCooldowns[abilityId] - currentTime
	return math.max(0, remaining)
end

function AbilityManager.getAllCooldowns(player: Player): { [string]: number }
	local cooldowns = {}
	for abilityId, _ in pairs(ABILITIES) do
		cooldowns[abilityId] = AbilityManager.getAbilityCooldown(player, abilityId)
	end
	return cooldowns
end

function AbilityManager.init()
	AbilityDebug:info("AbilityManager initialized", {
		abilitiesCount = #ABILITIES,
	})
end

return AbilityManager
