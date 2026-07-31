--!strict
-- MinimapBlips: the wire format shared by BlipReplicator (server) and
-- MinimapService (client).
--
-- The minimap used to work by scanning workspace.Units / workspace.Buildings on
-- the client and calling CheckVisibility:InvokeServer() once per object, twice a
-- second. That is a blocking round trip per unit per client, and under
-- StreamingEnabled it can only ever see objects inside the client's streaming
-- radius -- so on a 1600-stud map it was structurally incapable of showing the
-- whole board.
--
-- Instead the server pushes a whole snapshot ~4x/second on a RemoteEvent.
-- Snapshots are latest-state-wins, which would normally argue for an
-- UnreliableRemoteEvent -- but those deliver nothing at all in Studio Play Solo
-- (measured: zero packets received at 64 bytes through 3KB, while a reliable
-- remote delivered every one), and they cap payloads at 900 bytes. See the
-- comment on BlipSnapshotEvent in GameManager.
--
-- One blip is 6 bytes, laid out so neither side has to allocate a table per
-- blip:
--
--   offset 0   i16   world X in studs
--   offset 2   i16   world Z in studs
--   offset 4   u8    bits 0-3  owner slot (0 = neutral, 1-4 = spawn zone)
--                    bits 4-5  relation  (see Relation)
--                    bits 6-7  reserved
--   offset 5   u8    bits 0-3  kind      (see Kind)
--                    bits 4-7  subtype   (kind-specific, see *Subtype)
--
-- i16 caps world coordinates at +/-32767 studs. The largest shipped map is 1600
-- (MapData.Maps.TheIslands), so there is a lot of headroom, but encode() clamps
-- rather than wrapping in case a unit is ever flung out of bounds.

local MinimapBlips = {}

MinimapBlips.BYTES_PER_BLIP = 6

-- Positions are snapped to this grid before de-duplication. The minimap is
-- ~170-210px wide for a 1600-stud map, so one pixel is roughly 8 studs: finer
-- precision than this is not renderable and only costs bandwidth.
MinimapBlips.QUANTIZE_STUDS = 8

-- Hard ceiling on blips in a single snapshot. At 6 bytes each this caps a
-- snapshot at ~3KB. De-duplication normally keeps a 500-unit battle well under
-- 200 blips; this is a backstop, not a target.
MinimapBlips.MAX_BLIPS = 512

MinimapBlips.Kind = {
	Unit = 0,
	Building = 1,
	Resource = 2,
}

MinimapBlips.Relation = {
	Self = 0,
	Ally = 1,
	Enemy = 2,
	Neutral = 3,
}

-- Subtype is only used to pick an icon/size on the client. Anything not listed
-- falls back to 0, which renders as the generic dot for its kind.
MinimapBlips.BuildingSubtype = {
	Keep = 1,
	Town_Center = 2,
	Barracks = 3,
	Farm = 4,
	Mine = 5,
	Storehouse = 6,
	Tower = 7,
	Wall = 8,
}

MinimapBlips.ResourceSubtype = {
	Wood = 1,
	Stone = 2,
	Food = 3,
	Iron_Ore = 4,
	Gold = 5,
}

--- Number of blips in a snapshot buffer.
function MinimapBlips.count(buf: buffer): number
	return buffer.len(buf) // MinimapBlips.BYTES_PER_BLIP
end

--- Write one blip at `index` (0-based). Callers are responsible for having
--- allocated a buffer large enough; this does no bounds checking because it sits
--- in the replicator's inner loop.
function MinimapBlips.write(
	buf: buffer,
	index: number,
	x: number,
	z: number,
	ownerSlot: number,
	relation: number,
	kind: number,
	subtype: number
)
	local offset = index * MinimapBlips.BYTES_PER_BLIP

	buffer.writei16(buf, offset, math.clamp(math.round(x), -32768, 32767))
	buffer.writei16(buf, offset + 2, math.clamp(math.round(z), -32768, 32767))
	buffer.writeu8(buf, offset + 4, bit32.bor(bit32.band(ownerSlot, 0xF), bit32.lshift(bit32.band(relation, 0x3), 4)))
	buffer.writeu8(buf, offset + 5, bit32.bor(bit32.band(kind, 0xF), bit32.lshift(bit32.band(subtype, 0xF), 4)))
end

--- Read one blip at `index` (0-based).
--- Returns x, z, ownerSlot, relation, kind, subtype.
function MinimapBlips.read(buf: buffer, index: number): (number, number, number, number, number, number)
	local offset = index * MinimapBlips.BYTES_PER_BLIP

	local x = buffer.readi16(buf, offset)
	local z = buffer.readi16(buf, offset + 2)
	local ownerByte = buffer.readu8(buf, offset + 4)
	local kindByte = buffer.readu8(buf, offset + 5)

	return x,
		z,
		bit32.band(ownerByte, 0xF),
		bit32.band(bit32.rshift(ownerByte, 4), 0x3),
		bit32.band(kindByte, 0xF),
		bit32.band(bit32.rshift(kindByte, 4), 0xF)
end

return MinimapBlips
