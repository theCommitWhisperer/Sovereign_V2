--!strict
-- StudioCameraController: owns Camera.CFrame in BOTH of the game's views.
--
--   RTS  — overhead Studio-style rig (CameraRig + CameraAnimator + BoundsManager),
--          WASD pans the camera, character controls are OFF.
--   Hero — third-person over-the-shoulder camera (HeroCamera), WASD drives the
--          Lord, character controls are ON.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHY THE CAMERA IS SCRIPTABLE IN BOTH VIEWS
-- ═══════════════════════════════════════════════════════════════════════════
-- The previous "King mode" handed the camera back to Roblox's default camera
-- module (CameraType = Custom + player.CameraMode = LockFirstPerson). Two owners
-- of CameraType/MouseBehaviour/zoom clamps meant any yield or error between the
-- four property writes left the player in a state that was neither view — the
-- "stuck half-toggled" bug. Now:
--   * CameraType stays Scriptable forever (re-asserted every frame in
--     _EnsureCamera, which is the single guard that makes a half-applied toggle
--     impossible),
--   * player.CameraMode stays Classic forever and is NOT a mode signal — hero
--     view is third person, so it would read Classic either way. ViewMode is the
--     signal,
--   * because we own the CFrame in both views we can blend continuously between
--     them, which is what makes the flip feel like one camera and not two.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE TRANSITION IS A STRUCT, NOT A TWEEN
-- ═══════════════════════════════════════════════════════════════════════════
-- `self.transition` is advanced by hand inside Update. Deliberately not
-- TweenService and deliberately not a task.wait loop: the headline requirement
-- is that the player can flip views "on a whim", so a second toggle 100ms into a
-- 350ms blend must retarget the SAME blend from wherever the camera currently
-- is. A Tween owns the property for its whole duration and a wait-loop cannot be
-- interrupted cleanly; both produce dropped input or double-fires.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputHandler = require(script.Parent.InputHandler)
local DesktopInput = require(script.Parent.DesktopInput)
local MobileInput = require(script.Parent.MobileInput)
local CameraRig = require(script.Parent.CameraRig)
local CameraAnimator = require(script.Parent.CameraAnimator)
local BoundsManager = require(script.Parent.BoundsManager)
local KeybindingsManager = require(script.Parent.KeybindingsManager)
local HeroCamera = require(script.Parent.HeroCamera)

local ViewMode = require(ReplicatedStorage.Shared.ViewMode)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local CameraDebug = DebugManager.createChannel("StudioCamera", false)

-- Mirrors ViewMode.Modes so this file never invents a third spelling. The legacy
-- "King" string lives only in ViewMode.normalize now.
local CameraMode = {
	RTS = ViewMode.Modes.RTS,
	Hero = ViewMode.Modes.Hero,
}

-- Streaming is centered on the player's character by default, while an RTS
-- camera can travel hundreds of studs away from that character. Request the
-- current camera region at a measured rate so map panning never exposes an
-- unloaded play area.
local STREAM_REQUEST_INTERVAL = 1.0
local STREAM_MOVE_THRESHOLD = 48

local TRANSITION_DURATION = 0.35
-- Only long enough to swallow OS key-repeat and a duplicate InputBegan. The old
-- 0.25s debounce silently ate any second press inside the blend, which is
-- exactly the input this system is supposed to honour.
local TOGGLE_DEBOUNCE = 0.08
-- How long a "I pressed the toggle while dead" latch stays armed.
local PENDING_HERO_TIMEOUT = 8
-- The server stamps IsKing/CanFirstPerson shortly AFTER CharacterAdded
-- replicates, so the latch polls rather than refusing on the first frame.
local PENDING_HERO_POLL_INTERVAL = 0.25

type Transition = {
	from: CFrame,
	-- Last solved destination CFrame. The destination view keeps moving during
	-- the blend (the Lord runs, the rig pans), so this is refreshed every frame
	-- and the blend chases a live target instead of a stale snapshot.
	to: CFrame,
	elapsed: number,
	duration: number,
	target: ViewMode.Mode,
}

type Fields = {
	-- InputHandler / DesktopInput / MobileInput / CameraRig / CameraAnimator /
	-- BoundsManager predate the typed-class pattern and export no instance type.
	-- `any` here is deliberate: inventing structural types for them in this file
	-- would silently drift from the real modules (which this refactor does not
	-- own), and `typeof(X.new(...))` needs dummy arguments for the two that take
	-- a constructor parameter. Every method call on them below is a real method
	-- on those modules.
	inputHandler: any,
	desktopInput: any,
	mobileInput: any,
	cameraRig: any,
	animator: any,
	boundsManager: any,

	heroCamera: HeroCamera.HeroCamera,

	enabled: boolean,
	-- The COMMITTED mode: set the instant a switch is accepted, before the blend
	-- runs. So `currentMode` always names the view the player last asked for and
	-- a mid-blend retoggle needs no extra bookkeeping.
	currentMode: ViewMode.Mode,
	transition: Transition?,
	controlsModule: any,

	lastStreamRequest: number,
	lastStreamedFocus: Vector3?,
	lastToggleTime: number,

	-- Set when a hero toggle arrived while there was nothing living to control.
	pendingHeroOnSpawn: boolean,
	pendingHeroDeadline: number,

	player: Player,
	camera: Camera,
	-- Cached at construction. The old code did WaitForChild("RemoteEvents") on
	-- every toggle, i.e. a potential yield in the middle of a state transition,
	-- which is precisely how a half-applied state happens.
	gameEvent: RemoteEvent?,

	connections: { RBXScriptConnection },
	-- Mode-scoped connections (death / removal watchers while in Hero view);
	-- always disconnected on every mode switch so nothing leaks.
	modeConnections: { RBXScriptConnection },
}

export type StudioCameraController = typeof(setmetatable({} :: Fields, {} :: StudioCameraControllerImpl))

type StudioCameraControllerImpl = {
	__index: StudioCameraControllerImpl,

	new: () -> StudioCameraController,
	Initialize: (self: StudioCameraController, startPosition: Vector3) -> (),
	Update: (self: StudioCameraController, deltaTime: number) -> (),
	Disable: (self: StudioCameraController) -> (),
	Destroy: (self: StudioCameraController) -> (),

	SwitchToHero: (self: StudioCameraController) -> boolean,
	SwitchToKing: (self: StudioCameraController) -> boolean,
	SwitchToRTS: (self: StudioCameraController) -> (),
	ToggleCameraMode: (self: StudioCameraController) -> (),
	GetCurrentMode: (self: StudioCameraController) -> ViewMode.Mode,
	IsHeroMode: (self: StudioCameraController) -> boolean,

	SetHeroAimMode: (self: StudioCameraController, aim: ViewMode.AimMode) -> (),
	ToggleHeroFirstPerson: (self: StudioCameraController) -> (),
	GetHeroCamera: (self: StudioCameraController) -> HeroCamera.HeroCamera,

	HandleInputEvent: (self: StudioCameraController, event: InputHandler.InputEvent) -> (),
	RequestStreamingAroundFocus: (self: StudioCameraController) -> (),
	FocusOnPoint: (self: StudioCameraController, position: Vector3, distance: number?) -> (),
	FocusOnPart: (self: StudioCameraController, part: BasePart) -> (),
	ResetCamera: (self: StudioCameraController, position: Vector3?) -> (),

	SetBounds: (self: StudioCameraController, bounds: any) -> (),
	SetBoundsFromPart: (self: StudioCameraController, part: BasePart, padding: number?) -> (),
	ClearBounds: (self: StudioCameraController) -> (),
	SyncKeybindings: (self: StudioCameraController) -> (),
	ClearModeConnections: (self: StudioCameraController) -> (),

	_EnsureCamera: (self: StudioCameraController) -> Camera,
	_BeginTransition: (self: StudioCameraController, target: ViewMode.Mode) -> (),
	_CommitMode: (self: StudioCameraController, mode: ViewMode.Mode) -> (),
	_NotifyServer: (self: StudioCameraController, mode: ViewMode.Mode) -> (),
	_ResolveGameEvent: (self: StudioCameraController) -> (),
	_CheckHeroEligibility: (self: StudioCameraController) -> (boolean, string, Model?),
	_LatchHeroOnSpawn: (self: StudioCameraController, reason: string) -> (),
	_OnCharacterAdded: (self: StudioCameraController, character: Model) -> (),
	_AttachHeroWatchers: (self: StudioCameraController, character: Model) -> (),
	_EnsureControls: (self: StudioCameraController) -> boolean,
	_SetCharacterControlsEnabled: (self: StudioCameraController, enabled: boolean) -> (),
}

--- Which keybinding actions the RTS DesktopInput module should mirror. Hero
--- actions are consumed by HeroCamera / the hero combat controller; forwarding
--- them would ask the RTS rig to pan on a dodge roll. ResetCamera and
--- ToggleCameraMode are handled by CameraController.client directly.
local function shouldForwardToDesktopInput(action: KeybindingsManager.KeybindingAction): boolean
	if action == "ResetCamera" or action == "ToggleCameraMode" then
		return false
	end
	return not KeybindingsManager.IsHeroAction(action)
end

--- Ease-out cubic. Hand-rolled so the blend can be evaluated at an arbitrary
--- alpha the same frame it is retargeted.
local function easeOut(alpha: number): number
	local inverse = 1 - alpha
	return 1 - inverse * inverse * inverse
end

local StudioCameraController = {} :: StudioCameraControllerImpl
StudioCameraController.__index = StudioCameraController

function StudioCameraController.new(): StudioCameraController
	local inputHandler = InputHandler.new()

	local fields: Fields = {
		inputHandler = inputHandler,
		desktopInput = DesktopInput.new(inputHandler),
		mobileInput = MobileInput.new(inputHandler),
		cameraRig = CameraRig.new(),
		animator = nil,
		boundsManager = BoundsManager.new(),

		heroCamera = HeroCamera.new(),

		enabled = false,
		currentMode = CameraMode.RTS,
		transition = nil,
		controlsModule = nil,

		lastStreamRequest = 0,
		lastStreamedFocus = nil,
		lastToggleTime = 0,

		pendingHeroOnSpawn = false,
		pendingHeroDeadline = 0,

		player = Players.LocalPlayer,
		camera = Workspace.CurrentCamera :: Camera,
		gameEvent = nil,

		connections = {},
		modeConnections = {},
	}
	fields.animator = CameraAnimator.new(fields.cameraRig)

	local self = setmetatable(fields, StudioCameraController)

	self.inputHandler:SetDesktopInput(self.desktopInput)
	self.inputHandler:SetMobileInput(self.mobileInput)

	self.inputHandler:OnInputEvent(function(event: InputHandler.InputEvent)
		self:HandleInputEvent(event)
	end)

	self:_ResolveGameEvent()
	self:SyncKeybindings()

	CameraDebug:info("StudioCameraController created")

	return self
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ═══════════════════════════════════════════════════════════════════════════

function StudioCameraController.Initialize(self: StudioCameraController, startPosition: Vector3)
	if self.enabled then
		return
	end

	self.enabled = true
	self.currentMode = CameraMode.RTS
	ViewMode.set(CameraMode.RTS)
	ViewMode.setTransitioning(false)

	self.cameraRig:Initialize(startPosition)

	local camera = self:_EnsureCamera()
	camera.CameraSubject = nil

	-- Classic, permanently. LockFirstPerson would hand control to the default
	-- camera module; hero view is third person and drives itself.
	self.player.CameraMode = Enum.CameraMode.Classic
	-- Reset once, in case an older build left the first-person 0.5/0.5 clamps
	-- behind on this player. Never touched again for mode purposes.
	self.player.CameraMinZoomDistance = 0.5
	self.player.CameraMaxZoomDistance = 128

	self.inputHandler:Enable()

	-- RTS view owns WASD for camera panning, so the default character controls
	-- must start disabled or the Lord wanders while the player pans. Spawned
	-- because PlayerModule may not have replicated yet — this is the one place a
	-- yield is safe, since it is not inside a state transition.
	task.spawn(function()
		local playerScripts = self.player:WaitForChild("PlayerScripts", 20)
		if playerScripts then
			playerScripts:WaitForChild("PlayerModule", 20)
		end
		if self.enabled and self.currentMode == CameraMode.RTS then
			self:_SetCharacterControlsEnabled(false)
		end
	end)

	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(deltaTime: number)
			self:Update(deltaTime)
		end)
	)

	-- Re-acquire the character across respawns / Lord replacement.
	table.insert(
		self.connections,
		self.player.CharacterAdded:Connect(function(character: Model)
			self:_OnCharacterAdded(character)
		end)
	)

	CameraDebug:info("StudioCameraController initialized", {
		startPosition = startPosition,
		isMobile = self.inputHandler:IsMobile(),
		isDesktop = self.inputHandler:IsDesktop(),
	})
end

function StudioCameraController.Disable(self: StudioCameraController)
	if not self.enabled then
		return
	end

	self.enabled = false
	self.pendingHeroOnSpawn = false
	self.transition = nil

	self.heroCamera:Disable()
	self.inputHandler:Disable()

	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
	self:ClearModeConnections()

	-- Leave the shared contract in a sane resting state; a consumer that outlives
	-- the camera must not be told the player is still driving a Lord.
	self.currentMode = CameraMode.RTS
	ViewMode.setTransitioning(false)
	ViewMode.set(CameraMode.RTS)

	CameraDebug:info("StudioCameraController disabled")
end

function StudioCameraController.Destroy(self: StudioCameraController)
	self:Disable()

	self.heroCamera:Destroy()
	self.inputHandler:Destroy()
	self.desktopInput:Destroy()
	self.mobileInput:Destroy()
	self.animator:Destroy()

	CameraDebug:info("StudioCameraController destroyed")
end

function StudioCameraController.ClearModeConnections(self: StudioCameraController)
	for _, connection in ipairs(self.modeConnections) do
		connection:Disconnect()
	end
	self.modeConnections = {}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PER-FRAME
-- ═══════════════════════════════════════════════════════════════════════════

function StudioCameraController.Update(self: StudioCameraController, deltaTime: number)
	if not self.enabled then
		return
	end

	local camera = self:_EnsureCamera()
	local targetCFrame: CFrame

	if self.currentMode == CameraMode.Hero then
		local heroCFrame = self.heroCamera:Update(deltaTime)
		if not heroCFrame then
			-- Backup guard; the Died/AncestryChanged watchers are primary. Being
			-- unable to solve the hero view must never leave us stuck in it.
			CameraDebug:warn("Hero character is gone - returning to RTS view")
			self:SwitchToRTS()
			return
		end
		targetCFrame = heroCFrame
	else
		self.animator:Update(deltaTime)

		if self.boundsManager.enabled then
			local currentFocal = self.cameraRig:GetFocalPoint()
			local clampedFocal =
				self.boundsManager:SoftClampPosition(currentFocal, self.animator:GetDampingFactor())
			if clampedFocal ~= currentFocal then
				self.cameraRig:SetFocalPoint(clampedFocal)
			end
		end

		-- The rig writes Camera.CFrame itself; read it straight back as this
		-- view's solved target. If a transition is running we overwrite it below,
		-- which is free because RenderStepped runs before the frame is drawn.
		self.cameraRig:UpdateCamera()
		self:RequestStreamingAroundFocus()
		targetCFrame = camera.CFrame
	end

	local transition = self.transition
	if not transition then
		camera.CFrame = targetCFrame
		return
	end

	transition.to = targetCFrame
	transition.elapsed += deltaTime

	local alpha = if transition.duration > 0
		then math.clamp(transition.elapsed / transition.duration, 0, 1)
		else 1
	if alpha >= 1 then
		camera.CFrame = targetCFrame
		self.transition = nil
		-- Only now is the camera actually looking through the destination view,
		-- so only now may click-to-order and hero attacks trust a screen ray.
		ViewMode.setTransitioning(false)
	else
		camera.CFrame = transition.from:Lerp(targetCFrame, easeOut(alpha))
	end
end

function StudioCameraController._EnsureCamera(self: StudioCameraController): Camera
	local current = Workspace.CurrentCamera
	if current and current ~= self.camera then
		-- Respawns and some CoreGui flows replace CurrentCamera outright; holding
		-- the stale reference is how the view "freezes" after a death.
		self.camera = current
		CameraDebug:info("CurrentCamera was replaced - rebound")
	end

	local camera = self.camera
	-- The one guard that makes a half-applied toggle impossible: whatever else
	-- happens, this camera is ours in both views.
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	return camera
end

function StudioCameraController.RequestStreamingAroundFocus(self: StudioCameraController)
	if not Workspace.StreamingEnabled then
		return
	end

	local now = time()
	if now - self.lastStreamRequest < STREAM_REQUEST_INTERVAL then
		return
	end

	local focus = self.cameraRig:GetFocalPoint()
	local flatFocus = Vector3.new(focus.X, 0, focus.Z)
	local lastFocus = self.lastStreamedFocus
	if lastFocus and (flatFocus - lastFocus).Magnitude < STREAM_MOVE_THRESHOLD then
		return
	end

	self.lastStreamRequest = now
	self.lastStreamedFocus = flatFocus
	task.spawn(function()
		pcall(function()
			Workspace:RequestStreamAroundAsync(focus, 0)
		end)
	end)
end

function StudioCameraController.HandleInputEvent(
	self: StudioCameraController,
	event: InputHandler.InputEvent
)
	-- Hero view routes all look/zoom input through HeroCamera's own connections;
	-- the RTS input modules are disabled there, but guard anyway so a queued
	-- event from the switch frame cannot pan the rig behind our back.
	if not self.enabled or self.currentMode ~= CameraMode.RTS then
		return
	end

	if event.Type == "Pan" and event.IsActive and event.Delta then
		self.cameraRig:Pan(event.Delta.X, event.Delta.Y)
		self.animator:CancelAnimations()
	elseif event.Type == "Rotate" and event.IsActive and event.Delta then
		self.cameraRig:Rotate(event.Delta.X, event.Delta.Y)
		self.animator:CancelAnimations()
	elseif event.Type == "Zoom" and event.IsActive and event.ZoomDelta then
		self.cameraRig:Zoom(event.ZoomDelta)
		self.animator:CancelAnimations("Focus")
	elseif event.Type == "Move" and event.IsActive and event.MoveDirection then
		self.cameraRig:Move(event.MoveDirection, 1 / 60) -- Approximate deltaTime
		self.animator:CancelAnimations()
	elseif event.Type == "Focus" and event.IsActive then
		self:FocusOnPoint(self.cameraRig:GetFocalPoint())
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MODE SWITCHING
-- ═══════════════════════════════════════════════════════════════════════════

function StudioCameraController._BeginTransition(self: StudioCameraController, target: ViewMode.Mode)
	local camera = self:_EnsureCamera()
	local from = camera.CFrame

	local existing = self.transition
	if existing then
		-- Retarget IN PLACE from wherever the blend currently is. No queueing and
		-- no second transition object: pressing the toggle three times quickly
		-- must land in the view matching the last press, never mid-flight toward
		-- the first one.
		existing.from = from
		existing.to = from
		existing.elapsed = 0
		existing.duration = TRANSITION_DURATION
		existing.target = target
	else
		self.transition = {
			from = from,
			to = from,
			elapsed = 0,
			duration = TRANSITION_DURATION,
			target = target,
		}
	end

	ViewMode.setTransitioning(true)
end

function StudioCameraController._CommitMode(self: StudioCameraController, mode: ViewMode.Mode)
	self.currentMode = mode
	-- Written BEFORE the blend finishes on purpose: ViewMode should always name
	-- the view the player asked for. Input consumers are already protected during
	-- the blend by ViewMode.isTransitioning().
	ViewMode.set(mode)
	-- Nothing in this codebase should read player.CameraMode as a mode signal any
	-- more, but keep it pinned so an older script cannot flip us to first person.
	if self.player.CameraMode ~= Enum.CameraMode.Classic then
		self.player.CameraMode = Enum.CameraMode.Classic
	end
	CameraDebug:info(`Committed view: {mode}`)
	self:_NotifyServer(mode)
end

function StudioCameraController.SwitchToHero(self: StudioCameraController): boolean
	if not self.enabled then
		return false
	end

	-- An explicit switch supersedes any queued one.
	self.pendingHeroOnSpawn = false

	if self.currentMode == CameraMode.Hero then
		return true
	end

	local eligible, reason, character = self:_CheckHeroEligibility()
	if not eligible or not character then
		self:_LatchHeroOnSpawn(reason)
		return false
	end

	-- ORDER MATTERS: kill RTS input first. DesktopInput:Disable() writes
	-- MouseBehavior = Default, so running it after HeroCamera:Enable would
	-- immediately clobber the shift-lock we just engaged.
	self.inputHandler:Disable()
	self.animator:CancelAnimations()

	if not self.heroCamera:Enable(character) then
		-- Roll all the way back rather than sitting with RTS input disabled and
		-- no camera driver — that is the half-toggled state in another costume.
		self.inputHandler:Enable()
		CameraDebug:warn("Hero camera refused to enable - staying in RTS view")
		return false
	end

	self:ClearModeConnections()
	-- setTransitioning(true) BEFORE ViewMode.set: _CommitMode fires ViewMode.Changed
	-- synchronously, and a listener that snapshots isTransitioning() in that
	-- callback must not see `false` while the camera is still mid-blend.
	self:_BeginTransition(CameraMode.Hero)
	self:_CommitMode(CameraMode.Hero)
	self:_SetCharacterControlsEnabled(true)
	self:_AttachHeroWatchers(character)

	return true
end

--- Deprecated: kept because older scripts and saved Studio test commands still
--- call SwitchToKing. Use SwitchToHero.
function StudioCameraController.SwitchToKing(self: StudioCameraController): boolean
	return self:SwitchToHero()
end

function StudioCameraController.SwitchToRTS(self: StudioCameraController)
	self.pendingHeroOnSpawn = false

	if self.currentMode == CameraMode.RTS then
		return
	end

	-- Drop the hero watchers first so a Died/AncestryChanged firing during the
	-- switch cannot re-enter this function.
	self:ClearModeConnections()

	-- Recenter the rig over the Lord before the blend is measured: he may have
	-- run a long way in hero view, and the blend target must be where he stands.
	local heroCharacter = self.heroCamera:GetCharacter()
	local rootPart = heroCharacter and heroCharacter:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		self.cameraRig:SetFocalPoint(rootPart.Position)
	end

	self.heroCamera:Disable()
	self:_SetCharacterControlsEnabled(false)
	self.animator:CancelAnimations()
	self.inputHandler:Enable()

	-- Transition flag first, then commit — see the note in SwitchToHero.
	self:_BeginTransition(CameraMode.RTS)
	self:_CommitMode(CameraMode.RTS)
end

function StudioCameraController.ToggleCameraMode(self: StudioCameraController)
	local now = os.clock()
	if now - self.lastToggleTime < TOGGLE_DEBOUNCE then
		return
	end
	self.lastToggleTime = now

	if self.currentMode == CameraMode.RTS then
		if self.pendingHeroOnSpawn then
			-- A second press while a hero entry is queued means "never mind". Without
			-- this the player has no way to take the request back and gets yanked
			-- into hero view several seconds later at a moment they did not choose.
			self.pendingHeroOnSpawn = false
			CameraDebug:info("Queued hero toggle cancelled by a second press")
			return
		end
		self:SwitchToHero()
	else
		self:SwitchToRTS()
	end
end

function StudioCameraController.GetCurrentMode(self: StudioCameraController): ViewMode.Mode
	return self.currentMode
end

function StudioCameraController.IsHeroMode(self: StudioCameraController): boolean
	return self.currentMode == CameraMode.Hero
end

function StudioCameraController.GetHeroCamera(self: StudioCameraController): HeroCamera.HeroCamera
	return self.heroCamera
end

function StudioCameraController.SetHeroAimMode(self: StudioCameraController, aim: ViewMode.AimMode)
	if self.currentMode ~= CameraMode.Hero then
		return
	end
	self.heroCamera:SetAimMode(aim)
end

function StudioCameraController.ToggleHeroFirstPerson(self: StudioCameraController)
	if self.currentMode ~= CameraMode.Hero then
		return
	end
	self.heroCamera:ToggleFirstPerson()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HERO ELIGIBILITY / CHARACTER LIFECYCLE
-- ═══════════════════════════════════════════════════════════════════════════

--- Returns (eligible, humanReadableReason, character). The IsKing /
--- CanFirstPerson attributes are the server's authorization gate and are still
--- honoured verbatim; only the reporting changed.
function StudioCameraController._CheckHeroEligibility(
	self: StudioCameraController
): (boolean, string, Model?)
	local character = self.player.Character
	if not character or not character.Parent then
		return false, "no character has spawned yet", nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "character has no Humanoid", nil
	end
	if humanoid.Health <= 0 then
		return false, "the Lord is dead or respawning", nil
	end

	if not (character:GetAttribute("IsKing") or character:GetAttribute("CanFirstPerson")) then
		-- Warn instead of no-op'ing: a missing attribute is a server-side bug and
		-- for months it presented as "the V key does nothing".
		return false,
			"character is not flagged IsKing/CanFirstPerson - the server has not authorized hero control",
			nil
	end

	return true, "", character
end

--- The toggle must never be silently swallowed. If the player asked for hero
--- view while dead / respawning / before the server stamped the attributes, arm
--- a latch and enter hero view as soon as a living, authorized character exists.
function StudioCameraController._LatchHeroOnSpawn(self: StudioCameraController, reason: string)
	CameraDebug:warn(`Cannot enter Hero view yet: {reason} - queued until the Lord is ready`)
	self.pendingHeroOnSpawn = true
	self.pendingHeroDeadline = os.clock() + PENDING_HERO_TIMEOUT
end

function StudioCameraController._OnCharacterAdded(self: StudioCameraController, character: Model)
	-- If we were in hero view when the previous character went away, the
	-- mode-scoped watchers already returned us to RTS; nothing to undo here.
	if not self.pendingHeroOnSpawn then
		return
	end
	if os.clock() > self.pendingHeroDeadline then
		self.pendingHeroOnSpawn = false
		return
	end

	-- A polling task, NOT part of the transition. The blend itself is never
	-- driven by task.wait (see the header) — this only waits for the server to
	-- finish stamping authorization attributes onto a freshly spawned character.
	task.spawn(function()
		local deadline = self.pendingHeroDeadline
		while os.clock() < deadline do
			if not (self.enabled and self.pendingHeroOnSpawn) then
				return
			end
			if self.currentMode ~= CameraMode.RTS then
				return
			end
			if self.player.Character ~= character then
				return -- superseded by yet another respawn
			end

			local eligible = self:_CheckHeroEligibility()
			if eligible then
				CameraDebug:info("Deferred hero toggle firing - the Lord is ready")
				self.pendingHeroOnSpawn = false
				self:SwitchToHero()
				return
			end
			task.wait(PENDING_HERO_POLL_INTERVAL)
		end

		if self.pendingHeroOnSpawn then
			self.pendingHeroOnSpawn = false
			CameraDebug:warn("Deferred hero toggle expired - the character never became eligible")
		end
	end)
end

function StudioCameraController._AttachHeroWatchers(self: StudioCameraController, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(
			self.modeConnections,
			humanoid.Died:Connect(function()
				CameraDebug:info("Lord died - returning to RTS view")
				self:SwitchToRTS()
			end)
		)
	end

	table.insert(
		self.modeConnections,
		character.AncestryChanged:Connect(function(_, parent: Instance?)
			if not parent then
				CameraDebug:info("Lord removed - returning to RTS view")
				self:SwitchToRTS()
			end
		end)
	)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLAYERMODULE CONTROLS
-- ═══════════════════════════════════════════════════════════════════════════

--- HARD-WON LESSON, do not "simplify": PlayerModule must be REQUIRED and its
--- Controls object fetched via :GetControls(). The raw ControlModule instance has
--- no Enable/Disable methods, so calling them threw and aborted the camera switch
--- half-way through — first person never engaged. Everything here is pcall'd and
--- uses FindFirstChild rather than WaitForChild, because this runs inside a state
--- transition and must not yield (Initialize does the yielding warm-up instead).
function StudioCameraController._EnsureControls(self: StudioCameraController): boolean
	if self.controlsModule then
		return true
	end

	local ok, controls = pcall(function()
		local playerScripts = self.player:FindFirstChild("PlayerScripts")
		if not playerScripts then
			return nil
		end
		local playerModule = playerScripts:FindFirstChild("PlayerModule")
		if not playerModule then
			return nil
		end
		return require(playerModule):GetControls()
	end)

	if ok and controls then
		self.controlsModule = controls
		return true
	end
	return false
end

function StudioCameraController._SetCharacterControlsEnabled(
	self: StudioCameraController,
	enabled: boolean
)
	if not self:_EnsureControls() then
		if enabled then
			CameraDebug:warn("PlayerModule controls unavailable - hero movement will not respond")
		end
		return
	end

	local controls = self.controlsModule
	local ok, err = pcall(function()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
	if not ok then
		local verb = if enabled then "Enable" else "Disable"
		CameraDebug:warn(`PlayerModule controls {verb}() failed: {err}`)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FOCUS / BOUNDS / KEYBINDINGS (unchanged behaviour)
-- ═══════════════════════════════════════════════════════════════════════════

function StudioCameraController.FocusOnPoint(
	self: StudioCameraController,
	position: Vector3,
	distance: number?
)
	self.animator:AnimateFocusOn(position, distance)
end

function StudioCameraController.FocusOnPart(self: StudioCameraController, part: BasePart)
	local size = part.Size
	local distance = math.max(size.X, size.Y, size.Z) * 2
	self:FocusOnPoint(part.Position, distance)
end

function StudioCameraController.ResetCamera(self: StudioCameraController, position: Vector3?)
	if position then
		self.cameraRig:Reset(position)
	else
		self.cameraRig:Reset()
	end
	self.animator:CancelAnimations()
end

function StudioCameraController.SetBounds(self: StudioCameraController, bounds: any)
	self.boundsManager:SetBounds(bounds)
	self.boundsManager:SetEnabled(true)
end

function StudioCameraController.SetBoundsFromPart(
	self: StudioCameraController,
	part: BasePart,
	padding: number?
)
	self.boundsManager:SetBoundsFromPart(part, padding)
	self.boundsManager:SetEnabled(true)
end

function StudioCameraController.ClearBounds(self: StudioCameraController)
	self.boundsManager:ClearBounds()
	self.boundsManager:SetEnabled(false)
end

function StudioCameraController.SyncKeybindings(self: StudioCameraController)
	local keybindings = KeybindingsManager.GetAllKeybindings()
	for action, keyCode in pairs(keybindings) do
		if shouldForwardToDesktopInput(action) then
			self.desktopInput:SetKeybinding(action, keyCode)
		end
	end

	for _, action in ipairs(KeybindingsManager.GetAllActions()) do
		if shouldForwardToDesktopInput(action) then
			KeybindingsManager.OnKeybindingChanged(action, function(keyCode: Enum.KeyCode)
				self.desktopInput:SetKeybinding(action, keyCode)
			end)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SERVER NOTIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

function StudioCameraController._ResolveGameEvent(self: StudioCameraController)
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local gameEvent = remoteEvents and remoteEvents:FindFirstChild("GameEvent")
	if gameEvent and gameEvent:IsA("RemoteEvent") then
		self.gameEvent = gameEvent
		return
	end

	-- Resolve out of band. Never WaitForChild inside a switch: a yield in the
	-- middle of a state transition is how half-applied states happen.
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("RemoteEvents", 30)
		if not folder then
			CameraDebug:warn("RemoteEvents folder never appeared - view changes will not reach the server")
			return
		end
		local resolved = folder:WaitForChild("GameEvent", 30)
		if resolved and resolved:IsA("RemoteEvent") then
			self.gameEvent = resolved
		else
			CameraDebug:warn("GameEvent remote never appeared - view changes will not reach the server")
		end
	end)
end

function StudioCameraController._NotifyServer(self: StudioCameraController, mode: ViewMode.Mode)
	local gameEvent = self.gameEvent
	if not gameEvent then
		CameraDebug:warn(`GameEvent not resolved - server was not told about the switch to {mode}`)
		return
	end
	-- Wire protocol per ViewMode: "RTS" | "Hero".
	gameEvent:FireServer("CameraModeChanged", mode)
end

return StudioCameraController
