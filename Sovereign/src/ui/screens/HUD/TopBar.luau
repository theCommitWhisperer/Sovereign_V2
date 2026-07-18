local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local TopBar = React.Component:extend("TopBar")

-- Helper function to create a stat display with text positioned under an icon in the image
function TopBar:createStatDisplay(value: any, position: UDim2, textColor: Color3?)
	return React.createElement("TextLabel", {
		Size = UDim2.new(0, 60, 0, 25),
		Position = position,
		BackgroundTransparency = 1,
		Text = tostring(value),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = textColor or Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
	})
end

-- Helper function to get weather icon
function TopBar:getWeatherIcon(weather: string?): string
	if weather == "Clear" then
		return "☀️"
	elseif weather == "Rain" then
		return "🌧️"
	elseif weather == "Storm" then
		return "⛈️"
	elseif weather == "Drought" then
		return "🌵"
	end
	return "☀️" -- Default to Clear
end

function TopBar:render()
	-- Extract props
	local resources = self.props.resources or {}
	local honor = self.props.honor or 0
	local glory = self.props.glory or 0
	local population = self.props.population or 0
	local date = self.props.date or "Year 1 Month 1"
	local weather = self.props.weather
	local peaceTimeRemaining = self.props.peaceTimeRemaining or 0
	local victoryCondition = self.props.victoryCondition or "Score"

	-- Map lobby victory mode to a short display label
	local victoryIcons = {
		Score = "🏆 Score",
		Conquest = "⚔️ Conquest",
		Wonder = "🏛 Wonder",
		Regicide = "👑 Regicide",
	}
	local victoryLabel = victoryIcons[victoryCondition] or ("🏆 " .. victoryCondition)

	return React.createElement("ImageLabel", {
		Name = "TopBar",
		Size = UDim2.new(0.35, 0, 0, 100), -- 35% of screen width, 100px height
		Position = UDim2.fromScale(0.5, 0), -- Centered horizontally
		AnchorPoint = Vector2.new(0.5, 0), -- Anchor at center
		Image = "rbxassetid://71446311211523",
		ScaleType = Enum.ScaleType.Stretch, -- Stretch to fill the frame
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		ImageTransparency = 0,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		-- Container for all stats with automatic horizontal layout
		StatsContainer = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 30), -- Full width, 30px height to accommodate offset labels
			Position = UDim2.new(0, 0, 1, -45), -- 45px from bottom
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 30), -- 30px spacing between labels
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			-- Weather display (at Y=0, same as others)
			WeatherDisplay = weather and React.createElement("TextLabel", {
				Size = UDim2.fromOffset(60, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = self:getWeatherIcon(weather),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 1,
			}) or nil,

			-- Honor (Fame) (at Y=0, same as others)
			HonorDisplay = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(60, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = tostring(honor),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 2,
			}),

			-- Glory (at Y=0, same as others)
			GloryDisplay = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(60, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = tostring(glory),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 3,
			}),

			-- Population (at Y=0, same as others)
			PopulationDisplay = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(60, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = tostring(population),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 4,
			}),

			-- Date (container frame with label positioned lower)
			DateDisplay = React.createElement("Frame", {
				Size = UDim2.fromOffset(80, 30),
				BackgroundTransparency = 1,
				LayoutOrder = 5,
			}, {
				Label = React.createElement("TextLabel", {
					Size = UDim2.fromOffset(80, 25),
					Position = UDim2.fromOffset(0, 8), -- 8px down within the frame
					BackgroundTransparency = 1,
					Text = tostring(date),
					Font = Enum.Font.GothamBold,
					TextSize = 14,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextStrokeTransparency = 0.5,
					TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				}),
			}),

			-- Food (at Y=0, same as most)
			FoodDisplay = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(60, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = tostring(resources.Food or 0),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 6,
			}),

			-- Wood (at Y=0, same as most)
			WoodDisplay = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(60, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = tostring(resources.Wood or 0),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 7,
			}),

			-- Stone (at Y=0, same as most)
			StoneDisplay = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(60, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = tostring(resources.Stone or 0),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 8,
			}),

			-- Iron (at Y=0, same as most)
			IronDisplay = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(60, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = tostring(resources.Iron_Bars or 0),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 9,
			}),

			-- Peace time countdown (only shown when peace time is active)
			PeaceTimeDisplay = peaceTimeRemaining > 0 and React.createElement("TextLabel", {
				Size = UDim2.fromOffset(80, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = string.format("🕊 %d:%02d", math.floor(peaceTimeRemaining / 60), peaceTimeRemaining % 60),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(180, 220, 255), -- Light blue to stand out
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 10,
			}) or nil,

			-- Victory condition indicator (always visible)
			VictoryDisplay = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(100, 25),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = victoryLabel,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(255, 215, 100), -- Gold color
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.5,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				LayoutOrder = 11,
			}),
		}),
	})
end

return TopBar
