--!strict
-- HeroCombatController: input + feedback for third-person hero combat.
--
-- Replaces the deleted FirstPersonCombat.client.luau, which gated everything on
-- `player.CameraMode == Enum.CameraMode.LockFirstPerson`. That check is now dead
-- wrong: hero mode is THIRD person, so CameraMode is Classic and the old script
-- would have refused every swing. The gate is ViewMode.isCombatReady().
--
-- ---------------------------------------------------------------------------
-- WHAT THIS IS AND IS NOT
-- ---------------------------------------------------------------------------
-- IS:  input interpretation (tap vs hold), local prediction of the animation and
--      VFX so the game feels responsive at 150ms ping, and a cooldown mirror so
--      we don't spam the remote.
-- NOT: authority. Every cooldown here is a DUPLICATE of the server's, kept only
--      to reduce remote traffic. If the two disagree the server wins and the
--      player sees a swing that did no damage — which is the correct failure
--      mode, and much better than trusting the client.
--
-- ---------------------------------------------------------------------------
-- WHY THE ANIMATION IS PROCEDURAL
-- ---------------------------------------------------------------------------
-- There are NO combat animation assets in this project and none can be uploaded:
-- every `attack` slot in UnitAnimationsData is nil, and there are no block/dodge
-- /hit slots at all. The Lord is a stock R15 avatar, so the only asset-free way
-- to get real body motion out of him is to drive the Motor6D `Transform` of his
-- shoulders and waist directly, on the client, every frame.
--
-- HERO_ANIMATION_IDS below is the upgrade path: drop a real uploaded animation id
-- into a slot and it TAKES PRECEDENCE over the procedural pose for that action,
-- with no other change. The procedural poses stay as the fallback for every slot
-- left empty, so the two can coexist while animations are authored one at a time.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local ViewMode = require(ReplicatedStorage.Shared.ViewMode)

-- KeybindingsManager is owned by the camera agent; we only READ from it.
local KeybindingsManager = require(script.Parent.Parent.Camera.KeybindingsManager)

local HeroDebug = DebugManager.createChannel("HeroCombatClient", false)

local Hero = CombatConfig.Hero

local player = Players.LocalPlayer

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local gameEvent = remoteEvents:WaitForChild("GameEvent") :: RemoteEvent
local combatEvents = remoteEvents:WaitForChild("CombatEvents") :: RemoteEvent

local HeroCombatController = {}

-- ---------------------------------------------------------------------------
-- ANIMATION ASSET HOOKS
-- ---------------------------------------------------------------------------
--
-- Leave a slot as "" to use the procedural fallback. Put an
-- "rbxassetid://..." in it and that clip plays instead — Animator:LoadAnimation
-- works normally here because the Lord is a stock R15 rig (unlike the game's
-- units, which are custom skinned MeshPart rigs where stock ids silently no-op).
local HERO_ANIMATION_IDS: { [string]: string } = {
	light1 = "",
	light2 = "",
	light3 = "",
	heavy = "",
	block = "",
	dodge = "",
	parry = "",
	bow = "",
}

-- ---------------------------------------------------------------------------
-- KEYBINDS
-- ---------------------------------------------------------------------------
--
-- These action names are being added to KeybindingsManager by the camera agent.
-- Until they land, GetKeybinding returns nil for them, so every lookup falls back
-- to the documented default and the feature works today — it just is not
-- rebindable yet. Do NOT add the actions here; that file is not ours.
--
-- KNOWN CONFLICT to resolve when the actions are added: the default for
-- HeroRangedAttack is Q, and Q is already RotateLeft in DEFAULT_KEYBINDINGS.
-- KeybindingsManager.HasConflict will reject setting them both, and in hero mode
-- the RTS rotate keys are inert, so sharing the key is survivable — but it should
-- be a deliberate decision, not a surprise.
local KEY_DEFAULTS: { [string]: Enum.KeyCode } = {
	HeroRangedAttack = Enum.KeyCode.Q,
	HeroDodge = Enum.KeyCode.LeftControl,
	-- Secondary heavy trigger. Hold-LMB is the primary one; this exists because
	-- the action is listed in the rebindable keybindings UI. Without a fallback
	-- entry here, keyFor() would return nil if the KeybindingsManager lookup ever
	-- failed, and the comparison would silently never match.
	HeroHeavyAttack = Enum.KeyCode.R,
}

local function keyFor(action: string): Enum.KeyCode
	local ok, bound = pcall(function()
		return (KeybindingsManager :: any).GetKeybinding(action)
	end)
	if ok and typeof(bound) == "EnumItem" then
		return bound :: Enum.KeyCode
	end
	return KEY_DEFAULTS[action]
end

-- ---------------------------------------------------------------------------
-- AUDIO
-- ---------------------------------------------------------------------------
--
-- There are no sound assets in this repo. This follows the only convention that
-- exists here (DeletionEffects.client.luau): look for
-- ReplicatedStorage.Assets.Sounds.<Name>, fall back to a stock rbxasset:// id,
-- parent to the emitting part so it is positional, and let Debris clean up.
--
-- Unlike DeletionEffects, a found asset is CLONED rather than played in place: a
-- combo fires these three times in 1.5s and replaying one shared Sound instance
-- restarts it instead of layering.
local SOUND_FALLBACKS: { [string]: string } = {
	HeroSwingLight = "rbxasset://sounds/swordslash.wav",
	HeroSwingHeavy = "rbxasset://sounds/swordlunge.wav",
	HeroBlock = "rbxasset://sounds/metal.ogg",
	HeroParry = "rbxasset://sounds/electronicpingshort.wav",
	HeroDodge = "rbxasset://sounds/action_falling.mp3",
	HeroBowRelease = "rbxasset://sounds/swordslash.wav",
}

local function playHeroSound(name: string, at: BasePart?, volume: number, pitch: number?)
	local emitter: Instance = at or (Workspace.CurrentCamera :: Camera)
	local sound: Sound

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local soundsFolder = assets and assets:FindFirstChild("Sounds")
	local template = soundsFolder and soundsFolder:FindFirstChild(name)
	if template and template:IsA("Sound") then
		sound = template:Clone()
	else
		sound = Instance.new("Sound")
		sound.SoundId = SOUND_FALLBACKS[name] or SOUND_FALLBACKS.HeroSwingLight
	end

	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 120
	sound.Parent = emitter
	sound:Play()
	Debris:AddItem(sound, 5)
end

-- ---------------------------------------------------------------------------
-- CROSSHAIR / HUD
-- ---------------------------------------------------------------------------
--
-- Deliberately tiny and self-contained: the real HUD is owned by another agent
-- and lives under src/ui. This is combat-reticle-only, parented to PlayerGui
-- under its own name so it cannot collide with anything there.

type Reticle = {
	gui: ScreenGui,
	root: Frame,
	ticks: { Frame },
	ring: Frame,
	pips: { Frame },
}

local reticle: Reticle? = nil

local COLOR_IDLE = Color3.fromRGB(235, 235, 235)
local COLOR_CHARGING = Color3.fromRGB(255, 175, 40)
local COLOR_BLOCK = Color3.fromRGB(110, 180, 255)
local COLOR_COOLDOWN = Color3.fromRGB(120, 120, 120)
local COLOR_PARRY = Color3.fromRGB(255, 250, 190)

local function buildReticle(): Reticle
	local gui = Instance.new("ScreenGui")
	gui.Name = "HeroCombatReticle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(64, 64)
	root.BackgroundTransparency = 1
	root.Parent = gui

	-- Block ring: a hollow circle that fades in while guarding.
	local ring = Instance.new("Frame")
	ring.Name = "BlockRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(40, 40)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Parent = root
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Name = "Stroke"
	ringStroke.Thickness = 2
	ringStroke.Color = COLOR_BLOCK
	ringStroke.Transparency = 1
	ringStroke.Parent = ring

	-- Four ticks around the centre. Their distance from centre is the "gap", which
	-- widens while a heavy charges — the standard, wordless way to say "committed".
	local ticks: { Frame } = {}
	for index = 1, 4 do
		local tick = Instance.new("Frame")
		tick.Name = `Tick{index}`
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.BackgroundColor3 = COLOR_IDLE
		tick.BorderSizePixel = 0
		tick.Size = if index <= 2 then UDim2.fromOffset(2, 8) else UDim2.fromOffset(8, 2)
		tick.Parent = root
		ticks[index] = tick
	end

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(2, 2)
	dot.BackgroundColor3 = COLOR_IDLE
	dot.BorderSizePixel = 0
	dot.Parent = root

	-- Combo pips: three small marks under the reticle showing chain progress.
	-- (Stamina is disabled by default in CombatConfig.Hero, so there is no stamina
	-- bar — adding one for a resource that is always full would be a lie.)
	local pips: { Frame } = {}
	for index = 1, #Hero.lightCombo do
		local pip = Instance.new("Frame")
		pip.Name = `Pip{index}`
		pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.Position = UDim2.new(0.5, (index - 2) * 10, 0.5, 30)
		pip.Size = UDim2.fromOffset(6, 3)
		pip.BackgroundColor3 = COLOR_IDLE
		pip.BackgroundTransparency = 0.75
		pip.BorderSizePixel = 0
		pip.Parent = root
		pips[index] = pip
	end

	return { gui = gui, root = root, ticks = ticks, ring = ring, pips = pips }
end

local function getReticle(): Reticle
	local existing = reticle
	if existing then
		return existing
	end
	local created = buildReticle()
	reticle = created
	return created
end

-- ---------------------------------------------------------------------------
-- PREDICTED LOCAL STATE
-- ---------------------------------------------------------------------------
--
-- Mirrors the server's timings so the animation and the reticle can react at
-- once. Never trusted for anything that matters.

type ClientState = {
	nextActionAt: number,
	comboIndex: number,
	comboExpiresAt: number,
	dodgeReadyAt: number,
	rangedReadyAt: number,
	blocking: boolean,
	-- LMB tap-vs-hold detection
	lmbDownAt: number?,
	heavyFired: boolean,
	hitStopUntil: number,
}

local state: ClientState = {
	nextActionAt = 0,
	comboIndex = 0,
	comboExpiresAt = 0,
	dodgeReadyAt = 0,
	rangedReadyAt = 0,
	blocking = false,
	lmbDownAt = nil,
	heavyFired = false,
	hitStopUntil = 0,
}

local function resetPredictedState()
	state.nextActionAt = 0
	state.comboIndex = 0
	state.comboExpiresAt = 0
	state.dodgeReadyAt = 0
	state.rangedReadyAt = 0
	state.blocking = false
	state.lmbDownAt = nil
	state.heavyFired = false
	state.hitStopUntil = 0
end

local function character(): Model?
	local model = player.Character
	if not model or not model.Parent then
		return nil
	end
	return model
end

local function humanoidOf(model: Model?): Humanoid?
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

--- The single input gate. `ViewMode.isCombatReady()` is exactly "hero mode +
--- locked crosshair + not mid-transition"; everything else here is liveness.
local function canFight(): boolean
	if not ViewMode.isCombatReady() then
		return false
	end
	local model = character()
	if not humanoidOf(model) then
		return false
	end
	-- CanFirstPerson = Battle Arena hero; IsKing = the Lord in a normal game.
	-- Kept as a cheap "the server thinks I can fight" sanity check.
	return (model :: Model):GetAttribute("CanFirstPerson") == true
		or (model :: Model):GetAttribute("IsKing") == true
end

local function aimDirection(): Vector3
	local camera = Workspace.CurrentCamera
	if not camera then
		return Vector3.new(0, 0, -1)
	end
	return camera.CFrame.LookVector
end

-- ---------------------------------------------------------------------------
-- PROCEDURAL POSE SYSTEM
-- ---------------------------------------------------------------------------

type Pose = {
	rightShoulder: CFrame?,
	leftShoulder: CFrame?,
	waist: CFrame?,
}

type Keyframe = { time: number, pose: Pose }

type Clip = {
	duration: number,
	hold: boolean, -- freeze on the last keyframe until explicitly released
	keyframes: { Keyframe },
}

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local IDENTITY_POSE: Pose = {}

-- Every clip is authored as shoulder/waist offsets from the rig's rest pose. They
-- are intentionally big: a subtle 15° arm swing reads as nothing at all once the
-- camera is 12 studs back behind the character.
local CLIPS: { [string]: Clip } = {
	-- Light 1: horizontal slash, right to left, hips lead.
	light1 = {
		duration = 0.48,
		hold = false,
		keyframes = {
			{ time = 0.00, pose = IDENTITY_POSE },
			{ time = 0.12, pose = { rightShoulder = angles(-25, 0, -55), waist = angles(0, 22, 0) } },
			{ time = 0.22, pose = { rightShoulder = angles(-95, 0, 40), waist = angles(0, -26, 0) } },
			{ time = 0.48, pose = IDENTITY_POSE },
		},
	},
	-- Light 2: backhand return the other way, so the chain reads as alternating.
	light2 = {
		duration = 0.44,
		hold = false,
		keyframes = {
			{ time = 0.00, pose = IDENTITY_POSE },
			{ time = 0.10, pose = { rightShoulder = angles(-70, 0, 55), waist = angles(0, -20, 0) } },
			{ time = 0.20, pose = { rightShoulder = angles(-80, 0, -50), waist = angles(0, 24, 0) } },
			{ time = 0.44, pose = IDENTITY_POSE },
		},
	},
	-- Light 3: overhead finisher with a forward lean.
	light3 = {
		duration = 0.74,
		hold = false,
		keyframes = {
			{ time = 0.00, pose = IDENTITY_POSE },
			{ time = 0.18, pose = { rightShoulder = angles(35, 0, -20), leftShoulder = angles(20, 0, 20), waist = angles(-12, 0, 0) } },
			{ time = 0.32, pose = { rightShoulder = angles(-130, 0, 0), leftShoulder = angles(-30, 0, 0), waist = angles(24, 0, 0) } },
			{ time = 0.74, pose = IDENTITY_POSE },
		},
	},
	-- Heavy: a long, obvious wind-up over the shoulder. The windup pose is held
	-- through most of the clip because being READABLE is the heavy's whole cost.
	heavy = {
		duration = 1.13,
		hold = false,
		keyframes = {
			{ time = 0.00, pose = IDENTITY_POSE },
			{ time = 0.20, pose = { rightShoulder = angles(70, 0, -35), leftShoulder = angles(35, 0, 25), waist = angles(-22, -18, 0) } },
			{ time = 0.42, pose = { rightShoulder = angles(80, 0, -40), leftShoulder = angles(40, 0, 30), waist = angles(-26, -22, 0) } },
			{ time = 0.58, pose = { rightShoulder = angles(-140, 0, 25), leftShoulder = angles(-40, 0, -20), waist = angles(30, 20, 0) } },
			{ time = 1.13, pose = IDENTITY_POSE },
		},
	},
	-- Block: shield arm up across the chest, sword low. HELD while RMB is down.
	block = {
		duration = 0.14,
		hold = true,
		keyframes = {
			{ time = 0.00, pose = IDENTITY_POSE },
			{ time = 0.14, pose = { leftShoulder = angles(-80, 0, 55), rightShoulder = angles(-15, 0, -25), waist = angles(-6, 14, 0) } },
		},
	},
	-- Parry: a sharp shield punch out of the block pose.
	parry = {
		duration = 0.34,
		hold = false,
		keyframes = {
			{ time = 0.00, pose = { leftShoulder = angles(-80, 0, 55), rightShoulder = angles(-15, 0, -25) } },
			{ time = 0.08, pose = { leftShoulder = angles(-105, 0, 15), rightShoulder = angles(-10, 0, -35), waist = angles(-14, -10, 0) } },
			{ time = 0.34, pose = { leftShoulder = angles(-80, 0, 55), rightShoulder = angles(-15, 0, -25) } },
		},
	},
	-- Dodge: tuck, then recover.
	dodge = {
		duration = 0.78,
		hold = false,
		keyframes = {
			{ time = 0.00, pose = IDENTITY_POSE },
			{ time = 0.10, pose = { waist = angles(-45, 0, 0), rightShoulder = angles(-60, 0, -30), leftShoulder = angles(-60, 0, 30) } },
			{ time = 0.40, pose = { waist = angles(-20, 0, 0), rightShoulder = angles(-30, 0, -15), leftShoulder = angles(-30, 0, 15) } },
			{ time = 0.78, pose = IDENTITY_POSE },
		},
	},
	-- Bow: draw, release, lower.
	bow = {
		duration = 0.62,
		hold = false,
		keyframes = {
			{ time = 0.00, pose = IDENTITY_POSE },
			{ time = 0.22, pose = { leftShoulder = angles(-90, 0, 5), rightShoulder = angles(-70, 0, -35), waist = angles(0, -12, 0) } },
			{ time = 0.32, pose = { leftShoulder = angles(-92, 0, 5), rightShoulder = angles(-40, 0, -10), waist = angles(0, -8, 0) } },
			{ time = 0.62, pose = IDENTITY_POSE },
		},
	},
}

type MotorSet = {
	rightShoulder: Motor6D?,
	leftShoulder: Motor6D?,
	waist: Motor6D?,
}

local motors: MotorSet = {}
local motorCharacter: Model? = nil

--- Resolve the R15 Motor6D joints. Cached per character because this walks the
--- rig, and re-walking it every frame at 60fps for a cosmetic pose would be
--- indefensible on a machine already simulating hundreds of units.
local function resolveMotors(model: Model): MotorSet
	if motorCharacter == model then
		return motors
	end
	local function findMotor(partName: string, motorName: string): Motor6D?
		local part = model:FindFirstChild(partName)
		if not part then
			return nil
		end
		local motor = part:FindFirstChild(motorName)
		if motor and motor:IsA("Motor6D") then
			return motor
		end
		return nil
	end
	motors = {
		rightShoulder = findMotor("RightUpperArm", "RightShoulder"),
		leftShoulder = findMotor("LeftUpperArm", "LeftShoulder"),
		waist = findMotor("UpperTorso", "Waist"),
	}
	motorCharacter = model
	return motors
end

local activeClipName: string? = nil
local activeClip: Clip? = nil
local clipTime = 0
local clipWeight = 0 -- 0..1 blend so we do not snap in and out of the stock idle
local POSE_BLEND_IN = 0.06
local POSE_BLEND_OUT = 0.14

--- Interpolate a clip's keyframes at `time`. Missing joints in a keyframe are
--- treated as rest, which is what lets a clip animate only the shield arm.
local function samplePose(clip: Clip, time: number): Pose
	local frames = clip.keyframes
	local previous = frames[1]
	local following = frames[#frames]
	for index = 1, #frames - 1 do
		if time >= frames[index].time and time <= frames[index + 1].time then
			previous = frames[index]
			following = frames[index + 1]
			break
		end
	end
	local span = following.time - previous.time
	local alpha = if span > 1e-4 then math.clamp((time - previous.time) / span, 0, 1) else 1
	-- Smoothstep: linear joint interpolation on a 3-keyframe swing looks robotic,
	-- and easing is free here.
	alpha = alpha * alpha * (3 - 2 * alpha)

	local function blend(a: CFrame?, b: CFrame?): CFrame
		return (a or CFrame.identity):Lerp(b or CFrame.identity, alpha)
	end
	return {
		rightShoulder = blend(previous.pose.rightShoulder, following.pose.rightShoulder),
		leftShoulder = blend(previous.pose.leftShoulder, following.pose.leftShoulder),
		waist = blend(previous.pose.waist, following.pose.waist),
	}
end

-- -- Uploaded-animation path (takes precedence when an id is present) ---------
local loadedTracks: { [string]: AnimationTrack } = {}
local trackCharacter: Model? = nil

local function playUploadedAnimation(model: Model, slot: string): boolean
	local assetId = HERO_ANIMATION_IDS[slot]
	if not assetId or assetId == "" then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	if trackCharacter ~= model then
		table.clear(loadedTracks)
		trackCharacter = model
	end
	local track = loadedTracks[slot]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = assetId
		local ok, result = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		animation:Destroy()
		if not ok or not result then
			-- A bad id must not break combat: fall through to the procedural pose.
			HeroDebug:warn("Failed to load hero animation", { slot = slot, id = assetId })
			HERO_ANIMATION_IDS[slot] = ""
			return false
		end
		track = result :: AnimationTrack
		loadedTracks[slot] = track
	end
	track:Play(0.08)
	return true
end

local function playClip(slot: string)
	local model = character()
	if not model then
		return
	end
	if playUploadedAnimation(model, slot) then
		-- Real animation is driving the rig; make sure the procedural pose is not
		-- also writing Transform and fighting it.
		activeClip = nil
		activeClipName = nil
		return
	end
	local clip = CLIPS[slot]
	if not clip then
		return
	end
	activeClipName = slot
	activeClip = clip
	clipTime = 0
end

local function stopClip(slot: string?)
	if slot and activeClipName ~= slot then
		return
	end
	activeClip = nil
	activeClipName = nil
end

-- ---------------------------------------------------------------------------
-- CAMERA KICK / SHAKE
-- ---------------------------------------------------------------------------
--
-- Applied as a POST-PROCESS on the camera CFrame from a render step bound AFTER
-- Enum.RenderPriority.Camera, deliberately: the hero camera is owned by another
-- agent's CameraRig, and writing an absolute CFrame here would fight it every
-- frame. Multiplying whatever it produced is additive and survives any camera
-- implementation.
--
-- It also means we never touch Humanoid.CameraOffset, which a custom camera
-- module is free to ignore.

type Shake = { amplitude: number, decay: number, until_: number }

local activeShakes: { Shake } = {}

local function addShake(amplitude: number, duration: number)
	table.insert(activeShakes, {
		amplitude = amplitude,
		decay = duration,
		until_ = os.clock() + duration,
	})
end

local function applyCameraShake()
	local camera = Workspace.CurrentCamera
	if not camera or #activeShakes == 0 then
		return
	end
	local now = os.clock()
	local totalAmplitude = 0
	for index = #activeShakes, 1, -1 do
		local shake = activeShakes[index]
		if now >= shake.until_ then
			table.remove(activeShakes, index)
		else
			local remaining = (shake.until_ - now) / math.max(shake.decay, 1e-3)
			totalAmplitude += shake.amplitude * remaining * remaining
		end
	end
	if totalAmplitude <= 1e-4 then
		return
	end
	local function jitter(): number
		return (math.random() * 2 - 1) * totalAmplitude
	end
	camera.CFrame = camera.CFrame
		* CFrame.new(jitter() * 0.35, jitter() * 0.35, 0)
		* CFrame.Angles(math.rad(jitter() * 1.6), math.rad(jitter() * 1.6), math.rad(jitter()))
end

-- ---------------------------------------------------------------------------
-- WORLD FLASHES (local prediction + own-hero reactions)
-- ---------------------------------------------------------------------------
--
-- Same procedural Part + TweenService + Debris convention as
-- CombatEffectsClient, parented to the same "ClientCombatEffects" folder so
-- there is one place to clear VFX from.

local function effectsFolder(): Instance
	local folder = Workspace:FindFirstChild("ClientCombatEffects")
	if folder then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "ClientCombatEffects"
	created.Parent = Workspace
	return created
end

local function parryFlash(position: Vector3)
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1.5, 1.5, 1.5)
	flash.Position = position
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Color = COLOR_PARRY
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.1
	flash.Parent = effectsFolder()
	TweenService:Create(flash, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(7, 7, 7),
		Transparency = 1,
	}):Play()
	Debris:AddItem(flash, 0.32)
end

local function blockSpark(position: Vector3)
	local spark = Instance.new("Part")
	spark.Size = Vector3.new(0.4, 0.4, 0.4)
	spark.Position = position
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.CanTouch = false
	spark.CastShadow = false
	spark.Color = COLOR_BLOCK
	spark.Material = Enum.Material.Neon
	spark.Transparency = 0.2
	spark.Parent = effectsFolder()
	TweenService:Create(spark, TweenInfo.new(0.22), { Size = Vector3.new(2.2, 2.2, 2.2), Transparency = 1 }):Play()
	Debris:AddItem(spark, 0.26)
end

-- ---------------------------------------------------------------------------
-- WEAPON ARC (extends the existing animateSwing primitive, per combo step)
-- ---------------------------------------------------------------------------
--
-- CombatEffectsClient.animateSwing already does the canonical 3-stage
-- WeaponGrip tween. It is driven by the server's "swing"/"hswing" event, which
-- arrives up to one combat tick (100ms) late — fine for a distant soldier,
-- far too late for the weapon in your own hands. So the local hero predicts its
-- own arc here with a per-step amplitude, and CombatEffectsClient skips the
-- replicated arc for the local character (see its hswing branch).

local weaponBaseC0: { [Weld]: CFrame } = setmetatable({} :: any, { __mode = "k" })

local ARC_BY_SLOT: { [string]: { windupDeg: number, strikeDeg: number, roll: number, time: number } } = {
	light1 = { windupDeg = 30, strikeDeg = -70, roll = -35, time = 0.10 },
	light2 = { windupDeg = 25, strikeDeg = -65, roll = 40, time = 0.10 },
	light3 = { windupDeg = 45, strikeDeg = -100, roll = 0, time = 0.14 },
	heavy = { windupDeg = 70, strikeDeg = -130, roll = 15, time = 0.18 },
	bow = { windupDeg = 0, strikeDeg = 0, roll = 0, time = 0.12 },
}

local function animateWeaponArc(slot: string)
	local model = character()
	if not model then
		return
	end
	local weapon = model:FindFirstChild("Weapon")
	if not weapon then
		return -- no weapon drawn (RTS mode leftovers, or WeaponVisuals not attached yet)
	end
	local weld = weapon:FindFirstChild("WeaponGrip", true)
	if not weld or not weld:IsA("Weld") then
		return
	end
	local arc = ARC_BY_SLOT[slot]
	if not arc or arc.strikeDeg == 0 then
		return
	end

	local base = weaponBaseC0[weld]
	if not base then
		base = weld.C0
		weaponBaseC0[weld] = base
	end

	local windupC0 = base * CFrame.Angles(math.rad(arc.windupDeg), 0, math.rad(-arc.roll * 0.4))
	local strikeC0 = base * CFrame.Angles(math.rad(arc.strikeDeg), 0, math.rad(arc.roll))

	local windup = TweenService:Create(weld, TweenInfo.new(arc.time * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = windupC0 })
	local strike = TweenService:Create(weld, TweenInfo.new(arc.time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = strikeC0 })
	local recover = TweenService:Create(weld, TweenInfo.new(arc.time * 1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = base })

	windup:Play()
	windup.Completed:Once(function()
		if not weld.Parent then
			return
		end
		strike:Play()
		strike.Completed:Once(function()
			if weld.Parent then
				recover:Play()
			end
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- ACTION SENDERS
-- ---------------------------------------------------------------------------

local function rootPart(): BasePart?
	local model = character()
	if not model then
		return nil
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function sendLight()
	local now = os.clock()
	if now < state.nextActionAt then
		return
	end

	-- Predict the chain the same way the server advances it, so the animation and
	-- the reticle pip match what the server is about to do.
	local steps = Hero.lightCombo
	local nextIndex = if now < state.comboExpiresAt then state.comboIndex + 1 else 1
	if nextIndex > #steps then
		nextIndex = 1
	end
	local step = steps[nextIndex]

	state.comboIndex = nextIndex
	state.nextActionAt = now + step.windup + step.activeWindow + step.recovery
	state.comboExpiresAt = state.nextActionAt + step.comboWindow

	gameEvent:FireServer("HeroLight", { aim = aimDirection() })

	local slot = `light{nextIndex}`
	playClip(slot)
	animateWeaponArc(slot)
	playHeroSound("HeroSwingLight", rootPart(), 0.45, 0.95 + nextIndex * 0.05)
	HeroDebug:info("Light attack", { step = nextIndex })
end

local function sendHeavy()
	local now = os.clock()
	if now < state.nextActionAt then
		return
	end
	local heavy = Hero.heavy
	if state.comboIndex > heavy.maxComboIndexToChainFrom and now < state.comboExpiresAt then
		return -- the server would reject this; don't waste the remote call
	end

	state.comboIndex = 0
	state.comboExpiresAt = 0
	state.nextActionAt = now + heavy.windup + heavy.activeWindow + heavy.recovery

	gameEvent:FireServer("HeroHeavy", { aim = aimDirection() })

	playClip("heavy")
	animateWeaponArc("heavy")
	playHeroSound("HeroSwingHeavy", rootPart(), 0.6, 0.85)
	-- The heavy's own weight kicks the camera on the swing, before it connects.
	task.delay(heavy.windup, function()
		addShake(0.5, 0.18)
	end)
	HeroDebug:info("Heavy attack")
end

local function sendRanged()
	local now = os.clock()
	if now < state.nextActionAt or now < state.rangedReadyAt then
		return
	end
	local ranged = Hero.ranged
	state.rangedReadyAt = now + ranged.cooldown
	state.nextActionAt = now + ranged.windup + ranged.recovery
	state.comboIndex = 0
	state.comboExpiresAt = 0

	gameEvent:FireServer("HeroRanged", { aim = aimDirection() })

	playClip("bow")
	task.delay(ranged.windup, function()
		playHeroSound("HeroBowRelease", rootPart(), 0.4, 1.1)
	end)
	HeroDebug:info("Bow shot")
end

local function sendBlock(blocking: boolean)
	if state.blocking == blocking then
		return
	end
	state.blocking = blocking
	gameEvent:FireServer("HeroBlock", { blocking = blocking, aim = aimDirection() })
	if blocking then
		playClip("block")
	else
		stopClip("block")
	end
end

-- -- DODGE -------------------------------------------------------------------
--
-- The CLIENT moves the character; the SERVER owns the i-frames and the cooldown.
-- See the matching note in server/Combat/HeroCombat.luau — the character has
-- client network ownership, so a server-side CFrame write or LinearVelocity
-- fights this simulation and rubber-bands.
--
-- The roll is driven by rewriting AssemblyLinearVelocity's horizontal components
-- each frame, leaving Y alone so gravity still applies. A LinearVelocity
-- constraint with a Vector target would pin Y to zero and float the character
-- across the map.

local dodgeUntil = 0
local dodgeVelocity = Vector3.zero
local dodgeRestoreAutoRotate: boolean? = nil

local function sendDodge()
	local now = os.clock()
	if now < state.dodgeReadyAt or now < state.nextActionAt then
		return
	end
	local model = character()
	local humanoid = humanoidOf(model)
	local root = rootPart()
	if not model or not humanoid or not root then
		return
	end

	local dodge = Hero.dodge
	-- Roll in the direction the player is actually moving; backwards if standing
	-- still, which is the reliable "get me out of here" default.
	local moveDirection = humanoid.MoveDirection
	local direction: Vector3
	if moveDirection.Magnitude > 0.1 then
		direction = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit
	else
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		direction = if flat.Magnitude > 1e-3 then -flat.Unit else Vector3.new(0, 0, 1)
	end

	local travelTime = dodge.distance / math.max(dodge.speed, 1)
	state.dodgeReadyAt = now + dodge.cooldown
	state.nextActionAt = now + travelTime + dodge.recovery
	state.comboIndex = 0
	state.comboExpiresAt = 0
	if state.blocking then
		-- The server drops the shield on a dodge; mirror it or the two disagree
		-- about whether RMB is still held.
		state.blocking = false
		stopClip("block")
	end

	gameEvent:FireServer("HeroDodge", { direction = direction })

	dodgeUntil = now + travelTime
	dodgeVelocity = direction * dodge.speed
	if dodgeRestoreAutoRotate == nil then
		dodgeRestoreAutoRotate = humanoid.AutoRotate
	end
	humanoid.AutoRotate = false

	playClip("dodge")
	playHeroSound("HeroDodge", root, 0.35, 1.15)
	addShake(0.25, 0.12)
	HeroDebug:info("Dodge roll", { direction = direction })
end

-- ---------------------------------------------------------------------------
-- INPUT
-- ---------------------------------------------------------------------------
--
-- LMB is tap-vs-hold: a tap (released before heavy.holdSeconds) is a light
-- attack, holding past it commits a heavy. The heavy fires the MOMENT the
-- threshold passes rather than on release, so the player gets feedback while
-- still holding — waiting for release makes a held button feel broken.

-- The tap-vs-hold state machine is factored out of the mouse handler so the
-- on-screen touch attack button can drive the IDENTICAL code path (see the
-- ViewMode.HeroActionRequested subscription below). Sharing the two functions —
-- and, crucially, the same `state.lmbDownAt` / `state.heavyFired` fields — means
-- the heavy auto-commit in onPoseStep and the reticle's charge readout work for
-- touch for free, and mobile can never end up with a different hold threshold
-- than desktop.
local function beginAttackHold()
	if not canFight() then
		return
	end
	state.lmbDownAt = os.clock()
	state.heavyFired = false
end

local function endAttackHold()
	local downAt = state.lmbDownAt
	state.lmbDownAt = nil
	if downAt and not state.heavyFired and canFight() then
		if os.clock() - downAt < Hero.heavy.holdSeconds then
			sendLight()
		end
	end
	state.heavyFired = false
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not canFight() then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		beginAttackHold()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		sendBlock(true)
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == keyFor("HeroRangedAttack") then
			sendRanged()
		elseif input.KeyCode == keyFor("HeroDodge") then
			sendDodge()
		elseif input.KeyCode == keyFor("HeroHeavyAttack") then
			-- Hold-LMB is the primary heavy trigger, but HeroHeavyAttack is listed
			-- in the rebindable keybindings UI, so it has to actually do something
			-- — a key the settings screen advertises and silently ignores reads as
			-- a bug. Fires immediately (no hold threshold): the whole point of the
			-- dedicated key is that it skips the charge-up ambiguity.
			sendHeavy()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- InputEnded is deliberately NOT gated on canFight(): if the player leaves
	-- hero mode while holding RMB we still have to release the block, or the
	-- server keeps him guarding forever.
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		endAttackHold()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		sendBlock(false)
	end
end)

-- ---------------------------------------------------------------------------
-- ON-SCREEN (TOUCH) INPUT
-- ---------------------------------------------------------------------------
--
-- The touch HUD cluster (ui/screens/HUD/HeroTouchControls) cannot require this
-- module — it lives in the other client script tree — so it raises requests on
-- ViewMode and we route them here. Every branch lands on the same function the
-- mouse/keyboard path uses, so the client cooldown mirror, the combo prediction
-- and the canFight() gate are shared rather than reimplemented in the UI.
--
-- Begin phases are gated exactly like InputBegan is. "Block"/"End" deliberately
-- is NOT gated on canFight(), for the same reason InputEnded isn't: if the
-- player leaves hero mode, dies, or the HUD unmounts mid-guard, the release must
-- still reach the server or the hero guards forever. sendBlock() early-returns
-- when the state already matches, so a redundant release from the UI's several
-- overlapping safety nets is free.
local connectionCleanups: { () -> () } = {}

table.insert(
	connectionCleanups,
	ViewMode.HeroActionRequested:connect(function(action: string, phase: string)
		if action == "Block" then
			if phase == "End" then
				sendBlock(false)
			elseif canFight() then
				sendBlock(true)
			end
			return
		end

		if phase == "End" then
			if action == "Attack" then
				endAttackHold()
			end
			return
		end

		if not canFight() then
			return
		end
		if action == "Attack" then
			beginAttackHold()
		elseif action == "Light" then
			sendLight()
		elseif action == "Heavy" then
			sendHeavy()
		elseif action == "Dodge" then
			sendDodge()
		elseif action == "Ranged" then
			sendRanged()
		end
	end)
)

-- ---------------------------------------------------------------------------
-- SERVER FEEDBACK INTAKE
-- ---------------------------------------------------------------------------
--
-- CombatEffectsClient draws the world VFX for every hero. This connection exists
-- only for reactions that must be limited to the LOCAL hero: camera kick,
-- hit-stop, the parry flash and the parry pose.

type CombatEvent = {
	t: string,
	p: Vector3?,
	p2: Vector3?,
	d: number?,
	n: string?,
	f: number?,
	m: Model?,
}

combatEvents.OnClientEvent:Connect(function(events: { CombatEvent })
	local model = player.Character
	if not model then
		return
	end
	for _, event in events do
		if event.t ~= "himpact" or event.m ~= model then
			continue
		end
		local kind = event.n
		local position = event.p
		if kind == "confirm" then
			-- Hit-stop + kick scaled by how much damage the swing actually did, so
			-- a finisher through four peasants lands harder than a poke.
			local weight = math.clamp((event.d or 0) / 200, 0.25, 1)
			state.hitStopUntil = os.clock() + 0.05 + 0.05 * weight
			addShake(0.35 + 0.5 * weight, 0.14)
		elseif kind == "parry" then
			if position then
				parryFlash(position)
			end
			playHeroSound("HeroParry", rootPart(), 0.7, 1.0)
			addShake(0.8, 0.22)
			state.hitStopUntil = os.clock() + 0.09
			playClip("parry")
		elseif kind == "block" then
			if position then
				blockSpark(position)
			end
			playHeroSound("HeroBlock", rootPart(), 0.5, 0.95 + math.random() * 0.1)
			addShake(0.3, 0.12)
		end
	end
end)

-- ---------------------------------------------------------------------------
-- PER-FRAME: POSE, DODGE MOVEMENT, RETICLE
-- ---------------------------------------------------------------------------

local POSE_STEP = "HeroCombatPose"
local SHAKE_STEP = "HeroCombatShake"

local function updateReticle(now: number)
	local active = getReticle()
	local visible = ViewMode.isCombatReady()
	if active.gui.Enabled ~= visible then
		active.gui.Enabled = visible
	end
	if not visible then
		return
	end

	-- Charging a heavy: LMB is down and past the hold threshold.
	local downAt = state.lmbDownAt
	local charging = downAt ~= nil and (now - (downAt :: number)) >= Hero.heavy.holdSeconds * 0.5
	local onCooldown = now < state.nextActionAt

	local gap: number
	local color: Color3
	if state.blocking then
		gap = 10
		color = COLOR_BLOCK
	elseif charging then
		-- Widen with charge so the player can feel the commitment building.
		local charge = math.clamp((now - (downAt :: number)) / Hero.heavy.holdSeconds, 0, 1)
		gap = 12 + 14 * charge
		color = COLOR_CHARGING
	elseif onCooldown then
		gap = 8
		color = COLOR_COOLDOWN
	else
		gap = 12
		color = COLOR_IDLE
	end

	local offsets = { UDim2.new(0.5, 0, 0.5, -gap), UDim2.new(0.5, 0, 0.5, gap), UDim2.new(0.5, -gap, 0.5, 0), UDim2.new(0.5, gap, 0.5, 0) }
	for index, tick in active.ticks do
		tick.Position = offsets[index]
		tick.BackgroundColor3 = color
	end

	local stroke = active.ring:FindFirstChild("Stroke") :: UIStroke?
	if stroke then
		stroke.Transparency = if state.blocking then 0.15 else 1
	end

	local comboActive = now < state.comboExpiresAt
	for index, pip in active.pips do
		local lit = comboActive and index <= state.comboIndex
		pip.BackgroundTransparency = if lit then 0 else 0.8
		pip.BackgroundColor3 = if lit then COLOR_CHARGING else COLOR_IDLE
	end
end

local function onPoseStep(deltaTime: number)
	local now = os.clock()

	-- Heavy commit while the button is still held.
	local downAt = state.lmbDownAt
	if downAt and not state.heavyFired and now - (downAt :: number) >= Hero.heavy.holdSeconds then
		state.heavyFired = true
		if canFight() then
			sendHeavy()
		end
	end

	-- Dodge movement. Rewritten every frame because the Humanoid's own controller
	-- overwrites velocity constantly; a one-shot impulse dies immediately.
	if now < dodgeUntil then
		local root = rootPart()
		if root then
			local current = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(dodgeVelocity.X, current.Y, dodgeVelocity.Z)
		end
	elseif dodgeRestoreAutoRotate ~= nil then
		local humanoid = humanoidOf(character())
		if humanoid then
			humanoid.AutoRotate = dodgeRestoreAutoRotate :: boolean
		end
		dodgeRestoreAutoRotate = nil
	end

	updateReticle(now)

	-- Publish the predicted cooldown state so the touch buttons can dim from the
	-- SAME numbers the crosshair above uses. Mutates a shared table in place (no
	-- allocation, no signal fire) precisely because this runs every frame; the UI
	-- polls it and re-renders only when a derived boolean flips.
	ViewMode.setHeroStatus(
		state.nextActionAt,
		state.dodgeReadyAt,
		state.rangedReadyAt,
		state.blocking,
		if now < state.comboExpiresAt then state.comboIndex else 0,
		canFight()
	)

	-- -- Procedural pose ---------------------------------------------------
	local model = character()
	if not model then
		clipWeight = 0
		return
	end
	local set = resolveMotors(model)

	local clip = activeClip
	if clip then
		-- Hit-stop: freeze the swing for a few frames on impact. This is the entire
		-- reason clipTime is accumulated rather than derived from a start
		-- timestamp — you cannot pause a `now - startTime` clock.
		if now >= state.hitStopUntil then
			clipTime += deltaTime
		end
		if clip.hold then
			clipTime = math.min(clipTime, clip.duration)
			if not state.blocking then
				stopClip(activeClipName)
			end
		elseif clipTime >= clip.duration then
			stopClip(activeClipName)
		end
	end

	local targetWeight = if activeClip then 1 else 0
	local blendRate = if targetWeight > clipWeight then POSE_BLEND_IN else POSE_BLEND_OUT
	clipWeight += (targetWeight - clipWeight) * math.clamp(deltaTime / blendRate, 0, 1)
	if clipWeight <= 0.005 and targetWeight == 0 then
		clipWeight = 0
		return -- fully faded out: leave Transform alone so the stock idle plays
	end

	local pose = if activeClip then samplePose(activeClip :: Clip, clipTime) else IDENTITY_POSE

	-- Written every frame at a render-step priority AFTER Character so it
	-- supersedes the stock animate script's Transform write for this frame. If a
	-- real uploaded animation is ever installed for this action, playClip clears
	-- activeClip and this loop stops writing entirely rather than fighting it.
	local function apply(motor: Motor6D?, target: CFrame?)
		if not motor then
			return
		end
		motor.Transform = motor.Transform:Lerp(motor.Transform * (target or CFrame.identity), clipWeight)
	end
	apply(set.rightShoulder, pose.rightShoulder)
	apply(set.leftShoulder, pose.leftShoulder)
	apply(set.waist, pose.waist)
end

RunService:BindToRenderStep(POSE_STEP, Enum.RenderPriority.Character.Value + 1, onPoseStep)
RunService:BindToRenderStep(SHAKE_STEP, Enum.RenderPriority.Camera.Value + 10, applyCameraShake)

-- ---------------------------------------------------------------------------
-- LIFECYCLE
-- ---------------------------------------------------------------------------

player.CharacterAdded:Connect(function()
	-- Fresh rig: drop cached motors/tracks or we keep writing Transform to joints
	-- that belong to a destroyed character (a genuine leak, since the cache would
	-- hold the old model alive).
	motorCharacter = nil
	motors = {}
	trackCharacter = nil
	table.clear(loadedTracks)
	stopClip(nil)
	clipWeight = 0
	dodgeUntil = 0
	dodgeRestoreAutoRotate = nil
	resetPredictedState()
end)

-- Leaving hero mode must release a held block. Without this, toggling to RTS with
-- RMB down leaves the server-side hero permanently guarding — and because
-- InputEnded for that click never arrives while the RTS handler owns the mouse,
-- nothing would ever clear it.
table.insert(connectionCleanups, ViewMode.Changed:connect(function(newMode: string)
	if newMode ~= "Hero" then
		if state.blocking then
			state.blocking = false
			gameEvent:FireServer("HeroBlock", { blocking = false, aim = aimDirection() })
		end
		state.lmbDownAt = nil
		state.heavyFired = false
		stopClip(nil)
	end
end))

table.insert(connectionCleanups, ViewMode.AimChanged:connect(function(newAim: string)
	-- Dropping out of the locked crosshair (mouse released to look around) is not
	-- a combat posture; release the shield the same way.
	if newAim ~= "Locked" and state.blocking then
		state.blocking = false
		gameEvent:FireServer("HeroBlock", { blocking = false, aim = aimDirection() })
		stopClip("block")
	end
end))

--- Drop every ViewMode subscription and unbind the render steps. ViewMode's
--- `connect` hands back a plain closure rather than an RBXScriptConnection, so
--- an untracked listener here would keep this whole module (and the character it
--- caches motors for) alive forever — the exact leak pattern this codebase has
--- been bitten by before. Also releases a held block on the way out, since a
--- controller that stops listening can no longer send the release itself.
function HeroCombatController.destroy()
	if state.blocking then
		state.blocking = false
		gameEvent:FireServer("HeroBlock", { blocking = false, aim = aimDirection() })
	end
	for _, disconnect in ipairs(connectionCleanups) do
		local ok, err = pcall(disconnect)
		if not ok then
			HeroDebug:warn("Cleanup failed", { error = err })
		end
	end
	table.clear(connectionCleanups)
	RunService:UnbindFromRenderStep(POSE_STEP)
	RunService:UnbindFromRenderStep(SHAKE_STEP)
end

-- Studio's "stop playtest" tears the script tree down; without this the render
-- steps keep firing against a half-destroyed character for a frame or two.
script.Destroying:Once(function()
	HeroCombatController.destroy()
end)

HeroDebug:info("HeroCombatController initialized", {
	comboSteps = #Hero.lightCombo,
	heavyHold = Hero.heavy.holdSeconds,
	rangedKey = keyFor("HeroRangedAttack").Name,
	dodgeKey = keyFor("HeroDodge").Name,
})

return HeroCombatController
