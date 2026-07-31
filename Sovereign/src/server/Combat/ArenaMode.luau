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
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
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

-- Arena-specific hero overrides. Everything about how the hero FIGHTS (combo
-- timings, arcs, block, parry, dodge, bow) now comes from CombatConfig.Hero via
-- HeroCombat, so the arena and the normal game run one implementation instead of
-- two that drift. What stays here is arena-only: the fighter's stat line and the
-- respawn delay.
--
-- The old per-action tuning (meleeRange/meleeArcCos/meleeCooldown/...) is gone
-- deliberately — it duplicated GameManager's LORD_FIGHTER table verbatim, and the
-- two had already been edited independently.
local HERO = {
	baseType = CombatConfig.Hero.fighter.baseType, -- seeds the damage-type profile only
	maxHealth = CombatConfig.Hero.fighter.maxHealth, -- buffed vs a rank-and-file soldier
	attackDamage = CombatConfig.Hero.fighter.attackDamage,
	armor = CombatConfig.Hero.fighter.armor,
	respawnDelay = 3,
}

-- Per-player arena state and connections.
--
-- The old lastMelee/lastRanged cooldown tables are gone: cooldowns are now
-- enforced inside HeroCombat's state machine (which also enforces the combo
-- lockout, dodge cooldown and bow cooldown), so keeping a second, weaker copy
-- here would have meant two sources of truth and two tables to leak.
local arenaState: { [number]: { spawnCFrame: CFrame, faction: string } } = {}
local characterConns: { [number]: RBXScriptConnection } = {}

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
-- PLAYER HERO FIGHTER (first-person combat)
-- ═══════════════════════════════════════════════════════════════════════════

-- Drop the character onto solid ground at `xz` by raycasting down; returns a CFrame
-- whose position sits just above whatever floor is found (falls back to the arena
-- floor height if nothing solid is hit), preserving the given look rotation.
local function groundedSpawnCFrame(baseCFrame: CFrame): CFrame
	local xz = baseCFrame.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local arena = workspace:FindFirstChild("CombatArena")
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Units") } :: { Instance }
	local hit = workspace:Raycast(xz + Vector3.new(0, 200, 0), Vector3.new(0, -600, 0), params)
	local groundY = hit and hit.Position.Y or (xz.Y)
	local _ = arena
	return baseCFrame.Rotation + Vector3.new(xz.X, groundY + 4, xz.Z)
end

-- Runs on every (re)spawn of an arena player's character: place it on the arena
-- floor, join the Units collision group (so marching armies aren't blocked),
-- register it as a first-person hero combatant, and schedule a respawn on death.
local function onArenaCharacter(player: Player, character: Model)
	local st = arenaState[player.UserId]
	if not st then
		return
	end
	local hrp = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hrp then
		return
	end
	character.PrimaryPart = hrp
	-- Position on solid ground at the spawn point (raycast avoids falling through).
	character:PivotTo(groundedSpawnCFrame(st.spawnCFrame))

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Units"
		end
	end

	if not CombatManager then
		CombatManager = require(Managers.CombatManager) :: any
	end
	CombatManager.registerPlayerFighter(character, st.faction, player.UserId, {
		baseType = HERO.baseType,
		maxHealth = HERO.maxHealth,
		attackDamage = HERO.attackDamage,
		armor = HERO.armor,
	})
	-- Same hero state machine the normal game's Lord uses. Registering it here
	-- (rather than on a camera-mode toggle, as GameManager does) is the arena's
	-- one difference: the arena hero is a fighter from the moment he spawns.
	CombatManager.registerHero(player, character, { maxHealth = HERO.maxHealth })
	character:SetAttribute("CanFirstPerson", true) -- lets the client enter hero mode

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			-- Tear the hero action state down with the fighter, or the respawned
			-- character inherits the corpse's combo index and cooldowns.
			CombatManager.unregisterHero(player)
			CombatManager.unregisterPlayerFighter(character)
			task.delay(HERO.respawnDelay, function()
				if player.Parent and arenaState[player.UserId] then
					player:LoadCharacter()
				end
			end)
		end)
	end

	ArenaDebug:info("Hero fighter equipped", { player = player.Name, faction = st.faction })
end

-- Forward a hero action into the shared HeroCombat state machine. This layer does
-- shape validation only — legality, cooldowns, combo state, damage and i-frames
-- all live in HeroCombat, exactly as they do for the normal game's Lord.
--
-- Actions: "HeroLight" | "HeroHeavy" | "HeroRanged" | "HeroBlock" | "HeroDodge",
-- plus the legacy aliases "PlayerMeleeAttack" -> HeroLight and
-- "PlayerRangedAttack" -> HeroRanged.
local function handleHeroAction(player: Player, action: string, data: any)
	if not player.Character or not arenaState[player.UserId] then
		return
	end
	if not CombatManager then
		CombatManager = require(Managers.CombatManager) :: any
	end

	if action == "HeroBlock" then
		local blocking = typeof(data) == "table" and data.blocking or nil
		if typeof(blocking) ~= "boolean" then
			return
		end
		local aim = (typeof(data) == "table" and typeof(data.aim) == "Vector3") and data.aim or nil
		CombatManager.heroBlock(player, blocking, aim)
		return
	end

	if action == "HeroDodge" then
		-- nil direction is legal and means "roll backwards".
		local direction = typeof(data) == "table" and data.direction or nil
		CombatManager.heroDodge(player, direction)
		return
	end

	local aim = (typeof(data) == "table" and typeof(data.aim) == "Vector3") and data.aim or nil
	if not aim then
		return
	end
	if action == "HeroLight" then
		CombatManager.heroLight(player, aim)
	elseif action == "HeroHeavy" then
		CombatManager.heroHeavy(player, aim)
	elseif action == "HeroRanged" then
		CombatManager.heroRanged(player, aim)
	end
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

	-- Build the arena
	local arenaCenter = CombatSandbox.setupArena(player)

	-- The client camera initializes at the character's position when GameStarted
	-- arrives. Players.CharacterAutoLoads is FALSE in this game — the normal
	-- StartGame path calls player:LoadCharacter(), and the arena branch skips
	-- that path, so we must spawn the character ourselves or the camera waits
	-- forever and the player stares at open water.
	local viewPos = arenaCenter + Vector3.new(0, 6, 150)
	local spawnCFrame = CFrame.lookAt(viewPos, arenaCenter + Vector3.new(0, 3, 0))
	playerData.SpawnPoint = spawnCFrame -- respawns also come back to the arena

	-- Remember what this player needs on every (re)spawn.
	arenaState[player.UserId] = { spawnCFrame = spawnCFrame, faction = faction }

	-- Equip the hero fighter on each (re)spawn (initial load + respawns after death).
	if characterConns[player.UserId] then
		characterConns[player.UserId]:Disconnect()
	end
	characterConns[player.UserId] = player.CharacterAdded:Connect(function(character)
		task.spawn(onArenaCharacter, player, character)
	end)

	task.spawn(function()
		player:LoadCharacter()
		local character = player.Character or player.CharacterAdded:Wait()
		-- onArenaCharacter (fired by CharacterAdded) positions + registers the fighter;
		-- wait for the character to exist, then give replication a beat so the client
		-- camera reads the placed position.
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.3)

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
			zoneCenter = arenaCenter,
			zoneRadius = 200,
			-- The minimap reads its world extent from here rather than a
			-- hardcoded constant. The arena is 400 studs, not 1000.
			mapConfig = {
				Name = "Battle Arena",
				Size = 400,
			},
		})

		NotificationManager.info(
			player,
			"Battle Arena",
			"Open the Battle Setup panel to build two armies, then hit FIGHT. No economy here — just combat."
		)
	end)

	ArenaDebug:info("Player entered Battle Arena", { player = player.Name, faction = faction })
end

function ArenaMode.isArenaPlayer(player: Player): boolean
	return arenaPlayers[player.UserId] == true
end

function ArenaMode.playerRemoving(player: Player)
	arenaPlayers[player.UserId] = nil
	arenaState[player.UserId] = nil
	-- HeroCombat also cleans up on its own PlayerRemoving connection; calling it
	-- here too is harmless (dropPlayer is idempotent) and makes the arena's
	-- teardown self-contained rather than dependent on connection ordering.
	if CombatManager then
		CombatManager.unregisterHero(player)
	end
	local conn = characterConns[player.UserId]
	if conn then
		conn:Disconnect()
		characterConns[player.UserId] = nil
	end
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
			elseif
				action == "HeroLight"
				or action == "HeroHeavy"
				or action == "HeroRanged"
				or action == "HeroBlock"
				or action == "HeroDodge"
			then
				handleHeroAction(player, action, data)
			elseif action == "PlayerMeleeAttack" then
				handleHeroAction(player, "HeroLight", data) -- legacy alias
			elseif action == "PlayerRangedAttack" then
				handleHeroAction(player, "HeroRanged", data) -- legacy alias
			end
		end)
	end)

	game:GetService("Players").PlayerRemoving:Connect(ArenaMode.playerRemoving)

	ArenaDebug:info("ArenaMode initialized")
end

return ArenaMode
