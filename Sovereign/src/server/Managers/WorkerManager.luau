--!strict
-- WorkerManager: thin delegating shim over WorkerService.
--
-- The three competing state machines (WorkerTask.state, HaulerTask.state,
-- IdlePeasantManager.IdleBehavior) that used to live in this 1300-line file
-- have been replaced by one engine: Systems/WorkerService.luau. This module
-- now only exists so the many existing call sites (GameManager.server.luau,
-- HappinessManager, RevoltManager, MaintenanceSystem, specs) keep working
-- without every one of them being rewritten to require WorkerService
-- directly. New code should prefer requiring WorkerService.
--
-- Every function here is a direct pass-through -- no logic, no state -- so
-- there is exactly one place (WorkerService) where a worker's attributes,
-- task membership and idle-pool membership can disagree with each other.

local WorkerService = require(script.Parent.Parent.Systems.WorkerService)

local WorkerManager = {}

function WorkerManager.getAssignedCount(building: Instance): number
	return WorkerService.getAssignedCount(building)
end

function WorkerManager.getWorkerCapacity(building: Instance): number
	return WorkerService.getWorkerCapacity(building)
end

function WorkerManager.getTotalWorkers(building: Instance): number
	return WorkerService.getTotalWorkers(building)
end

function WorkerManager.assignWorkerToBuilding(peasant: Model?, building: Instance?, ownerId: number)
	WorkerService.assignWorkerToBuilding(peasant, building, ownerId)
end

function WorkerManager.assignNearestIdlePeasant(building: Instance, ownerId: number): boolean
	return WorkerService.assignNearestIdlePeasant(building, ownerId)
end

function WorkerManager.unassignWorker(building: Instance, count: number?): number
	return WorkerService.unassignWorker(building, count)
end

function WorkerManager.unassignWorkersFromBuilding(building: Instance): number
	return WorkerService.unassignWorkersFromBuilding(building)
end

function WorkerManager.releaseFromWork(unit: Model?)
	WorkerService.releaseFromWork(unit)
end

function WorkerManager.revertToBaseUnit(unit: Model?): Model?
	return WorkerService.revertToBaseUnit(unit)
end

function WorkerManager.createHaulerTask(
	hauler: Model?,
	sourceBuilding: Instance?,
	resourceType: string,
	ownerId: number,
	role: ("Output" | "Supply")?
)
	WorkerService.createHaulerTask(hauler, sourceBuilding, resourceType, ownerId, role)
end

function WorkerManager.setProductionModifier(player: Player, modifier: number)
	WorkerService.setProductionModifier(player, modifier)
end

function WorkerManager.update(dt: number)
	WorkerService.update(dt)
end

function WorkerManager.startLoop()
	WorkerService.startLoop()
end

return WorkerManager
