local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local ClientDebug = DebugManager.createChannel("Client", false) -- Corrected to be off by default

ClientDebug:info("Hello world, from client!")

require(script.Selection.SelectionManager)
require(script.Movement.MovementManager)
require(script.Combat.HealthBarManager)
