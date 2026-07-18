--!strict
-- CombatSandbox: Instant combat testing without playing through the game.
--
--   /arena                       → builds a flat arena + teleports you there
--   /battle 10xSpearman,5xArcher vs 12xViking
--                                → spawns both armies facing each other; they fight
--   /battle ... vs ... @Empire   → optional enemy faction override
--   /killall                     → wipes every combat unit
--
-- When a battle ends (one side wiped) a report is printed: duration, survivors,
-- top damage dealers. Also auto-arena on Studio start when the Workspace
-- attribute "CombatSandboxAutoStart" is true.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local CombatService = require(script.Parent.CombatService)
local CombatTypes = require(script.Parent.CombatTypes)

local Managers = script.Parent.Parent.Managers
local NotificationManager = require(Managers.NotificationManager)
local PlayerManager = require(Managers.PlayerManager)

-- Lazy-loaded: UnitManager requires CombatManager (facade) which requires this
-- module — requiring it at load time would create a cycle.
local UnitManager = nil :: any
local function getUnitManager(): any
	if not UnitManager then
		UnitManager = require(Managers.UnitManager) :: any
	end
	return UnitManager
end

local SandboxDebug = DebugManager.createChannel("CombatSandbox", true)

type CombatUnit = CombatTypes.CombatUnit

local CombatSandbox = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════════════════════════════════════════

local ARENA_CENTER = Vector3.new(0, 100, -1500)
local ARENA_SIZE = 400
local ARMY_GAP = 70 -- studs between the two front lines
local UNIT_SPACING = 6
local UNITS_PER_ROW = 8
local ENEMY_OWNER_ID = 2000000 -- sentinel AI owner for side B
local DEFAULT_ENEMY_FACTION = "Viking"

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════

type BattleState = {
	startTime: number,
	sideA: { [Model]: boolean },
	sideB: { [Model]: boolean },
	sideACount: number,
	sideBCount: number,
	reportTo: Player?,
	finished: boolean,
}

local activeBattle: BattleState? = nil
local killUnsubscribe: (() -> ())? = nil
local arenaFolder: Folder? = nil

-- ═══════════════════════════════════════════════════════════════════════════
-- ARENA
-- ═══════════════════════════════════════════════════════════════════════════

function CombatSandbox.setupArena(player: Player?): Vector3
	if not arenaFolder or not arenaFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "CombatArena"

		local floor = Instance.new("Part")
		floor.Name = "ArenaFloor"
		floor.Size = Vector3.new(ARENA_SIZE, 2, ARENA_SIZE)
		floor.Position = ARENA_CENTER
		floor.Anchored = true
		floor.Material = Enum.Material.Grass
		floor.Color = Color3.fromRGB(90, 125, 70)
		floor.Parent = folder

		-- Corner markers so you can orient yourself
		for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
			local marker = Instance.new("Part")
			marker.Size = Vector3.new(2, 12, 2)
			marker.Position = ARENA_CENTER + corner * (ARENA_SIZE / 2 - 4) + Vector3.new(0, 7, 0)
			marker.Anchored = true
			marker.Material = Enum.Material.Neon
			marker.Color = Color3.fromRGB(255, 170, 0)
			marker.Parent = folder
		end

		folder.Parent = Workspace
		arenaFolder = folder
		SandboxDebug:info("Arena created", { center = tostring(ARENA_CENTER) })
	end

	-- Bring the requesting player's character over for a good view
	if player and player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			player.Character:PivotTo(CFrame.new(ARENA_CENTER + Vector3.new(0, 6, ARENA_SIZE / 2 - 20)))
		end
	end

	return ARENA_CENTER
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ARMY SPEC PARSING:  "10xSpearman,5xArcher"
-- ═══════════════════════════════════════════════════════════════════════════

export type ArmySpec = { { count: number, unitType: string } }

-- Case-insensitive unit type lookup
local function resolveUnitType(name: string): string?
	local lowered = string.lower(name)
	for unitType in GameData.Units :: { [string]: any } do
		if string.lower(unitType) == lowered then
			return unitType
		end
	end
	return nil
end

function CombatSandbox.parseArmySpec(spec: string): (ArmySpec?, string?)
	local army: ArmySpec = {}
	for _, token in string.split(spec, ",") do
		token = string.gsub(token, "%s", "")
		if token == "" then
			continue
		end
		local countStr, typeStr = string.match(token, "^(%d+)[xX](%a+)$")
		if not countStr then
			-- allow bare "Spearman" meaning 1
			typeStr = string.match(token, "^(%a+)$")
			countStr = "1"
		end
		if not typeStr then
			return nil, `Bad token "{token}" (use e.g. 10xSpearman)`
		end
		local unitType = resolveUnitType(typeStr :: string)
		if not unitType then
			return nil, `Unknown unit type "{typeStr}"`
		end
		local unitData = (GameData.Units :: { [string]: any })[unitType]
		if not unitData.combat then
			return nil, `{unitType} has no combat stats`
		end
		table.insert(army, { count = tonumber(countStr) :: number, unitType = unitType })
	end
	if #army == 0 then
		return nil, "Empty army spec"
	end
	return army, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SPAWNING
-- ═══════════════════════════════════════════════════════════════════════════

local function spawnArmy(
	army: ArmySpec,
	ownerId: number,
	faction: string?,
	lineCenter: Vector3,
	facingDir: number -- +1 spawns rows extending +Z, -1 extends -Z
): { [Model]: boolean }
	local spawned: { [Model]: boolean } = {}
	local index = 0
	for _, entry in army do
		for _ = 1, entry.count do
			local row = index // UNITS_PER_ROW
			local col = index % UNITS_PER_ROW
			local xOffset = (col - (UNITS_PER_ROW - 1) / 2) * UNIT_SPACING
			local zOffset = facingDir * row * UNIT_SPACING
			local pos = lineCenter + Vector3.new(xOffset, 3, zOffset)

			local unit = getUnitManager().createUnit(entry.unitType, ownerId, pos, faction)
			if unit then
				spawned[unit] = true
			end
			index += 1
		end
	end
	return spawned
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BATTLE LIFECYCLE
-- ═══════════════════════════════════════════════════════════════════════════

local function countTable(t: { [Model]: boolean }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function buildReport(battle: BattleState, winner: string): string
	local duration = os.clock() - battle.startTime

	local survivorCounts: { [string]: number } = {}
	local survivorTotal = 0
	local units = CombatService.getActiveCombatUnits()
	local topDamage: { { name: string, dmg: number, kills: number } } = {}

	for model, unit in units do
		if battle.sideA[model] or battle.sideB[model] then
			survivorCounts[unit.unitType] = (survivorCounts[unit.unitType] or 0) + 1
			survivorTotal += 1
			table.insert(topDamage, { name = unit.unitType, dmg = unit.damageDealt, kills = unit.kills })
		end
	end
	table.sort(topDamage, function(a, b)
		return a.dmg > b.dmg
	end)

	local lines = {
		`BATTLE REPORT — {winner} wins in {string.format("%.1f", duration)}s`,
		`Survivors ({survivorTotal}):`,
	}
	for unitType, count in survivorCounts do
		table.insert(lines, `  {count}x {unitType}`)
	end
	table.insert(lines, "Top damage (survivors):")
	for i = 1, math.min(3, #topDamage) do
		local entry = topDamage[i]
		table.insert(lines, `  {entry.name}: {entry.dmg} dmg, {entry.kills} kills`)
	end
	return table.concat(lines, "\n")
end

local function finishBattle(winner: string)
	local battle = activeBattle
	if not battle or battle.finished then
		return
	end
	battle.finished = true

	local report = buildReport(battle, winner)
	SandboxDebug:info(report)
	print(report) -- always visible in Studio output

	if battle.reportTo then
		NotificationManager.info(battle.reportTo :: Player, "Battle Over", report)
	end
end

local function onUnitKilled(victim: CombatUnit, _killer: CombatUnit?)
	local battle = activeBattle
	if not battle or battle.finished then
		return
	end
	if battle.sideA[victim.model] then
		battle.sideA[victim.model] = nil
		battle.sideACount -= 1
	elseif battle.sideB[victim.model] then
		battle.sideB[victim.model] = nil
		battle.sideBCount -= 1
	else
		return
	end

	if battle.sideACount <= 0 then
		finishBattle("Side B (enemy)")
	elseif battle.sideBCount <= 0 then
		finishBattle("Side A (you)")
	end
end

function CombatSandbox.startBattle(player: Player, specText: string): string?
	-- Optional enemy faction override: "... @Empire"
	local enemyFaction = DEFAULT_ENEMY_FACTION
	local factionOverride = string.match(specText, "@(%a+)%s*$")
	if factionOverride then
		enemyFaction = factionOverride
		specText = string.gsub(specText, "@%a+%s*$", "")
	end

	specText = string.gsub(specText, "%s+[vV][sS]%s+", " vs ")
	local sides = string.split(specText, " vs ")
	if #sides ~= 2 then
		return 'Usage: /battle 10xSpearman,5xArcher vs 12xViking [@Faction]'
	end

	local armyA, errA = CombatSandbox.parseArmySpec(sides[1])
	if not armyA then
		return `Side A: {errA}`
	end
	local armyB, errB = CombatSandbox.parseArmySpec(sides[2])
	if not armyB then
		return `Side B: {errB}`
	end

	local center = CombatSandbox.setupArena(player)

	-- Side A must get an explicit hostile-capable faction: most UnitsData entries
	-- default to faction = "Neutral", which is enemies with nobody.
	local playerData = PlayerManager.get(player)
	local playerFaction: string = (playerData and playerData.Faction) or "Kingdom"

	local lineA = center + Vector3.new(0, 0, -ARMY_GAP / 2)
	local lineB = center + Vector3.new(0, 0, ARMY_GAP / 2)

	local sideA = spawnArmy(armyA :: ArmySpec, player.UserId, playerFaction, lineA, -1)
	local sideB = spawnArmy(armyB :: ArmySpec, ENEMY_OWNER_ID, enemyFaction, lineB, 1)

	activeBattle = {
		startTime = os.clock(),
		sideA = sideA,
		sideB = sideB,
		sideACount = countTable(sideA),
		sideBCount = countTable(sideB),
		reportTo = player,
		finished = false,
	}

	if not killUnsubscribe then
		killUnsubscribe = CombatService.onUnitKilled(onUnitKilled)
	end

	local battle = activeBattle :: BattleState
	SandboxDebug:info("Battle started", {
		sideA = battle.sideACount,
		sideB = battle.sideBCount,
		enemyFaction = enemyFaction,
	})
	return nil -- no error
end

function CombatSandbox.killAll()
	activeBattle = nil
	CombatService.clearAllUnits()
	SandboxDebug:info("All combat units cleared")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STUDIO AUTO-START
-- ═══════════════════════════════════════════════════════════════════════════

function CombatSandbox.init()
	if RunService:IsStudio() and Workspace:GetAttribute("CombatSandboxAutoStart") == true then
		Players.PlayerAdded:Connect(function(player)
			task.wait(3) -- let core systems settle
			CombatSandbox.setupArena(player)
			NotificationManager.info(
				player,
				"Combat Sandbox",
				"Arena ready. Try: /battle 10xSpearman,5xArcher vs 12xViking"
			)
		end)
	end
end

return CombatSandbox
