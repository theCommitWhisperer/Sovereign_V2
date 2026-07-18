--[[
	ValidateWallModel — paste into the Roblox Studio COMMAND BAR and run
	with a wall/tower model SELECTED.

	Checks the model against WALL_MODEL_AUTHORING_SPEC.md and prints a
	pass/fail report: Root/PrimaryPart, ConnectionPoint placement +
	outward orientation, WalkwayDoor height, GroundDoor, attributes.
]]

local EXPECTED_WALKWAY_HEIGHT = 30
local TOLERANCE = 0.25 -- studs

local Selection = game:GetService("Selection")
local model = Selection:Get()[1]

if not model or not model:IsA("Model") then
	error("[Validate] Select a wall/tower model first.")
end

local pass, fail = 0, 0
local function check(ok: boolean, label: string, detail: string?)
	if ok then
		pass += 1
		print(("  [PASS] %s"):format(label))
	else
		fail += 1
		warn(("  [FAIL] %s%s"):format(label, detail and (" — " .. detail) or ""))
	end
end

print(("[Validate] === %s ==="):format(model.Name))

-- Ground center reference
local bcf, bsize = model:GetBoundingBox()
local center = Vector3.new(bcf.Position.X, bcf.Position.Y - bsize.Y / 2, bcf.Position.Z)

-- 1. Root / PrimaryPart
local root = model:FindFirstChild("Root")
check(root ~= nil and root:IsA("BasePart"), "Root part exists")
check(model.PrimaryPart ~= nil, "PrimaryPart is set")
if root and root:IsA("BasePart") then
	local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	check(flat.Magnitude <= TOLERANCE * 4, "Root centered on tower axis",
		("off by %.2f studs"):format(flat.Magnitude))
end

-- 2. ConnectionPoints
local cpFolder = model:FindFirstChild("ConnectionPoints")
check(cpFolder ~= nil, "ConnectionPoints folder exists")

local cps: { BasePart } = {}
if cpFolder then
	for _, child in cpFolder:GetChildren() do
		if child:IsA("BasePart") and child.Name == "ConnectionPoint" then
			table.insert(cps, child)
		end
	end
end
check(#cps >= 2, "At least 2 ConnectionPoints", ("found %d"):format(#cps))

local radii: { number } = {}
for _, cp in cps do
	local offset = Vector3.new(cp.Position.X - center.X, 0, cp.Position.Z - center.Z)
	table.insert(radii, offset.Magnitude)
	-- outward orientation
	if offset.Magnitude > 0.01 then
		local outward = offset.Unit
		local look = Vector3.new(cp.CFrame.LookVector.X, 0, cp.CFrame.LookVector.Z)
		local ok = look.Magnitude > 0.01 and outward:Dot(look.Unit) > 0.99
		check(ok, ("CP face %s LookVector points outward"):format(tostring(cp:GetAttribute("FaceIndex") or "?")),
			ok and nil or "rotate the part so its front faces away from the tower")
	end
end

-- equal radius
if #radii >= 2 then
	local minR, maxR = math.min(unpack(radii)), math.max(unpack(radii))
	check(maxR - minR <= TOLERANCE, "All CPs equidistant from center",
		("radius varies %.2f..%.2f"):format(minR, maxR))
end

-- CPs at ground level
for _, cp in cps do
	local h = cp.Position.Y - center.Y
	if math.abs(h - 0.5) > TOLERANCE * 4 then
		check(false, "CP at ground level", ("CP sits %.2f studs above ground"):format(h))
		break
	end
end

-- 3. WalkwayDoors
local wdFolder = model:FindFirstChild("WalkwayDoors")
check(wdFolder ~= nil, "WalkwayDoors folder exists")
if wdFolder then
	local count = 0
	for _, wd in wdFolder:GetChildren() do
		if wd:IsA("BasePart") and wd.Name == "WalkwayDoor" then
			count += 1
			local h = wd.Position.Y - center.Y - 0.5
			check(math.abs(h - EXPECTED_WALKWAY_HEIGHT) <= TOLERANCE,
				("WalkwayDoor face %s at walkway height"):format(tostring(wd:GetAttribute("FaceIndex") or "?")),
				("floor at %.2f, expected %d"):format(h, EXPECTED_WALKWAY_HEIGHT))
		end
	end
	check(count == #cps, "One WalkwayDoor per ConnectionPoint",
		("%d doors vs %d CPs"):format(count, #cps))
end

-- 4. GroundDoor
check(model:FindFirstChild("GroundDoor") ~= nil, "GroundDoor marker exists")

-- 5. Attributes
for _, attr in { "TowerRadius", "WalkwayHeight", "ConnectionCount" } do
	check(model:GetAttribute(attr) ~= nil, ("Attribute '%s' set"):format(attr))
end

print(("[Validate] === %d passed, %d failed ==="):format(pass, fail))
if fail == 0 then
	print("[Validate] Model meets the spec — ready for marker-based placement code.")
end
