local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local ResourceDisplay = require(script.Parent.ResourceDisplay)
local BuildingMenu = require(script.Parent.BuildingMenu)

local HUD = React.Component:extend("HUD")

function HUD:init()
	print("[HUD] Initializing...")

	self:setState({
		resources = {
			Wood = 0,
			Stone = 0,
			Gold = 0,
			Food = 0,
			Weapons = 0,
			Iron_Bars = 0,
		},
		isPlacingBuilding = false,
		selectedBuilding = nil,
	})

	-- Get game event reference
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	self.gameEvent = RemoteEvents:WaitForChild("GameEvent")

	self.connection = self.gameEvent.OnClientEvent:Connect(function(action, data)
		if action == "GameStarted" and data.resources then
			print("[HUD] Received resources:", data.resources)
			self:setState({ resources = data.resources })
		elseif action == "UpdateResources" and data.resources then
			print("[HUD] Resources updated:", data.resources)
			self:setState({ resources = data.resources })
		elseif action == "StartPlacement" and typeof(data) == "string" then
			print("[HUD] Server approved placement for:", data)
			-- The PlacementController will handle this
		end
	end)
end

function HUD:willUnmount()
	if self.connection then
		self.connection:Disconnect()
	end
end

function HUD:render()
	print("[HUD] Rendering with resources:", self.state.resources)

	return React.createElement("ScreenGui", {
		Name = "HUDGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	}, {
		-- Top Bar for Resources
		TopBar = React.createElement("Frame", {
			Name = "TopBar",
			Size = UDim2.new(1, 0, 0, 60),
			Position = UDim2.fromScale(0, 0),
			BackgroundColor3 = Color3.fromRGB(40, 40, 45),
			BorderSizePixel = 0,
		}, {
			ResourceDisplay = React.createElement(ResourceDisplay, {
				resources = self.state.resources,
			}),
		}),

		-- Bottom Bar with Building Menu
		BottomBar = React.createElement("Frame", {
			Name = "BottomBar",
			Size = UDim2.new(1, 0, 0, 200),
			Position = UDim2.new(0, 0, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Color3.fromRGB(40, 40, 45),
			BorderSizePixel = 0,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),

			BuildingMenu = React.createElement(BuildingMenu, {
				resources = self.state.resources,
				onBuildingSelected = function(buildingName)
					print("[HUD] Building selected:", buildingName)
					self:setState({
						isPlacingBuilding = true,
						selectedBuilding = buildingName,
					})

					-- Request placement from server
					self.gameEvent:FireServer("StartPlacement", buildingName)
				end,
			}),
		}),

		-- Mini-map Placeholder (Bottom Right)
		MiniMapFrame = React.createElement("Frame", {
			Name = "MiniMapFrame",
			Size = UDim2.new(0, 200, 0, 200),
			Position = UDim2.new(1, -10, 1, -210),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundColor3 = Color3.fromRGB(30, 30, 35),
			BorderColor3 = Color3.fromRGB(100, 100, 100),
			BorderSizePixel = 2,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "Mini Map\n(Coming Soon)",
				Font = Enum.Font.Gotham,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(150, 150, 150),
			}),
		}),
	})
end

return HUD
