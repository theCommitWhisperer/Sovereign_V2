--!strict
-- UnitAnimationsData: the single registry of animation asset ids per rig.
--
-- WHY THIS EXISTS
-- Roblox's stock walk/idle animations only drive R6/R15 *part* hierarchies
-- ("Torso", "Left Arm", "UpperTorso", …). A skinned MeshPart rig — one MeshPart
-- with a Bone tree, which is what every custom-authored asset is — has none of
-- those parts, so a stock animation loads without error and then moves nothing.
-- The unit slides across the ground in its bind pose. That is the entire reason
-- custom models "don't walk".
--
-- So each rig needs animations authored against ITS OWN skeleton, and something
-- has to say which set belongs to which model. That's the `AnimSet` attribute:
-- it's set on the TEMPLATE in ReplicatedStorage.Assets.Units, so it survives the
-- clone-and-rename that UnitManager.createUnit performs and the client can read
-- it off any spawned unit.
--
-- ADDING A NEW RIG  (the "Peasant_Male_4" pipeline — see StudioTools/RigSetup.lua)
--   1. Import the rig + its animations into Studio. The importer drops a
--      `<Name>_Character_output` Model and a pile of KeyframeSequences in Workspace,
--      and publishes one Animation asset per clip to your inventory.
--   2. Run `python tools/fetch_anim_ids.py <robloxUserId> --prefix <Name>` — it reads
--      your public inventory and prints a ready-to-paste Set, ids already mapped to
--      slots by clip name.
--   3. Paste it below.
--   4. Run StudioTools/RigSetup.lua in the command bar. It normalizes the import
--      (Humanoid, HumanoidRootPart, SkinnedRig + AnimSet attributes) and files it
--      into ReplicatedStorage.Assets.Units.<UnitType> as a variant.
--
-- ADDING AN ANIMATION TO AN EXISTING RIG
--   Just fill in the slot. Any slot left nil degrades gracefully — see
--   UnitAnimator's `resolve`, which never falls back to a stock animation for a
--   skinned rig (that's what produced the silent no-op in the first place).

local UnitAnimationsData = {}

-- Every slot takes EITHER one asset id or a list of them.
--
-- A list is a variant pool: the animator re-rolls which clip to play each time
-- the unit enters that state, so a field of 200 peasants isn't 200 copies of the
-- same idle breathing in lockstep. The roll is per-entry, not per-unit, so the
-- same peasant standing around cycles through its idles over time.
--
-- One string and a one-element list behave identically — existing sets did not
-- have to change.
export type AnimationSlot = string | { string }

export type AnimationSet = {
	-- Locomotion. `walk` is the only required slot.
	walk: AnimationSlot,
	run: AnimationSlot?,
	idle: AnimationSlot?,
	-- Stationary pose that REPLACES `idle` when the unit's `Pose` attribute asks
	-- for it. Purely cosmetic and always optional: a rig with no `sit` just idles
	-- at the campfire instead, which looks fine.
	sit: AnimationSlot?,
	-- Played while a worker is at its station (Pose = "work"). Same mechanism as
	-- `sit`; see POSE_SLOTS.
	work: AnimationSlot?,
	-- Studs to lower the body by while the `sit` clip plays.
	--
	-- A Humanoid always holds its root a fixed height above the ground, sized for
	-- a STANDING rig. A seated pose folds the legs up, so the lowest point of the
	-- body rises — and the unit hovers by exactly that much, because nothing told
	-- the Humanoid its occupant sat down. This is that correction.
	--
	-- Applied via the rig's RootJoint, NOT via HipHeight — see setSeated in
	-- IdlePeasantManager for why lowering the Humanoid makes units fight the
	-- floor instead of sitting.
	--
	-- Measure it, don't guess: play the sit clip and the idle clip on the rig and
	-- take (lowest bone below root while idling) - (lowest bone below root while
	-- seated). Note this only works in PLAY mode, and only while the track is
	-- genuinely playing — scrubbing TimePosition at speed 0 does not drive the
	-- skinning, and every bone reads as unanimated.
	sitHipDrop: number?,
	-- Combat / lifecycle. `death` is played on Humanoid.Died; `attack` is wired
	-- for the combat engine and unused by the locomotion loop.
	attack: AnimationSlot?,
	death: AnimationSlot?,
	-- Studs/sec the walk cycle was authored for. Playback speed is scaled by
	-- (observed speed / this), so legs match ground travel instead of skating.
	walkBaseSpeed: number?,
	-- Skinned rigs must never fall back to stock R6/R15 animations: they load
	-- fine and animate nothing. Set false to hard-disable that fallback.
	allowStockFallback: boolean?,
}

-- ---------------------------------------------------------------------------
-- CUSTOM RIGS
-- ---------------------------------------------------------------------------

UnitAnimationsData.Sets = {
	-- The Peasant Man rig. Character-Creator skeleton (`CC_Base_*`, 71 bones).
	--
	-- RETIRED 2026-07-26 — the model now lives in Assets.UnitsBackup.Peasant and
	-- no longer spawns. It only ever had a walk and a death, so it froze on walk
	-- frame 0 whenever it stood still (see UnitAnimator's frozen-walk fallback),
	-- while the PeasantBiped rigs above have a full set. The table stays here
	-- because the model still exists in backup; if it's ever restored to the pool
	-- this is what drives it.
	--
	-- IMPORTANT: this skeleton shares ZERO bone names with the Celtic rig below,
	-- so the two sets are NOT interchangeable in either direction. Loading one
	-- rig's animation on the other fails silently — it plays and moves nothing.
	-- Always author animations against the rig they'll run on.
	PeasantMan = {
		walk = "rbxassetid://132430041531045",

		-- Breathing_Idle (75670874766855) is DISABLED — it collapses the rig.
		--
		-- Measured on the live rig: with the walk playing, head-to-foot is 4.06
		-- studs (standing). With this idle playing it's 0.57 — the character folds
		-- into a heap. Neither animation keys bone POSITIONS (max offset 0.000),
		-- so it isn't a scale or retarget-displacement problem: the idle's
		-- ROTATIONS are relative to a different rest pose than the one this model
		-- was exported with. The walk came out of the same DCC scene as the mesh;
		-- this idle did not.
		--
		-- TO FIX: re-export the idle against THIS rig (same skeleton, same rest
		-- pose as PeasantManWalking), re-upload, and put the new id here. Nothing
		-- in the code needs to change — just un-comment the line.
		idle = nil, -- "rbxassetid://75670874766855",

		-- Verified good: stands upright (head-foot 4.29) and carries real hip root
		-- motion, so the body actually falls rather than sinking in place.
		death = "rbxassetid://122356832819525", -- Standing React Death

		run = nil,
		attack = nil,
		-- Measured: 1.033s cycle, reads naturally at 16 studs/sec.
		walkBaseSpeed = 16,
		allowStockFallback = false,
	} :: AnimationSet,

	-- The standard 22-bone biped skeleton, and the reference for every rig
	-- authored from here on.
	--
	-- Skinned MeshPart `char1` + a Mixamo-style tree (Hips, Spine, Spine01,
	-- Spine02, neck, Head, {Left,Right}{UpLeg,Leg,Foot,ToeBase,Shoulder,Arm,
	-- ForeArm,Hand}). The bones are UNPREFIXED, which is what distinguishes them
	-- from the older `mixamorig:`-prefixed uploads (those drive nothing here) and
	-- from the CC_Base PeasantMan tree below.
	--
	-- KEYED TO THE SKELETON, NOT TO A MODEL. Every model exported from the same
	-- tool shares this bone tree exactly, so they all share these clips: verified
	-- by comparing bone sets, Peasant_Male_4 and Peasant_Male_2 differ by zero
	-- bones in either direction. Point any new model's `AnimSet` here rather than
	-- duplicating the table — a second copy is a second thing to forget to update.
	--
	-- Current members: Peasant_Male_2, Peasant_Male_4, Male_Peasant_3,
	-- Female_Peasant_1, Female_Peasant_2, Female_Peasant_3 — six variants, all
	-- verified 22/22 against these clips.
	--
	-- Every id below came out of tools/fetch_anim_ids.py against the 2026-07-26
	-- upload batch; the clip name each one maps to is in the trailing comment so a
	-- re-upload can be diffed against this table by name rather than by id.
	PeasantBiped = {
		walk = "rbxassetid://125385772561188", -- Walking / walking_man
		run = "rbxassetid://78199799672532", -- Running

		-- Three authored idles. The animator picks one on each transition INTO
		-- idle, so a standing crowd desynchronizes on its own and a peasant that
		-- stands still for a while visibly changes what it's doing.
		--
		-- Idle_11 was here and was dropped. The two 20-second clips are long
		-- enough that a peasant rarely loops one before something re-tasks it.
		idle = {
			"rbxassetid://127963036901982", -- Idle_03 (5.3s)
			"rbxassetid://118134631533803", -- Idle_Stretching (20.0s)
			"rbxassetid://115094929855068", -- Idle_Hands_On_Side (20.0s)
		},

		-- Played instead of `idle` when the unit is stationary AND something has
		-- set its `Pose` attribute to "sit" — today that's IdlePeasantManager
		-- parking a peasant at the Keep's campfire. See the Pose contract below.
		sit = "rbxassetid://127140555193167", -- Sitting_At_Campfire (10.0s loop)
		-- Measured on Peasant_Male_4 in Play mode: the lowest bone sits 2.76 studs
		-- below the root while idling and 1.13 below it while seated, giving a
		-- 1.63-stud hover. Raised to 1.90 by eye — the measurement tracks the
		-- lowest BONE, but what should touch the ground is the seated body's
		-- surface, and there is more mesh below the pelvis bone than below the
		-- toe bone the standing pose was calibrated against.
		--
		-- One value covers every PeasantBiped rig: the drop comes from the CLIP
		-- and the skeleton, which they share, not from each model's own height.
		-- IdlePeasantManager guarantees the full drop is applied even on rigs
		-- whose HipHeight runs out first — see setSeated.
		sitHipDrop = 1.90,

		-- Three melee combos. Unused by the locomotion loop — CombatService drives
		-- these — but registered so the variant pool exists the moment it's wired.
		attack = {
			"rbxassetid://113440818269792", -- Punch_Combo
			"rbxassetid://87583774456196", -- Punch_Combo_1
			"rbxassetid://71687197274580", -- Punch_Combo_2
		},

		-- Three deaths, rolled per-death, so a wiped-out squad doesn't fall in
		-- perfect unison.
		death = {
			"rbxassetid://133735504348112", -- dying_backwards
			"rbxassetid://94428973599707", -- Fall_Dead_from_Abdominal_Injury
			"rbxassetid://76684635965094", -- Dead
		},

		-- UNASSIGNED. The character file's own bind clip: zero-length, holds the
		-- T-pose. Never assign it to a slot — it exists only as an import artefact.
		--   rbxassetid://82516295175679  -- Character_output clip0
		--
		-- Dropped: rbxassetid://132178834925182 (Idle_11).

		walkBaseSpeed = 16,
		allowStockFallback = false,
	} :: AnimationSet,

	-- The Celtic Champion skinned rig (MeshPart `char1` + Mixamo Hips bone tree).
	-- Currently stands in for the other 51 unit types until their assets exist.
	Celtic_Champion = {
		walk = "rbxassetid://129344956118964",
		run = nil, -- TODO: author a run cycle; walk is time-scaled meanwhile
		idle = nil, -- TODO: author an idle; walk-frame-0 hold is used meanwhile
		attack = nil,
		death = nil,
		-- Measured: the cycle is 1.03s long and reads naturally at Roblox's
		-- default 16 studs/sec. Units move at UnitsData.move_speed * 16, so a
		-- Peasant (1.0) plays at 1.0x, a Knight (2.0) at 2.0x, and a Celtic
		-- Champion (3.8) pins to the clamp — see the note on SPEED_CLAMP.
		walkBaseSpeed = 16,
		allowStockFallback = false,
	} :: AnimationSet,
}

-- ---------------------------------------------------------------------------
-- STOCK ROBLOX FALLBACK — for real R6/R15 part rigs only
-- ---------------------------------------------------------------------------

UnitAnimationsData.Stock = {
	R6 = {
		idle = "rbxassetid://180435571",
		walk = "rbxassetid://180426354",
		walkBaseSpeed = 14,
	} :: AnimationSet,
	R15 = {
		idle = "rbxassetid://507766388",
		walk = "rbxassetid://913402848",
		walkBaseSpeed = 14,
	} :: AnimationSet,
}

-- ---------------------------------------------------------------------------
-- TUNING
-- ---------------------------------------------------------------------------

-- Below this ground speed (studs/sec) a unit counts as standing still.
UnitAnimationsData.WALK_THRESHOLD = 0.6
-- -- THE `Gait` ATTRIBUTE: what makes a unit run ----------------------------
--
-- Run is a decision the SERVER makes, not something the client infers from how
-- fast a unit happens to be moving. A unit runs when it is charging an enemy or
-- hurrying home — never because it's walking somewhere at its normal speed.
--
-- This replaced a `speed >= 0.85 * BaseWalkSpeed` heuristic, which was wrong in
-- the most basic case: a unit walking anywhere at its ordinary speed IS at 100%
-- of its base speed, so it played the run cycle for every ordinary move order
-- and the walk cycle was effectively dead. No threshold fixes that — normal
-- walking and running are the same speed, so speed cannot distinguish them.
--
-- The attribute holds the REASON, so that two independent systems can each
-- clear only what they set and never stomp each other:
--
--   nil        walking (or standing)
--   "charge"   closing on an enemy — set/cleared by CombatService from
--              `isCharging`, which is itself gated on the stance's `canCharge`
--   "hurry"    ordered back to the Keep — set by GameManager's ReturnToKeep,
--              cleared by MovementSystem when the unit arrives
--
-- Any non-nil value means run. Add new reasons freely; the animator doesn't
-- care which one it is, only that the server asked for a run.
--
-- Replication cost is one attribute written on a STATE TRANSITION, not per
-- frame — a charging unit writes once when it starts and once when it stops.
UnitAnimationsData.GAIT_ATTRIBUTE = "Gait"

-- -- THE `Pose` ATTRIBUTE: what a STATIONARY unit is doing -------------------
--
-- Same shape as `Gait`, and deliberately separate from it. `Gait` answers "how
-- is this unit travelling"; `Pose` answers "what is it doing while stopped".
-- A unit that starts moving plays its walk regardless of Pose, so nothing has
-- to remember to clear the pose before issuing a move order — the peasant
-- simply stands up and walks.
--
--   nil      ordinary idle
--   "sit"    seated — set by IdlePeasantManager when a peasant reaches its
--            campfire slot, cleared when it's re-tasked or leaves
--   "work"   at a workplace — set by WorkerManager while a worker is producing,
--            cleared when it stops or is unassigned
--
-- Unknown values fall back to the ordinary idle rather than freezing the rig,
-- so a typo here is cosmetic rather than a unit standing in its bind pose. The
-- same is true of a pose whose clip hasn't been authored yet: the unit simply
-- idles, which is why the `work` slots can ship empty.
UnitAnimationsData.POSE_ATTRIBUTE = "Pose"

-- Every slot a `Pose` value may name. The animator loads a track pool per entry
-- and plays whichever the attribute selects, so ADDING A NEW POSE IS A DATA
-- CHANGE: add the slot to AnimationSet, list its name here, fill it in per rig,
-- and have a server system set the attribute. No animator code changes.
UnitAnimationsData.POSE_SLOTS = { "sit", "work" }
-- Clamp on walk-cycle playback rate, so slow units don't crawl in slow motion
-- and cavalry doesn't vibrate.
--
-- NOTE: UnitsData.move_speed is multiplied by 16 to get WalkSpeed, so a Celtic
-- Champion (move_speed 3.8) travels at 60.8 studs/sec — nearly 4x the speed the
-- walk cycle was authored for. It pins to `max` and still under-strides, i.e.
-- the fast units will look like they're skating a little. That's a game-tuning
-- question (move_speed values) rather than an animation one, so it's left alone.
UnitAnimationsData.SPEED_CLAMP = { min = 0.5, max = 3.0 }
-- Crossfade time for every locomotion transition.
UnitAnimationsData.FADE = 0.15

function UnitAnimationsData.getSet(animSet: string?): AnimationSet?
	if not animSet then
		return nil
	end
	return UnitAnimationsData.Sets[animSet]
end

-- Flatten a slot to a list of ids, so callers never branch on the union type.
-- nil and "" both yield an empty list, which is how a missing slot is expressed
-- everywhere downstream.
function UnitAnimationsData.toList(slot: AnimationSlot?): { string }
	if slot == nil then
		return {}
	end
	if type(slot) == "string" then
		return if slot == "" then {} else { slot }
	end
	local out = {}
	for _, id in slot do
		if type(id) == "string" and id ~= "" then
			table.insert(out, id)
		end
	end
	return out
end

function UnitAnimationsData.getStock(rigType: Enum.HumanoidRigType): AnimationSet
	return if rigType == Enum.HumanoidRigType.R15
		then UnitAnimationsData.Stock.R15
		else UnitAnimationsData.Stock.R6
end

return UnitAnimationsData

