--!strict
-- PathfindingCore: Core A* pathfinding implementation for RTS games
-- Optimized for Roblox with grid-based navigation

local PathfindingCore = {}

-- Priority Queue implementation for A* open set
local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new()
	return setmetatable({
		items = {},
		count = 0,
	}, PriorityQueue)
end

function PriorityQueue:push(item, priority)
	self.count += 1
	table.insert(self.items, { item = item, priority = priority })

	-- Bubble up
	local index = self.count
	while index > 1 do
		local parentIndex = math.floor(index / 2)
		if self.items[index].priority >= self.items[parentIndex].priority then
			break
		end
		self.items[index], self.items[parentIndex] = self.items[parentIndex], self.items[index]
		index = parentIndex
	end
end

function PriorityQueue:pop()
	if self.count == 0 then
		return nil
	end

	local result = self.items[1].item
	self.items[1] = self.items[self.count]
	table.remove(self.items, self.count)
	self.count -= 1

	-- Bubble down
	local index = 1
	while true do
		local leftChild = index * 2
		local rightChild = index * 2 + 1
		local smallest = index

		if leftChild <= self.count and self.items[leftChild].priority < self.items[smallest].priority then
			smallest = leftChild
		end
		if rightChild <= self.count and self.items[rightChild].priority < self.items[smallest].priority then
			smallest = rightChild
		end

		if smallest == index then
			break
		end

		self.items[index], self.items[smallest] = self.items[smallest], self.items[index]
		index = smallest
	end

	return result
end

function PriorityQueue:isEmpty(): boolean
	return self.count == 0
end

-- Node structure for pathfinding
export type Node = {
	x: number,
	y: number,
	walkable: boolean,
	cost: number, -- Terrain cost multiplier (1 = normal, higher = slower)
}

export type GridNode = Node & {
	g: number, -- Cost from start
	h: number, -- Heuristic cost to end
	f: number, -- Total cost (g + h)
	parent: GridNode?,
}

export type PathfindingGrid = {
	width: number,
	height: number,
	cellSize: number,
	originX: number,
	originZ: number,
	nodes: { { Node } },
}

export type PathPoint = {
	x: number,
	z: number,
}

-- Create a new pathfinding grid
function PathfindingCore.createGrid(
	width: number,
	height: number,
	cellSize: number,
	originX: number,
	originZ: number
): PathfindingGrid
	local grid: PathfindingGrid = {
		width = width,
		height = height,
		cellSize = cellSize,
		originX = originX,
		originZ = originZ,
		nodes = {},
	}

	-- Initialize all nodes as walkable
	for y = 1, height do
		grid.nodes[y] = {}
		for x = 1, width do
			grid.nodes[y][x] = {
				x = x,
				y = y,
				walkable = true,
				cost = 1.0,
			}
		end
	end

	return grid
end

-- Convert world position to grid coordinates
function PathfindingCore.worldToGrid(
	grid: PathfindingGrid,
	worldX: number,
	worldZ: number
): (number, number)
	local gridX = math.floor((worldX - grid.originX) / grid.cellSize) + 1
	local gridY = math.floor((worldZ - grid.originZ) / grid.cellSize) + 1
	-- Clamp to grid bounds so units spawning just outside the grid
	-- get mapped to the nearest edge cell (which is always walkable)
	-- rather than triggering the out-of-bounds "unwalkable" path.
	gridX = math.clamp(gridX, 1, grid.width)
	gridY = math.clamp(gridY, 1, grid.height)
	return gridX, gridY
end

-- Convert grid coordinates to world position
function PathfindingCore.gridToWorld(
	grid: PathfindingGrid,
	gridX: number,
	gridY: number
): (number, number)
	local worldX = grid.originX + (gridX - 0.5) * grid.cellSize
	local worldZ = grid.originZ + (gridY - 0.5) * grid.cellSize
	return worldX, worldZ
end

-- Check if grid coordinates are valid
function PathfindingCore.isValidNode(grid: PathfindingGrid, x: number, y: number): boolean
	return x >= 1 and x <= grid.width and y >= 1 and y <= grid.height
end

-- Get neighbors of a node (8-directional movement)
function PathfindingCore.getNeighbors(grid: PathfindingGrid, node: Node): { Node }
	local neighbors = {}
	local x, y = node.x, node.y

	-- Cardinal directions
	local directions = {
		{ 0, -1, 1.0 }, -- North
		{ 1, 0, 1.0 }, -- East
		{ 0, 1, 1.0 }, -- South
		{ -1, 0, 1.0 }, -- West
		{ 1, -1, 1.414 }, -- Northeast
		{ 1, 1, 1.414 }, -- Southeast
		{ -1, 1, 1.414 }, -- Southwest
		{ -1, -1, 1.414 }, -- Northwest
	}

	for _, dir in ipairs(directions) do
		local nx, ny = x + dir[1], y + dir[2]

		if PathfindingCore.isValidNode(grid, nx, ny) then
			local neighbor = grid.nodes[ny][nx]

			-- For diagonal movement, check if both adjacent cardinal directions are walkable
			if dir[3] > 1.0 then
				local cardinalX = grid.nodes[y][nx]
				local cardinalY = grid.nodes[ny][x]
				if cardinalX.walkable and cardinalY.walkable and neighbor.walkable then
					table.insert(neighbors, neighbor)
				end
			elseif neighbor.walkable then
				table.insert(neighbors, neighbor)
			end
		end
	end

	return neighbors
end

-- Heuristic function (Octile distance for 8-directional movement)
function PathfindingCore.heuristic(nodeA: Node, nodeB: Node): number
	local dx = math.abs(nodeA.x - nodeB.x)
	local dy = math.abs(nodeA.y - nodeB.y)

	-- Octile distance (more accurate for 8-directional movement than Manhattan or Euclidean)
	local D = 1.0
	local D2 = 1.414
	return D * (dx + dy) + (D2 - 2 * D) * math.min(dx, dy)
end

-- A* pathfinding algorithm
function PathfindingCore.findPath(
	grid: PathfindingGrid,
	startX: number,
	startY: number,
	endX: number,
	endY: number
): { PathPoint }?
	-- Validate start and end positions
	if not PathfindingCore.isValidNode(grid, startX, startY) then
		warn("Start position out of bounds:", startX, startY)
		return nil
	end
	if not PathfindingCore.isValidNode(grid, endX, endY) then
		warn("End position out of bounds:", endX, endY)
		return nil
	end

	local startNode = grid.nodes[startY][startX]
	local endNode = grid.nodes[endY][endX]

	if not startNode.walkable then
		warn("Start position is not walkable")
		return nil
	end
	if not endNode.walkable then
		warn("End position is not walkable")
		return nil
	end

	-- If start == end, return empty path
	if startX == endX and startY == endY then
		return {}
	end

	-- Initialize data structures
	local openSet = PriorityQueue.new()
	local closedSet = {}
	local nodeData: { [Node]: GridNode } = {}

	-- Initialize start node
	local startData: GridNode = {
		x = startNode.x,
		y = startNode.y,
		walkable = startNode.walkable,
		cost = startNode.cost,
		g = 0,
		h = PathfindingCore.heuristic(startNode, endNode),
		f = 0,
		parent = nil,
	}
	startData.f = startData.g + startData.h
	nodeData[startNode] = startData

	openSet:push(startNode, startData.f)

	local maxIterations = grid.width * grid.height
	local iterations = 0

	while not openSet:isEmpty() and iterations < maxIterations do
		iterations += 1

		local currentNode = openSet:pop()
		if not currentNode then
			break
		end

		local currentData = nodeData[currentNode]

		-- Check if we reached the goal
		if currentNode.x == endX and currentNode.y == endY then
			-- Reconstruct path
			local path: { PathPoint } = {}
			local current = currentNode

			while current do
				local worldX, worldZ = PathfindingCore.gridToWorld(grid, current.x, current.y)
				table.insert(path, 1, { x = worldX, z = worldZ })
				current = nodeData[current].parent
			end

			return path
		end

		closedSet[currentNode] = true

		-- Check neighbors
		local neighbors = PathfindingCore.getNeighbors(grid, currentNode)
		for _, neighbor in ipairs(neighbors) do
			if closedSet[neighbor] then
				continue
			end

			-- Calculate movement cost
			local dx = math.abs(neighbor.x - currentNode.x)
			local dy = math.abs(neighbor.y - currentNode.y)
			local movementCost = if dx + dy == 2 then 1.414 else 1.0

			local tentativeG = currentData.g + movementCost * neighbor.cost

			-- Initialize neighbor data if needed
			if not nodeData[neighbor] then
				nodeData[neighbor] = {
					x = neighbor.x,
					y = neighbor.y,
					walkable = neighbor.walkable,
					cost = neighbor.cost,
					g = math.huge,
					h = PathfindingCore.heuristic(neighbor, endNode),
					f = math.huge,
					parent = nil,
				}
			end

			local neighborData = nodeData[neighbor]

			if tentativeG < neighborData.g then
				neighborData.parent = currentNode
				neighborData.g = tentativeG
				neighborData.f = neighborData.g + neighborData.h

				openSet:push(neighbor, neighborData.f)
			end
		end
	end

	-- No path found
	return nil
end

-- Set a node as walkable or unwalkable
function PathfindingCore.setNodeWalkable(
	grid: PathfindingGrid,
	x: number,
	y: number,
	walkable: boolean
)
	if PathfindingCore.isValidNode(grid, x, y) then
		grid.nodes[y][x].walkable = walkable
	end
end

-- Set terrain cost for a node
function PathfindingCore.setNodeCost(
	grid: PathfindingGrid,
	x: number,
	y: number,
	cost: number
)
	if PathfindingCore.isValidNode(grid, x, y) then
		grid.nodes[y][x].cost = math.max(0.1, cost)
	end
end

-- Set a rectangular area as walkable/unwalkable
function PathfindingCore.setAreaWalkable(
	grid: PathfindingGrid,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	walkable: boolean
)
	local minX = math.max(1, math.min(x1, x2))
	local maxX = math.min(grid.width, math.max(x1, x2))
	local minY = math.max(1, math.min(y1, y2))
	local maxY = math.min(grid.height, math.max(y1, y2))

	for y = minY, maxY do
		for x = minX, maxX do
			grid.nodes[y][x].walkable = walkable
		end
	end
end

return PathfindingCore
