--!strict
-- Sovereign_V2/src/shared/DebugSystem/Manager/DebugManager.luau

-- A centralized utility for logging and debugging.
-- Inspired by the original Sovereign DebugManager.

local HttpService = game:GetService("HttpService")

type LogLevel = "ERROR" | "WARN" | "INFO" | "DEBUG"
local logLevels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 }

local DebugManager = {}
local debugEnabled = true
local currentLogLevel: number = logLevels.DEBUG

--[[
	Encodes a Luau table into a JSON string, safely handling Vector3.
	@param data table The table to encode.
	@return string The JSON string.
]]
local function customJsonEncode(data: { [string]: any }): string
	local sanitizedData = {}
	for k, v in pairs(data) do
		if typeof(v) == "Vector3" then
			sanitizedData[k] = string.format("Vector3(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
		else
			sanitizedData[k] = v
		end
	end
	return HttpService:JSONEncode(sanitizedData)
end

--[[
	Sets the current logging level. Messages below this level won't be printed.
	@param level LogLevel The desired log level ("ERROR", "WARN", "INFO", or "DEBUG").
]]
function DebugManager.setLogLevel(level: LogLevel)
	currentLogLevel = logLevels[level] or logLevels.INFO
end

--[[
	Internal logging function.
	@param system string The name of the system logging the message.
	@param level LogLevel The severity of the message.
	@param message string The message to log.
	@param data { [string]: any }? Optional data to include.
]]
function DebugManager.log(system: string, level: LogLevel, message: string, data: { [string]: any }?)
	if not debugEnabled or logLevels[level] > currentLogLevel then
		return
	end

	local timestamp = os.date("%H:%M:%S")
	local logMessage = `[{timestamp}] [{level}] [{system}]: {message}`

	if data then
		local success, result = pcall(customJsonEncode, data)
		if success then
			logMessage = `{logMessage} | Data: {result}`
		else
			logMessage = `{logMessage} | Data: (Table) {tostring(data)}`
		end
	end

	if level == "ERROR" then
		warn(logMessage)
	else
		print(logMessage)
	end
end

function DebugManager.error(system: string, message: string, data: { [string]: any }?)
	DebugManager.log(system, "ERROR", message, data)
end

function DebugManager.warn(system: string, message: string, data: { [string]: any }?)
	DebugManager.log(system, "WARN", message, data)
end

function DebugManager.info(system: string, message: string, data: { [string]: any }?)
	DebugManager.log(system, "INFO", message, data)
end

function DebugManager.debug(system: string, message: string, data: { [string]: any }?)
	DebugManager.log(system, "DEBUG", message, data)
end

return DebugManager
