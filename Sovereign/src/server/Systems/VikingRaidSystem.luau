--!strict
-- VikingRaidSystem: Spawns periodic Viking raids that attack the player

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitManager = require(script.Parent.Parent.Managers.UnitManager)
local CombatManager = require(script.Parent.Parent.Managers.CombatManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local VikingDebug = DebugManager.createChannel("Viking", false)

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
	local peaceTimeSeconds = math.max(peaceTimeMinutes * 60, 60)
	activeRaids[playerId] = {
		playerId = playerId,
		enabled = true,
		peaceTimeSeconds = 30,
		raidIntervalSeconds = 180, -- Changed from 120 to 180 (3 minutes between raids)
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

	-- FIX: Set proper Y position - spawn ABOVE ground to prevent falling through
	spawnPosition = Vector3.new(spawnPosition.X, 20, spawnPosition.Z) -- Changed from keepPosition.Y to 20

	-- Scale difficulty with raid number - MORE CONSERVATIVE
	local vikingCount = math.min(3 + math.floor((raidNumber - 1) / 3), 15) -- Start with 3, add 1 every 3 raids, max 15
	local unitTypes = { "Viking" }

	-- For early raids, use weaker units
	if raidNumber == 1 then
		unitTypes = { "Viking" }
		vikingCount = 3 -- First raid is always 3 peasants
	elseif raidNumber <= 3 then
		unitTypes = { "Viking" }
		vikingCount = 3 + (raidNumber - 1) -- 3, 4, 5
	elseif raidNumber <= 5 then
		unitTypes = { "Viking" }
		vikingCount = 5 + (raidNumber - 3) -- 5, 6, 7
	end

	VikingDebug:info("Raid composition", {
		raidNumber = raidNumber,
		vikingCount = vikingCount,
		availableTypes = unitTypes,
	})

	-- Spawn Vikings
	local spawnedVikings = {}
	for i = 1, vikingCount do
		local unitType = unitTypes[math.random(1, #unitTypes)]
		local offset = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))

		local vikingSpawnPos = spawnPosition + offset
		vikingSpawnPos = Vector3.new(vikingSpawnPos.X, 20, vikingSpawnPos.Z)
		local viking = UnitManager.createUnit(unitType, VIKING_OWNER_ID, vikingSpawnPos, "Viking") -- Pass "Viking" faction
		-- FIX: Pass the Viking Faction explicitly ("Viking")
		if viking then
			table.insert(spawnedVikings, viking)

			-- Make Vikings slightly more aggressive (optional: modify stats)
			viking:SetAttribute("IsViking", true)
			viking:SetAttribute("TargetPlayerId", config.playerId)

			VikingDebug:info("Viking spawned", {
				type = unitType,
				position = viking.PrimaryPart and viking.PrimaryPart.Position or "no primary part",
			})
		else
			VikingDebug:warn("Failed to spawn Viking", { unitType = unitType })
		end
	end

	VikingDebug:info("Vikings spawned", {
		count = #spawnedVikings,
		position = spawnPosition,
	})

	config.nextRaidTime = tick() + config.raidIntervalSeconds
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
			local targetKeep = getPlayerKeepPosition(config.playerId)
			if targetKeep then
				-- Move towards Keep
				viking:SetAttribute("TargetPosition", targetKeep)
				viking:SetAttribute("IsMoving", true)

				VikingDebug:info("Viking targeting Keep", {
					viking = viking.Name,
					target = targetKeep,
				})
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
		if config.enabled and config.currentRaidNumber < 20 and currentTime >= config.nextRaidTime then
			spawnRaid(config)

			-- CRITICAL: Schedule the next raid AFTER this one
			config.nextRaidTime = currentTime + config.raidIntervalSeconds
		end
	end
end
-- Start update loop
RunService.Heartbeat:Connect(function(deltaTime)
	updateRaids(deltaTime)
end)

VikingDebug:info("Initialized")

return VikingRaidSystem
