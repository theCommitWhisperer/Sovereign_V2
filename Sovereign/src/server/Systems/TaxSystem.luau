--!strict
-- TaxSystem: Calculates player tax income (Gold).
-- Income = population * taxRate * popularity multiplier.
-- Popularity (Happiness) gates income via EconomyConfig.TaxPopularityGate:
-- unhappy subjects pay reduced or no taxes, loyal ones pay a small bonus.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyConfig = require(ReplicatedStorage.Shared.GameData.EconomyConfig)

local TaxSystem = {}

function TaxSystem.calculateTaxes(player: Player): number
    local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
    local TaxManager = require(script.Parent.Parent.Managers.TaxManager)
    local PopulationManager = require(script.Parent.Parent.Managers.PopulationManager)

    local playerData = PlayerManager.get(player)
    local taxInfo = TaxManager.get(player)

    if playerData and taxInfo then
        -- Population = peasants (same count the dashboard shows), not army size
        local population = PopulationManager.getCurrentPopulation(player)
        local taxRate = taxInfo.taxRate

        -- A negative rate is the "Generous Gifts" policy: the crown pays its
        -- subjects to buy goodwill. It must NOT go through the popularity gate,
        -- which exists to model unwilling subjects withholding tax -- applying
        -- it to a gift would mean the more unpopular you are, the less you are
        -- allowed to spend fixing it, which is exactly backwards.
        if taxRate < 0 then
            return math.floor(population * taxRate)
        end

        -- Popularity gate: happiness drives how much of the levy is actually paid
        local happiness = playerData.Happiness or 50
        local popularityMultiplier = EconomyConfig.getTaxPopularityMultiplier(happiness)

        return math.floor(population * taxRate * popularityMultiplier)
    end

    return 0
end

return TaxSystem
