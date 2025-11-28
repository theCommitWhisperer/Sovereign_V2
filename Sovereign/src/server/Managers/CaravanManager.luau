--!strict
-- CaravanManager: Manages NPC merchant caravans and trade routes

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerManager = require(script.Parent.PlayerManager)
local TradeManager = require(script.Parent.TradeManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local CaravanDebug = DebugManager.createChannel("CaravanManager", true)

local CaravanManager = {}

-- Track caravan data per player
local caravanData = {}

export type TradeRoute = {
	destination: string,
	distance: number, -- in game time (seconds)
	resources: { [string]: number }, -- What to trade
	profit: number, -- Expected gold profit
	risk: number, -- 0-1, chance of losing caravan to bandits
}

export type ActiveCaravan = {
	route: TradeRoute,
	startTime: number,
	arrivalTime: number,
	status: "traveling" | "arrived" | "lost",
}

export type CaravanData = {
	activeCaravans: { ActiveCaravan },
	completedTrades: number,
	totalProfit: number,
	caravansLost: number,
}

-- Available trade routes (Irish theme!)
local TRADE_ROUTES: { TradeRoute } = {
	{
		destination = "Dublin",
		distance = 60, -- 1 minute travel
		resources = { Ale = 20, Bread = 30 },
		profit = 50,
		risk = 0.1, -- 10% chance of loss
	},
	{
		destination = "Cork",
		distance = 90, -- 1.5 minutes
		resources = { Weapons = 5, Iron_Bars = 10 },
		profit = 80,
		risk = 0.15,
	},
	{
		destination = "Galway",
		distance = 75,
		resources = { Wood = 40, Stone = 30 },
		profit = 60,
		risk = 0.12,
	},
	{
		destination = "Limerick",
		distance = 120, -- 2 minutes
		resources = { Ale = 30, Weapons = 8, Bread = 40 },
		profit = 120,
		risk = 0.20, -- Higher risk for higher reward!
	},
	{
		destination = "Waterford",
		distance = 45,
		resources = { Food = 50 },
		profit = 35,
		risk = 0.08, -- Low risk, low reward
	},
}

-- Initialize caravan data for a player
function CaravanManager.create(player: Player)
	caravanData[player.UserId] = {
		activeCaravans = {},
		completedTrades = 0,
		totalProfit = 0,
		caravansLost = 0,
	}
	CaravanDebug:info(`Created caravan data for {player.Name}`)
end

-- Get caravan data for a player
function CaravanManager.get(player: Player): CaravanData?
	return caravanData[player.UserId]
end

-- Send a caravan on a trade route
function CaravanManager.sendCaravan(player: Player, routeIndex: number): boolean
	local playerData = PlayerManager.get(player)
	local data = caravanData[player.UserId]

	if not playerData or not data then
		return false
	end

	-- Get the route
	local route = TRADE_ROUTES[routeIndex]
	if not route then
		CaravanDebug:warn(`Invalid route index: {routeIndex}`)
		return false
	end

	-- Check if player has required resources
	for resource, amount in pairs(route.resources) do
		if (playerData.Resources[resource] or 0) < amount then
			CaravanDebug:warn(`{player.Name} lacks {resource} for caravan`)
			return false
		end
	end

	-- Check if player has Trading Post (required for caravans)
	local hasTradingPost = false
	for _, building in playerData.Buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			if buildingType == "Trading_Post" then
				hasTradingPost = true
				break
			end
		end
	end

	if not hasTradingPost then
		CaravanDebug:warn(`{player.Name} needs a Trading Post to send caravans`)
		return false
	end

	-- Deduct resources for the caravan
	PlayerManager.deductResources(player, route.resources)

	-- Create active caravan
	local currentTime = tick()
	local caravan: ActiveCaravan = {
		route = route,
		startTime = currentTime,
		arrivalTime = currentTime + route.distance,
		status = "traveling",
	}

	table.insert(data.activeCaravans, caravan)

	CaravanDebug:info(`{player.Name} sent caravan to {route.destination}`)

	-- Notify client
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
		if GameEvent then
			GameEvent:FireClient(player, "CaravanSent", {
				destination = route.destination,
				arrivalTime = route.distance,
				profit = route.profit,
				risk = route.risk,
			})
		end
	end

	return true
end

-- Update active caravans
function CaravanManager.update(player: Player)
	local data = caravanData[player.UserId]
	if not data then
		return
	end

	local currentTime = tick()

	for i = #data.activeCaravans, 1, -1 do
		local caravan = data.activeCaravans[i]

		if caravan.status == "traveling" and currentTime >= caravan.arrivalTime then
			-- Caravan has arrived! Roll for success/failure
			local success = math.random() > caravan.route.risk

			if success then
				-- SUCCESS! Deliver profit
				caravan.status = "arrived"
				data.completedTrades += 1
				data.totalProfit += caravan.route.profit

				PlayerManager.addResources(player, { Gold = caravan.route.profit })

				CaravanDebug:info(
					`{player.Name}'s caravan returned from {caravan.route.destination} with {caravan.route.profit} gold!`
				)

				-- Notify client
				local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
				if RemoteEvents then
					local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
					if GameEvent then
						GameEvent:FireClient(player, "CaravanReturned", {
							destination = caravan.route.destination,
							profit = caravan.route.profit,
							success = true,
						})
					end
				end
			else
				-- FAILURE! Caravan lost to bandits!
				caravan.status = "lost"
				data.caravansLost += 1

				CaravanDebug:warn(`{player.Name}'s caravan to {caravan.route.destination} was lost to bandits!`)

				-- Notify client
				local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
				if RemoteEvents then
					local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
					if GameEvent then
						GameEvent:FireClient(player, "CaravanLost", {
							destination = caravan.route.destination,
							message = "Your caravan was attacked by bandits and lost!",
						})
					end
				end
			end

			-- Remove caravan after processing
			table.remove(data.activeCaravans, i)
		end
	end
end

-- Get available trade routes for UI
function CaravanManager.getAvailableRoutes(): { TradeRoute }
	return TRADE_ROUTES
end

-- Get active caravans for a player
function CaravanManager.getActiveCaravans(player: Player): { ActiveCaravan }
	local data = caravanData[player.UserId]
	if not data then
		return {}
	end

	return data.activeCaravans
end

-- Initialize the caravan system
function CaravanManager.init()
	Players.PlayerAdded:Connect(CaravanManager.create)

	CaravanDebug:info("CaravanManager initialized")
end

return CaravanManager
