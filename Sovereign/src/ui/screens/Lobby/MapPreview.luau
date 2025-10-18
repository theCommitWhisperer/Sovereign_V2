-- thecommitwhisperer/sovereign_v2/Sovereign_V2-a5a2c87f4791d0aeedd3f50cf89de31685a4f9fb/Sovereign/src/ui/screens/Lobby/MapPreview.luau
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local MapPreview = React.Component:extend("MapPreview")

function MapPreview:render()
	local mapName = self.props.mapName
	local lobbyConfig = UIConfig.LobbyPage

	return React.createElement("Frame", {
		Name = "MapPreviewContainer",
		Size = self.props.Size or UDim2.new(1, 0, 0.6, 0),
		BackgroundTransparency = 1,
		LayoutOrder = self.props.LayoutOrder,
	}, {
		-- This layout will stack the title and the preview frame vertically
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),

		-- The title is now a separate element in the layout
		Title = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Text = "Map Preview",
			Size = UDim2.new(1, 0, 0, 40),
			FontFace = UIConfig.Font.Title,
			TextColor3 = lobbyConfig.MapPreviewTitleColor,
			TextSize = lobbyConfig.MapPreviewTitleSize,
			BackgroundTransparency = 1,
		}),

		-- This frame contains the preview box and the map name
		PreviewFrame = React.createElement("Frame", {
			LayoutOrder = 2,
			Name = "PreviewFrame",
			Size = UDim2.new(1, 0, 1, -50), -- Fills the remaining space
			BackgroundColor3 = lobbyConfig.PanelBackgroundColor,
			BackgroundTransparency = lobbyConfig.PanelBackgroundTransparency,
			BorderSizePixel = 0,
		}, {
			-- The dark gray box for the map image/preview
			PreviewArea = React.createElement("Frame", {
				Size = UDim2.fromScale(0.9, 0.9),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(0.1, 0.1, 0.1),
				BackgroundTransparency = 0.5,
			}),
			-- The selected map's name, anchored to the bottom of the preview frame
			MapName = React.createElement("TextLabel", {
				Text = mapName,
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.fromScale(0.5, 1),
				AnchorPoint = Vector2.new(0.5, 1),
				FontFace = UIConfig.Font.Default,
				TextColor3 = lobbyConfig.MapNameColor,
				TextSize = lobbyConfig.MapNameSize,
				BackgroundTransparency = 0.5,
				BackgroundColor3 = UIConfig.Color.Background,
			}),
		}),
	})
end

return MapPreview
