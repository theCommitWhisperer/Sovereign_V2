--!strict
-- Generic Modal component for overlays (Keep placement, Tutorial, Policies, Laws, Taxes, Menu, Stats, Tech, etc.)
-- Updated to match modern dark Peat/Gold design language with Theme.luau & MedievalCorners.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)
local MedievalCorners = require(script.Parent.Parent.components.MedievalCorners)

local Modal = React.Component:extend("Modal")

export type Props = {
	title: string,
	visible: boolean?,
	onClose: (() -> ())?,
	children: any,
	size: UDim2?,
}

function Modal:render()
	local visible = if self.props.visible ~= nil then self.props.visible else true
	local size = self.props.size or UDim2.fromScale(0.5, 0.6)

	if not visible then
		return nil
	end

	return React.createElement("ScreenGui", {
		Name = "ModalOverlay",
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100, -- Above HUD
		ResetOnSpawn = false,
	}, {
		-- Semi-transparent background overlay
		Background = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = Theme.Transparency.ScreenScrim,
			BorderSizePixel = 0,
		}),

		-- Centered dark Peat panel with Celtic Gold border & Medieval Corners
		MainPanel = React.createElement("Frame", {
			Size = size,
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.ScreenPanel,
			BorderSizePixel = 0,
			ZIndex = 101,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Corners = React.createElement(MedievalCorners, { size = 20, color = Theme.Color.Accent, thickness = 3 }),

			-- Header
			Header = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 60),
				BackgroundTransparency = 1,
			}, {
				Title = React.createElement("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = self.props.title,
					FontFace = Theme.FontFace.Display,
					TextSize = Theme.TextSize.Header,
					TextColor3 = Theme.Color.Accent,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
				}),

				-- X button in top-right corner (only if onClose is provided)
				CloseButtonTop = self.props.onClose and React.createElement("TextButton", {
					Size = UDim2.fromOffset(36, 36),
					Position = UDim2.new(1, -48, 0, 12),
					BackgroundColor3 = Theme.Color.SurfaceRaised,
					BackgroundTransparency = 0,
					AutoButtonColor = true,
					Text = "✕",
					FontFace = Theme.FontFace.Display,
					TextSize = 16,
					TextColor3 = Theme.Color.TextSecondary,
					[React.Event.Activated] = self.props.onClose,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
					Stroke = React.createElement("UIStroke", Theme.strokeProps()),
				}) or nil,

				HeaderDivider = React.createElement("Frame", {
					Size = UDim2.new(1, -32, 0, 1),
					Position = UDim2.new(0, 16, 1, -1),
					BackgroundColor3 = Theme.Color.Border,
					BorderSizePixel = 0,
				}),
			}),

			-- Content area (scrollable)
			ContentFrame = React.createElement("ScrollingFrame", {
				Position = UDim2.new(0, 0, 0, 60),
				Size = UDim2.new(1, 0, 1, if self.props.onClose then -120 else -60),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				ScrollBarImageColor3 = Theme.Color.Accent,
				CanvasSize = UDim2.fromScale(1, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 24),
					PaddingRight = UDim.new(0, 24),
				}),

				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),

				-- Children content passed in
				Content = React.createElement(React.Fragment, nil, self.props.children),
			}),

			-- Footer with close button (only if onClose is provided)
			Footer = self.props.onClose and React.createElement("Frame", {
				Position = UDim2.new(0, 0, 1, -60),
				Size = UDim2.new(1, 0, 0, 60),
				BackgroundTransparency = 1,
			}, {
				FooterDivider = React.createElement("Frame", {
					Size = UDim2.new(1, -32, 0, 1),
					Position = UDim2.new(0, 16, 0, 0),
					BackgroundColor3 = Theme.Color.Border,
					BorderSizePixel = 0,
				}),
				CloseButton = React.createElement("TextButton", {
					Size = UDim2.fromOffset(160, 36),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = Theme.Color.SurfaceRaised,
					BackgroundTransparency = 0,
					AutoButtonColor = true,
					Text = "Close",
					FontFace = Theme.FontFace.BodyBold,
					TextSize = Theme.TextSize.Body,
					TextColor3 = Theme.Color.TextPrimary,
					[React.Event.Activated] = self.props.onClose,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
					Stroke = React.createElement("UIStroke", Theme.strokeProps()),
				}),
			}) or nil,
		}),
	})
end

return Modal
