--!strict
-- LobbySettingsPanel: every LobbySettings group as chip pickers instead of the
-- old Toggle's </> arrows -- every option is visible and clickable directly,
-- so "what does this setting even offer" doesn't require cycling through it
-- blind. Same "show the option's real effect" spirit as DesktopBuildingGrid's
-- cost chips and ArmyPanel's tradeoff text.
--
-- VOTE TALLY GAP: LobbyManager.voteSetting keeps lobby.SettingsVotes (userId
-- -> value per setting) server-side, but broadcastLobbyState() never sends it
-- to clients -- only the WINNING value replicates (see LobbyManager.luau
-- around line 655). So this panel can honestly show "what won" (every option,
-- winner highlighted) and "what YOU voted" (tracked client-side in Lobby.luau
-- from the player's own VoteSetting calls), but NOT a real per-option vote
-- count from other players -- that data does not leave the server today.
-- The "outvoted" caption below is the honest substitute for a real tally.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)

export type SettingDef = {
	id: string,
	label: string,
	type: string,
	options: { any }?,
	defaultValue: any,
}

export type SettingGroup = {
	title: string,
	settings: { SettingDef },
}

export type Props = {
	groups: { SettingGroup },
	values: { [string]: any },
	myVotes: { [string]: any },
	onVote: (string, any) -> (),
	compact: boolean,
	LayoutOrder: number?,
}

local function optionLabel(setting: SettingDef, option: any): string
	if setting.type == "toggle" then
		return if option then "On" else "Off"
	end
	return tostring(option)
end

local function optionChip(
	setting: SettingDef,
	option: any,
	isCurrent: boolean,
	order: number,
	onVote: (string, any) -> (),
	rowHeight: number
)
	return React.createElement("TextButton", {
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, rowHeight),
		BackgroundColor3 = if isCurrent then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if isCurrent then Theme.Transparency.ScreenCardActive else Theme.Transparency.ScreenCard,
		AutoButtonColor = false,
		Text = "",
		[React.Event.Activated] = function()
			onVote(setting.id, option)
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", {
			Color = if isCurrent then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if isCurrent then 0 else Theme.Transparency.Border,
			Thickness = 1,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Label = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = optionLabel(setting, option),
			FontFace = if isCurrent then Theme.FontFace.BodyBold else Theme.FontFace.Body,
			TextSize = Theme.TextSize.ScreenCaption,
			TextColor3 = if isCurrent then Theme.Color.Accent else Theme.Color.TextSecondary,
		}),
	})
end

local function settingRow(
	setting: SettingDef,
	currentValue: any,
	myVote: any,
	onVote: (string, any) -> (),
	rowHeight: number,
	order: number
)
	local options: { any } = if setting.type == "toggle" then { false, true } else (setting.options or {})

	local chipsChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Wraps = true,
		}),
	}
	for i, option in options do
		chipsChildren[optionLabel(setting, option) .. i] = optionChip(setting, option, option == currentValue, i, onVote, rowHeight)
	end

	-- Only shown when your own vote lost -- if it matches the winner there is
	-- nothing to explain (goal: understand why a setting landed where it did).
	local outvoted = myVote ~= nil and myVote ~= currentValue

	-- LABEL AND CHIPS ON ONE LINE.
	--
	-- These used to stack -- a 22px label above its chip row -- which cost about
	-- 60px per setting. Across four groups that made the panel 1322px tall in a
	-- 645px column, so desktop had to scroll a screen with plenty of width to
	-- spare. Side by side, a setting is one row.
	local children: { [string]: any } = {
		Label = React.createElement("TextLabel", {
			Size = UDim2.new(0.42, -Theme.Metrics.GapTight, 1, 0),
			BackgroundTransparency = 1,
			Text = setting.label,
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.ScreenSmall,
			TextColor3 = Theme.Color.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Chips = React.createElement("Frame", {
			Position = UDim2.fromScale(0.42, 0),
			Size = UDim2.new(0.58, 0, 1, 0),
			BackgroundTransparency = 1,
		}, chipsChildren),
	}
	-- Folded into the label instead of a third row: the note is worth one line's
	-- worth of attention, not one line's worth of height on every setting.
	if outvoted then
		children.Label = React.createElement("TextLabel", {
			Size = UDim2.new(0.42, -Theme.Metrics.GapTight, 1, 0),
			BackgroundTransparency = 1,
			Text = `{setting.label}  (yours: {optionLabel(setting, myVote)})`,
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.ScreenSmall,
			TextColor3 = Theme.Color.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end

	return React.createElement("Frame", {
		key = setting.id,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, rowHeight),
		BackgroundTransparency = 1,
	}, children)
end

local function settingsGroup(group: SettingGroup, values: { [string]: any }, myVotes: { [string]: any }, onVote: (string, any) -> (), rowHeight: number, order: number)
	local groupChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Title = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = group.title,
			FontFace = Theme.FontFace.Display,
			TextSize = Theme.TextSize.ScreenHeading,
			TextColor3 = Theme.Color.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	}
	local rowOrder = 1
	for _, setting in group.settings do
		rowOrder += 1
		groupChildren[setting.id] = settingRow(setting, values[setting.id], myVotes[setting.id], onVote, rowHeight, rowOrder)
	end

	return React.createElement("Frame", {
		key = group.title,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, groupChildren)
end

local function LobbySettingsPanel(props: Props)
	local rowHeight = if props.compact then Theme.Metrics.TouchTarget else Theme.Metrics.DesktopTarget

	local content: { [string]: any } = {}

	if props.compact then
		-- Phone: one column, scrolled. There is no width to trade.
		content.Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.Gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		for i, group in props.groups do
			content["Group" .. i] = settingsGroup(group, props.values, props.myVotes, props.onVote, rowHeight, i)
		end
	else
		-- Desktop: two columns of groups side by side.
		--
		-- Even with single-line rows this panel was 770px in a 645px column, so it
		-- still forced a scroll. Groups alternate between the two columns rather
		-- than filling the first then the second, which keeps the two sides roughly
		-- level without having to measure anything.
		local columns = { {}, {} }
		for i, group in props.groups do
			local target = columns[(i - 1) % 2 + 1]
			target[#target + 1] = { group = group, order = i }
		end

		for colIndex, entries in columns do
			local colChildren: { [string]: any } = {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, Theme.Metrics.Gap),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			}
			for _, entry in entries do
				colChildren["Group" .. entry.order] =
					settingsGroup(entry.group, props.values, props.myVotes, props.onVote, rowHeight, entry.order)
			end
			content["Column" .. colIndex] = React.createElement("Frame", {
				LayoutOrder = colIndex,
				Size = UDim2.new(0.5, -Theme.Metrics.Gap / 2, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, colChildren)
		end

		content.Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, Theme.Metrics.Gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
	end

	content.Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() })
	content.Stroke = React.createElement("UIStroke", Theme.strokeProps())
	content.Pad = React.createElement("UIPadding", {
		PaddingTop = UDim.new(0, Theme.Metrics.Pad),
		PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
		PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
		PaddingRight = UDim.new(0, Theme.Metrics.Pad),
	})

	return React.createElement("Frame", {
		Name = "LobbySettingsPanel",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		-- A real card, not a transparent container. Section labels sitting directly
		-- on the backdrop image were part of why this screen was unreadable.
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = Theme.Transparency.ScreenPanel,
	}, content)
end

return LobbySettingsPanel
