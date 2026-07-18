--!strict
-- TerrainPalette: Material selector grid for terrain brush painting
local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local MapEditorTypes = require(ReplicatedStorage.Shared.MapEditorTypes)

local TerrainPalette = React.Component:extend("TerrainPalette")

function TerrainPalette:render()
	local selectedMaterial = self.props.selectedMaterial or "Grass"
	local onMaterialSelected = self.props.onMaterialSelected

	local materialButtons = {
		UIGridLayout = React.createElement("UIGridLayout", {
			CellSize = UDim2.new(0, 58, 0, 44),
			CellPadding = UDim2.new(0, 4, 0, 4),
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for i, mat in ipairs(MapEditorTypes.TERRAIN_MATERIALS) do
		local isSelected = selectedMaterial == mat.material
		local matColor = Color3.fromRGB(mat.color[1], mat.color[2], mat.color[3])

		materialButtons[mat.material] = React.createElement("TextButton", {
			LayoutOrder = i,
			BackgroundColor3 = matColor,
			BorderSizePixel = 0,
			Text = "",
			[React.Event.MouseButton1Click] = function()
				if onMaterialSelected then
					onMaterialSelected(mat.material)
				end
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			UIStroke = React.createElement("UIStroke", {
				Color = isSelected and Color3.fromRGB(218, 165, 32) or Color3.fromRGB(76, 62, 62),
				Thickness = isSelected and 2.5 or 1,
			}),
			Label = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = mat.name,
				FontFace = UIConfig.Font.Title,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 10,
				TextStrokeTransparency = 0.3,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			}),
			SelectedIndicator = isSelected and React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 3),
				Position = UDim2.new(0, 0, 1, -3),
				BackgroundColor3 = Color3.fromRGB(218, 165, 32),
				BorderSizePixel = 0,
			}) or nil,
		})
	end

	return React.createElement("Frame", {
		Name = "TerrainPalette",
		LayoutOrder = self.props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, 100),
		BackgroundTransparency = 1,
	}, materialButtons)
end

return TerrainPalette
