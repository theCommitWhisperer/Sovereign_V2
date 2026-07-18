--[[
	FixWallModel — paste into the Roblox Studio COMMAND BAR and run
	with the wall/tower model SELECTED.

	Auto-repairs everything mechanical from a ValidateWallModel report:
	- recenters Root on the tower axis (ground level)
	- re-orients every ConnectionPoint's LookVector to point outward (position kept)
	- creates a WalkwayDoor above any ConnectionPoint that lacks one
	- renumbers FaceIndex on CPs/doors sequentially by angle
	- sets TowerRadius / WalkwayHeight / ConnectionCount attributes
	  (TowerRadius measured from the CPs themselves)

	Geometry (meshes/parts) is never touched. Re-run ValidateWallModel after.
]]

local WALKWAY_HEIGHT = 30
local DOOR_WIDTH = 6

local Selection = game:GetService("Selection")
local model = Selection:Get()[1]
if not model or not model:IsA("Model") then
	error("[Fix] Select the wall/tower model first.")
end

print(("[Fix] === %s ==="):format(model.Name))

-- Ground center reference
local bcf, bsize = model:GetBoundingBox()
local center = Vector3.new(bcf.Position.X, bcf.Position.Y - bsize.Y / 2, bcf.Position.Z)

-- 1. Recenter Root
local root = model:FindFirstChild("Root")
if root and root:IsA("BasePart") then
	root.CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0))
	model.PrimaryPart = root
	model.WorldPivot = CFrame.new(center)
	print("[Fix] Root recentered on tower axis")
end

-- 2. Collect CPs, re-orient outward, sort by angle
local cpFolder = model:FindFirstChild("ConnectionPoints")
if not cpFolder then
	error("[Fix] No ConnectionPoints folder — run GenerateTowerScaffold first.")
end

local cps: { BasePart } = {}
for _, child in cpFolder:GetChildren() do
	if child:IsA("BasePart") and child.Name == "ConnectionPoint" then
		table.insert(cps, child)
	end
end

local radiusSum = 0
for _, cp in cps do
	local offset = Vector3.new(cp.Position.X - center.X, 0, cp.Position.Z - center.Z)
	if offset.Magnitude > 0.01 then
		local outward = offset.Unit
		cp.CFrame = CFrame.lookAt(cp.Position, cp.Position + outward)
		radiusSum += offset.Magnitude
	end
end
print(("[Fix] %d ConnectionPoints re-oriented outward"):format(#cps))

-- sort by angle for stable FaceIndex numbering
table.sort(cps, function(a, b)
	local oa = a.Position - center
	local ob = b.Position - center
	return math.atan2(oa.X, oa.Z) < math.atan2(ob.X, ob.Z)
end)
for i, cp in cps do
	cp:SetAttribute("FaceIndex", i - 1)
end

-- 3. Ensure one WalkwayDoor per CP (matched by direction)
local wdFolder = model:FindFirstChild("WalkwayDoors")
if not wdFolder then
	wdFolder = Instance.new("Folder")
	wdFolder.Name = "WalkwayDoors"
	wdFolder.Parent = model
end

local doors: { BasePart } = {}
for _, child in wdFolder:GetChildren() do
	if child:IsA("BasePart") and child.Name == "WalkwayDoor" then
		table.insert(doors, child)
	end
end

local created = 0
for i, cp in cps do
	local cpDir = Vector3.new(cp.Position.X - center.X, 0, cp.Position.Z - center.Z).Unit

	-- find an existing door on (roughly) the same bearing
	local match: BasePart? = nil
	for _, door in doors do
		local dDir = Vector3.new(door.Position.X - center.X, 0, door.Position.Z - center.Z)
		if dDir.Magnitude > 0.01 and cpDir:Dot(dDir.Unit) > 0.9 then
			match = door
			break
		end
	end

	if match then
		-- normalize its height and orientation, tag the face
		local pos = Vector3.new(match.Position.X, center.Y + WALKWAY_HEIGHT + 0.5, match.Position.Z)
		match.CFrame = CFrame.lookAt(pos, pos + cpDir)
		match:SetAttribute("FaceIndex", i - 1)
	else
		-- create one directly above the CP at walkway height
		local pos = Vector3.new(cp.Position.X, center.Y + WALKWAY_HEIGHT + 0.5, cp.Position.Z)
		local wd = Instance.new("Part")
		wd.Name = "WalkwayDoor"
		wd.Size = Vector3.new(DOOR_WIDTH, 1, 1)
		wd.CFrame = CFrame.lookAt(pos, pos + cpDir)
		wd.Anchored = true
		wd.CanCollide = false
		wd.CanQuery = false
		wd.CastShadow = false
		wd.Transparency = 0.4
		wd.Color = Color3.fromRGB(0, 128, 255)
		wd.Material = Enum.Material.Neon
		wd:SetAttribute("FaceIndex", i - 1)
		wd.Parent = wdFolder
		created += 1
	end
end
print(("[Fix] WalkwayDoors: %d matched/normalized, %d created"):format(#cps - created, created))

-- 4. Attributes (radius measured from the CPs)
local radius = #cps > 0 and (radiusSum / #cps) or 12
model:SetAttribute("TowerRadius", math.round(radius * 100) / 100)
model:SetAttribute("WalkwayHeight", WALKWAY_HEIGHT)
model:SetAttribute("ConnectionCount", #cps)
print(("[Fix] Attributes set: TowerRadius=%.2f, WalkwayHeight=%d, ConnectionCount=%d"):format(
	radius, WALKWAY_HEIGHT, #cps))

print("[Fix] Done — re-run ValidateWallModel to confirm.")
