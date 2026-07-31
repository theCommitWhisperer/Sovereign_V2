--!strict
-- InfoButton: Modular, reusable circular (i) info button component for UIs.
-- Ultra-compact 15px circular vector badge with sharp, tiny 'i' glyph.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)

export type Props = {
	active: boolean?,
	onActivated: () -> (),
	size: number?,
	LayoutOrder: number?,
}

local BOLD_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

local function InfoButton(props: Props)
	local isHovered, setIsHovered = React.useState(false)

	local size = props.size or 15
	local isActive = props.active == true

	return React.createElement("TextButton", {
		Name = "InfoButton",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = if isActive
			then Theme.Color.Accent
			elseif isHovered then Theme.Color.SurfaceRaised
			else Color3.fromRGB(35, 30, 24),
		BackgroundTransparency = 0,
		AutoButtonColor = true,
		Text = "i",
		FontFace = BOLD_FONT,
		TextSize = math.round(size * 0.65), -- ~10px for a 15px circle
		TextColor3 = if isActive then Theme.Color.OnAccent else Theme.Color.Accent,
		TextStrokeTransparency = 1,
		LayoutOrder = props.LayoutOrder,
		[React.Event.Activated] = props.onActivated,
		[React.Event.MouseEnter] = function()
			setIsHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setIsHovered(false)
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Color.Accent,
			Thickness = if isActive then 1.5 else 1,
			Transparency = 0,
		}),
	})
end

return InfoButton
