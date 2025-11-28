--!strict
-- TradeManager: Manages trading, pricing, and market mechanics

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local SeasonManager = require(script.Parent.SeasonManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local TradeDebug = DebugManager.createChannel("TradeManager", true)

local TradeManager = {}

-- Track trade data per player
local tradeData = {}

export type TradeData = {
	lastPriceUpdate: number,
	prices: { [string]: number }, -- Current market prices
	tradeVolume: { [string]: number }, -- Total traded this session
}

-- Base prices for each resource (in Gold)
local BASE_PRICES: { [string]: number } = {
	Wood = 1.0,
	Stone = 1.5,
	Gold = 1.0, -- Gold trades at 1:1 with itself
	Food = 0.8,
	Iron_Ore = 2.0,
	Iron_Bars = 4.0,
	Weapons = 8.0,
	Bread = 1.5,
	Ale = 2.0,
}

-- Price volatility factors
local PRICE_VOLATILITY = 0.15 -- Prices can fluctuate ±15%

-- Initialize trade data for a player
function TradeManager.create(player: Player)
	local initialPrices = {}
	for resource, basePrice in pairs(BASE_PRICES) do
		-- Start with slight random variation
		initialPrices[resource] = basePrice * (1 + (math.random() - 0.5) * 0.1)
	end

	tradeData[player.UserId] = {
		lastPriceUpdate = tick(),
		prices = initialPrices,
		tradeVolume = {},
	}
	TradeDebug:info(`Created trade data for {player.Name}`)
end

-- Get trade data for a player
function TradeManager.get(player: Player): TradeData?
	return tradeData[player.UserId]
end

-- Get current price for a resource
function TradeManager.getPrice(player: Player, resource: string): number
	local data = tradeData[player.UserId]
	if not data then
		return BASE_PRICES[resource] or 1.0
	end

	return data.prices[resource] or BASE_PRICES[resource] or 1.0
end

-- Update prices based on supply/demand and season
function TradeManager.updatePrices(player: Player)
	local data = tradeData[player.UserId]
	local playerData = PlayerManager.get(player)

	if not data or not playerData then
		return
	end

	-- Update prices based on player's current stockpile (supply/demand)
	for resource, basePrice in pairs(BASE_PRICES) do
		local currentStock = playerData.Resources[resource] or 0
		local currentPrice = data.prices[resource] or basePrice

		-- Calculate supply factor (more stock = lower price)
		local supplyFactor = 1.0
		if currentStock > 200 then
			supplyFactor = 0.7 -- Abundant supply, prices drop
		elseif currentStock > 100 then
			supplyFactor = 0.85
		elseif currentStock < 20 then
			supplyFactor = 1.5 -- Scarcity, prices rise!
		elseif currentStock < 50 then
			supplyFactor = 1.2
		end

		-- Seasonal adjustments
		local seasonalFactor = 1.0
		local currentSeason = SeasonManager.getCurrentSeason(player)

		if resource == "Food" or resource == "Bread" then
			if currentSeason == "Summer" then
				seasonalFactor = 0.8 -- Abundant harvest, cheap food
			elseif currentSeason == "Winter" then
				seasonalFactor = 1.4 -- Food scarce in winter
			end
		end

		if resource == "Wood" then
			if currentSeason == "Autumn" or currentSeason == "Winter" then
				seasonalFactor = 1.2 -- Wood more valuable for heating
			end
		end

		-- Random market fluctuation
		local randomFactor = 1 + (math.random() - 0.5) * PRICE_VOLATILITY

		-- Calculate new price
		local targetPrice = basePrice * supplyFactor * seasonalFactor * randomFactor

		-- Smooth price changes (don't jump instantly)
		local newPrice = currentPrice * 0.7 + targetPrice * 0.3

		data.prices[resource] = math.max(0.5, math.min(15, newPrice)) -- Clamp between 0.5 and 15 gold
	end

	data.lastPriceUpdate = tick()
	TradeDebug:info(`Updated prices for {player.Name}`)
end

-- Buy resources from market (spend gold, gain resource)
function TradeManager.buyResource(player: Player, resource: string, amount: number): boolean
	local playerData = PlayerManager.get(player)
	local data = tradeData[player.UserId]

	if not playerData or not data then
		return false
	end

	-- Calculate cost
	local pricePerUnit = TradeManager.getPrice(player, resource)
	local totalCost = math.floor(pricePerUnit * amount)

	-- Check if player can afford
	if (playerData.Resources.Gold or 0) < totalCost then
		TradeDebug:warn(`{player.Name} cannot afford {amount} {resource} (costs {totalCost} gold)`)
		return false
	end

	-- Execute trade
	PlayerManager.deductResources(player, { Gold = totalCost })
	PlayerManager.addResources(player, { [resource] = amount })

	-- Track trade volume
	data.tradeVolume[resource] = (data.tradeVolume[resource] or 0) + amount

	TradeDebug:info(`{player.Name} bought {amount} {resource} for {totalCost} gold`)

	-- Notify client
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
		if GameEvent then
			GameEvent:FireClient(player, "TradeCompleted", {
				type = "buy",
				resource = resource,
				amount = amount,
				cost = totalCost,
			})
		end
	end

	-- Update prices after trade (buying increases demand = higher prices)
	data.prices[resource] = (data.prices[resource] or BASE_PRICES[resource]) * 1.05

	return true
end

-- Sell resources to market (lose resource, gain gold)
function TradeManager.sellResource(player: Player, resource: string, amount: number): boolean
	local playerData = PlayerManager.get(player)
	local data = tradeData[player.UserId]

	if not playerData or not data then
		return false
	end

	-- Check if player has enough
	if (playerData.Resources[resource] or 0) < amount then
		TradeDebug:warn(`{player.Name} doesn't have {amount} {resource} to sell`)
		return false
	end

	-- Calculate revenue (selling gives slightly less than buying)
	local pricePerUnit = TradeManager.getPrice(player, resource) * 0.8 -- 20% market fee
	local totalRevenue = math.floor(pricePerUnit * amount)

	-- Execute trade
	PlayerManager.deductResources(player, { [resource] = amount })
	PlayerManager.addResources(player, { Gold = totalRevenue })

	-- Track trade volume
	data.tradeVolume[resource] = (data.tradeVolume[resource] or 0) + amount

	TradeDebug:info(`{player.Name} sold {amount} {resource} for {totalRevenue} gold`)

	-- Notify client
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
		if GameEvent then
			GameEvent:FireClient(player, "TradeCompleted", {
				type = "sell",
				resource = resource,
				amount = amount,
				revenue = totalRevenue,
			})
		end
	end

	-- Update prices after trade (selling increases supply = lower prices)
	data.prices[resource] = (data.prices[resource] or BASE_PRICES[resource]) * 0.95

	return true
end

-- Get all current prices for UI display
function TradeManager.getAllPrices(player: Player): { [string]: number }
	local data = tradeData[player.UserId]
	if not data then
		return BASE_PRICES
	end

	return data.prices
end

-- Check if player has access to market (has Market building)
function TradeManager.hasMarketAccess(player: Player): boolean
	local playerData = PlayerManager.get(player)
	if not playerData then
		return false
	end

	for _, building in playerData.Buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			if buildingType == "Market" or buildingType == "Trading_Post" then
				return true
			end
		end
	end

	return false
end

-- Initialize the trade system
function TradeManager.init()
	Players.PlayerAdded:Connect(TradeManager.create)

	TradeDebug:info("TradeManager initialized")
end

return TradeManager
