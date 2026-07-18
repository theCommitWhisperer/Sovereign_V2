--!strict
-- SpawnPointSystem: Manages unit spawning from buildings with SpawnPoint parts
-- Supports multiple spawn patterns: circle, columns, random

local SpawnPointSystem = {}

export type SpawnPattern = "circle" | "columns" | "random"

export type SpawnConfig = {
	pattern: SpawnPattern,
	radius: number?, -- For circle pattern (default: 10 studs)
	spacing: number?, -- For columns pattern (default: 3 studs)
	randomRange: number?, -- For random pattern (default: 15 studs)
	count: number, -- Number of units to spawn
	offset: Vector3?, -- Optional offset from spawn point (default: Vector3.zero)
}

-- Default spawn configurations
local DEFAULT_CONFIG: SpawnConfig = {
	pattern = "circle",
	radius = 10,
	spacing = 3,
	randomRange = 15,
	count = 1,
	offset = Vector3.new(0, 0, 0),
}

-- Finds the SpawnPoint part within a building model
local function findSpawnPoint(buildingModel: Model): BasePart?
	-- Check for "SpawnPoint" in the model (recursive search)
	local spawnPoint = buildingModel:FindFirstChild("SpawnPoint", true)

	if spawnPoint then
		-- If it's a BasePart, use it directly
		if spawnPoint:IsA("BasePart") then
			return spawnPoint :: BasePart
		end

		-- If it's a Model, use its PrimaryPart
		if spawnPoint:IsA("Model") then
			local model = spawnPoint :: Model
			if model.PrimaryPart then
				return model.PrimaryPart
			else
				-- Model doesn't have PrimaryPart, try to get any part
				local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
				if firstPart then
					return firstPart
				end
			end
		end
	end

	-- Fallback: use building's PrimaryPart if no valid SpawnPoint found
	if buildingModel.PrimaryPart then
		return buildingModel.PrimaryPart
	end

	return nil
end

-- Calculate spawn positions in a circle pattern
local function calculateCirclePositions(center: Vector3, count: number, radius: number, offset: Vector3): {Vector3}
	local positions = {}

	for i = 1, count do
		local angle = (math.pi * 2 * (i - 1)) / count
		local xOffset = math.cos(angle) * radius
		local zOffset = math.sin(angle) * radius
		local position = center + offset + Vector3.new(xOffset, 0, zOffset)
		table.insert(positions, position)
	end

	return positions
end

-- Calculate spawn positions in military column pattern (rows and columns)
local function calculateColumnPositions(center: Vector3, count: number, spacing: number, offset: Vector3): {Vector3}
	local positions = {}

	-- Calculate optimal grid dimensions (prefer more rows than columns for military formation)
	local columns = math.ceil(math.sqrt(count / 2)) -- Narrower formation
	local rows = math.ceil(count / columns)

	-- Calculate starting position (centered)
	local startX = -(columns - 1) * spacing / 2
	local startZ = -(rows - 1) * spacing / 2

	for i = 1, count do
		local row = math.floor((i - 1) / columns)
		local col = (i - 1) % columns

		local xPos = startX + (col * spacing)
		local zPos = startZ + (row * spacing)
		local position = center + offset + Vector3.new(xPos, 0, zPos)
		table.insert(positions, position)
	end

	return positions
end

-- Calculate spawn positions randomly around the center
local function calculateRandomPositions(center: Vector3, count: number, range: number, offset: Vector3): {Vector3}
	local positions = {}
	local random = Random.new()

	for i = 1, count do
		local xOffset = random:NextNumber(-range, range)
		local zOffset = random:NextNumber(-range, range)
		local position = center + offset + Vector3.new(xOffset, 0, zOffset)
		table.insert(positions, position)
	end

	return positions
end

-- Main function: Get spawn positions from a building's SpawnPoint
function SpawnPointSystem.getSpawnPositions(buildingModel: Model, config: SpawnConfig?): {Vector3}
	-- Merge config with defaults
	local spawnConfig = config or DEFAULT_CONFIG
	local pattern = spawnConfig.pattern or DEFAULT_CONFIG.pattern
	local count = spawnConfig.count or DEFAULT_CONFIG.count
	local offset = spawnConfig.offset or DEFAULT_CONFIG.offset

	-- Find the SpawnPoint part
	local spawnPoint = findSpawnPoint(buildingModel)
	if not spawnPoint then
		warn(`No SpawnPoint found in building {buildingModel.Name}`)
		return {}
	end

	local center = spawnPoint.Position

	-- Calculate positions based on pattern
	if pattern == "circle" then
		local radius = spawnConfig.radius or DEFAULT_CONFIG.radius
		return calculateCirclePositions(center, count, radius, offset)

	elseif pattern == "columns" then
		local spacing = spawnConfig.spacing or DEFAULT_CONFIG.spacing
		return calculateColumnPositions(center, count, spacing, offset)

	elseif pattern == "random" then
		local range = spawnConfig.randomRange or DEFAULT_CONFIG.randomRange
		return calculateRandomPositions(center, count, range, offset)

	else
		warn(`Unknown spawn pattern: {pattern}, defaulting to circle`)
		local radius = spawnConfig.radius or DEFAULT_CONFIG.radius
		return calculateCirclePositions(center, count, radius, offset)
	end
end

-- Convenience function: Get single spawn position from building
function SpawnPointSystem.getSpawnPosition(buildingModel: Model, offset: Vector3?): Vector3?
	local spawnPoint = findSpawnPoint(buildingModel)
	if not spawnPoint then
		return nil
	end

	local finalOffset = offset or Vector3.new(0, 0, 0)
	return spawnPoint.Position + finalOffset
end

-- Get the SpawnPoint CFrame (includes rotation)
function SpawnPointSystem.getSpawnCFrame(buildingModel: Model): CFrame?
	local spawnPoint = findSpawnPoint(buildingModel)
	if not spawnPoint then
		return nil
	end

	return spawnPoint.CFrame
end

-- Check if a building has a SpawnPoint
function SpawnPointSystem.hasSpawnPoint(buildingModel: Model): boolean
	return findSpawnPoint(buildingModel) ~= nil
end

-- Get spawn positions with ground height adjustment
function SpawnPointSystem.getSpawnPositionsWithTerrain(
	buildingModel: Model,
	config: SpawnConfig?,
	terrainHeight: number?
): {Vector3}
	local positions = SpawnPointSystem.getSpawnPositions(buildingModel, config)

	-- Adjust Y coordinate if terrain height provided
	if terrainHeight then
		for i, pos in ipairs(positions) do
			positions[i] = Vector3.new(pos.X, terrainHeight, pos.Z)
		end
	end

	return positions
end

return SpawnPointSystem
