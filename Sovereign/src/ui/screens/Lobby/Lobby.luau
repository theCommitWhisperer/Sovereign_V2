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
local MapData = require(ReplicatedStorage.Shared.GameData.MapData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local LobbyDebug = DebugManager.createChannel("Lobby", false)

local Lobby = React.Component:extend("Lobby")

local localPlayer = Players.LocalPlayer
local FACTIONS = { "Kingdom", "Empire", "Tribes", "IronLegion" }
local MEDIEVAL_BUTTON_IMAGE = "rbxassetid://93664952098994"

-- Helper function to generate the initial state from the settings config
local function getInitialState()
	local state = {
		players = {},
		mapKeys = MapData.getMapList(),
		selectedMap = MapData.DefaultMap,
		userMaps = {},          -- { {MapId, Name, UpdatedAt} } — player's editor-saved maps
		userMapsLoaded = false, -- whether we've fetched from server yet
		spawnSelections = {},  -- { [spawnNumber] = { userId, name } }
		mySpawn = nil,
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
	LobbyDebug:info("Lobby:init() - Initializing lobby component")
	self.state = getInitialState()
	LobbyDebug:info("Initial lobby state created", { mapCount = #self.state.mapKeys })

	-- Track if game is starting to prevent double-clicks
	self.isStartingGame = false

	-- Countdown thread reference
	self.countdownThread = nil

	-- Setup lobby event listener
	LobbyDebug:info("Waiting for RemoteEvents")
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local LobbyEvent = RemoteEvents:WaitForChild("LobbyEvent")
	local GameEvent = RemoteEvents:WaitForChild("GameEvent")
	LobbyDebug:info("RemoteEvents found and connected")

	-- Listen for lobby state updates from server
	self.lobbyConnection = LobbyEvent.OnClientEvent:Connect(function(action, data)
		LobbyDebug:info("Received LobbyEvent from server", { action = action })
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
					selectedColor = playerData.SelectedColor,
				})
			end

			-- Update settings from server
			local newState: any = {
				players = playersArray,
				countdownActive = data.CountdownActive,
				countdownTimeRemaining = data.CountdownTimeRemaining,
			}
			LobbyDebug:info("Players updated", { playerCount = #playersArray })

			-- Sync settings from server
			for key, value in pairs(data.Settings) do
				newState[key] = value
			end

			-- Preserve client-only state not broadcast by server
			newState.mapKeys = self.state.mapKeys
			newState.userMaps = self.state.userMaps
			newState.userMapsLoaded = self.state.userMapsLoaded

			-- Sync spawn selections from server
			if data.SpawnSelections then
				newState.spawnSelections = data.SpawnSelections
			end

			-- Find my faction, ready status, and spawn
			local myPlayerData = data.Players[localPlayer.UserId]
			if myPlayerData then
				newState.myFaction = myPlayerData.SelectedFaction
				newState.isReady = myPlayerData.IsReady
			end

			-- Find my spawn
			if data.SpawnSelections then
				for spawnNum, selection in pairs(data.SpawnSelections) do
					if selection.userId == localPlayer.UserId then
						newState.mySpawn = spawnNum
						break
					end
				end
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
		elseif action == "UserMapsList" then
			-- Server returned the player's editor-saved maps
			self:setState({ userMaps = data or {}, userMapsLoaded = true })
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
	LobbyDebug:info("Sending JoinLobby request to server")
	LobbyEvent:FireServer("JoinLobby")

	-- Fetch this player's editor-saved maps for the "My Maps" section
	LobbyEvent:FireServer("ListUserMaps")

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

	self.selectCustomMap = function(mapId)
		LobbyDebug:info("Custom map selected:", mapId)
		LobbyEvent:FireServer("SelectCustomMap", mapId)
	end

	self.onSettingChanged = function(settingId, newValue)
		LobbyDebug:info("Setting changed:", settingId, newValue)
		LobbyEvent:FireServer("VoteSetting", settingId, newValue)
	end

	self.selectSpawn = function(spawnNumber)
		LobbyDebug:info("Spawn selected:", spawnNumber)
		LobbyEvent:FireServer("SelectSpawn", spawnNumber)
	end

	self.selectColor = function(color)
		LobbyDebug:info("Color selected:", color)
		LobbyEvent:FireServer("SelectColor", color)
	end

	self.selectFaction = function(faction, targetUserId)
		-- If targetUserId is not provided, assume it's for the local player
		local userId = targetUserId or localPlayer.UserId
		LobbyDebug:info("Faction selected", { faction = faction, userId = userId })
		LobbyEvent:FireServer("SelectFaction", faction, userId)
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
			Padding = UDim.new(0, 3),
		}),
	}
	local mapKeys = self.state.mapKeys or MapData.getMapList()
	for _, mapKey in ipairs(mapKeys) do
		local mapConfig = MapData.getMap(mapKey)
		local displayName = mapConfig and mapConfig.Name or mapKey
		local isSelected = self.state.selectedMap == mapKey

		mapListChildren[mapKey] = React.createElement("TextButton", {
			key = mapKey,
			Size = UDim2.new(0.95, 0, 0, 32),
			BackgroundColor3 = isSelected and Color3.fromRGB(140, 100, 50) or Color3.fromRGB(90, 65, 35),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Text = displayName,
			FontFace = UIConfig.Font.Title,
			TextColor3 = isSelected and Color3.fromRGB(255, 240, 200) or Color3.fromRGB(220, 200, 170),
			TextSize = 14,
			[React.Event.MouseButton1Click] = function()
				self.selectMap(mapKey)
			end,
		}, {
			UICorner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 3),
			}),
			UIStroke = React.createElement("UIStroke", {
				Color = isSelected and Color3.fromRGB(200, 170, 90) or Color3.fromRGB(60, 45, 25),
				Thickness = isSelected and 2 or 1.5,
			}),
			UIGradient = React.createElement("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
					ColorSequenceKeypoint.new(0.3, Color3.fromRGB(220, 210, 200)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
					ColorSequenceKeypoint.new(0.7, Color3.fromRGB(210, 200, 190)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 235, 225)),
				}),
				Rotation = 0,
			}),
		})
	end

	-- "My Maps" section: player's editor-saved maps
	local userMaps = self.state.userMaps or {}
	if #userMaps > 0 or not self.state.userMapsLoaded then
		-- Divider label
		mapListChildren["__myMapsHeader__"] = React.createElement("TextLabel", {
			Size = UDim2.new(0.95, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = if self.state.userMapsLoaded then "── My Maps ──" else "── My Maps (loading…) ──",
			FontFace = UIConfig.Font.Title,
			TextColor3 = Color3.fromRGB(200, 180, 120),
			TextSize = 12,
		})
	end
	for _, entry in ipairs(userMaps) do
		local mapId: string = entry.MapId or ""
		local displayName: string = entry.Name or mapId
		local isSelected = self.state.selectedMap == "__custom__" and self.state.customMapId == mapId
		mapListChildren["__custom__" .. mapId] = React.createElement("TextButton", {
			Size = UDim2.new(0.95, 0, 0, 32),
			BackgroundColor3 = isSelected and Color3.fromRGB(60, 120, 80) or Color3.fromRGB(40, 80, 55),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Text = "★ " .. displayName,
			FontFace = UIConfig.Font.Title,
			TextColor3 = isSelected and Color3.fromRGB(200, 255, 200) or Color3.fromRGB(170, 220, 170),
			TextSize = 14,
			[React.Event.MouseButton1Click] = function()
				self.selectCustomMap(mapId)
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
			UIStroke = React.createElement("UIStroke", {
				Color = isSelected and Color3.fromRGB(100, 200, 120) or Color3.fromRGB(30, 60, 40),
				Thickness = isSelected and 2 or 1.5,
			}),
		})
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
				ClipsDescendants = true,
			}, {
				UIPadding = React.createElement("UIPadding", {
					PaddingTop = paddingConfig.LeftPanelSections.Top,
					PaddingBottom = paddingConfig.LeftPanelSections.Bottom,
					PaddingLeft = paddingConfig.LeftPanelSections.Left,
					PaddingRight = paddingConfig.LeftPanelSections.Right,
				}),
				UICorner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 6),
				}),
				UIStroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(100, 75, 40),
					Thickness = 3,
				}),

				-- Map preview takes the top portion
				MapPreview = React.createElement(
					MapPreview,
					{
						mapKey = self.state.selectedMap,
						mapConfig = MapData.getMap(self.state.selectedMap),
						spawnSelections = self.state.spawnSelections,
						mySpawn = self.state.mySpawn,
						onSpawnSelected = self.selectSpawn,
						players = self.state.players,
						localPlayerId = localPlayer.UserId,
						Size = UDim2.new(1, 0, 0.45, 0),
					}
				),

				-- Map selector section
				MapSelectorFrame = React.createElement("Frame", {
					Name = "MapSelectorFrame",
					Size = UDim2.new(1, 0, 0.35, 0),
					Position = UDim2.new(0, 0, 0.46, 0),
					BackgroundTransparency = 1,
				}, {
					UIListLayout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 6),
					}),
					Title = React.createElement("TextLabel", {
						LayoutOrder = 1,
						Text = "Select Map",
						Size = UDim2.new(1, 0, 0, 22),
						FontFace = UIConfig.Font.Title,
						TextColor3 = Color3.fromRGB(200, 180, 140),
						TextSize = 18,
						BackgroundTransparency = 1,
					}),
					Divider = React.createElement("Frame", {
						LayoutOrder = 2,
						Size = UDim2.new(0.8, 0, 0, 1),
						BackgroundColor3 = Color3.fromRGB(120, 100, 70),
						BorderSizePixel = 0,
					}),
					MapList = React.createElement(
						"ScrollingFrame",
						{
							LayoutOrder = 3,
							Size = UDim2.new(1, 0, 1, -30),
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							ScrollBarThickness = 4,
							ScrollBarImageColor3 = Color3.fromRGB(120, 100, 70),
							CanvasSize = UDim2.new(0, 0, 0, #mapKeys * 35),
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
						},
						mapListChildren
					),
				}),

				-- Map settings at the bottom
				MapSettingsFrame = React.createElement("Frame", {
					Name = "MapSettingsFrame",
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 0),
					Position = UDim2.new(0, 0, 0.82, 0),
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
							onSelectFaction = self.selectFaction,
							onSelectSpawn = self.selectSpawn,
							onSelectColor = self.selectColor,
							spawnSelections = self.state.spawnSelections,
							localPlayerId = localPlayer.UserId,
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
						-- Countdown Display (if active)
						CountdownLabel = self.state.countdownActive and React.createElement("TextLabel", {
							LayoutOrder = 1,
							Text = "Starting in " .. math.ceil(self.state.countdownTimeRemaining) .. "...",
							Size = UDim2.new(1, 0, 0, 50),
							FontFace = UIConfig.Font.Title,
							TextColor3 = Color3.fromRGB(255, 200, 0),
							TextSize = 24,
							BackgroundTransparency = 1,
						}) or nil,
						-- Ready Button
						ReadyButton = not self.state.countdownActive and React.createElement("TextButton", {
							LayoutOrder = 1,
							Size = UDim2.new(0.4, 0, 0, 50),
							BackgroundColor3 = if self.state.isReady
								then Color3.fromRGB(50, 95, 35)
								else Color3.fromRGB(120, 85, 40),
							BackgroundTransparency = 0,
							BorderSizePixel = 0,
							Text = if self.state.isReady then "Not Ready" else "Ready",
							FontFace = UIConfig.Font.Title,
							TextColor3 = if self.state.isReady
								then Color3.fromRGB(180, 255, 160)
								else Color3.fromRGB(255, 240, 200),
							TextSize = 26,
							[React.Event.MouseButton1Click] = function()
								self.toggleReady()
							end,
						}, {
							UICorner = React.createElement("UICorner", {
								CornerRadius = UDim.new(0, 4),
							}),
							UIStroke = React.createElement("UIStroke", {
								Color = if self.state.isReady
									then Color3.fromRGB(80, 140, 60)
									else Color3.fromRGB(180, 150, 70),
								Thickness = 2.5,
							}),
							UIGradient = React.createElement("UIGradient", {
								Color = ColorSequence.new({
									ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
									ColorSequenceKeypoint.new(0.25, Color3.fromRGB(230, 220, 210)),
									ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
									ColorSequenceKeypoint.new(0.75, Color3.fromRGB(220, 210, 200)),
									ColorSequenceKeypoint.new(1, Color3.fromRGB(245, 240, 230)),
								}),
								Rotation = 0,
							}),
						}) or nil,
						BackButton = React.createElement("TextButton", {
							LayoutOrder = 3,
							Size = UDim2.new(0.25, 0, 0, 36),
							BackgroundColor3 = Color3.fromRGB(85, 60, 30),
							BackgroundTransparency = 0,
							BorderSizePixel = 0,
							Text = if self.state.countdownActive then "Cancel" else "Back",
							FontFace = UIConfig.Font.Default,
							TextColor3 = Color3.fromRGB(220, 200, 170),
							TextSize = 18,
							[React.Event.MouseButton1Click] = function()
								if self.state.countdownActive then
									self.toggleReady()
								else
									if navigate then
										navigate("mainMenu")
									end
								end
							end,
						}, {
							UICorner = React.createElement("UICorner", {
								CornerRadius = UDim.new(0, 3),
							}),
							UIStroke = React.createElement("UIStroke", {
								Color = Color3.fromRGB(55, 40, 20),
								Thickness = 2,
							}),
							UIGradient = React.createElement("UIGradient", {
								Color = ColorSequence.new({
									ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
									ColorSequenceKeypoint.new(0.3, Color3.fromRGB(225, 215, 205)),
									ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
									ColorSequenceKeypoint.new(0.7, Color3.fromRGB(215, 205, 195)),
									ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 235, 225)),
								}),
								Rotation = 0,
							}),
						}),
					}),
				}
			),
		}),
	})
end

return Lobby
