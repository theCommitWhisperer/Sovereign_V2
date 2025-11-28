--!strict
-- BoundsManager: Enforces camera boundaries and limits
-- Keeps camera within playable area, enforces height/rotation limits

export type Bounds = {
	MinX: number?,
	MaxX: number?,
	MinZ: number?,
	MaxZ: number?,
	MinY: number?,
	MaxY: number?,
}

local BoundsManager = {}
BoundsManager.__index = BoundsManager

function BoundsManager.new()
	local self = setmetatable({}, BoundsManager)

	-- Boundary settings
	self.bounds = {
		MinX = nil,
		MaxX = nil,
		MinZ = nil,
		MaxZ = nil,
		MinY = 0, -- Ground level
		MaxY = nil,
	}

	self.enabled = false
	self.useSoftBounds = true -- Smooth clamping vs hard stops
	self.boundsPadding = 10 -- Extra padding from edges

	return self
end

function BoundsManager:SetEnabled(enabled: boolean)
	self.enabled = enabled
end

function BoundsManager:SetBounds(bounds: Bounds)
	-- Update bounds (nil values mean no limit in that direction)
	for key, value in pairs(bounds) do
		self.bounds[key] = value
	end
end

function BoundsManager:SetBoundsFromRegion(minCorner: Vector3, maxCorner: Vector3)
	self.bounds.MinX = minCorner.X
	self.bounds.MaxX = maxCorner.X
	self.bounds.MinZ = minCorner.Z
	self.bounds.MaxZ = maxCorner.Z
	self.bounds.MinY = minCorner.Y
	self.bounds.MaxY = maxCorner.Y
end

function BoundsManager:SetBoundsFromPart(part: BasePart, padding: number?)
	local size = part.Size
	local position = part.Position
	local pad = padding or self.boundsPadding

	self.bounds.MinX = position.X - size.X / 2 + pad
	self.bounds.MaxX = position.X + size.X / 2 - pad
	self.bounds.MinZ = position.Z - size.Z / 2 + pad
	self.bounds.MaxZ = position.Z + size.Z / 2 - pad
	self.bounds.MinY = position.Y - size.Y / 2
	self.bounds.MaxY = position.Y + size.Y / 2
end

function BoundsManager:ClearBounds()
	self.bounds = {
		MinX = nil,
		MaxX = nil,
		MinZ = nil,
		MaxZ = nil,
		MinY = 0,
		MaxY = nil,
	}
end

function BoundsManager:ClampPosition(position: Vector3): Vector3
	if not self.enabled then
		return position
	end

	local clampedPosition = position

	-- Clamp X axis
	if self.bounds.MinX and clampedPosition.X < self.bounds.MinX then
		clampedPosition = Vector3.new(self.bounds.MinX, clampedPosition.Y, clampedPosition.Z)
	end
	if self.bounds.MaxX and clampedPosition.X > self.bounds.MaxX then
		clampedPosition = Vector3.new(self.bounds.MaxX, clampedPosition.Y, clampedPosition.Z)
	end

	-- Clamp Y axis
	if self.bounds.MinY and clampedPosition.Y < self.bounds.MinY then
		clampedPosition = Vector3.new(clampedPosition.X, self.bounds.MinY, clampedPosition.Z)
	end
	if self.bounds.MaxY and clampedPosition.Y > self.bounds.MaxY then
		clampedPosition = Vector3.new(clampedPosition.X, self.bounds.MaxY, clampedPosition.Z)
	end

	-- Clamp Z axis
	if self.bounds.MinZ and clampedPosition.Z < self.bounds.MinZ then
		clampedPosition = Vector3.new(clampedPosition.X, clampedPosition.Y, self.bounds.MinZ)
	end
	if self.bounds.MaxZ and clampedPosition.Z > self.bounds.MaxZ then
		clampedPosition = Vector3.new(clampedPosition.X, clampedPosition.Y, self.bounds.MaxZ)
	end

	return clampedPosition
end

function BoundsManager:SoftClampPosition(position: Vector3, dampingFactor: number): Vector3
	if not self.enabled or not self.useSoftBounds then
		return self:ClampPosition(position)
	end

	-- Soft clamping: gradually push back when approaching bounds
	local softPosition = position
	local damping = math.clamp(dampingFactor, 0.01, 0.99)

	-- X axis soft clamping
	if self.bounds.MinX and softPosition.X < self.bounds.MinX then
		softPosition = softPosition:Lerp(
			Vector3.new(self.bounds.MinX, softPosition.Y, softPosition.Z),
			1 - damping
		)
	end
	if self.bounds.MaxX and softPosition.X > self.bounds.MaxX then
		softPosition = softPosition:Lerp(
			Vector3.new(self.bounds.MaxX, softPosition.Y, softPosition.Z),
			1 - damping
		)
	end

	-- Y axis soft clamping
	if self.bounds.MinY and softPosition.Y < self.bounds.MinY then
		softPosition = softPosition:Lerp(
			Vector3.new(softPosition.X, self.bounds.MinY, softPosition.Z),
			1 - damping
		)
	end
	if self.bounds.MaxY and softPosition.Y > self.bounds.MaxY then
		softPosition = softPosition:Lerp(
			Vector3.new(softPosition.X, self.bounds.MaxY, softPosition.Z),
			1 - damping
		)
	end

	-- Z axis soft clamping
	if self.bounds.MinZ and softPosition.Z < self.bounds.MinZ then
		softPosition = softPosition:Lerp(
			Vector3.new(softPosition.X, softPosition.Y, self.bounds.MinZ),
			1 - damping
		)
	end
	if self.bounds.MaxZ and softPosition.Z > self.bounds.MaxZ then
		softPosition = softPosition:Lerp(
			Vector3.new(softPosition.X, softPosition.Y, self.bounds.MaxZ),
			1 - damping
		)
	end

	return softPosition
end

function BoundsManager:IsInBounds(position: Vector3): boolean
	if not self.enabled then
		return true
	end

	if self.bounds.MinX and position.X < self.bounds.MinX then
		return false
	end
	if self.bounds.MaxX and position.X > self.bounds.MaxX then
		return false
	end
	if self.bounds.MinY and position.Y < self.bounds.MinY then
		return false
	end
	if self.bounds.MaxY and position.Y > self.bounds.MaxY then
		return false
	end
	if self.bounds.MinZ and position.Z < self.bounds.MinZ then
		return false
	end
	if self.bounds.MaxZ and position.Z > self.bounds.MaxZ then
		return false
	end

	return true
end

function BoundsManager:GetDistanceFromBounds(position: Vector3): number
	if not self.enabled then
		return math.huge
	end

	local minDistance = math.huge

	-- Check distance from each bound
	if self.bounds.MinX then
		minDistance = math.min(minDistance, math.abs(position.X - self.bounds.MinX))
	end
	if self.bounds.MaxX then
		minDistance = math.min(minDistance, math.abs(position.X - self.bounds.MaxX))
	end
	if self.bounds.MinZ then
		minDistance = math.min(minDistance, math.abs(position.Z - self.bounds.MinZ))
	end
	if self.bounds.MaxZ then
		minDistance = math.min(minDistance, math.abs(position.Z - self.bounds.MaxZ))
	end

	return minDistance
end

function BoundsManager:GetBounds(): Bounds
	return table.clone(self.bounds)
end

function BoundsManager:SetSoftBounds(enabled: boolean)
	self.useSoftBounds = enabled
end

function BoundsManager:SetBoundsPadding(padding: number)
	self.boundsPadding = padding
end

return BoundsManager
