--!strict
-- FormationCohesion: Ensures units in formation stay together during movement
-- Units adjust speed to maintain formation shape while traveling

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local FormationDebug = DebugManager.createChannel("Formation", false)

local FormationCohesion = {}

-- Configuration
local MAX_SEPARATION_DISTANCE = 15 -- Max studs units can separate before slowing down
local COHESION_SLOWDOWN = 0.5 -- Speed multiplier when waiting for formation (50% speed)
local LEADER_SLOWDOWN = 0.7 -- How much the leader slows when formation spreads (70% speed)
local CHECK_INTERVAL = 0.5 -- Seconds between cohesion checks (performance optimization)

-- Track formation states
local formationStates: { [string]: FormationState } = {}
local lastCheckTimes: { [string]: number } = {}

type FormationState = {
	formationId: string,
	units: { Model },
	centerPosition: Vector3,
	averageProgress: number, -- 0-1, how far along the path
	needsCohesion: boolean,
}

-- Calculate formation center position
local function calculateFormationCenter(units: { Model }): Vector3?
	local sum = Vector3.new(0, 0, 0)
	local count = 0

	for _, unit in units do
		if unit.PrimaryPart and unit.Parent then
			sum += unit.PrimaryPart.Position
			count += 1
		end
	end

	if count == 0 then
		return nil
	end

	return sum / count
end

-- Calculate how spread out the formation is
local function calculateFormationSpread(units: { Model }, center: Vector3): number
	local maxDistance = 0

	for _, unit in units do
		if unit.PrimaryPart and unit.Parent then
			local distance = (unit.PrimaryPart.Position - center).Magnitude
			maxDistance = math.max(maxDistance, distance)
		end
	end

	return maxDistance
end

-- Check if formation needs cohesion (units too spread out)
local function formationNeedsCohesion(units: { Model }): (boolean, Vector3?, number)
	local center = calculateFormationCenter(units)
	if not center then
		return false, nil, 0
	end

	local spread = calculateFormationSpread(units, center)
	local needsCohesion = spread > MAX_SEPARATION_DISTANCE

	return needsCohesion, center, spread
end

-- Register a formation for cohesion tracking
function FormationCohesion.registerFormation(formationId: string, units: { Model })
	if #units < 2 then
		FormationDebug:info(`Formation {formationId} only has {#units} units, skipping cohesion`)
		return
	end

	formationStates[formationId] = {
		formationId = formationId,
		units = units,
		centerPosition = Vector3.new(0, 0, 0),
		averageProgress = 0,
		needsCohesion = false,
	}

	FormationDebug:info(`Registered formation {formationId} with {#units} units for cohesion tracking`)
end

-- Unregister a formation
function FormationCohesion.unregisterFormation(formationId: string)
	if formationStates[formationId] then
		formationStates[formationId] = nil
		lastCheckTimes[formationId] = nil
		FormationDebug:info(`Unregistered formation {formationId}`)
	end
end

-- Calculate speed multiplier for a unit in formation
function FormationCohesion.getSpeedMultiplier(unit: Model, formationId: string?): number
	if not formationId then
		return 1.0 -- Not in a formation
	end

	local state = formationStates[formationId]
	if not state then
		return 1.0 -- Formation not tracked
	end

	-- Throttle checks for performance
	local now = tick()
	local lastCheck = lastCheckTimes[formationId] or 0
	if now - lastCheck < CHECK_INTERVAL then
		-- Use cached result
		return state.needsCohesion and COHESION_SLOWDOWN or 1.0
	end

	-- Perform cohesion check
	lastCheckTimes[formationId] = now
	local needsCohesion, center, spread = formationNeedsCohesion(state.units)

	state.needsCohesion = needsCohesion
	if center then
		state.centerPosition = center
	end

	if not needsCohesion then
		return 1.0 -- Formation is tight, full speed
	end

	-- Formation is spread out - slow down units that are ahead
	if not unit.PrimaryPart or not center then
		return 1.0
	end

	local unitPos = unit.PrimaryPart.Position
	local distanceFromCenter = (unitPos - center).Magnitude

	-- Units far from center (leading) slow down more
	if distanceFromCenter > MAX_SEPARATION_DISTANCE * 0.7 then
		FormationDebug:info(`Unit {unit.Name} is leading, slowing to {LEADER_SLOWDOWN * 100}%`)
		return LEADER_SLOWDOWN
	end

	-- Units in the middle slow down a bit
	if distanceFromCenter > MAX_SEPARATION_DISTANCE * 0.4 then
		return (LEADER_SLOWDOWN + COHESION_SLOWDOWN) / 2
	end

	-- Lagging units get a speed boost
	FormationDebug:info(`Unit {unit.Name} is lagging, maintaining full speed`)
	return 1.0
end

-- Update formation state (called by MovementSystem)
function FormationCohesion.updateFormation(formationId: string)
	local state = formationStates[formationId]
	if not state then
		return
	end

	-- Clean up units that no longer exist
	local activeUnits = {}
	for _, unit in state.units do
		if unit.Parent and unit.PrimaryPart then
			table.insert(activeUnits, unit)
		end
	end

	state.units = activeUnits

	-- Unregister if too few units left
	if #activeUnits < 2 then
		FormationCohesion.unregisterFormation(formationId)
		FormationDebug:info(`Formation {formationId} dissolved (only {#activeUnits} units remaining)`)
	end
end

-- Check if a unit is in any formation
function FormationCohesion.getUnitFormation(unit: Model): string?
	for formationId, state in pairs(formationStates) do
		for _, formationUnit in state.units do
			if formationUnit == unit then
				return formationId
			end
		end
	end
	return nil
end

-- Get all active formations
function FormationCohesion.getActiveFormations(): { string }
	local formations = {}
	for formationId, _ in pairs(formationStates) do
		table.insert(formations, formationId)
	end
	return formations
end

-- Clean up formations with no active units
function FormationCohesion.cleanupInactiveFormations()
	local toRemove = {}

	for formationId, state in pairs(formationStates) do
		local activeCount = 0
		for _, unit in state.units do
			if unit.Parent and unit.PrimaryPart then
				activeCount += 1
			end
		end

		if activeCount < 2 then
			table.insert(toRemove, formationId)
		end
	end

	for _, formationId in toRemove do
		FormationCohesion.unregisterFormation(formationId)
	end

	if #toRemove > 0 then
		FormationDebug:info(`Cleaned up {#toRemove} inactive formations`)
	end
end

-- Get configuration for debugging
function FormationCohesion.getConfig()
	return {
		maxSeparation = MAX_SEPARATION_DISTANCE,
		cohesionSlowdown = COHESION_SLOWDOWN,
		leaderSlowdown = LEADER_SLOWDOWN,
		checkInterval = CHECK_INTERVAL,
	}
end

-- Get formation state for debugging
function FormationCohesion.getFormationState(formationId: string): FormationState?
	return formationStates[formationId]
end

FormationDebug:info("FormationCohesion loaded successfully")

return FormationCohesion
