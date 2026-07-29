--!strict
-- ViewToggleButton: on-screen control for switching between the overhead RTS
-- view and the third-person Hero view, plus a first/third person flip once in
-- Hero view.
--
-- ---------------------------------------------------------------------------
-- WHY THIS EXISTS
-- ---------------------------------------------------------------------------
-- The view toggle was keyboard-only (V). On a touch device there was no way to
-- reach hero view at all, and on desktop nothing on screen told a new player the
-- second view existed. This is the discoverable, no-keyboard path to both.
--
-- ---------------------------------------------------------------------------
-- HOW IT TALKS TO THE CAMERA
-- ---------------------------------------------------------------------------
-- It doesn't, directly. This component lives in the React tree under
-- StarterPlayerScripts.UI; the camera lives under StarterPlayerScripts.Client.
-- Neither can require the other by a relative path. So the button raises
-- ViewMode.requestToggle() and the camera controller — the only writer of
-- ViewMode — decides whether to honour it. That routes the tap into the exact
-- same method the V key calls, so the two can never drift apart, and the
-- debounce/mid-transition rules only have to be correct in one place.
--
-- State comes back the same way: we re-render off ViewMode.Changed /
-- TransitionChanged rather than polling.

local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ViewMode = require(ReplicatedStorage.Shared.ViewMode)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

-- KeybindingsManager lives in the OTHER client script tree
-- (PlayerScripts.Client.Camera), so it is resolved lazily and defensively rather
-- than with a top-level require: at module-eval time that tree may not have
-- replicated yet, and a yield or throw here would take the whole HUD down over a
-- cosmetic key hint. Cached after the first success; nil just means "no hint".
local cachedKeybindings: any = nil

local function getKeybindingsManager(): any
	if cachedKeybindings then
		return cachedKeybindings
	end
	local ok, result = pcall(function()
		local playerScripts = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerScripts")
		local client = playerScripts and playerScripts:FindFirstChild("Client")
		local camera = client and client:FindFirstChild("Camera")
		local module = camera and camera:FindFirstChild("KeybindingsManager")
		return module and require(module :: ModuleScript)
	end)
	if ok and result then
		cachedKeybindings = result
	end
	return cachedKeybindings
end

-- Touch devices get a bigger target and no key hints. A device can report BOTH
-- touch and keyboard (Surface, iPad + Magic Keyboard), so "is there a keyboard"
-- is the right question for hints, not "is there a touchscreen".
local function isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- 56px is the smallest comfortable touch target; desktop can afford to be
-- smaller since it is a mouse click and the key is the primary path anyway.
local function buttonHeight(): number
	return if isTouchOnly() then 56 else 44
end

local function buttonWidth(): number
	return if isTouchOnly() then 132 else 116
end

local function keyHint(action: string): string
	if isTouchOnly() then
		return ""
	end
	local manager = getKeybindingsManager()
	if not manager then
		return ""
	end
	local ok, keyCode = pcall(function()
		return manager.GetKeybinding(action)
	end)
	if not ok or not keyCode then
		return ""
	end
	return `  [{(keyCode :: Enum.KeyCode).Name}]`
end

type Props = {}

type State = {
	mode: string,
	transitioning: boolean,
	firstPerson: boolean,
}

local ViewToggleButton = React.Component:extend("ViewToggleButton")

function ViewToggleButton:init()
	self:setState({
		mode = ViewMode.get(),
		transitioning = ViewMode.isTransitioning(),
		firstPerson = false,
	})
	-- ViewMode's connect returns a plain closure, not an RBXScriptConnection, so
	-- these are stored as functions and called on unmount. Storing them at all is
	-- the point: an unmounted component still holding a live listener is exactly
	-- the leak pattern this codebase has been bitten by.
	self._disconnects = {} :: { () -> () }
end

function ViewToggleButton:didMount()
	table.insert(
		self._disconnects,
		ViewMode.Changed:connect(function(newMode: string)
			-- Leaving hero view always drops the first-person flag: the camera
			-- resets it on exit, and a stale `true` would mislabel the button on
			-- the next entry.
			self:setState({
				mode = newMode,
				firstPerson = if newMode == ViewMode.Modes.Hero then self.state.firstPerson else false,
			})
		end)
	)
	table.insert(
		self._disconnects,
		ViewMode.TransitionChanged:connect(function(isTransitioning: boolean)
			self:setState({ transitioning = isTransitioning })
		end)
	)
end

function ViewToggleButton:willUnmount()
	for _, disconnect in ipairs(self._disconnects) do
		disconnect()
	end
	self._disconnects = {}
end

function ViewToggleButton:render()
	local state = self.state :: State
	local inHero = state.mode == ViewMode.Modes.Hero
	local busy = state.transitioning

	local height = buttonHeight()
	local width = buttonWidth()

	local children: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),

		-- Primary: swap views. Label names the view you'd be GOING to, not the one
		-- you're in — a button captioned with the current state reads as a status
		-- readout and players hesitate to press it.
		ViewButton = React.createElement("TextButton", {
			Name = "ViewButton",
			LayoutOrder = 1,
			Size = UDim2.new(0, width, 0, height),
			BackgroundColor3 = if inHero
				then UIConfig.HUD.DarkWood
				else Color3.fromRGB(61, 74, 43),
			BackgroundTransparency = if busy then 0.55 else 0.15,
			BorderSizePixel = 0,
			AutoButtonColor = not busy,
			Text = if inHero then `?  Command{keyHint("ToggleCameraMode")}` else `?  Fight{keyHint("ToggleCameraMode")}`,
			Font = Enum.Font.GothamBold,
			TextSize = if isTouchOnly() then 15 else 13,
			TextColor3 = UIConfig.Color.Primary,
			TextTransparency = if busy then 0.4 else 0,
			ZIndex = 60,
			[React.Event.Activated] = function()
				-- Swallow taps mid-blend. The camera would debounce it anyway, but
				-- letting the press visibly do nothing is better feedback than
				-- queueing a switch the player has already stopped expecting.
				if ViewMode.isTransitioning() then
					return
				end
				ViewMode.requestToggle()
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Stroke = React.createElement("UIStroke", {
				Color = UIConfig.HUD.AccentGold,
				Transparency = if busy then 0.7 else 0.35,
				Thickness = 1.5,
			}),
			Padding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		}),
	}

	-- Secondary: first/third person. Only meaningful in hero view, so it is not
	-- rendered at all in RTS rather than being shown disabled — a permanently
	-- dead button trains players to ignore that corner of the screen.
	if inHero then
		children.PerspectiveButton = React.createElement("TextButton", {
			Name = "PerspectiveButton",
			LayoutOrder = 2,
			Size = UDim2.new(0, width, 0, height - 6),
			BackgroundColor3 = UIConfig.HUD.DarkWood,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Text = if state.firstPerson
				then `??  3rd Person{keyHint("HeroFirstPerson")}`
				else `??  1st Person{keyHint("HeroFirstPerson")}`,
			Font = Enum.Font.Gotham,
			TextSize = if isTouchOnly() then 14 else 12,
			TextColor3 = UIConfig.Color.Secondary,
			ZIndex = 60,
			[React.Event.Activated] = function()
				if ViewMode.isTransitioning() then
					return
				end
				ViewMode.requestFirstPersonToggle()
				-- Optimistic: the camera owns zoom state and publishes no signal for
				-- it, so the label tracks our own request. Reset whenever hero view
				-- is left (see the Changed handler) so it cannot desync for long.
				self:setState({ firstPerson = not self.state.firstPerson })
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Stroke = React.createElement("UIStroke", {
				Color = UIConfig.HUD.StrokeColor,
				Transparency = 0.55,
				Thickness = 1,
			}),
			Padding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		})
	end

	return React.createElement("Frame", {
		Name = "ViewToggleCluster",
		-- Right edge, below the top bar: clear of the minimap (bottom-right) and
		-- the building menu (bottom). AnchorPoint on the right keeps it pinned to
		-- the edge across every aspect ratio instead of drifting on ultrawide.
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, UIConfig.HUD.TopBarHeight + 14),
		Size = UDim2.new(0, width, 0, height * 2 + 8),
		BackgroundTransparency = 1,
		ZIndex = 60,
	}, children)
end

return ViewToggleButton
