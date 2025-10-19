local React = require(game.ReplicatedStorage.Packages.react)
local Router = require(script.Parent.Router)

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
	print("App.luau: init() called.")
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
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	self.gameEvent = RemoteEvents:WaitForChild("GameEvent")

	-- NEW: Listen for game started confirmation
	self.gameEvent.OnClientEvent:Connect(function(action, data)
		if action == "GameStarted" then
			print("App.luau: Game started! Switching to HUD.")
			self:setState({ route = "hud" })
		end
	end)

	self.navigate = function(route)
		print("App.luau: navigate() called with route:", route)

		-- NEW: If navigating to HUD, send StartGame event to server
		if route == "hud" then
			print("App.luau: Sending StartGame request to server")
			self.gameEvent:FireServer("StartGame", {})
		end

		self:setState({ route = route })
	end
end

function App:render()
	print("App.luau: render() called. Current route is:", self.state.route)
	return React.createElement(Router, {
		route = self.state.route,
		routes = self.routes,
		routeProps = {
			navigate = self.navigate,
		},
	})
end

return App
