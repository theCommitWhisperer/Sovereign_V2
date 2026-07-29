--!strict
-- UnitManager: Handles unit creation and management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")

-- Units pass through each other (they'd shove one another out of formation
-- slots and clump in melee otherwise) but still collide with the world.
local UNITS_COLLISION_GROUP = "Units"
do
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(UNITS_COLLISION_GROUP)
	end)
	if ok then
		PhysicsService:CollisionGroupSetCollidable(UNITS_COLLISION_GROUP, UNITS_COLLISION_GROUP, false)
	end
end

local function assignUnitCollisionGroup(unit: Model)
	for _, descendant in unit:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = UNITS_COLLISION_GROUP
		end
	end
	-- Parts added later (weapons, effects) join the group too
	unit.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = UNITS_COLLISION_GROUP
		end
	end)
end

local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local UnitManagerDebug = DebugManager.createChannel("UnitManager", false)
local Managers = script.Parent
local CombatManager = require(Managers.CombatManager)
local MoraleManager = require(Managers.MoraleManager)
local FormationManager = require(Managers.FormationManager)
local PlayerManager = require(Managers.PlayerManager)

-- Import new A* pathfinding integration
local PathfindingIntegration = require(script.Parent.Parent.Systems.PathfindingIntegration)
local WeaponVisuals = require(script.Parent.Parent.Combat.WeaponVisuals)

local UnitManager = {}

-- Ensure Units folder exists
local UnitsFolder = Workspace:FindFirstChild("Units")
if not UnitsFolder then
	UnitsFolder = Instance.new("Folder")
	UnitsFolder.Name = "Units"
	UnitsFolder.Parent = Workspace
end

local function loadModelFromAsset(assetId: number): Model?
	local success, model = pcall(function()
		return game:GetService("InsertService"):LoadAsset(assetId)
	end)

	if success and model then
		local actualModel = model:FindFirstChildOfClass("Model")
		if actualModel then
			actualModel.Parent = ServerStorage
			model:Destroy()
			return actualModel
		end
	end

	return nil
end

local function getDummyModel(): Model
	-- Check ServerStorage for an existing Dummy rig (inserted via Studio toolbox)
	local existing = ServerStorage:FindFirstChild("Dummy")
	if existing and existing:IsA("Model") then
		return existing
	end

	UnitManagerDebug:warn("No Dummy found in ServerStorage, creating simple model")
	local model = Instance.new("Model")
	model.Name = "Dummy"

	-- Make HumanoidRootPart (critical for Humanoid:MoveTo to work)
	local humanoidRootPart = Instance.new("Part")
	humanoidRootPart.Name = "HumanoidRootPart"
	humanoidRootPart.Size = Vector3.new(2, 4, 2)
	humanoidRootPart.Transparency = 1 -- Invisible
	humanoidRootPart.CanCollide = true -- MUST collide for pathfinding
	humanoidRootPart.Material = Enum.Material.SmoothPlastic
	humanoidRootPart.Anchored = false -- MUST be unanchored for movement
	humanoidRootPart.Parent = model

	-- Add basic visible parts (Head and Torso)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 2, 2)
	head.Color = Color3.fromRGB(255, 204, 153)
	head.CanCollide = false -- Don't need collision on welded parts
	head.Material = Enum.Material.Plastic
	head.Shape = Enum.PartType.Block
	head.Anchored = false
	head.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(3, 4, 1.5)
	torso.Color = Color3.fromRGB(100, 100, 100)
	torso.CanCollide = false -- Don't need collision on welded parts
	torso.Material = Enum.Material.Plastic
	torso.Anchored = false
	torso.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2.5 -- Standard R15 hip height
	humanoid.WalkSpeed = 16 -- Default walk speed
	humanoid.Parent = model

	model.PrimaryPart = humanoidRootPart

	-- Position parts relative to HumanoidRootPart
	torso.CFrame = humanoidRootPart.CFrame
	head.CFrame = humanoidRootPart.CFrame * CFrame.new(0, 3, 0)

	-- Weld parts to HumanoidRootPart
	local weldTorso = Instance.new("WeldConstraint")
	weldTorso.Part0 = humanoidRootPart
	weldTorso.Part1 = torso
	weldTorso.Parent = humanoidRootPart

	local weldHead = Instance.new("WeldConstraint")
	weldHead.Part0 = torso
	weldHead.Part1 = head
	weldHead.Parent = torso

	model.Parent = ServerStorage
	return model
end

-- Look up a custom model for a unit type so you can supply your own rigs.
-- In ReplicatedStorage/Assets/Units (or ServerStorage/Assets/Units), the unit
-- type name is the key. You can provide:
--   • a single Model named "Peasant"                         → always used
--   • several Models "Peasant", "Peasant_A", "Peasant_2", …  → random variant
--   • a Folder "Peasant" holding any-named Model children     → random variant
-- (i.e. all you need is the name to start with the type; "_suffix" = a variant.)
-- Set `model_name` on the unit in UnitsData to key off a different name.
-- Each model must be a proper rig: a Humanoid + a PrimaryPart (HumanoidRootPart),
-- unanchored and welded, like a Roblox character. Returns a random matching
-- TEMPLATE (the caller clones it), or nil if none exist.
local function getUnitModel(unitType: string, unitInfo: any): Model?
	local modelName = (unitInfo and unitInfo.model_name) or unitType
	local prefix = modelName .. "_"

	local candidates: { Model } = {}

	local function collectFrom(root: Instance?)
		if not root then
			return
		end

		-- A Folder named exactly after the type is a variant pool.
		local exact = root:FindFirstChild(modelName)
		if exact and exact:IsA("Folder") then
			for _, child in exact:GetChildren() do
				if child:IsA("Model") then
					table.insert(candidates, child)
				end
			end
		end

		-- Loose models named "<type>" or "<type>_<variant>".
		for _, child in root:GetChildren() do
			if child:IsA("Model") and (child.Name == modelName or child.Name:sub(1, #prefix) == prefix) then
				table.insert(candidates, child)
			end
		end
	end

	local repAssets = ReplicatedStorage:FindFirstChild("Assets")
	collectFrom(repAssets and repAssets:FindFirstChild("Units"))
	local ssAssets = ServerStorage:FindFirstChild("Assets")
	collectFrom(ssAssets and ssAssets:FindFirstChild("Units"))

	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(1, #candidates)]
end

-- Exposed so other systems resolve rigs the same way units do instead of
-- writing a second copy of this scan (WorkerService swaps a worker's model
-- between its Peasant rig and its trade rig using this same resolver).
UnitManager.getUnitModel = getUnitModel

-- Is a part already held to something by a joint (so it won't fall off)?
local function isJointed(part: BasePart, model: Model): boolean
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("Snap") then
			local joint = d :: any
			if joint.Part0 == part or joint.Part1 == part then
				return true
			end
		end
	end
	return false
end

-- Make sure a cloned model can actually be used as a unit (PrimaryPart + Humanoid)
-- AND that it holds together. createUnit only unanchors the PrimaryPart, so any
-- custom part that isn't welded/jointed to the rig falls off once physics starts
-- (head, arms, legs dropping away). We unanchor everything and weld loose parts
-- to the root so ANY model — welded rig or plain prop — stays intact and moves
-- as one. Parts already driven by a joint (Motor6D animation, existing welds)
-- are left alone.
local function normalizeUnitModel(unit: Model): boolean
	if not unit.PrimaryPart then
		local hrp = unit:FindFirstChild("HumanoidRootPart")
			or unit:FindFirstChildWhichIsA("BasePart", true)
		if hrp and hrp:IsA("BasePart") then
			unit.PrimaryPart = hrp
		end
	end
	if not unit.PrimaryPart then
		UnitManagerDebug:warn(`Custom model for {unit.Name} has no usable PrimaryPart`)
		return false
	end

	if not unit:FindFirstChildOfClass("Humanoid") then
		local h = Instance.new("Humanoid")
		h.Parent = unit
	end

	-- Templates authored in Studio often arrive with a driver script attached
	-- (the "walking demo" script that ships with most model tutorials). Left in
	-- place it runs its own PathfindingService loop on every spawned unit and
	-- fights MovementSystem for control of the Humanoid — the unit twitches
	-- between two destinations and appears to ignore orders. Units are driven
	-- entirely by the server systems, so no unit model may carry its own logic.
	for _, d in unit:GetDescendants() do
		if d:IsA("BaseScript") then
			UnitManagerDebug:warn(
				`Stripped rogue {d.ClassName} "{d.Name}" from unit template {unit.Name} — `
					.. `unit models must not carry their own movement logic`
			)
			d:Destroy()
		end
	end

	local primary = unit.PrimaryPart

	-- A skinned rig is ONE MeshPart deformed by a Bone tree. Its mesh must stay
	-- free to be posed by the animation; welding it to the root pins it rigid,
	-- so the unit slides in its bind pose. Detect it and leave the mesh alone.
	local isSkinned = unit:GetAttribute("SkinnedRig") == true
	if not isSkinned then
		for _, d in unit:GetDescendants() do
			if d:IsA("Bone") then
				isSkinned = true
				break
			end
		end
	end

	for _, part in unit:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			local skinnedMesh = isSkinned and part:IsA("MeshPart") and #part:GetChildren() > 0
			if part ~= primary and not skinnedMesh and not isJointed(part, unit) then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = part
				weld.Parent = primary
			end
		end
	end

	-- The Humanoid needs something solid under it to stand on. A skinned rig's
	-- only collider is its root, and custom rigs are frequently exported with
	-- collision off everywhere — which drops them through the terrain.
	if not primary.CanCollide then
		local anyCollider = false
		for _, part in unit:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide then
				anyCollider = true
				break
			end
		end
		if not anyCollider then
			primary.CanCollide = true
			UnitManagerDebug:info(`Enabled collision on {unit.Name}'s root — rig had no collider`)
		end
	end

	return true
end

-- NEW: Ground finding logic (portable version of UnitSpawnManager's logic)
local function findGroundPosition(initialPoint: Vector3): Vector3
	local rayOrigin = initialPoint + Vector3.new(0, 50, 0)
	local rayDirection = Vector3.new(0, -100, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { UnitsFolder }

	local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if result and result.Position then
		return result.Position
	else
		return Vector3.new(initialPoint.X, 0.5, initialPoint.Z)
	end
end

function UnitManager.createUnit(unitType: string, ownerId: number, position: Vector3?, explicitFaction: string?): Model?
	local unitInfo = GameData.Units[unitType]
	if not unitInfo then
		UnitManagerDebug:warn(`Unknown unit type: {unitType}`)
		return nil
	end

	-- Determine faction (priority: explicit > unitData > player > default)
	local faction = explicitFaction -- Use provided faction first

	if not faction then
		-- Special case: Vikings
		if unitType == "Viking" then
			faction = "Viking"
		elseif unitInfo.faction and unitInfo.faction ~= "Neutral" then
			-- Use faction from unit data if specified ("Neutral" = any faction,
			-- so fall through to the owning player's faction instead)
			faction = unitInfo.faction
		else
			-- Try to get faction from player
			local success, player = pcall(function()
				return game.Players:GetPlayerByUserId(ownerId)
			end)

			if success and player then
				local playerData = PlayerManager.get(player)
				if playerData and playerData.Faction then
					faction = playerData.Faction
				end
			end
		end
	end

	faction = faction or "Kingdom"

	-- Determine player name first
	local playerName = "Unknown"
	if ownerId == 1000000 then
		playerName = "Vikings"
	else
		local success, player = pcall(function()
			return game.Players:GetPlayerByUserId(ownerId)
		end)
		if success and player then
			playerName = player.Name
		else
			playerName = tostring(ownerId)
		end
	end

	-- DEBUG: Always print what faction we're using
	UnitManagerDebug:info(`Creating unit`, {
		unitType = unitType,
		owner = playerName,
		ownerId = ownerId,
		faction = faction,
		explicitFaction = explicitFaction,
	})

	-- Prefer a custom model from Assets/Units (yours); fall back to the Dummy rig.
	local customTemplate = getUnitModel(unitType, unitInfo)
	local template = customTemplate or getDummyModel()
	if not template then
		UnitManagerDebug:warn("Failed to get a unit model")
		return nil
	end

	-- Clone the template
	local unit = template:Clone()

	-- Custom models may lack PrimaryPart / Humanoid — make them usable, and if a
	-- custom model is malformed, fall back to the Dummy so spawning never fails.
	if customTemplate then
		if normalizeUnitModel(unit) then
			UnitManagerDebug:info(`Using custom model for {unitType}`)
		else
			unit:Destroy()
			unit = getDummyModel():Clone()
		end
	end

	-- Generate unique ID
	local uniqueId = tostring(math.random(1000, 9999))
	unit.Name = `{unitType}_{ownerId}_{uniqueId}`

	-- Set health attributes first
	unit:SetAttribute("MaxHealth", unitInfo.max_health or 100)
	unit:SetAttribute("CurrentHealth", unitInfo.max_health or 100)

	-- Set unit attributes BEFORE parenting
	unit:SetAttribute("UnitType", unitType)
	unit:SetAttribute("OwnerId", ownerId)
	unit:SetAttribute("UnitId", unit.Name)

	-- Flying units (can_fly in UnitsData): MovementSystem takes over with direct
	-- anchored flight — no ground pathfinding, no wall collision.
	if (unitInfo :: any).can_fly then
		unit:SetAttribute("CanFly", true)
	end

	-- Set initial position. Snap the model's FEET onto the ground so any rig
	-- spawns on the surface regardless of its pivot / HipHeight / size — the old
	-- code pivoted the model origin to the raw spawn Y, which was tuned for the
	-- Dummy and buried differently-shaped custom models.
	local spawnPos = position or Vector3.new(math.random(-20, 20), 10, math.random(-20, 20))

	if unit.PrimaryPart then
		unit.PrimaryPart.Anchored = true
		local ground = findGroundPosition(spawnPos)
		-- Place well above ground, measure the model's bottom, then drop it so the
		-- lowest point rests just on the surface.
		unit:PivotTo(CFrame.new(ground.X, ground.Y + 50, ground.Z))
		local bbCFrame, bbSize = unit:GetBoundingBox()
		local modelBottom = bbCFrame.Position.Y - bbSize.Y / 2
		local lift = (ground.Y + 0.5) - modelBottom
		unit:PivotTo(unit:GetPivot() + Vector3.new(0, lift, 0))
	end

	-- Update humanoid speed if specified
	if unitInfo.move_speed then
		local humanoid = unit:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = unitInfo.move_speed * 16
			-- Remember the unit's individual speed so group march can cap to the
			-- slowest member and later restore each unit to its own pace
			unit:SetAttribute("BaseWalkSpeed", humanoid.WalkSpeed)
		end
	end

	-- Friendly overhead name (the model name stays the unique id used for lookup).
	do
		local humanoid = unit:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayName = unitInfo.display_name or (unitType:gsub("_", " "))
		end
	end

	-- PARENT TO WORKSPACE FIRST (attributes work better when parented)
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		unitsFolder = Instance.new("Folder")
		unitsFolder.Name = "Units"
		unitsFolder.Parent = workspace
	end
	unit.Parent = unitsFolder

	-- NOW initialize systems that read attributes
	-- DEBUG: Print faction before passing to MoraleManager


	-- Units don't collide with each other (formation slots + melee spacing)
	assignUnitCollisionGroup(unit)

	-- Initialize morale
	MoraleManager.initializeUnit(unit, faction)

	-- Attach visual weapon/shield props (pure cosmetics).
	-- Skipped for rigs that model their own weapon: WeaponVisuals falls back to
	-- welding onto the root when it can't find a hand, and on a skinned rig there
	-- is no hand part — so the prop would hang in mid-air beside the unit,
	-- unanimated, on top of the weapon already in the mesh.
	if not unit:GetAttribute("HasBuiltInWeapon") then
		WeaponVisuals.attach(unit, unitType, unitInfo.subtype)
	end

	-- Create a fake player object for CombatManager if needed
	local playerForCombat = nil
	if ownerId ~= 1000000 then
		local success, player = pcall(function()
			return game.Players:GetPlayerByUserId(ownerId)
		end)
		if success and player then
			playerForCombat = player
		end
	end

	-- Initialize combat for ALL units (including Vikings)
	if playerForCombat then
		CombatManager.initializeCombatUnit(unit, playerForCombat)
	else
		-- For Vikings/AI, we need to initialize combat differently
		-- Create a temporary table that mimics a player
		local fakePlayer = {
			Name = playerName,
			UserId = ownerId,
		}
		-- Call a version that doesn't need PlayerManager
		local unitData = GameData.Units[unitType]

		if unitData then
			local combatUnit = {
				model = unit,
				unitData = unitData,
				owner = ownerId,
				unitType = unitType,
				health = unitData.max_health,
				maxHealth = unitData.max_health,
				attackDamage = unitData.attack_damage,
				attackSpeed = unitData.attack_speed,
				attackRange = unitData.attack_range * 3,
				armor = unitData.armor,
				morale = 75,
				stance = "Attack",
				targetModel = nil,
				formation = nil,
				lastAttackTime = 0,
				isCharging = false,
				faction = faction,
				-- Irish special abilities
				celticFuryActive = false,
				lastWarCryTime = 0,
				inShieldWall = false,
				shieldWallAllies = {},
			}

			-- Manually add to ActiveCombatUnits
			CombatManager.registerCombatUnit(unit, combatUnit)
		end
	end

	-- Add to player's units if we found the player
	if playerForCombat then
		PlayerManager.addUnit(playerForCombat, unit)
		PlayerManager.updatePlayerStats(playerForCombat)
	end

	-- Unanchor the unit after everything is set up so it can move.
	-- Flyers stay ANCHORED: MovementSystem moves them by PivotTo at altitude,
	-- which is what lets them ignore walls and terrain entirely.
	task.defer(function()
		local ok, err = pcall(function()
			if unit and unit.PrimaryPart and unit.Parent then
				if unit:GetAttribute("CanFly") then
					-- Lift off: hover a few studs above the spawn point
					unit:PivotTo(unit:GetPivot() + Vector3.new(0, 10, 0))
					UnitManagerDebug:info(`Flyer {unit.Name} spawned airborne (stays anchored)`)
				else
					unit.PrimaryPart.Anchored = false
					UnitManagerDebug:info(`Unanchored unit {unit.Name} for movement`)
				end
			end
		end)
		if not ok then
			-- Defensive: never let a deferred callback error escape uncaught.
			-- Logged with full context so a recurrence is diagnosable.
			UnitManagerDebug:error(`Deferred unanchor/liftoff failed for {tostring(unit and unit.Name)}: {tostring(err)}`)
			-- Best-effort fallback so the unit isn't left permanently frozen.
			pcall(function()
				if unit and unit.PrimaryPart and unit.Parent and not unit:GetAttribute("CanFly") then
					unit.PrimaryPart.Anchored = false
				end
			end)
		end
	end)

	-- Clean up pathfinding mover when unit is destroyed
	unit.Destroying:Connect(function()
		PathfindingIntegration.unregisterMover(unit)
	end)

	return unit
end

function UnitManager.destroyRandomUnit(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or #playerData.Units == 0 then
		return
	end

	local randomIndex = math.random(1, #playerData.Units)
	local unitToDestroy = playerData.Units[randomIndex]

	if unitToDestroy then
		-- Clean up pathfinding mover for this unit
		PathfindingIntegration.unregisterMover(unitToDestroy)

		PlayerManager.removeUnit(player, unitToDestroy)
		PlayerManager.updatePlayerStats(player)
		unitToDestroy:Destroy()
		UnitManagerDebug:info(`Destroyed random unit for {player.Name} due to desertion.`)
	end
end

return UnitManager
