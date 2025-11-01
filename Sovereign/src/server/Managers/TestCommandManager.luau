--!strict
-- TestCommandManager: Admin commands for testing economy systems

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local PopulationManager = require(script.Parent.PopulationManager)
local ConsumptionManager = require(script.Parent.ConsumptionManager)
local MaintenanceManager = require(script.Parent.MaintenanceManager)
local TaxManager = require(script.Parent.TaxManager)
local SeasonManager = require(script.Parent.SeasonManager)
local WeatherManager = require(script.Parent.WeatherManager)
local TradeManager = require(script.Parent.TradeManager)
local CaravanManager = require(script.Parent.CaravanManager)
local EventManager = require(script.Parent.EventManager)
local EconomyDashboardManager = require(script.Parent.EconomyDashboardManager)
local NotificationManager = require(script.Parent.NotificationManager)
local UnitManager = require(script.Parent.UnitManager)
local BuildingManager = require(script.Parent.BuildingManager)
local FogOfWarManager = require(script.Parent.FogOfWarManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local TestDebug = DebugManager.createChannel("TestCommands", true)

local TestCommandManager = {}

-- List of admin user IDs (add your Roblox user ID here!)
local ADMIN_USER_IDS = {
	8820940408, -- RiffetyRaff
	-- Add additional admin IDs below
}

-- Check if player is admin
local function isAdmin(player: Player): boolean
	return table.find(ADMIN_USER_IDS, player.UserId) ~= nil
end

-- Command: Add resources
local function cmdAddResources(player: Player, args: { string })
	if #args < 2 then
		NotificationManager.info(player, "Usage", "/addres [resource] [amount]")
		return
	end

	local resource = args[1]
	local amount = tonumber(args[2])

	if not amount then
		NotificationManager.warning(player, "Error", "Amount must be a number")
		return
	end

	PlayerManager.addResources(player, { [resource] = amount })
	NotificationManager.success(player, "Resources Added", `Added {amount} {resource}`)
	TestDebug:info(`{player.Name} added {amount} {resource}`)
end

-- Command: Set season
local function cmdSetSeason(player: Player, args: { string })
	if #args < 1 then
		NotificationManager.info(player, "Usage", "/season [Spring|Summer|Autumn|Winter]")
		return
	end

	local season = args[1]
	if season ~= "Spring" and season ~= "Summer" and season ~= "Autumn" and season ~= "Winter" then
		NotificationManager.warning(player, "Error", "Invalid season. Use: Spring, Summer, Autumn, or Winter")
		return
	end

	-- Force season change
	local seasonData = SeasonManager.get(player)
	if seasonData then
		seasonData.currentSeason = season :: any
		seasonData.seasonStartTime = tick()
		NotificationManager.success(player, "Season Changed", `Season set to {season}`)
		TestDebug:info(`{player.Name} changed season to {season}`)
	end
end

-- Command: Set weather
local function cmdSetWeather(player: Player, args: { string })
	if #args < 1 then
		NotificationManager.info(player, "Usage", "/weather [Clear|Rain|Drought|Storm]")
		return
	end

	local weather = args[1]
	if weather ~= "Clear" and weather ~= "Rain" and weather ~= "Drought" and weather ~= "Storm" then
		NotificationManager.warning(player, "Error", "Invalid weather. Use: Clear, Rain, Drought, or Storm")
		return
	end

	-- Force weather change
	local weatherData = WeatherManager.get(player)
	if weatherData then
		weatherData.currentWeather = weather :: any
		weatherData.weatherStartTime = tick()
		NotificationManager.success(player, "Weather Changed", `Weather set to {weather}`)
		TestDebug:info(`{player.Name} changed weather to {weather}`)
	end
end

-- Command: Trigger random event
local function cmdTriggerEvent(player: Player, args: { string })
	EventManager.tryTriggerEvent(player)
	NotificationManager.info(player, "Event Triggered", "Attempting to trigger random event...")
	TestDebug:info(`{player.Name} triggered random event`)
end

-- Command: Spawn peasants
local function cmdSpawnPeasants(player: Player, args: { string })
	local count = 5
	if #args >= 1 then
		count = tonumber(args[1]) or 5
	end

	local playerData = PlayerManager.get(player)
	if not playerData or not playerData.Keep or not playerData.Keep.Parent then
		NotificationManager.warning(player, "Error", "No Keep found")
		return
	end

	-- Get Keep position (handle both Model with PrimaryPart and single Part)
	local keepPos
	if playerData.Keep:IsA("Model") and playerData.Keep.PrimaryPart then
		keepPos = playerData.Keep.PrimaryPart.Position
	elseif playerData.Keep:IsA("BasePart") then
		keepPos = playerData.Keep.Position
	else
		NotificationManager.warning(player, "Error", "Keep has no valid position")
		return
	end

	local faction = playerData.Faction or "Kingdom"

	for i = 1, count do
		local randomOffset = Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
		local spawnPos = keepPos + randomOffset
		UnitManager.createUnit("Peasant", player.UserId, spawnPos, faction)
	end

	NotificationManager.success(player, "Peasants Spawned", `Spawned {count} peasants`)
	TestDebug:info(`{player.Name} spawned {count} peasants`)
end

-- Command: Show economy snapshot
local function cmdEconomyInfo(player: Player, args: { string })
	local snapshot = EconomyDashboardManager.getSnapshot(player)

	local message = `Economy Status: {snapshot.economyStatus} ({snapshot.economyHealth}/100)\n`
	message = message .. `Population: {snapshot.currentPopulation}/{snapshot.housingCapacity}\n`
	message = message .. `Food Consumption: {snapshot.foodConsumptionRate}/cycle\n`
	message = message .. `Season: {snapshot.currentSeason}, Weather: {snapshot.currentWeather}\n`
	message = message .. `Happiness: {snapshot.happiness}/100`

	NotificationManager.info(player, "Economy Info", message)
	TestDebug:info(`{player.Name} checked economy info`)
end

-- Command: Set tax rate
local function cmdSetTax(player: Player, args: { string })
	if #args < 1 then
		NotificationManager.info(player, "Usage", "/tax [0-100]")
		return
	end

	local taxPercent = tonumber(args[1])
	if not taxPercent or taxPercent < 0 or taxPercent > 100 then
		NotificationManager.warning(player, "Error", "Tax must be between 0 and 100")
		return
	end

	local taxData = TaxManager.get(player)
	if taxData then
		taxData.taxRate = taxPercent / 100
		NotificationManager.success(player, "Tax Set", `Tax rate set to {taxPercent}%`)
		TestDebug:info(`{player.Name} set tax to {taxPercent}%`)
	end
end

-- Command: Send test caravan
local function cmdTestCaravan(player: Player, args: { string })
	local routeIndex = 1
	if #args >= 1 then
		routeIndex = tonumber(args[1]) or 1
	end

	local success = CaravanManager.sendCaravan(player, routeIndex)
	if success then
		NotificationManager.success(player, "Caravan Sent", `Caravan sent on route {routeIndex}`)
	else
		NotificationManager.warning(player, "Failed", "Could not send caravan. Check requirements.")
	end
	TestDebug:info(`{player.Name} sent test caravan (route {routeIndex})`)
end

-- Command: Skip time (advance season/weather)
local function cmdSkipTime(player: Player, args: { string })
	-- Force season to advance
	SeasonManager.advanceSeason(player)
	-- Force weather to change
	WeatherManager.changeWeather(player)

	NotificationManager.success(player, "Time Skipped", "Advanced to next season and changed weather")
	TestDebug:info(`{player.Name} skipped time`)
end

-- Command: Test notifications
local function cmdTestNotify(player: Player, args: { string })
	NotificationManager.info(player, "Test Info", "This is an info notification")
	task.wait(1)
	NotificationManager.success(player, "Test Success", "This is a success notification")
	task.wait(1)
	NotificationManager.warning(player, "Test Warning", "This is a warning notification")
	task.wait(1)
	NotificationManager.alert(player, "Test Alert", "This is an alert notification")
	task.wait(1)
	NotificationManager.critical(player, "Test Critical", "This is a critical notification!")

	TestDebug:info(`{player.Name} tested notifications`)
end

-- Command: Toggle fog of war
local function cmdFogOfWar(player: Player, args: { string })
	if #args < 1 then
		local isEnabled = FogOfWarManager.isEnabled(player)
		NotificationManager.info(player, "Fog of War", `Fog of War is currently {isEnabled and "ON" or "OFF"}\nUsage: /fog [on|off]`)
		return
	end

	local mode = args[1]:lower()
	if mode == "on" then
		FogOfWarManager.toggle(player, true)
		NotificationManager.success(player, "Fog of War", "Fog of War enabled - You can only see units/buildings in vision range")
		TestDebug:info(`{player.Name} enabled fog of war`)
	elseif mode == "off" then
		FogOfWarManager.toggle(player, false)
		NotificationManager.warning(player, "Fog of War", "Fog of War disabled - You can see everything (admin mode)")
		TestDebug:info(`{player.Name} disabled fog of war`)
	else
		NotificationManager.warning(player, "Error", "Usage: /fog [on|off]")
	end
end

-- Command: Show all commands
local function cmdHelp(player: Player, args: { string })
	local helpText = [[
TEST COMMANDS:
/addres [resource] [amount] - Add resources
/season [Spring|Summer|Autumn|Winter] - Change season
/weather [Clear|Rain|Drought|Storm] - Change weather
/event - Trigger random event
/spawn [count] - Spawn peasants
/econinfo - Show economy info
/tax [0-100] - Set tax rate
/caravan [route 1-5] - Send test caravan
/skiptime - Advance season and weather
/testnotify - Test all notification types
/fog [on|off] - Toggle fog of war
/help - Show this help
]]

	NotificationManager.info(player, "Test Commands", helpText)
end

-- Command registry
local COMMANDS = {
	addres = cmdAddResources,
	season = cmdSetSeason,
	weather = cmdSetWeather,
	event = cmdTriggerEvent,
	spawn = cmdSpawnPeasants,
	econinfo = cmdEconomyInfo,
	tax = cmdSetTax,
	caravan = cmdTestCaravan,
	skiptime = cmdSkipTime,
	testnotify = cmdTestNotify,
	fog = cmdFogOfWar,
	help = cmdHelp,
}

-- Process a command
function TestCommandManager.processCommand(player: Player, commandText: string)
	-- Check admin
	if not isAdmin(player) then
		NotificationManager.warning(player, "Access Denied", "You are not an admin")
		return
	end

	-- Parse command
	local parts = string.split(commandText, " ")
	local command = parts[1]:lower()
	table.remove(parts, 1) -- Remove command from args

	-- Execute command
	local commandFunc = COMMANDS[command]
	if commandFunc then
		commandFunc(player, parts)
	else
		NotificationManager.warning(player, "Unknown Command", `Unknown command: {command}. Type /help for list.`)
	end
end

-- Initialize test command system
function TestCommandManager.init()
	-- Listen for test commands from client
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local GameEvent = RemoteEvents:WaitForChild("GameEvent")

	GameEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "TestCommand" and typeof(data) == "string" then
			TestCommandManager.processCommand(player, data)
		end
	end)

	TestDebug:info("TestCommandManager initialized")
	print("=== ECONOMY TEST COMMANDS ENABLED ===")
	print("Add your Roblox User ID to ADMIN_USER_IDS in TestCommandManager.luau")
	print("Then use /help in-game to see all test commands")
end

return TestCommandManager
