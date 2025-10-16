local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local Button = React.Component:extend("Button")

function Button:render()
    local props = {
        Name = self.props.Name or "Button",
        Text = self.props.Text or "Button",
        Size = self.props.Size or UIConfig.Size.Button,
        Position = self.props.Position,
        AnchorPoint = self.props.AnchorPoint,
        LayoutOrder = self.props.LayoutOrder,

        FontFace = UIConfig.getFont(self.props.FontFace, UIConfig.Font.Button.Default),
        TextSize = self.props.TextSize or 32,
        TextColor3 = self.props.TextColor3 or UIConfig.Color.Primary,
        TextXAlignment = self.props.TextXAlignment or Enum.TextXAlignment.Center,
        BackgroundTransparency = self.props.BackgroundTransparency or 0,
        BackgroundColor3 = self.props.BackgroundColor3 or UIConfig.Color.PrimaryButton,

        [React.Event.MouseButton1Click] = self.props.OnClick,
    }

    return React.createElement("TextButton", props)
end

return Button