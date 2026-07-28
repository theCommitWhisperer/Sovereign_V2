--!strict
-- HeroCamera: the third-person orbit camera for the "Hero" view.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHY THIS EXISTS AT ALL (read before "simplifying" it back)
-- ═══════════════════════════════════════════════════════════════════════════
-- The previous King mode handed the camera back to Roblox's default camera
-- module (CameraType = Custom + player.CameraMode = LockFirstPerson). That is
-- where every "stuck half-toggled" bug came from: the two systems each own
-- CameraType, MouseBehavior and the zoom clamps, and any yield or error between
-- the four property writes left the player in a state that was neither view.
--
-- This module drives the camera by hand instead. The camera stays Scriptable in
-- BOTH views forever, which means:
--   * there is exactly one writer of Camera.CFrame (StudioCameraController),
--   * we can blend continuously between the RTS rig and this camera,
--   * `player.CameraMode` is no longer a mode signal (hero view is THIRD
--     person, so it would read Classic anyway) — ViewMode is.
--
-- Note this module never writes Camera.CFrame itself. `Update` RETURNS the
-- desired CFrame and the controller decides whether to apply it straight or
-- blend it against the RTS rig mid-transition. One writer, no tug-of-war.
--
-- Character movement is still Roblox's PlayerModule ControlModule; it moves the
-- humanoid relative to workspace.CurrentCamera.CFrame, which a Scriptable
-- camera sets perfectly well, so camera-relative WASD comes for free.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ViewMode = require(ReplicatedStorage.Shared.ViewMode)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local HeroDebug = DebugManager.createChannel("HeroCamera", false)

-- ═══════════════════════════════════════════════════════════════════════════
-- TUNING
-- ═══════════════════════════════════════════════════════════════════════════

-- Radians of camera rotation per pixel of raw mouse delta. Matches roughly the
-- feel of Roblox shift-lock at default sensitivity.
local LOOK_SENSITIVITY: number = 0.0045
local MIN_PITCH: number = math.rad(-75)
local MAX_PITCH: number = math.rad(75)

-- Over-the-shoulder framing. Without the lateral offset the character's own
-- head sits exactly on the crosshair, which makes melee aiming impossible.
local SHOULDER_RIGHT: number = 2.0
-- Height above HumanoidRootPart's centre; ~eye level on a stock R15 rig.
local PIVOT_HEIGHT: number = 1.5

local LOCKED_MIN_DISTANCE: number = 6
local LOCKED_MAX_DISTANCE: number = 24
-- "Free" is the show-off-your-character posture, so it gets a wider leash.
local FREE_MIN_DISTANCE: number = 4
local FREE_MAX_DISTANCE: number = 40
local FIRST_PERSON_DISTANCE: number = 0.5
local DEFAULT_DISTANCE: number = 11
local ZOOM_STEP: number = 2.5

-- Frame-rate independent smoothing rates, used as `1 - exp(-k * dt)`. A raw
-- lerp alpha would make the camera feel different at 30 / 60 / 144 fps.
local PIVOT_SMOOTH_K: number = 16
-- Rotation is deliberately near-instant: this camera carries the combat
-- crosshair, and any perceptible lag between mouse and reticle reads as input
-- lag. k=120 is about one frame of de-jitter at 60fps, not "smoothing".
local ROTATION_SMOOTH_K: number = 120
local DISTANCE_SMOOTH_K: number = 12
-- Occlusion pulls IN instantly (never let a wall clip the near plane) and eases
-- back out slowly, so brushing a doorframe doesn't pop the camera.
local OCCLUSION_RECOVER_K: number = 6
-- Stand-off from whatever the occlusion ray hit, so the near plane clears it.
local CAMERA_SKIN: number = 0.4
local MIN_OCCLUDED_LENGTH: number = 0.2

-- The camera converges on a point this far down the look axis. Without it the
-- shoulder offset means the crosshair and the camera axis are parallel but not
-- coincident, and you can never hit what the reticle is over.
local AIM_CONVERGENCE: number = 250

-- A frame hitch (streaming, a big spawn) must not teleport the camera.
local MAX_STEP: number = 0.1

-- ═══════════════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════════════

type Fields = {
	enabled: boolean,
	character: Model?,
	humanoid: Humanoid?,
	rootPart: BasePart?,

	aimMode: ViewMode.AimMode,
	firstPerson: boolean,
	-- Distance to return to when first person is switched off.
	distanceBeforeFirstPerson: number,

	-- Raw look target, driven straight by mouse/touch.
	yaw: number,
	pitch: number,
	-- What is actually rendered this frame (raw, de-jittered).
	appliedYaw: number,
	appliedPitch: number,

	distance: number,
	targetDistance: number,
	occludedLength: number,

	smoothedPivot: Vector3,
	cameraPosition: Vector3,
	lookVector: Vector3,

	-- True for the first frame after Enable: everything snaps instead of easing
	-- in from wherever the previous session left it.
	snapNextFrame: boolean,
	-- Free-posture orbit is a drag gesture; true while the button is held.
	orbitDragActive: boolean,
	-- Touch look deltas arrive as events, mouse deltas are polled. Both land here.
	pendingLookDelta: Vector2,

	raycastParams: RaycastParams,
	connections: { RBXScriptConnection },

	-- Restored on Disable so we never leave the humanoid unable to turn.
	savedAutoRotate: boolean,
	hiddenParts: { BasePart },
	headHidden: boolean,
}

export type HeroCamera = typeof(setmetatable({} :: Fields, {} :: HeroCameraImpl))

type HeroCameraImpl = {
	__index: HeroCameraImpl,

	new: () -> HeroCamera,
	Enable: (self: HeroCamera, character: Model) -> boolean,
	Disable: (self: HeroCamera) -> (),
	Update: (self: HeroCamera, deltaTime: number) -> CFrame?,
	Destroy: (self: HeroCamera) -> (),

	SetAimMode: (self: HeroCamera, aim: ViewMode.AimMode) -> (),
	GetAimMode: (self: HeroCamera) -> ViewMode.AimMode,
	SetFirstPerson: (self: HeroCamera, firstPerson: boolean) -> (),
	ToggleFirstPerson: (self: HeroCamera) -> (),
	IsFirstPerson: (self: HeroCamera) -> boolean,
	IsEnabled: (self: HeroCamera) -> boolean,

	GetLookVector: (self: HeroCamera) -> Vector3,
	GetAimRay: (self: HeroCamera) -> (Vector3, Vector3),
	GetCameraPosition: (self: HeroCamera) -> Vector3,
	GetCharacter: (self: HeroCamera) -> Model?,

	_BindInput: (self: HeroCamera) -> (),
	_ClearConnections: (self: HeroCamera) -> (),
	_ApplyAimPosture: (self: HeroCamera) -> (),
	_RebuildRaycastFilter: (self: HeroCamera) -> (),
	_ApplyZoom: (self: HeroCamera, delta: number) -> (),
	_ClampTargetDistance: (self: HeroCamera) -> (),
	_IsMouseLookActive: (self: HeroCamera) -> boolean,
	_ApplyFirstPersonVisibility: (self: HeroCamera, hidden: boolean) -> (),
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function smoothAlpha(k: number, deltaTime: number): number
	return 1 - math.exp(-k * deltaTime)
end

--- Shortest signed angle from `from` to `to`. Without this, smoothing yaw
--- across the +/-pi seam spins the camera the long way round.
local function shortestAngle(from: number, to: number): number
	return (to - from + math.pi) % (math.pi * 2) - math.pi
end

--- The character's own head + accessories. Hidden in true first person so you
--- are not looking at the inside of your own skull.
local function collectHeadParts(character: Model): { BasePart }
	local parts: { BasePart } = {}
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		table.insert(parts, head)
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Accessory") then
			local handle = descendant:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				table.insert(parts, handle)
			end
		end
	end
	return parts
end

-- Pure-touch devices have no mouse to lock; writing MouseBehavior there is a
-- no-op at best and confuses the touch controls at worst.
local function hasMouse(): boolean
	return UserInputService.MouseEnabled
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS
-- ═══════════════════════════════════════════════════════════════════════════

local HeroCamera = {} :: HeroCameraImpl
HeroCamera.__index = HeroCamera

function HeroCamera.new(): HeroCamera
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true
	-- Decorative non-collidable props (banners, grass) must not shove the camera.
	raycastParams.RespectCanCollide = true
	raycastParams.FilterDescendantsInstances = {}

	local fields: Fields = {
		enabled = false,
		character = nil,
		humanoid = nil,
		rootPart = nil,

		aimMode = ViewMode.AimModes.Locked,
		firstPerson = false,
		distanceBeforeFirstPerson = DEFAULT_DISTANCE,

		yaw = 0,
		pitch = math.rad(-10),
		appliedYaw = 0,
		appliedPitch = math.rad(-10),

		distance = DEFAULT_DISTANCE,
		targetDistance = DEFAULT_DISTANCE,
		occludedLength = DEFAULT_DISTANCE,

		smoothedPivot = Vector3.zero,
		cameraPosition = Vector3.zero,
		lookVector = Vector3.new(0, 0, -1),

		snapNextFrame = true,
		orbitDragActive = false,
		pendingLookDelta = Vector2.zero,

		raycastParams = raycastParams,
		connections = {},

		savedAutoRotate = true,
		hiddenParts = {},
		headHidden = false,
	}

	return setmetatable(fields, HeroCamera)
end

-- ───────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ───────────────────────────────────────────────────────────────────────────

function HeroCamera.Enable(self: HeroCamera, character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	-- Split into separate guards rather than `not (a and b)` so the narrowing is
	-- unambiguous for the type checker below.
	if not humanoid then
		HeroDebug:warn("Enable refused - character has no Humanoid")
		return false
	end
	if not rootPart or not rootPart:IsA("BasePart") then
		HeroDebug:warn("Enable refused - character has no HumanoidRootPart")
		return false
	end

	-- Re-entrant safety: enabling twice (rapid toggle, respawn mid-transition)
	-- must not stack input connections or lose the saved AutoRotate value.
	if self.enabled then
		self:Disable()
	end

	self.character = character
	self.humanoid = humanoid
	self.rootPart = rootPart
	self.enabled = true
	self.firstPerson = false
	self.orbitDragActive = false
	self.pendingLookDelta = Vector2.zero
	self.snapNextFrame = true
	self.savedAutoRotate = humanoid.AutoRotate

	-- Inherit yaw from wherever the Lord is currently facing. In Locked posture
	-- the character faces the camera, so re-entering hero view after a toggle
	-- picks up exactly where it left off with no spin. Pitch persists on the
	-- instance across sessions for the same reason.
	local look = rootPart.CFrame.LookVector
	self.yaw = math.atan2(-look.X, -look.Z)
	self.appliedYaw = self.yaw
	self.appliedPitch = self.pitch

	self.targetDistance = DEFAULT_DISTANCE
	self.distance = DEFAULT_DISTANCE
	self.occludedLength = DEFAULT_DISTANCE
	self.smoothedPivot = rootPart.Position + Vector3.new(0, PIVOT_HEIGHT, 0)

	self:_RebuildRaycastFilter()
	self:_BindInput()
	-- Always enter combat-ready. Free look is a hold, not a sticky state.
	self.aimMode = ViewMode.AimModes.Locked
	ViewMode.setAimMode(ViewMode.AimModes.Locked)
	self:_ApplyAimPosture()

	HeroDebug:info("HeroCamera enabled", { character = character.Name })
	return true
end

function HeroCamera.Disable(self: HeroCamera)
	if not self.enabled then
		return
	end
	self.enabled = false

	self:_ClearConnections()
	self:_ApplyFirstPersonVisibility(false)
	self.firstPerson = false
	self.orbitDragActive = false
	self.pendingLookDelta = Vector2.zero

	-- Give the mouse back before anything else can yield. If we leaked
	-- LockCenter the player would be stuck with an invisible cursor in RTS view.
	if hasMouse() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end

	local humanoid = self.humanoid
	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = self.savedAutoRotate
	end

	self.character = nil
	self.humanoid = nil
	self.rootPart = nil
	self.hiddenParts = {}

	-- Locked is the default posture; leaving "Free" latched would make the next
	-- hero entry report isCombatReady() == false until the player tapped Alt.
	ViewMode.setAimMode(ViewMode.AimModes.Locked)
	self.aimMode = ViewMode.AimModes.Locked

	HeroDebug:info("HeroCamera disabled")
end

function HeroCamera.Destroy(self: HeroCamera)
	self:Disable()
	self:_ClearConnections()
	self.raycastParams.FilterDescendantsInstances = {}
end

function HeroCamera.IsEnabled(self: HeroCamera): boolean
	return self.enabled
end

function HeroCamera.GetCharacter(self: HeroCamera): Model?
	return self.character
end

-- ───────────────────────────────────────────────────────────────────────────
-- Input
-- ───────────────────────────────────────────────────────────────────────────

function HeroCamera._ClearConnections(self: HeroCamera)
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
end

function HeroCamera._BindInput(self: HeroCamera)
	self:_ClearConnections()

	-- Zoom. Wheel is live in both postures; the clamp in _ClampTargetDistance
	-- decides how far it may travel.
	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
			if not self.enabled or gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				self:_ApplyZoom(-input.Position.Z * ZOOM_STEP)
			end
		end)
	)

	-- FREE-POSTURE ORBIT — documented behaviour:
	-- the mouse is free (so the player can click UI / see the cursor) and the
	-- camera only orbits while middle OR right mouse is held and dragged. That
	-- is the MMO convention and it is the least surprising thing to do with a
	-- released cursor: nothing moves until you grab the world. During the drag
	-- we use LockCurrentPosition so the cursor stays put and GetMouseDelta keeps
	-- reporting (GetMouseDelta returns zero whenever the mouse is unlocked).
	local function isOrbitButton(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3
	end

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if not self.enabled or gameProcessed then
				return
			end
			if self.aimMode == ViewMode.AimModes.Free and isOrbitButton(input) then
				self.orbitDragActive = true
				if hasMouse() then
					UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
				end
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if not self.enabled then
				return
			end
			if isOrbitButton(input) and self.orbitDragActive then
				self.orbitDragActive = false
				-- Only hand the cursor back if we are still in Free; if the
				-- player released Alt mid-drag, _ApplyAimPosture already
				-- re-locked to centre and we must not undo that.
				if self.aimMode == ViewMode.AimModes.Free and hasMouse() then
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end
			end
		end)
	)

	-- Touch look. gameProcessed filters out the PlayerModule thumbstick (it is a
	-- GUI), so dragging to move does not also spin the camera.
	table.insert(
		self.connections,
		UserInputService.TouchMoved:Connect(function(touch: InputObject, gameProcessed: boolean)
			if not self.enabled or gameProcessed then
				return
			end
			local delta = touch.Delta
			self.pendingLookDelta = self.pendingLookDelta + Vector2.new(delta.X, delta.Y)
		end)
	)

	-- workspace.Units is created lazily when a match starts. If hero view is
	-- entered before that, re-add it to the occlusion filter when it appears —
	-- otherwise your own soldiers shove the camera into your face in a melee.
	table.insert(
		self.connections,
		Workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Units" then
				self:_RebuildRaycastFilter()
			end
		end)
	)
end

function HeroCamera._RebuildRaycastFilter(self: HeroCamera)
	local filter: { Instance } = {}
	local character = self.character
	if character then
		table.insert(filter, character)
	end
	local units = Workspace:FindFirstChild("Units")
	if units then
		table.insert(filter, units)
	end
	-- Cached, not rebuilt per frame: RaycastParams allocation on the render step
	-- is exactly the kind of churn that shows up as GC hitching.
	self.raycastParams.FilterDescendantsInstances = filter
end

function HeroCamera._IsMouseLookActive(self: HeroCamera): boolean
	if not hasMouse() then
		return false
	end
	if self.aimMode == ViewMode.AimModes.Locked then
		return true
	end
	return self.orbitDragActive
end

-- ───────────────────────────────────────────────────────────────────────────
-- Posture / zoom
-- ───────────────────────────────────────────────────────────────────────────

function HeroCamera.SetAimMode(self: HeroCamera, aim: ViewMode.AimMode)
	if aim ~= ViewMode.AimModes.Locked and aim ~= ViewMode.AimModes.Free then
		HeroDebug:warn(`SetAimMode ignored unknown posture: {tostring(aim)}`)
		return
	end
	self.aimMode = aim
	-- Single funnel: the posture and the shared flag are written together so
	-- they can never disagree. Combat reads ViewMode.isCombatReady().
	ViewMode.setAimMode(aim)
	self:_ApplyAimPosture()
end

function HeroCamera.GetAimMode(self: HeroCamera): ViewMode.AimMode
	return self.aimMode
end

function HeroCamera._ApplyAimPosture(self: HeroCamera)
	local humanoid = self.humanoid

	if not self.enabled then
		if hasMouse() then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
		if humanoid and humanoid.Parent then
			humanoid.AutoRotate = true
		end
		return
	end

	if self.aimMode == ViewMode.AimModes.Locked then
		if hasMouse() then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
		-- We drive the root's yaw ourselves each frame; leaving AutoRotate on
		-- makes the humanoid fight us toward the movement direction.
		if humanoid and humanoid.Parent then
			humanoid.AutoRotate = false
		end
	else
		self.orbitDragActive = false
		if hasMouse() then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
		if humanoid and humanoid.Parent then
			humanoid.AutoRotate = true
		end
	end

	self:_ClampTargetDistance()
end

function HeroCamera._ClampTargetDistance(self: HeroCamera)
	local minDistance: number
	local maxDistance: number
	if self.firstPerson and self.aimMode == ViewMode.AimModes.Locked then
		minDistance = FIRST_PERSON_DISTANCE
		maxDistance = FIRST_PERSON_DISTANCE
	elseif self.aimMode == ViewMode.AimModes.Locked then
		minDistance = LOCKED_MIN_DISTANCE
		maxDistance = LOCKED_MAX_DISTANCE
	else
		-- Free posture is for looking at your Lord, so it pulls out further and
		-- lets you come in closer than the combat posture does.
		minDistance = FREE_MIN_DISTANCE
		maxDistance = FREE_MAX_DISTANCE
	end
	self.targetDistance = math.clamp(self.targetDistance, minDistance, maxDistance)
end

function HeroCamera._ApplyZoom(self: HeroCamera, delta: number)
	-- Scrolling out of first person should just work rather than fighting the
	-- clamp that pins distance at 0.5.
	if self.firstPerson and delta > 0 then
		self:SetFirstPerson(false)
		return
	end
	-- Scrolling all the way in from the closest third-person distance drops you
	-- into true first person, which is what every other Roblox game does.
	if not self.firstPerson
		and delta < 0
		and self.aimMode == ViewMode.AimModes.Locked
		and self.targetDistance <= LOCKED_MIN_DISTANCE + 0.001
	then
		self:SetFirstPerson(true)
		return
	end
	self.targetDistance = self.targetDistance + delta
	self:_ClampTargetDistance()
end

--- True first person. Deliberately NOT Enum.CameraMode.LockFirstPerson: that
--- hands control back to the default camera module and reintroduces the exact
--- dual-owner bug this whole module exists to kill. It is just a zoom level.
function HeroCamera.SetFirstPerson(self: HeroCamera, firstPerson: boolean)
	if self.firstPerson == firstPerson then
		return
	end
	if firstPerson then
		self.distanceBeforeFirstPerson = self.targetDistance
		self.firstPerson = true
		self.targetDistance = FIRST_PERSON_DISTANCE
		-- First person is a combat posture; free-orbit with a released mouse at
		-- 0.5 studs is nonsense, so force the shift-lock posture with it.
		if self.aimMode ~= ViewMode.AimModes.Locked then
			self:SetAimMode(ViewMode.AimModes.Locked)
		end
	else
		self.firstPerson = false
		self.targetDistance = math.max(self.distanceBeforeFirstPerson, LOCKED_MIN_DISTANCE)
	end
	self:_ClampTargetDistance()
	HeroDebug:info("First person toggled", { firstPerson = self.firstPerson })
end

function HeroCamera.ToggleFirstPerson(self: HeroCamera)
	self:SetFirstPerson(not self.firstPerson)
end

function HeroCamera.IsFirstPerson(self: HeroCamera): boolean
	return self.firstPerson
end

function HeroCamera._ApplyFirstPersonVisibility(self: HeroCamera, hidden: boolean)
	if hidden == self.headHidden then
		return
	end
	if hidden then
		local character = self.character
		if not character then
			return
		end
		self.hiddenParts = collectHeadParts(character)
	end
	for _, part in ipairs(self.hiddenParts) do
		if part.Parent then
			-- LocalTransparencyModifier is client-only and nothing else writes it
			-- now that the default camera module is out of the picture.
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
	if not hidden then
		self.hiddenParts = {}
	end
	self.headHidden = hidden
end

-- ───────────────────────────────────────────────────────────────────────────
-- Per-frame
-- ───────────────────────────────────────────────────────────────────────────

--- Computes this frame's desired camera CFrame. Returns nil when the hero is
--- gone (dead, despawned, streamed out) — the controller treats that as "fall
--- back to RTS" rather than freezing on a corpse.
function HeroCamera.Update(self: HeroCamera, deltaTime: number): CFrame?
	if not self.enabled then
		return nil
	end

	-- Separate guards (not one `not (a and b and ...)`) so each condition narrows
	-- cleanly and the failure reason is obvious when stepping through.
	local character = self.character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = self.humanoid
	if not humanoid or not humanoid.Parent then
		return nil
	end
	local rootPart = self.rootPart
	if not rootPart or not rootPart.Parent then
		return nil
	end
	if humanoid.Health <= 0 then
		return nil
	end

	local dt = math.min(deltaTime, MAX_STEP)
	local snap = self.snapNextFrame

	-- Re-assert the mouse posture. Roblox's default CameraModule is still loaded
	-- (we only disabled the ControlModule) and it will happily reset
	-- MouseBehavior when the player alt-tabs or a CoreGui panel closes. Writes
	-- are guarded so we are not dirtying a property 60 times a second.
	if self.aimMode == ViewMode.AimModes.Locked and hasMouse() then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
	end

	-- ── 1. Look input ──────────────────────────────────────────────────────
	-- GetMouseDelta is THE api for a locked mouse: InputChanged/MouseMovement
	-- deltas are only delivered while the cursor is free, so the old
	-- InputChanged-based approach reported zero for the entire time the camera
	-- was actually locked.
	local delta = self.pendingLookDelta
	self.pendingLookDelta = Vector2.zero
	if self:_IsMouseLookActive() then
		delta = delta + UserInputService:GetMouseDelta()
	end
	if snap then
		-- Whatever accumulated while the mouse was unlocked is garbage; a 900px
		-- first-frame delta would whip the camera around on entry.
		delta = Vector2.zero
	end

	if delta.X ~= 0 or delta.Y ~= 0 then
		self.yaw = self.yaw - delta.X * LOOK_SENSITIVITY
		self.pitch = math.clamp(self.pitch - delta.Y * LOOK_SENSITIVITY, MIN_PITCH, MAX_PITCH)
		-- Keep yaw bounded so the float never loses precision over a long match.
		if self.yaw > math.pi then
			self.yaw -= math.pi * 2
		elseif self.yaw < -math.pi then
			self.yaw += math.pi * 2
		end
	end

	if snap then
		self.appliedYaw = self.yaw
		self.appliedPitch = self.pitch
	else
		local rotationAlpha = smoothAlpha(ROTATION_SMOOTH_K, dt)
		self.appliedYaw = self.appliedYaw + shortestAngle(self.appliedYaw, self.yaw) * rotationAlpha
		self.appliedPitch = self.appliedPitch + (self.pitch - self.appliedPitch) * rotationAlpha
	end

	-- ── 2. Zoom ────────────────────────────────────────────────────────────
	self:_ClampTargetDistance()
	if snap then
		self.distance = self.targetDistance
	else
		self.distance = self.distance
			+ (self.targetDistance - self.distance) * smoothAlpha(DISTANCE_SMOOTH_K, dt)
	end

	-- ── 3. Pivot (the only place follow-lag comes from) ────────────────────
	local pivot = rootPart.Position + Vector3.new(0, PIVOT_HEIGHT, 0)
	if snap then
		self.smoothedPivot = pivot
	else
		self.smoothedPivot = self.smoothedPivot:Lerp(pivot, smoothAlpha(PIVOT_SMOOTH_K, dt))
	end
	local smoothedPivot = self.smoothedPivot

	-- ── 4. Desired offset ──────────────────────────────────────────────────
	-- fromEulerAnglesYXZ applies yaw then pitch, which is the FPS convention and
	-- produces no roll. CFrame.Angles(pitch, yaw, 0) would roll on steep pitch.
	local rotation = CFrame.fromEulerAnglesYXZ(self.appliedPitch, self.appliedYaw, 0)
	-- Fade the shoulder offset out as we approach first person so the camera
	-- ends up at the eyes and not floating beside the head.
	local shoulderScale = math.clamp((self.distance - FIRST_PERSON_DISTANCE) / 3, 0, 1)
	local offset = rotation.RightVector * (SHOULDER_RIGHT * shoulderScale)
		- rotation.LookVector * self.distance

	local desiredLength = offset.Magnitude
	local direction = if desiredLength > 1e-4 then offset / desiredLength else -rotation.LookVector

	-- ── 5. Occlusion ───────────────────────────────────────────────────────
	local hitLength = desiredLength
	local result = Workspace:Raycast(smoothedPivot, direction * desiredLength, self.raycastParams)
	if result then
		hitLength = math.max((result.Position - smoothedPivot).Magnitude - CAMERA_SKIN, MIN_OCCLUDED_LENGTH)
	end

	if snap or hitLength < self.occludedLength then
		self.occludedLength = hitLength
	else
		self.occludedLength = self.occludedLength
			+ (hitLength - self.occludedLength) * smoothAlpha(OCCLUSION_RECOVER_K, dt)
	end
	self.occludedLength = math.min(self.occludedLength, desiredLength)

	local cameraPosition = smoothedPivot + direction * self.occludedLength

	-- Keyed off the OCCLUDED length, not the zoom level: if a wall has shoved the
	-- camera into the character's skull we need the head hidden regardless of how
	-- far out the player thinks they are zoomed.
	self:_ApplyFirstPersonVisibility(self.occludedLength < 1.5)

	-- ── 6. Turn the Lord to face the camera (Locked only) ──────────────────
	if self.aimMode == ViewMode.AimModes.Locked then
		local currentLook = rootPart.CFrame.LookVector
		local currentYaw = math.atan2(-currentLook.X, -currentLook.Z)
		-- Only write when the facing actually differs. A standing, non-turning
		-- Lord then has his root left completely alone, which avoids both fighting
		-- the physics solver and 60 pointless CFrame replications a second.
		if math.abs(shortestAngle(currentYaw, self.appliedYaw)) > 0.001 then
			-- The client has network ownership of its own character, so writing the
			-- root CFrame here replicates cleanly. Velocity is saved and restored:
			-- assigning CFrame otherwise reads as a dead stop to the assembly and
			-- the Lord loses his momentum mid-jump every single frame.
			local linearVelocity = rootPart.AssemblyLinearVelocity
			local angularVelocity = rootPart.AssemblyAngularVelocity
			rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, self.appliedYaw, 0)
			rootPart.AssemblyLinearVelocity = linearVelocity
			rootPart.AssemblyAngularVelocity = angularVelocity
		end
	end

	-- ── 7. Final CFrame ────────────────────────────────────────────────────
	-- Converge on a distant point along the pivot's look axis rather than just
	-- copying `rotation`: that makes screen-centre and the aim ray agree despite
	-- the shoulder offset.
	local focusPoint = smoothedPivot + rotation.LookVector * AIM_CONVERGENCE
	local cframe = CFrame.lookAt(cameraPosition, focusPoint)

	self.cameraPosition = cameraPosition
	self.lookVector = cframe.LookVector
	self.snapNextFrame = false

	return cframe
end

-- ───────────────────────────────────────────────────────────────────────────
-- Queries (combat reads these)
-- ───────────────────────────────────────────────────────────────────────────

--- The direction the crosshair points, taken from the hero camera's own solved
--- rotation rather than Camera.CFrame — mid-transition the real camera is
--- somewhere between the two views and would give a bogus answer.
function HeroCamera.GetLookVector(self: HeroCamera): Vector3
	return self.lookVector
end

--- (origin, direction) of the crosshair ray, unit direction. Combat should
--- length-scale it and raycast with its own filter; use ViewMode.isCombatReady()
--- to decide whether the ray is meaningful at all.
function HeroCamera.GetAimRay(self: HeroCamera): (Vector3, Vector3)
	return self.cameraPosition, self.lookVector
end

function HeroCamera.GetCameraPosition(self: HeroCamera): Vector3
	return self.cameraPosition
end

return HeroCamera
