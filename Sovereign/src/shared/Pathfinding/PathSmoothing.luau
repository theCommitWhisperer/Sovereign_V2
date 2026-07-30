--!strict
-- PathSmoothing: Optimize and smooth pathfinding results
-- Includes: String pulling, path simplification, and Catmull-Rom splines

local PathSmoothing = {}

export type PathPoint = {
	x: number,
	z: number,
}

-- Check if there's a clear line of sight between two points
-- This is a simplified version - you may want to integrate with your grid for actual collision checks
local function hasLineOfSight(
	grid: any,
	x1: number,
	z1: number,
	x2: number,
	z2: number
): boolean
	-- Bresenham-like algorithm to check all cells along the line
	local dx = math.abs(x2 - x1)
	local dz = math.abs(z2 - z1)
	local steps = math.max(dx, dz) / grid.cellSize

	if steps < 1 then
		return true
	end

	for i = 0, steps do
		local t = i / steps
		local x = x1 + (x2 - x1) * t
		local z = z1 + (z2 - z1) * t

		-- Convert to grid coordinates
		local gridX = math.floor((x - grid.originX) / grid.cellSize) + 1
		local gridY = math.floor((z - grid.originZ) / grid.cellSize) + 1

		-- Check if valid and walkable
		if
			gridX < 1
			or gridX > grid.width
			or gridY < 1
			or gridY > grid.height
			or not grid.nodes[gridY][gridX].walkable
		then
			return false
		end
	end

	return true
end

-- String pulling algorithm (funnel algorithm simplified)
-- Removes unnecessary waypoints by checking line of sight
function PathSmoothing.stringPull(path: { PathPoint }, grid: any?): { PathPoint }
	if #path <= 2 then
		return path
	end

	local smoothed: { PathPoint } = {}
	table.insert(smoothed, path[1])

	local currentIndex = 1

	while currentIndex < #path do
		local currentPoint = path[currentIndex]
		local farthestIndex = currentIndex + 1

		-- Find the farthest point we can reach in a straight line
		for i = currentIndex + 2, #path do
			if grid and hasLineOfSight(grid, currentPoint.x, currentPoint.z, path[i].x, path[i].z) then
				farthestIndex = i
			else
				break
			end
		end

		-- Add the farthest reachable point
		if farthestIndex ~= currentIndex then
			table.insert(smoothed, path[farthestIndex])
			currentIndex = farthestIndex
		else
			currentIndex += 1
		end
	end

	return smoothed
end

-- Simplify path by removing collinear points
function PathSmoothing.simplifyPath(path: { PathPoint }, tolerance: number?): { PathPoint }
	tolerance = tolerance or 0.1

	if #path <= 2 then
		return path
	end

	local simplified: { PathPoint } = {}
	table.insert(simplified, path[1])

	for i = 2, #path - 1 do
		local prev = path[i - 1]
		local current = path[i]
		local next = path[i + 1]

		-- Calculate the angle between vectors
		local v1x = current.x - prev.x
		local v1z = current.z - prev.z
		local v2x = next.x - current.x
		local v2z = next.z - current.z

		-- Normalize vectors
		local len1 = math.sqrt(v1x * v1x + v1z * v1z)
		local len2 = math.sqrt(v2x * v2x + v2z * v2z)

		if len1 > 0 and len2 > 0 then
			v1x /= len1
			v1z /= len1
			v2x /= len2
			v2z /= len2

			-- Dot product to check if vectors are similar
			local dot = v1x * v2x + v1z * v2z

			-- If not nearly collinear, keep the point
			if dot < 1.0 - tolerance then
				table.insert(simplified, current)
			end
		end
	end

	table.insert(simplified, path[#path])

	return simplified
end

-- Smooth path using Catmull-Rom splines
function PathSmoothing.smoothWithSpline(path: { PathPoint }, segments: number?): { PathPoint }
	segments = segments or 5

	if #path <= 2 then
		return path
	end

	local smoothed: { PathPoint } = {}

	-- Add first point
	table.insert(smoothed, path[1])

	-- For each segment between waypoints
	for i = 1, #path - 1 do
		local p0 = path[math.max(1, i - 1)]
		local p1 = path[i]
		local p2 = path[i + 1]
		local p3 = path[math.min(#path, i + 2)]

		-- Create smooth curve between p1 and p2
		for j = 1, segments do
			local t = j / segments
			local t2 = t * t
			local t3 = t2 * t

			-- Catmull-Rom basis functions
			local x = 0.5
				* (
					(2 * p1.x)
					+ (-p0.x + p2.x) * t
					+ (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
					+ (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3
				)

			local z = 0.5
				* (
					(2 * p1.z)
					+ (-p0.z + p2.z) * t
					+ (2 * p0.z - 5 * p1.z + 4 * p2.z - p3.z) * t2
					+ (-p0.z + 3 * p1.z - 3 * p2.z + p3.z) * t3
				)

			if j < segments or i == #path - 1 then
				table.insert(smoothed, { x = x, z = z })
			end
		end
	end

	return smoothed
end

-- Calculate path length
function PathSmoothing.getPathLength(path: { PathPoint }): number
	local length = 0

	for i = 1, #path - 1 do
		local dx = path[i + 1].x - path[i].x
		local dz = path[i + 1].z - path[i].z
		length += math.sqrt(dx * dx + dz * dz)
	end

	return length
end

-- Resample path to have evenly spaced points
function PathSmoothing.resamplePath(path: { PathPoint }, spacing: number): { PathPoint }
	if #path <= 1 then
		return path
	end

	local resampled: { PathPoint } = {}
	table.insert(resampled, path[1])

	local totalLength = PathSmoothing.getPathLength(path)
	local numPoints = math.max(2, math.floor(totalLength / spacing))

	local currentLength = 0
	local targetLength = spacing
	local currentSegment = 1

	while currentSegment < #path and #resampled < numPoints do
		local p1 = path[currentSegment]
		local p2 = path[currentSegment + 1]

		local dx = p2.x - p1.x
		local dz = p2.z - p1.z
		local segmentLength = math.sqrt(dx * dx + dz * dz)

		if currentLength + segmentLength >= targetLength then
			-- Interpolate point on this segment
			local t = (targetLength - currentLength) / segmentLength
			local newPoint = {
				x = p1.x + dx * t,
				z = p1.z + dz * t,
			}
			table.insert(resampled, newPoint)
			targetLength += spacing
		else
			currentLength += segmentLength
			currentSegment += 1
		end
	end

	-- Always include the last point
	if resampled[#resampled] ~= path[#path] then
		table.insert(resampled, path[#path])
	end

	return resampled
end

-- Full path optimization pipeline
function PathSmoothing.optimizePath(
	path: { PathPoint },
	grid: any?,
	options: {
		stringPull: boolean?,
		simplify: boolean?,
		smooth: boolean?,
		resample: boolean?,
		resampleSpacing: number?,
	}?
): { PathPoint }
	options = options or {}

	local optimized = path

	-- String pulling (remove unnecessary waypoints)
	if options.stringPull ~= false and grid then
		optimized = PathSmoothing.stringPull(optimized, grid)
	end

	-- Simplify (remove collinear points)
	if options.simplify ~= false then
		optimized = PathSmoothing.simplifyPath(optimized)
	end

	-- Smooth with splines
	if options.smooth then
		optimized = PathSmoothing.smoothWithSpline(optimized, 3)
	end

	-- Resample to even spacing
	if options.resample and options.resampleSpacing then
		optimized = PathSmoothing.resamplePath(optimized, options.resampleSpacing)
	end

	return optimized
end

return PathSmoothing
