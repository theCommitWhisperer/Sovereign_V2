--!strict
-- TopStatusStrip: the two-row, display-only top chrome. No [React.Event.*]
-- handler exists anywhere in this file -- that is what satisfies the "nothing
-- tappable near the top edge" rule structurally rather than by position alone.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)

export type Props = {
	resources: { [string]: number },
	population: number,
	populationCap: number,
	happiness: number,
	armySize: number,
	date: string,
	-- Number of things wanting the player's attention. HUDStore has no single
	-- "alerts" field, so MobileShell derives this (see its comment) -- kept as
	-- a plain number here so this component stays a pure display of whatever
	-- it's handed.
	alertCount: number,
}

local ROW_ONE_RESOURCES = { "Wood", "Stone", "Gold", "Food" }

local function TopStatusStrip(props: Props)
	local resourceLabels = {}
	resourceLabels.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.Metrics.GapLoose),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	for i, resource in ROW_ONE_RESOURCES do
		resourceLabels[resource] = React.createElement("TextLabel", {
			LayoutOrder = i,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = `{resource} {props.resources[resource] or 0}`,
			Font = Theme.Font.Number,
			TextSize = Theme.TextSize.Body,
			TextColor3 = Theme.resourceColor(resource),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	return React.createElement("Frame", {
		Name = "TopStatusStrip",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = Theme.Transparency.Panel,
		BorderSizePixel = 0,
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.PadTight),
			PaddingBottom = UDim.new(0, Theme.Metrics.PadTight),
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),

		RowOne = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0.5, 0),
			BackgroundTransparency = 1,
		}, {
			Resources = React.createElement("Frame", {
				Size = UDim2.new(1, -80, 1, 0),
				BackgroundTransparency = 1,
			}, resourceLabels),
			Population = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.fromOffset(76, 20),
				BackgroundTransparency = 1,
				Text = `{props.population}/{props.populationCap}`,
				Font = Theme.Font.BodyBold,
				TextSize = Theme.TextSize.Body,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),

		RowTwo = React.createElement("Frame", {
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0.5, 0),
			BackgroundTransparency = 1,
		}, {
			Left = React.createElement("TextLabel", {
				Size = UDim2.new(1, -80, 1, 0),
				BackgroundTransparency = 1,
				Text = `Happiness {math.floor(props.happiness)}%   ·   Army {props.armySize}   ·   {props.date}`,
				Font = Theme.Font.Body,
				TextSize = Theme.TextSize.Caption,
				TextColor3 = Theme.Color.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Alerts = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.fromOffset(76, 16),
				BackgroundTransparency = 1,
				Text = if props.alertCount > 0 then `⚠ {props.alertCount}` else "",
				Font = Theme.Font.BodyBold,
				TextSize = Theme.TextSize.Caption,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),
	})
end

return TopStatusStrip
