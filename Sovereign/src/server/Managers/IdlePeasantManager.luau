--!strict
-- IdlePeasantManager: thin delegating shim over WorkerService.
--
-- The campfire/roaming presentation this module used to own the "is this
-- unit idle" question for has been folded into WorkerService's Idle state as
-- pure decoration (see WorkerService's "IDLE PRESENTATION" section). This
-- module is no longer a competing authority -- `isIdle` now reads the same
-- state machine WorkerManager reads, so it cannot disagree with IsWorking/
-- IsHauling the way the old separate list could (that disagreement was the
-- documented "4th, unnamed state").
--
-- Kept as a shim because GameManager.server.luau and PopulationManager call
-- these directly (not through WorkerManager). New code should prefer
-- WorkerService.

local WorkerService = require(script.Parent.Parent.Systems.WorkerService)

local IdlePeasantManager = {}

function IdlePeasantManager.addIdlePeasant(peasant: Model, ownerId: number)
	WorkerService.addIdlePeasant(peasant, ownerId)
end

-- Previously this also forced IsIdle=false, which combined with
-- WorkerManager.releaseFromWork (both are called back-to-back by every
-- manual move order) produced the limbo state the redesign removes. Now it
-- only detaches the campfire/roam presentation so an idle unit stops
-- fighting a manual order for TargetPosition/IsMoving; the unit is still,
-- honestly, idle.
function IdlePeasantManager.removeIdlePeasant(peasant: Model): boolean
	return WorkerService.suppressPresentation(peasant)
end

function IdlePeasantManager.isIdle(peasant: Model): boolean
	return WorkerService.isIdle(peasant)
end

function IdlePeasantManager.getIdlePeasantsForOwner(ownerId: number): { Model }
	return WorkerService.getIdlePeasantsForOwner(ownerId)
end

-- No-op: WorkerService's own scheduler ticks idle presentation as part of
-- its round-robin update. Nothing outside WorkerManager.luau (whose own
-- `update` now calls WorkerService.update directly) ever called this, but
-- it's kept for interface compatibility.
function IdlePeasantManager.update(_dt: number) end

return IdlePeasantManager
