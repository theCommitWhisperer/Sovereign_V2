--!strict
-- HappinessSystem: Calculates player happiness

local HappinessSystem = {}

function HappinessSystem.calculateHappiness(player: Player)
    local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
    local TaxManager = require(script.Parent.Parent.Managers.TaxManager)
    local ConsumptionManager = require(script.Parent.Parent.Managers.ConsumptionManager)
    local PopulationManager = require(script.Parent.Parent.Managers.PopulationManager)
    local SeasonManager = require(script.Parent.Parent.Managers.SeasonManager)

    local playerData = PlayerManager.get(player)
    local taxInfo = TaxManager.get(player)

    if playerData and playerData.Resources and taxInfo then
        local food = playerData.Resources.Food or 0
        local taxRate = taxInfo.taxRate
        local happiness = 50

        -- Food factor (improved with more granularity)
        if food > 200 then
            happiness = happiness + 25 -- Abundant food
        elseif food > 100 then
            happiness = happiness + 15 -- Good food supply
        elseif food > 50 then
            happiness = happiness + 5 -- Adequate food
        elseif food < 10 then
            happiness = happiness - 30 -- Critical food shortage
        elseif food < 25 then
            happiness = happiness - 15 -- Low food
        end

        -- Starvation factor (SEVERE penalty)
        local isStarving = ConsumptionManager.isStarving(player)
        if isStarving then
            local starvationDuration = ConsumptionManager.getStarvationDuration(player)

            -- Progressive starvation penalties
            if starvationDuration > 120 then
                happiness = happiness - 50 -- Severe starvation (2+ minutes)
            elseif starvationDuration > 60 then
                happiness = happiness - 35 -- Major starvation (1+ minute)
            else
                happiness = happiness - 20 -- Beginning starvation
            end
        end

        -- Overcrowding factor (housing shortage)
        local isOvercrowded = PopulationManager.isOvercrowded(player)
        if isOvercrowded then
            happiness = happiness - 25 -- No housing available
        end

        -- Tax factor
        if taxRate > 0.5 then
            happiness = happiness - 30
        elseif taxRate > 0.2 then
            happiness = happiness - 15
        end

        -- Seasonal factor
        local seasonalModifier = SeasonManager.getHappinessModifier(player)
        happiness = happiness + seasonalModifier

        -- Luxury goods factor (Bread and Ale boost happiness!)
        local bread = playerData.Resources.Bread or 0
        local ale = playerData.Resources.Ale or 0

        if bread > 50 then
            happiness = happiness + 10 -- Fresh bread makes people happy!
        elseif bread > 20 then
            happiness = happiness + 5
        end

        if ale > 50 then
            happiness = happiness + 15 -- Irish folk love their ale!
        elseif ale > 20 then
            happiness = happiness + 8
        end

        return math.clamp(happiness, 0, 100)
    end

    return 50
end

return HappinessSystem