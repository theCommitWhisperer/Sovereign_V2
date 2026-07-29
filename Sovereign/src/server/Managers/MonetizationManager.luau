--!strict
-- MonetizationManager: MarketplaceService skeleton for cosmetics + hero
-- ability-tree progression. Roblox-policy-compliant: nothing sold here
-- changes base gameplay stats.
--
-- Responsibilities:
--   * ProcessReceipt for DevProduct cosmetics (MonetizationConfig catalogs)
--   * GamePass ownership checks (cached per session)
--   * Owned/equipped cosmetics per player, persisted via DataStore
--   * applyModelCosmetics(model, ownerId) — hook other systems call after
--     spawning a Lord/unit model to apply the owner's equipped skin
--   * Hero ability tree unlock/upgrade (Glory-paid, prerequisite-checked)
--
-- TODO markers below note everything that needs real IDs/assets before ship.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

local MonetizationConfig = require(ReplicatedStorage.Shared.GameData.MonetizationConfig)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

-- Lazy-loaded to avoid init-order cycles (same pattern as CombatService)
local GloryManager = nil :: any

local MonetizationDebug = DebugManager.createChannel("MonetizationManager", false)

local MonetizationManager = {}

export type OwnedData = {
	-- category ("LordSkins"/"UnitSkins"/"BannerStyles") -> set of owned skin ids
	ownedCosmetics: { [string]: { [string]: boolean } },
	-- category -> currently equipped skin id
	equipped: { [string]: string },
	-- ability node id -> current rank (0/absent = locked)
	abilityRanks: { [string]: number },
}

local DATASTORE_NAME = "MonetizationData_v1" -- TODO: bump on schema changes
local playerData: { [number]: OwnedData } = {}
local gamePassCache: { [number]: { [number]: boolean } } = {} -- userId -> gamePassId -> owned

local dataStore: DataStore? = nil
do
	-- DataStores are unavailable in unpublished Studio places; degrade gracefully
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		dataStore = store
	else
		MonetizationDebug:warn("DataStore unavailable — monetization data will not persist this session")
	end
end

-- ============================================================
-- DEFAULTS / PERSISTENCE
-- ============================================================

local function defaultData(): OwnedData
	return {
		ownedCosmetics = {
			LordSkins = { lord_default = true },
			UnitSkins = { units_default = true },
			BannerStyles = { banner_plain = true },
		},
		equipped = {
			LordSkins = "lord_default",
			UnitSkins = "units_default",
			BannerStyles = "banner_plain",
		},
		abilityRanks = {},
	}
end

local function loadData(player: Player)
	local data = defaultData()
	local store = dataStore
	if store then
		local ok, stored = pcall(function()
			return store:GetAsync(`Player_{player.UserId}`)
		end)
		if ok and typeof(stored) == "table" then
			-- Merge stored fields over defaults (schema-tolerant)
			for _, field in { "ownedCosmetics", "equipped", "abilityRanks" } do
				if typeof((stored :: any)[field]) == "table" then
					(data :: any)[field] = (stored :: any)[field]
				end
			end
		elseif not ok then
			MonetizationDebug:warn(`Failed to load monetization data for {player.Name}`)
		end
	end
	playerData[player.UserId] = data
end

local function saveData(player: Player)
	local data = playerData[player.UserId]
	local store = dataStore
	if not data or not store then
		return
	end
	local ok = pcall(function()
		store:SetAsync(`Player_{player.UserId}`, data)
	end)
	if not ok then
		MonetizationDebug:warn(`Failed to save monetization data for {player.Name}`)
	end
end

function MonetizationManager.get(player: Player): OwnedData?
	return playerData[player.UserId]
end

-- ============================================================
-- OWNERSHIP
-- ============================================================

function MonetizationManager.ownsGamePass(player: Player, gamePassId: number): boolean
	if gamePassId == 0 then
		return false -- placeholder id: nothing to own yet (TODO real ids)
	end
	local cache = gamePassCache[player.UserId]
	if not cache then
		cache = {}
		gamePassCache[player.UserId] = cache
	end
	if cache[gamePassId] == nil then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)
		cache[gamePassId] = ok and owns or false
	end
	return cache[gamePassId] == true
end

-- True if the player owns a cosmetic (free, purchased DevProduct, or active GamePass)
function MonetizationManager.ownsCosmetic(player: Player, category: string, skinId: string): boolean
	local data = playerData[player.UserId]
	if not data then
		return false
	end
	local owned = data.ownedCosmetics[category]
	if owned and owned[skinId] then
		return true
	end

	local entry: any = MonetizationConfig.findSkin(category, skinId)
		or (category == "BannerStyles" and MonetizationConfig.findBannerStyle(skinId) or nil)
	if not entry then
		return false
	end
	if entry.acquisition == "Free" then
		return true
	end
	if entry.acquisition == "GamePass" and entry.gamePassId then
		return MonetizationManager.ownsGamePass(player, entry.gamePassId)
	end
	return false
end

local function grantCosmetic(player: Player, category: string, skinId: string)
	local data = playerData[player.UserId]
	if not data then
		return
	end
	data.ownedCosmetics[category] = data.ownedCosmetics[category] or {}
	data.ownedCosmetics[category][skinId] = true
	MonetizationDebug:info(`Granted {category}/{skinId} to {player.Name}`)
	saveData(player)
end

-- ============================================================
-- EQUIP + APPLY HOOK
-- ============================================================

function MonetizationManager.equipCosmetic(player: Player, category: string, skinId: string): boolean
	local data = playerData[player.UserId]
	if not data or not MonetizationManager.ownsCosmetic(player, category, skinId) then
		return false
	end
	data.equipped[category] = skinId
	saveData(player)
	MonetizationDebug:info(`{player.Name} equipped {category}/{skinId}`)
	-- TODO: re-apply cosmetics to already-spawned models (walk playerData.Units
	-- and the Lord character calling applyModelCosmetics on each)
	return true
end

function MonetizationManager.getEquipped(ownerId: number, category: string): string?
	local data = playerData[ownerId]
	return data and data.equipped[category] or nil
end

-- HOOK for other systems (UnitManager after createUnit, Lord spawn code, etc.):
--   MonetizationManager.applyModelCosmetics(model, ownerId)
-- Applies the owner's equipped skin to a spawned model. Tint is implemented;
-- model swapping is a TODO pending skin rigs in Assets/Skins/.
function MonetizationManager.applyModelCosmetics(model: Model, ownerId: number)
	local data = playerData[ownerId]
	if not data then
		return
	end

	local isLord = model:GetAttribute("UnitType") == "Lord" or model.Name == "Lord"
	local category = if isLord then "LordSkins" else "UnitSkins"
	local skinId = data.equipped[category]
	if not skinId then
		return
	end
	local skin = MonetizationConfig.findSkin(category, skinId)
	if not skin then
		return
	end

	if skin.tintColor then
		for _, part in model:GetDescendants() do
			-- Tint clothing/torso parts only; leave faces/tools alone
			if part:IsA("BasePart") and part.Name ~= "Head" then
				part.Color = skin.tintColor
			end
		end
	end

	if skin.modelFolder then
		-- TODO: swap rig with Assets/Skins/<modelFolder> variant (follow the
		-- getUnitModel resolver pattern used by the worker model lifecycle)
		MonetizationDebug:info(`TODO model swap for skin {skin.id} (folder {skin.modelFolder})`)
	end
end

-- ============================================================
-- HERO ABILITY TREE (Glory progression — no base stat changes)
-- ============================================================

function MonetizationManager.getAbilityRank(player: Player, nodeId: string): number
	local data = playerData[player.UserId]
	return data and data.abilityRanks[nodeId] or 0
end

-- Full node-id -> rank map for the ability tree UI (copy — callers can't mutate state)
function MonetizationManager.getAbilityRanks(player: Player): { [string]: number }
	local data = playerData[player.UserId]
	return if data then table.clone(data.abilityRanks) else {}
end

-- Attempts to unlock (rank 0->1) or upgrade a node. Returns success + reason.
function MonetizationManager.purchaseAbilityNode(player: Player, nodeId: string): (boolean, string)
	local data = playerData[player.UserId]
	local node = MonetizationConfig.findAbilityNode(nodeId)
	if not data or not node then
		return false, "Unknown ability node"
	end

	local currentRank = data.abilityRanks[nodeId] or 0
	if currentRank >= node.maxRank then
		return false, "Already at max rank"
	end

	for _, prereqId in node.prerequisites do
		if (data.abilityRanks[prereqId] or 0) < 1 then
			return false, "Missing prerequisite"
		end
	end

	local cost = node.gloryCostPerRank[currentRank + 1] or math.huge
	if not GloryManager then
		GloryManager = require(script.Parent.GloryManager) :: any
	end
	if not GloryManager.spendGlory(player, cost, `ability node {nodeId} rank {currentRank + 1}`) then
		return false, `Not enough Glory (need {cost})`
	end

	data.abilityRanks[nodeId] = currentRank + 1
	saveData(player)
	MonetizationDebug:info(`{player.Name} advanced {nodeId} to rank {currentRank + 1}`)

	-- TODO: notify AbilityManager that the ability is unlocked/upgraded for
	-- this player (AbilityManager is owned by the hero-hub agent — integrate
	-- via a small "isAbilityUnlocked(player, abilityId)" query on this manager)
	return true, "OK"
end

-- Query for AbilityManager/hero systems: is this ability unlocked for the player?
function MonetizationManager.isAbilityUnlocked(player: Player, abilityId: string): boolean
	local data = playerData[player.UserId]
	if not data then
		return false
	end
	for _, node in MonetizationConfig.HeroAbilityTree do
		if node.abilityId == abilityId and (data.abilityRanks[node.id] or 0) >= 1 then
			return true
		end
	end
	return false
end

-- ============================================================
-- RECEIPTS
-- ============================================================

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retry when they rejoin
	end

	local category, skinId = MonetizationConfig.findByProductId(receiptInfo.ProductId)
	if category and skinId then
		grantCosmetic(player, category, skinId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- TODO: handle non-cosmetic DevProducts here if any are ever added
	MonetizationDebug:warn(`Unknown ProductId in receipt: {receiptInfo.ProductId}`)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

function MonetizationManager.init()
	Players.PlayerAdded:Connect(loadData)
	Players.PlayerRemoving:Connect(function(player)
		saveData(player)
		playerData[player.UserId] = nil
		gamePassCache[player.UserId] = nil
	end)
	-- Load any players already present (init runs after PlayerAdded in Studio tests)
	for _, player in Players:GetPlayers() do
		if not playerData[player.UserId] then
			loadData(player)
		end
	end

	-- NOTE: ProcessReceipt is a single global callback — if another system
	-- ever needs receipts, route through a shared dispatcher instead.
	MarketplaceService.ProcessReceipt = processReceipt

	MonetizationDebug:info("MonetizationManager initialized")
end

return MonetizationManager
