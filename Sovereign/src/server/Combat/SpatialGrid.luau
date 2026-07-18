--!strict
-- SpatialGrid: Uniform hash grid for O(1)-ish proximity queries over combat entities.
-- Replaces the old O(n²) nearest-enemy scan. Keyed by Model.

local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

export type SpatialGrid = typeof(setmetatable(
	{} :: {
		cellSize: number,
		cells: { [number]: { [Model]: Vector3 } },
		entityCell: { [Model]: number },
	},
	SpatialGrid
))

local FLOOR = math.floor

-- Pack 2D cell coords into one number key (offset to keep positive)
local function cellKey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

function SpatialGrid.new(cellSize: number): SpatialGrid
	return setmetatable({
		cellSize = cellSize,
		cells = {},
		entityCell = {},
	}, SpatialGrid) :: SpatialGrid
end

function SpatialGrid.update(self: SpatialGrid, entity: Model, position: Vector3)
	local cx = FLOOR(position.X / self.cellSize)
	local cz = FLOOR(position.Z / self.cellSize)
	local key = cellKey(cx, cz)

	local oldKey = self.entityCell[entity]
	if oldKey == key then
		local cell = self.cells[key]
		if cell then
			cell[entity] = position
		end
		return
	end

	if oldKey then
		local oldCell = self.cells[oldKey]
		if oldCell then
			oldCell[entity] = nil
			if next(oldCell) == nil then
				self.cells[oldKey] = nil
			end
		end
	end

	local cell = self.cells[key]
	if not cell then
		cell = {}
		self.cells[key] = cell
	end
	cell[entity] = position
	self.entityCell[entity] = key
end

function SpatialGrid.remove(self: SpatialGrid, entity: Model)
	local key = self.entityCell[entity]
	if key then
		local cell = self.cells[key]
		if cell then
			cell[entity] = nil
			if next(cell) == nil then
				self.cells[key] = nil
			end
		end
		self.entityCell[entity] = nil
	end
end

-- Calls visitor(entity, position) for every entity within `radius` of `position`.
-- Visitor may return true to stop early.
function SpatialGrid.query(
	self: SpatialGrid,
	position: Vector3,
	radius: number,
	visitor: (Model, Vector3) -> boolean?
)
	local minX = FLOOR((position.X - radius) / self.cellSize)
	local maxX = FLOOR((position.X + radius) / self.cellSize)
	local minZ = FLOOR((position.Z - radius) / self.cellSize)
	local maxZ = FLOOR((position.Z + radius) / self.cellSize)
	local radiusSq = radius * radius

	for cx = minX, maxX do
		for cz = minZ, maxZ do
			local cell = self.cells[cellKey(cx, cz)]
			if cell then
				for entity, pos in cell do
					local dx = pos.X - position.X
					local dz = pos.Z - position.Z
					if dx * dx + dz * dz <= radiusSq then
						if visitor(entity, pos) == true then
							return
						end
					end
				end
			end
		end
	end
end

function SpatialGrid.clear(self: SpatialGrid)
	table.clear(self.cells)
	table.clear(self.entityCell)
end

return SpatialGrid
