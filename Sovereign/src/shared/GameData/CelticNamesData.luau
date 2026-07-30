--!strict
-- CelticNamesData: names for AI kingdoms.
--
-- "AI_Opponent1" tells a player nothing and belongs to no setting. These are
-- drawn from Irish and Scots-Gaelic myth and history, which is where Sovereign's
-- factions already live (the High Kings of Tara, the Norse of Dublin, the
-- Highland Clans, Sidhe Mounds, Clachans, Celtic Crosses).
--
-- Each entry is a ruler name plus the style they rule under, so an AI reads as a
-- kingdom rather than a slot: "Brian Bóruma, High King of Munster".
--
-- Names are handed out without repeats within a lobby (see takeName), because
-- two kingdoms called Brian is worse than a numbered opponent.

local CelticNamesData = {}

export type Ruler = {
	name: string,
	title: string,
}

-- Mixed real and mythic on purpose: the game's own faction names already blend
-- the two, and the mythic ones give the AI kingdoms a slightly larger-than-life
-- quality that suits an opponent.
local RULERS: { Ruler } = {
	{ name = "Brian Bóruma", title = "High King of Munster" },
	{ name = "Niall Noígíallach", title = "of the Nine Hostages" },
	{ name = "Medb", title = "Queen of Connacht" },
	{ name = "Conchobar mac Nessa", title = "King of Ulaid" },
	{ name = "Gráinne Ní Mháille", title = "of the Western Isles" },
	{ name = "Somerled", title = "Lord of the Isles" },
	{ name = "Aífe", title = "Warrior-Queen of Alba" },
	{ name = "Lugaid Loígde", title = "of the Érainn" },
	{ name = "Scáthach", title = "of the Shadowed Fort" },
	{ name = "Cormac mac Airt", title = "King at Tara" },
	{ name = "Macha", title = "of the Red Branch" },
	{ name = "Domnall Ua Néill", title = "of Cenél nEógain" },
	{ name = "Fionnghuala", title = "of the Sídhe Hills" },
	{ name = "Muirchertach", title = "of the Leather Cloaks" },
	{ name = "Bres", title = "the Beautiful, of the Fomoire" },
	{ name = "Eithne", title = "of Dún Ailinne" },
}

--- Every ruler, for a UI that wants to offer the list.
function CelticNamesData.getAll(): { Ruler }
	return RULERS
end

--- A display string: "Brian Bóruma, High King of Munster".
function CelticNamesData.fullName(ruler: Ruler): string
	return ("%s, %s"):format(ruler.name, ruler.title)
end

--- Picks a ruler name not already present in `taken`.
---
--- `taken` is a set of names already in use, so a lobby cannot end up with two
--- kingdoms of the same name. Falls back to a numbered kingdom only if every
--- ruler is somehow exhausted, which needs more AI than any map has spawns.
function CelticNamesData.takeName(taken: { [string]: boolean }): string
	-- Shuffled start so repeated lobbies don't always open with Brian.
	local offset = math.random(#RULERS)
	for i = 0, #RULERS - 1 do
		local ruler = RULERS[((offset + i - 1) % #RULERS) + 1]
		if not taken[ruler.name] then
			return ruler.name
		end
	end
	return "Unnamed Kingdom"
end

--- The title that goes with a name, or nil for a name that isn't ours (a
--- player-typed one, say).
function CelticNamesData.titleFor(name: string): string?
	for _, ruler in RULERS do
		if ruler.name == name then
			return ruler.title
		end
	end
	return nil
end

return CelticNamesData
