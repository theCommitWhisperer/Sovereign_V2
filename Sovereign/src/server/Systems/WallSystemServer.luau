--!strict
-- WallSystemServer - Integrated from working test system
-- High tolerance wall building with smart placement and validation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- === SETUP ===
-- NOTE: RemoteEvents will be initialized in initialize() function to avoid circular dependency
local RemoteEvents: Folder? = nil
local placePathEvent: RemoteEvent? = nil
local removeWallPieceEvent: RemoteEvent? = nil

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
	-- High Tolerance Constraints
	MaxBuildDistance = 1000,
	MaxSegmentLength = 128, -- Increased to prevent false positives
}

-- === HELPERS ===

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

	-- Set up event connections
	placePathEvent.OnServerEvent:Connect(function(player: Player, pathData: any)
		local isValid, err = validatePath(player, pathData)

		if isValid then
			-- Place all pieces in the path
			for _, point in ipairs(pathData) do
				placeSinglePiece(point.type, point.position, point.rotation, player.UserId)
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
					model:Destroy()
					print(string.format("[WallSystemServer] Removed wall piece for %s", player.Name))
				end
			end
		end
	end)

	print("[WallSystemServer] Wall System Ready (MaxSegmentLength: 128)")
	print("[WallSystemServer] Initialized with RemoteEvents")
end

return WallSystemServer
