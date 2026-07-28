--!strict
-- EliminationManager: Military win conditions for Sovereign matches.
--
-- Implements exactly two elimination paths (active in the "Conquest" and
-- "Regicide" lobby victory modes; "Score" keeps the old economic conditions in
-- VictoryConditionManager and the Lord's 10-second respawn):
--
--   (a) DIRECT SLAY — the Lord (the player's King character) is slain while a
--       military mode is active. DESIGN DECISION: the existing 10s respawn in
--       GameManager is a Score-mode convenience; in military modes the Lord's
--       death is FINAL (permadeath, no respawn). GameManager consults
--       EliminationManager.onLordSlain() in its Died handler and skips the
--       respawn when it returns true.
--
--   (b) KEEP CAPTURE — enemy units hold the area around a player's Keep,
--       uncontested by any of the owner's (or their allies') units, for
--       CAPTURE_SECONDS. Progress decays at double speed while contested or
--       vacated. Capture is paused during lobby peace time.
--
-- A player whose Keep is destroyed outright (siege) is also funneled through
-- eliminate() so last-standing detection stays consistent with the existing
-- "Keep Destroyed" loss condition in VictoryConditionManager.
--
-- On elimination: staged Keep destruction sequence (fire + smoke particles,
-- charring, collapse tween), a "Defeat" GameEvent to the loser (App.luau
-- routes it to the DefeatScreen). When one player/team remains, every survivor
-- gets a "Victory" GameEvent (VictoryScreen).
--
-- AI KINGDOMS: participants are tracked generically by ownerId (a real UserId
-- for players, AI's negative pseudo-ownerId for AI — see LobbyManager.addAI).
-- AI kingdoms get BOTH elimination paths:
--   * Keep Capture / Keep Destroyed — the 70-stud sweep and the "Keep gone"
--     check already key off numeric OwnerId attributes, so they generalize
--     for free; AI records just carry their Keep instance directly (no
--     PlayerManager/PlayerData backing AI).
--   * Direct Slay — AI kingdoms are spawned with a real "King" NPC combat
--     unit (UnitManager.createUnit("King", ...), same data-driven path as any
--     other AI unit — no Player character, so none of the camera/first-person
--     hooks that key off IsKing/CanFirstPerson ever run for it). Its death is
--     caught via CombatManager.onUnitKilled (unitType == "King") instead of
--     the Humanoid.Died handler GameManager uses for the human Lord.
--
-- Full elimination sequence (both AI and human): staged Keep collapse, then
-- despawn remaining units, release held estates to neutral, and neutralize
-- remaining buildings — all batched over multiple frames.
--
-- On leave/return-to-menu the caller (GameManager LeaveGame) calls
-- cleanupPlayer(ownerId); resetMatch() wipes all state for a fresh match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Managers = script.Parent
local PlayerManager = require(Managers.PlayerManager)
local FactionManager = require(Managers.FactionManager)
local CombatManager = require(Managers.CombatManager)
local AIManager = require(Managers.AIManager)
local EstateManager = require(Managers.EstateManager)
local PathfindingIntegration = require(Managers.Parent.Systems.PathfindingIntegration)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local EliminationDebug = DebugManager.createChannel("Elimination", false)

local EliminationManager = {}

local CONFIG = {
	CAPTURE_RADIUS = 70, -- studs around the Keep pivot that counts as "the platform"
	CAPTURE_SECONDS = 60, -- uncontested enemy presence needed to capture
	CAPTURE_DECAY_MULT = 2, -- progress drains at 2x while no uncontested attacker
	CHECK_INTERVAL = 1, -- seconds between capture sweeps
	PROGRESS_NOTIFY_STEP = 0.25, -- notify the owner every 25% of capture progress
	CLEANUP_BATCH_SIZE = 6, -- units/buildings destroyed per cleanup batch
	CLEANUP_BATCH_DELAY = 0.15, -- seconds between cleanup batches
}

type Record = {
	ownerId: number,
	ownerName: string,
	isAI: boolean,
	player: Player?, -- nil for AI kingdoms
	aiKeep: Instance?, -- AI's Keep model (players use PlayerManager.get(player).Keep instead)
	eliminated: boolean,
	captureProgress: number, -- seconds of uncontested enemy occupation
	lastNotifiedQuarter: number,
}

local records: { [number]: Record } = {}
local eliminationEnabled = false
local matchEnded = false
local matchStartTime = 0
local peaceTimeSeconds = 0

local function getGameEvent(): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local event = remotes and remotes:FindFirstChild("GameEvent")
	return if event and event:IsA("RemoteEvent") then event else nil
end

-- ---------------------------------------------------------------------------
-- RECORD HELPERS (generalize Player-based lookups across AI ownerIds)
-- ---------------------------------------------------------------------------

local function getRecordFaction(record: Record): string
	if record.player then
		local playerData = PlayerManager.get(record.player)
		return (playerData and playerData.Faction) or "Kingdom"
	end
	local aiState = AIManager.getState(record.ownerId)
	return (aiState and aiState.faction) or "Kingdom"
end

local function getRecordKeep(record: Record): Instance?
	if record.player then
		local playerData = PlayerManager.get(record.player)
		return playerData and playerData.Keep
	end
	return record.aiKeep
end

-- Whether a record is still an active participant in capture sweeps (not yet
-- eliminated, still "in the match" — connected + InGame for players, still
-- tracked by AIManager for AI).
local function isRecordActive(record: Record): boolean
	if record.eliminated then
		return false
	end
	if record.player then
		if not record.player.Parent then
			return false
		end
		local playerData = PlayerManager.get(record.player)
		return playerData ~= nil and playerData.GameState == "InGame"
	end
	return AIManager.getState(record.ownerId) ~= nil
end

-- ---------------------------------------------------------------------------
-- KEEP DESTRUCTION SEQUENCE (staged: ignite ? char ? collapse)
-- ---------------------------------------------------------------------------

local function addFireEffects(part: BasePart)
	local fire = Instance.new("Fire")
	fire.Heat = 12
	fire.Size = math.clamp(part.Size.Magnitude / 3, 4, 25)
	fire.Parent = part

	local smoke = Instance.new("Smoke")
	smoke.RiseVelocity = 8
	smoke.Size = math.clamp(part.Size.Magnitude / 4, 3, 18)
	smoke.Opacity = 0.35
	smoke.Parent = part
end

local function playKeepDestruction(keep: Instance)
	if not keep:IsA("Model") or not keep.Parent then
		return
	end
	local model = keep :: Model

	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	if #parts == 0 then
		model:Destroy()
		return
	end

	-- Stage 1 (t=0): the Keep catches fire — flames on the largest parts
	table.sort(parts, function(a, b)
		return a.Size.Magnitude > b.Size.Magnitude
	end)
	for index = 1, math.min(8, #parts) do
		addFireEffects(parts[index])
	end

	-- Stage 2 (t=2s): stonework chars and buckles
	task.delay(2, function()
		if not model.Parent then
			return
		end
		local charColor = Color3.fromRGB(35, 30, 28)
		for _, part in parts do
			if part.Parent then
				TweenService:Create(part, TweenInfo.new(2.5), { Color = charColor }):Play()
			end
		end
	end)

	-- Stage 3 (t=4.5s): collapse — the whole structure sinks and fades
	task.delay(4.5, function()
		if not model.Parent then
			return
		end
		local _, bbSize = model:GetBoundingBox()
		local sinkDepth = math.max(bbSize.Y * 0.85, 10)
		local collapseInfo = TweenInfo.new(3.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in parts do
			if part.Parent then
				TweenService:Create(part, collapseInfo, {
					Position = part.Position - Vector3.new(0, sinkDepth, 0),
					Transparency = 1,
				}):Play()
			end
		end
	end)

	-- Cleanup (t=8.5s)
	task.delay(8.5, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- WIN / ELIMINATION CORE
-- ---------------------------------------------------------------------------

local LOSS_DESCRIPTIONS: { [string]: string } = {
	LordSlain = "Your Lord has fallen in battle. The kingdom dies with its sovereign.",
	KeepCaptured = "Enemy soldiers seized your Keep and tore down your banner.",
	KeepDestroyed = "Your Keep was reduced to rubble.",
}

-- End-of-match stats snapshot for the Victory/Defeat screens (existing
-- AchievementManager counters + Glory; lazy-required to avoid init cycles).
local function buildMatchStats(player: Player): { [string]: number }
	local stats: { [string]: number } = {}
	pcall(function()
		local AchievementManager = require(Managers.AchievementManager) :: any
		stats = AchievementManager.getMatchSnapshot(player, matchStartTime)
	end)
	return stats
end

local function survivingRecords(): { Record }
	local survivors = {}
	for _, record in records do
		if not record.eliminated then
			if record.player then
				if record.player.Parent then
					table.insert(survivors, record)
				end
			else
				-- AI kingdoms have no Parent to check; they survive until eliminated.
				table.insert(survivors, record)
			end
		end
	end
	return survivors
end

-- One kingdom/team standing (human or AI) ? fire the victory flow for every
-- surviving HUMAN (AI has no client to notify). A human only wins once every
-- OTHER kingdom — AI or human — is eliminated; there is no team/alliance
-- system beyond "same faction name" (FactionManager.areEnemies), so this is
-- inherently free-for-all unless two kingdoms happen to share a faction.
local function checkForWinner()
	if matchEnded then
		return
	end

	local survivors = survivingRecords()
	if #survivors == 0 then
		matchEnded = true -- mutual destruction; defeats already sent
		return
	end

	-- All survivors must be mutually non-hostile (same faction/team)
	for i = 1, #survivors do
		for j = i + 1, #survivors do
			local factionA = getRecordFaction(survivors[i])
			local factionB = getRecordFaction(survivors[j])
			if FactionManager.areEnemies(factionA, factionB) then
				return -- hostile kingdoms remain; the match continues
			end
		end
	end

	-- Solo matches never had an opponent to conquer — don't declare instant victory
	local totalRegistered = 0
	for _ in records do
		totalRegistered += 1
	end
	if totalRegistered <= 1 then
		return
	end

	matchEnded = true
	local gameEvent = getGameEvent()
	for _, record in survivors do
		EliminationDebug:info(`{record.ownerName} wins by conquest!`)
		if record.player and gameEvent then
			pcall(function()
				gameEvent:FireClient(record.player, "Victory", {
					victoryType = "Conquest",
					description = "All rival lords have been slain or unseated. The land is yours.",
					stats = buildMatchStats(record.player),
				})
			end)
		end
	end
end

-- ---------------------------------------------------------------------------
-- FULL ELIMINATION SEQUENCE — territory cleanup (both AI and human)
-- ---------------------------------------------------------------------------
-- Despawn the eliminated kingdom's remaining units, release held estates to
-- neutral, and neutralize remaining buildings (the Keep itself is handled by
-- playKeepDestruction's staged sequence). Both sweeps are batched over
-- multiple frames so a large army/base doesn't spike a frame when it falls.

local function despawnUnitsForOwner(ownerId: number, ownerPlayer: Player?)
	local unitsFolder = Workspace:FindFirstChild("Units")
	if not unitsFolder then
		return
	end
	local targets: { Instance } = {}
	for _, unit in unitsFolder:GetChildren() do
		if unit:GetAttribute("OwnerId") == ownerId then
			table.insert(targets, unit)
		end
	end
	if #targets == 0 then
		return
	end

	task.spawn(function()
		for i, unit in targets do
			if unit.Parent then
				-- Route through the same removal paths a normal unit death uses so
				-- nothing double-frees or leaks (pathfinding mover + PlayerManager
				-- bookkeeping; CombatService unregisters itself next tick once the
				-- model's Parent goes nil).
				pcall(function()
					PathfindingIntegration.unregisterMover(unit :: any)
				end)
				if ownerPlayer then
					PlayerManager.removeUnit(ownerPlayer, unit :: any)
				end
				unit:Destroy()
			end
			if i % CONFIG.CLEANUP_BATCH_SIZE == 0 then
				task.wait(CONFIG.CLEANUP_BATCH_DELAY)
			end
		end
		EliminationDebug:info(`Despawned {#targets} units for eliminated owner {ownerId}`)
	end)
end

local function neutralizeBuildingsForOwner(ownerId: number, skipInstance: Instance?)
	local buildingsFolder = Workspace:FindFirstChild("Buildings")
	if not buildingsFolder then
		return
	end
	local targets: { Instance } = {}
	for _, building in buildingsFolder:GetChildren() do
		if building ~= skipInstance and building:GetAttribute("OwnerId") == ownerId then
			table.insert(targets, building)
		end
	end
	if #targets == 0 then
		return
	end

	task.spawn(function()
		for i, building in targets do
			if building.Parent then
				for _, part in building:GetDescendants() do
					if part:IsA("BasePart") then
						TweenService:Create(part, TweenInfo.new(1.2), { Transparency = 1 }):Play()
					end
				end
				task.delay(1.2, function()
					if building.Parent then
						building:Destroy()
					end
				end)
			end
			if i % CONFIG.CLEANUP_BATCH_SIZE == 0 then
				task.wait(CONFIG.CLEANUP_BATCH_DELAY)
			end
		end
		EliminationDebug:info(`Neutralized {#targets} buildings for eliminated owner {ownerId}`)
	end)
end

local function runEliminationCleanup(record: Record)
	local ownerId = record.ownerId
	despawnUnitsForOwner(ownerId, record.player)
	neutralizeBuildingsForOwner(ownerId, getRecordKeep(record))
	local ok, err = pcall(function()
		EstateManager.releaseEstatesForOwner(ownerId)
	end)
	if not ok then
		EliminationDebug:warn(`Estate release failed for owner {ownerId}: {err}`)
	end
end

local function eliminate(record: Record, reason: string)
	if record.eliminated or matchEnded then
		return
	end
	record.eliminated = true

	EliminationDebug:warn(`{record.ownerName} ELIMINATED: {reason}`)

	-- Torch the Keep (skip if it's already gone — e.g. KeepDestroyed path)
	local keep = getRecordKeep(record)
	if keep and keep.Parent then
		playKeepDestruction(keep)
	end

	-- Mark the player out of the running. "Eliminated" stops InGame-gated
	-- loops (economy ticks, victory checks) without kicking them from the
	-- server — they can spectate. AI kingdoms have no equivalent flag; their
	-- AIManager state is torn down by the cleanup sweep below instead.
	if record.player then
		local playerData = PlayerManager.get(record.player)
		if playerData then
			playerData.GameState = "Eliminated"
		end
	end

	local gameEvent = getGameEvent()
	if gameEvent then
		if record.player then
			pcall(function()
				gameEvent:FireClient(record.player, "Defeat", {
					lossReason = reason,
					description = LOSS_DESCRIPTIONS[reason] or "Your kingdom has fallen.",
					stats = buildMatchStats(record.player),
				})
			end)
		end
		-- Let every connected human hear the bells toll (including for a
		-- fallen AI kingdom, which has no client of its own to notify).
		for _, other in Players:GetPlayers() do
			if other ~= record.player then
				pcall(function()
					gameEvent:FireClient(other, "PlayerEliminated", {
						playerName = record.ownerName,
						reason = reason,
					})
				end)
			end
		end
	end

	runEliminationCleanup(record)

	checkForWinner()
end

-- ---------------------------------------------------------------------------
-- KEEP CAPTURE SWEEP
-- ---------------------------------------------------------------------------

local function getRecordKeepPosition(record: Record): Vector3?
	local keep = getRecordKeep(record)
	if not keep or not keep.Parent then
		return nil
	end
	if keep:IsA("Model") then
		return keep:GetPivot().Position
	elseif keep:IsA("BasePart") then
		return keep.Position
	end
	return nil
end

-- Count hostile and friendly presence inside the capture radius.
-- Includes RTS combat units AND live Lord characters on both sides.
-- Third return: set of attacking PLAYER userIds (for capture-progress pushes).
local function scanKeepArea(ownerFaction: string, keepPos: Vector3): (number, number, { [number]: boolean })
	local attackers = 0
	local defenders = 0
	local attackerPlayerIds: { [number]: boolean } = {}
	local radiusSq = CONFIG.CAPTURE_RADIUS * CONFIG.CAPTURE_RADIUS

	for model, combatUnit in CombatManager.getActiveCombatUnits() do
		if combatUnit.health <= 0 or not model.Parent then
			continue
		end
		local primary = model.PrimaryPart
		if not primary then
			continue
		end
		local delta = primary.Position - keepPos
		local distSq = delta.X * delta.X + delta.Z * delta.Z
		if distSq > radiusSq then
			continue
		end
		if FactionManager.areEnemies(ownerFaction, combatUnit.faction) then
			attackers += 1
			local unitOwnerId = model:GetAttribute("OwnerId")
			if typeof(unitOwnerId) == "number" then
				attackerPlayerIds[unitOwnerId] = true
			end
		else
			defenders += 1
		end
	end

	-- Lord characters (not registered as combat units while in RTS view)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not root or humanoid.Health <= 0 or not root:IsA("BasePart") then
			continue
		end
		local playerData = PlayerManager.get(player)
		if not playerData or playerData.GameState ~= "InGame" then
			continue
		end
		local delta = root.Position - keepPos
		local distSq = delta.X * delta.X + delta.Z * delta.Z
		if distSq > radiusSq then
			continue
		end
		if FactionManager.areEnemies(ownerFaction, playerData.Faction or "Kingdom") then
			attackers += 1
			attackerPlayerIds[player.UserId] = true
		else
			defenders += 1
		end
	end

	return attackers, defenders, attackerPlayerIds
end

local function sweepCaptures()
	if matchEnded then
		return
	end
	-- Peace time: no captures yet
	if peaceTimeSeconds > 0 and tick() - matchStartTime < peaceTimeSeconds then
		return
	end

	local gameEvent = getGameEvent()

	for _, record in records do
		if not isRecordActive(record) then
			continue
		end
		local player = record.player

		-- Keep destroyed outright ? elimination through the same funnel.
		-- (A record with no Keep at all — e.g. a human who hasn't placed one
		-- yet — has nothing to capture or destroy; skip silently.)
		local keep = getRecordKeep(record)
		if keep ~= nil and not keep.Parent then
			eliminate(record, "KeepDestroyed")
			continue
		end

		local keepPos = getRecordKeepPosition(record)
		if not keepPos then
			continue -- no Keep placed yet; nothing to capture
		end

		local attackers, defenders, attackerPlayerIds = scanKeepArea(getRecordFaction(record), keepPos)

		if attackers > 0 and defenders == 0 then
			record.captureProgress += CONFIG.CHECK_INTERVAL

			local fraction = math.min(record.captureProgress / CONFIG.CAPTURE_SECONDS, 1)
			local secondsRemaining = math.max(0, math.ceil(CONFIG.CAPTURE_SECONDS - record.captureProgress))
			local percent = math.min(math.floor(fraction * 100), 99)

			-- Warn the owner with a chat-style message at 25/50/75% (and first contact)
			local quarter = math.floor(fraction / CONFIG.PROGRESS_NOTIFY_STEP)
			local message: string? = nil
			if quarter > record.lastNotifiedQuarter then
				record.lastNotifiedQuarter = quarter
				message = `Enemies are seizing your Keep! ({percent}%) — defend it!`
			end

			-- HUD countdown banner: every sweep (1 Hz, only while actively contested)
			-- to BOTH sides — the defender (if a real player; AI has no client to
			-- notify) and every attacking player.
			if gameEvent then
				if player then
					pcall(function()
						gameEvent:FireClient(player, "KeepCaptureProgress", {
							percent = percent,
							fraction = fraction,
							secondsRemaining = secondsRemaining,
							keepOwnerName = record.ownerName,
							attacker = false,
							message = message,
						})
					end)
				end
				for attackerUserId in attackerPlayerIds do
					local attackerPlayer = Players:GetPlayerByUserId(attackerUserId)
					if attackerPlayer then
						pcall(function()
							gameEvent:FireClient(attackerPlayer, "KeepCaptureProgress", {
								percent = percent,
								fraction = fraction,
								secondsRemaining = secondsRemaining,
								keepOwnerName = record.ownerName,
								attacker = true,
							})
						end)
					end
				end
			end

			if record.captureProgress >= CONFIG.CAPTURE_SECONDS then
				eliminate(record, "KeepCaptured")
			end
		elseif record.captureProgress > 0 then
			-- Contested or abandoned: progress bleeds away
			record.captureProgress = math.max(
				0,
				record.captureProgress - CONFIG.CHECK_INTERVAL * CONFIG.CAPTURE_DECAY_MULT
			)
			if record.captureProgress == 0 and record.lastNotifiedQuarter > 0 then
				record.lastNotifiedQuarter = 0
				if gameEvent and player then
					pcall(function()
						gameEvent:FireClient(player, "KeepCaptureProgress", {
							percent = 0,
							fraction = 0,
							secondsRemaining = 0,
							attacker = false,
							message = "Your Keep is secure again.",
						})
					end)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- PUBLIC API
-- ---------------------------------------------------------------------------

-- Called once per match start (per player, but mode/peace are match-global).
-- Military modes ("Conquest", "Regicide") enable both elimination paths.
function EliminationManager.setup(victoryMode: string, peaceSeconds: number)
	eliminationEnabled = victoryMode == "Conquest" or victoryMode == "Regicide"
	peaceTimeSeconds = peaceSeconds or 0
	matchStartTime = tick()
	matchEnded = false
	EliminationDebug:info(
		`Elimination setup — mode: {victoryMode}, enabled: {eliminationEnabled}, peace: {peaceTimeSeconds}s`
	)
end

function EliminationManager.registerPlayer(player: Player)
	records[player.UserId] = {
		ownerId = player.UserId,
		ownerName = player.Name,
		isAI = false,
		player = player,
		aiKeep = nil,
		eliminated = false,
		captureProgress = 0,
		lastNotifiedQuarter = 0,
	}
	EliminationDebug:info(`Registered {player.Name} for elimination tracking`)
end

-- Register an AI kingdom (no Player instance — ownerId is AIManager's
-- negative pseudo-UserId, see LobbyManager.addAI). `keep` is the AI's Keep
-- Instance if one was spawned (GameManager's spawnAIInitialSetup return),
-- used for Keep Capture/Keep Destroyed exactly like a human's playerData.Keep.
function EliminationManager.registerAIKingdom(ownerId: number, ownerName: string, keep: Instance?)
	records[ownerId] = {
		ownerId = ownerId,
		ownerName = ownerName,
		isAI = true,
		player = nil,
		aiKeep = keep,
		eliminated = false,
		captureProgress = 0,
		lastNotifiedQuarter = 0,
	}
	EliminationDebug:info(`Registered AI kingdom {ownerName} ({ownerId}) for elimination tracking`)
end

function EliminationManager.isEliminationMode(): boolean
	return eliminationEnabled
end

function EliminationManager.isEliminated(player: Player): boolean
	local record = records[player.UserId]
	return record ~= nil and record.eliminated
end

-- Generalized ownerId variant (works for both real players and AI kingdoms).
function EliminationManager.isEliminatedOwner(ownerId: number): boolean
	local record = records[ownerId]
	return record ~= nil and record.eliminated
end

-- GameManager calls this from the Lord's Humanoid.Died handler.
-- Returns true when the death was consumed as an elimination (skip the 10s
-- respawn); false when the normal respawn flow should proceed (Score mode,
-- unregistered player, or match already over).
function EliminationManager.onLordSlain(player: Player): boolean
	if not eliminationEnabled or matchEnded then
		return false
	end
	local record = records[player.UserId]
	if not record or record.eliminated then
		return false
	end
	eliminate(record, "LordSlain")
	return true
end

-- Remove a single participant's record (they left the match — either
-- disconnected or returned to the menu mid/post-match). Treated as an
-- elimination for last-standing purposes before the record is dropped, same
-- as the existing quitter handling below.
function EliminationManager.cleanupPlayer(ownerId: number)
	local record = records[ownerId]
	if record and not record.eliminated then
		record.eliminated = true
		checkForWinner()
	end
	records[ownerId] = nil
end

-- Full state wipe so a new match can start clean without a server restart.
function EliminationManager.resetMatch()
	records = {}
	eliminationEnabled = false
	matchEnded = false
	matchStartTime = 0
	peaceTimeSeconds = 0
	EliminationDebug:info("EliminationManager match state reset")
end

local loopStarted = false

function EliminationManager.startLoop()
	if loopStarted then
		return
	end
	loopStarted = true
	task.spawn(function()
		while true do
			task.wait(CONFIG.CHECK_INTERVAL)
			if eliminationEnabled then
				local ok, err = pcall(sweepCaptures)
				if not ok then
					EliminationDebug:warn(`Capture sweep failed: {err}`)
				end
			end
		end
	end)
	EliminationDebug:info("EliminationManager capture loop started")
end

function EliminationManager.init()
	Players.PlayerRemoving:Connect(function(player)
		-- A quitter counts as eliminated for last-standing purposes
		EliminationManager.cleanupPlayer(player.UserId)
	end)

	-- AI Direct Slay: AI kingdoms are spawned with a real "King" NPC combat
	-- unit (no Player character), so their Lord's death doesn't go through
	-- GameManager's Humanoid.Died handler like a human's does. Catch it here
	-- via the server-wide kill hook instead.
	CombatManager.onUnitKilled(function(victim)
		if victim.unitType ~= "King" then
			return
		end
		if not eliminationEnabled or matchEnded then
			return
		end
		local record = records[victim.owner]
		if not record or not record.isAI or record.eliminated then
			return
		end
		eliminate(record, "LordSlain")
	end)

	EliminationDebug:info("EliminationManager initialized")
end

return EliminationManager
