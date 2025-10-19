--!strict
-- GameData: Central configuration for factions and game setup

local GameData = {}

-- Import data modules
GameData.Buildings = require(script.BuildingsData)
GameData.Units = require(script.UnitsData)

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
		Weapons: number,
		Iron_Bars: number,
	},
}

GameData.Factions = {
	Empire = {
		Name = "The Empire",
		Description = "A disciplined and technologically advanced faction.",
		PrimaryColor = Color3.fromRGB(218, 165, 32),
		SecondaryColor = Color3.fromRGB(128, 0, 0),
		SpawnPoint = CFrame.new(-100, 10, 0),
		BuildZoneRadius = 600,
		StartingPeasants = 4,
		StartingResources = {
			Wood = 500,
			Stone = 250,
			Gold = 1000,
			Weapons = 10,
			Iron_Bars = 20,
		},
	} :: FactionData,

	Kingdom = {
		Name = "The Kingdom",
		Description = "A noble and chivalrous kingdom.",
		PrimaryColor = Color3.fromRGB(0, 0, 255),
		SecondaryColor = Color3.fromRGB(192, 192, 192),
		SpawnPoint = CFrame.new(0, 10, 100),
		BuildZoneRadius = 600,
		StartingPeasants = 5,
		StartingResources = {
			Wood = 600,
			Stone = 200,
			Gold = 900,
			Weapons = 10,
			Iron_Bars = 20,
		},
	} :: FactionData,

	Tribes = {
		Name = "The Tribes",
		Description = "Hardy and resourceful tribes.",
		PrimaryColor = Color3.fromRGB(0, 128, 0),
		SecondaryColor = Color3.fromRGB(139, 69, 19),
		SpawnPoint = CFrame.new(100, 10, 0),
		BuildZoneRadius = 600,
		StartingPeasants = 6,
		StartingResources = {
			Wood = 700,
			Stone = 150,
			Gold = 800,
			Weapons = 10,
			Iron_Bars = 20,
		},
	} :: FactionData,

	IronLegion = {
		Name = "The Iron Legion",
		Description = "Masters of smithing and defense.",
		PrimaryColor = Color3.fromRGB(80, 80, 85),
		SecondaryColor = Color3.fromRGB(100, 100, 20),
		SpawnPoint = CFrame.new(0, 10, -200),
		BuildZoneRadius = 600,
		StartingPeasants = 5,
		StartingResources = {
			Wood = 400,
			Stone = 400,
			Gold = 1000,
			Weapons = 10,
			Iron_Bars = 20,
		},
	} :: FactionData,
}

return GameData
