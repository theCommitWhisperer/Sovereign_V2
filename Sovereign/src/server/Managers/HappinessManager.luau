--!strict
-- HappinessManager: Manages player happiness and revolts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local WorkerManager = require(script.Parent.WorkerManager)
local UnitManager = require(script.Parent.UnitManager)
local HappinessSystem = require(script.Parent.Parent.Systems.HappinessSystem)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local HappinessDebug = DebugManager.createChannel("HappinessManager", false)

local HappinessManager = {}

local happinessData = {}

function HappinessManager.create(player: Player)
	local playerData = PlayerManager.get(player)
	if playerData then
		happinessData[player.UserId] = {
			happiness = 50, -- Initial happiness
			lastUpdated = tick(),
			revoltStage = 0, -- 0: No revolt, 1: Low happiness, 2: Very low happiness, 3: Open revolt
		}
		HappinessDebug:info(`Created happiness data for {player.Name}`)
	end
end

function HappinessManager.get(player: Player)
	return happinessData[player.UserId]
end

function HappinessManager.update(player: Player)
	local playerData = PlayerManager.get(player)
	local happinessInfo = happinessData[player.UserId]

	-- Only update happiness for players who are actually in a game
	if playerData and happinessInfo and playerData.GameState == "InGame" then
		local happinessScore = HappinessSystem.calculateHappiness(player)
		happinessInfo.happiness = happinessScore
		happinessInfo.lastUpdated = tick()

		-- Update player data
		playerData.Happiness = happinessScore

		-- Send update to client
		local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if RemoteEvents then
			local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
			if GameEvent then
				GameEvent:FireClient(player, "UpdateHappiness", { happiness = happinessScore })
			end
		end

		HappinessDebug:info(`Updated happiness for {player.Name} to {happinessScore}`)

		-- Check for revolt
		HappinessManager.checkForRevolt(player)
	end
end

function HappinessManager.checkForRevolt(player: Player)
	local happinessInfo = happinessData[player.UserId]
	if not happinessInfo then
		return
	end

	local currentStage = happinessInfo.revoltStage
	local newStage = 0

	if happinessInfo.happiness < 10 then
		newStage = 3
	elseif happinessInfo.happiness < 20 then
		newStage = 2
	elseif happinessInfo.happiness < 40 then
		newStage = 1
	end

	if newStage ~= currentStage then
		happinessInfo.revoltStage = newStage
		HappinessManager.triggerRevoltStage(player, newStage)
	end
end

function HappinessManager.triggerRevoltStage(player: Player, stage: number)
	local playerData = PlayerManager.get(player)
	if not playerData then
		return
	end

	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local GameEvent = RemoteEvents and RemoteEvents:FindFirstChild("GameEvent")

	if stage == 0 then
		HappinessDebug:info(`{player.Name} has recovered from low happiness.`)
		WorkerManager.setProductionModifier(player, 1.0) -- Restore production
		if GameEvent then
			GameEvent:FireClient(player, "RevoltEnded", {})
		end
	elseif stage == 1 then
		HappinessDebug:warn(`{player.Name} has low happiness! Production efficiency reduced.`)
		WorkerManager.setProductionModifier(player, 0.5) -- 50% production
		if GameEvent then
			GameEvent:FireClient(
				player,
				"RevoltStageChanged",
				{ stage = 1, message = "Production efficiency has dropped due to low happiness!" }
			)
		end
	elseif stage == 2 then
		HappinessDebug:warn(`{player.Name} has very low happiness! Production has halted.`)
		WorkerManager.setProductionModifier(player, 0) -- 0% production
		if GameEvent then
			GameEvent:FireClient(
				player,
				"RevoltStageChanged",
				{ stage = 2, message = "Production has halted due to very low happiness!" }
			)
		end
	elseif stage == 3 then
		HappinessDebug:error(`{player.Name} is in open revolt! Some units have become hostile.`)
		WorkerManager.setProductionModifier(player, 0) -- Production remains at 0%
		UnitManager.startRevolt(player, 0.25) -- 25% of units revolt
		if GameEvent then
			GameEvent:FireClient(
				player,
				"RevoltStageChanged",
				{ stage = 3, message = "A revolt has begun! Some of your people have taken up arms against you!" }
			)
		end
	end
end

function HappinessManager.init()
	Players.PlayerAdded:Connect(HappinessManager.create)

	-- Periodically update happiness for all players
	task.spawn(function()
		while true do
			task.wait(10) -- Update every 10 seconds
			for _, player in ipairs(Players:GetPlayers()) do
				HappinessManager.update(player)
			end
		end
	end)
end

return HappinessManager
