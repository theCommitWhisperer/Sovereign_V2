--!strict
-- ResourceNodeFactory: Builds gatherable resource node models from the user's
-- real asset library (ReplicatedStorage.Assets.DetailProps.*), resolved at
-- runtime per ResourceNodesConfig. Guarantees every node is a Model with a
-- PrimaryPart and standard attributes so WorkerManager / AIManager / minimap
-- consumers keep working unchanged.
--
-- Falls back to improved procedural models when no asset folder resolves, so
-- the game degrades gracefully instead of showing grey boxes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResourceNodesConfig = require(ReplicatedStorage.Shared.GameData.ResourceNodesConfig)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local FactoryDebug = DebugManager.createChannel("ResourceNodeFactory", false)

local ResourceNodeFactory = {}

local rng = Random.new()

-- ───────────────────────── Template resolution ─────────────────────────────

-- nodeType → resolved template list ({} = resolved but empty → use fallback)
local templateCache: { [string]: { Instance } } = {}

local function resolveFolder(path: string): Instance?
	local current: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for segment in string.gmatch(path, "[^/]+") do
		if not current then return nil end
		current = current:FindFirstChild(segment)
	end
	return current
end

local function getTemplates(nodeType: string): { Instance }
	local cached = templateCache[nodeType]
	if cached then return cached end

	local config = ResourceNodesConfig.get(nodeType)
	local skip = config.SkipTemplateNames or {}
	local templates: { Instance } = {}

	for _, path in ipairs(config.AssetFolders) do
		local folder = resolveFolder(path)
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if not skip[child.Name] and (child:IsA("Model") or child:IsA("BasePart")) then
					table.insert(templates, child)
				end
			end
			if #templates > 0 then
				FactoryDebug:info(`{nodeType}: resolved {#templates} templates from Assets/{path}`)
				break
			end
		end
	end

	if #templates == 0 then
		FactoryDebug:warn(`{nodeType}: no asset templates found, using procedural fallback`)
	end

	templateCache[nodeType] = templates
	return templates
end

-- Allow a re-scan (e.g. after assets stream in or Studio edits)
function ResourceNodeFactory.clearTemplateCache()
	table.clear(templateCache)
end

-- ───────────────────────── Procedural fallbacks ─────────────────────────────

-- These only run when the asset library has no folder for the node type.
-- They are deliberately nicer than the old primitive boxes.

local function buildFallbackTree(parent: Model)
	local trunkH = rng:NextNumber(9, 14)
	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Size = Vector3.new(2.2, trunkH, 2.2)
	trunk.Color = Color3.fromRGB(101, 67, 33)
	trunk.Material = Enum.Material.Wood
	trunk.Anchored = true
	trunk.CFrame = CFrame.new(0, trunkH / 2, 0)
	trunk.Parent = parent

	-- Layered canopy reads far better than one ball
	local canopyBase = trunkH - 1
	for layer = 1, 3 do
		local r = (9 - layer * 2) * rng:NextNumber(0.85, 1.15)
		local leaves = Instance.new("Part")
		leaves.Name = "Leaves" .. layer
		leaves.Shape = Enum.PartType.Ball
		leaves.Size = Vector3.new(r * 2, r * 1.5, r * 2)
		leaves.Color = Color3.fromRGB(rng:NextInteger(40, 70), rng:NextInteger(110, 150), rng:NextInteger(35, 60))
		leaves.Material = Enum.Material.LeafyGrass
		leaves.Anchored = true
		leaves.CanCollide = false
		leaves.CFrame = CFrame.new(
			rng:NextNumber(-1.5, 1.5),
			canopyBase + (layer - 1) * 3,
			rng:NextNumber(-1.5, 1.5)
		)
		leaves.Parent = parent
	end
end

local function buildFallbackBoulder(parent: Model, baseColor: Color3, material: Enum.Material, accentColor: Color3?)
	-- Cluster of 3-5 overlapping rocks
	local count = rng:NextInteger(3, 5)
	for i = 1, count do
		local r = rng:NextNumber(2, 4.5)
		local rock = Instance.new("Part")
		rock.Name = "Boulder" .. i
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.new(r * 2, r * rng:NextNumber(1.1, 1.5), r * 2)
		rock.Color = baseColor
		rock.Material = material
		rock.Anchored = true
		rock.CFrame = CFrame.new(rng:NextNumber(-3, 3), r * 0.55, rng:NextNumber(-3, 3))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		rock.Parent = parent
	end
	if accentColor then
		-- Visible ore veins
		for i = 1, 3 do
			local vein = Instance.new("Part")
			vein.Name = "OreVein" .. i
			vein.Size = Vector3.new(rng:NextNumber(1, 2), rng:NextNumber(0.6, 1.2), rng:NextNumber(1, 2))
			vein.Color = accentColor
			vein.Material = Enum.Material.CorrodedMetal
			vein.Anchored = true
			vein.CanCollide = false
			vein.CFrame = CFrame.new(rng:NextNumber(-3, 3), rng:NextNumber(1.5, 4), rng:NextNumber(-3, 3))
				* CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, 1))
			vein.Parent = parent
		end
	end
end

local function buildFallbackCropField(parent: Model)
	-- Wheat plot: soil base + rows of stalks
	local base = Instance.new("Part")
	base.Name = "Soil"
	base.Size = Vector3.new(9, 0.6, 9)
	base.Color = Color3.fromRGB(96, 74, 48)
	base.Material = Enum.Material.Ground
	base.Anchored = true
	base.CanCollide = false
	base.CFrame = CFrame.new(0, 0.3, 0)
	base.Parent = parent

	for row = -1, 1 do
		for col = -1, 1 do
			local h = rng:NextNumber(2, 3)
			local stalk = Instance.new("Part")
			stalk.Name = "Wheat"
			stalk.Size = Vector3.new(2.2, h, 2.2)
			stalk.Color = Color3.fromRGB(rng:NextInteger(220, 240), rng:NextInteger(200, 225), rng:NextInteger(120, 160))
			stalk.Material = Enum.Material.Grass
			stalk.Anchored = true
			stalk.CanCollide = false
			stalk.CFrame = CFrame.new(col * 2.8, 0.6 + h / 2, row * 2.8)
			stalk.Parent = parent
		end
	end
end

local function buildFallback(nodeType: string): Model
	local model = Instance.new("Model")
	if nodeType == "Wood" then
		buildFallbackTree(model)
	elseif nodeType == "Stone" then
		buildFallbackBoulder(model, Color3.fromRGB(136, 132, 128), Enum.Material.Slate)
	elseif nodeType == "Iron_Ore" then
		buildFallbackBoulder(model, Color3.fromRGB(110, 82, 66), Enum.Material.Rock, Color3.fromRGB(184, 115, 51))
	elseif nodeType == "Food" then
		buildFallbackCropField(model)
	else
		buildFallbackBoulder(model, Color3.fromRGB(136, 132, 128), Enum.Material.Slate)
	end
	return model
end

-- ───────────────────────── Node assembly ────────────────────────────────────

-- Strip scripts/effects from cloned assets and normalise part physics.
local function sanitize(model: Model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BaseScript") or desc:IsA("ModuleScript") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false -- collision handled by the hitbox only
			desc.CanQuery = false
			desc.CanTouch = false
		end
	end
end

-- Wrap a template clone (Model or BasePart) into a node Model with an
-- invisible hitbox as PrimaryPart, scaled, grounded at `position`.
local function assembleNode(nodeType: string, visual: Model, position: Vector3, scale: number): Model
	local config = ResourceNodesConfig.get(nodeType)

	sanitize(visual)
	if scale ~= 1 then
		visual:ScaleTo(scale)
	end

	-- Ground the visual: pivot to XZ, measure bounding box, shift so bottom sits at position.Y
	visual:PivotTo(CFrame.new(position.X, 0, position.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	local bbCf, bbSize = visual:GetBoundingBox()
	local bottomY = bbCf.Position.Y - bbSize.Y / 2
	visual:PivotTo(visual:GetPivot() + Vector3.new(0, position.Y - bottomY, 0))

	-- Node root model
	local node = Instance.new("Model")
	node.Name = nodeType .. "_Node"

	-- Invisible hitbox = PrimaryPart. Workers navigate to PrimaryPart.Position,
	-- AI uses GetPivot, so this must sit at the node's true location.
	local footprint = config.HitboxFootprint
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = config.Collides
	hitbox.CanQuery = true
	hitbox.Size = Vector3.new(
		footprint or math.min(bbSize.X, 12),
		math.min(bbSize.Y, 20),
		footprint or math.min(bbSize.Z, 12)
	)
	hitbox.CFrame = CFrame.new(position.X, position.Y + hitbox.Size.Y / 2, position.Z)
	hitbox.Parent = node

	visual.Name = "Visual"
	visual.Parent = node
	node.PrimaryPart = hitbox

	node:SetAttribute("ResourceType", nodeType)
	node:SetAttribute("ResourcesRemaining", config.MaxResources)
	node:SetAttribute("MaxResources", config.MaxResources)
	-- Spawn-time scale jitter; depletion stages scale relative to this
	node:SetAttribute("SpawnScale", visual:GetScale())

	return node
end

-- Native (unscaled) height of a template, whether Model or loose BasePart.
local function templateHeight(template: Instance): number
	if template:IsA("BasePart") then
		return template.Size.Y
	elseif template:IsA("Model") then
		return template:GetExtentsSize().Y
	end
	return 1
end

-- Public: create one node model of `nodeType` grounded at `position`.
-- Uses a random asset template when available, otherwise the fallback build.
-- Clones are normalised to config.TargetHeight (± HeightJitter) in world studs
-- so oversized source meshes never eat buildable space.
function ResourceNodeFactory.createNode(nodeType: string, position: Vector3): Model
	local config = ResourceNodesConfig.get(nodeType)
	local templates = getTemplates(nodeType)

	local targetHeight = config.TargetHeight
		* ResourceNodesConfig.GlobalSizeMultiplier
		* (1 + (rng:NextNumber(0, 2) - 1) * config.HeightJitter)

	local visual: Model
	local nativeHeight: number

	if #templates > 0 then
		local template = templates[rng:NextInteger(1, #templates)]
		nativeHeight = math.max(templateHeight(template), 0.1)
		local clone = template:Clone()
		if clone:IsA("BasePart") then
			-- Wrap loose parts (mesh rocks etc.) so ScaleTo / bounding box work uniformly
			local wrapper = Instance.new("Model")
			clone.Parent = wrapper
			wrapper.PrimaryPart = clone
			visual = wrapper
		else
			visual = clone :: Model
		end
	else
		visual = buildFallback(nodeType)
		nativeHeight = math.max(visual:GetExtentsSize().Y, 0.1)
	end

	local scale = targetHeight / nativeHeight
	return assembleNode(nodeType, visual, position, scale)
end

-- Public: whether real assets resolved for this type (useful for logging/QA)
function ResourceNodeFactory.hasAssets(nodeType: string): boolean
	return #getTemplates(nodeType) > 0
end

return ResourceNodeFactory
