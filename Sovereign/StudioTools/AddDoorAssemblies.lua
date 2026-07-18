--[[
	AddDoorAssemblies — paste into the Roblox Studio COMMAND BAR and run
	with the tower model SELECTED (after FixWallModel has passed validation).

	Reads the existing WalkwayDoor markers + GroundDoor marker and builds a
	functional door assembly at each one, in a "Doors" folder:

	Doors/
	  Door (Model)              -- one per marker
	    attrs: FaceIndex, Level ("Walkway"|"Ground"), DoorState ("Locked")
	    tag:   "TowerDoor"      -- CollectionService, for the runtime system
	    DoorPanel (Part)        -- visible wooden panel, swings on the hinge
	      HingeAttachment       -- on the frame-side edge, rotate around this to open
	    DoorBlocker (Part)      -- invisible collider; CanCollide = locked.
	                               THIS is what stops units/pathfinding, not the panel.

	Runtime contract (for the placement/door system):
	  - open  = Blocker.CanCollide false, panel rotated 110° around hinge (or hidden)
	  - locked = Blocker.CanCollide true, panel closed
	  - wall placement code: open doors on faces with walls attached,
	    leave the rest locked. GroundDoor starts open (it's the tower entrance).

	Existing markers are kept (they stay the alignment source of truth).
	Re-running replaces the Doors folder.
]]

local DOOR_HEIGHT = 8
local PANEL_THICKNESS = 0.4

local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")

local model = Selection:Get()[1]
if not model or not model:IsA("Model") then
	error("[Doors] Select the tower model first.")
end

-- Fresh Doors folder
local old = model:FindFirstChild("Doors")
if old then
	old:Destroy()
end
local doorsFolder = Instance.new("Folder")
doorsFolder.Name = "Doors"
doorsFolder.Parent = model

local built = 0

local function buildDoor(marker: BasePart, level: string)
	local faceIndex = marker:GetAttribute("FaceIndex")
	local width = marker.Size.X
	local outward = marker.CFrame.LookVector
	local right = marker.CFrame.RightVector

	-- Floor of the opening = bottom of the threshold marker
	local floorY = marker.Position.Y - marker.Size.Y / 2
	local basePos = Vector3.new(marker.Position.X, floorY, marker.Position.Z)

	local door = Instance.new("Model")
	door.Name = "Door"
	door:SetAttribute("FaceIndex", faceIndex)
	door:SetAttribute("Level", level)
	door:SetAttribute("DoorState", "Locked")
	CollectionService:AddTag(door, "TowerDoor")

	-- Visible panel, centered in the opening
	local panel = Instance.new("Part")
	panel.Name = "DoorPanel"
	panel.Size = Vector3.new(width, DOOR_HEIGHT, PANEL_THICKNESS)
	panel.CFrame = CFrame.lookAt(
		basePos + Vector3.new(0, DOOR_HEIGHT / 2, 0),
		basePos + Vector3.new(0, DOOR_HEIGHT / 2, 0) + outward
	)
	panel.Anchored = true
	panel.CanCollide = false -- collision is the blocker's job
	panel.Color = Color3.fromRGB(92, 62, 32) -- dark oak
	panel.Material = Enum.Material.WoodPlanks
	panel.Parent = door

	-- Hinge on the frame-side edge (left edge as seen from outside)
	local hinge = Instance.new("Attachment")
	hinge.Name = "HingeAttachment"
	hinge.Position = Vector3.new(-width / 2, 0, 0) -- local left edge of the panel
	hinge.Parent = panel

	-- Invisible blocker: the functional part of the door
	local blocker = Instance.new("Part")
	blocker.Name = "DoorBlocker"
	blocker.Size = Vector3.new(width, DOOR_HEIGHT, 1)
	blocker.CFrame = panel.CFrame
	blocker.Anchored = true
	blocker.CanCollide = true -- Locked by default
	blocker.Transparency = 1
	blocker.CanQuery = false
	blocker.CastShadow = false
	blocker.Parent = door

	door.PrimaryPart = panel
	door.Parent = doorsFolder
	built += 1

	-- keep the right vector referenced so the hinge side is unambiguous in review
	local _ = right
end

-- Walkway doors: one per marker
local wdFolder = model:FindFirstChild("WalkwayDoors")
if wdFolder then
	for _, marker in wdFolder:GetChildren() do
		if marker:IsA("BasePart") and marker.Name == "WalkwayDoor" then
			buildDoor(marker, "Walkway")
		end
	end
else
	warn("[Doors] No WalkwayDoors folder found — run GenerateTowerScaffold/FixWallModel first.")
end

-- Ground door
local gd = model:FindFirstChild("GroundDoor")
if gd and gd:IsA("BasePart") then
	buildDoor(gd, "Ground")
else
	warn("[Doors] No GroundDoor marker found — skipped.")
end

Selection:Set({ doorsFolder })
print(("[Doors] Built %d door assemblies (all DoorState=Locked, tagged 'TowerDoor')."):format(built))
print("[Doors] Panels are visual only; DoorBlocker.CanCollide is the lock. Restyle panels freely — just keep names, hinge, and attributes.")
