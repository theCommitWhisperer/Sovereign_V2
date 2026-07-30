--!strict
-- LobbyManager: Handles multiplayer lobby sessions and player synchronization

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MapData = require(ReplicatedStorage.Shared.GameData.MapData)
local TeamLayoutsData = require(ReplicatedStorage.Shared.GameData.TeamLayoutsData)
local LobbyDebug = DebugManager.createChannel("LobbyManager", false)

local LobbyManager = {}

-- Type definitions
export type LobbyPlayer = {
	Player: Player,
	UserId: number,
	Name: string,
	IsReady: boolean,
	SelectedFaction: string?,
	SelectedColor: { number }?, -- {R, G, B} color chosen by player
	IsAI: boolean,
}

export type LobbySettings = {
	selectedMap: string,
	startingTroops: string,
	startingGold: string,
	startingFood: string,
	startingWeapons: string,
	startingResources: string,
	gameSpeed: string,
	resourceDensity: string,
	victoryCondition: string,
	peaceTime: string,
	wildlifeHostility: string,
	unitMorale: string,
	abilityToTrade: string,
	randomEvents: string,
	legendsMode: string,
	vikingRaids: string,
	honor: string,
	rank: string,
	showTutorial: string,
	customMapId: string?,
	customMapAuthorId: number?,
	-- Team arrangement for the match ("2v2", "1v1v1v1", ...) -- see
	-- TeamLayoutsData. Voted on through the same voteSetting mechanism as
	-- every other lobby setting, not a bespoke remote.
	teamLayout: string,
}

export type SpawnSelection = {
	userId: number,
	name: string,
}

export type LobbySession = {
	SessionId: string,
	Players: { [number]: LobbyPlayer },
	Settings: LobbySettings,
	SettingsVotes: { [string]: { [number]: string } }, -- settingId -> { userId -> value }
	SpawnSelections: { [number]: SpawnSelection }, -- spawn -> { userId, name }
	CountdownActive: boolean,
	CountdownStartTime: number?,
}

-- Global lobby session (single session for all players in the server)
local currentLobby: LobbySession? = nil
local COUNTDOWN_DURATION = 5 -- seconds
local countdownThread: thread? = nil
-- The client receives a start notification for UI navigation, but the server
-- remains the authority for the settings that actually start its match.
local pendingStartSettings: { [number]: any } = {}

-- Available factions
local FACTIONS = { "Kingdom", "Empire", "Tribes", "IronLegion" }

-- Max kingdoms for the lobby's currently selected map (hand-placed keep zones
-- take priority over the declared MaxPlayers; defaults to 4).
local function getLobbyMaxPlayers(lobby: LobbySession): number
	local mapConfig = MapData.getMap(lobby.Settings.selectedMap)
	if mapConfig then
		if mapConfig.KeepSpawnZones and #mapConfig.KeepSpawnZones > 0 then
			return #mapConfig.KeepSpawnZones
		end
		return mapConfig.MaxPlayers or 4
	end
	return 4
end

-- Total players (human + AI) currently seated in the lobby.
local function countLobbyPlayers(lobby: LobbySession): number
	local total = 0
	for _ in pairs(lobby.Players) do
		total += 1
	end
	return total
end

-- Counts humans only. AI seats are filled automatically, so they never gate
-- whether a match can begin.
local function countHumans(lobby: LobbySession): number
	local total = 0
	for _, entry in lobby.Players do
		if not entry.IsAI then
			total += 1
		end
	end
	return total
end

-- Can this lobby start?
--
-- The first version of this required the roster to EXACTLY fill the layout,
-- which made most layouts unstartable in practice: a solo player picking 1v1
-- could not begin without first hand-adding an AI, and the default 1v1v1v1
-- needed four bodies before anything happened at all. Empty seats are filled
-- with AI instead (see fillEmptySeatsWithAI), so the only real requirements are
-- at least one human and no more humans than the layout has seats.
local function lobbyCanStart(lobby: LobbySession): boolean
	local humans = countHumans(lobby)
	return humans > 0 and humans <= TeamLayoutsData.getSlotCount(lobby.Settings.teamLayout)
end

-- Why a lobby cannot start, phrased for the player. nil when it can.
local function startBlocker(lobby: LobbySession): string?
	local humans = countHumans(lobby)
	local slots = TeamLayoutsData.getSlotCount(lobby.Settings.teamLayout)
	if humans == 0 then
		return "Waiting for a player"
	end
	if humans > slots then
		local label = TeamLayoutsData.getOrDefault(lobby.Settings.teamLayout).label
		return ("%s seats %d - %d players in lobby"):format(label, slots, humans)
	end
	return nil
end

-- Faction -> teamIndex for every seated player (human and AI alike), derived
-- from each player's assigned spawn slot and the lobby's chosen layout. This
-- is what FactionManager.applyTeamLayout needs to wire up alliances at match
-- start; built here (not in GameManager) because the lobby session -- the
-- only place SpawnSelections and SelectedFaction both live -- is gone by the
-- time the match starts.
local function buildTeamOf(lobby: LobbySession): { [string]: number }
	local slotByUserId: { [number]: number } = {}
	for spawnNum, selection in pairs(lobby.SpawnSelections) do
		slotByUserId[selection.userId] = spawnNum
	end

	local teamOf: { [string]: number } = {}
	for userId, lobbyPlayer in pairs(lobby.Players) do
		local faction = lobbyPlayer.SelectedFaction
		local slot = slotByUserId[userId]
		if faction and slot then
			local teamIndex = TeamLayoutsData.teamForSlot(lobby.Settings.teamLayout, slot)
			if teamIndex then
				teamOf[faction] = teamIndex
			end
		end
	end
	return teamOf
end

-- Auto-assign the first available spawn to a player
local function autoAssignSpawn(lobby: LobbySession, userId: number, playerName: string)
	for spawnNum = 1, getLobbyMaxPlayers(lobby) do
		if not lobby.SpawnSelections[spawnNum] then
			lobby.SpawnSelections[spawnNum] = {
				userId = userId,
				name = playerName,
			}
			LobbyDebug:info(playerName .. " auto-assigned to spawn " .. spawnNum)
			return
		end
	end
	LobbyDebug:warn("No available spawns for auto-assignment:", playerName)
end

-- Get or create the global lobby session
local function getOrCreateLobby(): LobbySession
	if not currentLobby then
		currentLobby = {
			SessionId = tostring(os.time()),
			Players = {},
			SpawnSelections = {},
		Settings = {
				selectedMap = MapData.DefaultMap,
				startingTroops = "Standard",
				startingGold = "Standard",
				startingFood = "Standard",
				startingWeapons = "Bronze",
				startingResources = "Standard",
				gameSpeed = "Normal",
				resourceDensity = "Standard",
				victoryCondition = "Conquest",
				peaceTime = "10 minutes",
				wildlifeHostility = "Peaceful",
				unitMorale = true,
				abilityToTrade = true,
				randomEvents = true,
				legendsMode = false,
				vikingRaids = false,
				honor = "Standard",
				rank = "Knight",
				showTutorial = true,
				customMapId = nil,
				customMapAuthorId = nil,
				teamLayout = TeamLayoutsData.Default,
			},
			SettingsVotes = {},
			CountdownActive = false,
			CountdownStartTime = nil,
		}
		LobbyDebug:info("Created new lobby session:", currentLobby.SessionId)
	end
	return currentLobby
end

-- Add a player to the lobby
-- Grows the team layout to fit the humans present.
--
-- The lobby opens on 1v1 so the first player sees a startable match rather than
-- a 1v1v1v1 waiting on three strangers. As people arrive it steps up:
-- 1v1 -> 1v1v1 -> 1v1v1v1.
--
-- Only ever GROWS, and only ever between free-for-all layouts. Shrinking would
-- yank the layout out from under the remaining players when someone leaves, and
-- escalating an explicitly-chosen 2v2 into a three-way FFA would silently change
-- the kind of match they picked.
local function escalateLayoutForPlayers(lobby: LobbySession): boolean
	local current = lobby.Settings.teamLayout
	if not TeamLayoutsData.isFreeForAll(current) then
		return false
	end

	local humans = countHumans(lobby)
	if humans <= TeamLayoutsData.getSlotCount(current) then
		return false
	end

	local grown = TeamLayoutsData.smallestFreeForAllFor(humans)
	if not grown or grown == current then
		return false
	end

	-- Never past what the map can seat.
	if TeamLayoutsData.getSlotCount(grown) > getLobbyMaxPlayers(lobby) then
		return false
	end

	lobby.Settings.teamLayout = grown
	LobbyDebug:info(`Grew team layout {current} -> {grown} for {humans} players`)
	return true
end

function LobbyManager.addPlayer(player: Player)
	local lobby = getOrCreateLobby()

	if lobby.Players[player.UserId] then
		LobbyDebug:warn("Player already in lobby:", player.Name)
		return
	end

	local lobbyPlayer: LobbyPlayer = {
		Player = player,
		UserId = player.UserId,
		Name = player.Name,
		IsReady = false,
		SelectedFaction = nil,
		IsAI = false,
	}

	lobby.Players[player.UserId] = lobbyPlayer
	LobbyDebug:info("Player joined lobby:", player.Name)

	-- Auto-assign a spawn zone so the player starts with one selected
	autoAssignSpawn(lobby, player.UserId, player.Name)

	-- Broadcast updated lobby state to all players

	-- A new arrival may need a bigger layout than the duel we opened on.
	escalateLayoutForPlayers(lobby)
	LobbyManager.broadcastLobbyState()
end

-- Remove a player from the lobby
function LobbyManager.removePlayer(player: Player)
	pendingStartSettings[player.UserId] = nil
	local lobby = currentLobby
	if not lobby then
		return
	end

	if not lobby.Players[player.UserId] then
		LobbyDebug:warn("Player not in lobby:", player.Name)
		return
	end

	lobby.Players[player.UserId] = nil

	-- Clear their spawn selection
	for q, selection in pairs(lobby.SpawnSelections) do
		if selection.userId == player.UserId then
			lobby.SpawnSelections[q] = nil
			break
		end
	end

	LobbyDebug:info("Player left lobby:", player.Name)

	-- Cancel countdown if active
	if lobby.CountdownActive then
		LobbyManager.cancelCountdown()
	end

	-- Broadcast updated lobby state to all players
	LobbyManager.broadcastLobbyState()
end

-- Add an AI player to the lobby
-- Seats one AI per empty slot in the chosen layout.
--
-- This is what makes every layout playable on its own: pick 2v2 alone and you
-- get three AI opponents/allies rather than a lobby that refuses to start. Runs
-- at countdown time rather than on layout change so a human joining during the
-- wait takes a real seat instead of displacing a bot that already has one.
local function fillEmptySeatsWithAI(lobby: LobbySession)
	local slots = TeamLayoutsData.getSlotCount(lobby.Settings.teamLayout)
	local guard = 0
	while countLobbyPlayers(lobby) < slots and guard < slots do
		guard += 1
		local index = countLobbyPlayers(lobby) + 1
		local aiId = -1 * index
		if lobby.Players[aiId] then
			-- Id already taken (a hand-added AI); walk past it rather than
			-- overwrite, otherwise the loop cannot terminate.
			aiId -= slots
		end
		lobby.Players[aiId] = {
			Player = nil :: any,
			UserId = aiId,
			Name = "AI_Opponent" .. index,
			IsReady = true,
			SelectedFaction = nil,
			IsAI = true,
		}
		autoAssignSpawn(lobby, aiId, "AI_Opponent" .. index)
		LobbyDebug:info(`Auto-seated AI for empty slot {index}/{slots}`)
	end
end

function LobbyManager.addAI(requestingPlayer: Player)
	local lobby = getOrCreateLobby()

	local totalPlayers = countLobbyPlayers(lobby)

	-- If the layout is already full, GROW it rather than refusing.
	--
	-- The lobby now opens on 1v1, so one human plus one AI fills it immediately
	-- and a second Add AI just warned at the player -- who had asked for a bigger
	-- match and got nothing. Adding an opponent to a full free-for-all steps the
	-- layout up (1v1 -> 1v1v1 -> 1v1v1v1), which is what the click means.
	--
	-- Explicitly-chosen team layouts are NOT grown: turning someone's 2v2 into a
	-- 2v1v1 because they clicked Add AI would silently change the match they
	-- picked. Those refuse, as does a free-for-all that has hit the map's spawns.
	if totalPlayers >= TeamLayoutsData.getSlotCount(lobby.Settings.teamLayout) then
		local grown = TeamLayoutsData.smallestFreeForAllFor(totalPlayers + 1)
		local fitsMap = grown ~= nil and TeamLayoutsData.getSlotCount(grown) <= getLobbyMaxPlayers(lobby)

		if TeamLayoutsData.isFreeForAll(lobby.Settings.teamLayout) and grown and fitsMap then
			LobbyDebug:info(`Add AI grew layout {lobby.Settings.teamLayout} -> {grown}`)
			lobby.Settings.teamLayout = grown
		else
			LobbyDebug:warn("Lobby is full and the layout cannot grow further; cannot add AI")
			return
		end
	end

	-- Create unique AI ID
	local aiId = -1 * (totalPlayers + 1) -- Negative IDs for AI
	local aiName = "AI_Opponent" .. (totalPlayers)

	local aiPlayer: LobbyPlayer = {
		Player = nil :: any, -- AI doesn't have a Player instance
		UserId = aiId,
		Name = aiName,
		IsReady = true, -- AI is always ready
		SelectedFaction = nil,
		IsAI = true,
	}

	lobby.Players[aiId] = aiPlayer
	LobbyDebug:info("AI player added:", aiName)

	-- Auto-assign a spawn zone for the AI
	autoAssignSpawn(lobby, aiId, aiName)

	-- Broadcast updated lobby state
	LobbyManager.broadcastLobbyState()
end

-- Remove an AI or human player (requested by a player)
function LobbyManager.removePlayerOrAI(requestingPlayer: Player, targetUserId: number)
	local lobby = getOrCreateLobby()

	if not lobby.Players[targetUserId] then
		LobbyDebug:warn("Target player not in lobby:", targetUserId)
		return
	end

	local targetPlayer = lobby.Players[targetUserId]

	-- Don't allow removing other human players, only AI or self
	if not targetPlayer.IsAI and targetPlayer.UserId ~= requestingPlayer.UserId then
		LobbyDebug:warn("Cannot remove other human players")
		return
	end

	lobby.Players[targetUserId] = nil

	-- Clear their spawn selection
	for q, selection in pairs(lobby.SpawnSelections) do
		if selection.userId == targetUserId then
			lobby.SpawnSelections[q] = nil
			break
		end
	end

	LobbyDebug:info("Removed player:", targetPlayer.Name)

	-- Cancel countdown if active
	if lobby.CountdownActive then
		LobbyManager.cancelCountdown()
	end

	-- Broadcast updated lobby state
	LobbyManager.broadcastLobbyState()
end

-- Vote on a setting value
function LobbyManager.voteSetting(player: Player, settingId: string, value: any)
	local lobby = getOrCreateLobby()

	if settingId == "selectedMap" then
		if typeof(value) ~= "string" or (value ~= "__custom__" and not MapData.getMap(value)) then
			LobbyDebug:warn("Rejected invalid map vote", { player = player.Name, value = value })
			return
		end
	end

	if settingId == "teamLayout" then
		local playable = TeamLayoutsData.getPlayableOn(getLobbyMaxPlayers(lobby))
		if typeof(value) ~= "string" or not table.find(playable, value) then
			LobbyDebug:warn("Rejected team layout vote not playable on this map", { player = player.Name, value = value })
			return
		end
	end

	if not lobby.SettingsVotes[settingId] then
		lobby.SettingsVotes[settingId] = {}
	end

	lobby.SettingsVotes[settingId][player.UserId] = value
	LobbyDebug:info(player.Name .. " voted for " .. settingId, { value = value })

	-- Calculate the most popular vote for this setting
	local voteCounts: { [string]: number } = {}
	for _, votedValue in pairs(lobby.SettingsVotes[settingId]) do
		voteCounts[votedValue] = (voteCounts[votedValue] or 0) + 1
	end

	-- Find the value with the most votes
	local maxVotes = 0
	local winningValue = value
	for votedValue, count in pairs(voteCounts) do
		if count > maxVotes then
			maxVotes = count
			winningValue = votedValue
		end
	end

	-- Update the setting to the winning value
	lobby.Settings[settingId] = winningValue

	-- A map change can shrink the available spawns out from under the
	-- currently selected layout (a 2v2 needs 4, the new map only has 2) --
	-- fall back to the default rather than leave an unplayable layout selected.
	if settingId == "selectedMap" then
		local stillPlayable = table.find(TeamLayoutsData.getPlayableOn(getLobbyMaxPlayers(lobby)), lobby.Settings.teamLayout)
		if not stillPlayable then
			LobbyDebug:info("Team layout no longer playable after map change; reverting to default", {
				from = lobby.Settings.teamLayout,
				to = TeamLayoutsData.Default,
			})
			lobby.Settings.teamLayout = TeamLayoutsData.Default
		end
	end

	-- Broadcast updated lobby state
	LobbyManager.broadcastLobbyState()
end

-- Select a faction for a player (or AI)
function LobbyManager.selectFaction(player: Player, faction: string, targetUserId: number?)
	local lobby = getOrCreateLobby()

	-- Default to the requesting player if no target specified
	local userId = targetUserId or player.UserId

	if not lobby.Players[userId] then
		LobbyDebug:warn("Target player not in lobby", { userId = userId })
		return
	end

	-- Validate faction
	local isValidFaction = false
	for _, validFaction in ipairs(FACTIONS) do
		if validFaction == faction then
			isValidFaction = true
			break
		end
	end

	if not isValidFaction then
		LobbyDebug:warn("Invalid faction", { faction = faction })
		return
	end

	-- Check if faction is already taken (no duplicates)
	for existingUserId, lobbyPlayer in pairs(lobby.Players) do
		if existingUserId ~= userId and lobbyPlayer.SelectedFaction == faction then
			LobbyDebug:warn("Faction already taken", { faction = faction })
			-- Send error to client
			local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
			local LobbyEvent = RemoteEvents:FindFirstChild("LobbyEvent")
			if LobbyEvent then
				LobbyEvent:FireClient(player, "FactionTaken", faction)
			end
			return
		end
	end

	lobby.Players[userId].SelectedFaction = faction
	LobbyDebug:info("Faction selected for player", { playerName = lobby.Players[userId].Name, faction = faction })

	-- Broadcast updated lobby state
	LobbyManager.broadcastLobbyState()
end

-- Select a spawn location for a player
function LobbyManager.selectSpawn(player: Player, spawnNumber: number)
	local lobby = getOrCreateLobby()

	if not lobby.Players[player.UserId] then
		LobbyDebug:warn("Player not in lobby:", player.Name)
		return
	end

	if spawnNumber < 1 or spawnNumber > getLobbyMaxPlayers(lobby) then
		LobbyDebug:warn("Invalid spawn number:", spawnNumber)
		return
	end

	local existing = lobby.SpawnSelections[spawnNumber]
	if existing and existing.userId ~= player.UserId then
		LobbyDebug:warn("Spawn already claimed by", existing.name)
		return
	end

	for s, selection in pairs(lobby.SpawnSelections) do
		if selection.userId == player.UserId then
			lobby.SpawnSelections[s] = nil
			break
		end
	end

	lobby.SpawnSelections[spawnNumber] = {
		userId = player.UserId,
		name = player.Name,
	}

	LobbyDebug:info(player.Name .. " selected spawn " .. spawnNumber)
	LobbyManager.broadcastLobbyState()
end

-- Select a color for a player
function LobbyManager.selectColor(player: Player, color: { number })
	local lobby = getOrCreateLobby()

	if not lobby.Players[player.UserId] then
		LobbyDebug:warn("Player not in lobby:", player.Name)
		return
	end

	if type(color) ~= "table" or #color ~= 3 then
		LobbyDebug:warn("Invalid color format from", player.Name)
		return
	end

	for i = 1, 3 do
		if type(color[i]) ~= "number" or color[i] < 0 or color[i] > 255 then
			LobbyDebug:warn("Invalid color value from", player.Name)
			return
		end
	end

	-- Check if color is already taken by someone else
	for userId, lobbyPlayer in pairs(lobby.Players) do
		if userId ~= player.UserId and lobbyPlayer.SelectedColor then
			local sc = lobbyPlayer.SelectedColor
			if sc[1] == color[1] and sc[2] == color[2] and sc[3] == color[3] then
				LobbyDebug:warn("Color already taken by", lobbyPlayer.Name)
				return
			end
		end
	end

	lobby.Players[player.UserId].SelectedColor = color
	LobbyDebug:info(player.Name .. " selected color", color)
	LobbyManager.broadcastLobbyState()
end

-- Toggle ready status
function LobbyManager.toggleReady(player: Player)
	local lobby = getOrCreateLobby()

	if not lobby.Players[player.UserId] then
		LobbyDebug:warn("Player not in lobby:", player.Name)
		return
	end

	local lobbyPlayer = lobby.Players[player.UserId]
	lobbyPlayer.IsReady = not lobbyPlayer.IsReady
	LobbyDebug:info(player.Name .. " ready status:", lobbyPlayer.IsReady)

	-- Check if all players are ready
	local allReady = true
	local humanCount = 0
	for _, p in pairs(lobby.Players) do
		if not p.IsAI then
			humanCount += 1
		end
		if not p.IsReady then
			allReady = false
		end
	end

	-- Need at least 1 human player, and the roster has to exactly fill the
	-- chosen layout's teams -- a 2v2 with 3 players has no valid split.
	if allReady and humanCount > 0 and not lobby.CountdownActive and lobbyCanStart(lobby) then
		LobbyManager.startCountdown()
	elseif not allReady and lobby.CountdownActive then
		LobbyManager.cancelCountdown()
	end

	-- Broadcast updated lobby state
	LobbyManager.broadcastLobbyState()
end

-- Start the countdown
function LobbyManager.startCountdown()
	local lobby = getOrCreateLobby()

	-- Defense in depth: toggleReady is the normal gate, but a roster change
	-- between that check and this call (e.g. an AI added mid-toggle) must not
	-- be allowed to start a countdown for a layout that no longer fits.
	local blocker = startBlocker(lobby)
	if blocker then
		LobbyDebug:warn(`Cannot start countdown: {blocker}`)
		return
	end

	-- Any seat still empty becomes an AI, so the layout is always full by the
	-- time the match builds its team map.
	fillEmptySeatsWithAI(lobby)

	lobby.CountdownActive = true
	lobby.CountdownStartTime = tick()

	LobbyDebug:info("Starting countdown:", COUNTDOWN_DURATION, "seconds")

	-- Broadcast countdown start
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local LobbyEvent = RemoteEvents:FindFirstChild("LobbyEvent")
	if LobbyEvent then
		for _, lobbyPlayer in pairs(lobby.Players) do
			if not lobbyPlayer.IsAI and lobbyPlayer.Player then
				LobbyEvent:FireClient(lobbyPlayer.Player, "CountdownStarted", COUNTDOWN_DURATION)
			end
		end
	end

	-- Start countdown thread
	if countdownThread then
		task.cancel(countdownThread)
	end

	countdownThread = task.spawn(function()
		task.wait(COUNTDOWN_DURATION)

		-- Verify countdown wasn't cancelled
		if lobby.CountdownActive then
			LobbyManager.startGame()
		end
	end)
end

-- Cancel the countdown
function LobbyManager.cancelCountdown()
	local lobby = getOrCreateLobby()

	if not lobby.CountdownActive then
		return
	end

	lobby.CountdownActive = false
	lobby.CountdownStartTime = nil

	LobbyDebug:info("Countdown cancelled")

	-- Cancel countdown thread
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end

	-- Broadcast countdown cancelled
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local LobbyEvent = RemoteEvents:FindFirstChild("LobbyEvent")
	if LobbyEvent then
		for _, lobbyPlayer in pairs(lobby.Players) do
			if not lobbyPlayer.IsAI and lobbyPlayer.Player then
				LobbyEvent:FireClient(lobbyPlayer.Player, "CountdownCancelled")
			end
		end
	end
end

-- Start the game
function LobbyManager.startGame()
	local lobby = getOrCreateLobby()

	-- Same defense-in-depth as startCountdown: the countdown thread wakes up
	-- COUNTDOWN_DURATION seconds after being scheduled, and the roster can
	-- have changed underneath it since. Refuse rather than start a match that
	-- can't seat everyone into the chosen layout.
	if not lobbyCanStart(lobby) then
		LobbyDebug:warn(`Cannot start game: {startBlocker(lobby) or "unknown"}`)

		-- Reset the countdown state directly instead of calling
		-- cancelCountdown(): this guard runs INSIDE the countdown's own thread
		-- (the task.spawn body in startCountdown), and task.cancel on the
		-- currently running thread halts execution at that exact call --
		-- everything after it, including the broadcasts below, would never run.
		lobby.CountdownActive = false
		lobby.CountdownStartTime = nil
		countdownThread = nil

		local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
		local LobbyEvent = RemoteEvents:FindFirstChild("LobbyEvent")
		if LobbyEvent then
			for _, lobbyPlayer in pairs(lobby.Players) do
				if not lobbyPlayer.IsAI and lobbyPlayer.Player then
					LobbyEvent:FireClient(lobbyPlayer.Player, "CountdownCancelled")
				end
			end
		end

		LobbyManager.broadcastLobbyState()
		return
	end

	LobbyDebug:info("Starting game with settings:", lobby.Settings)

	-- Auto-assign factions to players who haven't chosen
	local assignedFactions = {}
	for _, lobbyPlayer in pairs(lobby.Players) do
		if lobbyPlayer.SelectedFaction then
			assignedFactions[lobbyPlayer.SelectedFaction] = true
		end
	end

	local availableFactions = {}
	for _, faction in ipairs(FACTIONS) do
		if not assignedFactions[faction] then
			table.insert(availableFactions, faction)
		end
	end

	for userId, lobbyPlayer in pairs(lobby.Players) do
		if not lobbyPlayer.SelectedFaction and #availableFactions > 0 then
			local faction = table.remove(availableFactions, 1)
			lobbyPlayer.SelectedFaction = faction
			LobbyDebug:info("Auto-assigned faction to " .. lobbyPlayer.Name .. ":", faction)
		end
	end

	-- Faction -> teamIndex for every seated player, human and AI alike. Built
	-- here (not in GameManager) because SpawnSelections and SelectedFaction
	-- both live only in this lobby session, which is cleared below.
	local teamOf = buildTeamOf(lobby)

	-- Notify clients and start game for all players
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local LobbyEvent = RemoteEvents:WaitForChild("LobbyEvent")

	-- Store lobby data before clearing it
	local lobbyData = {
		Settings = lobby.Settings,
		Players = lobby.Players,
	}

	-- Extract and store AI players for spawning
	local aiPlayers = {}
	for _, lobbyPlayer in pairs(lobby.Players) do
		if lobbyPlayer.IsAI then
			table.insert(aiPlayers, {
				UserId = lobbyPlayer.UserId,
				Name = lobbyPlayer.Name,
				Faction = lobbyPlayer.SelectedFaction,
			})
		end
	end
	LobbyManager.storeAIPlayers(aiPlayers)
	LobbyDebug:info("Stored AI players for game:", #aiPlayers)

	-- Notify all human players to start the game
	for _, lobbyPlayer in pairs(lobby.Players) do
		if not lobbyPlayer.IsAI and lobbyPlayer.Player then
			-- Prepare settings with faction and spawn for this player
			local playerSettings = table.clone(lobby.Settings)
			playerSettings.faction = lobbyPlayer.SelectedFaction
			playerSettings.playerColor = lobbyPlayer.SelectedColor
			playerSettings.map = lobby.Settings.selectedMap
			playerSettings.allPlayers = lobbyData.Players -- Send all players including AI
			playerSettings.isMultiplayer = true -- Flag to indicate this is a multiplayer game
			playerSettings.teamOf = teamOf -- faction -> teamIndex, for FactionManager.applyTeamLayout

			-- Find player's chosen spawn
			for spawnNum, selection in pairs(lobby.SpawnSelections) do
				if selection.userId == lobbyPlayer.UserId then
					playerSettings.quadrant = spawnNum
					break
				end
			end

			pendingStartSettings[lobbyPlayer.UserId] = playerSettings

			-- The client still sends StartGame to acknowledge the transition, but
			-- GameManager consumes the server-created settings above instead of
			-- trusting that RemoteEvent payload.
			LobbyEvent:FireClient(lobbyPlayer.Player, "LobbyGameStart", playerSettings)
		end
	end

	-- Clear the lobby
	currentLobby = nil
	LobbyDebug:info("Game started, lobby cleared")
end

-- Broadcast current lobby state to all players
function LobbyManager.broadcastLobbyState()
	local lobby = getOrCreateLobby()

	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local LobbyEvent = RemoteEvents:FindFirstChild("LobbyEvent")

	if not LobbyEvent then
		LobbyDebug:warn("LobbyEvent not found, creating it")
		LobbyEvent = Instance.new("RemoteEvent")
		LobbyEvent.Name = "LobbyEvent"
		LobbyEvent.Parent = RemoteEvents
	end

	-- Slot each player belongs to, so their team can be derived below. Built
	-- once here rather than per-player -- SpawnSelections is keyed by slot,
	-- not by user.
	local slotByUserId: { [number]: number } = {}
	for spawnNum, selection in pairs(lobby.SpawnSelections) do
		slotByUserId[selection.userId] = spawnNum
	end

	-- Prepare lobby state for transmission (serialize Player instances)
	local serializedPlayers = {}
	for userId, lobbyPlayer in pairs(lobby.Players) do
		local slot = slotByUserId[userId]
		serializedPlayers[userId] = {
			UserId = lobbyPlayer.UserId,
			Name = lobbyPlayer.Name,
			IsReady = lobbyPlayer.IsReady,
			SelectedFaction = lobbyPlayer.SelectedFaction,
			SelectedColor = lobbyPlayer.SelectedColor,
			IsAI = lobbyPlayer.IsAI,
			TeamIndex = slot and TeamLayoutsData.teamForSlot(lobby.Settings.teamLayout, slot),
		}
	end

	local lobbyState = {
		SessionId = lobby.SessionId,
		Players = serializedPlayers,
		Settings = lobby.Settings,
		SpawnSelections = lobby.SpawnSelections,
		-- The client used to re-derive this from Settings.selectedMap by
		-- duplicating this exact function's logic (see the removed
		-- computeMaxPlayers in Lobby.luau) -- broadcast the real number
		-- instead so that copy can't drift from this one.
		MaxPlayers = getLobbyMaxPlayers(lobby),
		-- Why the lobby cannot start, or nil. Sent so the roster can state the
		-- real reason instead of the client re-deriving a rule the server owns.
		StartBlocker = startBlocker(lobby),
		CountdownActive = lobby.CountdownActive,
		CountdownTimeRemaining = if lobby.CountdownActive and lobby.CountdownStartTime
			then math.max(0, COUNTDOWN_DURATION - (tick() - lobby.CountdownStartTime))
			else 0,
	}

	-- Send to all players in lobby
	for _, lobbyPlayer in pairs(lobby.Players) do
		if not lobbyPlayer.IsAI and lobbyPlayer.Player then
			LobbyEvent:FireClient(lobbyPlayer.Player, "LobbyStateUpdate", lobbyState)
		end
	end
end

-- Get current lobby state (for initial sync)
function LobbyManager.getLobbyState(): LobbySession?
	return currentLobby
end

function LobbyManager.isPlayerInLobby(player: Player): boolean
	return currentLobby ~= nil and currentLobby.Players[player.UserId] ~= nil
end

-- Returns one server-authored settings payload for a player starting from the
-- lobby. The payload is deliberately consumed so it cannot start a second
-- match or be reused after a player has left.
function LobbyManager.consumePendingStartSettings(player: Player): any?
	local settings = pendingStartSettings[player.UserId]
	pendingStartSettings[player.UserId] = nil
	return settings
end

-- Store AI players from last game start (for spawning)
local lastGameAIPlayers = nil

function LobbyManager.storeAIPlayers(aiPlayers)
	lastGameAIPlayers = aiPlayers
end

function LobbyManager.getAIPlayersForGame()
	return lastGameAIPlayers
end

function LobbyManager.clearAIPlayers()
	lastGameAIPlayers = nil
end

return LobbyManager
