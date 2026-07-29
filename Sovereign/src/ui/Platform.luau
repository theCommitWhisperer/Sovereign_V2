--!strict
-- Platform: single source of truth for "what device is this, and how should
-- the HUD lay itself out". Per docs/EconomyRedesign.md section 8 -- one
-- component tree, one state store (HUDStore), and this: a device/layout
-- module everything else reads instead of re-deriving TouchEnabled checks.
--
-- Deliberately a PLAIN MODULE, not a React component: input handlers, camera
-- controllers and other non-UI client code need to read Platform.kind /
-- Platform.pointer too, and they must not have to pull in React to do it.
--
-- ---------------------------------------------------------------------------
-- DESKTOP-VS-MOBILE DETECTION
-- ---------------------------------------------------------------------------
-- Many Windows laptops and all Surface-style tablets report BOTH
-- UserInputService.TouchEnabled and KeyboardEnabled at the same time. Treating
-- "has touch" as "is mobile" misclassifies every one of those as a phone.
-- ViewToggleButton (src/ui/screens/HUD/ViewToggleButton.luau, ~line 62) already
-- hit this for its own touch-vs-desktop check and settled on: a keyboard
-- present means it's a desktop-shaped experience, touch or not. This module
-- applies the same rule for the whole HUD rather than re-deriving it per
-- component. GuiService:IsTenFootInterface() is checked first because it is
-- the one unambiguous signal Roblox exposes for "this is a living-room
-- console", which is neither of the other two buckets.
--
-- ---------------------------------------------------------------------------
-- WHY onChanged EXISTS
-- ---------------------------------------------------------------------------
-- None of these signals are fixed for the life of a session: a gamepad can be
-- plugged in mid-game, a player can resize the Studio/desktop window across
-- the point where the compact drawer layout should kick in, and a tablet can
-- be rotated. AdaptiveHUD subscribes to this to swap DesktopShell/MobileShell
-- live instead of only deciding once at mount.

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local UIConfig = require(script.Parent.UIConfig)

export type Kind = "Desktop" | "Mobile" | "Console"
export type Pointer = "Mouse" | "Touch" | "Gamepad"

export type Tokens = {
	hitTarget: number, -- minimum interactive control size, in pixels
	fontScale: number, -- multiply base TextSize by this
	padding: number, -- baseline spacing unit
	panelWidth: number, -- default width for a side panel / drawer
	cornerRadius: number, -- default UICorner radius
	bottomBarHeight: number, -- height of the primary bottom chrome bar
}

export type SafeArea = {
	Top: number,
	Bottom: number,
	Left: number,
	Right: number,
}

local Platform = {}

-- Desktop numbers intentionally match what HUD.luau already hardcodes
-- (UIConfig.HUD.BottomBarHeight, the 8px gaps components use today) so that
-- routing an existing panel through Platform.tokens on Desktop is a no-op --
-- see the "Keep visual output the same on desktop" constraint on the panel
-- migrations. Mobile/Console numbers are new judgment calls, not preserved
-- values, since neither layout existed before this module.
local TOKENS_BY_KIND: { [Kind]: Tokens } = {
	Desktop = {
		hitTarget = 28,
		fontScale = 1.0,
		padding = 8,
		panelWidth = 400,
		cornerRadius = 4,
		bottomBarHeight = UIConfig.HUD.BottomBarHeight,
	},
	Mobile = {
		hitTarget = 44, -- design rule: touch targets >= 44px
		fontScale = 1.15,
		padding = 14,
		panelWidth = 340,
		cornerRadius = 10,
		-- Thumb-zone action bar, NOT the desktop 300px bottom bar: mobile's
		-- bottom chrome is selection-driven and one bar tall, not a permanent
		-- minimap+categories+content-area strip (see MobileShell).
		bottomBarHeight = 120,
	},
	Console = {
		-- Gamepad focus needs the same generous target touch does -- a thumb-
		-- stick-driven cursor overshoots a 28px desktop-sized target constantly.
		hitTarget = 44,
		fontScale = 1.1,
		padding = 12,
		panelWidth = 380,
		cornerRadius = 6,
		bottomBarHeight = UIConfig.HUD.BottomBarHeight,
	},
}

-- Below this viewport width, even a Desktop-kind window needs the compact
-- drawer treatment. Deliberately independent of Kind: see Platform.isCompact().
local COMPACT_BREAKPOINT_X = 900

local function computeKind(): Kind
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Mobile"
	end
	return "Desktop"
end

local function isGamepadInputType(inputType: Enum.UserInputType): boolean
	-- Covers Gamepad1..Gamepad8 without enumerating all eight by name.
	return inputType.Name:sub(1, 7) == "Gamepad"
end

local function computePointer(kind: Kind): Pointer
	if kind == "Console" then
		return "Gamepad"
	end
	-- LastInputType tracks what the player is ACTUALLY using right now, which
	-- is the right signal for input hints (e.g. "[E]" vs a tap icon) on a
	-- hybrid device that has both a mouse and a touchscreen.
	local lastInput = UserInputService:GetLastInputType()
	if lastInput == Enum.UserInputType.Touch then
		return "Touch"
	elseif isGamepadInputType(lastInput) then
		return "Gamepad"
	elseif kind == "Mobile" then
		return "Touch"
	end
	return "Mouse"
end

local function computeSafeArea(kind: Kind): SafeArea
	local topLeft, bottomRight = GuiService:GetGuiInset()
	-- Roblox exposes no notch/gesture-bar API, so this is a fixed heuristic
	-- buffer rather than a measured value -- good enough to keep the bottom
	-- action bar clear of a home indicator, not a substitute for real safe-area
	-- data if Roblox ever adds it.
	local gestureAllowance = if kind == "Mobile" then 24 else 0
	return {
		Top = topLeft.Y,
		Left = topLeft.X,
		Right = bottomRight.X,
		Bottom = bottomRight.Y + gestureAllowance,
	}
end

Platform.kind = computeKind()
Platform.pointer = computePointer(Platform.kind)
Platform.tokens = TOKENS_BY_KIND[Platform.kind]
Platform.safeArea = computeSafeArea(Platform.kind)

function Platform.isCompact(): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		-- No camera yet (very early client bootstrap): fall back to Kind alone
		-- rather than crashing a component that renders before workspace does.
		return Platform.kind == "Mobile"
	end
	return camera.ViewportSize.X < COMPACT_BREAKPOINT_X
end

-- ---------------------------------------------------------------------------
-- CHANGE NOTIFICATION
-- ---------------------------------------------------------------------------
-- Plain callback set, same shape as ViewMode's signal (src/shared/ViewMode.luau):
-- returns an unsubscribe closure, iterates a snapshot so a listener can
-- disconnect mid-fire, and pcalls each listener so one throwing subscriber
-- can't stop the others from hearing a device change.

type Listener = () -> ()
local listeners: { [Listener]: true } = {}
local lastCompact = Platform.isCompact()

local function refresh()
	local kind = computeKind()
	local pointer = computePointer(kind)
	local compact = Platform.isCompact()
	local changed = kind ~= Platform.kind or pointer ~= Platform.pointer or compact ~= lastCompact

	Platform.kind = kind
	Platform.pointer = pointer
	Platform.tokens = TOKENS_BY_KIND[kind]
	Platform.safeArea = computeSafeArea(kind)
	lastCompact = compact

	if not changed then
		return
	end
	for listener in table.clone(listeners) do
		local ok, err = pcall(listener)
		if not ok then
			warn(`[Platform] onChanged listener errored: {err}`)
		end
	end
end

--- Fires whenever Kind, Pointer, or the compact breakpoint crosses (gamepad
--- connected/disconnected, input method switched, window/viewport resized).
--- Returns an unsubscribe function; callers MUST call it on unmount or this
--- leaks exactly like the connections HUD.luau doesn't clean up today.
function Platform.onChanged(callback: Listener): () -> ()
	listeners[callback] = true
	local disconnected = false
	return function()
		if disconnected then
			return
		end
		disconnected = true
		listeners[callback] = nil
	end
end

-- These are module-level (never disconnected) by design, same as ViewMode's
-- underlying wiring: Platform is a process-lifetime singleton, not something
-- that mounts/unmounts, so there is no "unmount" to disconnect on.
local viewportConnection: RBXScriptConnection? = nil

local function bindCamera(camera: Camera?)
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
end

bindCamera(Workspace.CurrentCamera)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera(Workspace.CurrentCamera)
	refresh()
end)

UserInputService.LastInputTypeChanged:Connect(refresh)
UserInputService.GamepadConnected:Connect(refresh)
UserInputService.GamepadDisconnected:Connect(refresh)

return Platform
