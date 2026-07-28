--!strict
-- CombatManager: Thin compatibility facade over the combat v2 engine.
--
-- The real implementation lives in server/Combat/:
--   CombatService     — core loop, targeting, engagement, siege
--   DamageResolver    — counter-matrix damage math (pure functions)
--   ProjectileSystem  — ranged combat with real flight time
--   AbilitySystem     — Celtic Fury, War Cry, Shield Wall + expanded roster
--   SpatialGrid       — proximity queries (replaces O(n²) scans)
--   CombatReplication — batched client VFX events
--   CombatSandbox     — /battle, /arena instant-test harness
--
-- This module preserves the legacy public API so GameManager, UnitManager and
-- other call sites don't need to change.

local Combat = script.Parent.Parent.Combat
local CombatService = require(Combat.CombatService)
local CombatSandbox = require(Combat.CombatSandbox)
local CombatTypes = require(Combat.CombatTypes)
local HeroCombat = require(Combat.HeroCombat)

export type Stance = CombatTypes.Stance
export type CombatUnit = CombatTypes.CombatUnit
export type HeroState = CombatTypes.HeroState
export type HeroActionState = CombatTypes.HeroActionState

local CombatManager = {}

-- ── Settings ────────────────────────────────────────────────────────────────

function CombatManager.setMoraleEnabled(enabled: boolean)
	CombatService.setMoraleEnabled(enabled)
end

function CombatManager.isMoraleEnabled(): boolean
	return CombatService.isMoraleEnabled()
end

-- ── Registration ────────────────────────────────────────────────────────────

function CombatManager.registerCombatUnit(unitModel: Model, combatUnit: any)
	CombatService.registerCombatUnit(unitModel, combatUnit)
end

function CombatManager.initializeCombatUnit(unitModel: Model, owner: Player)
	CombatService.initializeCombatUnit(unitModel, owner)
end

function CombatManager.registerBuilding(buildingModel: Model)
	CombatService.registerBuilding(buildingModel)
end

-- ── Orders ──────────────────────────────────────────────────────────────────

function CombatManager.setTarget(attackerModel: Model, targetModel: Model)
	CombatService.setTarget(attackerModel, targetModel)
end

function CombatManager.setStance(unitModel: Model, stance: Stance)
	CombatService.setStance(unitModel, stance)
end

-- Group march: passive stance + shared slowest speed. Call when the player
-- issues a plain move order to keep the group together.
function CombatManager.applyGroupMarch(units: { Model })
	CombatService.applyGroupMarch(units)
end

function CombatManager.clearTarget(unitModel: Model)
	CombatService.clearTarget(unitModel)
end

-- ── Queries ─────────────────────────────────────────────────────────────────

function CombatManager.getActiveCombatUnits(): { [Model]: CombatUnit }
	return CombatService.getActiveCombatUnits()
end

-- Subscribe to every combat-unit death server-wide (victim + optional killer
-- CombatUnit tables). Returns an unsubscribe function. Used by EliminationManager
-- for the AI Direct Slay hook (unitType == "King").
function CombatManager.onUnitKilled(listener: (victim: CombatUnit, killer: CombatUnit?) -> ()): () -> ()
	return CombatService.onUnitKilled(listener)
end

-- ── Player fighter (first-person combat) ─────────────────────────────────────

function CombatManager.registerPlayerFighter(character: Model, faction: string, ownerId: number, opts: any?)
	CombatService.registerPlayerFighter(character, faction, ownerId, opts)
end

function CombatManager.unregisterPlayerFighter(character: Model)
	CombatService.unregisterPlayerFighter(character)
end

function CombatManager.playerMeleeAttack(character: Model, aimDir: Vector3, range: number, arcCos: number, damage: number): number
	return CombatService.playerMeleeAttack(character, aimDir, range, arcCos, damage)
end

function CombatManager.playerRangedAttack(character: Model, aimDir: Vector3, maxRange: number, arcCos: number, damage: number, projectileKey: string): boolean
	return CombatService.playerRangedAttack(character, aimDir, maxRange, arcCos, damage, projectileKey)
end

-- ── Hero combo combat (third-person Lord) ───────────────────────────────────
--
-- The full action set: 3-hit light chain, heavy, block/parry, dodge, bow. All
-- server-authoritative — see server/Combat/HeroCombat.luau. GameManager and
-- ArenaMode both dispatch through this facade so the two modes share one
-- implementation instead of maintaining a copy each.
--
-- Every one of these returns whether the action was ACCEPTED. Callers should not
-- treat `false` as an error worth reporting to the player: a legitimate client
-- gets rejected constantly by simple latency (it predicts a combo chain the
-- server has already timed out). HeroCombat logs every rejection.

function CombatManager.registerHero(player: Player, character: Model, opts: HeroCombat.HeroOptions?): boolean
	return HeroCombat.register(player, character, opts)
end

function CombatManager.unregisterHero(player: Player)
	HeroCombat.unregister(player)
end

function CombatManager.heroLight(player: Player, aim: any): boolean
	return HeroCombat.requestLight(player, aim)
end

function CombatManager.heroHeavy(player: Player, aim: any): boolean
	return HeroCombat.requestHeavy(player, aim)
end

function CombatManager.heroRanged(player: Player, aim: any): boolean
	return HeroCombat.requestRanged(player, aim)
end

function CombatManager.heroBlock(player: Player, blocking: any, aim: any): boolean
	return HeroCombat.setBlocking(player, blocking, aim)
end

function CombatManager.heroDodge(player: Player, direction: any): boolean
	return HeroCombat.requestDodge(player, direction)
end

function CombatManager.getHeroState(player: Player): HeroState?
	return HeroCombat.getState(player)
end

function CombatManager.isHeroInvulnerable(character: Model): boolean
	return HeroCombat.isInvulnerable(character)
end

-- Test aid for AI-vs-AI sandbox battles: lets allied formations fight each
-- other. Toggled by the admin "/ff" command.
--
-- NOTE: this no longer gates the PLAYER's attacks. The Lord's swings hit
-- everything in the arc unconditionally — allies and his own peasants included —
-- per CombatConfig.Hero.playerAttacksHitAllies, where the griefing tradeoff is
-- documented in full.
function CombatManager.setFriendlyFire(enabled: boolean)
	CombatService.setFriendlyFire(enabled)
end

function CombatManager.getFriendlyFire(): boolean
	return CombatService.getFriendlyFire()
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function CombatManager.init()
	CombatService.init()
	CombatSandbox.init()
	-- Must run after CombatService.init: it installs the incoming-damage hook on
	-- the service and connects PlayerRemoving cleanup.
	HeroCombat.init()
end

function CombatManager.startLoop()
	CombatService.startLoop()
end

return CombatManager
