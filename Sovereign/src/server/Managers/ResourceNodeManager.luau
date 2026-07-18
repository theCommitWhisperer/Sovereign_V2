--!strict
-- ResourceNodeManager: Spawns and manages gatherable resource nodes.
--
-- Production overhaul:
--   • Nodes are built by ResourceNodeFactory from the real asset library
--     (ReplicatedStorage.Assets.DetailProps.*) with procedural fallbacks.
--   • All stats and layout rules come from ResourceNodesConfig.
--   • Depletion shows staged shrink/fade, then removal (leak-free).
--   • Optional per-type respawn (e.g. food fields regrow).
--   • gatherFromInstance() lets systems that hold the workspace Model
--     (WorkerManager) deplete nodes without touching internal tables.
--
-- Contract kept for existing consumers:
--   • Nodes live in Workspace.ResourceNodes as Models
--   • Model has PrimaryPart + attributes ResourceType / ResourcesRemaining
--   • Public API: spawnNodesNearPosition, spawnNodesFromPatches,
--     findNearestNode, gatherFromNode, getActiveNodes

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local ResourceNodesConfig = require(ReplicatedStorage.Shared.GameData.ResourceNodesConfig)
local ResourceNodeFactory = require(script.Parent.Parent.Systems.ResourceNodeFactory)

local ResourceNodeManagerDebug = DebugManager.createChannel("ResourceNodeManager", false)

local ResourceNodeManager = {}

export type ResourceNode = {
	Type: string,
	Instance: Model,
	Position: Vector3,
	ResourcesRemaining: number,
	MaxResources: number,
	-- internal bookkeeping
	StageIndex: number, -- 0 = pristine
}

local ActiveNodes: { ResourceNode } = {}
-- Fast lookup for gatherFromInstance / leak-free removal
local NodesByInstance: { [Model]: ResourceNode } = {}
-- Bumped by clearAllNodes(); invalidates pending respawn timers from old matches
local generation = 0

local rng = Random.new()

-- Ensure ResourceNodes folder exists
local NodesFolder: Folder
do
	local existing = Workspace:FindFirstChild("ResourceNodes")
	if existing and existing:IsA("Folder") then
		NodesFolder = existing
	else
		NodesFolder = Instance.new("Folder")
		NodesFolder.Name = "ResourceNodes"
		NodesFolder.Parent = Workspace
	end
end

-- ───────────────────────── Terrain grounding ────────────────────────────────

local function buildGroundRaycastParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local includeList: { Instance } = {}
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if terrain then table.insert(includeList, terrain) end
	if baseplate then table.insert(includeList, baseplate) end
	if #includeList == 0 then table.insert(includeList, Workspace) end
	params.FilterDescendantsInstances = includeList
	return params
end

local function groundPosition(x: number, z: number, params: RaycastParams): Vector3?
	local result = Workspace:Raycast(Vector3.new(x, 1000, z), Vector3.new(0, -1500, 0), params)
	if result then
		-- Refuse underwater / out-of-map placements
		if result.Material == Enum.Material.Water then
			return nil
		end
		return result.Position
	end
	return nil
end

-- ───────────────────────── Spawning core ────────────────────────────────────

local function registerNode(nodeType: string, model: Model, position: Vector3): ResourceNode
	local config = ResourceNodesConfig.get(nodeType)
	local node: ResourceNode = {
		Type = nodeType,
		Instance = model,
		Position = position,
		ResourcesRemaining = config.MaxResources,
		MaxResources = config.MaxResources,
		StageIndex = 0,
	}
	table.insert(ActiveNodes, node)
	NodesByInstance[model] = node
	return node
end

local function spawnSingleNode(nodeType: string, position: Vector3): ResourceNode
	local model = ResourceNodeFactory.createNode(nodeType, position)
	model.Parent = NodesFolder
	return registerNode(nodeType, model, position)
end

-- Scatter `count` nodes uniformly in a disc, respecting per-type MinSpacing.
local function scatterNodes(nodeType: string, cx: number, cz: number, radius: number, count: number): number
	local config = ResourceNodesConfig.get(nodeType)
	local params = buildGroundRaycastParams()
	local minSpacingSq = config.MinSpacing * config.MinSpacing

	local placedPositions: { Vector3 } = {}
	local placed = 0
	local attempts = 0
	local maxAttempts = count * 8

	while placed < count and attempts < maxAttempts do
		attempts += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber(0, 1)) * radius -- uniform over the disc
		local px = cx + math.cos(angle) * dist
		local pz = cz + math.sin(angle) * dist

		local position = groundPosition(px, pz, params)
		if position then
			local tooClose = false
			for _, existing in ipairs(placedPositions) do
				local dx, dz = existing.X - position.X, existing.Z - position.Z
				if dx * dx + dz * dz < minSpacingSq then
					tooClose = true
					break
				end
			end
			if not tooClose then
				spawnSingleNode(nodeType, position)
				table.insert(placedPositions, position)
				placed += 1
			end
		end
	end

	return placed
end

-- ───────────────────────── Public spawning API ──────────────────────────────

-- Spawn `count` nodes of `nodeType` randomly within `radius` of `centerPos`.
-- (Kept for the procedural-terrain path in GameManager.)
function ResourceNodeManager.spawnNodesNearPosition(centerPos: Vector3, radius: number, nodeType: string, count: number)
	local placed = scatterNodes(nodeType, centerPos.X, centerPos.Z, radius, count)
	ResourceNodeManagerDebug:info(`Spawned {placed}/{count} {nodeType} nodes near {centerPos}`)
end

-- Spawn nodes from painted ResourcePatches (Studio/editor maps).
-- Node counts follow ResourceNodesConfig so the in-game result matches the
-- density the map editor overlay previews.
function ResourceNodeManager.spawnNodesFromPatches(patches: { any })
	if not patches or #patches == 0 then return end

	for _, patch in ipairs(patches) do
		local cx = patch.Position.X
		local cz = patch.Position.Z
		local radius = math.clamp(patch.Radius or 30, 5, 300)
		local nodeType = patch.ResourceType or "Wood"
		local config = ResourceNodesConfig.get(nodeType)

		-- Density 1-10, default 5 = baseline (matches map editor semantics)
		local density = math.clamp(patch.Density or 5, 1, 10)
		local area = math.pi * radius * radius
		local count = math.clamp(
			math.floor(area / config.AreaPerNode * (density / 5)),
			config.MinPerPatch,
			config.MaxPerPatch
		)

		local placed = scatterNodes(nodeType, cx, cz, radius, count)
		ResourceNodeManagerDebug:info(
			string.format("Patch %s at (%.0f, %.0f) r=%.0f → %d/%d nodes",
				nodeType, cx, cz, radius, placed, count)
		)
	end

	ResourceNodeManagerDebug:info("Spawned nodes from " .. #patches .. " resource patches")
end

-- Register an externally placed model (e.g. hand-placed trees in Studio) as a
-- gatherable node. The model is reparented into Workspace.ResourceNodes and
-- given the standard attributes. Returns the node record.
function ResourceNodeManager.registerExistingModel(model: Model, nodeType: string): ResourceNode?
	if not model.PrimaryPart then
		local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
		if not firstPart then
			ResourceNodeManagerDebug:warn(`registerExistingModel: {model.Name} has no BasePart`)
			return nil
		end
		model.PrimaryPart = firstPart
	end

	local config = ResourceNodesConfig.get(nodeType)

	-- Normalise to the shared gameplay size (same rule as ResourceNodeFactory)
	-- so hand-placed models don't tower over spawned ones.
	local nativeHeight = model:GetExtentsSize().Y
	if nativeHeight > 0.1 then
		local targetHeight = config.TargetHeight * ResourceNodesConfig.GlobalSizeMultiplier
		local groundY = model:GetPivot().Position.Y - nativeHeight / 2
		model:ScaleTo(model:GetScale() * targetHeight / nativeHeight)
		-- Keep the base grounded after scaling
		local newHeight = model:GetExtentsSize().Y
		local pivot = model:GetPivot()
		model:PivotTo(CFrame.new(pivot.Position.X, groundY + newHeight / 2, pivot.Position.Z) * (pivot - pivot.Position))
	end

	model:SetAttribute("ResourceType", nodeType)
	model:SetAttribute("ResourcesRemaining", config.MaxResources)
	model:SetAttribute("MaxResources", config.MaxResources)
	model:SetAttribute("SpawnScale", model:GetScale())
	model.Parent = NodesFolder

	return registerNode(nodeType, model, model:GetPivot().Position)
end

-- ───────────────────────── Depletion & gathering ────────────────────────────

local function removeNode(node: ResourceNode)
	NodesByInstance[node.Instance] = nil
	local index = table.find(ActiveNodes, node)
	if index then
		table.remove(ActiveNodes, index)
	end
	if node.Instance then
		node.Instance:Destroy()
	end
end

local function applyDepletionStage(node: ResourceNode)
	local config = ResourceNodesConfig.get(node.Type)
	local fraction = node.ResourcesRemaining / node.MaxResources

	-- Find the deepest stage whose threshold we've crossed
	local targetIndex = 0
	for i, stage in ipairs(config.DepletionStages) do
		if fraction <= stage.Threshold then
			targetIndex = i
		end
	end
	if targetIndex == node.StageIndex or targetIndex == 0 then return end

	local stage = config.DepletionStages[targetIndex]
	local visual = node.Instance:FindFirstChild("Visual")

	if visual and visual:IsA("Model") then
		-- Stage scale is relative to the node's spawn-time scale; keep the base grounded
		local spawnScale = (node.Instance:GetAttribute("SpawnScale") :: number?) or 1
		local targetScale = spawnScale * stage.Scale
		if math.abs(targetScale - visual:GetScale()) > 0.01 then
			local _, bbSizeBefore = visual:GetBoundingBox()
			visual:ScaleTo(targetScale)
			local _, bbSizeAfter = visual:GetBoundingBox()
			visual:PivotTo(visual:GetPivot() - Vector3.new(0, (bbSizeBefore.Y - bbSizeAfter.Y) / 2, 0))
		end
		for _, part in ipairs(visual:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = math.max(part.Transparency, stage.Transparency)
			end
		end
	else
		-- Externally registered models: transparency only (no Visual wrapper)
		for _, part in ipairs(node.Instance:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "Hitbox" then
				part.Transparency = math.max(part.Transparency, stage.Transparency)
			end
		end
	end

	node.StageIndex = targetIndex
end

local function scheduleRespawn(nodeType: string, position: Vector3, delaySeconds: number)
	local scheduledGeneration = generation
	task.delay(delaySeconds, function()
		-- Skip if the match ended (clearAllNodes) or the game was torn down
		if scheduledGeneration ~= generation or not NodesFolder.Parent then return end
		spawnSingleNode(nodeType, position)
		ResourceNodeManagerDebug:info(`Respawned {nodeType} node at {position}`)
	end)
end

local function depleteNode(node: ResourceNode)
	ResourceNodeManagerDebug:info(`Node depleted: {node.Type}`)
	local config = ResourceNodesConfig.get(node.Type)
	local nodeType, position = node.Type, node.Position
	removeNode(node)
	if config.RespawnSeconds then
		scheduleRespawn(nodeType, position, config.RespawnSeconds)
	end
end

-- Gather from a node record. Returns the amount actually gathered.
function ResourceNodeManager.gatherFromNode(node: ResourceNode, amount: number): number
	if node.ResourcesRemaining <= 0 then return 0 end

	local gathered = math.min(amount, node.ResourcesRemaining)
	node.ResourcesRemaining -= gathered

	if node.Instance and node.Instance.Parent then
		node.Instance:SetAttribute("ResourcesRemaining", node.ResourcesRemaining)
		applyDepletionStage(node)
	end

	if node.ResourcesRemaining <= 0 then
		depleteNode(node)
	end

	return gathered
end

-- Gather via the workspace Model (for WorkerManager, which finds nodes by
-- scanning Workspace.ResourceNodes). Returns the amount actually gathered;
-- 0 means the node is depleted/unknown and the caller should retarget.
function ResourceNodeManager.gatherFromInstance(model: Model, amount: number): number
	local node = NodesByInstance[model]
	if not node then return 0 end
	return ResourceNodeManager.gatherFromNode(node, amount)
end

-- ───────────────────────── Queries & lifecycle ──────────────────────────────

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

-- Get all active nodes
function ResourceNodeManager.getActiveNodes(): { ResourceNode }
	return ActiveNodes
end

-- Remove every node and reset state. Call when a match ends / returns to menu
-- so the next game starts from a clean map.
function ResourceNodeManager.clearAllNodes()
	for _, node in ipairs(ActiveNodes) do
		if node.Instance then
			node.Instance:Destroy()
		end
	end
	table.clear(ActiveNodes)
	table.clear(NodesByInstance)
	generation += 1
	ResourceNodeFactory.clearTemplateCache()
	ResourceNodeManagerDebug:info("Cleared all resource nodes")
end

return ResourceNodeManager
