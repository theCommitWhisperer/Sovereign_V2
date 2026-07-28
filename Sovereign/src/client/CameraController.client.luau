--!strict
-- CameraController: thin bootstrapper for the two-view camera system.
--
-- The camera itself lives in Camera/StudioCameraController (RTS rig + Hero
-- third-person camera). This script only decides WHEN it comes up and routes the
-- rebindable view keys to it.
--
-- View state is published on ReplicatedStorage.Shared.ViewMode; nothing here or
-- anywhere else should read player.CameraMode to find out which view is active
-- (hero view is third person, so CameraMode reads Classic in both).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local CameraDebug = DebugManager.createChannel("Camera", false)

local ViewMode = require(ReplicatedStorage.Shared.ViewMode)
local StudioCameraController = require(script.Parent.Camera.StudioCameraController)
-- Keybindings are the single source of truth for the view keys, so rebinding in
-- Settings > Controls actually takes effect here.
local KeybindingsManager = require(script.Parent.Camera.KeybindingsManager)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local gameEvent = RemoteEvents:WaitForChild("GameEvent") :: RemoteEvent

local cameraController: StudioCameraController.StudioCameraController? = nil

-- ContextActionService, not UserInputService.InputBegan, for the hero keys.
-- Both read their KeyCode from KeybindingsManager, so a player rebinding the
-- action in Settings > Controls takes effect on the next rebind callback without
-- touching this file.
--
-- CAS (rather than InputBegan) because these are context-scoped: returning Pass
-- whenever we are not in hero view means the key keeps whatever meaning it has
-- everywhere else in the game, instead of being swallowed globally. That matters
-- most for keys a player might rebind onto something the engine also uses.
-- No hero default is Tab — the engine reserves it for GUI focus.
local HERO_ACTION_PRIORITY = 3000
local FIRST_PERSON_ACTION = "SovereignHeroFirstPerson"
local FREE_LOOK_ACTION = "SovereignHeroFreeLook"

local function bindFirstPersonAction()
	ContextActionService:UnbindAction(FIRST_PERSON_ACTION)

	local keyCode = KeybindingsManager.GetKeybinding("HeroFirstPerson")
	if not keyCode then
		return
	end

	ContextActionService:BindActionAtPriority(
		FIRST_PERSON_ACTION,
		function(_actionName: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			local controller = cameraController
			if not controller or not controller:IsHeroMode() then
				return Enum.ContextActionResult.Pass
			end
			controller:ToggleHeroFirstPerson()
			return Enum.ContextActionResult.Sink
		end,
		false,
		HERO_ACTION_PRIORITY,
		keyCode
	)
end

local function bindFreeLookAction()
	ContextActionService:UnbindAction(FREE_LOOK_ACTION)

	local keyCode = KeybindingsManager.GetKeybinding("HeroFreeLook")
	if not keyCode then
		return
	end

	-- Free look is a HOLD: release always returns to the shift-lock combat
	-- posture. Cancel is handled too, otherwise alt-tabbing mid-hold would leave
	-- the player permanently unable to attack (ViewMode.isCombatReady() is false
	-- in the Free posture).
	ContextActionService:BindActionAtPriority(
		FREE_LOOK_ACTION,
		function(_actionName: string, state: Enum.UserInputState): Enum.ContextActionResult
			local controller = cameraController
			if not controller or not controller:IsHeroMode() then
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.Begin then
				controller:SetHeroAimMode(ViewMode.AimModes.Free)
				return Enum.ContextActionResult.Sink
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				controller:SetHeroAimMode(ViewMode.AimModes.Locked)
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		HERO_ACTION_PRIORITY,
		keyCode
	)
end

local function bindHeroActions()
	bindFirstPersonAction()
	bindFreeLookAction()
end

-- Rebind when the player changes the key in Settings > Controls.
KeybindingsManager.OnKeybindingChanged("HeroFirstPerson", function()
	bindFirstPersonAction()
end)
KeybindingsManager.OnKeybindingChanged("HeroFreeLook", function()
	bindFreeLookAction()
end)

-- If the player was already holding free-look when they flipped into hero view
-- (hold Alt, tap V) ContextActionService never sends another Begin, so the
-- posture would silently be wrong — shift-locked while the player believes they
-- are orbiting — until they released and re-pressed. Catch it on entry instead.
ViewMode.Changed:connect(function(mode: ViewMode.Mode)
	if mode ~= ViewMode.Modes.Hero then
		return
	end
	local controller = cameraController
	local keyCode = KeybindingsManager.GetKeybinding("HeroFreeLook")
	if controller and keyCode and UserInputService:IsKeyDown(keyCode) then
		controller:SetHeroAimMode(ViewMode.AimModes.Free)
	end
end)

--- The camera must come up even if the character is late (streaming, or a
--- respawn racing the GameStarted remote). Initialize immediately with whatever
--- position we have and recentre once the Lord actually lands.
local function centerOnCharacterWhenReady()
	task.spawn(function()
		local character = player.Character or player.CharacterAdded:Wait()
		local rootPart = character:WaitForChild("HumanoidRootPart", 15)
		local controller = cameraController
		if not (rootPart and rootPart:IsA("BasePart") and controller) then
			return
		end
		-- Do not yank a player who has already driven the camera somewhere, and
		-- never fight the hero camera for control.
		if controller:GetCurrentMode() == ViewMode.Modes.RTS then
			controller:ResetCamera(rootPart.Position)
		end
	end)
end

local function initializeCamera()
	if cameraController then
		return
	end

	local controller = StudioCameraController.new()
	cameraController = controller

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local haveSpawn = rootPart ~= nil and rootPart:IsA("BasePart")
	local startPosition = if haveSpawn then (rootPart :: BasePart).Position else Vector3.zero

	controller:Initialize(startPosition)
	bindHeroActions()

	-- A Studio-authored map can expose a simple invisible MapBounds part. When
	-- present, it prevents RTS panning outside the streamed play space.
	local mapBounds = workspace:FindFirstChild("MapBounds")
	if mapBounds and mapBounds:IsA("BasePart") then
		controller:SetBoundsFromPart(mapBounds, 12)
	end

	if not haveSpawn then
		centerOnCharacterWhenReady()
	end

	CameraDebug:info("Camera system initialized", {
		spawnPos = startPosition,
		hadCharacter = haveSpawn,
		isMobile = controller.inputHandler:IsMobile(),
		isDesktop = controller.inputHandler:IsDesktop(),
	})
end

gameEvent.OnClientEvent:Connect(function(action: string)
	if action == "GameStarted" then
		initializeCamera()
	end
end)

-- On-screen buttons (HUD, React tree) raise their intent through ViewMode rather
-- than reaching into the camera directly — see the ToggleRequests section there.
-- Routing them into the SAME methods the keys call is deliberate: the button and
-- the V key are then physically incapable of behaving differently, and the
-- debounce/transition rules only have to be right in one place.
ViewMode.ToggleRequested:connect(function()
	local controller = cameraController
	if controller then
		controller:ToggleCameraMode()
	end
end)

ViewMode.FirstPersonToggleRequested:connect(function()
	local controller = cameraController
	-- Ignored outside hero view: there is no first person to toggle from the
	-- overhead RTS rig, and the HUD hides the button there anyway. Guarding here
	-- too means a stale button press mid-transition can't strand the camera.
	if controller and controller:IsHeroMode() then
		controller:ToggleHeroFirstPerson()
	end
end)

-- View switching + camera reset, driven by the (rebindable) keybindings.
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local controller = cameraController
	if not controller then
		return
	end
	-- Don't hijack keys while the player is typing in a text field.
	if UserInputService:GetFocusedTextBox() then
		return
	end

	local key = input.KeyCode
	if key == KeybindingsManager.GetKeybinding("ToggleCameraMode") then
		-- No debounce here: ToggleCameraMode owns that, and it is deliberately
		-- short so rapid flipping works.
		controller:ToggleCameraMode()
	elseif key == KeybindingsManager.GetKeybinding("ResetCamera") then
		CameraDebug:info("Reset-camera key pressed")
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			controller:ResetCamera(rootPart.Position)
		end
	end
end)

CameraDebug:info("Camera controller loaded (RTS / Hero two-view system)")
