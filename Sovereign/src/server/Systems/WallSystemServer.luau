--!strict
-- WallSystemServer - Integrated from working test system
-- High tolerance wall building with smart placement and validation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Import WallSystem for grid-based connection management
local WallSystem = require(script.Parent.WallSystem)

-- === SETUP ===
-- NOTE: RemoteEvents will be initialized in initialize() function to avoid circular dependency
local RemoteEvents: Folder? = nil
local placePathEvent: RemoteEvent? = nil
local removeWallPieceEvent: RemoteEvent? = nil
local getEndpointsEvent: RemoteFunction? = nil

-- Create our wall system remote events
local function getOrCreateRemote(name: string, className: string)
	if not RemoteEvents then
		error("[WallSystemServer] RemoteEvents not initialized! Call initialize() first.")
	end
	local remote = RemoteEvents:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = RemoteEvents
	end
	return remote
end

-- Get/create placed walls folder
local placedWallsFolder = Workspace:FindFirstChild("PlacedWalls") or Workspace:FindFirstChild("Buildings")
if not placedWallsFolder then
	placedWallsFolder = Instance.new("Folder")
	placedWallsFolder.Name = "Buildings"
	placedWallsFolder.Parent = Workspace
end

-- === CONFIGURATION ===
local CONFIG = {
	PieceTypes = {
		Tower = "Stone_Wall_Small_Tower",
		Straight = "Stone_Wall_Straight",
		Short = "Stone_Wall_Short_Straight",
		Corner = "Stone_Wall_Small_Tower", -- No corner model, use tower
		Gatehouse = "Stone_Wall_Gatehouse",
		Ladder = "Stone_Wall_Ladder",
	},
	-- Wall dimensions for endpoint calculation
	WallLengthLong = 16,
	WallLengthShort = 10,
	TowerRadius = 12, -- Stone_Wall_Small_Tower is 24 studs (radius = 12)
	GatehouseSpacing = 58,
	-- High Tolerance Constraints
	MaxBuildDistance = 1000,
	MaxSegmentLength = 128, -- Increased to prevent false positives
}

-- === SERVER-SIDE ENDPOINT TRACKING ===
-- Track all wall endpoints for snapping persistence across sessions
local wallEndpoints: { { position: Vector3, incomingDir: Vector3, pieceRef: Model } } = {}

-- === HELPERS ===

local function getWallEndpoints(centerPos: Vector3, rotation: number, length: number): (Vector3, Vector3)
	local cf = CFrame.new(centerPos) * CFrame.Angles(0, rotation, 0)
	local direction = cf.RightVector
	return centerPos - (direction * (length / 2)), centerPos + (direction * (length / 2))
end

local function registerWallEndpoints(piece: Model, position: Vector3, rotation: number, pieceType: string)
	-- Handle linear pieces (walls with two endpoints)
	local len = 0
	if pieceType == "Straight" or pieceType == "Ladder" then
		len = CONFIG.WallLengthLong
	elseif pieceType == "Short" then
		len = CONFIG.WallLengthShort
	elseif pieceType == "Gatehouse" then
		len = CONFIG.GatehouseSpacing
	end

	if len > 0 then
		local p1, p2 = getWallEndpoints(position, rotation, len)
		local dir = (p2 - p1).Unit
		table.insert(wallEndpoints, { position = p1, incomingDir = -dir, pieceRef = piece })
		table.insert(wallEndpoints, { position = p2, incomingDir = dir, pieceRef = piece })
	elseif pieceType == "Tower" then
		-- Towers have 4 connection points (one in each cardinal direction)
		-- Tower radius is 12 studs (24 stud diameter)
		local offset = CONFIG.TowerRadius or 12

		-- North endpoint (negative Z)
		table.insert(wallEndpoints, {
			position = position + Vector3.new(0, 0, -offset),
			incomingDir = Vector3.new(0, 0, 1),  -- Incoming from south
			pieceRef = piece
		})

		-- East endpoint (positive X)
		table.insert(wallEndpoints, {
			position = position + Vector3.new(offset, 0, 0),
			incomingDir = Vector3.new(-1, 0, 0),  -- Incoming from west
			pieceRef = piece
		})

		-- South endpoint (positive Z)
		table.insert(wallEndpoints, {
			position = position + Vector3.new(0, 0, offset),
			incomingDir = Vector3.new(0, 0, -1),  -- Incoming from north
			pieceRef = piece
		})

		-- West endpoint (negative X)
		table.insert(wallEndpoints, {
			position = position + Vector3.new(-offset, 0, 0),
			incomingDir = Vector3.new(1, 0, 0),  -- Incoming from east
			pieceRef = piece
		})
	end
end

local function unregisterWallEndpoints(piece: Model)
	-- Remove all endpoints associated with this piece
	for i = #wallEndpoints, 1, -1 do
		if wallEndpoints[i].pieceRef == piece then
			table.remove(wallEndpoints, i)
		end
	end
end

local function getAllWallEndpoints(): { { position: Vector3, incomingDir: Vector3 } }
	-- Return simplified endpoint data (without piece references) for client sync
	local simplified = {}
	for _, endpoint in ipairs(wallEndpoints) do
		table.insert(simplified, { position = endpoint.position, incomingDir = endpoint.incomingDir })
	end
	return simplified
end

local function anchorModel(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
		end
	end
end

local function getGroundHeight(position: Vector3): number
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { placedWallsFolder }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(position + Vector3.new(0, 100, 0), Vector3.new(0, -200, 0), params)
	return result and result.Position.Y or position.Y
end

-- === VALIDATION ===
type PathPoint = {
	position: Vector3,
	type: string,
	rotation: number?,
}

local function validatePath(player: Player, pathData: { PathPoint }): (boolean, string?)
	if type(pathData) ~= "table" then
		return false, "Invalid Data Format"
	end
	if #pathData == 0 then
		return false, "Empty Path"
	end
	if #pathData > 200 then
		return false, "Path Too Long"
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false, "No Character"
	end

	local lastPos: Vector3? = nil

	for i, point in ipairs(pathData) do
		-- 1. Check Data Types
		if not point.position or typeof(point.position) ~= "Vector3" then
			return false, "Invalid Vector3"
		end
		if not point.type or not CONFIG.PieceTypes[point.type] then
			return false, "Invalid Piece Type"
		end

		-- 2. Check Distance from Player
		if (point.position - root.Position).Magnitude > CONFIG.MaxBuildDistance then
			return false, "Too Far From Player"
		end

		-- 3. Check Distance Between Segments
		if lastPos then
			local dist = (point.position - lastPos).Magnitude
			if dist > CONFIG.MaxSegmentLength then
				return false, string.format("Gap Too Large: %.1f studs", dist)
			end
		end

		lastPos = point.position
	end

	return true
end

local function placeSinglePiece(pieceType: string, position: Vector3, rotation: number?, ownerId: number): Model?
	local modelName = CONFIG.PieceTypes[pieceType]

	-- Get model from Assets
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	if not Assets then
		warn("[WallSystemServer] Assets folder not found")
		return nil
	end
	local Buildings = Assets:FindFirstChild("Buildings")
	if not Buildings then
		warn("[WallSystemServer] Buildings folder not found")
		return nil
	end

	local template = Buildings:FindFirstChild(modelName)
	if not template or not template:IsA("Model") then
		warn("[WallSystemServer] Model not found:", modelName)
		return nil
	end

	local piece = template:Clone() :: Model
	piece.Name = pieceType .. "_" .. tostring(tick())

	-- Mark as placed wall piece
	local tag = Instance.new("BoolValue")
	tag.Name = "PlacedPiece"
	tag.Parent = piece

	-- Set ownership and attributes
	piece:SetAttribute("Owner", ownerId)
	piece:SetAttribute("BuildingType", "Stone_Wall")
	piece:SetAttribute("WallPieceType", modelName)
	-- Don't set ManualPieceType - allow grid system to auto-update based on neighbors
	-- This ensures corners become towers automatically when surrounded

	anchorModel(piece)
	piece.Parent = placedWallsFolder

	-- Find or set primary part
	if not piece.PrimaryPart then
		for _, part in ipairs(piece:GetDescendants()) do
			if part:IsA("BasePart") then
				piece.PrimaryPart = part
				break
			end
		end
	end

	if piece.PrimaryPart then
		local groundY = getGroundHeight(position)
		local cf, size = piece:GetBoundingBox()
		local pivotOffset = piece.PrimaryPart.Position.Y - (cf.Position.Y - size.Y / 2)
		local finalPos = Vector3.new(position.X, groundY + pivotOffset, position.Z)

		piece:SetPrimaryPartCFrame(CFrame.new(finalPos) * CFrame.Angles(0, rotation or 0, 0))
	else
		piece:Destroy()
		return nil
	end

	return piece
end

-- === EVENTS ===
-- Event connections are set up in initialize() to avoid circular dependency

local WallSystemServer = {}

function WallSystemServer.initialize()
	-- Initialize RemoteEvents (must be called AFTER GameManager creates RemoteEvents folder)
	RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	placePathEvent = getOrCreateRemote("PlaceWallPath", "RemoteEvent") :: RemoteEvent
	removeWallPieceEvent = getOrCreateRemote("RemoveWallPiece", "RemoteEvent") :: RemoteEvent
	getEndpointsEvent = getOrCreateRemote("GetWallEndpoints", "RemoteFunction") :: RemoteFunction

	-- Set up endpoint sync for clients
	getEndpointsEvent.OnServerInvoke = function(player: Player)
		return getAllWallEndpoints()
	end

	-- Set up event connections
	placePathEvent.OnServerEvent:Connect(function(player: Player, pathData: any)
		local isValid, err = validatePath(player, pathData)

		if isValid then
			-- Place all pieces in the path
			for _, point in ipairs(pathData) do
				local piece = placeSinglePiece(point.type, point.position, point.rotation, player.UserId)
				-- Register endpoints for snapping (but NOT with grid system - it breaks placement)
				if piece then
					registerWallEndpoints(piece, point.position, point.rotation or 0, point.type)
				end
			end
			print(string.format("[WallSystemServer] Placed %d wall pieces for %s", #pathData, player.Name))
		else
			warn(string.format("[WallSystemServer] Blocked Build (%s): %s", player.Name, err))
		end
	end)

	removeWallPieceEvent.OnServerEvent:Connect(function(player: Player, model: Instance)
		if not model or not model.Parent or not model:IsA("Model") then
			return
		end

		-- Check if it's a placed piece and belongs to player
		if model:FindFirstChild("PlacedPiece") and model:GetAttribute("Owner") == player.UserId then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

			if root and model.PrimaryPart then
				if (model.PrimaryPart.Position - root.Position).Magnitude < CONFIG.MaxBuildDistance then
					-- Unregister endpoints before destroying
					unregisterWallEndpoints(model)
					model:Destroy()
					print(string.format("[WallSystemServer] Removed wall piece for %s", player.Name))
				end
			end
		end
	end)

	-- Initialize existing walls on server start
	print("[WallSystemServer] Scanning for existing walls...")
	local BuildingsFolder = Workspace:FindFirstChild("Buildings")
	if BuildingsFolder then
		for _, child in BuildingsFolder:GetChildren() do
			local bType = child:GetAttribute("BuildingType")
			local wallPieceType = child:GetAttribute("WallPieceType")
			if bType and (bType == "Stone_Wall" or string.find(tostring(bType), "Wall")) and child:IsA("Model") then
				-- Determine piece type from model name or attributes
				local pieceType = "Straight" -- Default
				if wallPieceType then
					if string.find(wallPieceType, "Tower") then
						pieceType = "Tower"
					elseif string.find(wallPieceType, "Gatehouse") then
						pieceType = "Gatehouse"
					elseif string.find(wallPieceType, "Short") then
						pieceType = "Short"
					elseif string.find(wallPieceType, "Ladder") then
						pieceType = "Ladder"
					end
				end

				-- Register endpoints from existing walls
				if child.PrimaryPart then
					local pos = child.PrimaryPart.Position
					local _, _, _, _, _, _, m11, m12, m13 = child.PrimaryPart.CFrame:GetComponents()
					local rotation = math.atan2(-m13, m11)
					registerWallEndpoints(child, pos, rotation, pieceType)
				end
			end
		end
		print(string.format("[WallSystemServer] Registered %d wall endpoints from existing walls", #wallEndpoints))
	end

	print("[WallSystemServer] Wall System Ready (MaxSegmentLength: 128)")
	print("[WallSystemServer] Initialized with RemoteEvents")
end

return WallSystemServer
