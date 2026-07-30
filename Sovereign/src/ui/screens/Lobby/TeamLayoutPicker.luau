--!strict
-- TeamLayoutPicker: dropdown for the match's team arrangement (2v2, 1v1v1v1,
-- 3v1, ...).
--
-- WHY A DROPDOWN AND NOT A CARD LIST
-- ----------------------------------
-- This was six always-visible cards, each with a label, a description and an
-- asymmetry warning -- 213px of permanent height to express one choice you make
-- once per match. Collapsed it costs one row; the descriptions are still there,
-- just only while you are actually choosing.
--
-- Presentational only: `layoutIds` (the lobby filters this to
-- TeamLayoutsData.getPlayableOn(maxPlayers), since what is playable depends on
-- the selected map) and `selectedLayout` come in as props, `onSelect` is the
-- only way out. The caller owns the VoteSetting remote call.

local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.Parent.Parent.Theme)
local TeamLayoutsData = require(ReplicatedStorage.Shared.GameData.TeamLayoutsData)

export type Props = {
	layoutIds: { string },
	selectedLayout: string,
	onSelect: (string) -> (),
	compact: boolean,
	LayoutOrder: number?,
}

local function optionRow(
	layout: TeamLayoutsData.Layout,
	isSelected: boolean,
	rowHeight: number,
	order: number,
	onSelect: (string) -> ()
)
	return React.createElement("TextButton", {
		Name = layout.id,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, rowHeight),
		BackgroundColor3 = if isSelected then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if isSelected then 0.75 else Theme.Transparency.ScreenCard,
		AutoButtonColor = true,
		Text = "",
		[React.Event.Activated] = function()
			onSelect(layout.id)
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Pad = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Label = React.createElement("TextLabel", {
			Size = UDim2.new(0.3, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = layout.label,
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.ScreenSmall,
			TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		-- The asymmetry warning rides on the description line rather than taking
		-- a row of its own.
		Detail = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.3, 0),
			Size = UDim2.new(0.7, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = if layout.asymmetric
				then "uneven teams · " .. layout.description
				else layout.description,
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.ScreenCaption,
			TextColor3 = if layout.asymmetric then Theme.Color.Warning else Theme.Color.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	})
end

local function TeamLayoutPicker(props: Props)
	local open, setOpen = React.useState(false)
	local rowHeight = if props.compact then Theme.Metrics.TouchTarget else Theme.Metrics.DesktopTarget
	local selected = TeamLayoutsData.getOrDefault(props.selectedLayout)

	local children: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		Trigger = React.createElement("TextButton", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, rowHeight),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BackgroundTransparency = Theme.Transparency.ScreenCard,
			AutoButtonColor = true,
			Text = "",
			[React.Event.Activated] = function()
				setOpen(function(wasOpen)
					return not wasOpen
				end)
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = React.createElement("UIStroke", {
				Color = if open then Theme.Color.Accent else Theme.Color.Border,
				Transparency = if open then 0 else Theme.Transparency.Border,
				Thickness = 1,
			}),
			Pad = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
				PaddingRight = UDim.new(0, Theme.Metrics.Pad),
			}),
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(0.45, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = "Teams",
				FontFace = Theme.FontFace.Body,
				TextSize = Theme.TextSize.ScreenSmall,
				TextColor3 = Theme.Color.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Value = React.createElement("TextLabel", {
				Position = UDim2.fromScale(0.45, 0),
				Size = UDim2.new(0.55, -14, 1, 0),
				BackgroundTransparency = 1,
				Text = selected.label,
				FontFace = Theme.FontFace.BodyBold,
				TextSize = Theme.TextSize.ScreenSmall,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
			Caret = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.fromOffset(12, 12),
				BackgroundTransparency = 1,
				Text = if open then "▴" else "▾",
				FontFace = Theme.FontFace.Body,
				TextSize = Theme.TextSize.ScreenCaption,
				TextColor3 = Theme.Color.TextSecondary,
			}),
		}),
	}

	if open then
		local listChildren: { [string]: any } = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 2),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}
		for i, id in props.layoutIds do
			local layout = TeamLayoutsData.get(id)
			if layout then
				listChildren[id] = optionRow(layout, id == props.selectedLayout, rowHeight, i, function(chosen)
					props.onSelect(chosen)
					setOpen(false)
				end)
			end
		end

		children.Options = React.createElement("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, listChildren)
	end

	return React.createElement("Frame", {
		Name = "TeamLayoutPicker",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, children)
end

return TeamLayoutPicker
