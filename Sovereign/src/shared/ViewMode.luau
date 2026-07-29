--!strict
-- ViewMode: the single source of truth for which of the game's two views the
-- LOCAL PLAYER is currently in, plus the hero-camera aim substate.
--
-- ---------------------------------------------------------------------------
-- WHY THIS MODULE EXISTS
-- ---------------------------------------------------------------------------
-- Before this, every system that needed to know "is the player driving his Lord
-- right now?" asked `player.CameraMode == Enum.CameraMode.LockFirstPerson`
-- (SelectionManager, PlacementController, FirstPersonCombat, ...). That was a
-- proxy, not a fact, and it broke the moment hero mode became THIRD person:
-- `CameraMode` is `Classic` in third person, so every one of those checks would
-- silently report "player is in RTS" while the player was swinging a sword.
--
-- Everything now reads this module instead. It is deliberately dumb: it holds
-- state, validates transitions, and fires signals. The camera owns writing to
-- it; everyone else only reads.
--
-- ---------------------------------------------------------------------------
-- CLIENT-ONLY STATE
-- ---------------------------------------------------------------------------
-- This lives in ReplicatedStorage.Shared only so any client script — under
-- StarterPlayerScripts.Client OR StarterPlayerScripts.UI — can require it by an
-- absolute path. It is NOT replicated and the server must never require it: the
-- server's authoritative view of a player's mode is the `PlayerFighter`
-- attribute plus the "ViewModeChanged" remote, not this table.
--
-- ---------------------------------------------------------------------------
-- WIRE PROTOCOL
-- ---------------------------------------------------------------------------
-- Client -> server: GameEvent:FireServer("CameraModeChanged", <"RTS"|"Hero">)
-- Server -> client: GameEvent:FireClient(p, "CameraModeChanged", <"RTS"|"Hero">)
-- The legacy value "King" is still accepted on both ends and normalized to
-- "Hero" (older HUD builds and saved test scripts still send it).

local ViewMode = {}

export type Mode = "RTS" | "Hero"
-- "Locked" = shift-lock: mouse is captured at screen centre, the Lord faces
-- wherever the camera looks, crosshair is live. This is the combat posture.
-- "Free"   = mouse is released and orbits the camera without turning the Lord.
--            For looking at your army / showing the character off.
export type AimMode = "Locked" | "Free"

ViewMode.Modes = {
	RTS = "RTS" :: Mode,
	Hero = "Hero" :: Mode,
}

ViewMode.AimModes = {
	Locked = "Locked" :: AimMode,
	Free = "Free" :: AimMode,
}

-- ---------------------------------------------------------------------------
-- MINIMAL SIGNAL
-- ---------------------------------------------------------------------------
-- A plain-table signal rather than a BindableEvent: listeners here fire on the
-- camera's hot path, and a BindableEvent would deep-copy every argument and
-- defer the call to a fresh coroutine. Callers get synchronous, allocation-free
-- notification. Errors in one listener must not stop the others (a throwing HUD
-- listener used to abort the mode switch half-applied), so each is pcall'd.

type Listener<T...> = (T...) -> ()

export type Signal<T...> = {
	connect: (self: Signal<T...>, listener: Listener<T...>) -> () -> (),
	fire: (self: Signal<T...>, T...) -> (),
}

local function createSignal<T...>(name: string): Signal<T...>
	local listeners: { Listener<T...> } = {}
	local signal = {}

	function signal:connect(listener: Listener<T...>): () -> ()
		table.insert(listeners, listener)
		-- Returns a disconnect closure. Idempotent: calling it twice is a no-op,
		-- so a Janitor can safely clean up a already-disconnected listener.
		local disconnected = false
		return function()
			if disconnected then
				return
			end
			disconnected = true
			local index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end
	end

	function signal:fire(...: T...)
		-- Iterate a snapshot: a listener is allowed to disconnect itself (or
		-- another listener) from inside the callback without shifting the array
		-- out from under this loop.
		local snapshot = table.clone(listeners)
		for _, listener in ipairs(snapshot) do
			local ok, err = pcall(listener, ...)
			if not ok then
				warn(`[ViewMode] {name} listener errored: {err}`)
			end
		end
	end

	return (signal :: any) :: Signal<T...>
end

-- Fired AFTER the mode has changed. (newMode, previousMode)
ViewMode.Changed = createSignal("Changed") :: Signal<Mode, Mode>
-- Fired when the hero aim posture changes. (newAimMode, previousAimMode)
ViewMode.AimChanged = createSignal("AimChanged") :: Signal<AimMode, AimMode>
-- Fired when a mode transition starts/finishes. (isTransitioning)
ViewMode.TransitionChanged = createSignal("TransitionChanged") :: Signal<boolean>

-- ---------------------------------------------------------------------------
-- TOGGLE REQUESTS (UI -> camera)
-- ---------------------------------------------------------------------------
-- The HUD is a React tree living under StarterPlayerScripts.UI, while the camera
-- lives under StarterPlayerScripts.Client. Neither can `require` the other by a
-- relative path, and having the UI reach across into the camera controller would
-- couple a view to a system it has no business owning.
--
-- So the on-screen buttons don't call the camera — they raise a request here and
-- the camera controller, which is already the only writer of this module, decides
-- whether to honour it. Same path as a keypress, so the button and the V key
-- cannot drift apart in behaviour.
--
-- This is also what makes the two views reachable with no keyboard at all, which
-- is the entire mobile story.
ViewMode.ToggleRequested = createSignal("ToggleRequested") :: Signal<()>
ViewMode.FirstPersonToggleRequested = createSignal("FirstPersonToggleRequested") :: Signal<()>

--- Ask the camera to switch views. Safe to call from anywhere, including the UI
--- tree. A no-op if the camera is not yet listening (pre-GameStarted), which is
--- the correct behaviour — there is nothing to switch to yet.
function ViewMode.requestToggle()
	ViewMode.ToggleRequested:fire()
end

--- Ask the hero camera to flip between third and first person. Ignored by the
--- camera unless the player is actually in hero view.
function ViewMode.requestFirstPersonToggle()
	ViewMode.FirstPersonToggleRequested:fire()
end

-- ---------------------------------------------------------------------------
-- HERO ACTION REQUESTS (touch UI -> HeroCombatController)
-- ---------------------------------------------------------------------------
-- Same reasoning as ToggleRequested above, for the same reason: the on-screen
-- combat buttons live in the React tree under StarterPlayerScripts.UI and the
-- combat controller lives under StarterPlayerScripts.Client. Neither can require
-- the other by a relative path.
--
-- So the touch buttons do NOT implement combat. They raise an action request
-- here and HeroCombatController routes it into the SAME sendLight/sendHeavy/
-- sendBlock/sendDodge/sendRanged functions the mouse and keyboard call. That is
-- deliberate: the client-side cooldown mirror and the canFight() gate then apply
-- identically on both, and touch cannot drift away from desktop feel — there is
-- only one implementation of each action to drift from.
--
-- "Attack" is the tap-vs-hold trigger and is the direct analogue of LMB: Begin
-- starts the hold timer, End resolves it as a light (released early) or does
-- nothing (the heavy already committed at the threshold). The UI never decides
-- which one happened; the controller does, with the same clock desktop uses.
export type HeroAction = "Attack" | "Light" | "Heavy" | "Block" | "Dodge" | "Ranged"
-- Two-phase because Block is hold-to-guard: a Begin with no matching End leaves
-- the server-side hero guarding forever (see the stuck-block notes in
-- HeroTouchControls and HeroCombatController).
export type ActionPhase = "Begin" | "End"

ViewMode.HeroActions = {
	Attack = "Attack" :: HeroAction,
	Light = "Light" :: HeroAction,
	Heavy = "Heavy" :: HeroAction,
	Block = "Block" :: HeroAction,
	Dodge = "Dodge" :: HeroAction,
	Ranged = "Ranged" :: HeroAction,
}

ViewMode.ActionPhases = {
	Begin = "Begin" :: ActionPhase,
	End = "End" :: ActionPhase,
}

ViewMode.HeroActionRequested = createSignal("HeroActionRequested") :: Signal<HeroAction, ActionPhase>

local VALID_HERO_ACTIONS: { [string]: boolean } = {
	Attack = true,
	Light = true,
	Heavy = true,
	Block = true,
	Dodge = true,
	Ranged = true,
}

--- Ask the hero combat controller to perform an action. `phase` defaults to
--- "Begin"; only Block (and Attack's hold) care about "End".
--- A no-op if the controller is not listening, which is correct: with no
--- controller there is nothing to swing.
function ViewMode.requestHeroAction(action: HeroAction, phase: ActionPhase?)
	if not VALID_HERO_ACTIONS[action :: string] then
		warn(`[ViewMode] refusing unknown hero action: {tostring(action)}`)
		return
	end
	local resolved: ActionPhase = if phase == "End" then "End" else "Begin"
	ViewMode.HeroActionRequested:fire(action, resolved)
end

-- ---------------------------------------------------------------------------
-- HERO COMBAT STATUS MIRROR (HeroCombatController -> touch UI)
-- ---------------------------------------------------------------------------
-- The desktop crosshair dims itself from HeroCombatController's predicted
-- cooldown state. The touch buttons must dim from the EXACT SAME numbers or the
-- two readouts disagree about whether a swing is legal — the classic "the button
-- looks ready but nothing happens" bug.
--
-- This is a plain mutable table rather than a signal on purpose: the controller
-- refreshes it every render step, and firing a signal at 60fps into a React tree
-- would re-render the HUD every frame. Consumers poll it and re-render only when
-- a derived boolean actually flips. The fields are mutated IN PLACE so the
-- per-frame write allocates nothing.
--
-- All timestamps are `os.clock()` values. This is a MIRROR of a prediction, not
-- authority — never gate anything that matters on it.
export type HeroStatus = {
	busyUntil: number, -- no action is legal until this time (state.nextActionAt)
	dodgeReadyAt: number,
	rangedReadyAt: number,
	blocking: boolean,
	comboIndex: number,
	canFight: boolean, -- the controller's own canFight() result
}

local heroStatus: HeroStatus = {
	busyUntil = 0,
	dodgeReadyAt = 0,
	rangedReadyAt = 0,
	blocking = false,
	comboIndex = 0,
	canFight = false,
}

--- Controller only. Called once per render step; mutates in place.
function ViewMode.setHeroStatus(
	busyUntil: number,
	dodgeReadyAt: number,
	rangedReadyAt: number,
	blocking: boolean,
	comboIndex: number,
	canFight: boolean
)
	heroStatus.busyUntil = busyUntil
	heroStatus.dodgeReadyAt = dodgeReadyAt
	heroStatus.rangedReadyAt = rangedReadyAt
	heroStatus.blocking = blocking
	heroStatus.comboIndex = comboIndex
	heroStatus.canFight = canFight
end

--- Read-only for everyone but the controller. Returns the live table; do not
--- hold a reference expecting a snapshot, and do not write to it.
function ViewMode.getHeroStatus(): HeroStatus
	return heroStatus
end

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------

local currentMode: Mode = "RTS"
local currentAim: AimMode = "Locked"
-- True while the camera is blending between the two views. Input consumers MUST
-- ignore clicks while this is true: mid-blend the camera CFrame does not match
-- either view, so a raycast from the mouse lands somewhere the player never
-- aimed at (this is how "I pressed V and my army walked into the sea" happens).
local transitioning = false
-- True while a building placement ghost is on screen and owning the mouse.
--
-- WHY THIS LIVES HERE: PlacementController binds MouseButton2 to "cancel the
-- ghost" and MovementManager binds MouseButton2 to "issue an order". Both are
-- plain UserInputService.InputBegan listeners, so one right-click ran BOTH — the
-- ghost vanished and the selected army simultaneously marched to wherever the
-- cursor happened to be. Neither module can require the other (PlacementController
-- is a client script, and a Placement -> Movement require would close a cycle
-- through SelectionManager), but both already require ViewMode. It is the
-- client's input-state hub, so the flag belongs on it.
--
-- DANGER: a stuck-true value silently disables ALL RTS orders and selection,
-- which is far worse than the double-fire it fixes. PlacementController must
-- therefore funnel every write through a single setter that also clears on
-- cancel, successful place, error and character death — see setPlacing() there.
local placementActive = false

-- ---------------------------------------------------------------------------
-- READS (safe from anywhere)
-- ---------------------------------------------------------------------------

function ViewMode.get(): Mode
	return currentMode
end

function ViewMode.isRTS(): boolean
	return currentMode == "RTS"
end

function ViewMode.isHero(): boolean
	return currentMode == "Hero"
end

function ViewMode.getAimMode(): AimMode
	return currentAim
end

--- True only when the player is actively driving the Lord with a locked
--- crosshair — i.e. the exact condition under which hero attack input is legal.
function ViewMode.isCombatReady(): boolean
	return currentMode == "Hero" and currentAim == "Locked" and not transitioning
end

function ViewMode.isTransitioning(): boolean
	return transitioning
end

--- True while a building placement ghost is active. Read by any RTS input
--- handler that must not act while the mouse belongs to the ghost.
function ViewMode.isPlacementActive(): boolean
	return placementActive
end

--- The check that replaces every old `player.CameraMode == LockFirstPerson`
--- guard in RTS input handlers: "should I ignore this click?".
---
--- Placement is folded in here rather than bolted onto each caller so that every
--- handler already honouring this guard (SelectionManager's box-select and
--- MovementManager's right-click order dispatcher) is covered by construction.
--- During placement the mouse belongs to the ghost: LMB places, RMB cancels, and
--- neither may also select units or issue a move order.
function ViewMode.shouldBlockRTSInput(): boolean
	return currentMode ~= "RTS" or transitioning or placementActive
end

-- ---------------------------------------------------------------------------
-- WRITES (camera only)
-- ---------------------------------------------------------------------------

--- Accepts the legacy "King" spelling so an older client script or a saved
--- Studio test command can't put the state machine into an unknown mode.
function ViewMode.normalize(value: any): Mode?
	if value == "RTS" then
		return "RTS"
	elseif value == "Hero" or value == "King" then
		return "Hero"
	end
	return nil
end

--- Set the current mode. Returns true if the mode actually changed. Only the
--- camera controller should call this; it fires Changed synchronously.
function ViewMode.set(mode: Mode): boolean
	if mode ~= "RTS" and mode ~= "Hero" then
		warn(`[ViewMode] refusing unknown mode: {tostring(mode)}`)
		return false
	end
	if mode == currentMode then
		return false
	end
	local previous = currentMode
	currentMode = mode
	ViewMode.Changed:fire(mode, previous)
	return true
end

function ViewMode.setAimMode(aim: AimMode): boolean
	if aim ~= "Locked" and aim ~= "Free" then
		warn(`[ViewMode] refusing unknown aim mode: {tostring(aim)}`)
		return false
	end
	if aim == currentAim then
		return false
	end
	local previous = currentAim
	currentAim = aim
	ViewMode.AimChanged:fire(aim, previous)
	return true
end

--- Placement controllers only. Idempotent and deliberately signal-free: this is
--- polled by input handlers on the click path, never subscribed to, so there is
--- no listener that can throw and leave the flag half-applied.
function ViewMode.setPlacementActive(value: boolean)
	placementActive = value == true
end

function ViewMode.setTransitioning(value: boolean)
	local next_ = value == true
	if next_ == transitioning then
		return
	end
	transitioning = next_
	ViewMode.TransitionChanged:fire(next_)
end

return ViewMode
