--!strict
-- DeletionInputHandler: Handles single-click and drag-to-select deletion
-- Processes mouse input for deleting buildings and walls (both single and multi-delete)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

-- State
local isDeleteModeActive = false
local isDragging = false
local dragStartPosition: Vector2? = nil
local selectionBox: Frame? = nil
local selectedBuildings: { Model } = {}

-- Configuration
local MIN_DRAG_DISTANCE = 10 -- Minimum pixels to count as a drag vs click

-- Helper Functions

local function findBuildingModelFromPart(part: BasePart): Model?
	local current: Instance? = part
	while current do
		if current:IsA("Model") then
			local bType = current:GetAttribute("BuildingType")
			local owner = current:GetAttribute("Owner")
			-- Also check for wall pieces
			local isWall = current:FindFirstChild("PlacedPiece")
			if (bType ~= nil and owner ~= nil) or isWall then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function canDeleteBuilding(building: Model): boolean
	local owner = building:GetAttribute("Owner")
	return owner == player.UserId
end

local function isProtectedBuilding(building: Model): boolean
	local buildingType = building:GetAttribute("BuildingType")
	return buildingType == "Keep"
end

local function createSelectionBox(): Frame
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DragDeleteSelection"
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	local box = Instance.new("Frame")
	box.Name = "SelectionBox"
	box.BackgroundColor3 = Color3.new(1, 0.2, 0.2)
	box.BackgroundTransparency = 0.7
	box.BorderSizePixel = 2
	box.BorderColor3 = Color3.new(1, 0, 0)
	box.ZIndex = 999
	box.Parent = screenGui

	return box
end

local function updateSelectionBox(startPos: Vector2, currentPos: Vector2)
	if not selectionBox then
		return
	end

	local minX = math.min(startPos.X, currentPos.X)
	local minY = math.min(startPos.Y, currentPos.Y)
	local maxX = math.max(startPos.X, currentPos.X)
	local maxY = math.max(startPos.Y, currentPos.Y)

	selectionBox.Position = UDim2.fromOffset(minX, minY)
	selectionBox.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
end

local function clearSelectionBox()
	if selectionBox then
		if selectionBox.Parent then
			selectionBox.Parent:Destroy()
		end
		selectionBox = nil
	end
end

local function getBuildingsInScreenBox(topLeft: Vector2, bottomRight: Vector2): { Model }
	local buildings: { Model } = {}

	-- Get GUI inset to convert between coordinate systems
	-- Mouse position includes GUI inset, WorldToScreenPoint doesn't
	local guiInset = game:GetService("GuiService"):GetGuiInset()

	-- Search in both Buildings and PlacedWalls folders
	local foldersToSearch = {}
	local buildingsFolder = workspace:FindFirstChild("Buildings")
	local wallsFolder = workspace:FindFirstChild("PlacedWalls")

	if buildingsFolder then
		table.insert(foldersToSearch, buildingsFolder)
	end
	if wallsFolder then
		table.insert(foldersToSearch, wallsFolder)
	end

	if #foldersToSearch == 0 then
		print("[DeletionInputHandler] No Buildings or PlacedWalls folder found")
		return buildings
	end

	-- Get all building models from all folders
	for _, folder in foldersToSearch do
		for _, obj in folder:GetDescendants() do
			if obj:IsA("Model") then
				local building = findBuildingModelFromPart(obj)
				if building and canDeleteBuilding(building) and not isProtectedBuilding(building) then
					-- Check if any part of the building is within the selection box
					local shouldSelect = false

					-- Get building bounds
					local cframe, size = building:GetBoundingBox()

					-- Check 8 corners of the bounding box
					local corners = {
						cframe * CFrame.new(size.X/2, size.Y/2, size.Z/2),
						cframe * CFrame.new(-size.X/2, size.Y/2, size.Z/2),
						cframe * CFrame.new(size.X/2, -size.Y/2, size.Z/2),
						cframe * CFrame.new(-size.X/2, -size.Y/2, size.Z/2),
						cframe * CFrame.new(size.X/2, size.Y/2, -size.Z/2),
						cframe * CFrame.new(-size.X/2, size.Y/2, -size.Z/2),
						cframe * CFrame.new(size.X/2, -size.Y/2, -size.Z/2),
						cframe * CFrame.new(-size.X/2, -size.Y/2, -size.Z/2),
					}

					-- Check if any corner is in the selection box
					for _, cornerCFrame in corners do
						local screenPos, onScreen = camera:WorldToScreenPoint(cornerCFrame.Position)
						if onScreen then
							local screenPos2D = Vector2.new(screenPos.X, screenPos.Y) + Vector2.new(guiInset.X, guiInset.Y)
							if
								screenPos2D.X >= topLeft.X
								and screenPos2D.X <= bottomRight.X
								and screenPos2D.Y >= topLeft.Y
								and screenPos2D.Y <= bottomRight.Y
							then
								shouldSelect = true
								break
							end
						end
					end

					if shouldSelect then
						-- Make sure we don't add duplicates
						local alreadyAdded = false
						for _, b in buildings do
							if b == building then
								alreadyAdded = true
								break
							end
						end
						if not alreadyAdded then
							table.insert(buildings, building)
						end
					end
				end
			end
		end
	end

	print(string.format("[DeletionInputHandler] Found %d buildings in selection box", #buildings))
	return buildings
end

local function fireMultiDeleteEvent()
	if #selectedBuildings == 0 then
		return
	end

	-- Fire event to HUD to show confirmation dialog
	local multiDeleteEvent = ReplicatedStorage:FindFirstChild("MultiDeleteRequested")
	if not multiDeleteEvent then
		multiDeleteEvent = Instance.new("BindableEvent")
		multiDeleteEvent.Name = "MultiDeleteRequested"
		multiDeleteEvent.Parent = ReplicatedStorage
	end

	multiDeleteEvent:Fire(selectedBuildings)
	selectedBuildings = {}
end

-- Input Handling

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not isDeleteModeActive then
		return
	end

	if gameProcessed then
		print("[DeletionInputHandler] Input was game processed, ignoring")
		return
	end

	-- Start drag selection on left mouse button down
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragStartPosition = UserInputService:GetMouseLocation()
		isDragging = false -- Wait to see if it's a drag or click
		print("[DeletionInputHandler] Mouse down at", dragStartPosition)
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not isDeleteModeActive or not dragStartPosition then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local currentPos = UserInputService:GetMouseLocation()
		local distance = (currentPos - dragStartPosition).Magnitude

		-- Only start visual drag after minimum distance
		if distance > MIN_DRAG_DISTANCE then
			if not isDragging then
				isDragging = true
				selectionBox = createSelectionBox()
				print("[DeletionInputHandler] Started dragging, distance:", distance)
			end

			if isDragging and selectionBox then
				updateSelectionBox(dragStartPosition, currentPos)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if not isDeleteModeActive then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		print("[DeletionInputHandler] Mouse released. isDragging:", isDragging, "dragStartPosition:", dragStartPosition)

		if isDragging and dragStartPosition then
			-- Complete drag selection
			local endPos = UserInputService:GetMouseLocation()
			local topLeft = Vector2.new(
				math.min(dragStartPosition.X, endPos.X),
				math.min(dragStartPosition.Y, endPos.Y)
			)
			local bottomRight = Vector2.new(
				math.max(dragStartPosition.X, endPos.X),
				math.max(dragStartPosition.Y, endPos.Y)
			)

			print(string.format("[DeletionInputHandler] Selection box: (%d,%d) to (%d,%d)",
				topLeft.X, topLeft.Y, bottomRight.X, bottomRight.Y))

			selectedBuildings = getBuildingsInScreenBox(topLeft, bottomRight)

			if #selectedBuildings > 0 then
				print(string.format("[DeletionInputHandler] Selected %d buildings for deletion", #selectedBuildings))
				fireMultiDeleteEvent()
			else
				print("[DeletionInputHandler] No buildings found in selection")
			end
		elseif dragStartPosition and not isDragging then
			-- Single click - use mouse.Target to find clicked building
			print("[DeletionInputHandler] Single click detected, checking mouse target")
			local mouse = player:GetMouse()
			local target = mouse.Target

			if target then
				print("[DeletionInputHandler] Mouse target:", target.Name, "ClassName:", target.ClassName)
				local building = findBuildingModelFromPart(target)

				if building then
					print("[DeletionInputHandler] Found building model:", building.Name)
					print("[DeletionInputHandler] Can delete?", canDeleteBuilding(building))
					print("[DeletionInputHandler] Is protected?", isProtectedBuilding(building))
				else
					print("[DeletionInputHandler] No building model found from hit part")
				end

				if building and canDeleteBuilding(building) and not isProtectedBuilding(building) then
					print("[DeletionInputHandler] Found valid building for single deletion:", building.Name)
					-- Fire single-building delete event
					selectedBuildings = { building }
					fireMultiDeleteEvent()
				else
					print("[DeletionInputHandler] Building not valid for deletion")
				end
			else
				print("[DeletionInputHandler] No mouse target found")
			end
		end

		-- Reset drag state
		clearSelectionBox()
		isDragging = false
		dragStartPosition = nil
	end
end)

-- Listen for delete mode changes
local deleteModeEvent = ReplicatedStorage:FindFirstChild("DeleteModeChanged")
if not deleteModeEvent then
	deleteModeEvent = Instance.new("BindableEvent")
	deleteModeEvent.Name = "DeleteModeChanged"
	deleteModeEvent.Parent = ReplicatedStorage
end

deleteModeEvent.Event:Connect(function(isActive: boolean)
	isDeleteModeActive = isActive
	if not isActive then
		clearSelectionBox()
		isDragging = false
		dragStartPosition = nil
		selectedBuildings = {}
	end
end)

print("[DeletionInputHandler] Drag-to-delete system initialized")

return {}
