--!strict
-- GloryManager: Battlefield renown earned from combat kills.
--
-- EARN: every combat kill credited to a player awards Glory scaled by the
--   victim's value (training cost + max health). Melee kills earn full value,
--   ranged kills half; the Lord fighting in first person (playerControlled
--   CombatUnit) earns double for melee kills. Wired in CombatService's
--   handleUnitDeath killer-credit block.
--
-- SPEND:
--   • Hero active abilities (AbilityManager.useAbility charges glory_cost)
--   • Ability cooldown reduction (AbilityManager.reduceCooldownWithGlory)
--   • Prestige structures: buildings with glory_required in BuildingsData
--     (the three Hero Hubs) unlock at LIFETIME Glory thresholds — spending
--     Glory never re-locks a hub.
--
-- REPLICATION: lean by design — a single int pair per player, batched.
--   Dirty players are flushed every REPLICATION_INTERVAL over the existing
--   RemoteEvents/GameEvent channel as ("GloryUpdate", { glory, lifetime }).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local GloryDebug = DebugManager.createChannel("Glory", false)

local GloryManager = {}

-- ---------------------------------------------------------------------------
-- CONFIG
-- ---------------------------------------------------------------------------

local GloryConfig = {
	BASE_PER_KILL = 2, -- flat Glory for any kill
	COST_VALUE_DIVISOR = 20, -- +1 Glory per this much total training cost
	HEALTH_VALUE_DIVISOR = 100, -- +1 Glory per this much victim max health
	MAX_PER_KILL = 75, -- cap so hero kills don't explode the economy
	RANGED_MULT = 0.5, -- ranged kills are worth half
	LORD_MELEE_MULT = 2.0, -- the Lord's first-person melee kills are worth double
	REPLICATION_INTERVAL = 0.5, -- seconds between batched client flushes
}
GloryManager.Config = GloryConfig

export type KillInfo = {
	victimType: string,
	victimCost: { [string]: number }?,
	victimMaxHealth: number,
	attackType: string?, -- "Melee" | "Ranged" (defaults to Melee)
	killerIsLord: boolean?, -- playerControlled first-person Lord landed the kill
}

type GloryState = {
	glory: number, -- spendable balance
	lifetime: number, -- total ever earned (prestige unlocks key off this)
}

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------

local gloryData: { [number]: GloryState } = {}
local dirtyPlayers: { [number]: boolean } = {}

local function getState(userId: number): GloryState
	local state = gloryData[userId]
	if not state then
		state = { glory = 0, lifetime = 0 }
		gloryData[userId] = state
	end
	return state
end

local function markDirty(userId: number)
	dirtyPlayers[userId] = true
end

local function flushDirty()
	for userId in dirtyPlayers do
		dirtyPlayers[userId] = nil
		local player = Players:GetPlayerByUserId(userId)
		local state = gloryData[userId]
		if player and state then
			local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			local gameEvent = remoteEvents and remoteEvents:FindFirstChild("GameEvent")
			if gameEvent and gameEvent:IsA("RemoteEvent") then
				gameEvent:FireClient(player, "GloryUpdate", {
					glory = state.glory,
					lifetime = state.lifetime,
				})
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- PUBLIC API — BALANCE
-- ---------------------------------------------------------------------------

function GloryManager.getGlory(player: Player): number
	return getState(player.UserId).glory
end

function GloryManager.getLifetimeGlory(player: Player): number
	return getState(player.UserId).lifetime
end

function GloryManager.addGlory(player: Player, amount: number, reason: string?)
	if amount <= 0 then
		return
	end
	amount = math.floor(amount)
	local state = getState(player.UserId)
	state.glory += amount
	state.lifetime += amount
	markDirty(player.UserId)
	GloryDebug:info(`{player.Name} earned {amount} Glory ({reason or "unspecified"}) — balance {state.glory}`)
end

function GloryManager.spendGlory(player: Player, amount: number, reason: string?): boolean
	if amount <= 0 then
		return true
	end
	amount = math.ceil(amount)
	local state = getState(player.UserId)
	if state.glory < amount then
		GloryDebug:info(`{player.Name} lacks Glory for {reason or "purchase"} ({state.glory}/{amount})`)
		return false
	end
	state.glory -= amount
	markDirty(player.UserId)
	GloryDebug:info(`{player.Name} spent {amount} Glory ({reason or "unspecified"}) — balance {state.glory}`)
	return true
end

-- ---------------------------------------------------------------------------
-- PUBLIC API — EARN (combat kill path)
-- ---------------------------------------------------------------------------

-- Glory value of a victim, before attack-type multipliers.
function GloryManager.getKillValue(info: KillInfo): number
	local costTotal = 0
	if info.victimCost then
		for _, amount in info.victimCost do
			costTotal += amount
		end
	end
	local value = GloryConfig.BASE_PER_KILL
		+ costTotal / GloryConfig.COST_VALUE_DIVISOR
		+ math.max(info.victimMaxHealth, 0) / GloryConfig.HEALTH_VALUE_DIVISOR
	return math.min(math.floor(value), GloryConfig.MAX_PER_KILL)
end

-- Called from CombatService.handleUnitDeath when a killer's owner is a player.
function GloryManager.awardForKill(player: Player, info: KillInfo)
	local value = GloryManager.getKillValue(info)
	if info.attackType == "Ranged" then
		value = math.floor(value * GloryConfig.RANGED_MULT)
	elseif info.killerIsLord then
		-- First-person Lord melee kill: the marquee Glory moment.
		value = math.floor(value * GloryConfig.LORD_MELEE_MULT)
	end
	if value > 0 then
		GloryManager.addGlory(player, value, `slew {info.victimType}`)
	end
end

-- ---------------------------------------------------------------------------
-- PUBLIC API — PRESTIGE STRUCTURE GATING
-- ---------------------------------------------------------------------------

function GloryManager.getBuildingGloryRequirement(buildingName: string): number
	local buildingInfo = GameData.Buildings[buildingName]
	if buildingInfo and buildingInfo.glory_required then
		return buildingInfo.glory_required :: number
	end
	return 0
end

-- Lifetime-based: once earned, a hub never re-locks even after spending.
function GloryManager.canUnlockBuilding(player: Player, buildingName: string): boolean
	local required = GloryManager.getBuildingGloryRequirement(buildingName)
	if required <= 0 then
		return true
	end
	return getState(player.UserId).lifetime >= required
end

-- ---------------------------------------------------------------------------
-- LIFECYCLE
-- ---------------------------------------------------------------------------

function GloryManager.create(player: Player)
	getState(player.UserId)
	markDirty(player.UserId) -- push initial zero state to the HUD
end

-- Per-match reset for one player (called from GameManager's LeaveGame
-- teardown — Glory is match-scoped, not account-level, so "Return to Menu"
-- clears it the same way disconnecting already does below).
function GloryManager.resetPlayer(player: Player)
	gloryData[player.UserId] = { glory = 0, lifetime = 0 }
	markDirty(player.UserId)
end

-- Full state wipe for every connected player (bulk "last player left" path —
-- redundant with per-player LeaveGame resets in the common case, but a clean
-- safety net for the next match).
function GloryManager.resetMatch()
	for _, player in Players:GetPlayers() do
		GloryManager.resetPlayer(player)
	end
	GloryDebug:info("GloryManager match state reset")
end

function GloryManager.init()
	Players.PlayerAdded:Connect(GloryManager.create)
	Players.PlayerRemoving:Connect(function(player)
		gloryData[player.UserId] = nil
		dirtyPlayers[player.UserId] = nil
	end)
	for _, player in Players:GetPlayers() do
		GloryManager.create(player)
	end

	-- Batched replication loop: one small payload per dirty player.
	task.spawn(function()
		while true do
			task.wait(GloryConfig.REPLICATION_INTERVAL)
			flushDirty()
		end
	end)

	GloryDebug:info("GloryManager initialized")
end

return GloryManager
