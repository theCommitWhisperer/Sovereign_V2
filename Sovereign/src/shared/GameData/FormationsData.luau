--!strict
-- FormationsData: the formation shapes and their combat bonuses.
--
-- WHY THIS IS SHARED AND NOT LOCAL TO FormationManager
-- ---------------------------------------------------
-- This table used to be a `local FORMATIONS` inside
-- server/Managers/FormationManager.luau, which meant the UI physically could
-- not read it -- a client module cannot require a server one. The army panel
-- needs each formation's bonuses, minimum unit count and description in order
-- to tell the player what picking it actually DOES, and the only alternative
-- was re-typing all ten entries in the UI where they would immediately drift
-- from the real numbers.
--
-- Same reasoning as BuildingSpec/BuildingCatalog: the UI derives its text from
-- the one authoritative table rather than carrying its own copy.

local FormationsData = {
	ShieldWall = {
		-- Defensive formation, strong against frontal attacks
		shape = "line",
		rows = 2,
		spacing = 4,
		bonuses = {
			attack = 0.8,
			defense = 1.5,
			speed = 0.7,
			morale = 1.1,
		},
		minUnits = 4,
		description = "Defensive line formation with shields locked",
	},
	Wedge = {
		-- Offensive formation for breaking enemy lines
		shape = "triangle",
		rows = 3,
		spacing = 4, -- >= body width (3) so units fit their slots
		bonuses = {
			attack = 1.3,
			defense = 0.9,
			speed = 1.1,
			morale = 1.2,
		},
		minUnits = 5,
		description = "Triangular charge formation",
	},
	Circle = {
		-- All-around defense, good against cavalry
		shape = "circle",
		rows = 1,
		spacing = 4, -- >= body width (3) so units fit their slots
		bonuses = {
			attack = 0.9,
			defense = 1.3,
			speed = 0.5,
			morale = 1.0,
		},
		minUnits = 6,
		description = "Circular defense against surrounding enemies",
	},
	Schiltron = {
		-- Scottish pike formation (included for Irish Gallowglass)
		shape = "square",
		rows = 3,
		spacing = 3.5, -- dense pike square, but still >= body width
		bonuses = {
			attack = 1.1,
			defense = 1.4,
			speed = 0.4,
			morale = 1.3,
		},
		minUnits = 9,
		description = "Dense pike square formation",
	},
	Loose = {
		-- Skirmish formation for mobility
		shape = "scatter",
		rows = 1,
		spacing = 8,
		bonuses = {
			attack = 1.0,
			defense = 0.7,
			speed = 1.3,
			morale = 0.9,
		},
		minUnits = 1,
		description = "Loose formation for mobility",
	},
	Line = {
		-- Basic line formation
		shape = "line",
		rows = 1,
		spacing = 6,  -- Increased from 5 to reduce collisions
		bonuses = {
			attack = 1.0,
			defense = 1.0,
			speed = 1.0,
			morale = 1.0,
		},
		minUnits = 2,
		description = "Standard battle line",
	},
	Phalanx = {
		-- Deep infantry block: narrow front, four ranks
		shape = "line",
		rows = 4,
		spacing = 4,
		bonuses = {
			attack = 1.1,
			defense = 1.3,
			speed = 0.6,
			morale = 1.2,
		},
		minUnits = 8,
		description = "Deep four-rank block for holding ground",
	},
	Crescent = {
		-- Enveloping arc, wings pushed forward
		shape = "arc",
		rows = 1,
		spacing = 4,
		bonuses = {
			attack = 1.2,
			defense = 1.0,
			speed = 0.9,
			morale = 1.1,
		},
		minUnits = 6,
		description = "Crescent with forward wings for envelopment",
	},
	Skirmish = {
		-- Staggered checkerboard, hard to hit with volleys
		shape = "staggered",
		rows = 3,
		spacing = 6,
		bonuses = {
			attack = 1.0,
			defense = 0.85,
			speed = 1.25,
			morale = 0.95,
		},
		minUnits = 4,
		description = "Staggered open order for skirmishers",
	},
	Column = {
		-- Marching formation - multiple files side-by-side
		shape = "column",
		rows = 1,
		spacing = 4,  -- Increased from 3 to reduce collisions
		bonuses = {
			attack = 0.8,
			defense = 0.8,
			speed = 1.2,
			morale = 1.0,
		},
		minUnits = 2,
		description = "Column formation for marching (2-4 files wide)",
	},
}

-- Display order for the picker. Roughly offensive -> defensive -> movement, so
-- the list reads as a spectrum rather than an alphabetical jumble.
FormationsData.Order = {
	"Line", "Wedge", "Phalanx", "ShieldWall", "Schiltron",
	"Circle", "Crescent", "Skirmish", "Loose", "Column",
}

function FormationsData.get(name: string)
	return (FormationsData :: any)[name]
end

return FormationsData
