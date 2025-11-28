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

	-- Create multiplayer player factions (one per quadrant)
	FactionManager.createFaction("Kingdom") -- Quadrant 1 (NW)
	FactionManager.createFaction("Empire") -- Quadrant 2 (NE)
	FactionManager.createFaction("Tribes") -- Quadrant 3 (SW)
	FactionManager.createFaction("IronLegion") -- Quadrant 4 (SE)

	-- Set default NPC relationships
	FactionManager.setRelationship("Player", "Rebel", "Enemy")
	FactionManager.setRelationship("Player", "Viking", "Enemy")

	-- Set multiplayer PvP relationships - all player factions are enemies
	local playerFactions = { "Kingdom", "Empire", "Tribes", "IronLegion" }
	for i = 1, #playerFactions do
		for j = i + 1, #playerFactions do
			FactionManager.setRelationship(playerFactions[i], playerFactions[j], "Enemy")
		end
	end

	-- Set player factions vs NPCs
	for _, faction in ipairs(playerFactions) do
		FactionManager.setRelationship(faction, "Rebel", "Enemy")
		FactionManager.setRelationship(faction, "Viking", "Enemy")
	end
end

return FactionManager
