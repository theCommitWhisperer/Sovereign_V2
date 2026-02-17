--!strict
-- Enhanced Interactive minimap with alert pings, resource nodes, and strategic icons

local React = require(game.ReplicatedStorage.Packages.react)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

-- Remote function for checking visibility
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local CheckVisibility = RemoteEvents:WaitForChild("CheckVisibility")

local MiniMap = React.Component:extend("MiniMap")

-- Map constants
local MAP_SIZE = 1000 -- 1000x1000 stud map
local MINIMAP_SIZE = UIConfig.HUD.MinimapSize or 170

-- Strategic icons for different building types
local BUILDING_ICONS = {
	Keep = "🏰",
	Town_Center = "🏛️",
	Barracks = "⚔️",
	Farm = "🌾",
	Mine = "⛏️",
	Storehouse = "📦",
	Tower = "🗼",
	Wall = "🧱",
}

function MiniMap:init()
	self:setState({
		unitDots = {},
		buildingIcons = {},
		resourceNodes = {},
		alertPings = {}, -- {x, z, color, timestamp, message}
	})

	-- Update minimap every 0.5 seconds
	task.spawn(function()
		while true do
			task.wait(0.5)
			self:updateMinimapIndicators()
			self:cleanupOldPings()
		end
	end)

	-- Listen for alert pings from game events
	local GameEvent = RemoteEvents:WaitForChild("GameEvent")
	self.pingConnection = GameEvent.OnClientEvent:Connect(function(action, data)
		if action == "MinimapPing" then
			self:addAlertPing(data.position, data.color, data.message)
		elseif action == "BuildingUnderAttack" then
			-- Automatically ping when building is attacked
			if data.position then
				self:addAlertPing(data.position, Color3.fromRGB(255, 0, 0), "🔥 Under Attack!")
			end
		elseif action == "VikingRaidStarted" then
			-- Ping when Vikings spawn
			if data.spawnPosition then
				self:addAlertPing(data.spawnPosition, Color3.fromRGB(255, 100, 0), "⚠️ Vikings!")
			end
		end
	end)
end

function MiniMap:willUnmount()
	if self.pingConnection then
		self.pingConnection:Disconnect()
	end
end

function MiniMap:addAlertPing(worldPosition, color, message)
	-- Convert world position to minimap coordinates
	local minimapX = (worldPosition.X + MAP_SIZE / 2) / MAP_SIZE
	local minimapZ = (worldPosition.Z + MAP_SIZE / 2) / MAP_SIZE

	minimapX = math.clamp(minimapX, 0, 1)
	minimapZ = math.clamp(minimapZ, 0, 1)

	local pings = table.clone(self.state.alertPings)
	table.insert(pings, {
		x = minimapX,
		z = minimapZ,
		color = color or Color3.fromRGB(255, 255, 0),
		timestamp = os.clock(),
		message = message or "!",
	})

	self:setState({ alertPings = pings })
end

function MiniMap:cleanupOldPings()
	-- Remove pings older than 5 seconds
	local currentTime = os.clock()
	local pings = {}
	for _, ping in ipairs(self.state.alertPings) do
		if currentTime - ping.timestamp < 5 then
			table.insert(pings, ping)
		end
	end
	if #pings ~= #self.state.alertPings then
		self:setState({ alertPings = pings })
	end
end

function MiniMap:updateMinimapIndicators()
	local unitDots = {}
	local buildingIcons = {}
	local resourceNodes = {}

	-- Get units (with count aggregation for performance)
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		local unitClusters = {} -- Group nearby units
		for _, unit in unitsFolder:GetChildren() do
			if unit:IsA("Model") and unit.PrimaryPart then
				local isVisible = CheckVisibility:InvokeServer("Unit", unit)
				if isVisible then
					local owner = unit:GetAttribute("OwnerId")
					local pos = unit.PrimaryPart.Position

					local minimapX = (pos.X + MAP_SIZE / 2) / MAP_SIZE
					local minimapZ = (pos.Z + MAP_SIZE / 2) / MAP_SIZE

					minimapX = math.clamp(minimapX, 0, 1)
					minimapZ = math.clamp(minimapZ, 0, 1)

					-- Create cluster key (rounded to nearest 5% of map)
					local clusterKey = string.format("%.1f_%.1f_%s", math.floor(minimapX * 20) / 20, math.floor(minimapZ * 20) / 20, tostring(owner == player.UserId))

					if not unitClusters[clusterKey] then
						unitClusters[clusterKey] = {
							x = minimapX,
							z = minimapZ,
							isOwned = owner == player.UserId,
							count = 0,
						}
					end
					unitClusters[clusterKey].count = unitClusters[clusterKey].count + 1
				end
			end
		end

		-- Convert clusters to dots
		for _, cluster in pairs(unitClusters) do
			table.insert(unitDots, cluster)
		end
	end

	-- Get buildings with types
	local buildingsFolder = workspace:FindFirstChild("Buildings")
	if buildingsFolder then
		for _, building in buildingsFolder:GetChildren() do
			if building:IsA("Model") and building.PrimaryPart then
				local isVisible = CheckVisibility:InvokeServer("Building", building)
				if isVisible then
					local owner = building:GetAttribute("OwnerId")
					local buildingType = building:GetAttribute("BuildingType")
					local pos = building.PrimaryPart.Position

					local minimapX = (pos.X + MAP_SIZE / 2) / MAP_SIZE
					local minimapZ = (pos.Z + MAP_SIZE / 2) / MAP_SIZE

					minimapX = math.clamp(minimapX, 0, 1)
					minimapZ = math.clamp(minimapZ, 0, 1)

					-- Get health for color coding
					local health = building:GetAttribute("Health")
					local maxHealth = building:GetAttribute("MaxHealth")
					local healthPercent = if health and maxHealth and maxHealth > 0 then health / maxHealth else 1

					table.insert(buildingIcons, {
						x = minimapX,
						z = minimapZ,
						isOwned = owner == player.UserId,
						buildingType = buildingType,
						icon = BUILDING_ICONS[buildingType] or "🏗️",
						healthPercent = healthPercent,
					})
				end
			end
		end
	end

	-- Get resource nodes
	local resourceNodesFolder = workspace:FindFirstChild("ResourceNodes")
	if resourceNodesFolder then
		for _, node in resourceNodesFolder:GetChildren() do
			if node:IsA("Model") and node.PrimaryPart then
				local pos = node.PrimaryPart.Position
				local resourceType = node:GetAttribute("ResourceType")

				local minimapX = (pos.X + MAP_SIZE / 2) / MAP_SIZE
				local minimapZ = (pos.Z + MAP_SIZE / 2) / MAP_SIZE

				minimapX = math.clamp(minimapX, 0, 1)
				minimapZ = math.clamp(minimapZ, 0, 1)

				-- Resource icons
				local resourceIcon = "🌲" -- Default tree
				if resourceType == "Stone" then
					resourceIcon = "🪨"
				elseif resourceType == "Gold" then
					resourceIcon = "💰"
				elseif resourceType == "Iron" then
					resourceIcon = "⛏️"
				end

				table.insert(resourceNodes, {
					x = minimapX,
					z = minimapZ,
					icon = resourceIcon,
				})
			end
		end
	end

	self:setState({
		unitDots = unitDots,
		buildingIcons = buildingIcons,
		resourceNodes = resourceNodes,
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

	-- Check if click is within circular boundary
	local centerX = relativeX - 0.5
	local centerZ = relativeZ - 0.5
	local distanceFromCenter = math.sqrt(centerX * centerX + centerZ * centerZ)

	if distanceFromCenter > 0.5 then
		return
	end

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

	-- Play click sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/button.wav"
	sound.Volume = 0.3
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

function MiniMap:render()
	local unitDotElements = {}
	local buildingIconElements = {}
	local resourceNodeElements = {}
	local alertPingElements = {}

	-- Create unit dots with counts
	for i, unit in ipairs(self.state.unitDots) do
		local showCount = unit.count > 1
		unitDotElements[`Unit{i}`] = React.createElement("Frame", {
			Size = UDim2.new(0, showCount and 8 or 3, 0, showCount and 8 or 3),
			Position = UDim2.fromScale(unit.x, unit.z),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = unit.isOwned and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(255, 100, 100),
			BorderSizePixel = showCount and 1 or 0,
			BorderColor3 = Color3.fromRGB(0, 0, 0),
			ZIndex = 3,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Count = showCount and React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = tostring(unit.count),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 8,
				Font = Enum.Font.GothamBold,
				TextStrokeTransparency = 0.5,
				ZIndex = 4,
			}) or nil,
		})
	end

	-- Create building icons with health color coding
	for i, building in ipairs(self.state.buildingIcons) do
		local baseColor = building.isOwned and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 150, 150)

		-- Tint red if damaged
		if building.healthPercent < 0.5 then
			baseColor = Color3.fromRGB(255, 100, 100)
		elseif building.healthPercent < 0.75 then
			baseColor = Color3.fromRGB(255, 200, 100)
		end

		buildingIconElements[`Building{i}`] = React.createElement("Frame", {
			Size = UDim2.new(0, 8, 0, 8),
			Position = UDim2.fromScale(building.x, building.z),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = baseColor,
			BorderSizePixel = 1,
			BorderColor3 = Color3.fromRGB(0, 0, 0),
			ZIndex = 2,
		}, {
			-- Add icon as emoji
			Icon = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = building.icon,
				TextSize = 8,
				ZIndex = 3,
			}),
		})
	end

	-- Create resource node icons
	for i, node in ipairs(self.state.resourceNodes) do
		resourceNodeElements[`Resource{i}`] = React.createElement("TextLabel", {
			Size = UDim2.new(0, 6, 0, 6),
			Position = UDim2.fromScale(node.x, node.z),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Text = node.icon,
			TextSize = 6,
			ZIndex = 1,
		})
	end

	-- Create alert pings (animated)
	for i, ping in ipairs(self.state.alertPings) do
		local age = os.clock() - ping.timestamp
		local alpha = math.max(0, 1 - (age / 5)) -- Fade over 5 seconds
		local scale = 1 + (age * 0.5) -- Grow outward

		alertPingElements[`Ping{i}`] = React.createElement("Frame", {
			Size = UDim2.new(0, 12 * scale, 0, 12 * scale),
			Position = UDim2.fromScale(ping.x, ping.z),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = ping.color,
			BackgroundTransparency = 1 - (alpha * 0.3),
			BorderSizePixel = 2,
			BorderColor3 = ping.color,
			ZIndex = 5,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Message = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = ping.message,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 10,
				Font = Enum.Font.GothamBold,
				TextStrokeTransparency = 0,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				ZIndex = 6,
			}),
		})
	end

	return React.createElement("ImageButton", {
		Name = "MiniMapButton",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 60, 40),
		BackgroundTransparency = 1,
		Image = "",
		ScaleType = Enum.ScaleType.Stretch,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ZIndex = 1,
		[React.Event.InputBegan] = function(rbx, input)
			self:onMinimapClick(rbx, input)
		end,
	}, {
		-- Grid lines
		GridOverlay = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}, {
			VLine = React.createElement("Frame", {
				Size = UDim2.new(0, 1, 1, 0),
				Position = UDim2.fromScale(0.5, 0),
				BackgroundColor3 = Color3.fromRGB(100, 100, 100),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
			}),
			HLine = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.fromScale(0, 0.5),
				BackgroundColor3 = Color3.fromRGB(100, 100, 100),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
			}),
		}),

		-- Resource nodes layer (bottom)
		ResourceNodes = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}, resourceNodeElements),

		-- Building icons layer
		Buildings = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, buildingIconElements),

		-- Unit dots layer
		Units = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, unitDotElements),

		-- Alert pings layer (top)
		AlertPings = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, alertPingElements),
	})
end

return MiniMap
