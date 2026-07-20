--!strict
-- CombatTypes: Shared type definitions for the combat v2 engine.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameData = require(ReplicatedStorage.Shared.GameData)
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)

export type Stance = "March" | "Attack" | "Defend" | "Skirmish"

export type CombatUnit = {
	model: Model,
	unitData: GameData.UnitData,
	owner: number,
	unitType: string,
	health: number,
	maxHealth: number,
	attackDamage: number,
	attackSpeed: number,
	attackRange: number,
	armor: number,
	morale: number,
	stance: Stance,
	targetModel: Model?, -- unit OR building model
	formation: string?,
	lastAttackTime: number,
	isCharging: boolean,
	faction: string,

	-- Irish special abilities (legacy fields kept for compatibility)
	celticFuryActive: boolean,
	lastWarCryTime: number,
	inShieldWall: boolean,
	shieldWallAllies: { Model },

	-- v2 fields
	profile: CombatConfig.UnitCombatProfile,
	attackType: CombatConfig.AttackType,
	inFormationCohesion: boolean,
	stunnedUntil: number,
	lastAbilityTimes: { [string]: number },
	berserkActive: boolean,
	battleSongMult: number, -- damage multiplier granted by a nearby Bard
	battleSongUntil: number, -- expiry timestamp for battleSongMult
	ambushSpentOn: Model?, -- Ambush first-strike tracking
	damageDealt: number, -- lifetime stats (used by sandbox reports)
	kills: number,
	lastScanTime: number, -- idle target-scan LOD throttle
	scanJitter: number, -- per-unit scan desync so armies don't retarget in lockstep
	slotAngle: number, -- stable ring-slot angle for surrounding targets
	guardPost: Vector3?, -- Defend stance: position the unit holds/returns to
	retreatUntil: number, -- Skirmish stance: melee hit-and-run backoff timer
}

export type CombatBuilding = {
	model: Model,
	owner: number,
	buildingType: string,
	faction: string,
	health: number,
	maxHealth: number,
}

return {}
