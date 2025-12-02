--!strict
-- LogManager: Saves console logs to files at the end of a session.

local Players = game:GetService("Players")
local DebugManager = require(game.ReplicatedStorage.src.shared.DebugManager)

local LOG_DIRECTORY = "logs"
local MAX_LOG_FILES = 3
local currentLogIndex = 1

-- Find the next log file index to use
local function getNextLogIndex(): number
	local highestIndex = 0
	local oldestTime = math.huge
	local oldestIndex = 1

	if not isfolder(LOG_DIRECTORY) then
		makefolder(LOG_DIRECTORY)
		return 1
	end

	local files = listfiles(LOG_DIRECTORY)
	if #files < MAX_LOG_FILES then
		-- If there are fewer than MAX_LOG_FILES, just use the next number.
		return #files + 1
	end

	-- Find the oldest file to overwrite
	for i = 1, #files do
		local file = files[i]
		local modifiedTime = getfilemodified(LOG_DIRECTORY .. "/" .. file)
		if modifiedTime < oldestTime then
			oldestTime = modifiedTime
			local num = tonumber(string.match(file, "%d+"))
			if num then
				oldestIndex = num
			end
		end
	end
	return oldestIndex
end


currentLogIndex = getNextLogIndex()

-- Function to save logs to a file
local function saveLogs()
	if not DebugManager.Enabled then return end

	local logHistory = DebugManager.getLogHistory()
	if #logHistory == 0 then
		print("LogManager: No logs to save.")
		return
	end

	local logContent = table.concat(logHistory, "\n")
	local fileName = string.format("%s/log%d.txt", LOG_DIRECTORY, currentLogIndex)

	local success, err = pcall(function()
		writefile(fileName, logContent)
	end)

	if success then
		print(string.format("LogManager: Successfully saved logs to %s", fileName))
	else
		warn(string.format("LogManager: Error saving logs to %s: %s", fileName, tostring(err)))
	end
end

-- Bind to game closing event
game:BindToClose(saveLogs)

-- Also save when the last player leaves (for server environments)
Players.PlayerRemoving:Connect(function()
	if #Players:GetPlayers() == 1 then
		saveLogs()
	end
end)

DebugManager.getChannel("LogManager"):info(string.format("LogManager initialized. Will save to log%d.txt", currentLogIndex))
