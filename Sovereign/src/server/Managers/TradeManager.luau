--!strict
-- TradeManager: Manages trading, pricing, and market mechanics

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local SeasonManager = require(script.Parent.SeasonManager)
local ResourcesData = require(ReplicatedStorage.Shared.GameData.ResourcesData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local TradeDebug = DebugManager.createChannel("TradeManager", false)

local TradeManager = {}

-- Track trade data per player
local tradeData = {}

export type TradeData = {
	lastPriceUpdate: number,
	prices: { [string]: number }, -- Current market prices
	tradeVolume: { [string]: number }, -- Total traded this session
	-- Accumulated glut per resource: positive = oversupplied by this player's
	-- own selling, negative = they have been buying it up. Decays toward 0.
	pressure: { [string]: number },
}

-- Base prices come from the resource registry rather than a second hand-written
-- list. The old literal here covered nine resources, so the six goods missing
-- from it (Flour, Leather, Furniture, Coal, Manuscripts, Vellum...) could not be
-- priced or sold at all -- the far end of every long production chain was
-- unreachable.
local BASE_PRICES: { [string]: number } = ResourcesData.getBasePrices()

-- Price volatility factors
local PRICE_VOLATILITY = 0.15 -- Prices can fluctuate ±15%

-- ============================================================
-- MARKET GLUT
--
-- Flooding the market has to hurt, or "make a ton of money" collapses into a
-- single dominant strategy: build one chain, dump infinite volume at a fixed
-- price. The previous rule knocked 5% off the price per TRANSACTION regardless
-- of size, which actively rewarded selling 1000 units in one click.
--
-- Instead, every UNIT sold applies pressure, and pressure decays back toward
-- neutral over time. The consequence is that a chain has a sustainable income
-- RATE rather than a total, so running three different chains genuinely beats
-- running one chain three times as hard. That is the mechanic that makes the
-- production tree in BuildingsData worth having.
-- ============================================================
-- Tuned by simulation against a ~30 minute match, not picked by feel:
--   25 units sold   -> 95% of the undamaged price (casual selling is free)
--   100 units       -> 80%
--   200 units       -> 63%
--   500 units       -> 49%   (dumping is halved, not banned)
--   450 of one good vs 150 each of three  ->  diversifying earns 1.40x
--   a fully glutted market heals in ~10 minutes
local GLUT = {
	perUnitSold = 0.004, -- each unit sold pushes price down 0.4%
	perUnitBought = 0.004, -- buying pulls it back up (you are taking supply)
	-- Capped so pressure cannot grow past the point the floor already binds.
	-- Uncapped, a single 1000-unit dump banked enough pressure to keep that
	-- market dead for 100 minutes -- longer than the match.
	maxPressure = 0.6,
	recoveryPerTick = 0.12, -- 12% of the gap back to neutral each 30s price tick
	floor = 0.4, -- never worth less than 40% of base
	ceiling = 1.6, -- never worth more than 160% of base
}

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
		pressure = {},
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

		-- Glut recovers toward neutral, so a market you flooded becomes worth
		-- selling into again if you give it time.
		local pressure = data.pressure[resource] or 0
		pressure = pressure - pressure * GLUT.recoveryPerTick
		if math.abs(pressure) < 0.001 then
			pressure = 0
		end
		data.pressure[resource] = pressure

		local gluttFactor = math.clamp(1 - pressure, GLUT.floor, GLUT.ceiling)

		-- Calculate new price
		local targetPrice = basePrice * supplyFactor * seasonalFactor * randomFactor * gluttFactor

		-- Smooth price changes (don't jump instantly)
		local newPrice = currentPrice * 0.7 + targetPrice * 0.3

		-- Clamp relative to THIS resource's base, not a global 0.5-15 window.
		-- The old absolute clamp silently capped Manuscripts (base 10) and
		-- would have crushed any future high-value good against the ceiling.
		data.prices[resource] = math.clamp(newPrice, basePrice * GLUT.floor, basePrice * GLUT.ceiling)
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

	-- Buying takes supply off the market, which relieves glut. This is what
	-- makes buying back your own oversupplied good a legitimate (if lossy)
	-- way to reset a market you flooded.
	data.pressure[resource] = math.max(
		-GLUT.maxPressure,
		(data.pressure[resource] or 0) - GLUT.perUnitBought * amount
	)

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

	-- Revenue is integrated over the sale rather than taken at a single price,
	-- so dumping a big stack walks the price down as it goes. Selling 1000 in
	-- one click and selling 1000 one at a time now earn the same -- neither is
	-- a way to dodge the glut.
	local basePrice = BASE_PRICES[resource] or 1.0
	local pressure = data.pressure[resource] or 0
	local marketFee = 0.8 -- 20% market fee
	local unitPrice = TradeManager.getPrice(player, resource)

	local totalRevenue = 0
	for _ = 1, amount do
		local factor = math.clamp(1 - pressure, GLUT.floor, GLUT.ceiling)
		totalRevenue += unitPrice * factor * marketFee
		pressure = math.min(GLUT.maxPressure, pressure + GLUT.perUnitSold)
	end
	totalRevenue = math.floor(totalRevenue)
	data.pressure[resource] = pressure

	-- Reflect the new glut in the displayed price immediately, so the player
	-- can see what their own sale just did rather than finding out next tick.
	data.prices[resource] = math.clamp(
		basePrice * math.clamp(1 - pressure, GLUT.floor, GLUT.ceiling),
		basePrice * GLUT.floor,
		basePrice * GLUT.ceiling
	)

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
