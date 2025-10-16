local React = require(game.ReplicatedStorage.Packages.react)
local Router = require(script.Parent.common.Router)
local MainMenuScreen = require(script.Parent.MainMenu.components.MainMenuScreen)
local SettingsPage = require(script.Parent.MainMenu.components.SettingsPage)

local App = React.Component:extend("App")

function App:init()
    self:setState({
        route = "mainMenu",
    })

    self.routes = {
        mainMenu = MainMenuScreen,
        settings = SettingsPage,
    }

    self.navigate = function(route)
        self:setState({ route = route })
    end
end

function App:render()
    return React.createElement(Router, {
        route = self.state.route,
        routes = self.routes,
        routeProps = {
            navigate = self.navigate,
        },
    })
end

return App
