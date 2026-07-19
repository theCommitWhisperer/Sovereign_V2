--!strict
-- FormationManager: Handles tactical formations for Irish RTS
-- Formations provide combat bonuses and are key to Celtic warfare tactics

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local FormationDebug = DebugManager.createChannel("Formation", false)

local FormationManager = {}

-- Formation types
export type FormationType =
	"ShieldWall"
	| "Wedge"
	| "Circle"
	| "Schiltron"
	| "Loose"
	| "Line"
	| "Column"
	| "Phalanx"
	| "Crescent"
	| "Skirmish"

export type Formation = {
	type: FormationType,
	units: { Model },
	leader: Model?,
	center: Vector3,
	facing: Vector3,
	positions: { [Model]: Vector3 },
	bonuses: {
		attack: number,
		defense: number,
		speed: number,
		morale: number,
	},
}

-- Formation configurations
local FORMATIONS = {
	ShieldWall = {
		-- Defensive formation, strong against frontal attacks
		shape = "line",
		rows = 2,
		spacing = 4,
		bonuses = {
			attack = 0.8,
			defense = 1.5,
			speed = 0.7,
			morale = 1.1,
		},
		minUnits = 4,
		description = "Defensive line formation with shields locked",
	},
	Wedge = {
		-- Offensive formation for breaking enemy lines
		shape = "triangle",
		rows = 3,
		spacing = 4, -- >= body width (3) so units fit their slots
		bonuses = {
			attack = 1.3,
			defense = 0.9,
			speed = 1.1,
			morale = 1.2,
		},
		minUnits = 5,
		description = "Triangular charge formation",
	},
	Circle = {
		-- All-around defense, good against cavalry
		shape = "circle",
		rows = 1,
		spacing = 4, -- >= body width (3) so units fit their slots
		bonuses = {
			attack = 0.9,
			defense = 1.3,
			speed = 0.5,
			morale = 1.0,
		},
		minUnits = 6,
		description = "Circular defense against surrounding enemies",
	},
	Schiltron = {
		-- Scottish pike formation (included for Irish Gallowglass)
		shape = "square",
		rows = 3,
		spacing = 3.5, -- dense pike square, but still >= body width
		bonuses = {
			attack = 1.1,
			defense = 1.4,
			speed = 0.4,
			morale = 1.3,
		},
		minUnits = 9,
		description = "Dense pike square formation",
	},
	Loose = {
		-- Skirmish formation for mobility
		shape = "scatter",
		rows = 1,
		spacing = 8,
		bonuses = {
			attack = 1.0,
			defense = 0.7,
			speed = 1.3,
			morale = 0.9,
		},
		minUnits = 1,
		description = "Loose formation for mobility",
	},
	Line = {
		-- Basic line formation
		shape = "line",
		rows = 1,
		spacing = 6,  -- Increased from 5 to reduce collisions
		bonuses = {
			attack = 1.0,
			defense = 1.0,
			speed = 1.0,
			morale = 1.0,
		},
		minUnits = 2,
		description = "Standard battle line",
	},
	Phalanx = {
		-- Deep infantry block: narrow front, four ranks
		shape = "line",
		rows = 4,
		spacing = 4,
		bonuses = {
			attack = 1.1,
			defense = 1.3,
			speed = 0.6,
			morale = 1.2,
		},
		minUnits = 8,
		description = "Deep four-rank block for holding ground",
	},
	Crescent = {
		-- Enveloping arc, wings pushed forward
		shape = "arc",
		rows = 1,
		spacing = 4,
		bonuses = {
			attack = 1.2,
			defense = 1.0,
			speed = 0.9,
			morale = 1.1,
		},
		minUnits = 6,
		description = "Crescent with forward wings for envelopment",
	},
	Skirmish = {
		-- Staggered checkerboard, hard to hit with volleys
		shape = "staggered",
		rows = 3,
		spacing = 6,
		bonuses = {
			attack = 1.0,
			defense = 0.85,
			speed = 1.25,
			morale = 0.95,
		},
		minUnits = 4,
		description = "Staggered open order for skirmishers",
	},
	Column = {
		-- Marching formation - multiple files side-by-side
		shape = "column",
		rows = 1,
		spacing = 4,  -- Increased from 3 to reduce collisions
		bonuses = {
			attack = 0.8,
			defense = 0.8,
			speed = 1.2,
			morale = 1.0,
		},
		minUnits = 2,
		description = "Column formation for marching (2-4 files wide)",
	},
}

local ActiveFormations: { Formation } = {}

-- Calculate formation positions based on type
local function calculateFormationPositions(
	formationType: FormationType,
	units: { Model },
	center: Vector3,
	facing: Vector3
): { [Model]: Vector3 }
	local positions = {}
	local config = FORMATIONS[formationType]
	if not config then
		return positions
	end

	local rightVector = facing:Cross(Vector3.new(0, 1, 0)).Unit
	local unitCount = #units

	if config.shape == "line" then
		local unitsPerRow = math.ceil(unitCount / config.rows)
		for i, unit in ipairs(units) do
			local row = math.floor((i - 1) / unitsPerRow)
			-- Center each row by its ACTUAL size so a partial back row sits in
			-- the middle instead of hanging off the left flank
			local rowSize = math.min(unitsPerRow, unitCount - row * unitsPerRow)
			local col = (i - 1) % unitsPerRow - (rowSize - 1) / 2

			local offset = rightVector * (col * config.spacing) + facing * (-row * config.spacing)
			positions[unit] = center + offset
		end
	elseif config.shape == "circle" then
		local angleStep = (math.pi * 2) / unitCount
		local radius = (unitCount * config.spacing) / (2 * math.pi)

		for i, unit in ipairs(units) do
			local angle = angleStep * (i - 1)
			local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			positions[unit] = center + offset
		end
	elseif config.shape == "triangle" or config.shape == "wedge" then
		-- Wedge formation with leader at point
		local rowSizes = {}
		local remaining = unitCount
		local currentRow = 1

		-- Calculate units per row (1, 2, 3, 4, ...)
		while remaining > 0 do
			local rowSize = math.min(currentRow * 2 - 1, remaining)
			table.insert(rowSizes, rowSize)
			remaining = remaining - rowSize
			currentRow = currentRow + 1
		end

		local unitIndex = 1
		for row, rowSize in ipairs(rowSizes) do
			for col = 1, rowSize do
				if unitIndex <= unitCount then
					local unit = units[unitIndex]
					local colOffset = (col - 1) - (rowSize - 1) / 2

					local offset = rightVector * (colOffset * config.spacing) + facing * (-row * config.spacing * 1.5)
					positions[unit] = center + offset
					unitIndex = unitIndex + 1
				end
			end
		end
	elseif config.shape == "square" then
		local sideLength = math.ceil(math.sqrt(unitCount))
		for i, unit in ipairs(units) do
			local row = math.floor((i - 1) / sideLength)
			local col = (i - 1) % sideLength

			local offset = rightVector * ((col - sideLength / 2) * config.spacing)
				+ facing * ((row - sideLength / 2) * config.spacing)
			positions[unit] = center + offset
		end
	elseif config.shape == "column" then
		-- Column formation: multiple files (columns) marching together
		-- For example, 6 units = 2 columns of 3, 12 units = 3 columns of 4
		local columnsWide = math.min(math.ceil(math.sqrt(unitCount / 2)), 4) -- Max 4 columns wide
		local unitsPerColumn = math.ceil(unitCount / columnsWide)

		FormationDebug:info(`Column formation: {unitCount} units = {columnsWide} columns × {unitsPerColumn} rows`)

		for i, unit in ipairs(units) do
			-- Which column (0 to columnsWide-1)
			local columnIndex = (i - 1) % columnsWide
			-- Which row (0 to unitsPerColumn-1)
			local rowIndex = math.floor((i - 1) / columnsWide)

			-- Offset perpendicular to facing (columns side-by-side)
			local lateralOffset = rightVector * ((columnIndex - (columnsWide - 1) / 2) * config.spacing)
			-- Offset along facing direction (rows front-to-back)
			local depthOffset = facing * (-(rowIndex * config.spacing))

			positions[unit] = center + lateralOffset + depthOffset
		end
	elseif config.shape == "arc" then
		-- Crescent: units along an arc with the wings pushed FORWARD (toward
		-- the enemy) for envelopment. Center of the crescent sits at `center`.
		local span = math.rad(140)
		local arcLength = math.max(unitCount - 1, 1) * config.spacing
		local radius = arcLength / span

		for i, unit in ipairs(units) do
			local t = if unitCount > 1 then (i - 1) / (unitCount - 1) else 0.5
			local angle = -span / 2 + span * t
			local offset = rightVector * (math.sin(angle) * radius)
				+ facing * ((1 - math.cos(angle)) * radius)
			positions[unit] = center + offset
		end
	elseif config.shape == "staggered" then
		-- Checkerboard: like a line but alternate rows shifted half a space
		local unitsPerRow = math.ceil(unitCount / config.rows)
		for i, unit in ipairs(units) do
			local row = math.floor((i - 1) / unitsPerRow)
			local col = (i - 1) % unitsPerRow - (unitsPerRow - 1) / 2
			local stagger = (row % 2) * config.spacing * 0.5

			local offset = rightVector * (col * config.spacing + stagger)
				+ facing * (-row * config.spacing)
			positions[unit] = center + offset
		end
	elseif config.shape == "scatter" then
		-- Random scatter within area
		for i, unit in ipairs(units) do
			local randomOffset = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)) * config.spacing / 3
			positions[unit] = center + randomOffset
		end
	end

	return positions
end

-- Reassign formation slots by proximity: each slot goes to the nearest
-- still-unassigned unit. Index-order assignment made units cross paths and
-- shove through each other, ending in a clump — greedy matching keeps paths
-- short and mostly parallel so formations actually form.
local function optimizeSlotAssignments(
	units: { Model },
	positions: { [Model]: Vector3 }
): { [Model]: Vector3 }
	-- Collect slots in a stable order (front rows first, as generated)
	local slots: { Vector3 } = {}
	for _, unit in ipairs(units) do
		local slot = positions[unit]
		if slot then
			table.insert(slots, slot)
		end
	end

	local remaining: { Model } = {}
	for _, unit in ipairs(units) do
		if positions[unit] and unit.PrimaryPart then
			table.insert(remaining, unit)
		end
	end

	local optimized: { [Model]: Vector3 } = {}
	for _, slot in ipairs(slots) do
		local bestIndex: number? = nil
		local bestDistSq = math.huge
		for index, unit in ipairs(remaining) do
			local primaryPart = unit.PrimaryPart :: BasePart
			local delta = primaryPart.Position - slot
			local distSq = delta.X * delta.X + delta.Z * delta.Z
			if distSq < bestDistSq then
				bestDistSq = distSq
				bestIndex = index
			end
		end
		if bestIndex then
			optimized[remaining[bestIndex :: number]] = slot
			table.remove(remaining, bestIndex :: number)
		end
	end

	-- Units without PrimaryPart keep their original slot (edge case)
	for _, unit in ipairs(units) do
		if positions[unit] and not optimized[unit] then
			optimized[unit] = positions[unit]
		end
	end

	-- 2-opt refinement: keep swapping any pair of assignments that lowers the
	-- total squared travel distance. Removes the path crossings greedy leaves
	-- behind, so units walk near-parallel lanes into position.
	local unitList: { Model } = {}
	for _, unit in ipairs(units) do
		if optimized[unit] and unit.PrimaryPart then
			table.insert(unitList, unit)
		end
	end

	local function travelSq(unit: Model, slot: Vector3): number
		local pos = (unit.PrimaryPart :: BasePart).Position
		local dx = pos.X - slot.X
		local dz = pos.Z - slot.Z
		return dx * dx + dz * dz
	end

	local passes = 0
	local improved = true
	while improved and passes < 6 do
		improved = false
		passes += 1
		for i = 1, #unitList - 1 do
			local unitA = unitList[i]
			for j = i + 1, #unitList do
				local unitB = unitList[j]
				local slotA = optimized[unitA]
				local slotB = optimized[unitB]
				local currentCost = travelSq(unitA, slotA) + travelSq(unitB, slotB)
				local swappedCost = travelSq(unitA, slotB) + travelSq(unitB, slotA)
				if swappedCost < currentCost - 0.01 then
					optimized[unitA] = slotB
					optimized[unitB] = slotA
					improved = true
				end
			end
		end
	end

	return optimized
end

-- Create a new formation
function FormationManager.createFormation(
	formationType: FormationType,
	units: { Model },
	position: Vector3,
	facing: Vector3?
): Formation?
	local config = FORMATIONS[formationType]
	if not config then
		FormationDebug:warn("Invalid formation type", { type = formationType })
		return nil
	end

	if #units < config.minUnits then
		FormationDebug:warn("Not enough units for formation", {
			type = formationType,
			required = config.minUnits,
			provided = #units,
		})
		return nil
	end

	local facingDirection = facing or Vector3.new(0, 0, -1)
	local positions = calculateFormationPositions(formationType, units, position, facingDirection)
	positions = optimizeSlotAssignments(units, positions)

	local formation: Formation = {
		type = formationType,
		units = units,
		leader = units[1], -- First unit is leader
		center = position,
		facing = facingDirection,
		positions = positions,
		bonuses = config.bonuses,
	}

	table.insert(ActiveFormations, formation)

	-- Set formation attributes on units
	for _, unit in ipairs(units) do
		unit:SetAttribute("InFormation", true)
		unit:SetAttribute("FormationType", formationType)
	end

	-- Visual feedback
	createFormationVisual(formation)

	FormationDebug:info("Formation created", {
		type = formationType,
		unitCount = #units,
		position = position,
	})

	return formation
end

-- Create visual indicator for formation
function createFormationVisual(formation: Formation)
	local config = FORMATIONS[formation.type]
	if not config then
		return
	end

	-- Create a temporary visual effect in a separate task (non-blocking)
	task.spawn(function()
		local part = Instance.new("Part")
		part.Name = "FormationIndicator"
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.8
		part.Material = Enum.Material.ForceField
		part.Size = Vector3.new(20, 0.2, 20) -- Adjust based on formation
		part.Position = formation.center
		part.Color = Color3.fromRGB(100, 200, 100)
		part.Parent = workspace

		-- Fade out effect
		TweenService:Create(part, TweenInfo.new(2), {
			Transparency = 1,
		}):Play()

		task.wait(2)
		part:Destroy()
	end)
end

-- Move formation to new position
function FormationManager.moveFormation(formation: Formation, newPosition: Vector3, newFacing: Vector3?)
	formation.center = newPosition
	if newFacing then
		formation.facing = newFacing
	end

	-- Recalculate positions
	formation.positions =
		calculateFormationPositions(formation.type, formation.units, formation.center, formation.facing)

	FormationDebug:info("Formation moving", {
		type = formation.type,
		newPosition = newPosition,
	})
end

-- Break formation
function FormationManager.breakFormation(formation: Formation)
	-- Remove formation attributes
	for _, unit in ipairs(formation.units) do
		unit:SetAttribute("InFormation", false)
		unit:SetAttribute("FormationType", nil)
	end

	-- Remove from active formations
	local index = table.find(ActiveFormations, formation)
	if index then
		table.remove(ActiveFormations, index)
	end

	FormationDebug:info("Formation broken", {
		type = formation.type,
	})
end

-- Get formation bonuses for a unit
function FormationManager.getFormationBonus(unit: Model, bonusType: string): number
	if not unit:GetAttribute("InFormation") then
		return 1.0
	end

	local formationType = unit:GetAttribute("FormationType")
	if not formationType then
		return 1.0
	end

	local config = FORMATIONS[formationType]
	if not config or not config.bonuses then
		return 1.0
	end

	return config.bonuses[bonusType] or 1.0
end

-- Check if units can form a specific formation
function FormationManager.canFormFormation(formationType: FormationType, units: { Model }): boolean
	local config = FORMATIONS[formationType]
	if not config then
		return false
	end

	if #units < config.minUnits then
		return false
	end

	-- Check if units are already in another formation
	for _, unit in ipairs(units) do
		if unit:GetAttribute("InFormation") then
			return false
		end
	end

	-- Special requirements for certain formations
	if formationType == "Schiltron" then
		-- Requires pike units
		for _, unit in ipairs(units) do
			local unitType = unit:GetAttribute("UnitType")
			if not (unitType == "Pikeman" or unitType == "Gallowglass") then
				return false
			end
		end
	end

	return true
end

-- Update formation integrity
local function updateFormations()
	for i = #ActiveFormations, 1, -1 do
		local formation = ActiveFormations[i]
		local validUnits = {}

		-- Check which units are still valid
		for _, unit in ipairs(formation.units) do
			if unit and unit.Parent and unit:GetAttribute("InFormation") then
				table.insert(validUnits, unit)
			end
		end

		-- Break formation if too many units lost
		local config = FORMATIONS[formation.type]
		if #validUnits < (config and config.minUnits or 1) then
			FormationManager.breakFormation(formation)
		else
			formation.units = validUnits
		end
	end
end

-- Celtic special: Wild Charge formation
function FormationManager.wildCharge(units: { Model }, targetPosition: Vector3)
	FormationDebug:info("WILD CHARGE!", {
		unitCount = #units,
		target = targetPosition,
	})

	-- Break any existing formation
	for _, unit in ipairs(units) do
		if unit:GetAttribute("InFormation") then
			for _, formation in ipairs(ActiveFormations) do
				if table.find(formation.units, unit) then
					FormationManager.breakFormation(formation)
					break
				end
			end
		end
	end

	-- Form loose wedge for charge
	local facing = (targetPosition - units[1].PrimaryPart.Position).Unit
	local formation = FormationManager.createFormation("Wedge", units, units[1].PrimaryPart.Position, facing)

	if formation then
		-- Apply charge bonuses
		for _, unit in ipairs(units) do
			unit:SetAttribute("IsCharging", true)
			unit:SetAttribute("ChargeDamageBonus", 1.5)

			-- Visual effect
			local fire = Instance.new("Fire")
			fire.Size = 5
			fire.Heat = 10
			fire.Color = Color3.fromRGB(255, 150, 50)
			fire.SecondaryColor = Color3.fromRGB(255, 200, 100)
			fire.Parent = unit.PrimaryPart

			-- Remove after charge
			task.wait(5)
			fire:Destroy()
			unit:SetAttribute("IsCharging", false)
		end
	end
end

-- Initialize formation system
function FormationManager.init()
	RunService.Heartbeat:Connect(function()
		if tick() % 1 < 0.1 then -- Update every second
			updateFormations()
		end
	end)

	FormationDebug:info("Formation system initialized")
end

return FormationManager
