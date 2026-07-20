--!strict
-- UnitAnimator (client): makes any Humanoid unit look like it's walking.
--
-- Server-spawned NPCs don't animate on their own — Roblox's automatic walk/idle
-- animations only run for player characters (via the Animate LocalScript). This
-- module gives every unit in workspace.Units a rig-appropriate walk + idle
-- animation and plays them based on the unit's OBSERVED movement.
--
-- It runs entirely on the client and drives animation off each unit's velocity,
-- so it adds ZERO network replication — important at high unit counts. Works with
-- whatever rig you drop in (R6 or R15, detected from Humanoid.RigType), as long as
-- it's a real rig with Motor6D joints (which UnitManager's weld step preserves).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local AnimDebug = DebugManager.createChannel("UnitAnimator", false)

local UnitAnimator = {}

-- Roblox's default (public) animations, per rig type. Swap these for your own
-- asset ids if you ever want a custom gait — one place, applies to every unit.
local DEFAULTS = {
	R6 = {
		idle = "rbxassetid://180435571",
		walk = "rbxassetid://180426354",
	},
	R15 = {
		idle = "rbxassetid://507766388",
		walk = "rbxassetid://913402848",
	},
}

-- Below this speed (studs/sec) a unit is considered standing still.
local WALK_THRESHOLD = 0.6
-- Base walk speed the walk animation was authored for, used to scale playback.
local ANIM_BASE_SPEED = 14

type Entry = {
	humanoid: Humanoid,
	root: BasePart,
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	lastPos: Vector3,
	moving: boolean?,
}

local tracked: { [Model]: Entry } = {}

local function loadTrack(animator: Animator, id: string): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Looped = true
		return track
	end
	return nil
end

local function setupUnit(model: Model)
	if tracked[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	-- A local Animator is enough to play animations client-side.
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local rig = if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
	local ids = DEFAULTS[rig]

	tracked[model] = {
		humanoid = humanoid,
		root = root,
		idle = loadTrack(animator, ids.idle),
		walk = loadTrack(animator, ids.walk),
		lastPos = root.Position,
		moving = nil,
	}
	AnimDebug:info(`Animating {model.Name} ({rig})`)
end

local function cleanup(model: Model)
	local entry = tracked[model]
	if entry then
		if entry.walk then
			entry.walk:Stop()
		end
		if entry.idle then
			entry.idle:Stop()
		end
		tracked[model] = nil
	end
end

local function setMoving(entry: Entry, moving: boolean)
	if entry.moving == moving then
		return
	end
	entry.moving = moving
	if moving then
		if entry.idle then
			entry.idle:Stop(0.15)
		end
		if entry.walk then
			entry.walk:Play(0.15)
		end
	else
		if entry.walk then
			entry.walk:Stop(0.15)
		end
		if entry.idle then
			entry.idle:Play(0.15)
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	local step = math.max(dt, 1 / 240)
	for model, entry in pairs(tracked) do
		if not model.Parent or not entry.root or not entry.root.Parent then
			cleanup(model)
			continue
		end

		local pos = entry.root.Position
		local delta = pos - entry.lastPos
		local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / step
		entry.lastPos = pos

		local moving = speed > WALK_THRESHOLD
		setMoving(entry, moving)

		-- Match the leg cadence to how fast the unit is actually crossing ground.
		if moving and entry.walk then
			entry.walk:AdjustSpeed(math.clamp(speed / ANIM_BASE_SPEED, 0.5, 2.5))
		end
	end
end)

local function watchUnitsFolder(units: Instance)
	for _, child in units:GetChildren() do
		if child:IsA("Model") then
			task.defer(setupUnit, child)
		end
	end
	units.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			-- Defer a frame so the humanoid/parts of a freshly-cloned unit exist.
			task.defer(setupUnit, child)
		end
	end)
	units.ChildRemoved:Connect(cleanup)
end

task.spawn(function()
	local units = Workspace:FindFirstChild("Units") or Workspace:WaitForChild("Units", 30)
	if units then
		watchUnitsFolder(units)
		AnimDebug:info("UnitAnimator watching workspace.Units")
	else
		AnimDebug:warn("workspace.Units never appeared; UnitAnimator idle")
	end
end)

return UnitAnimator
