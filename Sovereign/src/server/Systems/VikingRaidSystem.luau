--!strict
-- VikingRaidSystem: Spawns periodic Viking raids that attack the player

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitManager = require(script.Parent.Parent.Managers.UnitManager)
local CombatManager = require(script.Parent.Parent.Managers.CombatManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local VikingDebug = DebugManager.createChannel("Viking", true)

local VikingRaidSystem = {}

-- Active raid configurations per player
type RaidConfig = {
	playerId: number,
	enabled: boolean,
	peaceTimeSeconds: number,
	raidIntervalSeconds: number,
	nextRaidTime: number,
	currentRaidNumber: number,
}

local activeRaids: { [number]: RaidConfig } = {}

-- Viking unit owner ID (use a special ID for AI Vikings)
local VIKING_OWNER_ID = 1000000

-- Enable Viking raids for a player
function VikingRaidSystem.enableRaids(playerId: number, peaceTimeMinutes: number)
	local peaceTimeSeconds = peaceTimeMinutes * 60

	activeRaids[playerId] = {
		playerId = playerId,
		enabled = true,
		peaceTimeSeconds = peaceTimeSeconds,
		raidIntervalSeconds = 120, -- Raid every 2 minutes after peace time
		nextRaidTime = tick() + peaceTimeSeconds,
		currentRaidNumber = 0,
	}

	VikingDebug:info("Viking Raids enabled", {
		playerId = playerId,
		peaceTimeMinutes = peaceTimeMinutes,
		firstRaidIn = peaceTimeSeconds,
	})
end

-- Disable Viking raids for a player
function VikingRaidSystem.disableRaids(playerId: number)
	if activeRaids[playerId] then
		activeRaids[playerId].enabled = false
		VikingDebug:info("Viking Raids disabled", { playerId = playerId })
	end
end

-- Get player's Keep position (spawn point)
local function getPlayerKeepPosition(playerId: number): Vector3?
	local buildingsFolder = workspace:FindFirstChild("Buildings")
	if not buildingsFolder then
		return nil
	end

	-- Find the player's Keep
	for _, building in buildingsFolder:GetChildren() do
		if building:GetAttribute("BuildingType") == "Keep" and building:GetAttribute("Owner") == playerId then
			return building.Position
		end
	end

	return nil
end

-- Spawn a Viking raid
local function spawnRaid(config: RaidConfig)
	config.currentRaidNumber += 1
	local raidNumber = config.currentRaidNumber

	VikingDebug:info("Spawning Viking Raid", {
		playerId = config.playerId,
		raidNumber = raidNumber,
	})

	-- Get player's Keep position to spawn near
	local keepPosition = getPlayerKeepPosition(config.playerId)
	if not keepPosition then
		VikingDebug:warn("Could not find Keep for player", { playerId = config.playerId })
		return
	end

	-- Spawn Vikings at a random location around the player
	local angle = math.random() * math.pi * 2
	local distance = 80 + math.random(-20, 20) -- 60-100 studs away
	local spawnOffset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	local spawnPosition = keepPosition + spawnOffset

	-- Scale difficulty with raid number
	local vikingCount = 3 + math.floor(raidNumber / 2) -- Start with 3, increase by 1 every 2 raids
	local unitTypes = { "Peasant", "Spearman", "Archer" }

	-- For early raids, use weaker units
	if raidNumber <= 2 then
		unitTypes = { "Peasant" }
	elseif raidNumber <= 4 then
		unitTypes = { "Peasant", "Spearman" }
	end

	VikingDebug:info("Raid composition", {
		vikingCount = vikingCount,
		availableTypes = unitTypes,
	})

	-- Spawn Vikings
	local spawnedVikings = {}
	for i = 1, vikingCount do
		local unitType = unitTypes[math.random(1, #unitTypes)]
		local offset = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))

		local viking = UnitManager.createUnit(unitType, VIKING_OWNER_ID, spawnPosition + offset)
		if viking then
			table.insert(spawnedVikings, viking)

			-- Make Vikings slightly more aggressive (optional: modify stats)
			viking:SetAttribute("IsViking", true)
			viking:SetAttribute("TargetPlayerId", config.playerId)
		end
	end

	VikingDebug:info("Vikings spawned", {
		count = #spawnedVikings,
		position = spawnPosition,
	})

	-- Notify player
	local player = game.Players:GetPlayerByUserId(config.playerId)
	if player then
		local RemoteEvents = game.ReplicatedStorage:FindFirstChild("RemoteEvents")
		if RemoteEvents then
			local gameEvent = RemoteEvents:FindFirstChild("GameEvent")
			if gameEvent then
				gameEvent:FireClient(player, "VikingRaid", {
					raidNumber = raidNumber,
					vikingCount = #spawnedVikings,
					position = spawnPosition,
				})
			end
		end
	end

	-- Make Vikings attack the player's Keep
	task.wait(1) -- Give them a moment to spawn
	for _, viking in spawnedVikings do
		if viking and viking.Parent then
			local keepPosition = getPlayerKeepPosition(config.playerId)
			if keepPosition then
				-- Move towards Keep
				viking:SetAttribute("TargetPosition", keepPosition)
				viking:SetAttribute("IsMoving", true)
			end
		end
	end

	-- Schedule next raid
	config.nextRaidTime = tick() + config.raidIntervalSeconds
end

-- Update raid system
local function updateRaids(deltaTime: number)
	local currentTime = tick()

	for playerId, config in activeRaids do
		if config.enabled and currentTime >= config.nextRaidTime then
			spawnRaid(config)
		end
	end
end

-- Start update loop
RunService.Heartbeat:Connect(function(deltaTime)
	updateRaids(deltaTime)
end)

VikingDebug:info("Initialized")

return VikingRaidSystem
