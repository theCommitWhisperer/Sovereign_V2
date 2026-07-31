--!strict
-- BlipReplicator: builds and pushes minimap snapshots.
--
-- Replaces the client-side scan-workspace-and-ask-the-server-about-every-object
-- loop that MiniMap, FogOfWarClient and HealthBarManager each ran independently
-- at 2Hz. That was three blocking RemoteFunction round trips per object per
-- client per half-second, and it could not see past the streaming radius.
--
-- Here the server does the work once per tick for everyone, quantises and
-- de-duplicates, and pushes a packed buffer. Positions come from the server's
-- own view of the world, so StreamingEnabled no longer determines what a player
-- can see on their minimap.
--
-- Cost shape: O(objects) once per tick to gather, then O(objects) per player to
-- filter. Fog queries are O(1) against FogOfWarManager's spatial index. A
-- 4-player match with 500 units is roughly 2500 cheap iterations per tick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MinimapBlips = require(ReplicatedStorage.Shared.MinimapBlips)

local Managers = script.Parent.Parent.Managers
local AIManager = require(Managers.AIManager)
local FactionManager = require(Managers.FactionManager)
local FogOfWarManager = require(Managers.FogOfWarManager)
local PlayerManager = require(Managers.PlayerManager)
local SpawnManager = require(Managers.SpawnManager)

local BlipDebug = DebugManager.createChannel("BlipReplicator", false)

local BlipReplicator = {}

-- Must match FogOfWarManager.INDEX_TTL so the vision index a snapshot is built
-- against is never more than one tick stale.
local TICK = 0.25

local QUANTIZE = MinimapBlips.QUANTIZE_STUDS
local MAX_BLIPS = MinimapBlips.MAX_BLIPS
local BYTES = MinimapBlips.BYTES_PER_BLIP

local Kind = MinimapBlips.Kind
local Relation = MinimapBlips.Relation

local remoteEvent: RemoteEvent? = nil
local running = false

-- Scratch state, allocated once and reused every tick. The whole point of the
-- packed format is to avoid per-blip garbage; allocating these per tick would
-- give it straight back.
local srcX: { number } = {}
local srcZ: { number } = {}
local srcOwner: { number } = {}
local srcKind: { number } = {}
local srcSubtype: { number } = {}
local srcCount = 0

local factionCache: { [number]: string? } = {}
local seen: { [number]: boolean } = {}
local scratch = buffer.create(MAX_BLIPS * BYTES)

--- Faction name for an owner id, whether that owner is a human or an AI.
--- Cached per tick because a 500-unit army resolves the same handful of owners
--- over and over.
local function factionOf(ownerId: number): string?
	local cached = factionCache[ownerId]
	if cached ~= nil then
		return cached
	end

	local faction: string? = nil

	local player = Players:GetPlayerByUserId(ownerId)
	if player then
		local playerData = PlayerManager.get(player)
		faction = playerData and playerData.Faction
	else
		local aiState = AIManager.getState(ownerId)
		faction = aiState and aiState.faction
	end

	factionCache[ownerId] = faction
	return faction
end

local function addSource(position: Vector3, ownerId: number, kind: number, subtype: number)
	srcCount += 1
	srcX[srcCount] = position.X
	srcZ[srcCount] = position.Z
	srcOwner[srcCount] = ownerId
	srcKind[srcCount] = kind
	srcSubtype[srcCount] = subtype
end

local function gatherFolder(folderName: string, kind: number, attributeName: string, subtypeMap: { [string]: number }?)
	local folder = workspace:FindFirstChild(folderName)
	if not folder then
		return
	end

	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local primary = model.PrimaryPart
		if not primary then
			continue
		end

		local ownerId = model:GetAttribute("OwnerId")
		local subtype = 0
		if subtypeMap then
			local typeName = model:GetAttribute(attributeName)
			if typeof(typeName) == "string" then
				subtype = subtypeMap[typeName] or 0
			end
		end

		addSource(primary.Position, if typeof(ownerId) == "number" then ownerId else 0, kind, subtype)
	end
end

--- Snapshot the world once per tick, shared across every player.
---
--- Order matters. sendSnapshot walks this array front to back and stops at
--- MAX_BLIPS, so whatever is gathered last is what gets dropped when a match
--- gets large. Units are the unbounded population; buildings and resource nodes
--- are few and mostly static. Gathering units first meant a big battle could
--- push a player's own Keep off their own minimap -- so buildings go first and
--- units absorb the truncation.
local function gatherSources()
	srcCount = 0
	table.clear(factionCache)

	gatherFolder("Buildings", Kind.Building, "BuildingType", MinimapBlips.BuildingSubtype)
	gatherFolder("ResourceNodes", Kind.Resource, "ResourceType", MinimapBlips.ResourceSubtype)
	gatherFolder("Units", Kind.Unit, "UnitType", nil)
end

--- Build and send one player's snapshot. Returns the blip count for logging.
local function sendSnapshot(player: Player, remote: RemoteEvent): number
	local viewerId = player.UserId
	local viewerData = PlayerManager.get(player)
	local viewerFaction = viewerData and viewerData.Faction

	-- nil when fog is off for this player, in which case every position passes.
	local visionIndex = FogOfWarManager.getVisionIndex(player)

	table.clear(seen)
	local written = 0

	for i = 1, srcCount do
		if written >= MAX_BLIPS then
			break
		end

		local ownerId = srcOwner[i]
		local kind = srcKind[i]
		local x, z = srcX[i], srcZ[i]

		-- Relation first: it decides whether fog even applies.
		local relation: number
		if kind == Kind.Resource or ownerId == 0 then
			relation = Relation.Neutral
		elseif ownerId == viewerId then
			relation = Relation.Self
		else
			local ownerFaction = factionOf(ownerId)
			if viewerFaction and ownerFaction and FactionManager.areAllies(viewerFaction, ownerFaction) then
				relation = Relation.Ally
			else
				relation = Relation.Enemy
			end
		end

		-- You always see your own and your allies'. Resource nodes are static
		-- terrain features and were never fogged. Everything else is a fog query.
		local visible = relation == Relation.Self
			or relation == Relation.Ally
			or kind == Kind.Resource
			or FogOfWarManager.isPositionVisibleWithIndex(visionIndex, x, z)

		if visible then
			local ownerSlot = 0
			if ownerId ~= 0 then
				ownerSlot = SpawnManager.getPlayerSpawn(ownerId) or 0
			end
			-- The wire format gives ownerSlot 4 bits and the dedupe key below
			-- multiplies by 16. Clamp rather than letting a hypothetical
			-- 16-kingdom map silently wrap the byte AND collide dedupe keys.
			ownerSlot = math.clamp(ownerSlot, 0, 15)

			-- Snap to the quantisation grid and drop anything that lands on a
			-- cell already claimed by the same owner and kind. At 8 studs this
			-- is roughly one minimap pixel, so nothing visible is lost, and a
			-- packed 200-unit army collapses to a few dozen blips.
			--
			-- Clamp to the same i16 range MinimapBlips.write clamps to, so a
			-- unit flung out of bounds dedupes on the cell it will actually be
			-- drawn at rather than its true one.
			local cellX = math.floor(math.clamp(x, -32768, 32767) / QUANTIZE)
			local cellZ = math.floor(math.clamp(z, -32768, 32767) / QUANTIZE)
			local key = (((cellX + 4096) * 8192 + (cellZ + 4096)) * 16 + ownerSlot) * 4 + kind

			if not seen[key] then
				seen[key] = true
				MinimapBlips.write(
					scratch,
					written,
					cellX * QUANTIZE,
					cellZ * QUANTIZE,
					ownerSlot,
					relation,
					kind,
					srcSubtype[i]
				)
				written += 1
			end
		end
	end

	-- Send a right-sized copy so an empty map costs 0 bytes rather than 3KB.
	local packet = buffer.create(written * BYTES)
	buffer.copy(packet, 0, scratch, 0, written * BYTES)
	remote:FireClient(player, packet)

	return written
end

--- Wire up the remote. Called by GameManager once the RemoteEvents folder exists.
function BlipReplicator.init(remote: RemoteEvent)
	remoteEvent = remote
	BlipDebug:info("BlipReplicator initialized")
end

--- Idempotent, like FogOfWarManager.startUpdates -- GameManager has a history of
--- starting things twice.
function BlipReplicator.start()
	if running then
		return
	end
	local remote = remoteEvent
	if not remote then
		BlipDebug:warn("start() called before init(); no remote to push on")
		return
	end
	running = true

	task.spawn(function()
		while running do
			task.wait(TICK)

			local ok, err = pcall(function()
				local players = Players:GetPlayers()
				if #players == 0 then
					return
				end

				gatherSources()

				for _, player in players do
					local playerData = PlayerManager.get(player)
					if playerData and playerData.GameState == "InGame" then
						sendSnapshot(player, remote)
					end
				end
			end)

			if not ok then
				BlipDebug:warn(`snapshot tick failed: {tostring(err)}`)
			end
		end
	end)

	BlipDebug:info("BlipReplicator started")
end

function BlipReplicator.stop()
	running = false
end

return BlipReplicator
