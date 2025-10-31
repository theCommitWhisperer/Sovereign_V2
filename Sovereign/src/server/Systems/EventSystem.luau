--!strict
-- EventSystem: Handles periodic random event checks

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventManager = require(script.Parent.Parent.Managers.EventManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local EventSystemDebug = DebugManager.createChannel("EventSystem", true)

local EventSystem = {}

-- Event check interval (in seconds)
local EVENT_CHECK_INTERVAL = 45 -- Check for events every 45 seconds

-- Try to trigger events for a player
local function checkForEvents(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Try to trigger an event
	local eventTriggered = EventManager.tryTriggerEvent(player)

	if eventTriggered then
		EventSystemDebug:info(`Event triggered for {player.Name}`)
	end
end

-- Initialize the event system
function EventSystem.init()
	-- Check for events periodically for all players
	task.spawn(function()
		while true do
			task.wait(EVENT_CHECK_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				checkForEvents(player)
			end
		end
	end)

	EventSystemDebug:info(`EventSystem initialized - checking for events every {EVENT_CHECK_INTERVAL} seconds`)
end

return EventSystem
