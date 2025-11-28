--!strict
-- RevoltSystem.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RevoltManager = require(script.Parent.Parent.Managers.RevoltManager)

local RevoltSystem = {}

function RevoltSystem:init()
    -- Periodically update revolt risk for all players
    task.spawn(function()
        while true do
            task.wait(10) -- Update every 10 seconds
            for _, player in ipairs(Players:GetPlayers()) do
                RevoltManager.update(player)
            end
        end
    end)
end

function RevoltSystem:update(dt)
    -- not used
end

return RevoltSystem