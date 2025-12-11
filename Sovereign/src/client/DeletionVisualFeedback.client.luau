--!strict
-- DeletionVisualFeedback: Handles visual feedback for delete mode
-- Shows which buildings/walls can be deleted with hover effects and cursor changes

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- State
local isDeleteModeActive = false
local hoveredBuilding: Model? = nil
local highlightAdornment: SelectionBox? = nil

-- Configuration
local HOVER_COLOR_DELETABLE = Color3.new(1, 0.2, 0.2) -- Red for deletable
local HOVER_COLOR_PROTECTED = Color3.new(0.8, 0.8, 0.2) -- Yellow for protected
local HIGHLIGHT_THICKNESS = 0.15

-- Helper Functions

local function findBuildingModelFromPart(part: BasePart): Model?
	local current: Instance? = part
	while current do
		if current:IsA("Model") then
			local bType = current:GetAttribute("BuildingType")
			local owner = current:GetAttribute("Owner")
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
	-- Protect Keep from deletion
	return buildingType == "Keep"
end

local function canDeleteBuilding(building: Model): boolean
	local owner = building:GetAttribute("Owner")
	return owner == player.UserId
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
end

local function clearHighlight()
	if highlightAdornment then
		highlightAdornment:Destroy()
		highlightAdornment = nil
	end
	hoveredBuilding = nil
end

local function updateMouseIcon()
	if isDeleteModeActive then
		-- Change cursor to indicate delete mode
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

	-- If we're hovering over the same building, no need to update
	if building == hoveredBuilding then
		return
	end

	clearHighlight()

	if building then
		-- Check if player owns this building
		if canDeleteBuilding(building) then
			hoveredBuilding = building

			-- Check if it's protected
			if isProtectedBuilding(building) then
				createHighlight(building, HOVER_COLOR_PROTECTED)
			else
				createHighlight(building, HOVER_COLOR_DELETABLE)
			end
		end
	end
end

-- Event Listeners

-- Listen for delete mode changes from HUD
local deleteModeEvent = ReplicatedStorage:FindFirstChild("DeleteModeChanged")
if not deleteModeEvent then
	deleteModeEvent = Instance.new("BindableEvent")
	deleteModeEvent.Name = "DeleteModeChanged"
	deleteModeEvent.Parent = ReplicatedStorage
end

deleteModeEvent.Event:Connect(function(isActive: boolean)
	isDeleteModeActive = isActive
	updateMouseIcon()
	if not isActive then
		clearHighlight()
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
end)

print("[DeletionController] Deletion visual feedback system initialized")

return {}
