--!strict
-- MapEditor: Main screen component for the in-game map editor
local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local EditorTopBar = require(script.Parent.EditorTopBar)
local EditorPropertyPanel = require(script.Parent.EditorPropertyPanel)

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MapEditorDebug = DebugManager.createChannel("MapEditorUI", false)

local MapEditor = React.Component:extend("MapEditor")

function MapEditor:init()
	MapEditorDebug:info("MapEditor:init()")

	self.state = {
		activeTool = "Select",
		mapName = "Untitled Map",
		mapSize = 1000,
		maxPlayers = 4,
		editorReady = false,
		statusText = "Initializing editor...",
	}

	-- Connect to MapEditorEvent
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local MapEditorEvent = RemoteEvents:WaitForChild("MapEditorEvent")

	self.editorConnection = MapEditorEvent.OnClientEvent:Connect(function(action, data)
		MapEditorDebug:info("Received MapEditorEvent:", action)

		if action == "EditorReady" then
			local mapData = data
			self:setState({
				editorReady = true,
				mapName = mapData.Name or "Untitled Map",
				mapSize = mapData.Size or 1000,
				maxPlayers = mapData.MaxPlayers or 4,
				statusText = "Ready - " .. (mapData.Name or "Untitled Map"),
			})
		elseif action == "TerrainUpdated" then
			self:setState({ statusText = "Terrain updated" })
		elseif action == "MapSaved" then
			if data.success then
				self:setState({ statusText = "Map saved!" })
			else
				self:setState({ statusText = "Save failed: " .. (data.error or "unknown") })
			end
		elseif action == "MapLoaded" then
			local mapData = data
			self:setState({
				mapName = mapData.Name,
				mapSize = mapData.Size,
				maxPlayers = mapData.MaxPlayers,
				statusText = "Loaded: " .. mapData.Name,
			})
		elseif action == "ExportResult" then
			self:setState({ statusText = "Exported! Check output console." })
			-- Print to output for copy-paste
			print("=== EXPORTED MAP CONFIG ===")
			print(data.luaCode)
			print("=== END EXPORT ===")
		elseif action == "MapList" then
			self:setState({ statusText = "Maps: " .. #data.maps .. " found" })
		end
	end)

	-- Tell server to enter editor
	MapEditorEvent:FireServer("EnterEditor")

	-- Store callbacks
	self.onToolSelected = function(toolId)
		self:setState({ activeTool = toolId })
		-- Sync active tool to player attributes so MapEditorController can read it
		localPlayer:SetAttribute("EditorActiveTool", toolId)
	end

	self.onBrushSettingsChanged = function(settings)
		-- Sync brush settings to player attributes for MapEditorController
		localPlayer:SetAttribute("EditorBrushRadius", settings.radius)
		localPlayer:SetAttribute("EditorBrushHeight", settings.height)
		localPlayer:SetAttribute("EditorBrushShape", settings.shape)
		localPlayer:SetAttribute("EditorBrushMaterial", settings.material)
	end

	self.onSave = function()
		local MapEditorEvent2 = RemoteEvents:FindFirstChild("MapEditorEvent")
		if MapEditorEvent2 then
			MapEditorEvent2:FireServer("SaveMap")
		end
	end

	self.onLoad = function()
		local MapEditorEvent2 = RemoteEvents:FindFirstChild("MapEditorEvent")
		if MapEditorEvent2 then
			MapEditorEvent2:FireServer("ListMaps")
		end
	end

	self.onExport = function()
		local MapEditorEvent2 = RemoteEvents:FindFirstChild("MapEditorEvent")
		if MapEditorEvent2 then
			MapEditorEvent2:FireServer("ExportMap")
		end
	end

	self.onBack = function()
		-- Tell server to leave editor
		local MapEditorEvent2 = RemoteEvents:FindFirstChild("MapEditorEvent")
		if MapEditorEvent2 then
			MapEditorEvent2:FireServer("LeaveEditor")
		end
		-- Navigate back to main menu
		if self.props.navigate then
			self.props.navigate("mainMenu")
		end
	end
end

function MapEditor:willUnmount()
	if self.editorConnection then
		self.editorConnection:Disconnect()
	end

	-- Tell server to leave editor if we navigate away
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local MapEditorEvent = RemoteEvents:FindFirstChild("MapEditorEvent")
		if MapEditorEvent then
			MapEditorEvent:FireServer("LeaveEditor")
		end
	end
end

function MapEditor:render()
	return React.createElement("ScreenGui", {
		Name = "MapEditorGui",
		ClipToDeviceSafeArea = true,
		DisplayOrder = 5,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		-- Top Bar (includes tools, map info, and file actions)
		TopBar = React.createElement(EditorTopBar, {
			mapName = self.state.mapName,
			mapSize = self.state.mapSize,
			maxPlayers = self.state.maxPlayers,
			activeTool = self.state.activeTool,
			onToolSelected = self.onToolSelected,
			onSave = self.onSave,
			onLoad = self.onLoad,
			onExport = self.onExport,
			onBack = self.onBack,
		}),

		-- Left Property Panel (below top bar)
		PropertyPanel = React.createElement(EditorPropertyPanel, {
			activeTool = self.state.activeTool,
			onBrushSettingsChanged = self.onBrushSettingsChanged,
		}),

		-- Status bar at the bottom
		StatusBar = React.createElement("Frame", {
			Name = "StatusBar",
			Size = UDim2.new(1, 0, 0, 28),
			Position = UDim2.new(0, 0, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = UIConfig.HUD.TopBarBackground,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ZIndex = 10,
		}, {
			UIStroke = React.createElement("UIStroke", {
				Color = UIConfig.HUD.StrokeColor,
				Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			UIPadding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 14),
			}),
			StatusText = React.createElement("TextLabel", {
				Size = UDim2.new(0.5, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = self.state.statusText,
				FontFace = UIConfig.Font.Default,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			ControlsHint = React.createElement("TextLabel", {
				Size = UDim2.new(0.5, 0, 1, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				BackgroundTransparency = 1,
				Text = "LMB: Paint | MMB: Pan | Scroll: Zoom",
				FontFace = UIConfig.Font.Default,
				TextColor3 = UIConfig.HUD.StrokeColor,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),
	})
end

return MapEditor
