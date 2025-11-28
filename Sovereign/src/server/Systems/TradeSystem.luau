--!strict
-- TradeSystem: Handles periodic price updates

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TradeManager = require(script.Parent.Parent.Managers.TradeManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local TradeSystemDebug = DebugManager.createChannel("TradeSystem", false)

local TradeSystem = {}

-- Price update interval (in seconds)
local PRICE_UPDATE_INTERVAL = 30 -- Update prices every 30 seconds

-- Update prices for a player
local function updatePrices(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Update market prices
	TradeManager.updatePrices(player)
end

-- Initialize the trade system
function TradeSystem.init()
	-- Update prices periodically for all players
	task.spawn(function()
		while true do
			task.wait(PRICE_UPDATE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				updatePrices(player)
			end
		end
	end)

	TradeSystemDebug:info(`TradeSystem initialized - updating prices every {PRICE_UPDATE_INTERVAL} seconds`)
end

return TradeSystem
