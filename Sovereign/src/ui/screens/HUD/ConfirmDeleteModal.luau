--!strict
-- ConfirmDeleteModal: Shows a confirmation dialog when deleting important buildings

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local ConfirmDeleteModal = {}

export type Props = {
	buildingName: string,
	buildingType: string,
	refundInfo: string?,
	onConfirm: () -> (),
	onCancel: () -> (),
}

function ConfirmDeleteModal.new(props: Props)
	local dialogHeight = props.refundInfo and 240 or 200

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		ZIndex = 1000,
	}, {
		DialogBox = React.createElement("Frame", {
			Size = UDim2.fromOffset(400, dialogHeight),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = UIConfig.HUD.PanelBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.PanelBorder,
			ZIndex = 1001,
		}, {
			UICorner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),

			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 15),
				PaddingBottom = UDim.new(0, 15),
				PaddingLeft = UDim.new(0, 20),
				PaddingRight = UDim.new(0, 20),
			}),

			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 15),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),

			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				Text = "⚠️ Confirm Deletion",
				Font = Enum.Font.GothamBold,
				TextSize = 20,
				TextColor3 = UIConfig.Colors.Warning,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),

			Message = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 60),
				BackgroundTransparency = 1,
				Text = string.format(
					"Are you sure you want to delete this %s?\n\n%s",
					props.buildingType,
					props.buildingName
				),
				Font = Enum.Font.Gotham,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),

			RefundInfo = props.refundInfo and React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				Text = "💰 Refund: " .. props.refundInfo,
				Font = Enum.Font.Gotham,
				TextSize = 13,
				TextColor3 = UIConfig.Colors.Success,
				TextXAlignment = Enum.TextXAlignment.Center,
			}) or nil,

			ButtonContainer = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 10),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
				}),

				CancelButton = React.createElement("TextButton", {
					Size = UDim2.fromOffset(150, 40),
					BackgroundColor3 = UIConfig.HUD.CategoryButtonBackground,
					BorderSizePixel = 1,
					BorderColor3 = UIConfig.HUD.CategoryButtonBorder,
					Text = "Cancel",
					Font = Enum.Font.GothamBold,
					TextSize = 16,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					[React.Event.MouseButton1Click] = props.onCancel,
				}, {
					UICorner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 4),
					}),
				}),

				ConfirmButton = React.createElement("TextButton", {
					Size = UDim2.fromOffset(150, 40),
					BackgroundColor3 = UIConfig.Colors.Danger,
					BorderSizePixel = 1,
					BorderColor3 = Color3.new(0.6, 0, 0),
					Text = "Delete",
					Font = Enum.Font.GothamBold,
					TextSize = 16,
					TextColor3 = Color3.new(1, 1, 1),
					[React.Event.MouseButton1Click] = props.onConfirm,
				}, {
					UICorner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 4),
					}),
				}),
			}),
		}),
	})
end

return ConfirmDeleteModal
