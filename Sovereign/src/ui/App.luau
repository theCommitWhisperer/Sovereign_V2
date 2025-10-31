local React = require(game.ReplicatedStorage.Packages.react)
local Router = require(script.Parent.Router)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local AppDebug = DebugManager.createChannel("App", true)

-- Updated paths to the new 'screens' directory
local MainMenu = require(script.Parent.screens.MainMenu.MainMenu)
local Settings = require(script.Parent.screens.Settings.Settings)
local Lobby = require(script.Parent.screens.Lobby.Lobby)
local HUD = require(script.Parent.screens.HUD.HUD)
local VictoryScreen = require(script.Parent.screens.PostGame.VictoryScreen)
local DefeatScreen = require(script.Parent.screens.PostGame.DefeatScreen)
local Keybindings = require(script.Parent.screens.Keybindings.Keybindings)

local App = React.Component:extend("App")

function App:init()
	AppDebug:info("App:init() called.")
	self:setState({
		route = "mainMenu", -- Default screen
	})

	self.routes = {
		mainMenu = MainMenu,
		settings = Settings,
		lobby = Lobby,
		hud = HUD,
		victory = VictoryScreen,
		defeat = DefeatScreen,
		keybindings = Keybindings,
	}

	-- NEW: Get RemoteEvent reference
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	self.gameEvent = RemoteEvents:WaitForChild("GameEvent")

	-- NEW: Listen for game started confirmation
	self.gameEvent.OnClientEvent:Connect(function(action, data)
		if action == "GameStarted" then
			AppDebug:info("Game started! Switching to HUD.")
			self:setState({ route = "hud" })
		elseif action == "GameLeft" then
			AppDebug:info("Game left! Switching to main menu.")
			self:setState({ route = "mainMenu" })
		end
	end)

	self.navigate = function(route)
		AppDebug:info("App:navigate() called with route:", route)

		-- Navigation to HUD is now handled by GameStarted event from server
		-- Lobby sends StartGame event directly, so don't send it again here
		self:setState({ route = route })
	end
end

function App:render()
	AppDebug:info("App:render() called. Current route is:", self.state.route)
	return React.createElement(Router, {
		route = self.state.route,
		routes = self.routes,
		routeProps = {
			navigate = self.navigate,
		},
	})
end

return App
