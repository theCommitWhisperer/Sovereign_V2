--!strict
-- TeamLayoutsData: the selectable team arrangements for a match.
--
-- WHY LAYOUTS ARE DATA
-- --------------------
-- "Customizable -- 1v1v1v1, 1v3, 2v2 etc." means the arrangement has to be a
-- lobby SETTING, not a hardcoded assumption. Today every player is their own
-- faction at war with everyone else, which is only the 1v1v1v1 case; there is
-- no representation of "these two are allied" anywhere in the lobby.
--
-- A layout is just a list of team sizes. Everything else -- how many slots the
-- lobby shows, which faction each player gets, who is allied with whom -- is
-- derived from that list, so adding 2v1v1 is one table entry rather than a code
-- change in the lobby, FactionManager and the victory check.
--
-- FactionManager already models arbitrary relationships between factions
-- (setRelationship / areEnemies), so alliances need no new combat concept: a
-- team is a set of factions marked Allied with each other and Enemy with the
-- rest.

local TeamLayoutsData = {}

export type Layout = {
	id: string,
	label: string, -- shown in the lobby, e.g. "2v2"
	description: string,
	-- One entry per team, each the number of slots on that team. { 2, 2 } is
	-- 2v2; { 1, 1, 1, 1 } is a four-way free-for-all; { 1, 3 } is one player
	-- against three.
	teams: { number },
	-- Asymmetric layouts hand one side a numerical disadvantage on purpose, so
	-- the lobby can warn rather than let someone pick it by accident.
	asymmetric: boolean?,
	-- Grouping for the picker: "Free for all" or "Teams". Every-team-of-one is
	-- a different KIND of match from allied play, and the dropdown reads far
	-- better split than as one flat list of ten.
	category: string,
}

local LAYOUTS: { [string]: Layout } = {}
local ORDER: { string } = {}

local function define(layout: Layout)
	LAYOUTS[layout.id] = layout
	table.insert(ORDER, layout.id)
end

define({
	id = "FFA4",
	category = "Free for all",
	label = "1v1v1v1",
	description = "Four-way free-for-all. Everyone against everyone.",
	teams = { 1, 1, 1, 1 },
})

define({
	id = "FFA3",
	category = "Free for all",
	label = "1v1v1",
	description = "Three-way free-for-all.",
	teams = { 1, 1, 1 },
})

define({
	id = "DUEL",
	category = "Free for all",
	label = "1v1",
	description = "A duel.",
	teams = { 1, 1 },
})

define({
	id = "TEAM22",
	category = "Teams",
	label = "2v2",
	description = "Two allied pairs. Shared victory, allied vision, no friendly fire.",
	teams = { 2, 2 },
})

define({
	id = "TEAM31",
	category = "Teams",
	label = "3v1",
	description = "Three allies against one. The lone kingdom starts with a handicap bonus.",
	teams = { 3, 1 },
	asymmetric = true,
})

define({
	id = "TEAM211",
	category = "Teams",
	label = "2v1v1",
	description = "One allied pair against two lone kingdoms.",
	teams = { 2, 1, 1 },
	asymmetric = true,
})

-- Start at a duel and grow. A lobby that opens on 1v1v1v1 needs four bodies
-- before it means anything, so the first player sees a match they could
-- actually start; LobbyManager escalates this as humans arrive (see
-- escalateForPlayerCount below).
TeamLayoutsData.Default = "DUEL"

function TeamLayoutsData.get(id: string): Layout?
	return LAYOUTS[id]
end

function TeamLayoutsData.getOrDefault(id: string?): Layout
	return (id and LAYOUTS[id]) or LAYOUTS[TeamLayoutsData.Default]
end

--- Layout ids in display order.
function TeamLayoutsData.getOrder(): { string }
	return table.clone(ORDER)
end

--- Total slots a layout needs. This is what the lobby should size its roster
--- to, rather than the map's maxPlayers -- a 2v2 on a four-spawn map fills all
--- four, but a 1v1 only needs two.
function TeamLayoutsData.getSlotCount(id: string?): number
	local total = 0
	for _, size in TeamLayoutsData.getOrDefault(id).teams do
		total += size
	end
	return total
end

function TeamLayoutsData.getTeamCount(id: string?): number
	return #TeamLayoutsData.getOrDefault(id).teams
end

--- Which team a given slot index (1-based) belongs to. Slots are filled in
--- order, so with { 2, 2 } slots 1-2 are team 1 and slots 3-4 are team 2.
--- Returns nil when the index is past the end of the layout.
function TeamLayoutsData.teamForSlot(id: string?, slotIndex: number): number?
	local remaining = slotIndex
	for teamIndex, size in TeamLayoutsData.getOrDefault(id).teams do
		if remaining <= size then
			return teamIndex
		end
		remaining -= size
	end
	return nil
end

--- Slot indices belonging to a team, for rendering the roster grouped.
function TeamLayoutsData.slotsForTeam(id: string?, teamIndex: number): { number }
	local out: { number } = {}
	local slot = 0
	for i, size in TeamLayoutsData.getOrDefault(id).teams do
		for _ = 1, size do
			slot += 1
			if i == teamIndex then
				table.insert(out, slot)
			end
		end
	end
	return out
end

--- Only layouts the map can actually host. A 2v2 needs four spawns; offering it
--- on a two-spawn map would let a lobby start a match it cannot place.
function TeamLayoutsData.getPlayableOn(mapMaxPlayers: number): { string }
	local out: { string } = {}
	for _, id in ORDER do
		if TeamLayoutsData.getSlotCount(id) <= mapMaxPlayers then
			table.insert(out, id)
		end
	end
	return out
end

--- The smallest free-for-all layout that seats `humans`, or nil if none does.
---
--- Used to grow the default as players join: 1v1 -> 1v1v1 -> 1v1v1v1. Only
--- free-for-all layouts are considered, because escalating someone's explicitly
--- chosen 2v2 into a 3-way FFA would silently change the kind of match they
--- picked. Never shrinks -- a player leaving a 1v1v1 should not collapse the
--- lobby back to a duel underneath the remaining two.
function TeamLayoutsData.smallestFreeForAllFor(humans: number): string?
	local best, bestSlots = nil, math.huge
	for _, id in ORDER do
		local slots = TeamLayoutsData.getSlotCount(id)
		if TeamLayoutsData.isFreeForAll(id) and slots >= humans and slots < bestSlots then
			best, bestSlots = id, slots
		end
	end
	return best
end

--- Is this layout a genuine free-for-all (every team of size one)? Used to skip
--- alliance setup entirely, and to decide whether the UI should show team
--- grouping at all.
function TeamLayoutsData.isFreeForAll(id: string?): boolean
	for _, size in TeamLayoutsData.getOrDefault(id).teams do
		if size > 1 then
			return false
		end
	end
	return true
end

return TeamLayoutsData
