--!strict
-- Pathfinding Module: Main entry point for pathfinding system
-- Combines all pathfinding components into a unified interface

local PathfindingCore = require(script.PathfindingCore)
local PathSmoothing = require(script.PathSmoothing)
local UnitMovement = require(script.UnitMovement)

local Pathfinding = {}

-- Re-export types
export type PathfindingGrid = PathfindingCore.PathfindingGrid
export type PathPoint = PathfindingCore.PathPoint
export type MovementConfig = UnitMovement.MovementConfig
export type UnitMover = UnitMovement.UnitMover

-- Re-export core functions
Pathfinding.createGrid = PathfindingCore.createGrid
Pathfinding.findPath = PathfindingCore.findPath
Pathfinding.worldToGrid = PathfindingCore.worldToGrid
Pathfinding.gridToWorld = PathfindingCore.gridToWorld
Pathfinding.setNodeWalkable = PathfindingCore.setNodeWalkable
Pathfinding.setNodeCost = PathfindingCore.setNodeCost
Pathfinding.setAreaWalkable = PathfindingCore.setAreaWalkable

-- Re-export smoothing functions
Pathfinding.optimizePath = PathSmoothing.optimizePath
Pathfinding.simplifyPath = PathSmoothing.simplifyPath
Pathfinding.smoothWithSpline = PathSmoothing.smoothWithSpline

-- Re-export movement functions
Pathfinding.createUnitMover = UnitMovement.new

-- High-level helper: Find and optimize a path
function Pathfinding.findOptimizedPath(
	grid: PathfindingGrid,
	startWorldX: number,
	startWorldZ: number,
	endWorldX: number,
	endWorldZ: number,
	optimizationOptions: {
		stringPull: boolean?,
		simplify: boolean?,
		smooth: boolean?,
	}?
): { PathPoint }?
	-- Convert world coordinates to grid
	local startGridX, startGridY = PathfindingCore.worldToGrid(grid, startWorldX, startWorldZ)
	local endGridX, endGridY = PathfindingCore.worldToGrid(grid, endWorldX, endWorldZ)

	-- Find path
	local path = PathfindingCore.findPath(grid, startGridX, startGridY, endGridX, endGridY)

	if not path then
		return nil
	end

	-- Optimize path
	if optimizationOptions then
		path = PathSmoothing.optimizePath(path, grid, optimizationOptions)
	end

	return path
end

-- Create a grid from Roblox workspace terrain
function Pathfinding.createGridFromRegion(
	region: Region3,
	cellSize: number,
	checkFunction: ((Vector3) -> boolean)?
): PathfindingGrid
	local size = region.Size
	local position = region.CFrame.Position

	local width = math.ceil(size.X / cellSize)
	local height = math.ceil(size.Z / cellSize)

	local originX = position.X - size.X / 2
	local originZ = position.Z - size.Z / 2

	local grid = PathfindingCore.createGrid(width, height, cellSize, originX, originZ)

	-- If a check function is provided, use it to determine walkability
	if checkFunction then
		for y = 1, height do
			for x = 1, width do
				local worldX, worldZ = PathfindingCore.gridToWorld(grid, x, y)
				local worldPos = Vector3.new(worldX, position.Y, worldZ)

				if not checkFunction(worldPos) then
					PathfindingCore.setNodeWalkable(grid, x, y, false)
				end
			end
		end
	end

	return grid
end

-- Visualize grid in workspace (for debugging)
function Pathfinding.visualizeGrid(grid: PathfindingGrid, parent: Instance?)
	parent = parent or workspace

	local folder = Instance.new("Folder")
	folder.Name = "PathfindingGrid"
	folder.Parent = parent

	for y = 1, grid.height do
		for x = 1, grid.width do
			local node = grid.nodes[y][x]
			local worldX, worldZ = PathfindingCore.gridToWorld(grid, x, y)

			local part = Instance.new("Part")
			part.Name = `Cell_{x}_{y}`
			part.Size = Vector3.new(grid.cellSize * 0.9, 0.5, grid.cellSize * 0.9)
			part.Position = Vector3.new(worldX, 0.25, worldZ)
			part.Anchored = true
			part.CanCollide = false
			part.Transparency = 0.7

			if node.walkable then
				if node.cost > 1.0 then
					part.Color = Color3.fromRGB(255, 255, 0) -- Yellow for high cost
				else
					part.Color = Color3.fromRGB(0, 255, 0) -- Green for walkable
				end
			else
				part.Color = Color3.fromRGB(255, 0, 0) -- Red for unwalkable
			end

			part.Parent = folder
		end
	end

	return folder
end

-- Visualize a path in workspace (for debugging)
function Pathfinding.visualizePath(path: { PathPoint }, parent: Instance?, color: Color3?)
	parent = parent or workspace
	color = color or Color3.fromRGB(0, 150, 255)

	local folder = Instance.new("Folder")
	folder.Name = "PathVisualization"
	folder.Parent = parent

	-- Draw waypoints
	for i, point in ipairs(path) do
		local part = Instance.new("Part")
		part.Name = `Waypoint_{i}`
		part.Size = Vector3.new(1, 1, 1)
		part.Position = Vector3.new(point.x, 1, point.z)
		part.Anchored = true
		part.CanCollide = false
		part.Shape = Enum.PartType.Ball
		part.Color = color
		part.Material = Enum.Material.Neon
		part.Parent = folder

		-- Draw line to next waypoint
		if i < #path then
			local nextPoint = path[i + 1]
			local startPos = Vector3.new(point.x, 1, point.z)
			local endPos = Vector3.new(nextPoint.x, 1, nextPoint.z)
			local distance = (endPos - startPos).Magnitude

			local line = Instance.new("Part")
			line.Name = `Line_{i}`
			line.Size = Vector3.new(0.2, 0.2, distance)
			line.CFrame = CFrame.lookAt((startPos + endPos) / 2, endPos)
			line.Anchored = true
			line.CanCollide = false
			line.Color = color
			line.Material = Enum.Material.Neon
			line.Parent = folder
		end
	end

	return folder
end

return Pathfinding
