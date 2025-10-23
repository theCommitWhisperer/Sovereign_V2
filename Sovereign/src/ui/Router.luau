local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local RouterDebug = DebugManager.createChannel("Router", false)

local Router = React.Component:extend("Router")

function Router:render()
	RouterDebug:info("Router:render() called.")
	local route = self.props.route
	local routes = self.props.routes

	RouterDebug:info("Attempting to find component for route:", route)

	if routes[route] then
		RouterDebug:info("Found component for route. Rendering now.")
		return React.createElement(routes[route], self.props.routeProps)
	else
		RouterDebug:warn("Router.luau: No component found for route:", route, "- Rendering nothing.")
		return nil
	end
end

return Router
