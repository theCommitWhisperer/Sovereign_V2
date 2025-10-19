local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local LobbySettings = require(script.Parent.Parent.Parent.LobbySettings)
local Button = require(script.Parent.Parent.Parent.components.Button)
local Toggle = require(script.Parent.Parent.Parent.components.Toggle)
local PlayerList = require(script.Parent.PlayerList)
local MapPreview = require(script.Parent.MapPreview)
local Row = require(script.Parent.Parent.Parent.components.Row)

local Lobby = React.Component:extend("Lobby")

-- Helper function to generate the initial state from the settings config
local function getInitialState()
	local state = {
		players = { { name = "Player1", isAI = false } },
		maps = { "Default Map", "Forest Lands", "Desert Sands", "Frozen Peaks" },
		selectedMap = "Default Map",
	}

	for groupName, settings in pairs(LobbySettings) do
		for _, setting in ipairs(settings) do
			state[setting.id] = setting.defaultValue
		end
	end

	return state
end

function Lobby:init()
	self.state = getInitialState()

	self.addAI = function()
		if #self.state.players < 4 then
			local newPlayers = table.clone(self.state.players)
			table.insert(newPlayers, { name = "AI_Opponent" .. #newPlayers, isAI = true })
			self:setState({ players = newPlayers })
		end
	end

	self.removePlayer = function(playerToRemove)
		local newPlayers = {}
		for _, player in ipairs(self.state.players) do
			if player ~= playerToRemove then
				table.insert(newPlayers, player)
			end
		end
		self:setState({ players = newPlayers })
	end

	self.selectMap = function(mapName)
		self:setState({ selectedMap = mapName })
	end

	self.onSettingChanged = function(settingId, newValue)
		self:setState({ [settingId] = newValue })
	end
end

-- Helper function to render a list of settings from the config
function Lobby:renderSettingsGroup(settings)
	local elements = {}
	for i, settingInfo in ipairs(settings) do
		table.insert(
			elements,
			React.createElement(Row, {
				key = settingInfo.id,
				LayoutOrder = i,
				Label = settingInfo.label,
				TextColor3 = UIConfig.LobbyPage.OptionsTextColor,
				TextSize = UIConfig.LobbyPage.OptionsTextSize,
			}, {
				Control = React.createElement(Toggle, {
					value = self.state[settingInfo.id],
					options = settingInfo.type == "cycle" and settingInfo.options or nil,
					onValueChanged = function(newValue)
						self.onSettingChanged(settingInfo.id, newValue)
					end,
				}),
			})
		)
	end
	return elements
end

function Lobby:render()
	local navigate = self.props.navigate
	local lobbyConfig = UIConfig.LobbyPage
	local paddingConfig = lobbyConfig.Padding

	local mapListChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 5),
		}),
	}
	for _, mapName in ipairs(self.state.maps) do
		table.insert(
			mapListChildren,
			React.createElement("TextButton", {
				key = mapName,
				Text = mapName,
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = self.state.selectedMap == mapName and lobbyConfig.MapSelectorBackgroundColor
					or Color3.fromRGB(50, 50, 50),
				TextColor3 = lobbyConfig.MapSelectorTextColor,
				[React.Event.MouseButton1Click] = function()
					self.selectMap(mapName)
				end,
			})
		)
	end

	local mapSettingsChildren = self:renderSettingsGroup(LobbySettings.MapSettings)
	table.insert(
		mapSettingsChildren,
		1,
		React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		})
	)
	table.insert(
		mapSettingsChildren,
		2,
		React.createElement("TextLabel", {
			LayoutOrder = 0,
			Text = "Map Settings",
			Size = UDim2.new(1, 0, 0, 30),
			FontFace = UIConfig.Font.Title,
			TextColor3 = lobbyConfig.GameRulesTitleColor,
			TextSize = lobbyConfig.GameRulesTitleSize,
			BackgroundTransparency = 1,
		})
	)

	local startingResourcesChildren = self:renderSettingsGroup(LobbySettings.StartingResources)
	table.insert(
		startingResourcesChildren,
		1,
		React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = paddingConfig.SettingsRows.Bottom,
		})
	)
	table.insert(
		startingResourcesChildren,
		2,
		React.createElement("TextLabel", {
			LayoutOrder = 0,
			Text = "Starting Resources",
			Size = UDim2.new(1, 0, 0, 25),
			FontFace = UIConfig.Font.Title,
			TextColor3 = lobbyConfig.StartingResourcesTitleColor,
			TextSize = lobbyConfig.StartingResourcesTitleSize,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	)

	local gameplayModifierChildren = self:renderSettingsGroup(LobbySettings.GameplayModifiers)
	local pacingAndEconomyChildren = self:renderSettingsGroup(LobbySettings.PacingAndEconomy)

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
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0.02, 0),
			}),

			LeftPanel = React.createElement("Frame", {
				Name = "LeftPanel",
				Size = UDim2.new(0.3, 0, 1, 0),
				BackgroundColor3 = lobbyConfig.PanelBackgroundColor,
				BackgroundTransparency = lobbyConfig.PanelBackgroundTransparency,
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
					Padding = UDim.new(0, 20),
				}),
				MapPreview = React.createElement(
					MapPreview,
					{ LayoutOrder = 1, mapName = self.state.selectedMap, Size = UDim2.new(1, 0, 0.4, 0) }
				),
				MapSelectorFrame = React.createElement("Frame", {
					LayoutOrder = 2,
					Name = "MapSelectorFrame",
					Size = UDim2.new(1, 0, 0.3, 0),
					BackgroundTransparency = 1,
				}, {
					UIListLayout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 10),
					}),
					Title = React.createElement("TextLabel", {
						LayoutOrder = 1,
						Text = "Map Selector",
						Size = UDim2.new(1, 0, 0, 30),
						FontFace = UIConfig.Font.Title,
						TextColor3 = lobbyConfig.MapPreviewTitleColor,
						TextSize = lobbyConfig.MapPreviewTitleSize,
						BackgroundTransparency = 1,
					}),
					MapList = React.createElement(
						"Frame",
						{ LayoutOrder = 2, Size = UDim2.new(1, 0, 1, -30), BackgroundTransparency = 1 },
						mapListChildren
					),
				}),
				MapSettingsFrame = React.createElement("Frame", {
					LayoutOrder = 3,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 0),
					BackgroundTransparency = 1,
				}, mapSettingsChildren),
			}),

			RightPanel = React.createElement(
				"Frame",
				{ Name = "RightPanel", Size = UDim2.new(0.68, 0, 1, 0), BackgroundTransparency = 1 },
				{
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
					}),
					ContentFrame = React.createElement("Frame", {
						LayoutOrder = 1,
						Name = "ContentFrame",
						Size = UDim2.new(1, 0, 1, -100),
						BackgroundTransparency = 1,
					}, {
						UIListLayout = React.createElement("UIListLayout", {
							FillDirection = Enum.FillDirection.Vertical,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0.02, 0),
						}),
						PlayerList = React.createElement(PlayerList, {
							LayoutOrder = 1,
							players = self.state.players,
							onAddAI = self.addAI,
							onRemovePlayer = self.removePlayer,
							Size = UDim2.new(1, 0, 0, 250),
							Button = Button,
						}),
						GameSettingsFrame = React.createElement("Frame", {
							LayoutOrder = 2,
							Name = "GameSettingsFrame",
							AutomaticSize = Enum.AutomaticSize.Y,
							Size = UDim2.new(1, 0, 0, 0),
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
								AutomaticSize = Enum.AutomaticSize.Y,
								Size = UDim2.new(0.95, 0, 0, 0),
								BackgroundTransparency = 1,
							}, {
								UIListLayout = React.createElement("UIListLayout", {
									FillDirection = Enum.FillDirection.Horizontal,
									VerticalAlignment = Enum.VerticalAlignment.Top,
									SortOrder = Enum.SortOrder.LayoutOrder,
									Padding = UDim.new(0.02, 0),
								}),
								LeftColumn = React.createElement("Frame", {
									LayoutOrder = 1,
									AutomaticSize = Enum.AutomaticSize.Y,
									Size = UDim2.new(0.49, 0, 0, 0),
									BackgroundTransparency = 1,
								}, {
									UIPadding = React.createElement("UIPadding", {
										PaddingTop = paddingConfig.SettingsColumns.Top,
										PaddingBottom = paddingConfig.SettingsColumns.Bottom,
										PaddingLeft = paddingConfig.SettingsColumns.Left,
										PaddingRight = paddingConfig.SettingsColumns.Right,
									}),
								}, startingResourcesChildren),
								RightColumn = React.createElement("Frame", {
									LayoutOrder = 2,
									AutomaticSize = Enum.AutomaticSize.Y,
									Size = UDim2.new(0.49, 0, 0, 0),
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
										HorizontalAlignment = Enum.HorizontalAlignment.Center,
										SortOrder = Enum.SortOrder.LayoutOrder,
										Padding = UDim.new(0, 20),
									}),
									GameplayModifiersFrame = React.createElement("Frame", {
										LayoutOrder = 1,
										AutomaticSize = Enum.AutomaticSize.Y,
										Size = UDim2.new(1, 0, 0, 0),
										BackgroundTransparency = 1,
									}, {
										UIListLayout = React.createElement("UIListLayout", {
											FillDirection = Enum.FillDirection.Vertical,
											SortOrder = Enum.SortOrder.LayoutOrder,
											Padding = paddingConfig.SettingsRows.Bottom,
										}),
										Title = React.createElement("TextLabel", {
											LayoutOrder = 0,
											Text = "Gameplay Modifiers",
											Size = UDim2.new(1, 0, 0, 25),
											FontFace = UIConfig.Font.Title,
											TextColor3 = lobbyConfig.GameRulesTitleColor,
											TextSize = lobbyConfig.GameRulesTitleSize,
											BackgroundTransparency = 1,
											TextXAlignment = Enum.TextXAlignment.Left,
										}),
									}, gameplayModifierChildren),
									PacingAndEconomyFrame = React.createElement("Frame", {
										LayoutOrder = 2,
										AutomaticSize = Enum.AutomaticSize.Y,
										Size = UDim2.new(1, 0, 0, 0),
										BackgroundTransparency = 1,
									}, {
										UIListLayout = React.createElement("UIListLayout", {
											FillDirection = Enum.FillDirection.Vertical,
											SortOrder = Enum.SortOrder.LayoutOrder,
											Padding = paddingConfig.SettingsRows.Bottom,
										}),
										Title = React.createElement("TextLabel", {
											LayoutOrder = 0,
											Text = "Pacing & Economy",
											Size = UDim2.new(1, 0, 0, 25),
											FontFace = UIConfig.Font.Title,
											TextColor3 = lobbyConfig.GameRulesTitleColor,
											TextSize = lobbyConfig.GameRulesTitleSize,
											BackgroundTransparency = 1,
											TextXAlignment = Enum.TextXAlignment.Left,
										}),
									}, pacingAndEconomyChildren),
								}),
							}),
						}),
					}),
					ButtonsFrame = React.createElement("Frame", {
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 0, 100),
						BackgroundTransparency = 1,
						Position = UDim2.new(0, 0, 1, -100),
						AnchorPoint = Vector2.new(0, 1),
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
							Padding = UDim.new(0, 10),
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
									if type(value) ~= "table" and type(value) ~= "function" then
										print(string.format("  %s: %s", setting, tostring(value)))
									end
								end
								-- Navigate to HUD (which triggers game start in App.luau)
								if navigate then
									navigate("hud")
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
				}
			),
		}),
	})
end

return Lobby
