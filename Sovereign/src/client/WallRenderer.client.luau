--!strict
--[[
	WallRenderer - Mobile-optimized wall rendering with LOD (Client-side)

	Features:
	- Level of Detail (LOD) system based on distance from camera
	- Automatic draw call reduction
	- Mobile device detection and optimization
	- Streaming-friendly architecture

	LOD Levels:
	- High (0-80 studs): Full detail
	- Medium (80-200 studs): Simplified geometry
	- Low (200+ studs): Minimal rendering or culled
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local WallRenderer = {}

-- Detect if running on mobile device
local function isMobileDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- LOD configuration
local LOD_CONFIG = {
	-- Mobile devices use more aggressive LOD
	mobile = {
		highDetailDistance = 50,
		mediumDetailDistance = 120,
		lowDetailDistance = 250,
		updateInterval = 0.5, -- Update LOD twice per second
	},

	-- Desktop can handle more detail
	desktop = {
		highDetailDistance = 80,
		mediumDetailDistance = 200,
		lowDetailDistance = 400,
		updateInterval = 0.3, -- Update LOD ~3 times per second
	},
}

local isMobile = isMobileDevice()
local config = isMobile and LOD_CONFIG.mobile or LOD_CONFIG.desktop

print(string.format("[WallRenderer] Running on %s device", isMobile and "MOBILE" or "DESKTOP"))
print(string.format("[WallRenderer] LOD distances: High=%.0f, Medium=%.0f, Low=%.0f",
	config.highDetailDistance,
	config.mediumDetailDistance,
	config.lowDetailDistance))

-- Wall tracking
type WallLODData = {
	model: Model,
	currentLOD: string, -- "high" | "medium" | "low" | "culled"
	originalTransparency: { [BasePart]: number },
}

local trackedWalls: { [Model]: WallLODData } = {}
local buildingsFolder: Folder? = nil
local lastUpdateTime = 0

-- Initialize renderer
function WallRenderer.initialize()
	print("[WallRenderer] Initializing...")

	buildingsFolder = Workspace:WaitForChild("Buildings") :: Folder

	-- Track existing walls
	for _, child in buildingsFolder:GetChildren() do
		if child:IsA("Model") then
			local buildingType = child:GetAttribute("BuildingType")
			if buildingType and string.find(buildingType, "Wall") then
				WallRenderer._trackWall(child)
			end
		end
	end

	-- Listen for new walls
	buildingsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			local buildingType = child:GetAttribute("BuildingType")
			if buildingType and string.find(buildingType, "Wall") then
				WallRenderer._trackWall(child)
			end
		end
	end)

	-- Listen for removed walls
	buildingsFolder.ChildRemoved:Connect(function(child)
		if trackedWalls[child] then
			trackedWalls[child] = nil
		end
	end)

	print(string.format("[WallRenderer] Tracking %d walls", #trackedWalls))
end

-- Track a wall for LOD management
function WallRenderer._trackWall(wall: Model)
	if trackedWalls[wall] then
		return -- Already tracking
	end

	-- Store original transparency values
	local originalTransparency = {}
	for _, descendant in wall:GetDescendants() do
		if descendant:IsA("BasePart") then
			originalTransparency[descendant] = descendant.Transparency
		end
	end

	trackedWalls[wall] = {
		model = wall,
		currentLOD = "high",
		originalTransparency = originalTransparency,
	}
end

-- Apply LOD level to a wall
function WallRenderer._applyLOD(wallData: WallLODData, newLOD: string)
	if wallData.currentLOD == newLOD then
		return -- No change
	end

	local model = wallData.model

	if newLOD == "high" then
		-- Full detail - restore original transparency
		for part, originalTrans in wallData.originalTransparency do
			if part:IsDescendantOf(game) then
				part.Transparency = originalTrans
				part.CastShadow = true
			end
		end

	elseif newLOD == "medium" then
		-- Medium detail - reduce some visual elements
		for part, originalTrans in wallData.originalTransparency do
			if part:IsDescendantOf(game) then
				part.Transparency = originalTrans
				part.CastShadow = false -- Disable shadows for performance

				-- Hide small decorative parts
				if part.Size.Magnitude < 2 then
					part.Transparency = 1
				end
			end
		end

	elseif newLOD == "low" then
		-- Low detail - only show main structure
		for part, originalTrans in wallData.originalTransparency do
			if part:IsDescendantOf(game) then
				part.CastShadow = false

				-- Only show large structural parts
				if part.Size.Magnitude < 5 then
					part.Transparency = 1
				else
					part.Transparency = math.min(originalTrans + 0.3, 0.9)
				end
			end
		end

	elseif newLOD == "culled" then
		-- Completely hidden (beyond render distance)
		for part, _ in wallData.originalTransparency do
			if part:IsDescendantOf(game) then
				part.Transparency = 1
				part.CastShadow = false
			end
		end
	end

	wallData.currentLOD = newLOD
end

-- Update LOD for all walls based on camera distance
function WallRenderer._updateLOD()
	if not camera then
		return
	end

	local cameraPos = camera.CFrame.Position

	for model, wallData in trackedWalls do
		if not model:IsDescendantOf(game) then
			trackedWalls[model] = nil
			continue
		end

		-- Calculate distance from camera to wall
		local wallPos = model:GetPivot().Position
		local distance = (cameraPos - wallPos).Magnitude

		-- Determine LOD level
		local newLOD: string
		if distance < config.highDetailDistance then
			newLOD = "high"
		elseif distance < config.mediumDetailDistance then
			newLOD = "medium"
		elseif distance < config.lowDetailDistance then
			newLOD = "low"
		else
			newLOD = "culled"
		end

		-- Apply LOD
		WallRenderer._applyLOD(wallData, newLOD)
	end
end

-- Start LOD update loop
function WallRenderer.startLODUpdates()
	RunService.RenderStepped:Connect(function()
		local currentTime = tick()

		-- Only update at specified interval
		if currentTime - lastUpdateTime >= config.updateInterval then
			WallRenderer._updateLOD()
			lastUpdateTime = currentTime
		end
	end)

	print("[WallRenderer] LOD update loop started")
end

-- Get statistics
function WallRenderer.getStats(): { [string]: number }
	local stats = {
		totalWalls = 0,
		highLOD = 0,
		mediumLOD = 0,
		lowLOD = 0,
		culled = 0,
	}

	for _, wallData in trackedWalls do
		stats.totalWalls += 1

		if wallData.currentLOD == "high" then
			stats.highLOD += 1
		elseif wallData.currentLOD == "medium" then
			stats.mediumLOD += 1
		elseif wallData.currentLOD == "low" then
			stats.lowLOD += 1
		elseif wallData.currentLOD == "culled" then
			stats.culled += 1
		end
	end

	return stats
end

-- Debug: Print stats
function WallRenderer.printStats()
	local stats = WallRenderer.getStats()
	print(string.format(
		"[WallRenderer] Walls: %d total | High: %d | Medium: %d | Low: %d | Culled: %d",
		stats.totalWalls,
		stats.highLOD,
		stats.mediumLOD,
		stats.lowLOD,
		stats.culled
	))
end

-- Initialize automatically
WallRenderer.initialize()
WallRenderer.startLODUpdates()

return WallRenderer
