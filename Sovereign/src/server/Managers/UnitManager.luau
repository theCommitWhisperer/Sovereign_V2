--!strict
-- UnitManager: Handles unit creation and management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local UnitManagerDebug = DebugManager.createChannel("UnitManager", true)
local Managers = script.Parent
local CombatManager = require(Managers.CombatManager)
local MoraleManager = require(Managers.MoraleManager)
local FormationManager = require(Managers.FormationManager)
local PlayerManager = require(Managers.PlayerManager)

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
	-- ... (up to UnitManagerDebug:warn)

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
		elseif unitInfo.faction then
			-- Use faction from unit data if specified
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

	-- Get dummy model
	local dummyModel = getDummyModel()
	if not dummyModel then
		UnitManagerDebug:warn("Failed to get dummy model")
		return nil
	end

	-- Clone the dummy
	local unit = dummyModel:Clone()

	-- Generate unique ID
	local uniqueId = tostring(math.random(1000, 9999))
	unit.Name = `{unitType}_{ownerId}_{uniqueId}`

	-- Set health attributes first
	if unitInfo.health then
		unit:SetAttribute("MaxHealth", unitInfo.health.max_health or 100)
		unit:SetAttribute("CurrentHealth", unitInfo.health.max_health or 100)
	else
		unit:SetAttribute("MaxHealth", 100)
		unit:SetAttribute("CurrentHealth", 100)
	end

	-- Set unit attributes BEFORE parenting
	unit:SetAttribute("UnitType", unitType)
	unit:SetAttribute("Owner", ownerId)
	unit:SetAttribute("UnitId", unit.Name)

	-- Set initial position (use PivotTo for unanchored models)
	local spawnPos = position or Vector3.new(math.random(-20, 20), 10, math.random(-20, 20))

	-- Temporarily anchor to position, then unanchor for physics
	if unit.PrimaryPart then
		unit.PrimaryPart.Anchored = true
		unit:PivotTo(CFrame.new(spawnPos))
	end

	-- Update humanoid speed if specified
	if unitInfo.movement then
		local humanoid = unit:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = unitInfo.movement.speed_meters_per_second * 16
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
	print(`[UnitManager DEBUG] About to init morale. Faction = {faction}, Type = {type(faction)}`)

	-- Initialize morale
	MoraleManager.initializeUnit(unit, faction)

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

		if unitData.combat then
			local combatUnit = {
				model = unit,
				unitData = unitData,
				owner = ownerId,
				unitType = unitType,
				health = unitData.health.max_health,
				maxHealth = unitData.health.max_health,
				attackDamage = unitData.combat.attack_damage,
				attackSpeed = unitData.combat.attack_speed,
				attackRange = unitData.combat.attack_range * 3,
				armor = unitData.combat.armor,
				morale = 75,
				stance = "Aggressive",
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

	-- Unanchor the unit after everything is set up so it can move
	task.defer(function()
		if unit and unit.PrimaryPart and unit.Parent then
			unit.PrimaryPart.Anchored = false
			UnitManagerDebug:info(`Unanchored unit {unit.Name} for movement`)
		end
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
		PlayerManager.removeUnit(player, unitToDestroy)
		PlayerManager.updatePlayerStats(player)
		unitToDestroy:Destroy()
		UnitManagerDebug:info(`Destroyed random unit for {player.Name} due to desertion.`)
	end
end

return UnitManager
