--!strict
-- Interactive minimap with clickable camera movement and unit/building indicators

local React = require(game.ReplicatedStorage.Packages.react)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local MiniMap = React.Component:extend("MiniMap")

-- Map constants
local MAP_SIZE = 1000  -- 1000x1000 stud map
local MINIMAP_SIZE = UIConfig.HUD.MinimapSize or 170

function MiniMap:init()
	self:setState({
		unitDots = {},
		buildingIcons = {},
	})

	-- Update minimap every 0.5 seconds
	task.spawn(function()
		while true do
			task.wait(0.5)
			self:updateMinimapIndicators()
		end
	end)
end

function MiniMap:updateMinimapIndicators()
	local unitDots = {}
	local buildingIcons = {}

	-- Get units
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		for _, unit in unitsFolder:GetChildren() do
			if unit:IsA("Model") and unit.PrimaryPart then
				local owner = unit:GetAttribute("Owner")
				local pos = unit.PrimaryPart.Position

				-- Convert world position to minimap position (0-1 scale)
				local minimapX = (pos.X + MAP_SIZE/2) / MAP_SIZE
				local minimapZ = (pos.Z + MAP_SIZE/2) / MAP_SIZE

				-- Clamp to minimap bounds
				minimapX = math.clamp(minimapX, 0, 1)
				minimapZ = math.clamp(minimapZ, 0, 1)

				table.insert(unitDots, {
					x = minimapX,
					z = minimapZ,
					isOwned = owner == player.UserId,
					unitType = unit:GetAttribute("UnitType"),
				})
			end
		end
	end

	-- Get buildings
	local buildingsFolder = workspace:FindFirstChild("Buildings")
	if buildingsFolder then
		for _, building in buildingsFolder:GetChildren() do
			if building:IsA("Model") and building.PrimaryPart then
				local owner = building:GetAttribute("Owner")
				local pos = building.PrimaryPart.Position

				-- Convert world position to minimap position (0-1 scale)
				local minimapX = (pos.X + MAP_SIZE/2) / MAP_SIZE
				local minimapZ = (pos.Z + MAP_SIZE/2) / MAP_SIZE

				-- Clamp to minimap bounds
				minimapX = math.clamp(minimapX, 0, 1)
				minimapZ = math.clamp(minimapZ, 0, 1)

				table.insert(buildingIcons, {
					x = minimapX,
					z = minimapZ,
					isOwned = owner == player.UserId,
					buildingType = building:GetAttribute("BuildingType"),
				})
			end
		end
	end

	self:setState({
		unitDots = unitDots,
		buildingIcons = buildingIcons,
	})
end

function MiniMap:onMinimapClick(rbx: GuiObject, input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	-- Get click position relative to minimap
	local mousePos = UserInputService:GetMouseLocation()
	local minimapPos = rbx.AbsolutePosition
	local minimapSize = rbx.AbsoluteSize

	-- Calculate relative position (0-1)
	local relativeX = (mousePos.X - minimapPos.X) / minimapSize.X
	local relativeZ = (mousePos.Y - minimapPos.Y) / minimapSize.Y

	-- Clamp to valid range
	relativeX = math.clamp(relativeX, 0, 1)
	relativeZ = math.clamp(relativeZ, 0, 1)

	-- Convert to world position
	local worldX = (relativeX * MAP_SIZE) - (MAP_SIZE / 2)
	local worldZ = (relativeZ * MAP_SIZE) - (MAP_SIZE / 2)

	-- Move camera to clicked position
	local camera = workspace.CurrentCamera
	if camera then
		local targetPos = Vector3.new(worldX, camera.CFrame.Position.Y, worldZ)
		camera.CFrame = CFrame.new(targetPos, targetPos + camera.CFrame.LookVector)
	end
end

function MiniMap:render()
	local unitDotElements = {}
	local buildingIconElements = {}

	-- Create unit dots
	for i, unit in ipairs(self.state.unitDots) do
		unitDotElements[`Unit{i}`] = React.createElement("Frame", {
			Size = UDim2.new(0, 3, 0, 3),  -- Small dot
			Position = UDim2.fromScale(unit.x, unit.z),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = unit.isOwned
				and Color3.fromRGB(100, 200, 255)  -- Blue for owned units
				or Color3.fromRGB(255, 100, 100),   -- Red for enemy units
			BorderSizePixel = 0,
			ZIndex = 3,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),  -- Make it circular
			}),
		})
	end

	-- Create building icons
	for i, building in ipairs(self.state.buildingIcons) do
		buildingIconElements[`Building{i}`] = React.createElement("Frame", {
			Size = UDim2.new(0, 6, 0, 6),  -- Larger square for buildings
			Position = UDim2.fromScale(building.x, building.z),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = building.isOwned
				and Color3.fromRGB(150, 255, 150)  -- Green for owned buildings
				or Color3.fromRGB(255, 150, 150),   -- Light red for enemy buildings
			BorderSizePixel = 1,
			BorderColor3 = Color3.fromRGB(0, 0, 0),
			ZIndex = 2,
		})
	end

	return React.createElement("ImageButton", {
		Name = "MiniMapButton",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 60, 40),  -- Dark green terrain color
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ZIndex = 1,
		[React.Event.InputBegan] = function(rbx, input)
			self:onMinimapClick(rbx, input)
		end,
	}, {
		-- Grid lines for visual reference
		GridOverlay = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}, {
			-- Vertical center line
			VLine = React.createElement("Frame", {
				Size = UDim2.new(0, 1, 1, 0),
				Position = UDim2.fromScale(0.5, 0),
				BackgroundColor3 = Color3.fromRGB(100, 100, 100),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
			}),
			-- Horizontal center line
			HLine = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.fromScale(0, 0.5),
				BackgroundColor3 = Color3.fromRGB(100, 100, 100),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
			}),
		}),

		-- Unit dots layer
		Units = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, unitDotElements),

		-- Building icons layer
		Buildings = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, buildingIconElements),
	})
end

return MiniMap
