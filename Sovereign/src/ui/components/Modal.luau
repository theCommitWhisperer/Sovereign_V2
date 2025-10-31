--!strict
-- Generic Modal component for overlays (Policies, Menu, Stats, etc.)
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)

local Modal = React.Component:extend("Modal")

export type Props = {
	title: string,
	visible: boolean?,
	onClose: () -> (),
	children: any,
	size: UDim2?,
}

function Modal:render()
	local visible = if self.props.visible ~= nil then self.props.visible else true
	local size = self.props.size or UDim2.fromScale(0.6, 0.9)

	if not visible then
		return nil
	end

	return React.createElement("ScreenGui", {
		Name = "ModalOverlay",
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10, -- Above HUD
		ResetOnSpawn = false,
	}, {
		-- Semi-transparent background overlay
		Background = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		}),

		-- Centered scroll/parchment frame
		ScrollImage = React.createElement("ImageLabel", {
			Size = size,
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = UIConfig.HUD.PanelBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.PanelBorder,
			Image = "rbxassetid://137329762725330", -- Scroll/parchment texture
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(100, 100, 412, 412),
		}, {
			-- Header
			Header = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 80),
				BackgroundTransparency = 1,
			}, {
				Title = React.createElement("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = self.props.title,
					Font = Enum.Font.GothamBold,
					TextSize = 42,
					TextColor3 = UIConfig.HUD.PanelHeaderColor,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
				}),

				-- X button in top-right corner
				CloseButtonTop = React.createElement("TextButton", {
					Size = UDim2.new(0, 50, 0, 50),
					Position = UDim2.new(1, -60, 0, 15),
					BackgroundColor3 = Color3.fromRGB(60, 60, 65),
					BorderSizePixel = 2,
					BorderColor3 = UIConfig.HUD.UtilityButtonBorder,
					Text = "X",
					Font = Enum.Font.GothamBold,
					TextSize = 28,
					TextColor3 = Color3.fromRGB(220, 220, 220),
					[React.Event.MouseButton1Click] = self.props.onClose,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				}),
			}),

			-- Content area (scrollable)
			ContentFrame = React.createElement("ScrollingFrame", {
				Position = UDim2.new(0, 0, 0, 80),
				Size = UDim2.new(1, 0, 1, -160),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 8,
				ScrollBarImageColor3 = UIConfig.HUD.PanelBorder,
				CanvasSize = UDim2.fromScale(1, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 20),
					PaddingBottom = UDim.new(0, 20),
					PaddingLeft = UDim.new(0, 40),
					PaddingRight = UDim.new(0, 40),
				}),

				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 15),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),

				-- Children content passed in
				Content = React.createElement(React.Fragment, nil, self.props.children),
			}),

			-- Footer with close button
			Footer = React.createElement("Frame", {
				Position = UDim2.new(0, 0, 1, -80),
				Size = UDim2.new(1, 0, 0, 80),
				BackgroundTransparency = 1,
			}, {
				CloseButton = React.createElement("TextButton", {
					Size = UDim2.new(0, 200, 0, 50),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = UIConfig.HUD.UtilityButtonBackground,
					BorderSizePixel = 2,
					BorderColor3 = UIConfig.HUD.UtilityButtonBorder,
					Text = "Close",
					Font = Enum.Font.GothamBold,
					TextSize = 24,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					[React.Event.MouseButton1Click] = self.props.onClose,
				}),
			}),
		}),
	})
end

return Modal
