--!strict
-- WeaponVisuals: Procedural weapon + shield props welded to units at spawn.
-- Pure cosmetics — no gameplay effect. The client (CombatEffectsClient)
-- animates the "WeaponGrip" weld on swing events.
--
-- Works with both real rigs (Right Arm / RightHand) and the fallback dummy
-- (Head/Torso/HumanoidRootPart only) by gripping to the best available part.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)

local WeaponVisuals = {}

local WOOD = Color3.fromRGB(120, 85, 50)
local DARK_WOOD = Color3.fromRGB(90, 62, 35)
local STEEL = Color3.fromRGB(190, 195, 200)
local IRON = Color3.fromRGB(130, 132, 135)
local LEATHER = Color3.fromRGB(110, 75, 45)

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	return part
end

-- Weld `part` to `root` at offset (in root's space)
local function weldTo(root: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = root.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = root
end

-- ═══════════════════════════════════════════════════════════════════════════
-- WEAPON BUILDERS — each returns a Model whose PrimaryPart is the grip point.
-- Local space: +Y is "up" along the weapon when held vertically.
-- ═══════════════════════════════════════════════════════════════════════════

local function buildSword(): Model
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local handle = makePart("Handle", Vector3.new(0.14, 0.55, 0.14), DARK_WOOD, Enum.Material.Wood)
	handle.Parent = model
	model.PrimaryPart = handle

	local guard = makePart("Guard", Vector3.new(0.55, 0.09, 0.14), IRON, Enum.Material.Metal)
	guard.Parent = model
	weldTo(handle, guard, CFrame.new(0, 0.32, 0))

	local blade = makePart("Blade", Vector3.new(0.09, 1.5, 0.26), STEEL, Enum.Material.Metal)
	blade.Parent = model
	weldTo(handle, blade, CFrame.new(0, 1.11, 0))
	return model
end

local function buildAxe(): Model
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local handle = makePart("Handle", Vector3.new(0.15, 1.5, 0.15), WOOD, Enum.Material.Wood)
	handle.Parent = model
	model.PrimaryPart = handle

	local head = makePart("Head", Vector3.new(0.12, 0.5, 0.65), IRON, Enum.Material.Metal)
	head.Parent = model
	weldTo(handle, head, CFrame.new(0, 0.55, -0.32))

	local blade = makePart("Edge", Vector3.new(0.09, 0.55, 0.14), STEEL, Enum.Material.Metal)
	blade.Parent = model
	weldTo(handle, blade, CFrame.new(0, 0.55, -0.66))
	return model
end

local function buildSpear(): Model
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local shaft = makePart("Shaft", Vector3.new(0.12, 2.6, 0.12), WOOD, Enum.Material.Wood)
	shaft.Parent = model
	model.PrimaryPart = shaft

	local tip = makePart("Tip", Vector3.new(0.09, 0.5, 0.2), STEEL, Enum.Material.Metal)
	tip.Parent = model
	weldTo(shaft, tip, CFrame.new(0, 1.5, 0))
	return model
end

local function buildJavelin(): Model
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local shaft = makePart("Shaft", Vector3.new(0.1, 1.9, 0.1), WOOD, Enum.Material.Wood)
	shaft.Parent = model
	model.PrimaryPart = shaft

	local tip = makePart("Tip", Vector3.new(0.08, 0.4, 0.16), IRON, Enum.Material.Metal)
	tip.Parent = model
	weldTo(shaft, tip, CFrame.new(0, 1.1, 0))
	return model
end

local function buildBow(): Model
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local grip = makePart("Grip", Vector3.new(0.13, 0.55, 0.13), LEATHER, Enum.Material.Fabric)
	grip.Parent = model
	model.PrimaryPart = grip

	local upper = makePart("UpperLimb", Vector3.new(0.1, 1.05, 0.1), DARK_WOOD, Enum.Material.Wood)
	upper.Parent = model
	weldTo(grip, upper, CFrame.new(0, 0.7, -0.12) * CFrame.Angles(math.rad(-14), 0, 0))

	local lower = makePart("LowerLimb", Vector3.new(0.1, 1.05, 0.1), DARK_WOOD, Enum.Material.Wood)
	lower.Parent = model
	weldTo(grip, lower, CFrame.new(0, -0.7, -0.12) * CFrame.Angles(math.rad(14), 0, 0))

	local bowString = makePart("String", Vector3.new(0.03, 2.35, 0.03), Color3.fromRGB(225, 220, 200), Enum.Material.Fabric)
	bowString.Parent = model
	weldTo(grip, bowString, CFrame.new(0, 0, 0.16))
	return model
end

local function buildStaff(): Model
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local shaft = makePart("Shaft", Vector3.new(0.15, 2.3, 0.15), DARK_WOOD, Enum.Material.Wood)
	shaft.Parent = model
	model.PrimaryPart = shaft

	local orb = makePart("Orb", Vector3.new(0.38, 0.38, 0.38), Color3.fromRGB(120, 220, 160), Enum.Material.Neon)
	orb.Shape = Enum.PartType.Ball
	orb.Parent = model
	weldTo(shaft, orb, CFrame.new(0, 1.3, 0))
	return model
end

local function buildClub(): Model
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local handle = makePart("Handle", Vector3.new(0.15, 0.9, 0.15), WOOD, Enum.Material.Wood)
	handle.Parent = model
	model.PrimaryPart = handle

	local head = makePart("Head", Vector3.new(0.3, 0.6, 0.3), DARK_WOOD, Enum.Material.Wood)
	head.Parent = model
	weldTo(handle, head, CFrame.new(0, 0.7, 0))
	return model
end

local function buildSling(): Model
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local strap = makePart("Strap", Vector3.new(0.09, 0.8, 0.05), LEATHER, Enum.Material.Fabric)
	strap.Parent = model
	model.PrimaryPart = strap

	local pouch = makePart("Pouch", Vector3.new(0.2, 0.16, 0.12), DARK_WOOD, Enum.Material.Fabric)
	pouch.Parent = model
	weldTo(strap, pouch, CFrame.new(0, -0.45, 0))
	return model
end

local BUILDERS: { [string]: () -> Model } = {
	Sword = buildSword,
	Axe = buildAxe,
	Spear = buildSpear,
	Javelin = buildJavelin,
	Bow = buildBow,
	Staff = buildStaff,
	Club = buildClub,
	Sling = buildSling,
}

local function buildShield(): Model
	local model = Instance.new("Model")
	model.Name = "Shield"
	local face = makePart("Face", Vector3.new(0.15, 1.1, 0.9), WOOD, Enum.Material.WoodPlanks)
	face.Parent = model
	model.PrimaryPart = face

	local boss = makePart("Boss", Vector3.new(0.1, 0.3, 0.3), IRON, Enum.Material.Metal)
	boss.Parent = model
	weldTo(face, boss, CFrame.new(-0.1, 0, 0))
	return model
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ATTACHMENT
-- ═══════════════════════════════════════════════════════════════════════════

-- Best right-hand grip part for whatever rig this unit uses
local function findGripPart(unit: Model, rightSide: boolean): (BasePart?, CFrame)
	local sideName = if rightSide then "Right" else "Left"

	-- R15
	local hand = unit:FindFirstChild(sideName .. "Hand")
	if hand and hand:IsA("BasePart") then
		return hand, CFrame.new(0, -0.1, 0)
	end
	-- R6
	local arm = unit:FindFirstChild(sideName .. " Arm")
	if arm and arm:IsA("BasePart") then
		return arm, CFrame.new(0, -0.9, 0)
	end
	-- Fallback dummy: grip to torso side, held slightly forward
	local torso = unit:FindFirstChild("Torso") or unit:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		local xOffset = if rightSide then 1.7 else -1.7
		return torso :: BasePart, CFrame.new(xOffset, -0.3, -0.3)
	end
	local root = unit.PrimaryPart
	if root then
		local xOffset = if rightSide then 1.3 else -1.3
		return root, CFrame.new(xOffset, -0.3, -0.3)
	end
	return nil, CFrame.new()
end

-- Attach the profile's weapon (and shield) to a freshly spawned unit.
function WeaponVisuals.attach(unit: Model, unitType: string, subtype: string?)
	local profile = CombatConfig.getProfile(unitType, subtype)
	local kind = CombatConfig.getWeaponKind(profile)

	if kind ~= "None" then
		local builder = BUILDERS[kind]
		if builder then
			local gripPart, gripOffset = findGripPart(unit, true)
			if gripPart then
				local weapon = builder()
				local handle = weapon.PrimaryPart :: BasePart

				-- Slight forward tilt so it reads as "held", not "flagpole"
				local heldOffset = gripOffset * CFrame.Angles(math.rad(-15), 0, 0)
				handle.CFrame = gripPart.CFrame * heldOffset

				local weld = Instance.new("Weld")
				weld.Name = "WeaponGrip"
				weld.Part0 = gripPart
				weld.Part1 = handle
				weld.C0 = heldOffset
				weld.Parent = handle

				weapon.Parent = unit
				unit:SetAttribute("WeaponKind", kind)
			end
		end
	end

	if profile.shield == true then
		local gripPart, gripOffset = findGripPart(unit, false)
		if gripPart then
			local shield = buildShield()
			local face = shield.PrimaryPart :: BasePart
			face.CFrame = gripPart.CFrame * gripOffset

			local weld = Instance.new("Weld")
			weld.Name = "ShieldGrip"
			weld.Part0 = gripPart
			weld.Part1 = face
			weld.C0 = gripOffset
			weld.Parent = face

			shield.Parent = unit
		end
	end
end

return WeaponVisuals
