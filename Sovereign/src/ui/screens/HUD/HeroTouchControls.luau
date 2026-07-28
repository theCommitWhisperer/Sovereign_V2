--!strict
-- HeroTouchControls: the on-screen attack / block / dodge / bow cluster for
-- hero view on touch devices.
--
-- ---------------------------------------------------------------------------
-- WHY THIS EXISTS
-- ---------------------------------------------------------------------------
-- ViewToggleButton made hero view REACHABLE without a keyboard, but hero combat
-- was still bound entirely to LMB / RMB / Q / LeftControl. A touch player could
-- enter third person, walk around with the PlayerModule thumbstick, and then do
-- nothing at all — no attack, no block, no dodge. This is the missing half.
--
-- ---------------------------------------------------------------------------
-- HOW IT TALKS TO COMBAT
-- ---------------------------------------------------------------------------
-- It doesn't own any combat logic. Same split as ViewToggleButton: this lives in
-- the React tree under StarterPlayerScripts.UI, HeroCombatController lives under
-- StarterPlayerScripts.Client, and neither can require the other by a relative
-- path. So every press raises ViewMode.requestHeroAction(action, phase) and the
-- controller routes it into the exact sendLight/sendHeavy/sendBlock/sendDodge/
-- sendRanged functions the mouse and keyboard already call.
--
-- That is the whole point: there is ONE implementation of "what a light attack
-- does", one client-side cooldown mirror, and one canFight() gate. Touch and
-- desktop cannot drift apart because there is nothing here for them to drift
-- from. In particular the attack button does NOT decide tap-vs-hold; it reports
-- Begin and End and the controller resolves it with the same
-- CombatConfig.Hero.heavy.holdSeconds clock LMB uses.
--
-- Cooldown dimming reads ViewMode.getHeroStatus(), which the controller
-- refreshes every render step from the same predicted state that drives the
-- desktop crosshair. We display it; we never re-derive it.
--
-- ---------------------------------------------------------------------------
-- THE STUCK BLOCK
-- ---------------------------------------------------------------------------
-- Block is hold-to-guard. A Begin with no matching End leaves the server-side
-- hero guarding forever — he takes 65% reduced damage and never lowers the
-- shield, and nothing in the game will ever clear it because the finger that
-- would have sent the release is long gone. Touch makes this much easier to hit
-- than mouse does: a finger can be dragged off the button, lifted outside the
-- window, stolen by a system gesture, or still be down when the HUD unmounts.
--
-- So the release is guaranteed by FIVE independent paths, any one of which is
-- sufficient. See _releaseHeld and the notes on each. Redundant releases are
-- free: HeroCombatController.sendBlock early-returns when the state already
-- matches, so it never sends a duplicate remote.
--
-- ---------------------------------------------------------------------------
-- AIM DRAG vs BUTTON PRESS
-- ---------------------------------------------------------------------------
-- HeroCamera takes touch look input from UserInputService.TouchMoved and drops
-- any event with gameProcessed == true. Roblox sets gameProcessed on a touch
-- that a GuiObject has sunk, so a drag that STARTS on one of these buttons never
-- reaches the camera and pressing a button cannot rotate the view.
--
-- The converse — a look-drag sliding over a button and triggering it — is
-- prevented because these are GuiButtons: their InputBegan only fires for a
-- touch that BEGINS inside them, and a touch that began on empty screen keeps
-- its capture for its whole lifetime.
--
-- The remaining hole was the gaps BETWEEN the buttons: a thumb landing in the
-- 12px space between Attack and Block would fall through to the RTS HUD behind
-- (on a narrow viewport that can be the building menu) and to the camera. The
-- Backdrop frame below is `Active = true` for exactly that reason — it sinks
-- every touch inside the cluster footprint without doing anything with it.

local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local ViewMode = require(ReplicatedStorage.Shared.ViewMode)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local Hero = CombatConfig.Hero

-- ---------------------------------------------------------------------------
-- LAYOUT
-- ---------------------------------------------------------------------------
--
-- A right-thumb arc. The left half of the screen is left completely alone: the
-- PlayerModule renders its movement thumbstick in the bottom-left and any
-- element we put there would either eat its touches or be eaten by it.
--
-- Sizes are all >= 56px (the smallest comfortable touch target, same number
-- ViewToggleButton uses) with 12px gaps, which is enough that a thumb aiming at
-- Block does not clip Attack.
local ATTACK_SIZE = 88 -- biggest: it is pressed the most and held for heavies
local SECONDARY_SIZE = 64
local GAP = 12
-- The cluster box is sized so that with every child anchored to its bottom-right
-- corner, nothing spills outside it — which matters because the Backdrop below
-- is exactly this size and is what stops touches falling through.
local CLUSTER_SIZE = ATTACK_SIZE + GAP + SECONDARY_SIZE -- 164
local EDGE_MARGIN = 18

-- Below this viewport width the RTS bottom bar's content area (building menu /
-- unit panel, which starts 540px into a left-anchored 1400px bar and runs to
-- ~1245px) reaches the right edge of the screen, so a bottom-right cluster would
-- sit on top of it. Above it, the cluster is clear of both the building menu and
-- the minimap (which is further left still, 185..395px) with room to spare.
local BOTTOM_BAR_CLEAR_WIDTH = 1460
-- Lifting the cluster above the bottom bar only helps if there is actually room
-- left over; on a short phone screen the 300px bar plus the 45px top bar leaves
-- nothing, and we would push the buttons off the top. In that case we stay put
-- and rely on the Backdrop to own every touch in the footprint.
local LIFT_MIN_HEIGHT = UIConfig.HUD.BottomBarHeight + CLUSTER_SIZE + UIConfig.HUD.TopBarHeight + 24

local COLOR_ATTACK = Color3.fromRGB(122, 44, 38)
local COLOR_BLOCK = Color3.fromRGB(38, 74, 122)
local COLOR_BLOCK_ACTIVE = Color3.fromRGB(70, 132, 205)
local COLOR_DODGE = Color3.fromRGB(52, 60, 74)
local COLOR_RANGED = Color3.fromRGB(56, 66, 42)
local COLOR_CHARGE = Color3.fromRGB(255, 175, 40) -- same amber the crosshair uses

-- Only genuine pointer inputs may drive combat. Without this a gamepad button or
-- an accessibility device landing on the GuiButton would start a block that no
-- touch release would ever end.
local function isPointerInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

type HeldMap = { [string]: InputObject }

type Props = {}

type State = {
	inHero: boolean,
	transitioning: boolean,
	compact: boolean,
	-- Mirrored from ViewMode.getHeroStatus(); never computed here.
	canFight: boolean,
	attackReady: boolean,
	dodgeReady: boolean,
	rangedReady: boolean,
	-- Pressed state for the two hold buttons. Kept in state (not just in _held) so
	-- the press lights up on the same frame as the touch instead of waiting for
	-- the next poll — 16ms of dead button is very noticeable under a thumb.
	blocking: boolean,
	attackHeld: boolean,
	-- 0..1 heavy charge, quantised so a held attack does not re-render the HUD
	-- on every one of the ~21 frames of the hold.
	charge: number,
}

local HeroTouchControls = React.Component:extend("HeroTouchControls")

function HeroTouchControls:init()
	self:setState({
		inHero = ViewMode.isHero(),
		transitioning = ViewMode.isTransitioning(),
		compact = false,
		canFight = false,
		attackReady = false,
		dodgeReady = false,
		rangedReady = false,
		blocking = false,
		attackHeld = false,
		charge = 0,
	})
	-- ViewMode's connect returns a plain closure, not an RBXScriptConnection, so
	-- these two lists are kept apart and torn down differently. Storing them at
	-- all is the point: an unmounted component still holding a live listener is
	-- exactly the leak pattern this codebase has been bitten by.
	self._disconnects = {} :: { () -> () }
	self._connections = {} :: { RBXScriptConnection }
	-- action name -> the InputObject currently holding it down.
	self._held = {} :: HeldMap
	self._chargeStart = nil :: number?
	-- willUnmount still has to fire the block release (see below), and that path
	-- wants to update the pressed-state visuals. Writing state to a component
	-- React is already tearing down is a warning at best, so the release path
	-- routes through here and simply skips the cosmetic half once we are going
	-- away. The remote release itself is NOT skipped — that is the whole point.
	self._unmounting = false
end

function HeroTouchControls:_safeSetState(patch: { [string]: any })
	if self._unmounting then
		return
	end
	self:setState(patch)
end

-- ---------------------------------------------------------------------------
-- HELD-BUTTON BOOKKEEPING (Attack, Block)
-- ---------------------------------------------------------------------------

function HeroTouchControls:_beginHeld(action: string, input: InputObject)
	if not isPointerInput(input) then
		return
	end
	-- A second finger on the same button while the first is still down would
	-- overwrite the tracked InputObject and orphan the first one — releasing the
	-- old one first keeps the begin/end pairing exact.
	if self._held[action] then
		self:_releaseHeld(action)
	end
	self._held[action] = input
	if action == "Attack" then
		self._chargeStart = os.clock()
	end
	ViewMode.requestHeroAction(action :: any, ViewMode.ActionPhases.Begin)
	if action == "Block" then
		self:_safeSetState({ blocking = true })
	elseif action == "Attack" then
		self:_safeSetState({ attackHeld = true, charge = 0 })
	end
end

--- Idempotent by design: every one of the five release paths calls this, and all
--- but the first find nothing to do.
function HeroTouchControls:_releaseHeld(action: string)
	if not self._held[action] then
		return
	end
	self._held[action] = nil
	if action == "Attack" then
		self._chargeStart = nil
		self:_safeSetState({ attackHeld = false, charge = 0 })
	end
	ViewMode.requestHeroAction(action :: any, ViewMode.ActionPhases.End)
	if action == "Block" then
		self:_safeSetState({ blocking = false })
	end
end

function HeroTouchControls:_releaseAllHeld()
	self:_releaseHeld("Attack")
	self:_releaseHeld("Block")
end

function HeroTouchControls:didMount()
	table.insert(
		self._disconnects,
		ViewMode.Changed:connect(function(newMode: string)
			-- RELEASE PATH 4/5: leaving hero view with a finger down. The controller
			-- clears its own block on this signal too, but we must drop OUR held
			-- bookkeeping as well or the next entry into hero view starts with a
			-- phantom held input that no release will ever match.
			if newMode ~= ViewMode.Modes.Hero then
				self:_releaseAllHeld()
			end
			self:setState({ inHero = newMode == ViewMode.Modes.Hero })
		end)
	)
	table.insert(
		self._disconnects,
		ViewMode.TransitionChanged:connect(function(isTransitioning: boolean)
			self:setState({ transitioning = isTransitioning })
		end)
	)

	-- Everything below is touch-only cost. On a desktop with no touchscreen this
	-- component renders nil and does not bind a per-frame step at all.
	if not UserInputService.TouchEnabled then
		return
	end

	-- RELEASE PATH 3/5: the touch ended anywhere on screen. A finger that is
	-- dragged off a GuiButton before lifting does not reliably deliver InputEnded
	-- to that button, so we watch the global stream and match on InputObject
	-- identity.
	table.insert(
		self._connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			for action, held in pairs(self._held) do
				if held == input then
					self:_releaseHeld(action)
				end
			end
		end)
	)

	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function()
			self:_poll()
		end)
	)
end

function HeroTouchControls:willUnmount()
	-- RELEASE PATH 5/5, and it must happen BEFORE the listeners go: once they are
	-- gone nothing in the game can lower the shield. This is the path that fires
	-- when the HUD is rebuilt or the player's character resets mid-guard.
	self._unmounting = true
	self:_releaseAllHeld()
	for _, disconnect in ipairs(self._disconnects) do
		disconnect()
	end
	self._disconnects = {}
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

-- ---------------------------------------------------------------------------
-- PER-FRAME POLL
-- ---------------------------------------------------------------------------
--
-- Polls rather than subscribes: HeroCombatController refreshes the status table
-- every render step, and firing a signal into React at 60fps would re-render the
-- whole HUD every frame. We setState only when a derived value actually flips.

function HeroTouchControls:_poll()
	local state = self.state :: State

	-- RELEASE PATH 2/5 (watchdog): the InputObject we are holding has gone to the
	-- End state but no InputEnded reached us — a system gesture, an app switch, or
	-- the touch being cancelled by Roblox. Also covers the case where hero view is
	-- exited by a path that somehow did not fire ViewMode.Changed.
	for action, held in pairs(self._held) do
		if held.UserInputState == Enum.UserInputState.End or not ViewMode.isHero() then
			self:_releaseHeld(action)
		end
	end

	if not state.inHero or not UserInputService.TouchEnabled then
		return
	end

	local now = os.clock()
	local status = ViewMode.getHeroStatus()
	local notBusy = now >= status.busyUntil

	local canFight = status.canFight
	local attackReady = canFight and notBusy
	local dodgeReady = canFight and notBusy and now >= status.dodgeReadyAt
	local rangedReady = canFight and notBusy and now >= status.rangedReadyAt

	-- Quantised to 5% steps: a 0.35s hold at 60fps is ~21 frames but only ~20
	-- distinct values, and without the quantisation an idle finger would still
	-- re-render on float noise.
	local charge = 0
	local chargeStart = self._chargeStart
	if chargeStart then
		charge = math.floor(math.clamp((now - chargeStart) / Hero.heavy.holdSeconds, 0, 1) * 20 + 0.5) / 20
	end

	if
		attackReady ~= state.attackReady
		or dodgeReady ~= state.dodgeReady
		or rangedReady ~= state.rangedReady
		or canFight ~= state.canFight
		or charge ~= state.charge
	then
		self:setState({
			canFight = canFight,
			attackReady = attackReady,
			dodgeReady = dodgeReady,
			rangedReady = rangedReady,
			charge = charge,
		})
	end

	-- Viewport is read here rather than subscribed to on the Camera so a camera
	-- swap (which happens on every respawn) cannot leave us listening to a dead
	-- instance. Only setStates when the layout band actually changes.
	local camera = Workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		local compact = viewport.X < BOTTOM_BAR_CLEAR_WIDTH and viewport.Y >= LIFT_MIN_HEIGHT
		if compact ~= state.compact then
			self:setState({ compact = compact })
		end
	end
end

-- ---------------------------------------------------------------------------
-- RENDER
-- ---------------------------------------------------------------------------

--- One combat button. `held` keeps a button interactive while a finger is on it
--- even if it has just gone on cooldown mid-press — flipping Active to false
--- under a live touch is how an InputEnded goes missing, and for Block that is
--- the stuck-shield bug.
function HeroTouchControls:_button(config: {
	name: string,
	layoutOrder: number,
	size: number,
	position: UDim2,
	color: Color3,
	glyph: string,
	label: string,
	ready: boolean,
	held: boolean,
	onBegan: ((InputObject) -> ())?,
	onEnded: ((InputObject) -> ())?,
	onLeave: (() -> ())?,
	children: { [string]: any }?,
}): any
	local interactive = config.ready or config.held
	local children: { [string]: any } = {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Color = if config.held then COLOR_CHARGE else UIConfig.HUD.AccentGold,
			Transparency = if interactive then 0.35 else 0.8,
			Thickness = if config.held then 2.5 else 1.5,
		}),
		Caption = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 1, -16),
			BackgroundTransparency = 1,
			Text = config.label,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = UIConfig.Color.Secondary,
			TextTransparency = if interactive then 0.15 else 0.6,
			ZIndex = 203,
		}),
	}
	if config.children then
		for key, value in pairs(config.children) do
			children[key] = value
		end
	end

	-- Hoisted out of the property table so the handler bodies are plain calls
	-- rather than a parenthesised expression opening a statement, which Luau will
	-- happily parse but is a well-known way to write something you did not mean.
	-- Defaulted to no-ops rather than left nil so the handlers are non-optional
	-- function values here: an optional captured in a closure does not narrow, and
	-- a `nil` slipping into a React.Event slot silently drops the binding — which
	-- for Block would mean a press with no release.
	local noopInput: (InputObject) -> () = function(_input: InputObject) end
	local onBegan: (InputObject) -> () = config.onBegan or noopInput
	local onEnded: (InputObject) -> () = config.onEnded or noopInput
	local onLeave: () -> () = config.onLeave or function() end

	return React.createElement("TextButton", {
		Name = config.name,
		LayoutOrder = config.layoutOrder,
		AnchorPoint = Vector2.new(1, 1),
		Position = config.position,
		Size = UDim2.fromOffset(config.size, config.size),
		BackgroundColor3 = config.color,
		BackgroundTransparency = if interactive then 0.12 else 0.55,
		BorderSizePixel = 0,
		-- Dimmed AND non-interactive when the action is illegal. The tap still does
		-- not fall through to the HUD behind: the Backdrop underneath is Active.
		Active = interactive,
		AutoButtonColor = false, -- we drive our own pressed state; see `held`
		Text = config.glyph,
		Font = Enum.Font.GothamBold,
		TextSize = math.floor(config.size * 0.42),
		TextColor3 = UIConfig.Color.Primary,
		TextTransparency = if interactive then 0 else 0.45,
		ZIndex = 202,
		[React.Event.InputBegan] = function(_rbx: TextButton, input: InputObject)
			onBegan(input)
		end,
		-- RELEASE PATH 1/5.
		[React.Event.InputEnded] = function(_rbx: TextButton, input: InputObject)
			onEnded(input)
		end,
		-- RELEASE PATH 1b: the finger slid off the button while still down. Roblox
		-- fires MouseLeave for a dragging touch, and this is the common one — thumbs
		-- wander during a fight.
		[React.Event.MouseLeave] = function()
			onLeave()
		end,
	}, children)
end

function HeroTouchControls:render()
	local state = self.state :: State

	-- Desktop with no touchscreen renders nothing at all — no frame, no listener,
	-- no input absorber anywhere near the mouse. On a hybrid device (Surface, iPad
	-- + keyboard) these DO render, and every keyboard/mouse binding stays live
	-- because they are owned by HeroCombatController and this component never
	-- touches them.
	if not UserInputService.TouchEnabled then
		return nil
	end
	if not state.inHero then
		return nil
	end

	local blocking = state.blocking
	local attackHeld = state.attackHeld
	local charging = attackHeld and state.charge > 0.12
	local committed = state.charge >= 1

	local children: { [string]: any } = {
		-- Sinks every touch inside the cluster footprint, including the gaps between
		-- the buttons. Two bugs at once: a thumb landing in a gap no longer spins the
		-- camera (HeroCamera drops gameProcessed touches), and it no longer reaches
		-- the RTS building menu that can sit underneath on a narrow viewport, which
		-- would start a building placement in the middle of a swordfight.
		Backdrop = React.createElement("Frame", {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = 200,
		}),

		Attack = self:_button({
			name = "AttackButton",
			layoutOrder = 1,
			size = ATTACK_SIZE,
			position = UDim2.new(1, 0, 1, 0),
			color = if committed then COLOR_CHARGE else COLOR_ATTACK,
			glyph = "?",
			label = if committed then "HEAVY" else "ATTACK",
			-- Stays interactive while held so a cooldown starting mid-hold cannot
			-- swallow the InputEnded that resolves the tap.
			ready = state.attackReady,
			held = attackHeld,
			onBegan = function(input: InputObject)
				self:_beginHeld("Attack", input)
			end,
			onEnded = function(input: InputObject)
				if isPointerInput(input) then
					self:_releaseHeld("Attack")
				end
			end,
			onLeave = function()
				self:_releaseHeld("Attack")
			end,
			children = {
				-- Charge feedback: a ring that fills toward the heavy threshold. It is
				-- the same amber the desktop crosshair widens in, so the two readouts
				-- say the same thing.
				ChargeRing = if charging
					then React.createElement("Frame", {
						Name = "ChargeRing",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 1),
						Size = UDim2.new(1, 0, state.charge, 0),
						BackgroundColor3 = COLOR_CHARGE,
						BackgroundTransparency = 0.55,
						BorderSizePixel = 0,
						ZIndex = 201,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.4, 0) }),
					})
					else nil,
			},
		}),

		Block = self:_button({
			name = "BlockButton",
			layoutOrder = 2,
			size = SECONDARY_SIZE,
			position = UDim2.new(1, -(ATTACK_SIZE + GAP), 1, 0),
			color = if blocking then COLOR_BLOCK_ACTIVE else COLOR_BLOCK,
			glyph = "??",
			label = "BLOCK",
			-- Block has no cooldown of its own; it is legal whenever fighting is.
			ready = state.canFight,
			held = blocking,
			onBegan = function(input: InputObject)
				self:_beginHeld("Block", input)
			end,
			onEnded = function(input: InputObject)
				if isPointerInput(input) then
					self:_releaseHeld("Block")
				end
			end,
			onLeave = function()
				self:_releaseHeld("Block")
			end,
		}),

		Dodge = self:_button({
			name = "DodgeButton",
			layoutOrder = 3,
			size = SECONDARY_SIZE,
			position = UDim2.new(1, 0, 1, -(ATTACK_SIZE + GAP)),
			color = COLOR_DODGE,
			glyph = "»",
			label = "DODGE",
			ready = state.dodgeReady,
			held = false,
			-- Fires on press, not on release: a dodge that waits for your thumb to
			-- lift arrives after the blow it was meant to avoid. There is no
			-- drag-off-to-cancel for the same reason.
			onBegan = function(input: InputObject)
				if isPointerInput(input) then
					ViewMode.requestHeroAction(ViewMode.HeroActions.Dodge, ViewMode.ActionPhases.Begin)
				end
			end,
		}),

		Ranged = self:_button({
			name = "RangedButton",
			layoutOrder = 4,
			size = SECONDARY_SIZE,
			position = UDim2.new(1, -(ATTACK_SIZE + GAP - 4), 1, -(ATTACK_SIZE + GAP - 4)),
			color = COLOR_RANGED,
			glyph = "??",
			label = "BOW",
			ready = state.rangedReady,
			held = false,
			onBegan = function(input: InputObject)
				if isPointerInput(input) then
					ViewMode.requestHeroAction(ViewMode.HeroActions.Ranged, ViewMode.ActionPhases.Begin)
				end
			end,
		}),
	}

	-- Bottom-right, anchored to the corner so it stays under the thumb on every
	-- aspect ratio. In `compact` (viewport too narrow for the RTS bottom bar's
	-- content area to clear the right edge) the whole cluster lifts above the bar.
	local bottomOffset = if state.compact then UIConfig.HUD.BottomBarHeight + GAP else EDGE_MARGIN

	return React.createElement("Frame", {
		Name = "HeroTouchControls",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -EDGE_MARGIN, 1, -bottomOffset),
		Size = UDim2.fromOffset(CLUSTER_SIZE, CLUSTER_SIZE),
		BackgroundTransparency = 1,
		-- Above every RTS HUD element (the highest of those is the view toggle at
		-- 60): mid-fight these buttons must win any overlap, both visually and for
		-- input.
		ZIndex = 200,
		-- Hidden mid-blend for the same reason the view toggle swallows taps then:
		-- the camera is between the two views, aim is meaningless, and
		-- ViewMode.isCombatReady() would reject the swing anyway.
		Visible = not state.transitioning,
	}, children)
end

return HeroTouchControls
