--!strict
-- CameraRig: Manages camera transform (position, rotation, zoom)
-- Uses spherical coordinates for Studio-style camera behavior

local Workspace = game:GetService("Workspace")

export type CameraSettings = {
	DefaultHeight: number,
	DefaultAngle: number,
	DefaultYaw: number,
	MinHeight: number,
	MaxHeight: number,
	MinPitch: number,
	MaxPitch: number,
	ZoomSpeed: number,
	RotationSpeed: number,
	PanSpeed: number,
	MoveSpeed: number,
}

local DEFAULT_SETTINGS: CameraSettings = {
	DefaultHeight = 80,
	DefaultAngle = 55, -- More top-down default angle
	DefaultYaw = 0,
	MinHeight = 20,
	MaxHeight = 200,
	MinPitch = math.rad(-75), -- Limit how steep you can look (more top-down)
	MaxPitch = math.rad(-35), -- Limit how shallow you can look (prevent extreme horizontal)
	ZoomSpeed = 5,
	RotationSpeed = 0.003,
	PanSpeed = 0.5,
	MoveSpeed = 30,
}

local CameraRig = {}
CameraRig.__index = CameraRig

function CameraRig.new(settings: CameraSettings?)
	local self = setmetatable({}, CameraRig)

	-- Merge provided settings with defaults
	self.settings = settings or DEFAULT_SETTINGS
	if settings then
		for key, value in pairs(DEFAULT_SETTINGS) do
			if self.settings[key] == nil then
				self.settings[key] = value
			end
		end
	end

	-- Camera state (spherical coordinates)
	self.focalPoint = Vector3.new(0, 0, 0) -- The point the camera orbits around
	self.distance = self.settings.DefaultHeight -- Distance from focal point
	self.yaw = math.rad(self.settings.DefaultYaw) -- Horizontal rotation (radians)
	self.pitch = math.rad(-self.settings.DefaultAngle) -- Vertical angle (radians, negative = looking down)

	-- Camera reference
	self.camera = Workspace.CurrentCamera

	return self
end

function CameraRig:Initialize(startPosition: Vector3)
	self.focalPoint = startPosition
	self:UpdateCamera()
end

function CameraRig:SetFocalPoint(position: Vector3)
	self.focalPoint = position
end

function CameraRig:GetFocalPoint(): Vector3
	return self.focalPoint
end

function CameraRig:SetDistance(distance: number)
	self.distance = math.clamp(distance, self.settings.MinHeight, self.settings.MaxHeight)
end

function CameraRig:GetDistance(): number
	return self.distance
end

function CameraRig:Zoom(delta: number)
	self.distance = math.clamp(
		self.distance + delta * self.settings.ZoomSpeed,
		self.settings.MinHeight,
		self.settings.MaxHeight
	)
end

function CameraRig:Rotate(deltaX: number, deltaY: number)
	-- Rotate camera based on mouse movement (Studio-style)
	self.yaw = self.yaw - deltaX * self.settings.RotationSpeed
	self.pitch = self.pitch + deltaY * self.settings.RotationSpeed

	-- Clamp pitch to prevent camera from going upside down
	self.pitch = math.clamp(self.pitch, self.settings.MinPitch, self.settings.MaxPitch)
end

function CameraRig:Pan(deltaX: number, deltaY: number)
	-- Convert screen space movement to world space (relative to camera orientation)
	local right = self.camera.CFrame.RightVector
	local forward = (self.camera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit

	self.focalPoint = self.focalPoint - (right * deltaX * self.settings.PanSpeed)
		+ (forward * deltaY * self.settings.PanSpeed)
end

function CameraRig:Move(direction: Vector3, deltaTime: number)
	-- Move camera in world space relative to camera rotation
	-- Scale movement speed based on zoom level (faster when zoomed out)
	local moveSpeed = self.settings.MoveSpeed + (self.distance - self.settings.MinHeight) * 1.5

	-- Apply camera rotation to movement direction
	local rotatedMove = CFrame.Angles(0, self.yaw, 0) * direction.Unit

	self.focalPoint = self.focalPoint + (rotatedMove * deltaTime * moveSpeed)
end

function CameraRig:FocusOn(position: Vector3, distance: number?)
	self.focalPoint = position
	if distance then
		self.distance = math.clamp(distance, self.settings.MinHeight, self.settings.MaxHeight)
	end
end

function CameraRig:UpdateCamera()
	-- Calculate camera position maintaining constant height (RTS-style)
	-- self.distance represents the height (Y-axis offset) from the focal point

	-- Calculate horizontal distance based on pitch angle to maintain constant height
	local heightOffset = self.distance
	local horizontalDistance = heightOffset / math.tan(math.abs(self.pitch))

	-- Calculate camera offset using pitch and yaw
	local offsetX = horizontalDistance * math.sin(self.yaw)
	local offsetY = heightOffset
	local offsetZ = horizontalDistance * math.cos(self.yaw)

	local cameraPosition = self.focalPoint + Vector3.new(offsetX, offsetY, offsetZ)

	-- Create camera CFrame looking at the focal point
	self.camera.CFrame = CFrame.lookAt(cameraPosition, self.focalPoint)
end

function CameraRig:GetCameraPosition(): Vector3
	return self.camera.CFrame.Position
end

function CameraRig:GetCameraRotation(): (number, number)
	return self.yaw, self.pitch
end

function CameraRig:SetCameraRotation(yaw: number, pitch: number)
	self.yaw = yaw
	self.pitch = math.clamp(pitch, self.settings.MinPitch, self.settings.MaxPitch)
end

function CameraRig:Reset(position: Vector3?)
	if position then
		self.focalPoint = position
	end
	self.distance = self.settings.DefaultHeight
	self.yaw = math.rad(self.settings.DefaultYaw)
	self.pitch = math.rad(-self.settings.DefaultAngle)
end

function CameraRig:GetSettings(): CameraSettings
	return self.settings
end

function CameraRig:UpdateSettings(newSettings: CameraSettings)
	-- Update settings while maintaining current state within new bounds
	for key, value in pairs(newSettings) do
		self.settings[key] = value
	end

	-- Re-clamp current values to new limits
	self.distance = math.clamp(self.distance, self.settings.MinHeight, self.settings.MaxHeight)
	self.pitch = math.clamp(self.pitch, self.settings.MinPitch, self.settings.MaxPitch)
end

return CameraRig
