--!strict
-- TaxSystem: Calculates player taxes

local TaxSystem = {}

function TaxSystem.calculateTaxes(player: Player)
    local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
    local TaxManager = require(script.Parent.Parent.Managers.TaxManager)
    local playerData = PlayerManager.get(player)
    local taxInfo = TaxManager.get(player)

    if playerData and taxInfo then
        local population = #playerData.Units -- Simple population count
        local taxRate = taxInfo.taxRate
        local taxes = math.floor(population * taxRate)
        return taxes
    end

    return 0
end

return TaxSystem