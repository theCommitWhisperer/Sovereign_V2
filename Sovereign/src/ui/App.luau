local React = require(game.ReplicatedStorage.Packages.react)
local Router = require(script.Parent.Router)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local AppDebug = DebugManager.createChannel("App", true)

-- Screens
local MainMenu = require(script.Parent.screens.MainMenu.MainMenu)
local Settings = require(script.Parent.screens.Settings.Settings)
local Lobby = require(script.Parent.screens.Lobby.Lobby)
local HUD = require(script.Parent.screens.HUD.HUD)
local VictoryScreen = require(script.Parent.screens.PostGame.VictoryScreen)
local DefeatScreen = require(script.Parent.screens.PostGame.DefeatScreen)
local Keybindings = require(script.Parent.screens.Keybindings.Keybindings)

-- Components
local Tooltip = require(script.Parent.components.Tooltip)

local App = React.Component:extend("App")

function App:init()
	AppDebug:info("App:init() called.")
	self:setState({
		route = "mainMenu", -- Default screen
		gameStartData = nil, -- Store GameStarted data to pass to HUD
	})

	self.tooltipRef = React.createRef()

	self.routes = {
		mainMenu = MainMenu,
		settings = Settings,
		lobby = Lobby,
		hud = HUD,
		victory = VictoryScreen,
		defeat = DefeatScreen,
		keybindings = Keybindings,
	}

	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	self.gameEvent = RemoteEvents:WaitForChild("GameEvent")

	self.gameEvent.OnClientEvent:Connect(function(action, data)
		if action == "GameStarted" then
			AppDebug:info("Game started! Switching to HUD.", data)
			-- Store the game start data to pass to HUD
			self:setState({
				route = "hud",
				gameStartData = data
			})
		elseif action == "GameLeft" then
			AppDebug:info("Game left! Switching to main menu.")
			self:setState({
				route = "mainMenu",
				gameStartData = nil
			})
		end
	end)

	self.navigate = function(route)
		AppDebug:info("App:navigate() called with route:", route)
		self:setState({ route = route })
	end
end

function App:render()
	AppDebug:info("App:render() called. Current route is:", self.state.route)

	local tooltipApi = self.tooltipRef and self.tooltipRef.current and self.tooltipRef.current.api

	return React.createElement(React.Fragment, {}, {
		Router = React.createElement(Router, {
			route = self.state.route,
			routes = self.routes,
			routeProps = {
				navigate = self.navigate,
				tooltip = tooltipApi, -- Pass tooltip API to all routes
				gameStartData = self.state.gameStartData, -- Pass game start data to HUD
			},
		}),
		Tooltip = React.createElement(Tooltip, {
			ref = self.tooltipRef,
		}),
	})
end

return App
