--!strict
-- TaxManager: Manages player taxes

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local TaxSystem = require(script.Parent.Parent.Systems.TaxSystem)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local TaxDebug = DebugManager.createChannel("TaxManager", false)

local TaxManager = {}

local taxData = {}

function TaxManager.create(player: Player)
    local playerData = PlayerManager.get(player)
    if playerData then
        taxData[player.UserId] = {
            taxRate = 0.1, -- Initial tax rate (10%)
            lastCollected = tick(),
        }
        TaxDebug:info(`Created tax data for {player.Name}`)
    end
end

function TaxManager.get(player: Player)
    return taxData[player.UserId]
end

function TaxManager.setTaxRate(player: Player, newRate: number)
    local taxInfo = taxData[player.UserId]
    if taxInfo then
        taxInfo.taxRate = math.clamp(newRate, 0, 1) -- Clamp between 0% and 100%
        TaxDebug:info(`Set tax rate for {player.Name} to {newRate * 100}%`)
    end
end

function TaxManager.collectTaxes(player: Player)
    local playerData = PlayerManager.get(player)
    local taxInfo = taxData[player.UserId]

    if playerData and taxInfo then
        local taxes = TaxSystem.calculateTaxes(player)
        PlayerManager.addResources(player, { Gold = taxes })
        taxInfo.lastCollected = tick()

        TaxDebug:info(`Collected {taxes} gold from {player.Name}`)
    end
end

function TaxManager.init()
    Players.PlayerAdded:Connect(TaxManager.create)

    -- Periodically collect taxes for all players
    task.spawn(function()
        while true do
            task.wait(60) -- Collect taxes every 60 seconds
            for _, player in ipairs(Players:GetPlayers()) do
                TaxManager.collectTaxes(player)
            end
        end
    end)
end

return TaxManager