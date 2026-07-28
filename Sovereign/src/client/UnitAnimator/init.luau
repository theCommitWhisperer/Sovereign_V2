--!strict
-- UnitAnimator (client): drives walk/idle on every server-spawned unit.
--
-- Server-spawned NPCs don't animate themselves — Roblox's automatic locomotion
-- animations come from the Animate LocalScript that only player characters get.
--
-- Runs entirely on the client and reads animation state off each unit's OBSERVED
-- position delta, so it costs ZERO network replication regardless of unit count.
-- The whole system is one Heartbeat loop over a table of tracked models.
--
-- RIG SUPPORT
-- Each unit model may carry an `AnimSet` attribute naming its entry in
-- GameData.UnitAnimations. That's how a skinned MeshPart rig (one MeshPart + a
-- Bone tree, i.e. any custom-authored asset) gets animations authored against
-- its own skeleton. Models with no AnimSet fall back to the stock R6/R15 ids,
-- which is correct only for genuine part-based rigs.
--
-- The failure this replaces: stock ids were used for EVERY model. On a skinned
-- rig they load without error and animate nothing, because they target part
-- names ("Torso", "UpperTorso") that a bone tree does not have. Units slid
-- around in their bind pose and nothing in the log said why.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Required directly (rather than through GameData) so `Anims.AnimationSet`
-- resolves as a type, not just a runtime field.
local Anims = require(ReplicatedStorage.Shared.GameData.UnitAnimationsData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local AnimDebug = DebugManager.createChannel("UnitAnimator", false)

local UnitAnimator = {}

type Entry = {
	humanoid: Humanoid,
	root: BasePart,
	-- Each slot is a POOL. A rig may author several idles / walks / deaths; the
	-- track to play is re-rolled on every transition into that state, so a crowd
	-- of identical units desynchronizes and a unit standing still for a while
	-- cycles through its idles instead of looping one forever.
	--
	-- All tracks in a pool are loaded once at setup and kept — LoadAnimation is
	-- the expensive call, Play/Stop is not, and re-loading on each transition
	-- would stall the first playback while the asset fetched.
	idles: { AnimationTrack },
	walks: { AnimationTrack },
	runs: { AnimationTrack },
	-- Stationary poses, keyed by the name the server puts in the `Pose` attribute
	-- ("sit", "work", …). A pose with no authored clip is simply absent, and the
	-- unit falls back to its ordinary idle.
	poses: { [string]: { AnimationTrack } },
	deaths: { AnimationTrack },
	-- The locomotion track currently playing, i.e. the one whose speed the
	-- Heartbeat loop scales. nil while frozen-walk idling.
	current: AnimationTrack?,
	-- When a rig has no authored idle, we hold the walk cycle at frame 0 instead
	-- of stopping every track (which would snap a skinned rig to its bind pose).
	idleIsFrozenWalk: boolean,
	walkBaseSpeed: number,
	-- Mirrors the server's `Gait` attribute. Kept as a plain boolean updated by a
	-- changed-signal rather than read inside the Heartbeat loop: with several
	-- hundred units on screen the loop runs a few hundred times a frame, and a
	-- gait change happens a handful of times per unit per battle.
	wantsRun: boolean,
	gaitConn: RBXScriptConnection?,
	-- Mirrors the server's `Pose` attribute, same reasoning as wantsRun.
	poseName: string?,
	poseConn: RBXScriptConnection?,
	lastPos: Vector3,
	state: string?, -- "idle" | "walk" | "run"
	-- Once dead the unit stops being driven by movement and holds its death pose.
	dead: boolean,
	diedConn: RBXScriptConnection?,
}

local tracked: { [Model]: Entry } = {}
local warnedSets: { [string]: boolean } = {}
local folderConns: { RBXScriptConnection } = {}
-- Units whose rig hasn't finished replicating yet; see `awaitRig`.
local pending: { [Model]: RBXScriptConnection } = {}

-- How long to keep waiting for a unit's parts to arrive before declaring the
-- model unanimatable. Generous: under StreamingEnabled a distant unit can take
-- a while, and the cost of waiting is one idle connection.
local RIG_WAIT_SECONDS = 20

local function loadTrack(animator: Animator, id: string?, oneShot: boolean?): AnimationTrack?
	if not id or id == "" then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if ok and track then
		track.Looped = not oneShot
		-- Action outranks Movement, so a death plays over a half-finished stride
		-- without having to stop the locomotion tracks first.
		track.Priority = if oneShot then Enum.AnimationPriority.Action else Enum.AnimationPriority.Movement
		return track
	end
	return nil
end

-- Load every id in a slot. A slot that is one string yields a one-element pool,
-- which is why nothing about the single-clip rigs had to change.
local function loadPool(
	animator: Animator,
	slot: Anims.AnimationSlot?,
	oneShot: boolean?,
	modelName: string,
	label: string
): { AnimationTrack }
	local pool: { AnimationTrack } = {}
	for _, id in Anims.toList(slot) do
		local track = loadTrack(animator, id, oneShot)
		if track then
			table.insert(pool, track)
		else
			-- Named loudly: a mistyped id in a variant pool is otherwise invisible
			-- because the other variants still play.
			warn(`[UnitAnimator] "{modelName}": {label} animation "{id}" failed to load and was skipped.`)
		end
	end
	return pool
end

-- Pick a clip from a pool. One element is returned as-is (no wasted random call);
-- with several, avoid repeating the clip that just played so "cycling" actually
-- reads as cycling rather than occasionally rolling the same idle three times.
--
-- With exactly TWO clips the avoid-repeat rule makes this strict alternation
-- rather than a coin flip. That's deliberate — two idles that alternate never
-- look stuck — and units still stay visually out of sync with each other because
-- they enter idle on different frames, not because the choice is random.
local function pick(pool: { AnimationTrack }, avoid: AnimationTrack?): AnimationTrack?
	local n = #pool
	if n == 0 then
		return nil
	end
	if n == 1 then
		return pool[1]
	end
	local choice = pool[math.random(1, n)]
	if choice == avoid then
		-- One re-roll, biased to a different index. Deterministic and cheap.
		choice = pool[(table.find(pool, choice) :: number) % n + 1]
	end
	return choice
end

-- Decide which animation set a model should use, and say so out loud when the
-- answer is "none" — a silent no-op here is exactly what made this hard to find.
local function resolve(model: Model, humanoid: Humanoid): Anims.AnimationSet?
	local key = model:GetAttribute("AnimSet") :: string?
	if key then
		local set = Anims.getSet(key)
		if set then
			return set
		end
		if not warnedSets[key] then
			warnedSets[key] = true
			warn(
				`[UnitAnimator] Model "{model.Name}" has AnimSet="{key}" but no such set exists in `
					.. `GameData/UnitAnimationsData.luau. Add it there, or clear the attribute.`
			)
		end
	end

	-- A skinned rig with no set must NOT get stock animations: they'd load
	-- cleanly and do nothing, which reads as "the animation is broken".
	if model:GetAttribute("SkinnedRig") then
		if not warnedSets[model.Name] then
			warnedSets[model.Name] = true
			warn(
				`[UnitAnimator] "{model.Name}" is a skinned rig with no usable AnimSet. `
					.. `Stock R6/R15 animations cannot drive a bone tree, so it will not be animated.`
			)
		end
		return nil
	end

	return Anims.getStock(humanoid.RigType)
end

-- Is every piece the animator needs present yet?
--
-- This matters because a unit replicates to the client PIECEMEAL. `ChildAdded`
-- on the Units folder fires as soon as the Model exists — its Humanoid, its
-- HumanoidRootPart and its mesh's Bone tree can all arrive several frames later,
-- and under StreamingEnabled (which this place uses) later still. Whether a
-- given unit was complete at the instant we looked is a coin flip, which is
-- exactly why some units animated and others silently never did.
local function rigParts(model: Model): (Humanoid?, BasePart?, boolean)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- A rig animates through joints: Motor6D for part rigs, Bones for skinned
	-- meshes. Neither present means it can't move its limbs — but it may simply
	-- not have replicated yet, so absence is not yet a verdict.
	local jointed = false
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Bone") then
			jointed = true
			break
		end
	end
	return humanoid, root, jointed
end

local setupUnit: (Model) -> ()
local playDeath: (Entry) -> ()

local function clearPending(model: Model)
	local conn = pending[model]
	if conn then
		conn:Disconnect()
		pending[model] = nil
	end
end

-- Re-attempt setup as the rest of the rig streams in, rather than giving up on
-- the first look. Costs one connection per incomplete unit, released as soon as
-- the unit is tracked or the deadline passes.
local function awaitRig(model: Model)
	if pending[model] then
		return
	end
	pending[model] = model.DescendantAdded:Connect(function()
		task.defer(function()
			if model.Parent and not tracked[model] then
				setupUnit(model)
			end
		end)
	end)

	task.delay(RIG_WAIT_SECONDS, function()
		if not pending[model] then
			return
		end
		clearPending(model)
		if tracked[model] or not model.Parent then
			return
		end
		local humanoid, root, jointed = rigParts(model)
		if humanoid and root and not jointed then
			warn(
				`[UnitAnimator] "{model.Name}" has no Motor6D joints and no Bones — it's a static `
					.. `welded model, not an animatable rig, so it can't walk.`
			)
		else
			warn(
				`[UnitAnimator] "{model.Name}" never finished replicating a usable rig `
					.. `(humanoid={humanoid ~= nil} root={root ~= nil} joints={jointed}); not animated.`
			)
		end
	end)
end

function setupUnit(model: Model)
	if tracked[model] then
		return
	end

	local humanoid, root, jointed = rigParts(model)
	if not humanoid or not root or not jointed then
		awaitRig(model)
		return
	end

	local set = resolve(model, humanoid)
	if not set then
		clearPending(model)
		return
	end

	-- A local Animator is enough to play animations client-side.
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local walks = loadPool(animator, set.walk, false, model.Name, "walk")
	if #walks == 0 then
		warn(`[UnitAnimator] No walk animation loaded for "{model.Name}"; not animated.`)
		return
	end
	local idles = loadPool(animator, set.idle, false, model.Name, "idle")
	local runs = loadPool(animator, set.run, false, model.Name, "run")
	-- One pool per pose the game knows about. Slots the rig hasn't authored yield
	-- an empty pool, which the state machine reads as "no such pose, just idle".
	local poses: { [string]: { AnimationTrack } } = {}
	for _, poseName in Anims.POSE_SLOTS do
		local pool = loadPool(animator, (set :: any)[poseName], false, model.Name, poseName)
		if #pool > 0 then
			poses[poseName] = pool
		end
	end
	local deaths = loadPool(animator, set.death, true, model.Name, "death")

	clearPending(model)
	local entry: Entry = {
		humanoid = humanoid,
		root = root,
		idles = idles,
		walks = walks,
		runs = runs,
		poses = poses,
		deaths = deaths,
		current = nil,
		idleIsFrozenWalk = #idles == 0,
		walkBaseSpeed = set.walkBaseSpeed or 14,
		wantsRun = model:GetAttribute(Anims.GAIT_ATTRIBUTE) ~= nil,
		gaitConn = nil,
		poseName = model:GetAttribute(Anims.POSE_ATTRIBUTE) :: string?,
		poseConn = nil,
		lastPos = root.Position,
		state = nil,
		dead = false,
		diedConn = nil,
	}
	tracked[model] = entry

	-- Follow the server's run decision. Any non-nil reason ("charge", "hurry", …)
	-- means run; see the Gait contract in UnitAnimationsData.
	entry.gaitConn = model:GetAttributeChangedSignal(Anims.GAIT_ATTRIBUTE):Connect(function()
		entry.wantsRun = model:GetAttribute(Anims.GAIT_ATTRIBUTE) ~= nil
	end)
	-- Stored raw. A name with no loaded pool falls through to the ordinary idle
	-- rather than leaving the unit in a pose nothing can clear.
	entry.poseConn = model:GetAttributeChangedSignal(Anims.POSE_ATTRIBUTE):Connect(function()
		entry.poseName = model:GetAttribute(Anims.POSE_ATTRIBUTE) :: string?
	end)

	-- Death needs no remote and no server involvement: CombatService already sets
	-- Humanoid.Health = 0, which replicates and fires Died on every client. The
	-- corpse then fades over 2s (CombatService), which the death pose plays under.
	if #deaths > 0 then
		if humanoid.Health <= 0 then
			playDeath(entry)
		else
			entry.diedConn = humanoid.Died:Connect(function()
				playDeath(entry)
			end)
		end
	end

	AnimDebug:info(
		`Animating {model.Name} (walk={#walks} idle={#idles} run={#runs} death={#deaths})`
	)
end

-- Iterate every LOCOMOTION track (deaths excluded — those are handled on their
-- own path so a corpse's pose survives a stop-everything sweep).
--
-- Note these are separate loops over separate arrays rather than one table
-- literal: `{walk, idle, run}` used to have a hole whenever a slot was nil, and
-- generalized iteration stops at a hole — which meant a rig with no idle never
-- had its run track stopped. Arrays that are merely empty have no such problem.
local function forEachTrack(entry: Entry, fn: (AnimationTrack) -> ())
	for _, track in entry.walks do
		fn(track)
	end
	for _, track in entry.idles do
		fn(track)
	end
	for _, track in entry.runs do
		fn(track)
	end
	-- Poses are included: they're stationary LOCOMOTION states, so walking away
	-- from the campfire (or the workbench) has to stop them like any other. Only
	-- deaths are excluded.
	for _, pool in entry.poses do
		for _, track in pool do
			fn(track)
		end
	end
end

-- Play the death pose and freeze on its last frame.
--
-- A one-shot track returns the rig to its BIND pose the instant it ends, which
-- on a skinned rig means the corpse snaps to a T-pose mid-fade. Holding the
-- final frame by zeroing playback avoids that.
function playDeath(entry: Entry)
	if entry.dead then
		return
	end
	entry.dead = true
	entry.current = nil

	-- Rolled here rather than at setup so a squad wiped out in the same volley
	-- doesn't fall in unison.
	local death = pick(entry.deaths)
	if not death then
		return
	end
	forEachTrack(entry, function(track)
		if track.IsPlaying then
			track:Stop(0.1)
		end
	end)
	death:Play(0.1)

	-- Length reads 0 until the asset has loaded; 3s is a safe upper bound for a
	-- death animation and the corpse is gone by then anyway.
	local hold = if death.Length > 0 then death.Length else 3
	task.delay(math.max(hold - 0.05, 0.05), function()
		if death.IsPlaying then
			death:AdjustSpeed(0)
		end
	end)
end

local function cleanup(model: Instance)
	clearPending(model :: Model)
	local entry = tracked[model :: Model]
	if not entry then
		return
	end
	if entry.diedConn then
		entry.diedConn:Disconnect()
		entry.diedConn = nil
	end
	if entry.gaitConn then
		entry.gaitConn:Disconnect()
		entry.gaitConn = nil
	end
	if entry.poseConn then
		entry.poseConn:Disconnect()
		entry.poseConn = nil
	end
	forEachTrack(entry, function(track)
		track:Stop(0)
		track:Destroy()
	end)
	for _, track in entry.deaths do
		track:Stop(0)
		track:Destroy()
	end
	entry.current = nil
	tracked[model :: Model] = nil
end

local function setState(entry: Entry, state: string)
	if entry.state == state then
		return
	end
	entry.state = state
	local fade = Anims.FADE

	-- Idle with no authored idle animation: hold the walk cycle at its first
	-- frame. Stopping every track instead would drop a skinned rig into its bind
	-- pose (arms out, T-pose), which looks far worse than a still walk frame.
	if state == "idle" and entry.idleIsFrozenWalk then
		for _, track in entry.runs do
			track:Stop(fade)
		end
		-- Whichever walk was last playing is the one to freeze; freezing a
		-- different variant would pop the pose.
		local walk = entry.current or entry.walks[1]
		for _, track in entry.walks do
			if track ~= walk and track.IsPlaying then
				track:Stop(fade)
			end
		end
		entry.current = walk
		if not walk.IsPlaying then
			walk:Play(fade)
		end
		walk:AdjustSpeed(0)
		walk.TimePosition = 0
		return
	end

	-- Re-rolled on every transition INTO the state, which is what makes idles
	-- cycle: a unit that stops, walks and stops again gets a different idle, and
	-- two units that stop on different frames were already out of phase.
	-- Anything that isn't locomotion is a pose name, looked up by that name. This
	-- is what lets a new pose be added in data alone.
	local pool = if state == "run"
		then entry.runs
		elseif state == "walk" then entry.walks
		elseif state == "idle" then entry.idles
		else entry.poses[state] or entry.idles
	local want = pick(pool, entry.current)
	entry.current = want

	forEachTrack(entry, function(track)
		if track == want then
			if not track.IsPlaying then
				track:Play(fade)
			end
			-- Undo any freeze. The frozen-walk idle path parks a walk variant at
			-- speed 0; without this it would still be frozen the next time that
			-- same variant is the one picked to walk with.
			track:AdjustSpeed(1)
		elseif track.IsPlaying then
			track:Stop(fade)
		end
	end)
end

RunService.Heartbeat:Connect(function(dt)
	local step = math.max(dt, 1 / 240)
	local clampMin, clampMax = Anims.SPEED_CLAMP.min, Anims.SPEED_CLAMP.max

	for model, entry in tracked do
		if not model.Parent or not entry.root.Parent then
			cleanup(model)
			continue
		end

		-- A corpse holds its death pose; ragdoll physics must not restart the
		-- walk cycle just because the body is still sliding to a stop.
		if entry.dead then
			continue
		end

		local pos = entry.root.Position
		local delta = pos - entry.lastPos
		local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / step
		entry.lastPos = pos

		if speed <= Anims.WALK_THRESHOLD then
			-- A pose is an idle variant, not a separate mode: a unit only adopts
			-- one once it has actually STOPPED. That's what makes the campfire and
			-- the workbench work without any hand-off — the unit walks in, stops,
			-- and settles; the moment it's ordered away it's moving again and
			-- simply walks.
			--
			-- An unknown pose name, or one whose clip isn't authored yet, has no
			-- pool and falls through to the ordinary idle.
			local pose = entry.poseName
			local posed = pose ~= nil and entry.poses[pose] ~= nil
			setState(entry, if posed then pose :: string else "idle")
			continue
		end

		-- Run only when the SERVER says to (charging, or hurrying to the Keep) and
		-- a run cycle actually exists. A rig with no run animation time-scales its
		-- walk instead, which reads fine and avoids a missing-asset gap.
		local running = entry.wantsRun and #entry.runs > 0
		setState(entry, if running then "run" else "walk")

		-- Scale only the variant setState actually chose. Scaling the whole pool
		-- would be wasted work on tracks that aren't playing.
		local active = entry.current
		if active then
			active:AdjustSpeed(math.clamp(speed / entry.walkBaseSpeed, clampMin, clampMax))
		end
	end
end)

local watchedFolder: Instance? = nil

local function watchUnitsFolder(units: Instance)
	if watchedFolder == units then
		return
	end
	-- Rebinding: drop the old folder's connections so they can't leak.
	for _, conn in folderConns do
		conn:Disconnect()
	end
	table.clear(folderConns)
	watchedFolder = units

	for _, child in units:GetChildren() do
		if child:IsA("Model") then
			task.defer(setupUnit, child)
		end
	end
	table.insert(
		folderConns,
		units.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				-- Defer a frame so a freshly-cloned unit's Humanoid/parts exist.
				-- If they don't, setupUnit parks it in `pending` and retries.
				task.defer(setupUnit, child)
			end
		end)
	)
	table.insert(folderConns, units.ChildRemoved:Connect(cleanup))
	AnimDebug:info("UnitAnimator watching workspace.Units")
end

function UnitAnimator.stop()
	for _, conn in folderConns do
		conn:Disconnect()
	end
	table.clear(folderConns)
	watchedFolder = nil
	for model in tracked do
		cleanup(model)
	end
	for model in pending do
		clearPending(model)
	end
end

-- Watch for the folder INDEFINITELY, and re-bind if it is ever replaced.
--
-- The previous `WaitForChild("Units", 30)` was the main reason units weren't
-- animating: the client boots into the main menu, workspace.Units isn't created
-- until the first unit of a match spawns, and any lobby that took longer than
-- 30 seconds left the animator permanently idle for the whole session. Whether
-- it worked came down to how fast you clicked Play.
do
	local existing = Workspace:FindFirstChild("Units")
	if existing then
		watchUnitsFolder(existing)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Units" and child:IsA("Folder") then
			watchUnitsFolder(child)
		end
	end)
end

return UnitAnimator


