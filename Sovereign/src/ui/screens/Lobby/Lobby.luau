-- The game lobby screen where players prepare for a match.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)
local Slider = require(script.Parent.Parent.Parent.components.Slider)
local Toggle = require(script.Parent.Parent.Parent.components.Toggle)
local MapPreview = require(script.Parent.MapPreview)
local PlayerList = require(script.Parent.PlayerList)

local Lobby = React.Component:extend("Lobby")

function Lobby:init()
	self:setState({
		startingGold = 500,
		honor = "Standard",
		rank = "Knight",
		peaceTime = "10 minutes",
		randomEvents = true,
		startingResources = 1000,
		startingFood = 50,
		abilityToTrade = true,
		startingWeapons = "Iron",
		startingTroops = 10,
		selectedMap = "Default Map",
	})
end

function Lobby:render()
	print("Lobby.luau: render() called. UI should be visible.")
	local navigate = self.props.navigate

	return React.createElement("ScreenGui", {
		Name = "LobbyGui",
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Background = React.createElement("ImageLabel", {
			Name = "Background",
			Size = UDim2.fromScale(1, 1),
			Image = "rbxassetid://99876577284469",
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 1,
		}),
		MainFrame = React.createElement("Frame", {
			Name = "MainFrame",
			Size = UDim2.new(0.95, 0, 0.95, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = UIConfig.Color.Background,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0.01, 0),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
			}),

			-- Top Section
			TopSection = React.createElement("Frame", {
				Name = "TopSection",
				Size = UDim2.new(1, 0, 0.4, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0.01, 0),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),

				MapSettingsFrame = React.createElement("Frame", {
					Name = "MapSettingsFrame",
					Size = UDim2.new(0.3, 0, 1, 0),
					BackgroundColor3 = Color3.new(0.15, 0.15, 0.15),
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 5),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					}),
					Title = React.createElement("TextLabel", {
						Text = "Map Settings",
						Size = UDim2.new(1, 0, 0, 30),
						FontFace = UIConfig.Font.Title,
						TextColor3 = UIConfig.Color.Primary,
						TextSize = 24,
						BackgroundTransparency = 1,
					}),
					RandomEvents = React.createElement(Toggle, {
						label = "Random Events",
						value = self.state.randomEvents,
						onValueChanged = function(newValue)
							self:setState({ randomEvents = newValue })
						end,
					}),
				}),

				MapSelectorFrame = React.createElement("Frame", {
					Name = "MapSelectorFrame",
					Size = UDim2.new(0.3, 0, 1, 0),
					BackgroundColor3 = Color3.new(0.15, 0.15, 0.15),
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 5),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					}),
					Title = React.createElement("TextLabel", {
						Text = "Map Selector",
						Size = UDim2.new(1, 0, 0, 30),
						FontFace = UIConfig.Font.Title,
						TextColor3 = UIConfig.Color.Primary,
						TextSize = 24,
						BackgroundTransparency = 1,
					}),
					MapSelectionDropdown = React.createElement("TextButton", {
						Name = "MapSelectionDropdown", -- Added name for clarity
						Text = self.state.selectedMap,
						Size = UDim2.new(0.9, 0, 0, 40),
						BackgroundColor3 = UIConfig.Color.Secondary,
						TextColor3 = UIConfig.Color.Primary, -- Make sure text is visible
						TextSize = 20,
						FontFace = UIConfig.Font.Default, -- Use default font
						BorderSizePixel = 0,
						ZIndex = 3,
						[React.Event.MouseButton1Click] = function() -- CORRECTED: This is the right way to handle clicks
							print("Open map selection for:", self.state.selectedMap)
							local maps = { "Default Map", "Forest Lands", "Desert Sands", "Frozen Peaks" }
							local currentIndex = table.find(maps, self.state.selectedMap) or 1
							local nextIndex = (currentIndex % #maps) + 1
							self:setState({ selectedMap = maps[nextIndex] })
						end,
					}),
				}),

				MapPreview = React.createElement(MapPreview, {
					mapName = self.state.selectedMap,
					Size = UDim2.new(0.35, 0, 1, 0),
				}),
			}),

			-- Bottom Section
			BottomSection = React.createElement("Frame", {
				Name = "BottomSection",
				Size = UDim2.new(1, 0, 0.6, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0.01, 0),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),

				GameSettingsFrame = React.createElement("Frame", {
					Name = "GameSettingsFrame",
					Size = UDim2.new(0.5, 0, 1, 0),
					BackgroundColor3 = Color3.new(0.15, 0.15, 0.15),
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 5),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					}),
					Title = React.createElement("TextLabel", {
						Text = "Game Settings",
						Size = UDim2.new(1, 0, 0, 30),
						FontFace = UIConfig.Font.Title,
						TextColor3 = UIConfig.Color.Primary,
						TextSize = 28,
						BackgroundTransparency = 1,
					}),

					React.createElement("Frame", {
						Size = UDim2.new(0.95, 0, 0.9, 0), -- Use most of the space
						BackgroundTransparency = 1,
					}, {
						Layout = React.createElement("UIGridLayout", {
							CellSize = UDim2.new(0.48, 0, 0.1, 0), -- Adjusted for better fit
							CellPadding = UDim2.new(0.02, 0, 0.02, 0), -- Padding between cells
							FillDirection = Enum.FillDirection.Horizontal,
							StartCorner = Enum.StartCorner.TopLeft,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							VerticalAlignment = Enum.VerticalAlignment.Top,
						}),
						StartingGold = React.createElement(Slider, {
							label = "Starting Gold",
							min = 100,
							max = 2000,
							value = self.state.startingGold,
							onValueChanged = function(newValue)
								self:setState({ startingGold = newValue })
							end,
						}),
						Honor = React.createElement(Toggle, {
							label = "Honor (" .. self.state.honor .. ")",
							value = true,
							onValueChanged = function()
								local options = { "Standard", "High", "Low" }
								local currentIndex = table.find(options, self.state.honor) or 1
								local nextIndex = (currentIndex % #options) + 1
								self:setState({ honor = options[nextIndex] })
							end,
						}),
						Rank = React.createElement(Toggle, {
							label = "Rank (" .. self.state.rank .. ")",
							value = true,
							onValueChanged = function()
								local options = { "Knight", "Baron", "Duke", "King" }
								local currentIndex = table.find(options, self.state.rank) or 1
								local nextIndex = (currentIndex % #options) + 1
								self:setState({ rank = options[nextIndex] })
							end,
						}),
						PeaceTime = React.createElement(Toggle, {
							label = "Peace Time (" .. self.state.peaceTime .. ")",
							value = true,
							onValueChanged = function()
								local options = { "None", "5 minutes", "10 minutes", "20 minutes" }
								local currentIndex = table.find(options, self.state.peaceTime) or 1
								local nextIndex = (currentIndex % #options) + 1
								self:setState({ peaceTime = options[nextIndex] })
							end,
						}),
						StartingResources = React.createElement(Slider, {
							label = "Starting Resources",
							min = 500,
							max = 5000,
							value = self.state.startingResources,
							onValueChanged = function(newValue)
								self:setState({ startingResources = newValue })
							end,
						}),
						StartingFood = React.createElement(Slider, {
							label = "Starting Food",
							min = 25,
							max = 200,
							value = self.state.startingFood,
							onValueChanged = function(newValue)
								self:setState({ startingFood = newValue })
							end,
						}),
						AbilityToTrade = React.createElement(Toggle, {
							label = "Ability to Trade",
							value = self.state.abilityToTrade,
							onValueChanged = function(newValue)
								self:setState({ abilityToTrade = newValue })
							end,
						}),
						StartingWeapons = React.createElement(Toggle, {
							label = "Weapons (" .. self.state.startingWeapons .. ")",
							value = true,
							onValueChanged = function()
								local options = { "None", "Bronze", "Iron", "Steel" }
								local currentIndex = table.find(options, self.state.startingWeapons) or 1
								local nextIndex = (currentIndex % #options) + 1
								self:setState({ startingWeapons = options[nextIndex] })
							end,
						}),
						StartingTroops = React.createElement(Slider, {
							label = "Starting Troops",
							min = 5,
							max = 50,
							value = self.state.startingTroops,
							onValueChanged = function(newValue)
								self:setState({ startingTroops = newValue })
							end,
						}),
					}),
				}),

				RightBottomPanel = React.createElement("Frame", {
					Name = "RightBottomPanel",
					Size = UDim2.new(0.45, 0, 1, 0),
					BackgroundTransparency = 1,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 10),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Top,
					}),
					PlayerList = React.createElement(PlayerList, {
						players = {
							{ name = "Player1", isAI = false },
							{ name = "AI_Opponent1", isAI = true },
							{ name = "Teammate1", isAI = false },
							{ name = "AI_Opponent2", isAI = true },
						},
						Size = UDim2.new(1, 0, 0.7, 0),
					}),
					ButtonsFrame = React.createElement("Frame", {
						Name = "ButtonsFrame",
						Size = UDim2.new(1, 0, 0.2, 0),
						BackgroundTransparency = 1,
					}, {
						Layout = React.createElement("UIListLayout", {
							FillDirection = Enum.FillDirection.Vertical,
							Padding = UDim.new(0, 5),
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							VerticalAlignment = Enum.VerticalAlignment.Bottom,
						}),
						StartButton = React.createElement(Button, {
							Text = "Start Game",
							OnClick = function()
								print("Starting game with the following settings:")
								for setting, value in pairs(self.state) do
									print(string.format("  %s: %s", setting, tostring(value)))
								end
							end,
						}),
						BackButton = React.createElement(Button, {
							Text = "Back",
							OnClick = function()
								if navigate then
									navigate("mainMenu")
								end
							end,
						}),
					}),
				}),
			}),
		}),
	})
end

return Lobby
