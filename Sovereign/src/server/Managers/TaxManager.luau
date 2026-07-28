--!strict
-- TaxManager: Manages player taxes

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local TaxSystem = require(script.Parent.Parent.Systems.TaxSystem)
local EconomyConfig = require(ReplicatedStorage.Shared.GameData.EconomyConfig)
local GameSettings = require(ReplicatedStorage.Shared.GameSettings)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local TaxDebug = DebugManager.createChannel("TaxManager", false)

local TaxManager = {}

local taxData = {}

function TaxManager.create(player: Player)
    local playerData = PlayerManager.get(player)
    if playerData then
        taxData[player.UserId] = {
            taxRate = EconomyConfig.Tax.defaultRate,
            taxPolicy = EconomyConfig.DefaultTaxPolicy,
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

-- Set tax rate via a named policy preset from the Policies UI
-- (EconomyConfig.TaxPolicies). Returns false for unknown policies.
function TaxManager.setTaxPolicy(player: Player, policyName: string): boolean
    local taxInfo = taxData[player.UserId]
    local policy = EconomyConfig.TaxPolicies[policyName]
    if not taxInfo or not policy then
        return false
    end
    taxInfo.taxPolicy = policyName
    TaxManager.setTaxRate(player, policy.rate)
    return true
end

function TaxManager.getTaxPolicy(player: Player): string
    local taxInfo = taxData[player.UserId]
    return taxInfo and taxInfo.taxPolicy or EconomyConfig.DefaultTaxPolicy
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
end

function TaxManager.startLoop()
    task.spawn(function()
        while true do
            task.wait(GameSettings.waitInterval(EconomyConfig.Tax.cycleSeconds))
            for _, player in ipairs(Players:GetPlayers()) do
                TaxManager.collectTaxes(player)
            end
        end
    end)
end

return TaxManager