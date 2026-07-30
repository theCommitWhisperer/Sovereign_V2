--[[
	Rally Point Visualizer
	Shows visual indicators for rally points on training buildings
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local rallyPoints = {} -- buildingId -> {position, part, beam}

-- Create rally point marker
local function createRallyPoint(building, position)
	-- Create flag marker at rally point
	local marker = Instance.new("Part")
	marker.Name = "RallyPoint"
	marker.Size = Vector3.new(0.5, 3, 0.5)
	marker.Position = position + Vector3.new(0, 1.5, 0)
	marker.Anchored = true
	marker.CanCollide = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(100, 200, 255)
	marker.Transparency = 0.3
	marker.Parent = workspace

	-- Add flag mesh
	local flagMesh = Instance.new("SpecialMesh")
	flagMesh.MeshType = Enum.MeshType.Sphere
	flagMesh.Scale = Vector3.new(1.5, 0.3, 1.5)
	flagMesh.Offset = Vector3.new(0, 1.2, 0)
	flagMesh.Parent = marker

	-- Create beam from building to rally point
	local buildingPos = building.PrimaryPart and building.PrimaryPart.Position
	if buildingPos then
		local attachment0 = Instance.new("Attachment")
		attachment0.Position = Vector3.new(0, 2, 0)
		attachment0.Parent = building.PrimaryPart

		local attachment1 = Instance.new("Attachment")
		attachment1.Parent = marker

		local beam = Instance.new("Beam")
		beam.Attachment0 = attachment0
		beam.Attachment1 = attachment1
		beam.Color = ColorSequence.new(Color3.fromRGB(100, 200, 255))
		beam.Width0 = 0.3
		beam.Width1 = 0.3
		beam.Transparency = NumberSequence.new(0.5)
		beam.FaceCamera = true
		beam.Parent = building.PrimaryPart

		return {
			marker = marker,
			beam = beam,
			attachment0 = attachment0,
			attachment1 = attachment1,
		}
	end

	return { marker = marker }
end

-- Remove rally point marker
local function removeRallyPoint(buildingId)
	local rallyPoint = rallyPoints[buildingId]
	if rallyPoint then
		if rallyPoint.marker then
			rallyPoint.marker:Destroy()
		end
		if rallyPoint.beam then
			rallyPoint.beam:Destroy()
		end
		if rallyPoint.attachment0 then
			rallyPoint.attachment0:Destroy()
		end
		if rallyPoint.attachment1 then
			rallyPoint.attachment1:Destroy()
		end
		rallyPoints[buildingId] = nil
	end
end

-- Listen for rally point events from server
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameEvent = RemoteEvents:WaitForChild("GameEvent")

GameEvent.OnClientEvent:Connect(function(action, data)
	if action == "SetRallyPoint" then
		if data.buildingId and data.position then
			-- Find building
			local building = workspace.Buildings:FindFirstChild(data.buildingId)
			if building and building:GetAttribute("OwnerId") == player.UserId then
				-- Remove old rally point
				removeRallyPoint(data.buildingId)

				-- Create new rally point
				rallyPoints[data.buildingId] = createRallyPoint(building, data.position)
			end
		end
	elseif action == "ClearRallyPoint" then
		if data.buildingId then
			removeRallyPoint(data.buildingId)
		end
	end
end)

-- Animate rally points (gentle bobbing)
local time = 0
RunService.RenderStepped:Connect(function(dt)
	time = time + dt
	for _, rallyData in pairs(rallyPoints) do
		if rallyData.marker then
			local baseY = rallyData.marker.Position.Y
			rallyData.marker.Position = Vector3.new(
				rallyData.marker.Position.X,
				baseY + math.sin(time * 2) * 0.2,
				rallyData.marker.Position.Z
			)
		end
	end
end)

-- Cleanup when buildings are destroyed
workspace.Buildings.ChildRemoved:Connect(function(building)
	removeRallyPoint(building.Name)
end)
