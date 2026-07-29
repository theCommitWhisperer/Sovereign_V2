--!strict
-- PlacementBanner: the PLACING bottom-zone state. Replaces the category rail
-- entirely while a placement is in flight -- Confirm/Cancel are the only
-- sensible actions until it resolves, so nothing else competes for the tap.
--
-- The actual ground-tap-to-place gesture is owned by PlacementController
-- (src/client), out of scope here. Confirm/Cancel only clear the shared
-- HUDStore flags that drive this banner's visibility; see MobileShell for why
-- that's the extent of what this layer can do without a dedicated HUDStore
-- action.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)

export type Props = {
	buildingName: string,
	onConfirm: () -> (),
	onCancel: () -> (),
	LayoutOrder: number?,
}

local function actionButton(text: string, layoutOrder: number, color: Color3, onClick: () -> ())
	return React.createElement("TextButton", {
		LayoutOrder = layoutOrder,
		Size = UDim2.new(0.5, -Theme.Metrics.GapTight, 1, 0),
		BackgroundColor3 = color,
		BackgroundTransparency = Theme.Transparency.CardActive,
		AutoButtonColor = false,
		Text = text,
		FontFace = Theme.FontFace.BodyBold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.TextPrimary,
		[React.Event.Activated] = onClick,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
	})
end

local function PlacementBanner(props: Props)
	return React.createElement("Frame", {
		Name = "PlacementBanner",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = Theme.Transparency.Drawer,
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusCard) }),
		Stroke = React.createElement("UIStroke", {
			Color = Theme.Color.Accent,
			Transparency = Theme.Transparency.BorderStrong,
			Thickness = 2,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.Pad),
			PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
			PaddingLeft = UDim.new(0, Theme.Metrics.PadLoose),
			PaddingRight = UDim.new(0, Theme.Metrics.PadLoose),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Title = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = `Placing {props.buildingName}`,
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.Heading,
			TextColor3 = Theme.Color.Accent,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Subtitle = React.createElement("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = "Tap the ground to place",
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Buttons = React.createElement("Frame", {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, Theme.Metrics.TouchTarget),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, Theme.Metrics.GapTight * 2),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Confirm = actionButton("Confirm", 1, Theme.Color.Action, props.onConfirm),
			Cancel = actionButton("Cancel", 2, Theme.Color.Surface, props.onCancel),
		}),
	})
end

return PlacementBanner
