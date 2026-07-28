--!strict
-- FactionManager: Manages factions and their relationships.
--
-- Faction IDs are stable internal strings ("Kingdom", "Viking", ...). The
-- player-facing historical flavor lives in DISPLAY_NAMES / GameData.Factions —
-- change display names freely, never the IDs.

local FactionManager = {}

local factions = {}
local factionRelationships = {}

-- Player-facing names (pseudo-historical, Irish-focused medieval setting)
local DISPLAY_NAMES: { [string]: string } = {
	-- Player factions (one per map quadrant)
	Kingdom = "The High Kings of Tara", -- Irish High Kings (Brian Boru's heirs)
	Empire = "The Norman Lords", -- Norman knights and castle-builders
	Tribes = "The Highland Clans", -- Scottish highlanders
	IronLegion = "The Norse of Dublin", -- Viking settlers, master smiths
	-- NPC factions
	Viking = "Viking Raiders", -- longship raiders from the sea
	Rebel = "Irish Rebels", -- rebellious clans of the countryside
	Player = "Player",
}

function FactionManager.createFaction(factionName: string)
	if not factions[factionName] then
		factions[factionName] = {}
		factionRelationships[factionName] = {}
	end
end

-- Readable name for UI; falls back to the raw ID for unknown factions.
function FactionManager.getDisplayName(factionName: string): string
	return DISPLAY_NAMES[factionName] or factionName
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
	-- Create default NPC factions
	FactionManager.createFaction("Player")
	FactionManager.createFaction("Rebel") -- Irish rebel clans
	FactionManager.createFaction("Viking") -- Norse raiders from the sea

	-- Create multiplayer player factions (one per quadrant)
	FactionManager.createFaction("Kingdom") -- Quadrant 1 (NW) — High Kings of Tara
	FactionManager.createFaction("Empire") -- Quadrant 2 (NE) — Norman Lords
	FactionManager.createFaction("Tribes") -- Quadrant 3 (SW) — Highland Clans
	FactionManager.createFaction("IronLegion") -- Quadrant 4 (SE) — Norse of Dublin

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
