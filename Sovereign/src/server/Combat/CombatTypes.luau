--!strict
-- CombatTypes: Shared type definitions for the combat v2 engine.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameData = require(ReplicatedStorage.Shared.GameData)
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)

export type Stance = "March" | "Attack" | "Defend" | "Skirmish"

-- ═══════════════════════════════════════════════════════════════════════════
-- HERO COMBAT STATE
-- ═══════════════════════════════════════════════════════════════════════════
--
-- HeroCombat owns these tables (keyed by UserId) but hangs a reference off the
-- player's CombatUnit as `heroState`. That matters because the damage funnel
-- (CombatService.applyDamageToUnit) only has a CombatUnit in hand — without the
-- back-reference it would need a Players:GetPlayerByUserId lookup on every
-- single hit taken by the hero, in the middle of a battle.
--
-- Every timing field is an ABSOLUTE os.clock() timestamp, never a countdown.
-- That is deliberate: this codebase has repeatedly shipped bugs where a
-- task.delay fired after the state it was cleaning up had already been replaced
-- (see the `stateToken` guard in HeroCombat). Absolute expiries are evaluated
-- lazily on the next request and cannot go stale.

export type HeroActionState = "Idle" | "Windup" | "Active" | "Recovery" | "Blocking" | "Dodging" | "Staggered"

export type HeroState = {
	userId: number,
	character: Model,

	state: HeroActionState,
	-- Monotonic. Incremented on EVERY state entry. A delayed callback captures
	-- the token it was scheduled under and no-ops if the token has moved on.
	stateToken: number,
	stateExpiresAt: number, -- when `state` lapses back to Idle if nothing else happens

	comboIndex: number, -- 0 = no chain in progress; 1..#lightCombo otherwise
	comboExpiresAt: number, -- chain resets to 0 once os.clock() passes this
	nextActionAt: number, -- global action lockout (windup+active+recovery)

	blocking: boolean,
	blockStartedAt: number,
	blockAim: Vector3, -- the flat facing the shield covers (client-reported, validated)

	dodgeUntil: number, -- dodge movement/animation window
	invulnUntil: number, -- i-frames; the damage funnel checks THIS, not dodgeUntil
	dodgeReadyAt: number,

	riposteUntil: number, -- a successful parry opens a free, boosted light attack

	rangedReadyAt: number,

	stamina: number,
	lastStaminaSpend: number,
	-- Stamina regen is integrated lazily (dt since the last time anything asked
	-- about this hero) rather than on a Heartbeat, so an idle hero costs zero
	-- CPU. Without this snapshot the "recompute from lastStaminaSpend" shortcut
	-- would compound and refill the bar instantly.
	lastRefreshAt: number,

	-- Per-action tuning. Arena and the normal game pass different fighter stats;
	-- everything else comes from CombatConfig.Hero.
	maxHealth: number,
}

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

	-- ── Player-driven fighters ────────────────────────────────────────────
	-- Set by CombatService.registerPlayerFighter. Previously this was assigned
	-- dynamically and read back through `(x :: any).playerControlled`, which
	-- meant a typo in the field name would have silently disabled the "the AI
	-- must never drive the Lord" guard in updateUnit. Declared so the analyser
	-- catches that.
	playerControlled: boolean?,
	-- Back-reference to the hero state machine's table. nil for every AI unit.
	heroState: HeroState?,
	-- The attack type that produced the damage currently being applied, when it
	-- differs from the profile's. The hero's profile says "Melee" (he is a
	-- Gallowglass under the hood) so a BOW kill used to be scored as a Lord
	-- MELEE kill and paid 2.0x Glory instead of 0.5x. Set immediately before
	-- applyDamageToUnit and cleared immediately after — there is no yield in
	-- between, so it cannot leak across attacks.
	killCreditAttackType: CombatConfig.AttackType?,
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
