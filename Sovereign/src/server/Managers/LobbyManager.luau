--!strict
-- LobbyManager: Handles multiplayer lobby sessions and player synchronization

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
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

-- Available factions
local FACTIONS = { "Kingdom", "Empire", "Tribes", "IronLegion" }

-- Auto-assign the first available spawn to a player
local function autoAssignSpawn(lobby: LobbySession, userId: number, playerName: string)
	for spawnNum = 1, 4 do
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
				selectedMap = "LargeContinent",
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
	LobbyManager.broadcastLobbyState()
end

-- Remove a player from the lobby
function LobbyManager.removePlayer(player: Player)
	local lobby = getOrCreateLobby()

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
function LobbyManager.addAI(requestingPlayer: Player)
	local lobby = getOrCreateLobby()

	-- Count current players (human + AI)
	local totalPlayers = 0
	for _ in pairs(lobby.Players) do
		totalPlayers += 1
	end

	if totalPlayers >= 4 then
		LobbyDebug:warn("Lobby is full, cannot add AI")
		return
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

	if spawnNumber < 1 or spawnNumber > 4 then
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

	-- Need at least 1 human player
	if allReady and humanCount > 0 and not lobby.CountdownActive then
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

			-- Find player's chosen spawn
			for spawnNum, selection in pairs(lobby.SpawnSelections) do
				if selection.userId == lobbyPlayer.UserId then
					playerSettings.quadrant = spawnNum
					break
				end
			end

			-- Send to client - client will fire StartGame back to server
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

	-- Prepare lobby state for transmission (serialize Player instances)
	local serializedPlayers = {}
	for userId, lobbyPlayer in pairs(lobby.Players) do
		serializedPlayers[userId] = {
			UserId = lobbyPlayer.UserId,
			Name = lobbyPlayer.Name,
			IsReady = lobbyPlayer.IsReady,
			SelectedFaction = lobbyPlayer.SelectedFaction,
			SelectedColor = lobbyPlayer.SelectedColor,
			IsAI = lobbyPlayer.IsAI,
		}
	end

	local lobbyState = {
		SessionId = lobby.SessionId,
		Players = serializedPlayers,
		Settings = lobby.Settings,
		SpawnSelections = lobby.SpawnSelections,
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
