--!strict
-- ResourceNodeManager: Spawns and manages resource nodes (trees, stone, etc.)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local ResourceNodeManagerDebug = DebugManager.createChannel("ResourceNodeManager", false)

local ResourceNodeManager = {}

export type ResourceNode = {
	Type: string,
	Instance: Model,
	Position: Vector3,
	ResourcesRemaining: number,
	MaxResources: number,
}

local ActiveNodes: { ResourceNode } = {}

-- Ensure ResourceNodes folder exists
local NodesFolder = Workspace:FindFirstChild("ResourceNodes")
if not NodesFolder then
	NodesFolder = Instance.new("Folder")
	NodesFolder.Name = "ResourceNodes"
	NodesFolder.Parent = Workspace
end

-- Create a simple resource node model
local function createNodeModel(nodeType: string, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = nodeType .. "_Node"

	local part = Instance.new("Part")
	part.Name = "NodePart"
	part.Anchored = true
	part.CanCollide = true

	if nodeType == "Wood" then
		-- Tree
		part.Size = Vector3.new(3, 12, 3)
		part.Color = Color3.fromRGB(101, 67, 33) -- Brown trunk
		part.Material = Enum.Material.Wood

		-- Add leaves
		local leaves = Instance.new("Part")
		leaves.Name = "Leaves"
		leaves.Size = Vector3.new(8, 8, 8)
		leaves.Color = Color3.fromRGB(34, 139, 34) -- Green
		leaves.Material = Enum.Material.Grass
		leaves.Anchored = true
		leaves.CanCollide = false
		leaves.Position = position + Vector3.new(0, 10, 0)
		leaves.Parent = model
	elseif nodeType == "Stone" then
		-- Rock
		part.Size = Vector3.new(6, 4, 6)
		part.Color = Color3.fromRGB(128, 128, 128)
		part.Material = Enum.Material.Slate
	elseif nodeType == "Food" then
		-- Wheat field
		part.Size = Vector3.new(8, 2, 8)
		part.Color = Color3.fromRGB(238, 232, 170) -- Pale yellow
		part.Material = Enum.Material.Ground
	elseif nodeType == "Iron_Ore" then
		-- Iron ore deposit
		part.Size = Vector3.new(5, 3, 5)
		part.Color = Color3.fromRGB(139, 69, 19) -- Dark brown/rust
		part.Material = Enum.Material.Slate

		-- Add some rust-colored spots
		local ore = Instance.new("Part")
		ore.Name = "OreVein"
		ore.Size = Vector3.new(3, 2, 3)
		ore.Color = Color3.fromRGB(184, 115, 51) -- Rust color
		ore.Material = Enum.Material.CorrodedMetal
		ore.Anchored = true
		ore.CanCollide = false
		ore.Position = position + Vector3.new(0, 2, 0)
		ore.Parent = model
	end

	part.Position = position + Vector3.new(0, part.Size.Y / 2, 0)
	part.Parent = model

	model.PrimaryPart = part
	model:SetAttribute("ResourceType", nodeType)
	model:SetAttribute("ResourcesRemaining", 100)

	return model
end

-- Spawn resource nodes around a position
function ResourceNodeManager.spawnNodesNearPosition(centerPos: Vector3, radius: number, nodeType: string, count: number)
	ResourceNodeManagerDebug:info(`Spawning {count} {nodeType} nodes near {centerPos}`)

	for i = 1, count do
		-- Random position within radius
		local angle = math.random() * math.pi * 2
		local distance = math.random(radius * 0.3, radius)
		local offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local position = centerPos + offset

		-- Raycast down to find ground (include Terrain voxels and any Baseplate)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		local terrainInst = Workspace:FindFirstChildOfClass("Terrain")
		local baseplateInst = Workspace:FindFirstChild("Baseplate")
		local includeList: { Instance } = {}
		if terrainInst then table.insert(includeList, terrainInst) end
		if baseplateInst then table.insert(includeList, baseplateInst) end
		if #includeList == 0 then table.insert(includeList, Workspace) end
		raycastParams.FilterDescendantsInstances = includeList

		local result = Workspace:Raycast(position + Vector3.new(0, 100, 0), Vector3.new(0, -200, 0), raycastParams)

		if result then
			position = result.Position
		end

		-- Create node
		local nodeModel = createNodeModel(nodeType, position)
		nodeModel.Parent = NodesFolder

		-- Track node
		local node: ResourceNode = {
			Type = nodeType,
			Instance = nodeModel,
			Position = position,
			ResourcesRemaining = 100,
			MaxResources = 100,
		}

		table.insert(ActiveNodes, node)
	end

	ResourceNodeManagerDebug:info(`Spawned {count} {nodeType} nodes`)
end

-- Find nearest resource node of a type
function ResourceNodeManager.findNearestNode(position: Vector3, resourceType: string): ResourceNode?
	local nearest: ResourceNode? = nil
	local nearestDistance = math.huge

	for _, node in ActiveNodes do
		if node.Type == resourceType and node.ResourcesRemaining > 0 then
			local distance = (node.Position - position).Magnitude
			if distance < nearestDistance then
				nearest = node
				nearestDistance = distance
			end
		end
	end

	return nearest
end

-- Gather from a node
function ResourceNodeManager.gatherFromNode(node: ResourceNode, amount: number): number
	local gathered = math.min(amount, node.ResourcesRemaining)
	node.ResourcesRemaining = node.ResourcesRemaining - gathered

	-- Update visual
	if node.Instance and node.Instance:IsA("Model") then
		node.Instance:SetAttribute("ResourcesRemaining", node.ResourcesRemaining)

		-- Make it smaller as resources deplete
		local scale = node.ResourcesRemaining / node.MaxResources
		if scale < 0.3 then
			-- Node is almost depleted, make it more transparent
			for _, part in node.Instance:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = 0.5
				end
			end
		end

		-- If depleted, remove it
		if node.ResourcesRemaining <= 0 then
			ResourceNodeManagerDebug:info(`Node depleted: {node.Type}`)
			node.Instance:Destroy()
			-- Note: We should remove from ActiveNodes table, but we'll handle that in cleanup
		end
	end

	return gathered
end

-- Spawn resource nodes from painted ResourcePatches (used for Studio terrain maps).
-- Each patch defines a center, radius, resource type, and density.
-- Nodes are distributed randomly within the patch circle using the same raycast logic.
function ResourceNodeManager.spawnNodesFromPatches(patches: { any })
	if not patches or #patches == 0 then return end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	local terrainInst = Workspace:FindFirstChildOfClass("Terrain")
	local baseplateInst = Workspace:FindFirstChild("Baseplate")
	local includeList: { Instance } = {}
	if terrainInst then table.insert(includeList, terrainInst) end
	if baseplateInst then table.insert(includeList, baseplateInst) end
	if #includeList == 0 then table.insert(includeList, Workspace) end
	raycastParams.FilterDescendantsInstances = includeList

	for _, patch in ipairs(patches) do
		local cx = patch.Position.X
		local cz = patch.Position.Z
		local radius = math.clamp(patch.Radius or 30, 5, 300)
		local nodeType = patch.ResourceType or "Wood"
		-- Density 1-10, default 5. Scale node count to patch area like the editor does.
		local density = math.clamp(patch.Density or 5, 1, 10)
		local area = math.pi * radius * radius
		local count = math.clamp(math.floor(area / 300 * (density / 5)), 1, 60)

		ResourceNodeManagerDebug:info(
			string.format("Spawning %d %s nodes from patch at (%.0f, %.0f) r=%.0f",
				count, nodeType, cx, cz, radius)
		)

		local placed = 0
		local attempts = 0
		while placed < count and attempts < count * 6 do
			attempts += 1
			local angle = math.random() * math.pi * 2
			local dist = math.sqrt(math.random()) * radius -- uniform disc distribution
			local px = cx + math.cos(angle) * dist
			local pz = cz + math.sin(angle) * dist

			local position = Vector3.new(px, 0, pz)
			local result = Workspace:Raycast(Vector3.new(px, 500, pz), Vector3.new(0, -600, 0), raycastParams)
			if result then
				position = result.Position
			end

			local nodeModel = createNodeModel(nodeType, position)
			nodeModel.Parent = NodesFolder

			table.insert(ActiveNodes, {
				Type = nodeType,
				Instance = nodeModel,
				Position = position,
				ResourcesRemaining = 100,
				MaxResources = 100,
			} :: ResourceNode)

			placed += 1
		end
	end

	ResourceNodeManagerDebug:info("Spawned nodes from " .. #patches .. " resource patches")
end

-- Get all active nodes
function ResourceNodeManager.getActiveNodes(): { ResourceNode }
	return ActiveNodes
end

return ResourceNodeManager
