local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local channel = DebugManager.newChannel("Hello", "info")

return function()
	channel:info("Hello, world!")
end