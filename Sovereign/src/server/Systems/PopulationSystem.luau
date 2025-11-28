--!strict
-- PopulationSystem: Handles periodic population growth checks

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PopulationManager = require(script.Parent.Parent.Managers.PopulationManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local PopulationSystemDebug = DebugManager.createChannel("PopulationSystem", false)

local PopulationSystem = {}

-- Track last growth attempt per player
local lastGrowthAttempt = {}

-- Check if a player should grow their population
local function checkPopulationGrowth(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	local userId = player.UserId
	local currentTime = tick()

	-- Initialize if first check
	if not lastGrowthAttempt[userId] then
		lastGrowthAttempt[userId] = currentTime
		return
	end

	-- Get growth rate (seconds per new peasant)
	local growthRate = PopulationManager.getGrowthRate(player)

	-- No growth if conditions aren't met
	if growthRate == 0 then
		PopulationSystemDebug:info(`{player.Name} cannot grow population (conditions not met)`)
		lastGrowthAttempt[userId] = currentTime
		return
	end

	-- Check if enough time has passed for growth
	local timeSinceLastGrowth = currentTime - lastGrowthAttempt[userId]

	if timeSinceLastGrowth >= growthRate then
		-- Attempt to grow population
		local success = PopulationManager.tryGrowPopulation(player)

		if success then
			PopulationSystemDebug:info(`{player.Name} population grew! New peasant spawned.`)
			lastGrowthAttempt[userId] = currentTime

			-- Send notification to client
			local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if RemoteEvents then
				local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
				if GameEvent then
					GameEvent:FireClient(player, "PopulationGrew", {
						message = "Your population has grown! A new peasant has arrived.",
					})
				end
			end
		else
			PopulationSystemDebug:warn(`{player.Name} failed to grow population`)
		end
	end
end

-- Initialize the population growth system
function PopulationSystem.init()
	-- Check population growth every 10 seconds for all players
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in ipairs(Players:GetPlayers()) do
				checkPopulationGrowth(player)
			end
		end
	end)

	PopulationSystemDebug:info("PopulationSystem initialized - checking growth every 10 seconds")
end

return PopulationSystem
