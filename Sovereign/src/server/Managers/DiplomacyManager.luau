--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local FactionManager = require(ServerScriptService.Managers.FactionManager)
local Knit = require(ReplicatedStorage.Packages.Knit)

local DiplomacyManager = Knit.CreateService {
    Name = "DiplomacyManager",
    Client = {},
}

-- Private

local _diplomatic_stances = {} -- { [factionId1] = { [factionId2] = stance } }

local STANCES = {
    WAR = "War",
    NEUTRAL = "Neutral",
    ALLY = "Ally",
}

-- Public

function DiplomacyManager:GetStance(factionId1, factionId2)
    if _diplomatic_stances[factionId1] then
        return _diplomatic_stances[factionId1][factionId2]
    end
    return nil
end

function DiplomacyManager:SetStance(factionId1, factionId2, stance)
    if not STANCES[stance] then
        warn("Invalid diplomatic stance:", stance)
        return
    end

    if not _diplomatic_stances[factionId1] then
        _diplomatic_stances[factionId1] = {}
    end
    _diplomatic_stances[factionId1][factionId2] = stance

    if not _diplomatic_stances[factionId2] then
        _diplomatic_stances[factionId2] = {}
    end
    _diplomatic_stances[factionId2][factionId1] = stance

    -- TODO: Fire a remote event to notify clients of the change
end

function DiplomacyManager:DeclareWar(factionId1, factionId2)
    self:SetStance(factionId1, factionId2, STANCES.WAR)
end

function DiplomacyManager:ProposeAlliance(factionId1, factionId2)
    -- For now, alliances are instant. In the future, this would send a request.
    self:SetStance(factionId1, factionId2, STANCES.ALLY)
end

function DiplomacyManager:MakePeace(factionId1, factionId2)
    -- For now, peace is instant. In the future, this would require agreement.
    self:SetStance(factionId1, factionId2, STANCES.NEUTRAL)
end

-- Knit Integration

function DiplomacyManager:KnitInit()
    -- Initialize diplomatic stances for all factions
    local factions = FactionManager:GetFactions()
    for i, faction1 in ipairs(factions) do
        for j, faction2 in ipairs(factions) do
            if i == j then
                -- A faction is an ally to itself
                self:SetStance(faction1.Id, faction2.Id, STANCES.ALLY)
            else
                -- All factions start as neutral to each other
                if not self:GetStance(faction1.Id, faction2.Id) then
                    self:SetStance(faction1.Id, faction2.Id, STANCES.NEUTRAL)
                end
            end
        end
    end

    print("DiplomacyManager initialized")
end

function DiplomacyManager:KnitStart()
    
end

return DiplomacyManager
