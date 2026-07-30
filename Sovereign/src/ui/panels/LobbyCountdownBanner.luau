--!strict
-- LobbyCountdownBanner: the "we are about to start" state. Rendered at the top
-- of whatever scroll column it lives in (see Lobby.luau) so it is the first
-- thing you see, not a strip competing with the Ready button for attention.
--
-- "WHO STARTED IT": the brief asks for this, but LobbyManager.startCountdown
-- fires when the LAST ready-up flips every human to ready -- it is a STATE
-- (all players ready), not an action taken by one identifiable player, and
-- the "CountdownStarted" client event only carries the duration (see
-- LobbyManager.luau). There is no player identity to show without a server
-- change (recommend LobbyManager record + broadcast who completed the
-- all-ready set). "All players ready" is the honest substitute rather than
-- inventing a name.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)

export type Props = {
	active: boolean,
	timeRemaining: number,
	compact: boolean,
	onCancel: () -> (),
	LayoutOrder: number?,
}

local function LobbyCountdownBanner(props: Props)
	if not props.active then
		return nil
	end

	local seconds = math.max(0, math.ceil(props.timeRemaining))

	return React.createElement("Frame", {
		Name = "LobbyCountdownBanner",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Color.Accent,
		BackgroundTransparency = Theme.Transparency.ScreenCardActive,
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusCard) }),
		Stroke = React.createElement("UIStroke", {
			Color = Theme.Color.Accent,
			Transparency = 0,
			Thickness = 2,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.Pad),
			PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
			PaddingLeft = UDim.new(0, Theme.Metrics.PadLoose),
			PaddingRight = UDim.new(0, Theme.Metrics.PadLoose),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = if props.compact then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Theme.Metrics.Gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		Text = React.createElement("Frame", {
			LayoutOrder = 1,
			Size = if props.compact then UDim2.new(1, 0, 0, 0) else UDim2.new(1, -170, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Headline = React.createElement("TextLabel", {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = `Starting in {seconds}s`,
				FontFace = Theme.FontFace.Display,
				TextSize = Theme.TextSize.ScreenTitle,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Subtitle = React.createElement("TextLabel", {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = "All players ready — match begins the moment this hits 0.",
				FontFace = Theme.FontFace.Body,
				TextSize = Theme.TextSize.ScreenSmall,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
			}),
		}),

		-- Firing the same ToggleReady the Ready button uses, not a separate
		-- "cancel" remote action -- LobbyManager already cancels the countdown
		-- the moment any human goes un-ready (see toggleReady), so this button
		-- doesn't need matchmaking-architecture changes to work.
		Cancel = React.createElement("TextButton", {
			LayoutOrder = 2,
			Size = if props.compact
				then UDim2.new(1, 0, 0, Theme.Metrics.TouchTarget)
				else UDim2.new(0, 150, 0, Theme.Metrics.TouchTarget),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.ScreenCard,
			AutoButtonColor = false,
			Text = "Cancel",
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.ScreenBody,
			TextColor3 = Theme.Color.Danger,
			[React.Event.Activated] = props.onCancel,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
		}),
	})
end

return LobbyCountdownBanner
