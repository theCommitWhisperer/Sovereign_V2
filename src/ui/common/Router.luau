local React = require(game.ReplicatedStorage.Packages.react)

local Router = React.Component:extend("Router")

function Router:render()
    local route = self.props.route
    local routes = self.props.routes

    if routes[route] then
        return React.createElement(routes[route], self.props.routeProps)
    else
        return nil
    end
end

return Router
