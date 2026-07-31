--!strict
-- UndoButton: Clean 26px utility button for building deletion undo.
-- Integrated declaratively into the right utility column with zero layout overflow.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Parent.Theme)

export type Props = {
	deletionHistory: { { buildingType: string } }?,
	onUndo: () -> (),
	LayoutOrder: number?,
}

local function UndoButton(props: Props)
	local hasHistory = props.deletionHistory ~= nil and #props.deletionHistory > 0
	local count = if hasHistory then #props.deletionHistory else 0

	local isHovered, setIsHovered = React.useState(false)

	return React.createElement("TextButton", {
		Name = "UndoBtn",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = if hasHistory then Theme.Color.SurfaceRaised else Color3.fromRGB(28, 24, 18),
		BackgroundTransparency = if hasHistory then Theme.Transparency.Card else 0.5,
		AutoButtonColor = hasHistory,
		Text = if hasHistory then string.format("↶ Undo (%d)", count) else "↶ Undo",
		FontFace = Theme.FontFace.Body,
		TextSize = Theme.TextSize.Caption,
		TextColor3 = if hasHistory then Theme.Color.TextPrimary else Theme.Color.TextMuted,
		TextStrokeTransparency = 1,
		LayoutOrder = props.LayoutOrder or 8,
		[React.Event.Activated] = function()
			if hasHistory then
				props.onUndo()
			end
		end,
		[React.Event.MouseEnter] = function()
			if hasHistory then
				setIsHovered(true)
			end
		end,
		[React.Event.MouseLeave] = function()
			setIsHovered(false)
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = if hasHistory then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if hasHistory then 0.2 else 0.8,
			Thickness = 1,
		}),
	})
end

return UndoButton
