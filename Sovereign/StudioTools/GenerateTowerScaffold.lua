--[[
	GenerateTowerScaffold — paste into the Roblox Studio COMMAND BAR and run.

	Two modes:
	1. NOTHING SELECTED  -> creates a new "Stone_Wall_Tower_Octagon" scaffold in
	   Workspace at the origin, with placeholder geometry you can replace.
	2. MODEL SELECTED    -> retrofits that model: adds Root, ConnectionPoints,
	   WalkwayDoors, GroundDoor, and attributes around its bounding box.
	   (Set OVERWRITE = false to keep existing marker folders.)

	Markers are color-coded neon so you can see and nudge them:
	  green  = ConnectionPoint (wall butt-join, LookVector points outward)
	  blue   = WalkwayDoor (upper door threshold, 30 studs above CP)
	  gold   = GroundDoor (ground entrance threshold)

	Adjust the CONFIG numbers below before running if needed.
]]

-- ======== CONFIG ========
local FACE_COUNT = 8 -- 8 = octagon (handles 45° + 90° corners), 4 = square
-- Explicit face bearings in degrees; overrides FACE_COUNT when set.
-- e.g. Tower_Corner_45 (90-to-45 / 45-to-90 corners): { 0, 135 }
--      Tower_Corner_90 (90-to-90 / 45-to-45 corners): { 0, 90 }
local FACE_ANGLES: { number }? = nil
local RADIUS = 12 -- Root -> connection face distance (match TowerRadius)
local WALKWAY_HEIGHT = 30 -- door floor height above ConnectionPoint (match Wall Segment)
local DOOR_WIDTH = 6
local DOOR_HEIGHT = 8
local GROUND_DOOR_FACE = 0 -- which face (0..FACE_COUNT-1) gets the ground door
local OVERWRITE = true -- retrofit mode: replace existing marker folders
local BUILD_PLACEHOLDER_BODY = true -- new-scaffold mode only
-- ========================

local Selection = game:GetService("Selection")

local function makeMarker(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 0.4
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Parent = parent
	return p
end

-- Resolve face bearings (explicit list wins over even spacing)
local faceAngles: { number } = {}
if FACE_ANGLES then
	faceAngles = FACE_ANGLES
else
	for i = 0, FACE_COUNT - 1 do
		table.insert(faceAngles, (360 / FACE_COUNT) * i)
	end
end
local faceCount = #faceAngles

local function faceDir(i: number): Vector3 -- i is 0-based
	local angle = math.rad(faceAngles[i + 1])
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

-- Resolve target model + ground-center reference
local selected = Selection:Get()[1]
local model: Model
local center: Vector3 -- ground-level center (XZ = tower axis, Y = ground)

if selected and selected:IsA("Model") then
	model = selected
	local cf, size = model:GetBoundingBox()
	center = Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)
	print(("[Scaffold] Retrofitting '%s' (ground center: %.1f, %.1f, %.1f)"):format(
		model.Name, center.X, center.Y, center.Z))
	if OVERWRITE then
		for _, name in { "ConnectionPoints", "WalkwayDoors", "GroundDoor", "Root" } do
			local old = model:FindFirstChild(name)
			if old then old:Destroy() end
		end
	end
else
	model = Instance.new("Model")
	if FACE_ANGLES then
		model.Name = "Stone_Wall_Tower_Custom" -- rename to e.g. Stone_Wall_Tower_Corner45
	else
		model.Name = "Stone_Wall_Tower_" .. (faceCount == 8 and "Octagon" or tostring(faceCount) .. "Face")
	end
	model.Parent = workspace
	center = Vector3.new(0, 0, 0)
	print("[Scaffold] Creating new scaffold '" .. model.Name .. "' at origin")
end

-- 1. Root (PrimaryPart, ground center)
local root = makeMarker("Root", Vector3.new(1, 1, 1),
	CFrame.new(center + Vector3.new(0, 0.5, 0)), Color3.fromRGB(255, 255, 255), model)
root.Transparency = 0.8
model.PrimaryPart = root
model.WorldPivot = CFrame.new(center)

-- 2. ConnectionPoints (oriented outward)
local cpFolder = Instance.new("Folder")
cpFolder.Name = "ConnectionPoints"
cpFolder.Parent = model

for i = 0, faceCount - 1 do
	local dir = faceDir(i)
	local pos = center + dir * RADIUS + Vector3.new(0, 0.5, 0)
	local cp = makeMarker("ConnectionPoint", Vector3.new(1, 1, 1),
		CFrame.lookAt(pos, pos + dir), Color3.fromRGB(0, 255, 0), cpFolder)
	cp:SetAttribute("FaceIndex", i)
end

-- 3. WalkwayDoors (threshold markers, floor at WALKWAY_HEIGHT above CP)
local wdFolder = Instance.new("Folder")
wdFolder.Name = "WalkwayDoors"
wdFolder.Parent = model

for i = 0, faceCount - 1 do
	local dir = faceDir(i)
	local pos = center + dir * RADIUS + Vector3.new(0, WALKWAY_HEIGHT + 0.5, 0)
	local wd = makeMarker("WalkwayDoor", Vector3.new(DOOR_WIDTH, 1, 1),
		CFrame.lookAt(pos, pos + dir), Color3.fromRGB(0, 128, 255), wdFolder)
	wd:SetAttribute("FaceIndex", i)
end

-- 4. GroundDoor (one face)
do
	local dir = faceDir(GROUND_DOOR_FACE)
	local pos = center + dir * RADIUS + Vector3.new(0, 0.5, 0)
	local gd = makeMarker("GroundDoor", Vector3.new(DOOR_WIDTH, 1, 1),
		CFrame.lookAt(pos, pos + dir), Color3.fromRGB(218, 165, 32), model)
	gd:SetAttribute("FaceIndex", GROUND_DOOR_FACE)
end

-- 5. Attributes
model:SetAttribute("TowerRadius", RADIUS)
model:SetAttribute("WalkwayHeight", WALKWAY_HEIGHT)
model:SetAttribute("ConnectionCount", faceCount)

-- 6. Placeholder body (new scaffolds only)
if BUILD_PLACEHOLDER_BODY and not (selected and selected:IsA("Model")) then
	local body = Instance.new("Folder")
	body.Name = "PlaceholderBody"
	body.Parent = model

	local wallWidth = 2 * RADIUS * math.tan(math.rad(180 / math.max(faceCount, 4))) + 0.1
	local bodyHeight = WALKWAY_HEIGHT
	for i = 0, faceCount - 1 do
		local dir = faceDir(i)
		local pos = center + dir * (RADIUS - 0.5) + Vector3.new(0, bodyHeight / 2, 0)
		local wall = Instance.new("Part")
		wall.Name = "BodyWall"
		wall.Size = Vector3.new(wallWidth, bodyHeight, 1)
		wall.CFrame = CFrame.lookAt(pos, pos + dir)
		wall.Anchored = true
		wall.Color = Color3.fromRGB(120, 120, 120)
		wall.Material = Enum.Material.Slate
		wall.Parent = body
	end

	local floor = Instance.new("Part")
	floor.Name = "WalkwayFloor"
	floor.Shape = Enum.PartType.Cylinder
	floor.Size = Vector3.new(1, RADIUS * 2, RADIUS * 2)
	floor.CFrame = CFrame.new(center + Vector3.new(0, WALKWAY_HEIGHT - 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	floor.Anchored = true
	floor.Color = Color3.fromRGB(100, 100, 100)
	floor.Material = Enum.Material.Slate
	floor.Parent = body
end

Selection:Set({ model })
print(("[Scaffold] Done: %d ConnectionPoints, %d WalkwayDoors, 1 GroundDoor, attributes set."):format(
	faceCount, faceCount))
print("[Scaffold] Green = wall joins, Blue = upper doors, Gold = ground door. Nudge as needed, then build/replace geometry around them.")
