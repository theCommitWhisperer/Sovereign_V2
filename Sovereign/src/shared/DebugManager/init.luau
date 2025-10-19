--!strict
-- DebugManager: Centralized logging with channel support

local DebugManager = {}

export type LogLevel = "info" | "warn" | "error"

export type Channel = {
	name: string,
	enabled: boolean,
	info: (self: Channel, message: string, data: any?) -> (),
	warn: (self: Channel, message: string, data: any?) -> (),
	error: (self: Channel, message: string, data: any?) -> (),
}

local channels: { [string]: Channel } = {}

-- Format data for logging
local function formatData(data: any): string
	if data == nil then
		return ""
	end

	if typeof(data) == "table" then
		local parts = {}
		for key, value in pairs(data) do
			if typeof(value) == "Vector3" then
				table.insert(parts, `{key}: ({value.X}, {value.Y}, {value.Z})`)
			else
				table.insert(parts, `{key}: {tostring(value)}`)
			end
		end
		return " | " .. table.concat(parts, ", ")
	end

	return " | " .. tostring(data)
end

-- Log with a specific level
local function logWithLevel(level: LogLevel, channelName: string, message: string, data: any?)
	local prefix = if level == "error" then "❌" elseif level == "warn" then "⚠️" else "ℹ️"
	local formattedData = formatData(data)
	local fullMessage = `{prefix} [{channelName}] {message}{formattedData}`

	if level == "error" then
		error(fullMessage, 2)
	elseif level == "warn" then
		warn(fullMessage)
	else
		print(fullMessage)
	end
end

-- Create a new debug channel
function DebugManager.createChannel(name: string, enabled: boolean?): Channel
	if channels[name] then
		return channels[name]
	end

	local channel: Channel = {
		name = name,
		enabled = if enabled ~= nil then enabled else true,
		info = function(self: Channel, message: string, data: any?)
			if self.enabled then
				logWithLevel("info", self.name, message, data)
			end
		end,
		warn = function(self: Channel, message: string, data: any?)
			if self.enabled then
				logWithLevel("warn", self.name, message, data)
			end
		end,
		error = function(self: Channel, message: string, data: any?)
			if self.enabled then
				logWithLevel("error", self.name, message, data)
			end
		end,
	} :: Channel

	channels[name] = channel
	return channel
end

-- Enable or disable a channel
function DebugManager.setChannelEnabled(name: string, enabled: boolean)
	if channels[name] then
		channels[name].enabled = enabled
	end
end

-- Get a channel (creates if doesn't exist)
function DebugManager.getChannel(name: string): Channel
	if not channels[name] then
		return DebugManager.createChannel(name, true)
	end
	return channels[name]
end

-- Legacy support - default channel
function DebugManager.log(message: string, data: any?)
	logWithLevel("info", "General", message, data)
end

function DebugManager.info(message: string, data: any?)
	logWithLevel("info", "General", message, data)
end

function DebugManager.warn(message: string, data: any?)
	logWithLevel("warn", "General", message, data)
end

function DebugManager.error(message: string, data: any?)
	logWithLevel("error", "General", message, data)
end

return DebugManager
