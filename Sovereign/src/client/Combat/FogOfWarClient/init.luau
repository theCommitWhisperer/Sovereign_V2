--!strict
-- FogOfWarClient: Hides enemy units and buildings that are not in vision range

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Remote function for checking visibility
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local CheckVisibility = RemoteEvents:WaitForChild("CheckVisibility")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local FogClientDebug = DebugManager.createChannel("FogOfWarClient", true)  -- Enable debug

local FogOfWarClient = {}

-- Track visibility state of units/buildings
local lastVisibility: { [Model]: boolean } = {}
local hiddenModels: { [Model]: Folder } = {}  -- Store hidden models here

-- Create a folder to store hidden models
local HiddenFolder = Instance.new("Folder")
HiddenFolder.Name = "HiddenByFog"
HiddenFolder.Parent = ReplicatedStorage

-- Update visibility of units and buildings
local function updateVisibility()
	-- Update units
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		for _, unit in unitsFolder:GetChildren() do
			if unit:IsA("Model") and unit.PrimaryPart then
				local owner = unit:GetAttribute("Owner")

				-- Always show own units
				if owner == player.UserId then
					-- Make sure it's visible (restore from hidden if needed)
					if hiddenModels[unit] then
						unit.Parent = unitsFolder
						hiddenModels[unit] = nil
					end
				else
					-- Check if enemy unit is visible
					local success, isVisible = pcall(function()
						return CheckVisibility:InvokeServer("Unit", unit)
					end)

					if not success then
						FogClientDebug:warn(`Failed to check visibility for unit {unit.Name}: {isVisible}`)
						return
					end

					FogClientDebug:info(`Unit {unit.Name} visibility: {isVisible}`)

					-- Only update if visibility changed (to reduce lag)
					if lastVisibility[unit] ~= isVisible then
						lastVisibility[unit] = isVisible

						if isVisible then
							-- Restore from hidden folder
							if hiddenModels[unit] then
								unit.Parent = unitsFolder
								hiddenModels[unit] = nil
								FogClientDebug:info(`Unit revealed: {unit.Name}`)
							end
						else
							-- Hide in fog of war by moving to hidden folder
							if not hiddenModels[unit] then
								unit.Parent = HiddenFolder
								hiddenModels[unit] = HiddenFolder
								FogClientDebug:info(`Unit hidden: {unit.Name}`)
							end
						end
					end
				end
			end
		end
	end

	-- Also check hidden folder for units that might have become visible
	for _, unit in HiddenFolder:GetChildren() do
		if unit:IsA("Model") and unit:GetAttribute("UnitType") then
			local isVisible = CheckVisibility:InvokeServer("Unit", unit)
			if isVisible then
				unit.Parent = unitsFolder
				hiddenModels[unit] = nil
				FogClientDebug:info(`Hidden unit revealed: {unit.Name}`)
			end
		end
	end

	-- Update buildings
	local buildingsFolder = workspace:FindFirstChild("Buildings")
	if buildingsFolder then
		for _, building in buildingsFolder:GetChildren() do
			if building:IsA("Model") and building.PrimaryPart then
				local owner = building:GetAttribute("Owner")

				-- Always show own buildings
				if owner == player.UserId then
					-- Make sure it's visible
					if hiddenModels[building] then
						building.Parent = buildingsFolder
						hiddenModels[building] = nil
					end
				else
					-- Check if enemy building is visible
					local success, isVisible = pcall(function()
						return CheckVisibility:InvokeServer("Building", building)
					end)

					if not success then
						FogClientDebug:warn(`Failed to check visibility for building {building.Name}: {isVisible}`)
						return
					end

					FogClientDebug:info(`Building {building.Name} visibility: {isVisible}`)

					-- Only update if visibility changed
					if lastVisibility[building] ~= isVisible then
						lastVisibility[building] = isVisible

						if isVisible then
							-- Restore from hidden folder
							if hiddenModels[building] then
								building.Parent = buildingsFolder
								hiddenModels[building] = nil
								FogClientDebug:info(`Building revealed: {building.Name}`)
							end
						else
							-- Hide in fog of war
							if not hiddenModels[building] then
								building.Parent = HiddenFolder
								hiddenModels[building] = HiddenFolder
								FogClientDebug:info(`Building hidden: {building.Name}`)
							end
						end
					end
				end
			end
		end
	end

	-- Check hidden folder for buildings that might have become visible
	for _, building in HiddenFolder:GetChildren() do
		if building:IsA("Model") and building:GetAttribute("BuildingType") then
			local isVisible = CheckVisibility:InvokeServer("Building", building)
			if isVisible then
				building.Parent = buildingsFolder
				hiddenModels[building] = nil
				FogClientDebug:info(`Hidden building revealed: {building.Name}`)
			end
		end
	end

	-- Update resource nodes (trees, rocks, etc.)
	local resourceNodesFolder = workspace:FindFirstChild("ResourceNodes")
	if resourceNodesFolder then
		for _, node in resourceNodesFolder:GetChildren() do
			if node:IsA("Model") and node.PrimaryPart then
				-- Check if resource node is visible (fog of war)
				local success, isVisible = pcall(function()
					-- Resource nodes use same logic as buildings (position-based visibility)
					return CheckVisibility:InvokeServer("Building", node)
				end)

				if success then
					-- Only update if visibility changed
					if lastVisibility[node] ~= isVisible then
						lastVisibility[node] = isVisible

						if isVisible then
							-- Restore from hidden folder
							if hiddenModels[node] then
								node.Parent = resourceNodesFolder
								hiddenModels[node] = nil
								FogClientDebug:info(`Resource node revealed: {node.Name}`)
							end
						else
							-- Hide in fog of war
							if not hiddenModels[node] then
								node.Parent = HiddenFolder
								hiddenModels[node] = HiddenFolder
								FogClientDebug:info(`Resource node hidden: {node.Name}`)
							end
						end
					end
				end
			end
		end
	end

	-- Check hidden folder for resource nodes that might have become visible
	for _, node in HiddenFolder:GetChildren() do
		if node:IsA("Model") and node.Name:find("_Node") then
			local success, isVisible = pcall(function()
				return CheckVisibility:InvokeServer("Building", node)
			end)
			if success and isVisible then
				local resourceNodesFolder2 = workspace:FindFirstChild("ResourceNodes")
				if resourceNodesFolder2 then
					node.Parent = resourceNodesFolder2
					hiddenModels[node] = nil
					FogClientDebug:info(`Hidden resource node revealed: {node.Name}`)
				end
			end
		end
	end

	-- Clean up destroyed models from tracking
	for model, _ in lastVisibility do
		if not model or not model.Parent then
			lastVisibility[model] = nil
			hiddenModels[model] = nil
		end
	end
end

-- Listen for new objects being added and immediately check their visibility
local function setupObjectListeners()
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		unitsFolder.ChildAdded:Connect(function(unit)
			task.wait(0.1)  -- Small delay to ensure attributes are set
			if unit:IsA("Model") and unit.PrimaryPart then
				local owner = unit:GetAttribute("Owner")
				if owner ~= player.UserId then
					-- Immediately check and hide if not visible
					local success, isVisible = pcall(function()
						return CheckVisibility:InvokeServer("Unit", unit)
					end)
					if success and not isVisible then
						unit.Parent = HiddenFolder
						hiddenModels[unit] = HiddenFolder
						lastVisibility[unit] = false
						FogClientDebug:info(`New unit immediately hidden: {unit.Name}`)
					end
				end
			end
		end)
	end

	local buildingsFolder = workspace:FindFirstChild("Buildings")
	if buildingsFolder then
		buildingsFolder.ChildAdded:Connect(function(building)
			task.wait(0.1)  -- Small delay to ensure attributes are set
			if building:IsA("Model") and building.PrimaryPart then
				local owner = building:GetAttribute("Owner")
				if owner ~= player.UserId then
					-- Immediately check and hide if not visible
					local success, isVisible = pcall(function()
						return CheckVisibility:InvokeServer("Building", building)
					end)
					if success and not isVisible then
						building.Parent = HiddenFolder
						hiddenModels[building] = HiddenFolder
						lastVisibility[building] = false
						FogClientDebug:info(`New building immediately hidden: {building.Name}`)
					end
				end
			end
		end)
	end

	local resourceNodesFolder = workspace:FindFirstChild("ResourceNodes")
	if resourceNodesFolder then
		resourceNodesFolder.ChildAdded:Connect(function(node)
			task.wait(0.1)  -- Small delay to ensure attributes are set
			if node:IsA("Model") and node.PrimaryPart then
				-- Immediately check and hide if not visible
				local success, isVisible = pcall(function()
					return CheckVisibility:InvokeServer("Building", node)
				end)
				if success and not isVisible then
					node.Parent = HiddenFolder
					hiddenModels[node] = HiddenFolder
					lastVisibility[node] = false
					FogClientDebug:info(`New resource node immediately hidden: {node.Name}`)
				end
			end
		end)
	end
end

setupObjectListeners()

-- Update visibility every 0.5 seconds (same as server fog of war updates)
task.spawn(function()
	while true do
		task.wait(0.5)
		updateVisibility()
	end
end)

-- Create visual fog effect (darken the world slightly to show fog is active)
local function setupFogVisuals()
	local lighting = game:GetService("Lighting")

	-- Store original lighting settings
	local originalBrightness = lighting.Brightness
	local originalAmbient = lighting.Ambient
	local originalOutdoorAmbient = lighting.OutdoorAmbient

	-- Slightly darken the world to indicate fog of war is active
	lighting.Brightness = math.max(1, originalBrightness * 0.85)
	lighting.Ambient = Color3.new(
		originalAmbient.R * 0.8,
		originalAmbient.G * 0.8,
		originalAmbient.B * 0.9
	)

	-- Add a slight blue tint to fog of war
	lighting.OutdoorAmbient = Color3.new(
		originalOutdoorAmbient.R * 0.75,
		originalOutdoorAmbient.G * 0.75,
		originalOutdoorAmbient.B * 0.85
	)

	FogClientDebug:info("Applied fog of war visual effects to lighting")
end

setupFogVisuals()

FogClientDebug:info("FogOfWarClient initialized - enemy units/buildings will be hidden in fog of war")

return FogOfWarClient
