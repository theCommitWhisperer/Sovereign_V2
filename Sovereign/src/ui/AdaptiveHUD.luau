--!strict
-- AdaptiveHUD: the single mount point for the adaptive HUD, per
-- docs/EconomyRedesign.md section 8. Picks DesktopShell or MobileShell from
-- Platform, starts/stops HUDStore's remote wiring for its own lifetime, and
-- re-picks the shell whenever Platform.onChanged fires (gamepad connected,
-- window resized across the compact breakpoint, tablet rotated) so the layout
-- swaps live instead of only being decided once at mount.
--
-- Both shells receive the exact same panel components (BuildingMenu,
-- SelectionPanel, ResourceDisplay, etc.) -- this file does not fork per
-- platform, the shells and Platform.tokens do.
--
-- ---------------------------------------------------------------------------
-- THIS IS NOW THE LIVE "hud" ROUTE
-- ---------------------------------------------------------------------------
-- App.luau mounts this instead of the old src/ui/screens/HUD/HUD.luau class
-- component, which has been deleted. Mounting this starts HUDStore, which is
-- now the ONLY thing wiring the HUD's RemoteEvents (HUD.luau's own listeners
-- went away with it) -- see HUDStore.luau's header.
--
-- HUDInput (the building-selection raycast + Ctrl+U/Escape hotkeys) is
-- started/stopped here rather than by either shell, since it is input
-- wiring, not layout: gated on Platform.pointer == "Mouse" so a touch device
-- never opens the keyboard/mouse InputBegan connection it has no use for, and
-- re-evaluated on Platform.onChanged for a hybrid device that gains/loses a
-- mouse mid-session (e.g. a Bluetooth mouse connected to a tablet).

local React = require(game.ReplicatedStorage.Packages.react)

local Platform = require(script.Parent.Platform)
local HUDStore = require(script.Parent.state.HUDStore)
local HUDInput = require(script.Parent.input.HUDInput)
local DesktopShell = require(script.Parent.layouts.DesktopShell)
local MobileShell = require(script.Parent.layouts.MobileShell)

export type Props = {
	tooltip: any?,
	gameStartData: any?,
	navigate: ((string) -> ())?,
}

local function pickShell()
	-- A small window on Desktop goes compact too -- Platform.isCompact() is
	-- deliberately independent of Kind (see Platform.luau) -- so MobileShell is
	-- also what a shrunk desktop window gets, not just touch devices.
	if Platform.kind == "Mobile" or Platform.isCompact() then
		return MobileShell
	end
	return DesktopShell
end

local function AdaptiveHUD(props: Props)
	local Shell, setShell = React.useState(pickShell)

	React.useEffect(function()
		HUDStore.init()
		-- HUDStore.setGameStartData exists specifically so shells can derive
		-- Battle Arena mode from `gameStartData.mode` (see its doc comment), but
		-- nothing was calling it: App.luau receives "GameStarted" once at the
		-- same moment it switches the route to "hud", so this component's first
		-- render already has the real payload in props -- same timing HUD.luau
		-- relied on when it read self.props.gameStartData directly in :init().
		HUDStore.setGameStartData(props.gameStartData)
		return function()
			HUDStore.destroy()
		end
	end, {})

	React.useEffect(function()
		-- Platform may have changed between the initial useState() call above
		-- and this effect committing (gamepad plugged in during load, etc.).
		setShell(pickShell())
		return Platform.onChanged(function()
			setShell(pickShell())
		end)
	end, {})

	React.useEffect(function()
		local function syncInput()
			if Platform.pointer == "Mouse" then
				HUDInput.start()
			else
				HUDInput.stop()
			end
		end
		syncInput()
		local unsubscribe = Platform.onChanged(syncInput)
		return function()
			unsubscribe()
			HUDInput.stop()
		end
	end, {})

	return React.createElement(Shell, {
		tooltip = props.tooltip,
		navigate = props.navigate,
	})
end

return AdaptiveHUD
