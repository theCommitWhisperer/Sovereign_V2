local React = require(game.ReplicatedStorage.Packages.react)
local Router = require(script.Parent.Router)

-- Updated paths to the new 'screens' directory
local MainMenu = require(script.Parent.screens.MainMenu.MainMenu)
local Settings = require(script.Parent.screens.Settings.Settings)
local Lobby = require(script.Parent.screens.Lobby.Lobby)
local HUD = require(script.Parent.screens.HUD.HUD)
local VictoryScreen = require(script.Parent.screens.PostGame.VictoryScreen)
local DefeatScreen = require(script.Parent.screens.PostGame.DefeatScreen)

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
    }

    self.navigate = function(route)
        print("App.luau: navigate() called with route:", route)
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
