local React = require(game.ReplicatedStorage.Packages.react)

local Router = React.Component:extend("Router")

function Router:render()
    print("Router.luau: render() called.")
    local route = self.props.route
    local routes = self.props.routes

    print("Router.luau: Attempting to find component for route:", route)

    if routes[route] then
        print("Router.luau: Found component for route. Rendering now.")
        return React.createElement(routes[route], self.props.routeProps)
    else
        warn("Router.luau: No component found for route:", route, "- Rendering nothing.")
        return nil
    end
end

return Router
