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

export type Stance = CombatTypes.Stance
export type CombatUnit = CombatTypes.CombatUnit

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

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function CombatManager.init()
	CombatService.init()
	CombatSandbox.init()
end

function CombatManager.startLoop()
	CombatService.startLoop()
end

return CombatManager
