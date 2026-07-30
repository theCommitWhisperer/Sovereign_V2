--!strict
-- GameData: Central configuration for factions and game setup

local GameData = {}

-- Import data modules from subfolders
local UnitsData = require(script.UnitsData)
GameData.Buildings = require(script.BuildingsData)
GameData.Units = UnitsData
-- Animation asset ids per rig, keyed by each model's `AnimSet` attribute.
GameData.UnitAnimations = require(script.UnitAnimationsData)

-- Re-export the flat unit schema so consumers can write GameData.UnitData
export type UnitData = UnitsData.UnitData

export type FactionData = {
	Name: string,
	Description: string,
	PrimaryColor: Color3,
	SecondaryColor: Color3,
	SpawnPoint: CFrame,
	BuildZoneRadius: number,
	StartingPeasants: number,
	StartingResources: {
		Wood: number,
		Stone: number,
		Gold: number,
		Food: number,
		Weapons: number,
		Iron_Bars: number,
	},
}

-- Playable factions. Table KEYS ("Kingdom", "Empire", "Tribes", "IronLegion")
-- are stable internal IDs used by FactionManager, SpawnManager and PlayerData —
-- never rename them. Name/Description are the player-facing historical flavor.
GameData.Factions = {
	Empire = {
		Name = "The Norman Lords",
		Description = "Armored Norman conquerors — disciplined knights and castle-builders carving out new fiefs in Ireland.",
		PrimaryColor = Color3.fromRGB(218, 165, 32),
		SecondaryColor = Color3.fromRGB(128, 0, 0),
		SpawnPoint = CFrame.new(-100, 10, 0),
		BuildZoneRadius = 600,
		StartingPeasants = 4,
		StartingResources = {
			Wood = 500,
			Stone = 250,
			Gold = 1000,
			Food = 200,
			Weapons = 10,
			Iron_Bars = 20,
		},
	} :: FactionData,

	Kingdom = {
		Name = "The High Kings of Tara",
		Description = "Heirs of Brian Boru — Irish High Kings ruling from the Hill of Tara with clansmen and gallowglass.",
		PrimaryColor = Color3.fromRGB(0, 0, 255),
		SecondaryColor = Color3.fromRGB(192, 192, 192),
		SpawnPoint = CFrame.new(0, 10, 100),
		BuildZoneRadius = 600,
		StartingPeasants = 5,
		StartingResources = {
			Wood = 600,
			Stone = 200,
			Gold = 900,
			Food = 300,
			Weapons = 10,
			Iron_Bars = 20,
		},
	} :: FactionData,

	Tribes = {
		Name = "The Highland Clans",
		Description = "Hardy Scottish highlanders — proud clansmen of the glens, fierce in the charge.",
		PrimaryColor = Color3.fromRGB(0, 128, 0),
		SecondaryColor = Color3.fromRGB(139, 69, 19),
		SpawnPoint = CFrame.new(100, 10, 0),
		BuildZoneRadius = 600,
		StartingPeasants = 6,
		StartingResources = {
			Wood = 700,
			Stone = 150,
			Gold = 800,
			Food = 400,
			Weapons = 10,
			Iron_Bars = 20,
		},
	} :: FactionData,

	IronLegion = {
		Name = "The Norse of Dublin",
		Description = "Viking sea-kings settled at Dublin — master smiths, raiders and traders of the northern seas.",
		PrimaryColor = Color3.fromRGB(80, 80, 85),
		SecondaryColor = Color3.fromRGB(100, 100, 20),
		SpawnPoint = CFrame.new(0, 10, -200),
		BuildZoneRadius = 600,
		StartingPeasants = 5,
		StartingResources = {
			Wood = 400,
			Stone = 400,
			Gold = 1000,
			Food = 250,
			Weapons = 10,
			Iron_Bars = 20,
		},
	} :: FactionData,
}
return GameData
