local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)
local Toggle = require(script.Parent.Parent.Parent.components.Toggle)
local PlayerList = require(script.Parent.PlayerList)
local MapPreview = require(script.Parent.MapPreview)
local Row = require(script.Parent.Parent.Parent.components.Row)

local Lobby = React.Component:extend("Lobby")

function Lobby:init()
	self.state = {
		selectedMap = "Default Map",
		randomEvents = true,
		startingGold = "Standard",
		peaceTime = "5 minutes",
		honor = "Standard",
		abilityToTrade = true,
		rank = "Knight",
		startingResources = "Standard",
		startingWeapons = "Bronze",
		startingFood = "Standard",
		startingTroops = "Standard",
		gameSpeed = "Normal",
		victoryCondition = "Conquest",
	}
end

function Lobby:render()
	local navigate = self.props.navigate
	local lobbyConfig = UIConfig.LobbyPage
	local paddingConfig = lobbyConfig.Padding

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
			UIPadding = React.createElement("UIPadding", {
				PaddingTop = paddingConfig.MainPanels.Top,
				PaddingBottom = paddingConfig.MainPanels.Bottom,
				PaddingLeft = paddingConfig.MainPanels.Left,
				PaddingRight = paddingConfig.MainPanels.Right,
			}),
			UIListLayout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0.02, 0), -- Spacing between Left and Right panels
			}),

			-- ## Left Panel ##
			LeftPanel = React.createElement("Frame", {
				Name = "LeftPanel",
				Size = UDim2.new(0.3, 0, 1, 0),
				BackgroundTransparency = lobbyConfig.PanelBackgroundTransparency,
				BackgroundColor3 = lobbyConfig.PanelBackgroundColor,
				BorderSizePixel = 0,
			}, {
				UIPadding = React.createElement("UIPadding", {
					PaddingTop = paddingConfig.LeftPanelSections.Top,
					PaddingBottom = paddingConfig.LeftPanelSections.Bottom,
					PaddingLeft = paddingConfig.LeftPanelSections.Left,
					PaddingRight = paddingConfig.LeftPanelSections.Right,
				}),
				UIListLayout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0.02, 0), -- Spacing between sections in left panel
				}),
				MapPreview = React.createElement(MapPreview, {
					LayoutOrder = 1,
					mapName = self.state.selectedMap,
					Size = UDim2.new(0.9, 0, 0.4, 0),
				}),
				MapSelectorFrame = React.createElement("Frame", {
					LayoutOrder = 2,
					Name = "MapSelectorFrame",
					Size = UDim2.new(0.9, 0, 0.2, 0),
					BackgroundTransparency = 1,
				}, {
					UIListLayout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					}),
					Title = React.createElement("TextLabel", {
						Text = "Map Selector",
						Size = UDim2.new(1, 0, 0, 30),
						FontFace = UIConfig.Font.Title,
						TextColor3 = lobbyConfig.MapPreviewTitleColor,
						TextSize = lobbyConfig.MapPreviewTitleSize,
						BackgroundTransparency = 1,
					}),
					MapSelectionDropdown = React.createElement("TextButton", {
						Text = self.state.selectedMap,
						Size = UDim2.new(1, 0, 0, 40),
						BackgroundColor3 = lobbyConfig.MapSelectorBackgroundColor,
						TextColor3 = lobbyConfig.MapSelectorTextColor,
						[React.Event.MouseButton1Click] = function()
							local maps = { "Default Map", "Forest Lands", "Desert Sands", "Frozen Peaks" }
							local currentIndex = table.find(maps, self.state.selectedMap) or 1
							local nextIndex = (currentIndex % #maps) + 1
							self:setState({ selectedMap = maps[nextIndex] })
						end,
					}),
				}),
				MapSettingsFrame = React.createElement("Frame", {
					LayoutOrder = 3,
					Name = "MapSettingsFrame",
					Size = UDim2.new(0.9, 0, 0.2, 0),
					BackgroundTransparency = 1,
				}, {
					UIListLayout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					}),
					Title = React.createElement("TextLabel", {
						Text = "Map Settings",
						Size = UDim2.new(1, 0, 0, 30),
						FontFace = UIConfig.Font.Title,
						TextColor3 = lobbyConfig.GameRulesTitleColor,
						TextSize = lobbyConfig.GameRulesTitleSize,
						BackgroundTransparency = 1,
					}),
					RandomEvents = React.createElement(Row, {
						Label = "Random Events",
						TextColor3 = lobbyConfig.OptionsTextColor,
						TextSize = lobbyConfig.OptionsTextSize,
					}, {
						Control = React.createElement(Toggle, {
							value = self.state.randomEvents,
							onValueChanged = function(newValue)
								self:setState({ randomEvents = newValue })
							end,
						}),
					}),
				}),
			}),

			-- ## Right Panel ##
			RightPanel = React.createElement("Frame", {
				Name = "RightPanel",
				Size = UDim2.new(0.68, 0, 1, 0),
				BackgroundTransparency = 1,
			}, {
				UIPadding = React.createElement("UIPadding", {
					PaddingTop = paddingConfig.RightPanelSections.Top,
					PaddingBottom = paddingConfig.RightPanelSections.Bottom,
					PaddingLeft = paddingConfig.RightPanelSections.Left,
					PaddingRight = paddingConfig.RightPanelSections.Right,
				}),
				UIListLayout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0.02, 0), -- Spacing between sections in right panel
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
					BackgroundColor3 = lobbyConfig.PanelBackgroundColor,
					BackgroundTransparency = lobbyConfig.PanelBackgroundTransparency,
					BorderSizePixel = 0,
				}, {
					UIPadding = React.createElement("UIPadding", {
						PaddingTop = paddingConfig.GameSettings.Top,
						PaddingBottom = paddingConfig.GameSettings.Bottom,
						PaddingLeft = paddingConfig.GameSettings.Left,
						PaddingRight = paddingConfig.GameSettings.Right,
					}),
					UIListLayout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Title = React.createElement("TextLabel", {
						LayoutOrder = 1,
						Text = "Game Settings",
						Size = UDim2.new(1, 0, 0, 30),
						FontFace = UIConfig.Font.Title,
						TextColor3 = lobbyConfig.GameSettingsTitleColor,
						TextSize = lobbyConfig.GameSettingsTitleSize,
						BackgroundTransparency = 1,
					}),
					SettingsContainer = React.createElement("Frame", {
						LayoutOrder = 2,
						Size = UDim2.new(0.95, 0, 0.8, 0),
						BackgroundTransparency = 1,
					}, {
						UIListLayout = React.createElement("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Top,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0.02, 0), -- Spacing between settings columns
						}),
						LeftColumn = React.createElement("Frame", {
							LayoutOrder = 1,
							Size = UDim2.new(0.49, 0, 1, 0),
							BackgroundTransparency = 1,
						}, {
							UIPadding = React.createElement("UIPadding", {
								PaddingTop = paddingConfig.SettingsColumns.Top,
								PaddingBottom = paddingConfig.SettingsColumns.Bottom,
								PaddingLeft = paddingConfig.SettingsColumns.Left,
								PaddingRight = paddingConfig.SettingsColumns.Right,
							}),
							UIListLayout = React.createElement("UIListLayout", {
								FillDirection = Enum.FillDirection.Vertical,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = paddingConfig.SettingsRows.Bottom,
							}),
							StartingResourcesTitle = React.createElement("TextLabel", {
								LayoutOrder = 1,
								Text = "Starting Resources",
								Size = UDim2.new(1, 0, 0, 25),
								FontFace = UIConfig.Font.Title,
								TextColor3 = lobbyConfig.StartingResourcesTitleColor,
								TextSize = lobbyConfig.StartingResourcesTitleSize,
								BackgroundTransparency = 1,
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
							GoldRow = React.createElement(Row, {
								LayoutOrder = 2,
								Label = "Gold",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.startingGold,
									options = { "Low", "Standard", "High" },
									onValueChanged = function(newValue)
										self:setState({ startingGold = newValue })
									end,
								}),
							}),
							TroopsRow = React.createElement(Row, {
								LayoutOrder = 3,
								Label = "Troops",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.startingTroops,
									options = { "Low", "Standard", "High" },
									onValueChanged = function(newValue)
										self:setState({ startingTroops = newValue })
									end,
								}),
							}),
							ResourcesRow = React.createElement(Row, {
								LayoutOrder = 4,
								Label = "Resources",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.startingResources,
									options = { "Low", "Standard", "High" },
									onValueChanged = function(newValue)
										self:setState({ startingResources = newValue })
									end,
								}),
							}),
							FoodRow = React.createElement(Row, {
								LayoutOrder = 5,
								Label = "Food",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.startingFood,
									options = { "Low", "Standard", "High" },
									onValueChanged = function(newValue)
										self:setState({ startingFood = newValue })
									end,
								}),
							}),
							WeaponsRow = React.createElement(Row, {
								LayoutOrder = 6,
								Label = "Weapons",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
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
							LayoutOrder = 2,
							Size = UDim2.new(0.49, 0, 1, 0),
							BackgroundTransparency = 1,
						}, {
							UIPadding = React.createElement("UIPadding", {
								PaddingTop = paddingConfig.SettingsColumns.Top,
								PaddingBottom = paddingConfig.SettingsColumns.Bottom,
								PaddingLeft = paddingConfig.SettingsColumns.Left,
								PaddingRight = paddingConfig.SettingsColumns.Right,
							}),
							UIListLayout = React.createElement("UIListLayout", {
								FillDirection = Enum.FillDirection.Vertical,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = paddingConfig.SettingsRows.Bottom,
							}),
							GameRulesTitle = React.createElement("TextLabel", {
								LayoutOrder = 1,
								Text = "Game Rules",
								Size = UDim2.new(1, 0, 0, 25),
								FontFace = UIConfig.Font.Title,
								TextColor3 = lobbyConfig.GameRulesTitleColor,
								TextSize = lobbyConfig.GameRulesTitleSize,
								BackgroundTransparency = 1,
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
							PeaceTimeRow = React.createElement(Row, {
								LayoutOrder = 2,
								Label = "Peace Time",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.peaceTime,
									options = { "None", "5 minutes", "10 minutes", "20 minutes" },
									onValueChanged = function(newValue)
										self:setState({ peaceTime = newValue })
									end,
								}),
							}),
							GameSpeedRow = React.createElement(Row, {
								LayoutOrder = 3,
								Label = "Game Speed",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.gameSpeed,
									options = { "Slow", "Normal", "Fast" },
									onValueChanged = function(newValue)
										self:setState({ gameSpeed = newValue })
									end,
								}),
							}),
							VictoryConditionRow = React.createElement(Row, {
								LayoutOrder = 4,
								Label = "Victory Condition",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.victoryCondition,
									options = { "Conquest", "Score", "Wonder" },
									onValueChanged = function(newValue)
										self:setState({ victoryCondition = newValue })
									end,
								}),
							}),
							TradeRow = React.createElement(Row, {
								LayoutOrder = 5,
								Label = "Ability to Trade",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
							}, {
								Control = React.createElement(Toggle, {
									value = self.state.abilityToTrade,
									onValueChanged = function(newValue)
										self:setState({ abilityToTrade = newValue })
									end,
								}),
							}),
							HonorRow = React.createElement(Row, {
								LayoutOrder = 6,
								Label = "Honor",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
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
								LayoutOrder = 7,
								Label = "Rank",
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = lobbyConfig.OptionsTextSize,
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
					UIPadding = React.createElement("UIPadding", {
						PaddingTop = paddingConfig.ButtonsFrame.Top,
						PaddingBottom = paddingConfig.ButtonsFrame.Bottom,
						PaddingLeft = paddingConfig.ButtonsFrame.Left,
						PaddingRight = paddingConfig.ButtonsFrame.Right,
					}),
					UIListLayout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 10), -- Spacing between buttons
					}),
					StartButton = React.createElement("TextButton", {
						LayoutOrder = 1,
						Text = "Start Game",
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.new(0, 0, 0, 50),
						BackgroundTransparency = 1,
						FontFace = UIConfig.Font.Title,
						TextColor3 = lobbyConfig.StartButtonTextColor,
						TextSize = lobbyConfig.StartButtonTextSize,
						[React.Event.MouseButton1Click] = function()
							print("Starting game with the following settings:")
							for setting, value in pairs(self.state) do
								print(string.format("  %s: %s", setting, tostring(value)))
							end
						end,
					}),
					BackButton = React.createElement("TextButton", {
						LayoutOrder = 2,
						Text = "Back",
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.new(0, 0, 0, 40),
						BackgroundTransparency = 1,
						FontFace = UIConfig.Font.Default,
						TextColor3 = lobbyConfig.BackButtonTextColor,
						TextSize = lobbyConfig.BackButtonTextSize,
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
