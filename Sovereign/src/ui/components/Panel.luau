-- A reusable panel component for consistent UI containers.
local React = require(game.ReplicatedStorage.Packages.react)
local Panel = React.Component:extend("Panel")
function Panel:render()
	return React.createElement("Frame", self.props)
end
return Panel
