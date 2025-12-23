local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local LobbySettings = require(script.Parent.Parent.Parent.LobbySettings)
local Button = require(script.Parent.Parent.Parent.components.Button)
local Toggle = require(script.Parent.Parent.Parent.components.Toggle)
local PlayerList = require(script.Parent.PlayerList)
local MapPreview = require(script.Parent.MapPreview)
local Row = require(script.Parent.Parent.Parent.components.Row)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local LobbyDebug = DebugManager.createChannel("Lobby", true)

local Lobby = React.Component:extend("Lobby")

local localPlayer = Players.LocalPlayer
local FACTIONS = { "Kingdom", "Empire", "Tribes", "IronLegion" }

-- Helper function to generate the initial state from the settings config
local function getInitialState()
	local state = {
		players = {},
		maps = { "Default Map", "Forest Lands", "Desert Sands", "Frozen Peaks" },
		selectedMap = "Default Map",
		myFaction = nil,
		isReady = false,
		countdownActive = false,
		countdownTimeRemaining = 0,
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

	-- Track if game is starting to prevent double-clicks
	self.isStartingGame = false

	-- Countdown thread reference
	self.countdownThread = nil

	-- Setup lobby event listener
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local LobbyEvent = RemoteEvents:WaitForChild("LobbyEvent")
	local GameEvent = RemoteEvents:WaitForChild("GameEvent")

	-- Listen for lobby state updates from server
	self.lobbyConnection = LobbyEvent.OnClientEvent:Connect(function(action, data)
		if action == "LobbyStateUpdate" then
			-- Convert server players to UI format
			local playersArray = {}
			for userId, playerData in pairs(data.Players) do
				table.insert(playersArray, {
					userId = playerData.UserId,
					name = playerData.Name,
					isAI = playerData.IsAI,
					isReady = playerData.IsReady,
					faction = playerData.SelectedFaction,
				})
			end

			-- Update settings from server
			local newState: any = {
				players = playersArray,
				countdownActive = data.CountdownActive,
				countdownTimeRemaining = data.CountdownTimeRemaining,
			}

			-- Sync settings from server
			for key, value in pairs(data.Settings) do
				newState[key] = value
			end

			-- Find my faction and ready status
			local myPlayerData = data.Players[localPlayer.UserId]
			if myPlayerData then
				newState.myFaction = myPlayerData.SelectedFaction
				newState.isReady = myPlayerData.IsReady
			end

			self:setState(newState)
			LobbyDebug:info("Lobby state updated from server")
		elseif action == "CountdownStarted" then
			self:setState({ countdownActive = true, countdownTimeRemaining = data })
			LobbyDebug:info("Countdown started:", data, "seconds")

			-- Start client-side countdown
			if self.countdownThread then
				task.cancel(self.countdownThread)
			end

			self.countdownThread = task.spawn(function()
				local timeLeft = data
				while timeLeft > 0 do
					task.wait(1)
					timeLeft = timeLeft - 1
					if self.state.countdownActive then
						self:setState({ countdownTimeRemaining = timeLeft })
					else
						break
					end
				end
			end)
		elseif action == "CountdownCancelled" then
			self:setState({ countdownActive = false, countdownTimeRemaining = 0 })
			LobbyDebug:info("Countdown cancelled")

			-- Cancel countdown thread
			if self.countdownThread then
				task.cancel(self.countdownThread)
				self.countdownThread = nil
			end
		elseif action == "FactionTaken" then
			-- Show error that faction is taken
			warn("Faction already taken:", data)
		elseif action == "LobbyGameStart" then
			-- Game is starting from multiplayer lobby!
			LobbyDebug:info("Game starting with settings:", data)

			-- Fire StartGame to GameManager with the settings from lobby
			GameEvent:FireServer("StartGame", data)

			-- Navigate to HUD
			local navigate = self.props.navigate
			if navigate then
				navigate("hud")
			end
		end
	end)

	-- Listen for game started confirmation from GameManager
	self.gameConnection = GameEvent.OnClientEvent:Connect(function(action, data)
		if action == "GameStarted" then
			LobbyDebug:info("Game started successfully with faction:", data.faction)
		end
	end)

	-- Join the lobby when component mounts
	LobbyEvent:FireServer("JoinLobby")

	self.addAI = function()
		LobbyDebug:info("Add AI button clicked")
		LobbyEvent:FireServer("AddAI")
	end

	self.removePlayer = function(playerInfo)
		LobbyDebug:info("Remove player:", playerInfo.userId)
		LobbyEvent:FireServer("RemovePlayer", playerInfo.userId)
	end

	self.selectMap = function(mapName)
		LobbyDebug:info("Map selected:", mapName)
		LobbyEvent:FireServer("VoteSetting", "selectedMap", mapName)
	end

	self.onSettingChanged = function(settingId, newValue)
		LobbyDebug:info("Setting changed:", settingId, newValue)
		LobbyEvent:FireServer("VoteSetting", settingId, newValue)
	end

	self.selectFaction = function(faction)
		LobbyDebug:info("Faction selected:", faction)
		LobbyEvent:FireServer("SelectFaction", faction)
	end

	self.toggleReady = function()
		LobbyDebug:info("Toggle ready clicked")
		LobbyEvent:FireServer("ToggleReady")
	end
end

function Lobby:willUnmount()
	-- Clean up connections
	if self.lobbyConnection then
		self.lobbyConnection:Disconnect()
	end
	if self.gameConnection then
		self.gameConnection:Disconnect()
	end

	-- Cancel countdown thread
	if self.countdownThread then
		task.cancel(self.countdownThread)
		self.countdownThread = nil
	end

	-- Leave lobby
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local LobbyEvent = RemoteEvents:FindFirstChild("LobbyEvent")
		if LobbyEvent then
			LobbyEvent:FireServer("LeaveLobby")
		end
	end
end

-- Helper to create faction button
function Lobby:createFactionButton(faction, order)
	local lobbyConfig = UIConfig.LobbyPage
	local isSelected = self.state.myFaction == faction
	local isTaken = false

	-- Check if faction is taken by someone else
	for _, player in ipairs(self.state.players) do
		if player.faction == faction and player.userId ~= localPlayer.UserId then
			isTaken = true
			break
		end
	end

	return React.createElement("TextButton", {
		LayoutOrder = order,
		Text = faction,
		Size = UDim2.new(0.15, 0, 0.7, 0),
		BackgroundColor3 = if isSelected then Color3.fromRGB(100, 200, 100)
			elseif isTaken then Color3.fromRGB(100, 100, 100)
			else Color3.fromRGB(50, 50, 50),
		TextColor3 = if isTaken then Color3.fromRGB(150, 150, 150) else lobbyConfig.MapSelectorTextColor,
		FontFace = UIConfig.Font.Default,
		TextSize = 16,
		BorderSizePixel = 0,
		[React.Event.MouseButton1Click] = function()
			if not isTaken then
				self.selectFaction(faction)
			end
		end,
	})
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
		BackgroundTransparency = 1,
	}, {
		BackgroundImage = React.createElement("ImageLabel", {
			Name = "BackgroundImage",
			Image = "rbxassetid://99876577284469",
			ScaleType = Enum.ScaleType.Stretch,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}),
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
						Size = UDim2.new(1, 0, 0, 180),
						BackgroundTransparency = 1,
						Position = UDim2.new(0, 0, 1, -180),
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
						-- Faction Selector
						FactionFrame = React.createElement("Frame", {
							LayoutOrder = 1,
							Size = UDim2.new(1, 0, 0, 50),
							BackgroundColor3 = lobbyConfig.PanelBackgroundColor,
							BackgroundTransparency = lobbyConfig.PanelBackgroundTransparency,
							BorderSizePixel = 0,
						}, {
							UIListLayout = React.createElement("UIListLayout", {
								FillDirection = Enum.FillDirection.Horizontal,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 10),
							}),
							Label = React.createElement("TextLabel", {
								LayoutOrder = 0,
								Text = "Faction:",
								Size = UDim2.new(0.25, 0, 1, 0),
								FontFace = UIConfig.Font.Default,
								TextColor3 = lobbyConfig.OptionsTextColor,
								TextSize = 18,
								BackgroundTransparency = 1,
							}),
							Kingdom = self:createFactionButton("Kingdom", 1),
							Empire = self:createFactionButton("Empire", 2),
							Tribes = self:createFactionButton("Tribes", 3),
							IronLegion = self:createFactionButton("IronLegion", 4),
						}),
						-- Countdown Display (if active)
						CountdownLabel = self.state.countdownActive and React.createElement("TextLabel", {
							LayoutOrder = 2,
							Text = "Starting in " .. math.ceil(self.state.countdownTimeRemaining) .. "...",
							Size = UDim2.new(1, 0, 0, 40),
							FontFace = UIConfig.Font.Title,
							TextColor3 = Color3.fromRGB(255, 200, 0),
							TextSize = 24,
							BackgroundTransparency = 1,
						}) or nil,
						-- Ready Button
						ReadyButton = React.createElement("TextButton", {
							LayoutOrder = 3,
							Text = if self.state.isReady then "Not Ready" else "Ready",
							AutomaticSize = Enum.AutomaticSize.X,
							Size = UDim2.fromOffset(0, 50),
							BackgroundTransparency = 1,
							FontFace = UIConfig.Font.Title,
							TextColor3 = if self.state.isReady
								then Color3.fromRGB(100, 255, 100)
								else lobbyConfig.StartButtonTextColor,
							TextSize = lobbyConfig.StartButtonTextSize,
							[React.Event.MouseButton1Click] = function()
								self.toggleReady()
							end,
						}),
						BackButton = React.createElement("TextButton", {
							LayoutOrder = 4,
							Text = "Back",
							AutomaticSize = Enum.AutomaticSize.X,
							Size = UDim2.fromOffset(0, 40),
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
