--!strict
-- ArenaMode: The "Battle Arena" lobby game mode — public combat testing.
--
-- When a lobby starts with selectedMap == "BattleArena", GameManager hands the
-- player to ArenaMode.startForPlayer instead of running the normal game setup
-- (no terrain, no Keep, no economy). Players get the Battle Setup UI panel and
-- spawn armies via remote actions, validated and capped here.
--
-- Remote actions (GameEvent):
--   "ArenaSpawnArmies" { mine = {{unitType, count}...}, enemy = {...}, enemyFaction? }
--   "ArenaClear"
--   "ArenaSetCap"     number (clamped; any arena player may adjust)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local CombatSandbox = require(script.Parent.CombatSandbox)

local Managers = script.Parent.Parent.Managers
local NotificationManager = require(Managers.NotificationManager)

local Systems = script.Parent.Parent.Systems
local MovementSystem = require(Systems.MovementSystem)

-- Lazy to avoid cycles (CombatManager facade requires the Combat folder)
local CombatManager = nil :: any

local ArenaDebug = DebugManager.createChannel("ArenaMode", true)

local ArenaMode = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIG / STATE
-- ═══════════════════════════════════════════════════════════════════════════

local DEFAULT_CAP = 100
local HARD_CAP = 200 -- absolute per-side limit regardless of setting
local MIN_CAP = 10
local VALID_ENEMY_FACTIONS = { Viking = true, Empire = true, Tribes = true, IronLegion = true, Rebel = true }

local arenaPlayers: { [number]: boolean } = {}
local maxPerSide = DEFAULT_CAP
local loopsStarted = false
local listenerConnected = false

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

export type ClientArmyEntry = { unitType: string, count: number }

-- Validate + sanitize a client-sent army list into a CombatSandbox.ArmySpec.
-- Returns (spec, total) or (nil, errorMessage).
local function sanitizeArmy(raw: any): (CombatSandbox.ArmySpec?, number | string)
	if typeof(raw) ~= "table" then
		return nil, "Army must be a table"
	end
	local spec: CombatSandbox.ArmySpec = {}
	local total = 0
	for _, entry in raw :: { any } do
		if typeof(entry) ~= "table" then
			return nil, "Bad army entry"
		end
		local unitType = entry.unitType
		local count = entry.count
		if typeof(unitType) ~= "string" or typeof(count) ~= "number" then
			return nil, "Bad army entry fields"
		end
		count = math.floor(count)
		if count <= 0 then
			continue
		end
		local unitData = (GameData.Units :: { [string]: any })[unitType]
		if not unitData then
			return nil, `Unknown unit: {unitType}`
		end
		if not unitData.combat then
			return nil, `{unitType} has no combat stats`
		end
		total += count
		if total > maxPerSide then
			return nil, `Army exceeds the {maxPerSide}/side cap`
		end
		table.insert(spec, { count = count, unitType = unitType })
	end
	if total == 0 then
		return nil, "Army is empty"
	end
	return spec, total
end

local function ensureLoopsStarted()
	if loopsStarted then
		return
	end
	loopsStarted = true
	if not CombatManager then
		CombatManager = require(Managers.CombatManager) :: any
	end
	-- Both are safe if GameManager starts them again later for a normal game:
	-- CombatService.startLoop is guarded internally, MovementSystem.startLoop
	-- is guarded via its loopStarted flag.
	MovementSystem.startLoop()
	CombatManager.startLoop()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MODE ENTRY (called by GameManager's StartGame handler)
-- ═══════════════════════════════════════════════════════════════════════════

-- playerData is GameManager's PlayerManager record; settings is the lobby table.
function ArenaMode.startForPlayer(player: Player, playerData: any, settings: any)
	arenaPlayers[player.UserId] = true

	local faction = (typeof(settings) == "table" and settings.faction) or "Kingdom"
	playerData.Faction = faction
	playerData.GameState = "InGame"

	ensureLoopsStarted()

	-- Build the arena and bring the player's character there
	CombatSandbox.setupArena(player)

	-- Fire GameStarted so the client routes to HUD + shows the Battle Setup panel
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local gameEvent = remoteEvents:WaitForChild("GameEvent") :: RemoteEvent
	gameEvent:FireClient(player, "GameStarted", {
		mode = "BattleArena",
		faction = faction,
		resources = playerData.Resources or {},
		showTutorial = false,
		spawnZone = 0,
		peaceTimeSeconds = 0,
		victoryCondition = "None",
		armyCap = maxPerSide,
	})

	NotificationManager.info(
		player,
		"Battle Arena",
		"Open the Battle Setup panel to build two armies, then hit FIGHT. No economy here — just combat."
	)

	ArenaDebug:info("Player entered Battle Arena", { player = player.Name, faction = faction })
end

function ArenaMode.isArenaPlayer(player: Player): boolean
	return arenaPlayers[player.UserId] == true
end

function ArenaMode.playerRemoving(player: Player)
	arenaPlayers[player.UserId] = nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- REMOTE HANDLING
-- ═══════════════════════════════════════════════════════════════════════════

local function handleSpawnArmies(player: Player, data: any)
	if typeof(data) ~= "table" then
		return
	end

	local mine, mineResult = sanitizeArmy(data.mine)
	if not mine then
		NotificationManager.warning(player, "Battle Setup", tostring(mineResult))
		return
	end
	local enemy, enemyResult = sanitizeArmy(data.enemy)
	if not enemy then
		NotificationManager.warning(player, "Battle Setup", tostring(enemyResult))
		return
	end

	local enemyFaction: string? = nil
	if typeof(data.enemyFaction) == "string" and VALID_ENEMY_FACTIONS[data.enemyFaction] then
		enemyFaction = data.enemyFaction
	end

	local err = CombatSandbox.startBattleWithArmies(
		player,
		mine :: CombatSandbox.ArmySpec,
		enemy :: CombatSandbox.ArmySpec,
		enemyFaction
	)
	if err then
		NotificationManager.warning(player, "Battle Setup", err)
	else
		NotificationManager.success(
			player,
			"Battle Started",
			`{mineResult} vs {enemyResult} — fight!`
		)
	end
end

local function handleSetCap(player: Player, data: any)
	if typeof(data) ~= "number" then
		return
	end
	maxPerSide = math.clamp(math.floor(data), MIN_CAP, HARD_CAP)
	ArenaDebug:info("Army cap changed", { by = player.Name, cap = maxPerSide })
	NotificationManager.info(player, "Battle Setup", `Army cap set to {maxPerSide} per side`)
end

function ArenaMode.init()
	if listenerConnected then
		return
	end
	listenerConnected = true

	task.spawn(function()
		local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
		local gameEvent = remoteEvents:WaitForChild("GameEvent") :: RemoteEvent

		gameEvent.OnServerEvent:Connect(function(player, action, data)
			-- Arena actions only work for players who entered via the Battle
			-- Arena mode; everyone in that lobby did.
			if not ArenaMode.isArenaPlayer(player) then
				return
			end

			if action == "ArenaSpawnArmies" then
				handleSpawnArmies(player, data)
			elseif action == "ArenaClear" then
				CombatSandbox.killAll()
				NotificationManager.info(player, "Battle Setup", "Arena cleared")
			elseif action == "ArenaSetCap" then
				handleSetCap(player, data)
			end
		end)
	end)

	game:GetService("Players").PlayerRemoving:Connect(ArenaMode.playerRemoving)

	ArenaDebug:info("ArenaMode initialized")
end

return ArenaMode
