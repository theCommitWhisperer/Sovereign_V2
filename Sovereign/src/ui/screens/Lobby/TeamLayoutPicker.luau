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

-- One layout as a square tile. The label ("2v2") is the thing you scan for, so
-- it dominates; the description is a caption under it and the asymmetry warning
-- replaces that caption rather than adding a line.
local TILE = 96

local function optionTile(
	layout: TeamLayoutsData.Layout,
	isSelected: boolean,
	order: number,
	onSelect: (string) -> ()
)
	return React.createElement("TextButton", {
		Name = layout.id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(TILE, TILE),
		BackgroundColor3 = if isSelected then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if isSelected then 0 else Theme.Transparency.ScreenCard,
		AutoButtonColor = true,
		Text = "",
		[React.Event.Activated] = function()
			onSelect(layout.id)
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", {
			Color = if isSelected then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if isSelected then 0 else Theme.Transparency.Border,
			Thickness = if isSelected then 2 else 1,
		}),
		Pad = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.PadTight),
			PaddingBottom = UDim.new(0, Theme.Metrics.PadTight),
			PaddingLeft = UDim.new(0, Theme.Metrics.PadTight),
			PaddingRight = UDim.new(0, Theme.Metrics.PadTight),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Label = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Text = layout.label,
			FontFace = Theme.FontFace.Display,
			TextSize = Theme.TextSize.ScreenTitle,
			TextColor3 = if isSelected then Theme.Color.OnAccent else Theme.Color.TextPrimary,
		}),
		Detail = React.createElement("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text = if layout.asymmetric then "uneven teams" else layout.description,
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.ScreenCaption,
			TextColor3 = if isSelected then Theme.Color.OnAccent
				elseif layout.asymmetric then Theme.Color.Warning
				else Theme.Color.TextMuted,
			TextWrapped = true,
		}),
	})
end

local function TeamLayoutPicker(props: Props)
	local open, setOpen = React.useState(false)
	local triggerHeight = if props.compact then Theme.Metrics.TouchTarget else Theme.Metrics.DesktopTarget
	local selected = TeamLayoutsData.getOrDefault(props.selectedLayout)

	local children: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		Trigger = React.createElement("TextButton", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, triggerHeight),
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
				Text = `{selected.label}  ·  {selected.category}`,
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
		-- TWO COLUMNS, ONE PER CATEGORY. Free-for-all on the left, allied play on
		-- the right, each a grid of square tiles. A single vertical list made the
		-- two kinds of match look like one arbitrary run of six options.
		local byCategory: { [string]: { TeamLayoutsData.Layout } } = {}
		local categoryOrder: { string } = {}
		for _, id in props.layoutIds do
			local layout = TeamLayoutsData.get(id)
			if layout then
				if not byCategory[layout.category] then
					byCategory[layout.category] = {}
					table.insert(categoryOrder, layout.category)
				end
				table.insert(byCategory[layout.category], layout)
			end
		end

		local columns: { [string]: any } = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, Theme.Metrics.Gap),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		for colIndex, category in categoryOrder do
			local tiles: { [string]: any } = {
				Header = React.createElement("TextLabel", {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 20),
					BackgroundTransparency = 1,
					Text = category,
					FontFace = Theme.FontFace.Display,
					TextSize = Theme.TextSize.ScreenCaption,
					TextColor3 = Theme.Color.AccentMuted,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Grid = React.createElement("Frame", {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
				}, (function()
					local cells: { [string]: any } = {
						Layout = React.createElement("UIGridLayout", {
							CellSize = UDim2.fromOffset(TILE, TILE),
							CellPadding = UDim2.fromOffset(Theme.Metrics.GapTight, Theme.Metrics.GapTight),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					}
					for i, layout in byCategory[category] do
						cells[layout.id] = optionTile(layout, layout.id == props.selectedLayout, i, function(chosen)
							props.onSelect(chosen)
							setOpen(false)
						end)
					end
					return cells
				end)()),
				Stack = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, Theme.Metrics.GapTight),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			}

			columns["Col" .. colIndex] = React.createElement("Frame", {
				LayoutOrder = colIndex,
				Size = UDim2.new(0.5, -Theme.Metrics.Gap / 2, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, tiles)
		end

		children.Options = React.createElement("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, columns)
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
