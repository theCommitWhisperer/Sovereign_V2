--!strict
-- EstateManager: Capturable neutral territory (estates).
--
-- STUDIO SETUP: place Models (or lone BaseParts) named "EstateFlagpole"
-- (EconomyConfig.Estates.flagpoleName) anywhere under Workspace — convention
-- is an "Estates" folder inside the map folder. Each flagpole becomes one
-- capturable estate. Parts named "Flag"/"Banner" inside the model are tinted
-- to the owner's banner color; if none exist the flagpole part itself is tinted.
--
-- RULES (tunables in EconomyConfig.Estates):
--   * Units (models with a Humanoid + OwnerId attribute) within captureRadius
--     of the flag contest it. One uncontested owner for captureSeconds flips
--     ownership and tints the flag to that owner's PlayerData.BannerColor.
--   * Owned estates spawn an automated supply cart every cartIntervalSeconds
--     (game-speed scaled) that travels in a straight line to the owner's Keep
--     and delivers cartYield (Stone/Iron_Ore/Food) on arrival.
--
-- NOTE: CaravanManager was evaluated for cart movement reuse, but it is purely
-- timer-based (no physical carts), so estates use a lightweight lerp cart here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerManager = require(script.Parent.PlayerManager)
local EconomyConfig = require(ReplicatedStorage.Shared.GameData.EconomyConfig)
local GameSettings = require(ReplicatedStorage.Shared.GameSettings)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local EstateDebug = DebugManager.createChannel("EstateManager", false)

local EstateManager = {}

export type EstateState = {
	id: number,
	model: Instance, -- the EstateFlagpole model/part as placed in Studio
	flagPart: BasePart, -- position anchor for capture checks and cart spawns
	ownerId: number?, -- nil = neutral
	captureCandidateId: number?, -- owner currently working on a capture
	captureProgress: number, -- seconds of uncontested presence
	nextCartTime: number, -- tick() when the next supply cart departs
}

local estates: { EstateState } = {}
local lastScanTime = 0
local loopStarted = false
local cartFolder: Folder? = nil

local Config = EconomyConfig.Estates

-- ============================================================
-- FLAG TINTING (same Banner/Flag naming rule as BuildingManager.applyBannerColor)
-- ============================================================

local function isBannerName(name: string): boolean
	return name == "Banner"
		or name == "Flag"
		or string.match(name, "^Banner") ~= nil
		or string.match(name, "^Flag") ~= nil
end

local function tintEstate(estate: EstateState, color: Color3)
	local recolored = 0
	for _, descendant in estate.model:GetDescendants() do
		if descendant:IsA("BasePart") and isBannerName(descendant.Name) then
			descendant.Color = color
			recolored += 1
		end
	end
	if recolored == 0 then
		-- No dedicated flag mesh: tint the flagpole part itself
		estate.flagPart.Color = color
	end
end

local function getOwnerBannerColor(ownerId: number): Color3
	local player = Players:GetPlayerByUserId(ownerId)
	if player then
		local playerData = PlayerManager.get(player)
		if playerData and playerData.BannerColor then
			return playerData.BannerColor
		end
	end
	return Color3.fromRGB(180, 40, 40) -- fallback for AI / missing banner color
end

-- ============================================================
-- DISCOVERY
-- ============================================================

local function resolveFlagPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Scan Workspace for flagpole markers. Safe to call again (rescan) after a
-- map loads; existing ownership is preserved by matching the same instance.
function EstateManager.rescan()
	lastScanTime = tick()
	local previous: { [Instance]: EstateState } = {}
	for _, estate in estates do
		previous[estate.model] = estate
	end

	estates = {}
	for _, inst in Workspace:GetDescendants() do
		if inst.Name == Config.flagpoleName then
			local flagPart = resolveFlagPart(inst)
			if flagPart then
				local existing = previous[inst]
				if existing then
					table.insert(estates, existing)
					existing.id = #estates
				else
					local estate: EstateState = {
						id = #estates + 1,
						model = inst,
						flagPart = flagPart,
						ownerId = nil,
						captureCandidateId = nil,
						captureProgress = 0,
						nextCartTime = 0,
					}
					table.insert(estates, estate)
					tintEstate(estate, Config.neutralColor)
				end
			else
				EstateDebug:warn(`{Config.flagpoleName} '{inst:GetFullName()}' has no BasePart — skipped`)
			end
		end
	end

	if #estates > 0 then
		EstateDebug:info(`Discovered {#estates} estate flagpole(s)`)
	end
end

function EstateManager.getEstateCount(): number
	return #estates
end

function EstateManager.getEstatesForOwner(ownerId: number): { EstateState }
	local owned = {}
	for _, estate in estates do
		if estate.ownerId == ownerId then
			table.insert(owned, estate)
		end
	end
	return owned
end

-- Revert every estate an owner holds back to neutral (player left, or their
-- kingdom was eliminated). Works for AI ownerIds exactly like real players —
-- ownerId is just a number either way. Safe to call with no matching estates.
function EstateManager.releaseEstatesForOwner(ownerId: number)
	for _, estate in estates do
		if estate.ownerId == ownerId then
			estate.ownerId = nil
			estate.captureCandidateId = nil
			estate.captureProgress = 0
			estate.nextCartTime = 0
			tintEstate(estate, Config.neutralColor)
		end
	end
end

-- Full state wipe for a new match: every estate reverts to neutral and any
-- in-flight supply carts are cleared. Flagpole discovery (estates table
-- membership) is untouched — rescan()/startLoop() re-establish it.
function EstateManager.resetMatch()
	for _, estate in estates do
		estate.ownerId = nil
		estate.captureCandidateId = nil
		estate.captureProgress = 0
		estate.nextCartTime = 0
		tintEstate(estate, Config.neutralColor)
	end
	if cartFolder and cartFolder.Parent then
		cartFolder:ClearAllChildren()
	end
	EstateDebug:info("EstateManager match state reset — all estates neutral")
end

-- ============================================================
-- CAPTURE LOGIC
-- ============================================================

-- Returns the set of ownerIds with at least one living unit near the flag
local function getContestingOwners(estate: EstateState): { [number]: boolean }
	local owners: { [number]: boolean } = {}
	local params = OverlapParams.new()
	params.MaxParts = 200

	local parts = Workspace:GetPartBoundsInRadius(estate.flagPart.Position, Config.captureRadius, params)
	local seenModels: { [Model]: boolean } = {}

	for _, part in parts do
		local model = part:FindFirstAncestorWhichIsA("Model")
		while model and model:GetAttribute("OwnerId") == nil do
			model = model:FindFirstAncestorWhichIsA("Model")
		end
		if model and not seenModels[model] then
			seenModels[model] = true
			local ownerId = model:GetAttribute("OwnerId")
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			-- Only living units contest (buildings have OwnerId but no Humanoid)
			if typeof(ownerId) == "number" and humanoid and humanoid.Health > 0 then
				owners[ownerId] = true
			end
		end
	end

	return owners
end

local function fireEstateEvent(userId: number, eventName: string, payload: { [string]: any })
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local GameEvent = RemoteEvents and RemoteEvents:FindFirstChild("GameEvent")
	if GameEvent and GameEvent:IsA("RemoteEvent") then
		pcall(function()
			GameEvent:FireClient(player, eventName, payload)
		end)
	end
end

local function setEstateOwner(estate: EstateState, newOwnerId: number)
	local previousOwnerId = estate.ownerId
	estate.ownerId = newOwnerId
	estate.captureCandidateId = nil
	estate.captureProgress = 0
	estate.nextCartTime = tick() + GameSettings.waitInterval(Config.cartIntervalSeconds)

	tintEstate(estate, getOwnerBannerColor(newOwnerId))
	EstateDebug:info(`Estate {estate.id} captured by owner {newOwnerId}`)

	fireEstateEvent(newOwnerId, "EstateCaptured", {
		estateId = estate.id,
		position = estate.flagPart.Position,
		yield = Config.cartYield,
	})
	if previousOwnerId then
		fireEstateEvent(previousOwnerId, "EstateLost", {
			estateId = estate.id,
			position = estate.flagPart.Position,
		})
	end
end

-- Lightweight capture-progress push: only fires while a capture is actively
-- running (once per tickSeconds, i.e. 1 Hz) to the capturing player and the
-- current owner. `capturing = false` signals the attempt ended/was broken.
local function fireCaptureProgress(estate: EstateState, fraction: number, capturing: boolean)
	local candidateId = estate.captureCandidateId
	if candidateId then
		fireEstateEvent(candidateId, "EstateCaptureProgress", {
			estateId = estate.id,
			fraction = fraction,
			capturing = capturing,
			attacker = true,
		})
	end
	if estate.ownerId and estate.ownerId ~= candidateId then
		fireEstateEvent(estate.ownerId, "EstateCaptureProgress", {
			estateId = estate.id,
			fraction = fraction,
			capturing = capturing,
			attacker = false,
		})
	end
end

local function updateCapture(estate: EstateState, dt: number)
	local owners = getContestingOwners(estate)

	-- Count owners present and check whether the current owner defends
	local presentCount = 0
	local soleOwnerId: number? = nil
	for ownerId in owners do
		presentCount += 1
		soleOwnerId = ownerId
	end

	if presentCount == 1 and soleOwnerId ~= nil and soleOwnerId ~= estate.ownerId then
		-- One uncontested attacker: build capture progress
		if estate.captureCandidateId ~= soleOwnerId then
			estate.captureCandidateId = soleOwnerId
			estate.captureProgress = 0
		end
		estate.captureProgress += dt
		if estate.captureProgress >= Config.captureSeconds then
			setEstateOwner(estate, soleOwnerId) -- fires EstateCaptured/EstateLost; clients clear their bars
		else
			fireCaptureProgress(estate, math.clamp(estate.captureProgress / Config.captureSeconds, 0, 1), true)
		end
	else
		-- Empty, contested, or defended: capture attempt resets
		if estate.captureProgress > 0 then
			fireCaptureProgress(estate, 0, false)
		end
		estate.captureCandidateId = nil
		estate.captureProgress = 0
	end
end

-- ============================================================
-- SUPPLY CARTS
-- ============================================================

local function getCartFolder(): Folder
	if cartFolder and cartFolder.Parent then
		return cartFolder
	end
	local folder = Workspace:FindFirstChild("EstateCarts")
	if not (folder and folder:IsA("Folder")) then
		folder = Instance.new("Folder")
		folder.Name = "EstateCarts"
		folder.Parent = Workspace
	end
	cartFolder = folder :: Folder
	return cartFolder :: Folder
end

local function spawnSupplyCart(estate: EstateState)
	local ownerId = estate.ownerId
	if not ownerId then
		return
	end
	local player = Players:GetPlayerByUserId(ownerId)
	if not player then
		return -- AI/absent owners hold estates but receive no deliveries (TODO: AI resource hook)
	end
	local playerData = PlayerManager.get(player)
	local keep = playerData and playerData.Keep
	local keepPart: BasePart? = nil
	if keep then
		if keep:IsA("Model") then
			keepPart = keep.PrimaryPart or keep:FindFirstChildWhichIsA("BasePart", true)
		elseif keep:IsA("BasePart") then
			keepPart = keep
		end
	end
	if not playerData or not keepPart then
		return -- No Keep to deliver to
	end

	-- Simple anchored cart that lerps straight to the Keep
	local cart = Instance.new("Part")
	cart.Name = "SupplyCart"
	cart.Size = Vector3.new(3, 2, 4)
	cart.Color = Color3.fromRGB(120, 85, 50)
	cart.Material = Enum.Material.Wood
	cart.Anchored = true
	cart.CanCollide = false
	cart.CanQuery = false
	cart:SetAttribute("OwnerId", ownerId) -- cosmetic tag; no Humanoid, so carts never contest
	cart.CFrame = CFrame.new(estate.flagPart.Position + Vector3.new(0, 2, 0))
	cart.Parent = getCartFolder()

	local startPos = cart.Position
	local endPos = keepPart.Position + Vector3.new(0, 2, 0)
	local distance = (endPos - startPos).Magnitude
	local duration = math.max(distance / Config.cartSpeed, 0.5)

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local dt = task.wait(0.1)
			elapsed += dt
			if not cart.Parent then
				return -- cart was destroyed externally
			end
			local alpha = math.clamp(elapsed / duration, 0, 1)
			local pos = startPos:Lerp(endPos, alpha)
			local flatDelta = Vector3.new(endPos.X - pos.X, 0, endPos.Z - pos.Z)
			local lookTarget = if flatDelta.Magnitude > 0.01 then endPos else pos + Vector3.zAxis
			cart.CFrame = CFrame.lookAt(pos, lookTarget)
		end
		cart:Destroy()

		-- Deliver the goods (player may have left mid-journey)
		local deliverPlayer = Players:GetPlayerByUserId(ownerId)
		if deliverPlayer and PlayerManager.get(deliverPlayer) then
			PlayerManager.addResources(deliverPlayer, Config.cartYield)
			EstateDebug:info(`Estate {estate.id} cart delivered to {deliverPlayer.Name}`)
			fireEstateEvent(ownerId, "SupplyCartArrived", {
				estateId = estate.id,
				resources = Config.cartYield,
			})
			local pd = PlayerManager.get(deliverPlayer)
			if pd then
				fireEstateEvent(ownerId, "UpdateResources", { resources = pd.Resources })
			end
		end
	end)
end

local function updateCarts(estate: EstateState)
	if not estate.ownerId then
		return
	end
	local now = tick()
	if estate.nextCartTime > 0 and now >= estate.nextCartTime then
		estate.nextCartTime = now + GameSettings.waitInterval(Config.cartIntervalSeconds)
		spawnSupplyCart(estate)
	end
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

function EstateManager.init()
	-- When an owner leaves, their estates revert to neutral
	Players.PlayerRemoving:Connect(function(player)
		EstateManager.releaseEstatesForOwner(player.UserId)
	end)
	EstateDebug:info("EstateManager initialized")
end

function EstateManager.startLoop()
	if loopStarted then
		return
	end
	loopStarted = true

	EstateManager.rescan()

	task.spawn(function()
		while true do
			local dt = task.wait(Config.tickSeconds)

			-- Maps can finish loading after game start: keep looking for
			-- flagpoles every 10s until at least one is found
			if #estates == 0 then
				if tick() - lastScanTime >= 10 then
					EstateManager.rescan()
				end
				continue
			end

			for _, estate in estates do
				if estate.flagPart.Parent then
					updateCapture(estate, dt)
					updateCarts(estate)
				end
			end
		end
	end)

	EstateDebug:info("EstateManager loop started")
end

return EstateManager
