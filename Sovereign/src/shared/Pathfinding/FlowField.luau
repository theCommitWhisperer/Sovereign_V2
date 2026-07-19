--!strict
-- FlowField: Dijkstra integration field over a pathfinding grid.
--
-- For group movement, computing one A* path per unit to the same destination
-- is wasteful and produces conflicting routes. A flow field instead solves the
-- whole grid ONCE from the goal outward: every walkable cell stores its cost
-- to the goal, and a unit simply steps toward its lowest-cost neighbour. Any
-- number of units share the same field, so a 60-unit move order costs one
-- solve instead of 60.

local PathfindingCore = require(script.Parent.PathfindingCore)

local FlowField = {}
FlowField.__index = FlowField

type Grid = PathfindingCore.PathfindingGrid

export type FlowField = {
	grid: Grid,
	goalX: number, -- goal grid coords
	goalY: number,
	cost: { { number } }, -- cost[y][x]; math.huge = unreachable/blocked
	width: number,
	height: number,
}

local SQRT2 = math.sqrt(2)
local HUGE = math.huge

-- 8-neighbour offsets with movement cost
local NEIGHBORS = {
	{ 0, -1, 1 },
	{ 0, 1, 1 },
	{ -1, 0, 1 },
	{ 1, 0, 1 },
	{ -1, -1, SQRT2 },
	{ 1, -1, SQRT2 },
	{ -1, 1, SQRT2 },
	{ 1, 1, SQRT2 },
}

-- ── Tiny binary min-heap (avoids a full O(n²) Dijkstra on big grids) ────────
type Heap = { size: number, cost: { number }, x: { number }, y: { number } }

local function heapPush(heap: Heap, cost: number, x: number, y: number)
	local i = heap.size + 1
	heap.size = i
	heap.cost[i] = cost
	heap.x[i] = x
	heap.y[i] = y
	while i > 1 do
		local parent = i // 2
		if heap.cost[parent] <= heap.cost[i] then
			break
		end
		heap.cost[parent], heap.cost[i] = heap.cost[i], heap.cost[parent]
		heap.x[parent], heap.x[i] = heap.x[i], heap.x[parent]
		heap.y[parent], heap.y[i] = heap.y[i], heap.y[parent]
		i = parent
	end
end

local function heapPop(heap: Heap): (number, number, number)
	local cost = heap.cost[1]
	local x = heap.x[1]
	local y = heap.y[1]
	local size = heap.size
	heap.cost[1] = heap.cost[size]
	heap.x[1] = heap.x[size]
	heap.y[1] = heap.y[size]
	heap.cost[size] = nil :: any
	heap.x[size] = nil :: any
	heap.y[size] = nil :: any
	heap.size = size - 1

	local i = 1
	while true do
		local left = i * 2
		local right = left + 1
		local smallest = i
		if left <= heap.size and heap.cost[left] < heap.cost[smallest] then
			smallest = left
		end
		if right <= heap.size and heap.cost[right] < heap.cost[smallest] then
			smallest = right
		end
		if smallest == i then
			break
		end
		heap.cost[smallest], heap.cost[i] = heap.cost[i], heap.cost[smallest]
		heap.x[smallest], heap.x[i] = heap.x[i], heap.x[smallest]
		heap.y[smallest], heap.y[i] = heap.y[i], heap.y[smallest]
		i = smallest
	end

	return cost, x, y
end

-- Compute an integration field from a goal world position. Returns nil if the
-- goal cell is unwalkable (caller should fall back to per-unit A*).
function FlowField.compute(grid: Grid, goalWorldX: number, goalWorldZ: number): FlowField?
	local goalX, goalY = PathfindingCore.worldToGrid(grid, goalWorldX, goalWorldZ)
	if not PathfindingCore.isValidNode(grid, goalX, goalY) then
		return nil
	end
	if not grid.nodes[goalY][goalX].walkable then
		return nil
	end

	-- cost[y][x] initialised to HUGE
	local cost: { { number } } = {}
	for y = 1, grid.height do
		local row = table.create(grid.width, HUGE)
		cost[y] = row
	end

	local heap: Heap = { size = 0, cost = {}, x = {}, y = {} }
	cost[goalY][goalX] = 0
	heapPush(heap, 0, goalX, goalY)

	local nodes = grid.nodes
	while heap.size > 0 do
		local curCost, cx, cy = heapPop(heap)
		if curCost <= cost[cy][cx] then
			for _, offset in NEIGHBORS do
				local nx = cx + offset[1]
				local ny = cy + offset[2]
				if nx >= 1 and nx <= grid.width and ny >= 1 and ny <= grid.height then
					local node = nodes[ny][nx]
					if node.walkable then
						-- Diagonal moves require both shared cardinals clear so
						-- units don't clip building corners
						local passable = true
						if offset[3] > 1 then
							if not nodes[cy][nx].walkable or not nodes[ny][cx].walkable then
								passable = false
							end
						end
						if passable then
							local stepCost = offset[3] * (node.cost or 1)
							local newCost = curCost + stepCost
							if newCost < cost[ny][nx] then
								cost[ny][nx] = newCost
								heapPush(heap, newCost, nx, ny)
							end
						end
					end
				end
			end
		end
	end

	return setmetatable({
		grid = grid,
		goalX = goalX,
		goalY = goalY,
		cost = cost,
		width = grid.width,
		height = grid.height,
	}, FlowField) :: any
end

-- Desired horizontal direction (Vector3, y=0) toward the goal from a world
-- position. Returns Vector3.zero at/near the goal or on an unreachable cell.
function FlowField.sampleDirection(field: FlowField, worldX: number, worldZ: number): Vector3
	local grid = field.grid
	local gx, gy = PathfindingCore.worldToGrid(grid, worldX, worldZ)
	local cost = field.cost

	if gx == field.goalX and gy == field.goalY then
		return Vector3.zero
	end

	-- Pick the reachable neighbour with the lowest cost, and steer toward its
	-- world centre. Using the actual neighbour centre (not just the gradient
	-- sign) keeps motion smooth and diagonal.
	local bestCost = cost[gy][gx]
	local bestX, bestY = gx, gy
	for _, offset in NEIGHBORS do
		local nx = gx + offset[1]
		local ny = gy + offset[2]
		if nx >= 1 and nx <= field.width and ny >= 1 and ny <= field.height then
			local c = cost[ny][nx]
			if c < bestCost then
				bestCost = c
				bestX, bestY = nx, ny
			end
		end
	end

	if bestX == gx and bestY == gy then
		return Vector3.zero -- local minimum / unreachable
	end

	local worldTargetX, worldTargetZ = PathfindingCore.gridToWorld(grid, bestX, bestY)
	local dir = Vector3.new(worldTargetX - worldX, 0, worldTargetZ - worldZ)
	if dir.Magnitude < 0.001 then
		return Vector3.zero
	end
	return dir.Unit
end

-- Is the goal reachable from this world position (cost is finite)?
function FlowField.isReachable(field: FlowField, worldX: number, worldZ: number): boolean
	local gx, gy = PathfindingCore.worldToGrid(field.grid, worldX, worldZ)
	return field.cost[gy][gx] < HUGE
end

return FlowField
