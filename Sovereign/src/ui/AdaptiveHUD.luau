--!strict
-- AdaptiveHUD: the single mount point for the new adaptive HUD, per
-- docs/EconomyRedesign.md section 8. Picks DesktopShell or MobileShell from
-- Platform, starts/stops HUDStore's remote wiring for its own lifetime, and
-- re-picks the shell whenever Platform.onChanged fires (gamepad connected,
-- window resized across the compact breakpoint, tablet rotated) so the layout
-- swaps live instead of only being decided once at mount.
--
-- Both shells receive the exact same panel components (BuildingMenu,
-- SelectionPanel, ResourceDisplay) -- this file does not fork per platform,
-- the shells and Platform.tokens do.
--
-- ---------------------------------------------------------------------------
-- NOT YET WIRED INTO App.luau's ROUTER
-- ---------------------------------------------------------------------------
-- src/ui/screens/HUD/HUD.luau is still the live "hud" route and still owns
-- its own remote connections; this tree currently mounts nowhere in the
-- running game. It exists as the foundation the remaining panel migrations
-- build on (see the hard constraint against rewriting HUD.luau). Swapping
-- App.luau's route table from HUD to AdaptiveHUD is the last step, once every
-- panel HUD.luau still owns directly has a presentational equivalent here.
--
-- Mounting THIS starts HUDStore, which opens a second set of listeners on the
-- same RemoteEvents HUD.luau already listens to -- see HUDStore.luau's header
-- for why that is safe today and must not become permanent.

local React = require(game.ReplicatedStorage.Packages.react)

local Platform = require(script.Parent.Platform)
local HUDStore = require(script.Parent.state.HUDStore)
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

	return React.createElement(Shell, {
		tooltip = props.tooltip,
	})
end

return AdaptiveHUD
