local React = require(game.ReplicatedStorage.Packages.react)

local Textbox = React.Component:extend("Textbox")

function Textbox:render()
    return React.createElement("Frame", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
    }, {
        Layout = React.createElement("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
        }),
        Label = React.createElement("TextLabel", {
            Text = self.props.Label,
            Size = UDim2.new(0.4, 0, 1, 0),
            TextSize = 24,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        Input = React.createElement("TextBox", {
            Size = UDim2.new(0.6, 0, 1, 0),
            Text = self.props.defaultText or "",
            TextSize = 24,
            [React.Event.FocusLost] = function(rbx)
                if self.props.onTextChanged then
                    self.props.onTextChanged(rbx.Text)
                end
            end,
        }),
    })
end

return Textbox