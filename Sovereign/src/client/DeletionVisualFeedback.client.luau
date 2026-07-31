--!strict
-- DeletionVisualFeedback: Handles visual feedback for delete mode.
-- Highlights ALL player-owned buildings in a red hue when delete mode is active,
-- and brightens hovered buildings for precise demolition feedback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- State
local isDeleteModeActive = false
local hoveredBuilding: Model? = nil
local highlightAdornment: SelectionBox? = nil
local activeGlobalHighlights: { [Model]: Highlight } = {}

-- Configuration
local HOVER_COLOR_DELETABLE = Color3.new(1, 0.2, 0.2) -- Red for deletable
local HOVER_COLOR_PROTECTED = Color3.new(0.8, 0.8, 0.2) -- Yellow for protected
local HIGHLIGHT_THICKNESS = 0.18

-- Helper Functions

local function findBuildingModelFromPart(part: BasePart): Model?
	local current: Instance? = part
	while current do
		if current:IsA("Model") then
			local bType = current:GetAttribute("BuildingType")
			local owner = current:GetAttribute("OwnerId")
			if bType ~= nil and owner ~= nil then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function isProtectedBuilding(building: Model): boolean
	local buildingType = building:GetAttribute("BuildingType")
	return buildingType == "Keep"
end

local function canDeleteBuilding(building: Model): boolean
	local owner = building:GetAttribute("OwnerId")
	return owner == player.UserId
end

local function highlightAllOwnedBuildings()
	-- Clear old global highlights
	for building, hl in pairs(activeGlobalHighlights) do
		if hl then
			hl:Destroy()
		end
	end
	table.clear(activeGlobalHighlights)

	-- Highlight all player-owned buildings in workspace in a red hue
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") then
			local owner = inst:GetAttribute("OwnerId")
			if owner == player.UserId then
				local hl = Instance.new("Highlight")
				hl.Name = "DeleteModeHue"
				hl.Adornee = inst
				hl.FillColor = Color3.fromRGB(220, 50, 50)
				hl.FillTransparency = 0.7
				hl.OutlineColor = Color3.fromRGB(255, 100, 100)
				hl.OutlineTransparency = 0.2
				hl.Parent = inst
				activeGlobalHighlights[inst] = hl
			end
		end
	end
end

local function clearAllGlobalHighlights()
	for _, hl in pairs(activeGlobalHighlights) do
		if hl then
			hl:Destroy()
		end
	end
	table.clear(activeGlobalHighlights)
end

local function createHighlight(building: Model, color: Color3)
	if highlightAdornment then
		highlightAdornment:Destroy()
	end

	highlightAdornment = Instance.new("SelectionBox")
	highlightAdornment.LineThickness = HIGHLIGHT_THICKNESS
	highlightAdornment.Color3 = color
	highlightAdornment.Adornee = building
	highlightAdornment.Parent = building

	-- Brighten global red hue on hover
	local hl = activeGlobalHighlights[building]
	if hl then
		hl.FillTransparency = 0.3
		hl.OutlineColor = Color3.fromRGB(255, 230, 0)
	end
end

local function clearHighlight()
	if hoveredBuilding and activeGlobalHighlights[hoveredBuilding] then
		local hl = activeGlobalHighlights[hoveredBuilding]
		hl.FillTransparency = 0.7
		hl.OutlineColor = Color3.fromRGB(255, 100, 100)
	end
	if highlightAdornment then
		highlightAdornment:Destroy()
		highlightAdornment = nil
	end
	hoveredBuilding = nil
end

local function updateMouseIcon()
	if isDeleteModeActive then
		mouse.Icon = "rbxasset://SystemCursors/Cross"
	else
		mouse.Icon = ""
	end
end

-- Main Update Loop
local function updateHoverEffect()
	if not isDeleteModeActive then
		clearHighlight()
		return
	end

	local target = mouse.Target
	if not target or not target:IsA("BasePart") then
		clearHighlight()
		return
	end

	local building = findBuildingModelFromPart(target)

	if building == hoveredBuilding then
		return
	end

	clearHighlight()

	if building then
		if canDeleteBuilding(building) then
			hoveredBuilding = building
			if isProtectedBuilding(building) then
				createHighlight(building, HOVER_COLOR_PROTECTED)
			else
				createHighlight(building, HOVER_COLOR_DELETABLE)
			end
		end
	end
end

-- Event Listeners
local deleteModeEvent = ReplicatedStorage:FindFirstChild("DeleteModeChanged")
if not deleteModeEvent then
	deleteModeEvent = Instance.new("BindableEvent")
	deleteModeEvent.Name = "DeleteModeChanged"
	deleteModeEvent.Parent = ReplicatedStorage
end

deleteModeEvent.Event:Connect(function(isActive: boolean)
	isDeleteModeActive = isActive
	updateMouseIcon()
	if isActive then
		highlightAllOwnedBuildings()
	else
		clearHighlight()
		clearAllGlobalHighlights()
	end
end)

-- Update hover effect every frame when delete mode is active
game:GetService("RunService").RenderStepped:Connect(function()
	if isDeleteModeActive then
		updateHoverEffect()
	end
end)

-- Cleanup on player leaving
player.AncestryChanged:Connect(function()
	clearHighlight()
	clearAllGlobalHighlights()
end)

return {}
