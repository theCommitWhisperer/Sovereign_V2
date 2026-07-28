--!strict
-- SiegeTowerSystem: "Wall Ferry" behaviour for the Siege_Tower unit.
--
-- FIRST-PASS DESIGN (pragmatic; the wall/pathfinding systems have no concept of
-- climbing or garrisons yet):
--   * A Siege Tower parked ADJACENT to a wall piece (any wall it doesn't own,
--     within DOCK_RANGE) becomes a ferry point.
--   * Every FERRY_INTERVAL seconds, friendly FOOT soldiers standing near the
--     tower (FERRY_RADIUS) are lifted over: they're pivoted to the far side of
--     the wall (opposite the tower), ground-snapped, and given a short
--     per-unit cooldown so they aren't ping-ponged back.
--   * Cavalry, siege engines and workers do NOT ferry — infantry only.
--
-- Honest limitations / TODOs:
--   * Units teleport rather than visibly climb (no climb animation, no ladder
--     traversal in the pathfinding grid).
--   * The drop position is a fixed clearance past the wall; if an enemy
--     building occupies that exact spot the ground raycast still lands units
--     on top of it, which reads as "jumping down off the wall" — acceptable.
--   * Walls are identified by their BuildingType/WallPieceType attributes
--     (see WallSystemServer.placeWallPiece) plus a name fallback.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local SiegeTowerDebug = DebugManager.createChannel("SiegeTower", false)

local SiegeTowerSystem = {}

local CONFIG = {
	FERRY_INTERVAL = 2, -- seconds between ferry scans
	DOCK_RANGE = 12, -- studs: tower-to-wall distance that counts as "docked"
	FERRY_RADIUS = 14, -- studs: friendly infantry this close to the tower get ferried
	DROP_CLEARANCE = 7, -- studs past the wall's far face where units land
	FERRY_COOLDOWN = 6, -- seconds before the same unit can be ferried again
}

-- Subtypes that may ride the tower over a wall (foot troops only)
local FERRYABLE_SUBTYPES: { [string]: boolean } = {
	["Infantry"] = true,
	["Light Infantry"] = true,
	["Medium Infantry"] = true,
	["Heavy Infantry"] = true,
	["Elite Infantry"] = true,
	["Ranged"] = true,
	["Ranged Infantry"] = true,
}

local function isWallPiece(building: Instance): boolean
	local buildingType = building:GetAttribute("BuildingType")
	if typeof(buildingType) == "string" and string.find(buildingType, "Wall", 1, true) then
		-- Gates are meant to be broken, not ferried over — still allow: a tower
		-- against a gate is fine flavor-wise.
		return true
	end
	-- Fallback for wall pieces placed before attributes existed
	return string.find(building.Name, "Wall", 1, true) ~= nil
end

local function getPivotPosition(instance: Instance): Vector3?
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("BasePart") then
		return instance.Position
	end
	return nil
end

-- Nearest wall piece within DOCK_RANGE of the tower, or nil
local function findAdjacentWall(towerPos: Vector3): (Instance?, Vector3?)
	local buildingsFolder = Workspace:FindFirstChild("Buildings")
	if not buildingsFolder then
		return nil, nil
	end

	local bestWall: Instance? = nil
	local bestPos: Vector3? = nil
	local bestDist = CONFIG.DOCK_RANGE

	for _, child in buildingsFolder:GetChildren() do
		if not isWallPiece(child) then
			continue
		end
		local pos = getPivotPosition(child)
		if not pos then
			continue
		end
		local delta = towerPos - pos
		local dist = Vector3.new(delta.X, 0, delta.Z).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestWall = child
			bestPos = pos
		end
	end

	return bestWall, bestPos
end

local function groundSnap(position: Vector3, unitsFolder: Instance): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { unitsFolder }
	local result = Workspace:Raycast(position + Vector3.new(0, 50, 0), Vector3.new(0, -120, 0), params)
	if result then
		return result.Position + Vector3.new(0, 3, 0)
	end
	return position + Vector3.new(0, 3, 0)
end

local function ferryUnitsOverWall(tower: Model, towerPos: Vector3, wallPos: Vector3, unitsFolder: Instance)
	local ownerId = tower:GetAttribute("OwnerId")
	if typeof(ownerId) ~= "number" then
		return
	end

	-- Direction "over the wall": from the tower through the wall piece
	local acrossFlat = Vector3.new(wallPos.X - towerPos.X, 0, wallPos.Z - towerPos.Z)
	if acrossFlat.Magnitude < 0.5 then
		return -- tower is on top of the wall somehow; no sane drop direction
	end
	local across = acrossFlat.Unit

	local now = tick()
	local ferried = 0

	for _, unit in unitsFolder:GetChildren() do
		if not unit:IsA("Model") or unit == tower or not unit.PrimaryPart then
			continue
		end
		if unit:GetAttribute("OwnerId") ~= ownerId then
			continue
		end
		local unitType = unit:GetAttribute("UnitType")
		local unitData = typeof(unitType) == "string" and GameData.Units[unitType] or nil
		if not unitData or not FERRYABLE_SUBTYPES[unitData.subtype] then
			continue
		end
		-- Per-unit cooldown so units don't bounce back and forth
		local lastFerry = unit:GetAttribute("WallFerryAt")
		if typeof(lastFerry) == "number" and now - lastFerry < CONFIG.FERRY_COOLDOWN then
			continue
		end

		local delta = unit.PrimaryPart.Position - towerPos
		if Vector3.new(delta.X, 0, delta.Z).Magnitude > CONFIG.FERRY_RADIUS then
			continue
		end

		-- Land past the wall's far face, fanned out slightly so a squad doesn't
		-- stack on one point
		local fan = Vector3.new(-across.Z, 0, across.X) * math.random(-4, 4)
		local dropPos = groundSnap(wallPos + across * CONFIG.DROP_CLEARANCE + fan, unitsFolder)

		unit:SetAttribute("WallFerryAt", now)
		-- Clear any in-flight move order; the player re-orders from the far side
		unit:SetAttribute("IsMoving", false)
		unit:SetAttribute("TargetPosition", nil)
		unit:PivotTo(CFrame.lookAt(dropPos, dropPos + across))
		ferried += 1
	end

	if ferried > 0 then
		SiegeTowerDebug:info(`Siege Tower {tower.Name} ferried {ferried} unit(s) over a wall`)
	end
end

local loopStarted = false

function SiegeTowerSystem.startLoop()
	if loopStarted then
		return
	end
	loopStarted = true

	task.spawn(function()
		while true do
			task.wait(CONFIG.FERRY_INTERVAL)

			local unitsFolder = Workspace:FindFirstChild("Units")
			if not unitsFolder then
				continue
			end

			for _, unit in unitsFolder:GetChildren() do
				if not unit:IsA("Model") or unit:GetAttribute("UnitType") ~= "Siege_Tower" then
					continue
				end
				if not unit.PrimaryPart then
					continue
				end
				-- Docked towers ferry; moving towers don't (must be parked)
				if unit:GetAttribute("IsMoving") then
					continue
				end

				local towerPos = unit.PrimaryPart.Position
				local wall, wallPos = findAdjacentWall(towerPos)
				if wall and wallPos then
					local ok, err = pcall(ferryUnitsOverWall, unit, towerPos, wallPos, unitsFolder)
					if not ok then
						SiegeTowerDebug:warn(`Wall ferry failed: {err}`)
					end
				end
			end
		end
	end)

	SiegeTowerDebug:info("SiegeTowerSystem loop started")
end

return SiegeTowerSystem
