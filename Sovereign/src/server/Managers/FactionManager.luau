--!strict
-- FactionManager: Manages factions and their relationships

local FactionManager = {}

local factions = {}
local factionRelationships = {}

function FactionManager.createFaction(factionName: string)
    if not factions[factionName] then
        factions[factionName] = {}
        factionRelationships[factionName] = {}
    end
end

function FactionManager.setRelationship(faction1: string, faction2: string, relationship: string)
    if factions[faction1] and factions[faction2] then
        factionRelationships[faction1][faction2] = relationship
        factionRelationships[faction2][faction1] = relationship
    end
end

function FactionManager.getRelationship(faction1: string, faction2: string): string
    if factionRelationships[faction1] and factionRelationships[faction1][faction2] then
        return factionRelationships[faction1][faction2]
    end
    return "Neutral" -- Default relationship
end

function FactionManager.areEnemies(faction1: string, faction2: string): boolean
    return FactionManager.getRelationship(faction1, faction2) == "Enemy"
end

function FactionManager.init()
    -- Create default factions
    FactionManager.createFaction("Player")
    FactionManager.createFaction("Rebel")
    FactionManager.createFaction("Viking")

    -- Set default relationships
    FactionManager.setRelationship("Player", "Rebel", "Enemy")
    FactionManager.setRelationship("Player", "Viking", "Enemy")
end

return FactionManager
