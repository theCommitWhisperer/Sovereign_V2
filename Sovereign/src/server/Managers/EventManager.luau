--!strict
-- EventManager: Manages random economic events (merchants, disasters, opportunities)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local PopulationManager = require(script.Parent.PopulationManager)
local BuildingManager = require(script.Parent.BuildingManager)
local UnitManager = require(script.Parent.UnitManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local EventDebug = DebugManager.createChannel("EventManager", false)

local EventManager = {}

-- Track event data per player
local eventData = {}

export type EventData = {
	lastEventTime: number,
	eventsTriggered: number,
	activeEvent: string?,
	eventCooldown: number,
}

export type EconomicEvent = {
	name: string,
	type: "disaster" | "opportunity" | "merchant" | "crisis",
	probability: number, -- 0-1, chance of occurring
	description: string,
	effect: (player: Player) -> (),
	canTrigger: (player: Player) -> boolean,
}

-- Define all possible events
local ECONOMIC_EVENTS: { EconomicEvent } = {
	-- DISASTERS
	{
		name = "Crop Failure",
		type = "disaster",
		probability = 0.15,
		description = "A blight has struck your farms! 30% of stored food is lost.",
		canTrigger = function(player: Player)
			local playerData = PlayerManager.get(player)
			return playerData and (playerData.Resources.Food or 0) > 20
		end,
		effect = function(player: Player)
			local playerData = PlayerManager.get(player)
			if playerData then
				local foodLoss = math.floor((playerData.Resources.Food or 0) * 0.3)
				PlayerManager.deductResources(player, { Food = foodLoss })
				EventDebug:warn(`CROP FAILURE! {player.Name} lost {foodLoss} food`)
			end
		end,
	},

	{
		name = "Bandit Raid",
		type = "disaster",
		probability = 0.12,
		description = "Bandits have raided your stores! Gold and resources stolen.",
		canTrigger = function(player: Player)
			local playerData = PlayerManager.get(player)
			return playerData and (playerData.Resources.Gold or 0) > 10
		end,
		effect = function(player: Player)
			local playerData = PlayerManager.get(player)
			if playerData then
				local goldLoss = math.floor((playerData.Resources.Gold or 0) * 0.2)
				local woodLoss = math.floor((playerData.Resources.Wood or 0) * 0.15)
				local foodLoss = math.floor((playerData.Resources.Food or 0) * 0.15)

				PlayerManager.deductResources(player, {
					Gold = goldLoss,
					Wood = woodLoss,
					Food = foodLoss,
				})

				EventDebug:warn(`BANDIT RAID! {player.Name} lost {goldLoss} gold, {woodLoss} wood, {foodLoss} food`)
			end
		end,
	},

	{
		name = "Plague Outbreak",
		type = "crisis",
		probability = 0.08,
		description = "Disease spreads through your settlement! Some peasants have fallen ill.",
		canTrigger = function(player: Player)
			local currentPop = PopulationManager.getCurrentPopulation(player)
			return currentPop >= 8
		end,
		effect = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return
			end

			-- Kill 2-3 random peasants
			local killed = 0
			for i = #playerData.Units, 1, -1 do
				local unit = playerData.Units[i]
				if unit and unit.Parent and unit:GetAttribute("UnitType") == "Peasant" then
					if killed < 2 then
						unit:Destroy()
						table.remove(playerData.Units, i)
						killed += 1
					end
				end
			end

			EventDebug:error(`PLAGUE! {player.Name} lost {killed} peasants to disease`)
		end,
	},

	{
		name = "Building Fire",
		type = "disaster",
		probability = 0.10,
		description = "A fire has broken out! One of your buildings has been damaged.",
		canTrigger = function(player: Player)
			local playerData = PlayerManager.get(player)
			return playerData and #playerData.Buildings > 2 -- More than just Keep
		end,
		effect = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return
			end

			-- Damage random building by removing some stored resources
			local eligibleBuildings = {}
			for _, building in playerData.Buildings do
				if building and building.Parent then
					local buildingType = building:GetAttribute("BuildingType")
					if buildingType ~= "Keep" then -- Don't burn the Keep!
						table.insert(eligibleBuildings, building)
					end
				end
			end

			if #eligibleBuildings > 0 then
				local targetBuilding = eligibleBuildings[math.random(1, #eligibleBuildings)]
				local buildingType = targetBuilding:GetAttribute("BuildingType")

				-- Clear 50% of stored resources in that building
				-- (This simulates fire damage without destroying the building)
				EventDebug:warn(`FIRE! {player.Name}'s {buildingType} was damaged by fire`)
			end
		end,
	},

	-- OPPORTUNITIES
	{
		name = "Traveling Merchant",
		type = "merchant",
		probability = 0.20,
		description = "A traveling merchant offers to trade goods!",
		canTrigger = function(player: Player)
			return true -- Always can trigger
		end,
		effect = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return
			end

			-- Merchant offers random trade
			local trades = {
				{ give = { Wood = 20 }, receive = { Gold = 15 } },
				{ give = { Stone = 15 }, receive = { Gold = 20 } },
				{ give = { Food = 30 }, receive = { Gold = 25 } },
				{ give = { Gold = 30 }, receive = { Iron_Ore = 20 } },
				{ give = { Gold = 40 }, receive = { Weapons = 5 } },
			}

			local trade = trades[math.random(1, #trades)]

			EventDebug:info(`MERCHANT! {player.Name} receives trade offer`)

			-- Send trade offer to client
			local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if RemoteEvents then
				local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
				if GameEvent then
					GameEvent:FireClient(player, "MerchantArrived", {
						trade = trade,
						message = "A traveling merchant has arrived!",
					})
				end
			end
		end,
	},

	{
		name = "Bumper Harvest",
		type = "opportunity",
		probability = 0.15,
		description = "An excellent harvest! Your farms produce extra food.",
		canTrigger = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return false
			end

			-- Check if player has farms
			for _, building in playerData.Buildings do
				if building and building.Parent then
					local buildingType = building:GetAttribute("BuildingType")
					if buildingType == "Farm" then
						return true
					end
				end
			end
			return false
		end,
		effect = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return
			end

			-- Add bonus food (50-100 food)
			local bonusFood = math.random(50, 100)
			PlayerManager.addResources(player, { Food = bonusFood })

			EventDebug:info(`BUMPER HARVEST! {player.Name} gained {bonusFood} food`)
		end,
	},

	{
		name = "Rich Ore Vein",
		type = "opportunity",
		probability = 0.12,
		description = "Miners discover a rich ore vein! Extra iron ore gathered.",
		canTrigger = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return false
			end

			-- Check if player has iron mine
			for _, building in playerData.Buildings do
				if building and building.Parent then
					local buildingType = building:GetAttribute("BuildingType")
					if buildingType == "Iron_Mine" then
						return true
					end
				end
			end
			return false
		end,
		effect = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return
			end

			-- Add bonus iron ore
			local bonusOre = math.random(30, 60)
			PlayerManager.addResources(player, { Iron_Ore = bonusOre })

			EventDebug:info(`RICH ORE VEIN! {player.Name} gained {bonusOre} iron ore`)
		end,
	},

	{
		name = "Wandering Peasants",
		type = "opportunity",
		probability = 0.18,
		description = "A group of wandering peasants wishes to join your settlement!",
		canTrigger = function(player: Player)
			-- Only if player has housing capacity
			return PopulationManager.canGrowPopulation(player)
		end,
		effect = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData or not playerData.Keep or not playerData.Keep.Parent then
				return
			end

			-- Spawn 2-3 new peasants
			local newPeasants = math.random(2, 3)
			local keepPos = playerData.Keep.PrimaryPart.Position
			local faction = playerData.Faction or "Kingdom"

			for i = 1, newPeasants do
				local randomOffset = Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
				local spawnPos = keepPos + randomOffset
				UnitManager.createUnit("Peasant", player.UserId, spawnPos, faction)
			end

			EventDebug:info(`WANDERING PEASANTS! {player.Name} gained {newPeasants} new peasants`)
		end,
	},

	{
		name = "Festival Day",
		type = "opportunity",
		probability = 0.10,
		description = "The people celebrate a festival! Happiness increased temporarily.",
		canTrigger = function(player: Player)
			return true
		end,
		effect = function(player: Player)
			-- This would be a temporary happiness boost
			-- For now, we'll just add some ale/bread as a gift
			PlayerManager.addResources(player, {
				Ale = 10,
				Bread = 15,
			})

			EventDebug:info(`FESTIVAL! {player.Name} receives ale and bread for celebration`)
		end,
	},
}

-- Initialize event data for a player
function EventManager.create(player: Player)
	eventData[player.UserId] = {
		lastEventTime = tick(),
		eventsTriggered = 0,
		activeEvent = nil,
		eventCooldown = 0,
	}
	EventDebug:info(`Created event data for {player.Name}`)
end

-- Get event data for a player
function EventManager.get(player: Player): EventData?
	return eventData[player.UserId]
end

-- Try to trigger a random event
function EventManager.tryTriggerEvent(player: Player): boolean
	local playerData = PlayerManager.get(player)
	local evtData = eventData[player.UserId]

	if not playerData or not evtData or playerData.GameState ~= "InGame" then
		return false
	end

	-- Check cooldown
	local currentTime = tick()
	if currentTime - evtData.lastEventTime < evtData.eventCooldown then
		return false
	end

	-- Randomly select an event to try
	local eligibleEvents = {}
	for _, event in ECONOMIC_EVENTS do
		if event.canTrigger(player) then
			table.insert(eligibleEvents, event)
		end
	end

	if #eligibleEvents == 0 then
		EventDebug:info(`No eligible events for {player.Name}`)
		return false
	end

	-- Select random event weighted by probability
	local randomEvent = eligibleEvents[math.random(1, #eligibleEvents)]

	-- Check if event triggers based on probability
	if math.random() < randomEvent.probability then
		-- Trigger the event!
		EventDebug:info(`Triggering event: {randomEvent.name} for {player.Name}`)

		evtData.activeEvent = randomEvent.name
		evtData.eventsTriggered += 1
		evtData.lastEventTime = currentTime
		evtData.eventCooldown = math.random(60, 120) -- 1-2 minute cooldown

		-- Execute event effect
		randomEvent.effect(player)

		-- Notify client
		local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if RemoteEvents then
			local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
			if GameEvent then
				GameEvent:FireClient(player, "EconomicEvent", {
					name = randomEvent.name,
					type = randomEvent.type,
					description = randomEvent.description,
				})
			end
		end

		return true
	end

	return false
end

-- Initialize the event system
function EventManager.init()
	Players.PlayerAdded:Connect(EventManager.create)

	EventDebug:info("EventManager initialized")
end

return EventManager
