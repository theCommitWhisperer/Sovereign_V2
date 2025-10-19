-- This module defines all the configurable settings available in the game lobby.
-- The lobby UI is built dynamically from this configuration, so adding, removing,
-- or changing a setting here will automatically update the UI.

local LobbySettings = {
	-- Settings that appear on the left panel, related to the map
	MapSettings = {
		{ id = "randomEvents", label = "Random Events", type = "toggle", defaultValue = true },
		{
			id = "resourceDensity",
			label = "Resource Density",
			type = "cycle",
			options = { "Scarce", "Standard", "Abundant" },
			defaultValue = "Standard",
		},
		{
			id = "wildlifeHostility",
			label = "Wildlife Hostility",
			type = "cycle",
			options = { "Peaceful", "Defensive", "Aggressive" },
			defaultValue = "Peaceful",
		},
		{ id = "vikingRaids", label = "Viking Raids", type = "toggle", defaultValue = false },
	},

	-- Settings related to starting conditions
	StartingResources = {
		{
			id = "startingGold",
			label = "Gold",
			type = "cycle",
			options = { "Low", "Standard", "High" },
			defaultValue = "Standard",
		},
		{
			id = "startingTroops",
			label = "Troops",
			type = "cycle",
			options = { "None", "Low", "Standard", "High" },
			defaultValue = "Standard",
		},
		{
			id = "startingResources",
			label = "Resources",
			type = "cycle",
			options = { "Low", "Standard", "High" },
			defaultValue = "Standard",
		},
		{
			id = "startingFood",
			label = "Food",
			type = "cycle",
			options = { "Low", "Standard", "High" },
			defaultValue = "Standard",
		},
		{
			id = "startingWeapons",
			label = "Weapons",
			type = "cycle",
			options = { "None", "Bronze", "Iron", "Steel" },
			defaultValue = "Bronze",
		},
		{
			id = "honor",
			label = "Honor",
			type = "cycle",
			options = { "Low", "Standard", "High" },
			defaultValue = "Standard",
		},
		{
			id = "rank",
			label = "Rank",
			type = "cycle",
			options = { "Knight", "Baron", "Duke", "King" },
			defaultValue = "Knight",
		},
	},

	-- Settings that modify core gameplay mechanics
	GameplayModifiers = {
		{ id = "legendsMode", label = "Legends Mode", type = "toggle", defaultValue = false },
		{ id = "unitMorale", label = "Unit Morale", type = "toggle", defaultValue = true },
		{
			id = "victoryCondition",
			label = "Victory Condition",
			type = "cycle",
			options = { "Conquest", "Wonder", "Score", "Regicide" },
			defaultValue = "Conquest",
		},
	},

	-- Settings that affect game speed and economy
	PacingAndEconomy = {
		{
			id = "peaceTime",
			label = "Peace Time",
			type = "cycle",
			options = { "None", "5 minutes", "10 minutes", "20 minutes" },
			defaultValue = "10 minutes",
		},
		{
			id = "gameSpeed",
			label = "Game Speed",
			type = "cycle",
			options = { "Slow", "Normal", "Fast" },
			defaultValue = "Normal",
		},
		{ id = "abilityToTrade", label = "Ability to Trade", type = "toggle", defaultValue = true },
	},
}

return LobbySettings
