--!strict
-- TeamLayoutPicker: chip-style picker for the match's team arrangement (2v2,
-- 1v1v1v1, 3v1, ...). Mirrors LobbySettingsPanel's chip pattern, but each
-- option needs more than a label -- its description, and for asymmetric
-- layouts a visible "uneven teams" marker -- so it gets its own small card
-- instead of being squeezed into the generic SettingDef chip used for plain
-- string/toggle settings.
--
-- Presentational only: `layoutIds` (which options to show -- the lobby
-- filters this to TeamLayoutsData.getPlayableOn(maxPlayers) before handing
-- it down, since what's playable depends on the selected map) and
-- `selectedLayout` come in as props, `onSelect` is the only way out. The
-- caller owns the VoteSetting remote call, same as every other lobby chip.

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

local function layoutCard(layout: TeamLayoutsData.Layout, isSelected: boolean, order: number, compact: boolean, onSelect: (string) -> ())
	local children: { [string]: any } = {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", {
			Color = if isSelected then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if isSelected then 0 else Theme.Transparency.Border,
			Thickness = 1,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.PadTight),
			PaddingBottom = UDim.new(0, Theme.Metrics.PadTight),
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Label = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = layout.label,
			FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body,
			TextSize = Theme.TextSize.Body,
			TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Description = React.createElement("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = layout.description,
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.Caption,
			TextColor3 = if isSelected then Theme.Color.TextPrimary else Theme.Color.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
		}),
	}

	-- Asymmetric layouts hand one side a numerical disadvantage on purpose --
	-- this has to be visible on the chip itself, not just in the description
	-- text, so picking one is never an accident.
	if layout.asymmetric then
		children.AsymmetricTag = React.createElement("TextLabel", {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = "⚠ Asymmetric -- uneven teams",
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Color.Warning,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	return React.createElement("TextButton", {
		key = layout.id,
		LayoutOrder = order,
		Size = UDim2.new(0, if compact then 158 else 196, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = if isSelected then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if isSelected then Theme.Transparency.CardActive else Theme.Transparency.Card,
		AutoButtonColor = false,
		Text = "",
		[React.Event.Activated] = function()
			onSelect(layout.id)
		end,
	}, children)
end

local function TeamLayoutPicker(props: Props)
	local chips: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Wraps = true,
		}),
	}
	for i, layoutId in props.layoutIds do
		local layout = TeamLayoutsData.get(layoutId)
		if layout then
			chips[layoutId] = layoutCard(layout, layoutId == props.selectedLayout, i, props.compact, props.onSelect)
		end
	end

	return React.createElement("Frame", {
		Name = "TeamLayoutPicker",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Title = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = "Team Layout",
			FontFace = Theme.FontFace.Display,
			TextSize = Theme.TextSize.Heading,
			TextColor3 = Theme.Color.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Chips = React.createElement("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, chips),
	})
end

return TeamLayoutPicker
