--!strict
-- Lobby: multiplayer staging screen. Presentation + clarity rebuild onto
-- Theme -- the remote wiring (LobbyEvent actions, the class-component
-- lifecycle) is unchanged from before this pass; only what gets drawn and how
-- the layout responds to screen size changed. See LobbyManager.luau (server,
-- read-only from here) for what state actually exists.
--
-- LAYOUT STRATEGY: Header and Footer are fixed-height and pinned to their
-- edges; MainArea fills the fixed remainder between them (Position/Size
-- computed from constants, the same explicit-offset technique the old file
-- used, and the one ArmyPanel's own ScrollingFrame sizing uses -- Roblox's
-- UIListLayout has no "fill remaining space" primitive). The countdown banner
-- is deliberately NOT a separate fixed slot in that math: it lives as the
-- first item inside whichever scrolling column it's part of (compact: the
-- single main scroll; desktop: the roster/settings column), so its variable
-- height never has to be predicted.
local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Theme = require(script.Parent.Parent.Parent.Theme)
local Platform = require(script.Parent.Parent.Parent.Platform)
local LobbySettings = require(script.Parent.Parent.Parent.LobbySettings)
local LobbySettingsPanel = require(script.Parent.Parent.Parent.panels.LobbySettingsPanel)
local LobbyCountdownBanner = require(script.Parent.Parent.Parent.panels.LobbyCountdownBanner)
local PlayerList = require(script.Parent.PlayerList)
local MapPreview = require(script.Parent.MapPreview)
local TeamLayoutPicker = require(script.Parent.TeamLayoutPicker)
local MapData = require(ReplicatedStorage.Shared.GameData.MapData)
local TeamLayoutsData = require(ReplicatedStorage.Shared.GameData.TeamLayoutsData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local LobbyDebug = DebugManager.createChannel("Lobby", false)

local Lobby = React.Component:extend("Lobby")

local localPlayer = Players.LocalPlayer

local SETTINGS_GROUPS = {
	{ title = "Map Settings", settings = LobbySettings.MapSettings },
	{ title = "Starting Resources", settings = LobbySettings.StartingResources },
	{ title = "Gameplay Modifiers", settings = LobbySettings.GameplayModifiers },
	{ title = "Pacing & Economy", settings = LobbySettings.PacingAndEconomy },
}

local function getInitialState()
	local state: any = {
		players = {},
		mapKeys = MapData.getMapList(),
		selectedMap = MapData.DefaultMap,
		-- Real map capacity now comes from the server's own broadcast
		-- (LobbyManager.broadcastLobbyState -> MaxPlayers) instead of being
		-- re-derived here from selectedMap -- see the FIX note in
		-- LobbyManager.luau's broadcastLobbyState.
		maxPlayers = 4,
		teamLayout = TeamLayoutsData.Default,
		spawnSelections = {}, -- { [spawnNumber] = { userId, name } }
		mySpawn = nil,
		myFaction = nil,
		isReady = false,
		countdownActive = false,
		countdownTimeRemaining = 0,
		compact = Platform.isCompact(),
		-- What the LOCAL player last voted per setting, tracked client-side --
		-- LobbyManager never broadcasts per-player votes (see
		-- LobbySettingsPanel's header comment), only the winning value.
		myVotes = { selectedMap = MapData.DefaultMap },
	}

	for _, settings in pairs(LobbySettings) do
		for _, setting in ipairs(settings) do
			state[setting.id] = setting.defaultValue
		end
	end

	return state
end

function Lobby:init()
	LobbyDebug:info("Lobby:init() - Initializing lobby component")
	self.state = getInitialState()

	self.isStartingGame = false
	self.countdownThread = nil

	LobbyDebug:info("Waiting for RemoteEvents")
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local LobbyEvent = RemoteEvents:WaitForChild("LobbyEvent")
	local GameEvent = RemoteEvents:WaitForChild("GameEvent")
	LobbyDebug:info("RemoteEvents found and connected")

	self.lobbyConnection = LobbyEvent.OnClientEvent:Connect(function(action, data)
		LobbyDebug:info("Received LobbyEvent from server", { action = action })
		if action == "LobbyStateUpdate" then
			local playersArray = {}
			for _, playerData in pairs(data.Players) do
				table.insert(playersArray, {
					userId = playerData.UserId,
					name = playerData.Name,
					isAI = playerData.IsAI,
					isReady = playerData.IsReady,
					faction = playerData.SelectedFaction,
					selectedColor = playerData.SelectedColor,
					teamIndex = playerData.TeamIndex,
				})
			end

			local newState: any = {
				players = playersArray,
				countdownActive = data.CountdownActive,
				countdownTimeRemaining = data.CountdownTimeRemaining,
			}
			LobbyDebug:info("Players updated", { playerCount = #playersArray })

			for key, value in pairs(data.Settings) do
				newState[key] = value
			end

			if data.MaxPlayers then
				newState.maxPlayers = data.MaxPlayers
			end

			newState.mapKeys = self.state.mapKeys

			if data.SpawnSelections then
				newState.spawnSelections = data.SpawnSelections
			end

			local myPlayerData = data.Players[localPlayer.UserId]
			if myPlayerData then
				newState.myFaction = myPlayerData.SelectedFaction
				newState.isReady = myPlayerData.IsReady
			end

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

			if self.countdownThread then
				task.cancel(self.countdownThread)
			end

			self.countdownThread = task.spawn(function()
				local timeLeft = data
				while timeLeft > 0 do
					task.wait(1)
					timeLeft -= 1
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

			if self.countdownThread then
				task.cancel(self.countdownThread)
				self.countdownThread = nil
			end
		elseif action == "FactionTaken" then
			warn("Faction already taken:", data)
		elseif action == "LobbyGameStart" then
			LobbyDebug:info("Game starting with settings:", data)
			GameEvent:FireServer("StartGame", data)
			local navigate = self.props.navigate
			if navigate then
				navigate("hud")
			end
		end
	end)

	self.gameConnection = GameEvent.OnClientEvent:Connect(function(action, data)
		if action == "GameStarted" then
			LobbyDebug:info("Game started successfully with faction:", data.faction)
		end
	end)

	LobbyDebug:info("Sending JoinLobby request to server")
	LobbyEvent:FireServer("JoinLobby")

	-- Pre-select the default map so the server is in sync from the start.
	LobbyEvent:FireServer("VoteSetting", "selectedMap", MapData.DefaultMap)

	self.addAI = function()
		LobbyEvent:FireServer("AddAI")
	end

	self.removePlayer = function(playerInfo)
		LobbyEvent:FireServer("RemovePlayer", playerInfo.userId)
	end

	self.selectMap = function(mapName)
		LobbyEvent:FireServer("VoteSetting", "selectedMap", mapName)
		self:recordVote("selectedMap", mapName)
	end

	self.selectTeamLayout = function(layoutId)
		LobbyEvent:FireServer("VoteSetting", "teamLayout", layoutId)
		self:recordVote("teamLayout", layoutId)
	end

	self.onSettingChanged = function(settingId, newValue)
		LobbyEvent:FireServer("VoteSetting", settingId, newValue)
		self:recordVote(settingId, newValue)
	end

	self.selectSpawn = function(spawnNumber)
		LobbyEvent:FireServer("SelectSpawn", spawnNumber)
	end

	self.selectColor = function(color)
		LobbyEvent:FireServer("SelectColor", color)
	end

	self.selectFaction = function(faction, targetUserId)
		local userId = targetUserId or localPlayer.UserId
		LobbyEvent:FireServer("SelectFaction", faction, userId)
	end

	self.toggleReady = function()
		LobbyEvent:FireServer("ToggleReady")
	end
end

--- Records what the local player actually clicked so LobbySettingsPanel can
--- show "your vote was outvoted" -- see its header comment for why this can't
--- come from the server today.
function Lobby:recordVote(settingId: string, value: any)
	local myVotes = table.clone(self.state.myVotes)
	myVotes[settingId] = value
	self:setState({ myVotes = myVotes })
end

function Lobby:didMount()
	self.platformUnsubscribe = Platform.onChanged(function()
		local compact = Platform.isCompact()
		if compact ~= self.state.compact then
			self:setState({ compact = compact })
		end
	end)
end

function Lobby:willUnmount()
	if self.lobbyConnection then
		self.lobbyConnection:Disconnect()
	end
	if self.gameConnection then
		self.gameConnection:Disconnect()
	end
	if self.platformUnsubscribe then
		self.platformUnsubscribe()
		self.platformUnsubscribe = nil
	end

	if self.countdownThread then
		task.cancel(self.countdownThread)
		self.countdownThread = nil
	end

	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local LobbyEvent = RemoteEvents:FindFirstChild("LobbyEvent")
		if LobbyEvent then
			LobbyEvent:FireServer("LeaveLobby")
		end
	end
end

--- One entry in the map picker. `horizontal` is the compact-mode strip
--- (AutomaticSize width, fixed height); the desktop list uses full-width rows.
function Lobby:renderMapChip(mapKey: string, order: number, horizontal: boolean)
	local mapConfig = MapData.getMap(mapKey)
	local displayName = mapConfig and mapConfig.Name or mapKey
	local isSelected = self.state.selectedMap == mapKey

	return React.createElement("TextButton", {
		key = mapKey,
		LayoutOrder = order,
		Size = if horizontal
			then UDim2.new(0, 0, 1, 0)
			else UDim2.new(1, 0, 0, Theme.Metrics.DesktopTarget),
		AutomaticSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
		BackgroundColor3 = if isSelected then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if isSelected then Theme.Transparency.ScreenCardActive else Theme.Transparency.ScreenCard,
		AutoButtonColor = false,
		Text = "",
		[React.Event.Activated] = function()
			self.selectMap(mapKey)
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", {
			Color = if isSelected then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if isSelected then 0 else Theme.Transparency.Border,
			Thickness = 1,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Label = React.createElement("TextLabel", {
			Size = if horizontal then UDim2.new(0, 0, 1, 0) else UDim2.new(1, 0, 1, 0),
			AutomaticSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
			BackgroundTransparency = 1,
			Text = displayName,
			FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body,
			TextSize = Theme.TextSize.ScreenBody,
			TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

function Lobby:render()
	local navigate = self.props.navigate
	local state = self.state
	local compact = state.compact
	local maxPlayers = state.maxPlayers
	local mapKeys = state.mapKeys or MapData.getMapList()
	-- Only offer layouts the current map can actually seat -- a 2v2 needs
	-- four spawns and must not be pickable on a two-spawn map.
	local playableLayouts = TeamLayoutsData.getPlayableOn(maxPlayers)

	-- Fixed row constants for the pinned Header/Footer; see the module comment
	-- for why MainArea's fill-remaining math only ever depends on these two.
	local headerHeight = 32
	local footerHeight = Platform.tokens.hitTarget + Theme.Metrics.Pad * 2
	local gap = Theme.Metrics.Gap
	-- No Theme token exists for "map preview panel height" (Theme.luau is
	-- scoped to the in-match HUD); Platform.tokens.panelWidth is the closest
	-- real token -- it's sized for exactly this kind of side panel -- so reuse
	-- it here to get a near-square preview instead of inventing a raw literal.
	local mapPreviewHeight = Platform.tokens.panelWidth

	local mapPreview = React.createElement(MapPreview, {
		mapKey = state.selectedMap,
		mapConfig = MapData.getMap(state.selectedMap),
		spawnSelections = state.spawnSelections,
		mySpawn = state.mySpawn,
		onSpawnSelected = self.selectSpawn,
		players = state.players,
		localPlayerId = localPlayer.UserId,
		Size = UDim2.new(1, 0, 0, mapPreviewHeight),
	})

	local countdownBanner = React.createElement(LobbyCountdownBanner, {
		LayoutOrder = 1,
		active = state.countdownActive,
		timeRemaining = state.countdownTimeRemaining,
		compact = compact,
		onCancel = self.toggleReady,
	})

	local playerList = React.createElement(PlayerList, {
		players = state.players,
		maxPlayers = maxPlayers,
		teamLayout = state.teamLayout,
		localPlayerId = localPlayer.UserId,
		spawnSelections = state.spawnSelections,
		onAddAI = self.addAI,
		onRemovePlayer = self.removePlayer,
		onSelectFaction = self.selectFaction,
		onSelectColor = self.selectColor,
		compact = compact,
	})

	local teamLayoutPicker = React.createElement(TeamLayoutPicker, {
		LayoutOrder = 1,
		layoutIds = playableLayouts,
		selectedLayout = state.teamLayout,
		onSelect = self.selectTeamLayout,
		compact = compact,
	})

	local settingsPanel = React.createElement(LobbySettingsPanel, {
		groups = SETTINGS_GROUPS,
		values = state,
		myVotes = state.myVotes,
		onVote = self.onSettingChanged,
		compact = compact,
	})

	local mainArea
	if compact then
		local mapChips: { [string]: any } = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, Theme.Metrics.GapTight),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}
		for i, mapKey in mapKeys do
			mapChips[mapKey] = self:renderMapChip(mapKey, i, true)
		end

		mainArea = React.createElement("ScrollingFrame", {
			Name = "MainArea",
			Position = UDim2.new(0, 0, 0, headerHeight + gap),
			Size = UDim2.new(1, 0, 1, -(headerHeight + footerHeight + gap * 2)),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.fromScale(0, 0),
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, Theme.Metrics.GapLoose),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Countdown = countdownBanner,
			MapSection = React.createElement("Frame", {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, Theme.Metrics.Gap),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Preview = mapPreview,
				Strip = React.createElement("ScrollingFrame", {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, Theme.Metrics.TouchTarget),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ScrollingDirection = Enum.ScrollingDirection.X,
					ScrollBarThickness = 4,
					AutomaticCanvasSize = Enum.AutomaticSize.X,
					CanvasSize = UDim2.fromScale(0, 0),
				}, mapChips),
			}),
			Players = React.createElement("Frame", {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, { List = playerList }),
			TeamLayout = React.createElement("Frame", {
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, { Picker = teamLayoutPicker }),
			Settings = React.createElement("Frame", {
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, { Panel = settingsPanel }),
		})
	else
		local mapListRows: { [string]: any } = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, Theme.Metrics.GapTight),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}
		for i, mapKey in mapKeys do
			mapListRows[mapKey] = self:renderMapChip(mapKey, i, false)
		end

		local leftColumn = React.createElement("Frame", {
			Name = "LeftColumn",
			Size = UDim2.new(0.38, -gap / 2, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Preview = mapPreview,
			MapListLabel = React.createElement("TextLabel", {
				Position = UDim2.new(0, 0, 0, mapPreviewHeight + gap),
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				Text = "Maps",
				FontFace = Theme.FontFace.BodyBold,
				TextSize = Theme.TextSize.ScreenSmall,
				TextColor3 = Theme.Color.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			MapList = React.createElement("ScrollingFrame", {
				Position = UDim2.new(0, 0, 0, mapPreviewHeight + gap + 16 + Theme.Metrics.GapTight),
				Size = UDim2.new(1, 0, 1, -(mapPreviewHeight + gap + 16 + Theme.Metrics.GapTight)),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = 4,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.fromScale(0, 0),
			}, mapListRows),
		})

		local rightColumn = React.createElement("ScrollingFrame", {
			Name = "RightColumn",
			Position = UDim2.new(0.4, 0, 0, 0),
			Size = UDim2.new(0.6, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.fromScale(0, 0),
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, Theme.Metrics.GapLoose),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Countdown = countdownBanner,
			Players = React.createElement("Frame", {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, { List = playerList }),
			TeamLayout = React.createElement("Frame", {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, { Picker = teamLayoutPicker }),
			Settings = React.createElement("Frame", {
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, { Panel = settingsPanel }),
		})

		mainArea = React.createElement("Frame", {
			Name = "MainArea",
			Position = UDim2.new(0, 0, 0, headerHeight + gap),
			Size = UDim2.new(1, 0, 1, -(headerHeight + footerHeight + gap * 2)),
			BackgroundTransparency = 1,
		}, {
			Left = leftColumn,
			Right = rightColumn,
		})
	end

	return React.createElement("Frame", {
		Name = "LobbyScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- The SAME backdrop MainMenu uses, so the out-of-match flow reads as one
		-- place. This screen previously had a fully transparent root with only a
		-- glass wash over it, borrowing the in-match HUD's translucency -- but
		-- there is no gameplay behind a lobby to see through to, so all that
		-- achieved was text competing with whatever happened to be behind the
		-- screen. Menus get a backdrop and a scrim; only the HUD is glass.
		Backdrop = React.createElement("ImageLabel", {
			Name = "Backdrop",
			Image = Theme.MenuBackgroundImage,
			ScaleType = Enum.ScaleType.Crop,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}),

		-- Darkens the backdrop so light text is legible over any part of it.
		Scrim = React.createElement("Frame", {
			Name = "Scrim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.ScreenScrim,
			BorderSizePixel = 0,
			ZIndex = 2,
		}),

		Content = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, Theme.Metrics.PadLoose),
				PaddingBottom = UDim.new(0, Theme.Metrics.PadLoose),
				PaddingLeft = UDim.new(0, Theme.Metrics.PadLoose),
				PaddingRight = UDim.new(0, Theme.Metrics.PadLoose),
			}),

			Header = React.createElement("Frame", {
				Name = "Header",
				Size = UDim2.new(1, 0, 0, headerHeight),
				BackgroundTransparency = 1,
			}, {
				Title = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 1,
					Text = "Lobby",
					FontFace = Theme.FontFace.Display,
					TextSize = Theme.TextSize.ScreenTitle,
					TextColor3 = Theme.Color.TextPrimary,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			}),

			Main = mainArea,

			Footer = React.createElement("Frame", {
				Name = "Footer",
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				Size = UDim2.new(1, 0, 0, footerHeight),
				BackgroundTransparency = 1,
			}, {
				-- Hidden entirely while the countdown banner is up -- that banner
				-- is now the only Ready/Cancel affordance, so there's nothing for
				-- this button to do until the countdown ends or gets cancelled.
				ReadyButton = (not state.countdownActive) and React.createElement("TextButton", {
					Size = UDim2.new(1, -120, 1, -Theme.Metrics.Pad),
					BackgroundColor3 = if state.isReady then Theme.Color.Accent else Theme.Color.Action,
					BackgroundTransparency = Theme.Transparency.ScreenCardActive,
					AutoButtonColor = false,
					Text = if state.isReady then "Ready ✓" else "Ready Up",
					FontFace = Theme.FontFace.BodyBold,
					TextSize = Theme.TextSize.ScreenHeading,
					TextColor3 = if state.isReady then Theme.Color.Accent else Theme.Color.TextPrimary,
					[React.Event.Activated] = self.toggleReady,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
					Stroke = React.createElement("UIStroke", {
						Color = if state.isReady then Theme.Color.Accent else Theme.Color.Border,
						Transparency = if state.isReady then 0 else Theme.Transparency.Border,
						Thickness = 1,
					}),
				}) or nil,

				BackButton = React.createElement("TextButton", {
					Position = UDim2.new(1, 0, 0, 0),
					AnchorPoint = Vector2.new(1, 0),
					Size = UDim2.new(0, 110, 1, -Theme.Metrics.Pad),
					BackgroundColor3 = Theme.Color.SurfaceRaised,
					BackgroundTransparency = Theme.Transparency.ScreenCard,
					AutoButtonColor = false,
					Text = "Leave",
					FontFace = Theme.FontFace.Body,
					TextSize = Theme.TextSize.ScreenBody,
					TextColor3 = Theme.Color.TextSecondary,
					[React.Event.Activated] = function()
						if navigate then
							navigate("mainMenu")
						end
					end,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
					Stroke = React.createElement("UIStroke", Theme.strokeProps()),
				}),
			}),
		}),
	})
end

return Lobby
