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

-- Derived from the policy table rather than hardcoded, so adding a more
-- generous policy cannot silently get clamped away.
local MIN_TAX_RATE = 0
for _, policy in EconomyConfig.TaxPolicies do
	if policy.rate < MIN_TAX_RATE then
		MIN_TAX_RATE = policy.rate
	end
end

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
        -- Lower bound is negative to allow the "Generous Gifts" policy, where the
        -- crown PAYS its subjects to buy popularity back. Clamping at 0 silently
        -- turned that policy into "No Tax": the UI showed -5%, the player picked
        -- it, and nothing happened.
        taxInfo.taxRate = math.clamp(newRate, MIN_TAX_RATE, 1)
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

        if taxes < 0 then
            -- "Generous Gifts": the crown pays out. Cap the payment at the gold
            -- actually held so a treasury cannot be driven negative -- every
            -- affordability check in the game assumes resources are >= 0.
            local available = playerData.Resources.Gold or 0
            local payout = math.min(available, -taxes)
            if payout > 0 then
                PlayerManager.deductResources(player, { Gold = payout })
            end
            TaxDebug:info(`Paid {payout} gold in gifts to {player.Name}'s subjects`)
        else
            PlayerManager.addResources(player, { Gold = taxes })
            TaxDebug:info(`Collected {taxes} gold from {player.Name}`)
        end

        taxInfo.lastCollected = tick()
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