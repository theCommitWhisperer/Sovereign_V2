local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)
local Slider = require(script.Parent.Parent.Parent.components.Slider)
local Toggle = require(script.Parent.Parent.Parent.components.Toggle)
local PlayerList = require(script.Parent.PlayerList)
local MapPreview = require(script.Parent.MapPreview)
local Row = require(script.Parent.Parent.Parent.components.Row)

local Lobby = React.Component:extend("Lobby")

function Lobby:init()
	self.state = {
		selectedMap = "Default Map",
		randomEvents = true,
		startingGold = 1000,
		peaceTime = "5 minutes",
		honor = "Standard",
		abilityToTrade = true,
		rank = "Knight",
		startingResources = 2500,
		startingWeapons = "Bronze",
		startingFood = 100,
		startingTroops = 20,
	}
end

function Lobby:render()
	local navigate = self.props.navigate

	return React.createElement("Frame", {
		Name = "LobbyScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UIConfig.Color.Background,
		BackgroundTransparency = 0.3,
	}, {
		MainFrame = React.createElement("Frame", {
			Name = "MainFrame",
			Size = UDim2.new(0.95, 0, 0.95, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0.02, 0),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),

			-- ## Left Panel ##
			LeftPanel = React.createElement("Frame", {
				Name = "LeftPanel",
				Size = UDim2.new(0.3, 0, 1, 0),
				BackgroundTransparency = 0.5,
				BackgroundColor3 = UIConfig.Color.Background,
				BorderSizePixel = 0,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0.02, 0),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				-- BackButton has been moved from here
				MapPreview = React.createElement(MapPreview, {
					LayoutOrder = 1, -- Changed LayoutOrder
					mapName = self.state.selectedMap,
					Size = UDim2.new(0.9, 0, 0.4, 0),
				}),
				MapSelectorFrame = React.createElement("Frame", {
					LayoutOrder = 2, -- Changed LayoutOrder
					Name = "MapSelectorFrame",
					Size = UDim2.new(0.9, 0, 0.2, 0),
					BackgroundTransparency = 1,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
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
						Text = self.state.selectedMap,
						Size = UDim2.new(1, 0, 0, 40),
						BackgroundColor3 = UIConfig.Color.Secondary,
						TextColor3 = UIConfig.Color.Primary,
						[React.Event.MouseButton1Click] = function()
							local maps = { "Default Map", "Forest Lands", "Desert Sands", "Frozen Peaks" }
							local currentIndex = table.find(maps, self.state.selectedMap) or 1
							local nextIndex = (currentIndex % #maps) + 1
							self:setState({ selectedMap = maps[nextIndex] })
						end,
					}),
				}),
				MapSettingsFrame = React.createElement("Frame", {
					LayoutOrder = 3, -- Changed LayoutOrder
					Name = "MapSettingsFrame",
					Size = UDim2.new(0.9, 0, 0.2, 0),
					BackgroundTransparency = 1,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
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
			}),

			-- ## Right Panel ##
			RightPanel = React.createElement("Frame", {
				Name = "RightPanel",
				Size = UDim2.new(0.68, 0, 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0.02, 0),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				PlayerList = React.createElement(PlayerList, {
					LayoutOrder = 1,
					players = {
						{ name = "Player1", isAI = false },
						{ name = "AI_Opponent1", isAI = true },
					},
					Size = UDim2.new(1, 0, 0.2, 0),
				}),
				GameSettingsFrame = React.createElement("Frame", {
					LayoutOrder = 2,
					Name = "GameSettingsFrame",
					Size = UDim2.new(1, 0, 0.5, 0),
					BackgroundColor3 = UIConfig.Color.Background,
					BackgroundTransparency = 0.5,
					BorderSizePixel = 0,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 5),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Title = React.createElement("TextLabel", {
						LayoutOrder = 1,
						Text = "Game Settings",
						Size = UDim2.new(1, 0, 0, 30),
						FontFace = UIConfig.Font.Title,
						TextColor3 = UIConfig.Color.Primary,
						TextSize = 28,
						BackgroundTransparency = 1,
					}),
					SettingsContainer = React.createElement("Frame", {
						LayoutOrder = 2,
						Size = UDim2.new(0.95, 0, 0.8, 0),
						BackgroundTransparency = 1,
					}, {
						Layout = React.createElement("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0.02, 0),
							SortOrder = Enum.SortOrder.LayoutOrder, -- This is the fix
						}),
						LeftColumn = React.createElement("Frame", {
							LayoutOrder = 1, -- Added LayoutOrder
							Size = UDim2.new(0.49, 0, 1, 0),
							BackgroundTransparency = 1,
						}, {
							Layout = React.createElement("UIListLayout", {
								FillDirection = Enum.FillDirection.Vertical,
								Padding = UDim.new(0, 10),
								SortOrder = Enum.SortOrder.LayoutOrder,
							}),
							StartingGoldRow = React.createElement(Row, {
								LayoutOrder = 1,
								Label = "Starting Gold",
							}, {
								Control = React.createElement(Slider, {
									min = 100,
									max = 2000,
									value = self.state.startingGold,
									onValueChanged = function(newValue)
										self:setState({ startingGold = newValue })
									end,
								}),
							}),
							TroopsRow = React.createElement(Row, {
								LayoutOrder = 4,
								Label = "Starting Troops",
							}, {
								Control = React.createElement(Slider, {
									min = 5,
									max = 50,
									value = self.state.startingTroops,
									onValueChanged = function(newValue)
										self:setState({ startingTroops = newValue })
									end,
								}),
							}),
							ResourcesRow = React.createElement(Row, {
								LayoutOrder = 5,
								Label = "Starting Resources",
							}, {
								Control = React.createElement(Slider, {
									min = 500,
									max = 5000,
									value = self.state.startingResources,
									onValueChanged = function(newValue)
										self:setState({ startingResources = newValue })
									end,
								}),
							}),
							FoodRow = React.createElement(Row, {
								LayoutOrder = 6,
								Label = "Starting Food",
							}, {
								Control = React.createElement(Slider, {
									min = 25,
									max = 200,
									value = self.state.startingFood,
									onValueChanged = function(newValue)
										self:setState({ startingFood = newValue })
									end,
								}),
							}),
							WeaponsRow = React.createElement(Row, {
								LayoutOrder = 7,
								Label = "Starting Weapons",
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.startingWeapons,
									options = { "None", "Bronze", "Iron", "Steel" },
									onValueChanged = function(newValue)
										self:setState({ startingWeapons = newValue })
									end,
								}),
							}),
						}),
						RightColumn = React.createElement("Frame", {
							LayoutOrder = 2, -- Added LayoutOrder
							Size = UDim2.new(0.49, 0, 1, 0),
							BackgroundTransparency = 1,
						}, {
							Layout = React.createElement("UIListLayout", {
								FillDirection = Enum.FillDirection.Vertical,
								Padding = UDim.new(0, 10),
								SortOrder = Enum.SortOrder.LayoutOrder,
							}),
							PeaceTimeRow = React.createElement(Row, {
								LayoutOrder = 1,
								Label = "Peace Time",
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.peaceTime,
									options = { "None", "5 minutes", "10 minutes", "20 minutes" },
									onValueChanged = function(newValue)
										self:setState({ peaceTime = newValue })
									end,
								}),
							}),
							TradeRow = React.createElement(Row, {
								LayoutOrder = 2,
								Label = "Ability to Trade",
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.abilityToTrade,
									onValueChanged = function(newValue)
										self:setState({ abilityToTrade = newValue })
									end,
								}),
							}),
							HonorRow = React.createElement(Row, {
								LayoutOrder = 2,
								Label = "Honor",
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.honor,
									options = { "Standard", "High", "Low" },
									onValueChanged = function(newValue)
										self:setState({ honor = newValue })
									end,
								}),
							}),
							RankRow = React.createElement(Row, {
								LayoutOrder = 3,
								Label = "Rank",
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.rank,
									options = { "Knight", "Baron", "Duke", "King" },
									onValueChanged = function(newValue)
										self:setState({ rank = newValue })
									end,
								}),
							}),
						}),
					}),
				}),
				ButtonsFrame = React.createElement("Frame", {
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0.2, 0),
					BackgroundTransparency = 1,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 10),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					-- Updated Start Button
					StartButton = React.createElement("TextButton", {
						LayoutOrder = 1,
						Text = "Start Game",
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.new(0, 0, 0, 50),
						BackgroundTransparency = 1,
						FontFace = UIConfig.Font.Title, -- Using Title font for emphasis
						TextColor3 = UIConfig.Color.Primary,
						TextSize = 32, -- Made slightly larger
						[React.Event.MouseButton1Click] = function()
							print("Starting game with the following settings:")
							for setting, value in pairs(self.state) do
								print(string.format("  %s: %s", setting, tostring(value)))
							end
						end,
					}),
					-- Updated Back Button
					BackButton = React.createElement("TextButton", {
						LayoutOrder = 2,
						Text = "Back",
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.new(0, 0, 0, 40),
						BackgroundTransparency = 1,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						TextSize = 24,
						[React.Event.MouseButton1Click] = function()
							if navigate then
								navigate("mainMenu")
							end
						end,
					}),
				}),
			}),
		}),
	})
end

return Lobby
