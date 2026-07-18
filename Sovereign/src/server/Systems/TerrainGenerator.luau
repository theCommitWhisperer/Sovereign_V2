--!strict
-- TerrainGenerator: Procedurally generates the game map terrain based on map configuration.
-- Each terrain type creates a visually distinct map that can be further refined in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local TerrainGeneratorDebug = DebugManager.createChannel("TerrainGenerator", true)

local TerrainGenerator = {}

-- Constants
local TERRAIN_SMOOTHNESS = 20
local MOUNTAIN_HEIGHT = 150
local MOUNTAIN_RADIUS = 200
local HILL_HEIGHT = 40
local HILL_RADIUS = 80

-- Helper: Fill a terrain block at a position
local function fillBlock(terrain, position: Vector3, size: Vector3, material: Enum.Material)
	terrain:FillBlock(CFrame.new(position), size, material)
end

-- Helper: Fill a terrain ball at a position
local function fillBall(terrain, position: Vector3, radius: number, material: Enum.Material)
	terrain:FillBall(position, radius, material)
end

-- Helper: Create gentle rolling hills
local function generateHills(terrain, mapSize: number, count: number, material: Enum.Material)
	for i = 1, count do
		local angle = (math.pi * 2 * i) / count
		local distance = mapSize * 0.3 + math.random(-50, 50)
		local x = math.cos(angle) * distance
		local z = math.sin(angle) * distance
		local height = HILL_HEIGHT * (0.5 + math.random() * 0.5)
		local radius = HILL_RADIUS * (0.7 + math.random() * 0.6)

		fillBall(terrain, Vector3.new(x, height / 2, z), radius, material)
	end
end

-- Helper: Create a river between two points
local function generateRiver(terrain, startPos: Vector3, endPos: Vector3, width: number)
	local direction = (endPos - startPos)
	local length = direction.Magnitude
	local midPoint = (startPos + endPos) / 2
	local angle = math.atan2(direction.Z, direction.X)

	local riverCFrame = CFrame.new(midPoint) * CFrame.Angles(0, -angle, 0)
	local riverSize = Vector3.new(length * 1.1, 12, width)
	terrain:FillBlock(riverCFrame, riverSize, Enum.Material.Water)
end

-- Helper: Create sand border around water features
local function generateBeachBorder(terrain, center: Vector3, innerRadius: number, outerRadius: number)
	-- Create a sand ring around water
	fillBall(terrain, center + Vector3.new(0, 2, 0), outerRadius, Enum.Material.Sand)
	-- The water will overwrite the center
	fillBall(terrain, center, innerRadius, Enum.Material.Water)
end

-- Helper: Create scattered rock formations
local function generateRockFormations(terrain, mapSize: number, count: number)
	for i = 1, count do
		local x = (math.random() - 0.5) * mapSize * 0.8
		local z = (math.random() - 0.5) * mapSize * 0.8
		local radius = 15 + math.random(0, 25)
		local height = 10 + math.random(0, 30)

		fillBall(terrain, Vector3.new(x, height / 2, z), radius, Enum.Material.Rock)
	end
end

-- Helper: Create quadrant boundary markers (subtle terrain features in neutral zone)
local function generateNeutralZone(terrain, mapSize: number, neutralWidth: number, material: Enum.Material)
	-- Subtle path/road in the neutral zone
	local pathMaterial = material or Enum.Material.Ground

	-- Horizontal neutral path
	fillBlock(terrain, Vector3.new(0, 0.5, 0), Vector3.new(mapSize, 3, neutralWidth * 0.3), pathMaterial)
	-- Vertical neutral path
	fillBlock(terrain, Vector3.new(0, 0.5, 0), Vector3.new(neutralWidth * 0.3, 3, mapSize), pathMaterial)
end

------------------------------------------------------------------------
-- TERRAIN TYPE GENERATORS
------------------------------------------------------------------------

-- Plains: Green grass base, scattered forests, gentle hills, no major obstacles
local function generatePlains(terrain, mapConfig)
	local mapSize = mapConfig.Size
	TerrainGeneratorDebug:info("Generating Plains terrain...")

	-- Base grass layer
	fillBlock(terrain, Vector3.new(0, -25, 0), Vector3.new(mapSize, 50, mapSize), Enum.Material.Grass)

	-- Gentle rolling hills
	generateHills(terrain, mapSize, 8, Enum.Material.Grass)

	-- Forests (if enabled) - create small elevated grass patches to represent tree areas
	if mapConfig.Features.HasForests then
		TerrainGeneratorDebug:info("Adding forest areas...")
		for i = 1, 12 do
			local x = (math.random() - 0.5) * mapSize * 0.7
			local z = (math.random() - 0.5) * mapSize * 0.7
			fillBall(terrain, Vector3.new(x, 3, z), 30 + math.random(0, 20), Enum.Material.LeafyGrass)
		end
	end

	-- Neutral zone ground paths
	generateNeutralZone(terrain, mapSize, mapConfig.NeutralZoneWidth, Enum.Material.Ground)
end

-- Mixed/Continental: Full featured map with lake, mountains, rivers, forests
local function generateMixed(terrain, mapConfig)
	local mapSize = mapConfig.Size
	TerrainGeneratorDebug:info("Generating Mixed/Continental terrain...")

	-- Base grass layer
	fillBlock(terrain, Vector3.new(0, -25, 0), Vector3.new(mapSize, 50, mapSize), Enum.Material.Grass)

	-- Mountains in the quadrant corners (away from spawn centers)
	if mapConfig.Features.HasMountains then
		TerrainGeneratorDebug:info("Generating mountains...")
		local mountainPositions = {
			Vector3.new(mapSize / 4, MOUNTAIN_HEIGHT / 2, mapSize / 4),
			Vector3.new(-mapSize / 4, MOUNTAIN_HEIGHT / 2, -mapSize / 4),
			Vector3.new(mapSize / 3, MOUNTAIN_HEIGHT / 3, -mapSize / 5),
			Vector3.new(-mapSize / 3, MOUNTAIN_HEIGHT / 3, mapSize / 5),
		}

		for _, pos in ipairs(mountainPositions) do
			fillBall(terrain, pos, MOUNTAIN_RADIUS, Enum.Material.Rock)
			-- Grass cap on top
			fillBall(terrain, pos + Vector3.new(0, TERRAIN_SMOOTHNESS, 0), MOUNTAIN_RADIUS * 0.8, Enum.Material.Grass)
			-- Snow on peaks
			fillBall(terrain, pos + Vector3.new(0, TERRAIN_SMOOTHNESS * 2, 0), MOUNTAIN_RADIUS * 0.4, Enum.Material.Snow)
		end
	end

	-- Rivers
	if mapConfig.Features.HasRivers then
		TerrainGeneratorDebug:info("Generating rivers...")
		-- Main river flowing diagonally
		generateRiver(
			terrain,
			Vector3.new(-mapSize / 2, 3, mapSize / 4),
			Vector3.new(mapSize / 2, 3, -mapSize / 4),
			50
		)
		-- Secondary tributary
		generateRiver(
			terrain,
			Vector3.new(0, 3, mapSize / 2),
			Vector3.new(mapSize / 4, 3, 0),
			30
		)
	end

	-- Central lake
	if mapConfig.Features.HasCentralLake then
		TerrainGeneratorDebug:info("Generating central lake...")
		local lakeRadius = mapSize / 6
		generateBeachBorder(terrain, Vector3.new(0, 2, 0), lakeRadius, lakeRadius * 1.3)
	end

	-- Forest areas
	if mapConfig.Features.HasForests then
		TerrainGeneratorDebug:info("Adding forest areas...")
		for i = 1, 16 do
			local x = (math.random() - 0.5) * mapSize * 0.7
			local z = (math.random() - 0.5) * mapSize * 0.7
			fillBall(terrain, Vector3.new(x, 3, z), 25 + math.random(0, 30), Enum.Material.LeafyGrass)
		end
	end

	-- Rolling hills
	generateHills(terrain, mapSize, 6, Enum.Material.Grass)

	-- Neutral zone paths
	generateNeutralZone(terrain, mapSize, mapConfig.NeutralZoneWidth, Enum.Material.Ground)
end

-- Island: Water surrounding a raised grass landmass with sandy beaches
local function generateIsland(terrain, mapConfig)
	local mapSize = mapConfig.Size
	TerrainGeneratorDebug:info("Generating Island terrain...")

	-- Surrounding ocean (fill the entire area with water first)
	fillBlock(terrain, Vector3.new(0, -10, 0), Vector3.new(mapSize * 1.3, 25, mapSize * 1.3), Enum.Material.Water)

	-- Island landmass (raised above water)
	local islandRadius = mapSize * 0.45
	fillBall(terrain, Vector3.new(0, 15, 0), islandRadius, Enum.Material.Grass)

	-- Sandy beach ring around the island
	-- Slightly larger sand layer under the grass
	fillBall(terrain, Vector3.new(0, 8, 0), islandRadius * 1.1, Enum.Material.Sand)
	-- Re-fill the interior with grass
	fillBall(terrain, Vector3.new(0, 15, 0), islandRadius * 0.9, Enum.Material.Grass)

	-- Flatten the top for playable area
	fillBlock(terrain, Vector3.new(0, -25, 0), Vector3.new(mapSize * 0.8, 50, mapSize * 0.8), Enum.Material.Grass)

	-- Central lake (if enabled)
	if mapConfig.Features.HasCentralLake then
		TerrainGeneratorDebug:info("Generating island lagoon...")
		local lakeRadius = mapSize / 8
		fillBall(terrain, Vector3.new(0, 2, 0), lakeRadius, Enum.Material.Water)
	end

	-- Palm forest areas
	if mapConfig.Features.HasForests then
		for i = 1, 8 do
			local angle = (math.pi * 2 * i) / 8
			local dist = mapSize * 0.25
			local x = math.cos(angle) * dist
			local z = math.sin(angle) * dist
			fillBall(terrain, Vector3.new(x, 3, z), 20 + math.random(0, 15), Enum.Material.LeafyGrass)
		end
	end

	-- Neutral zone
	generateNeutralZone(terrain, mapSize, mapConfig.NeutralZoneWidth, Enum.Material.Sand)
end

-- Desert: Sand base, rock outcroppings, oasis, sparse vegetation
local function generateDesert(terrain, mapConfig)
	local mapSize = mapConfig.Size
	TerrainGeneratorDebug:info("Generating Desert terrain...")

	-- Base sand layer
	fillBlock(terrain, Vector3.new(0, -25, 0), Vector3.new(mapSize, 50, mapSize), Enum.Material.Sand)

	-- Sand dunes (gentle hills of sand)
	for i = 1, 10 do
		local x = (math.random() - 0.5) * mapSize * 0.8
		local z = (math.random() - 0.5) * mapSize * 0.8
		local radius = 40 + math.random(0, 60)
		local height = 8 + math.random(0, 15)
		fillBall(terrain, Vector3.new(x, height / 2, z), radius, Enum.Material.Sand)
	end

	-- Rock formations (mountains)
	if mapConfig.Features.HasMountains then
		TerrainGeneratorDebug:info("Generating desert rock formations...")
		local rockPositions = {
			Vector3.new(mapSize / 3, 40, mapSize / 3),
			Vector3.new(-mapSize / 3, 50, -mapSize / 4),
			Vector3.new(mapSize / 4, 30, -mapSize / 3),
			Vector3.new(-mapSize / 4, 35, mapSize / 3),
		}

		for _, pos in ipairs(rockPositions) do
			fillBall(terrain, pos, 100 + math.random(0, 50), Enum.Material.Rock)
			-- Sandstone layer
			fillBall(terrain, pos + Vector3.new(0, 10, 0), 80 + math.random(0, 30), Enum.Material.Sandstone)
		end
	end

	-- Scattered smaller rock outcroppings
	generateRockFormations(terrain, mapSize, 15)

	-- Oasis / central lake (the only water source)
	if mapConfig.Features.HasCentralLake then
		TerrainGeneratorDebug:info("Generating desert oasis...")
		local oasisRadius = mapSize / 8
		-- Green grass around oasis
		fillBall(terrain, Vector3.new(0, 2, 0), oasisRadius * 1.5, Enum.Material.LeafyGrass)
		-- Water in center
		fillBall(terrain, Vector3.new(0, 1, 0), oasisRadius, Enum.Material.Water)
	end

	-- Neutral zone (rocky paths through desert)
	generateNeutralZone(terrain, mapSize, mapConfig.NeutralZoneWidth, Enum.Material.Sandstone)
end

-- Arena: Compact, flat stone/grass base with walled edges for 1v1 combat
local function generateArena(terrain, mapConfig)
	local mapSize = mapConfig.Size
	TerrainGeneratorDebug:info("Generating Arena terrain...")

	-- Base layer - mix of grass and stone
	fillBlock(terrain, Vector3.new(0, -25, 0), Vector3.new(mapSize, 50, mapSize), Enum.Material.Grass)

	-- Stone center (neutral zone area)
	local centerSize = mapConfig.NeutralZoneWidth * 2
	fillBlock(terrain, Vector3.new(0, 0.5, 0), Vector3.new(centerSize, 3, centerSize), Enum.Material.Slate)

	-- Raised rock walls around the arena perimeter
	local wallHeight = 30
	local wallThickness = 20
	local halfSize = mapSize / 2

	-- North wall
	fillBlock(terrain, Vector3.new(0, wallHeight / 2, halfSize), Vector3.new(mapSize, wallHeight, wallThickness), Enum.Material.Rock)
	-- South wall
	fillBlock(terrain, Vector3.new(0, wallHeight / 2, -halfSize), Vector3.new(mapSize, wallHeight, wallThickness), Enum.Material.Rock)
	-- East wall
	fillBlock(terrain, Vector3.new(halfSize, wallHeight / 2, 0), Vector3.new(wallThickness, wallHeight, mapSize), Enum.Material.Rock)
	-- West wall
	fillBlock(terrain, Vector3.new(-halfSize, wallHeight / 2, 0), Vector3.new(wallThickness, wallHeight, mapSize), Enum.Material.Rock)

	-- Small forest patches
	if mapConfig.Features.HasForests then
		for i = 1, 4 do
			local angle = (math.pi * 2 * i) / 4 + math.pi / 4
			local dist = mapSize * 0.3
			local x = math.cos(angle) * dist
			local z = math.sin(angle) * dist
			fillBall(terrain, Vector3.new(x, 3, z), 15 + math.random(0, 10), Enum.Material.LeafyGrass)
		end
	end

	-- Neutral zone
	generateNeutralZone(terrain, mapSize, mapConfig.NeutralZoneWidth, Enum.Material.Slate)
end

-- Mountains/Highland: Elevated rocky terrain with valleys between quadrants
local function generateMountains(terrain, mapConfig)
	local mapSize = mapConfig.Size
	TerrainGeneratorDebug:info("Generating Highland/Mountain terrain...")

	-- Base rock layer (higher elevation overall)
	fillBlock(terrain, Vector3.new(0, -20, 0), Vector3.new(mapSize, 50, mapSize), Enum.Material.Rock)
	-- Grass topsoil
	fillBlock(terrain, Vector3.new(0, 2, 0), Vector3.new(mapSize, 5, mapSize), Enum.Material.Grass)

	-- Major mountain ranges along quadrant boundaries
	TerrainGeneratorDebug:info("Generating mountain ranges...")

	-- Mountain ridge running north-south (along vertical neutral zone)
	for i = 1, 8 do
		local z = (i / 8 - 0.5) * mapSize * 0.8
		local height = MOUNTAIN_HEIGHT * (0.6 + math.random() * 0.4)
		local radius = MOUNTAIN_RADIUS * (0.5 + math.random() * 0.3)
		local x = (math.random() - 0.5) * mapConfig.NeutralZoneWidth * 2

		fillBall(terrain, Vector3.new(x, height / 2, z), radius, Enum.Material.Rock)
		-- Snow on peaks
		if height > MOUNTAIN_HEIGHT * 0.7 then
			fillBall(terrain, Vector3.new(x, height / 2 + 20, z), radius * 0.5, Enum.Material.Snow)
		end
	end

	-- Mountain ridge running east-west (along horizontal neutral zone)
	for i = 1, 8 do
		local x = (i / 8 - 0.5) * mapSize * 0.8
		local height = MOUNTAIN_HEIGHT * (0.5 + math.random() * 0.5)
		local radius = MOUNTAIN_RADIUS * (0.4 + math.random() * 0.3)
		local z = (math.random() - 0.5) * mapConfig.NeutralZoneWidth * 2

		fillBall(terrain, Vector3.new(x, height / 2, z), radius, Enum.Material.Rock)
		if height > MOUNTAIN_HEIGHT * 0.7 then
			fillBall(terrain, Vector3.new(x, height / 2 + 20, z), radius * 0.5, Enum.Material.Snow)
		end
	end

	-- Valleys in each quadrant (flatten spawn areas)
	local halfEstate = mapConfig.QuadrantSize / 2
	local offset = halfEstate + (mapConfig.NeutralZoneWidth / 2)
	local valleyPositions = {
		Vector3.new(-offset, 0, offset),   -- NW
		Vector3.new(offset, 0, offset),    -- NE
		Vector3.new(-offset, 0, -offset),  -- SW
		Vector3.new(offset, 0, -offset),   -- SE
	}

	for _, pos in ipairs(valleyPositions) do
		-- Clear a flat valley area for building
		fillBlock(terrain, pos + Vector3.new(0, -10, 0), Vector3.new(halfEstate * 1.2, 30, halfEstate * 1.2), Enum.Material.Grass)
	end

	-- Rivers through valleys
	if mapConfig.Features.HasRivers then
		TerrainGeneratorDebug:info("Generating mountain rivers...")
		-- River flowing through the neutral zone
		generateRiver(
			terrain,
			Vector3.new(-mapSize / 2, 5, 0),
			Vector3.new(mapSize / 2, 5, 0),
			40
		)
		-- Tributary
		generateRiver(
			terrain,
			Vector3.new(0, 5, -mapSize / 2),
			Vector3.new(0, 5, mapSize / 2),
			35
		)
	end

	-- Neutral zone (rocky mountain passes)
	generateNeutralZone(terrain, mapSize, mapConfig.NeutralZoneWidth, Enum.Material.Slate)
end

------------------------------------------------------------------------
-- MAIN GENERATE FUNCTION
------------------------------------------------------------------------

function TerrainGenerator.generate(mapConfig: any)
	TerrainGeneratorDebug:info("Generating terrain for map: " .. mapConfig.Name .. " (type: " .. mapConfig.TerrainType .. ")")
	local terrain = workspace:WaitForChild("Terrain")

	-- Clear existing terrain
	terrain:Clear()

	-- Route to terrain type-specific generator
	local terrainType = mapConfig.TerrainType

	if terrainType == "Plains" then
		generatePlains(terrain, mapConfig)
	elseif terrainType == "Mixed" then
		generateMixed(terrain, mapConfig)
	elseif terrainType == "Island" then
		generateIsland(terrain, mapConfig)
	elseif terrainType == "Desert" then
		generateDesert(terrain, mapConfig)
	elseif terrainType == "Arena" then
		generateArena(terrain, mapConfig)
	elseif terrainType == "Mountains" then
		generateMountains(terrain, mapConfig)
	else
		-- Fallback: basic grass terrain
		TerrainGeneratorDebug:warn("Unknown terrain type: " .. terrainType .. ", using basic grass")
		local mapSize = mapConfig.Size
		fillBlock(terrain, Vector3.new(0, -25, 0), Vector3.new(mapSize, 50, mapSize), Enum.Material.Grass)

		if mapConfig.Features.HasMountains then
			local mountainPositions = {
				Vector3.new(mapSize / 4, MOUNTAIN_HEIGHT / 2, mapSize / 4),
				Vector3.new(-mapSize / 4, MOUNTAIN_HEIGHT / 2, -mapSize / 4),
			}
			for _, pos in ipairs(mountainPositions) do
				fillBall(terrain, pos, MOUNTAIN_RADIUS, Enum.Material.Rock)
			end
		end

		if mapConfig.Features.HasCentralLake then
			local lakeRadius = mapSize / 6
			fillBall(terrain, Vector3.new(0, 2, 0), lakeRadius, Enum.Material.Water)
		end

		if mapConfig.Features.HasRivers then
			local riverCFrame = CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(20), 0)
			terrain:FillBlock(riverCFrame, Vector3.new(mapSize * 1.2, 10, 50), Enum.Material.Water)
		end
	end

	TerrainGeneratorDebug:info("Terrain generation complete for: " .. mapConfig.Name)
end

return TerrainGenerator
