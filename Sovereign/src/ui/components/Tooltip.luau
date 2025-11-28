local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)

local Tooltip = React.Component:extend("Tooltip")

function Tooltip:init()
	self.state = {
		visible = false,
		text = "",
		target = nil,
		position = UDim2.fromOffset(-10000, -10000),
	}

	-- External API to control the tooltip
	self.api = {
		show = function(text, target)
			self:setState({
				visible = true,
				text = text,
				target = target,
				position = UDim2.fromOffset(-10000, -10000), -- Initially off-screen
			})
		end,
		hide = function()
			self:setState({ visible = false, target = nil })
		end,
	}
end

function Tooltip:render()
	if not self.state.visible or not self.state.target then
		return nil
	end

	return React.createElement("ScreenGui", {
		Name = "TooltipGui",
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 999,
	}, {
		TooltipFrame = React.createElement("Frame", {
			Name = "TooltipFrame",
			AutomaticSize = Enum.AutomaticSize.XY,
			Position = self.state.position,
			BackgroundColor3 = UIConfig.HUD.TooltipBackground or Color3.fromRGB(20, 20, 25),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			[React.Change.AbsoluteSize] = function(rbx)
				if self.state.target then
					local target = self.state.target
					local x = target.AbsolutePosition.X + (target.AbsoluteSize.X / 2) - (rbx.AbsoluteSize.X / 2)
					local y = target.AbsolutePosition.Y - rbx.AbsoluteSize.Y - 5 -- 5 pixels offset
					self:setState({ position = UDim2.fromOffset(x, y) })
				end
			end,
		}, {
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(300, 1000),
			}),
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(100, 100, 120),
				Thickness = 1,
				Transparency = 0.3,
			}),
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
			TooltipText = React.createElement("TextLabel", {
				Name = "TooltipText",
				Size = UDim2.fromScale(1, 1),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = self.state.text,
				TextColor3 = UIConfig.HUD.TooltipText or Color3.fromRGB(230, 230, 240),
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				RichText = true,
			}),
		}),
	})
end

return Tooltip
