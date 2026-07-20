--[[
	UnitAnimationSystem  —  PASTE THIS INTO A Script IN ServerScriptService
	----------------------------------------------------------------------------
	In Studio: right-click ServerScriptService → Insert Object → Script, delete the
	default contents, paste this whole file, and press Play. (Put it directly under
	ServerScriptService, NOT inside the "Server" folder, so Rojo won't overwrite it.)

	What it does:
	  • Gives every Humanoid unit in workspace.Units a walk + idle animation.
	  • Runs on the SERVER, so the animation replicates to all clients (reliable
	    for NPCs) without you having to sync the client tree.
	  • Drives animation off each unit's actual movement — no per-model setup.
	  • Prints a line per unit; WARNS if a model has no Motor6D joints (meaning it
	    is a static/welded model and physically cannot animate — use a real rig).

	It works with whatever rig you use (R6 or R15, auto-detected). To use your own
	animations instead of the Roblox defaults, change the ids in DEFAULTS below.
--]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- Default (public) Roblox animations, per rig type. Swap for your own ids here.
local DEFAULTS = {
	R6 = { idle = "rbxassetid://180435571", walk = "rbxassetid://180426354" },
	R15 = { idle = "rbxassetid://507766388", walk = "rbxassetid://913402848" },
}

local WALK_THRESHOLD = 0.6 -- studs/sec before a unit counts as walking
local ANIM_BASE_SPEED = 14 -- speed the walk anim was authored for (for cadence)

local tracked = {}

local function loadTrack(animator, id)
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

local function setup(model)
	if tracked[model] or not model:IsA("Model") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local rig = humanoid.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"
	local ids = DEFAULTS[rig]

	local motors = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors += 1
		end
	end
	if motors == 0 then
		warn(('[UnitAnim] "%s" has NO Motor6D joints — a static/welded model can\'t walk. Use a real R6/R15 rig.'):format(model.Name))
	else
		print(('[UnitAnim] animating %s (%s, %d joints)'):format(model.Name, rig, motors))
	end

	tracked[model] = {
		root = root,
		walk = loadTrack(animator, ids.walk),
		idle = loadTrack(animator, ids.idle),
		lastPos = root.Position,
		moving = nil,
	}
end

local function cleanup(model)
	local e = tracked[model]
	if e then
		if e.walk then
			e.walk:Stop()
		end
		if e.idle then
			e.idle:Stop()
		end
		tracked[model] = nil
	end
end

local function watch(units)
	for _, c in ipairs(units:GetChildren()) do
		setup(c)
	end
	units.ChildAdded:Connect(function(c)
		task.defer(setup, c) -- let a freshly-cloned unit finish building
	end)
	units.ChildRemoved:Connect(cleanup)
end

RunService.Heartbeat:Connect(function(dt)
	local step = math.max(dt, 1 / 240)
	for model, e in pairs(tracked) do
		if not model.Parent or not e.root or not e.root.Parent then
			cleanup(model)
			continue
		end
		local pos = e.root.Position
		local delta = pos - e.lastPos
		local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / step
		e.lastPos = pos

		local moving = speed > WALK_THRESHOLD
		if moving ~= e.moving then
			e.moving = moving
			if moving then
				if e.idle then
					e.idle:Stop(0.15)
				end
				if e.walk then
					e.walk:Play(0.15)
				end
			else
				if e.walk then
					e.walk:Stop(0.15)
				end
				if e.idle then
					e.idle:Play(0.15)
				end
			end
		end
		if moving and e.walk then
			e.walk:AdjustSpeed(math.clamp(speed / ANIM_BASE_SPEED, 0.5, 2.5))
		end
	end
end)

do
	local units = Workspace:FindFirstChild("Units")
	if units then
		watch(units)
	else
		-- Units folder is created when the first unit spawns.
		Workspace.ChildAdded:Connect(function(c)
			if c.Name == "Units" and c:IsA("Folder") then
				watch(c)
			end
		end)
	end
end

print("[UnitAnim] UnitAnimationSystem running (server).")
