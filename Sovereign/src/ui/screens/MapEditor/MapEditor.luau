--!strict
-- MapEditor: Main screen component for the in-game map editor
local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local EditorTopBar = require(script.Parent.EditorTopBar)
local EditorPropertyPanel = require(script.Parent.EditorPropertyPanel)
local LoadMapModal = require(script.Parent.LoadMapModal)

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MapEditorDebug = DebugManager.createChannel("MapEditorUI", false)

-- ── Budget attribute helpers ────────────────────────────────────────────────
-- Encode { [key]: number } → "k1:v1,k2:v2"
local function encodeBudgetTargets(t: { [any]: number }): string
	local parts = {}
	for k, v in pairs(t) do
		table.insert(parts, tostring(k) .. ":" .. tostring(math.floor(v + 0.5)))
	end
	return table.concat(parts, ",")
end

-- Encode { [key]: boolean } → "k1:1,k2:0"
local function encodeBudgetLocked(t: { [any]: boolean }): string
	local parts = {}
	for k, v in pairs(t) do
		table.insert(parts, tostring(k) .. ":" .. (if v then "1" else "0"))
	end
	return table.concat(parts, ",")
end

-- Default zone targets/locked for a given mode
local function zoneDefaultTargets(mode: string): { [number]: number }
	local n = 5  -- 0..4
	local each = math.floor(100 / n)
	local t: { [number]: number } = {}
	for i = 0, 4 do t[i] = each end
	return t
end

local function zoneDefaultLocked(mode: string): { [number]: boolean }
	local l: { [number]: boolean } = {}
	for i = 0, 4 do l[i] = (mode == "Equal") end
	return l
end

-- ─────────────────────────────────────────────────────────────────────────────

local MapEditor = React.Component:extend("MapEditor")

function MapEditor:init()
	MapEditorDebug:info("MapEditor:init()")

	self.state = {
		activeTool = "Select",
		mapName = "Untitled Map",
		mapSize = 1000,
		maxPlayers = 4,
		description = "",
		neutralZoneWidth = 100,
		resourceDensity = { Wood = 20, Stone = 15, Food = 10, Iron_Ore = 8 },
		editorReady = false,
		statusText = "Initializing editor...",
		showLoadModal = false,
		loadedMaps = {},
		screenshotMode = false,
		-- Zone paint areas
		zoneAreas = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
		-- Zone budget (per-row lockable)
		zoneBudgetMode = "Equal",   -- "Freeform"|"Equal"|"Custom"
		zoneBudgetTargets = zoneDefaultTargets("Equal"),
		zoneBudgetLocked  = zoneDefaultLocked("Equal"),
		-- Polygon mode
		zoneMode = "Brush",
		polygonClosed = false,
		polygonNodeCount = 0,
		-- Resource tool
		selectedResourceZone = 0,   -- zone tab (0=Neutral, 1-4=P1-P4)
		resourceAreas = nil :: ({ [string]: number }?),
		resourceBudgetMode = "Equal",
		resourceBudgetTargets = {} :: { [string]: number },
		resourceBudgetLocked  = {} :: { [string]: boolean },
		-- Overlay visibility
		zoneOverlayOn = false,
		resourceOverlayOn = false,
	}

	-- Connect to MapEditorEvent
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local MapEditorEvent = RemoteEvents:WaitForChild("MapEditorEvent")
	self.mapEditorEvent = MapEditorEvent

	self.editorConnection = MapEditorEvent.OnClientEvent:Connect(function(action, data)
		MapEditorDebug:info("Received MapEditorEvent:", action)

		if action == "EditorReady" then
			local mapData = data
			self:setState({
				editorReady = true,
				mapName = mapData.Name or "Untitled Map",
				mapSize = mapData.Size or 1000,
				maxPlayers = mapData.MaxPlayers or 4,
				description = mapData.Description or "",
				neutralZoneWidth = mapData.NeutralZoneWidth or 100,
				resourceDensity = mapData.ResourceDensity or { Wood = 20, Stone = 15, Food = 10, Iron_Ore = 8 },
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
				description = mapData.Description or "",
				neutralZoneWidth = mapData.NeutralZoneWidth or 100,
				resourceDensity = mapData.ResourceDensity or { Wood = 20, Stone = 15, Food = 10, Iron_Ore = 8 },
				statusText = "Loaded: " .. mapData.Name,
				showLoadModal = false,
			})
		elseif action == "ZoneStats" then
			-- Controller handles ZoneStats and writes EditorZoneAreas attribute;
			-- the attribute watcher below updates state.
		elseif action == "PolygonCommitted" then
			self:setState({ polygonClosed = false, polygonNodeCount = 0, statusText = "Polygon zone committed." })
		elseif action == "KeepSpawnUpdated" then
			local zone = data and data.Zone or 0
			self:setState({ statusText = "P" .. zone .. " spawn zone placed." })
		elseif action == "SpawnPlacementRejected" then
			local reason = data and data.Reason or "Must place spawn within the correct player territory."
			self:setState({ statusText = "⚠ " .. reason })
		elseif action == "CustomMapActivated" then
			self:setState({ statusText = "Map activated for game! Join lobby to play it." })
		elseif action == "ExportResult" then
			-- Full output is printed server-side (check the Server output tab in Studio)
			self:setState({ statusText = "Exported! Check the SERVER output tab in Studio." })
		elseif action == "MapList" then
			self:setState({
				loadedMaps = data.maps or {},
				showLoadModal = true,
				statusText = "Choose a map to load",
			})
		end
	end)

	-- Tell server to enter editor
	MapEditorEvent:FireServer("EnterEditor")

	-- Store callbacks
	self.onToolSelected = function(toolId)
		self:setState({ activeTool = toolId })
		localPlayer:SetAttribute("EditorActiveTool", toolId)
	end

	self.onNameChanged = function(newName: string)
		self:setState({ mapName = newName })
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("UpdateMapSettings", { name = newName })
		end
	end

	self.onMapSettingsChanged = function(settings: { [string]: any })
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("UpdateMapSettings", settings)
		end
		local stateUpdate: { [string]: any } = {}
		if settings.maxPlayers then stateUpdate.maxPlayers = settings.maxPlayers end
		if settings.size then stateUpdate.mapSize = settings.size end
		if settings.description then stateUpdate.description = settings.description end
		if settings.neutralZoneWidth then stateUpdate.neutralZoneWidth = settings.neutralZoneWidth end
		if settings.resourceDensity then stateUpdate.resourceDensity = settings.resourceDensity end
		if next(stateUpdate) then
			self:setState(stateUpdate)
		end
	end

	-- ── Zone budget callbacks ───────────────────────────────────────────────
	local function pushZoneBudget(mode: string, targets: { [number]: number }, locked: { [number]: boolean })
		localPlayer:SetAttribute("EditorZoneBudgetMode", mode)
		localPlayer:SetAttribute("EditorZoneBudgetTargets", encodeBudgetTargets(targets))
		localPlayer:SetAttribute("EditorZoneBudgetLocked", encodeBudgetLocked(locked))
	end

	self.onZoneBudgetModeChanged = function(mode: string)
		local newTargets = zoneDefaultTargets(mode)
		local newLocked  = zoneDefaultLocked(mode)
		if mode == "Custom" then
			-- Keep existing targets, just unlock all by default
			newTargets = self.state.zoneBudgetTargets
			for i = 0, 4 do newLocked[i] = false end
		end
		self:setState({ zoneBudgetMode = mode, zoneBudgetTargets = newTargets, zoneBudgetLocked = newLocked })
		pushZoneBudget(mode, newTargets, newLocked)
	end

	self.onZoneBudgetTargetChanged = function(id: number, pct: number)
		local newTargets = {}
		for k, v in pairs(self.state.zoneBudgetTargets) do newTargets[k] = v end
		newTargets[id] = pct
		self:setState({ zoneBudgetTargets = newTargets })
		pushZoneBudget(self.state.zoneBudgetMode, newTargets, self.state.zoneBudgetLocked)
	end

	self.onZoneBudgetLockedChanged = function(id: number, locked: boolean)
		local newLocked = {}
		for k, v in pairs(self.state.zoneBudgetLocked) do newLocked[k] = v end
		newLocked[id] = locked
		self:setState({ zoneBudgetLocked = newLocked })
		pushZoneBudget(self.state.zoneBudgetMode, self.state.zoneBudgetTargets, newLocked)
	end

	-- Push initial zone budget attributes
	pushZoneBudget(self.state.zoneBudgetMode, self.state.zoneBudgetTargets, self.state.zoneBudgetLocked)

	-- ── Resource budget callbacks ───────────────────────────────────────────
	local RESOURCE_TYPES = { "Wood", "Stone", "Food", "Iron_Ore" }
	local ZONE_IDS = { 0, 1, 2, 3, 4 }

	local function allResourceKeys(): { string }
		local keys = {}
		for _, z in ipairs(ZONE_IDS) do
			for _, r in ipairs(RESOURCE_TYPES) do
				table.insert(keys, tostring(z) .. "_" .. r)
			end
		end
		return keys
	end

	local function resourceDefaultTargets(mode: string): { [string]: number }
		local keys = allResourceKeys()
		local each = math.floor(100 / #keys)
		local t: { [string]: number } = {}
		for _, k in ipairs(keys) do t[k] = each end
		return t
	end

	local function resourceDefaultLocked(mode: string): { [string]: boolean }
		local keys = allResourceKeys()
		local l: { [string]: boolean } = {}
		for _, k in ipairs(keys) do l[k] = (mode == "Equal") end
		return l
	end

	local function pushResourceBudget(mode: string, targets: { [string]: number }, locked: { [string]: boolean })
		localPlayer:SetAttribute("EditorResourceBudgetMode", mode)
		localPlayer:SetAttribute("EditorResourceBudgetTargets", encodeBudgetTargets(targets))
		localPlayer:SetAttribute("EditorResourceBudgetLocked", encodeBudgetLocked(locked))
	end

	self.onResourceZoneChanged = function(zoneId: number)
		self:setState({ selectedResourceZone = zoneId })
		localPlayer:SetAttribute("EditorResourceZoneOwner", zoneId)
	end

	self.onResourceBudgetModeChanged = function(mode: string)
		local newTargets = resourceDefaultTargets(mode)
		local newLocked  = resourceDefaultLocked(mode)
		if mode == "Custom" then
			newTargets = self.state.resourceBudgetTargets
			for _, k in ipairs(allResourceKeys()) do newLocked[k] = false end
		end
		self:setState({ resourceBudgetMode = mode, resourceBudgetTargets = newTargets, resourceBudgetLocked = newLocked })
		pushResourceBudget(mode, newTargets, newLocked)
	end

	self.onResourceBudgetTargetChanged = function(id: string, pct: number)
		local newTargets = {}
		for k, v in pairs(self.state.resourceBudgetTargets) do newTargets[k] = v end
		newTargets[id] = pct
		self:setState({ resourceBudgetTargets = newTargets })
		pushResourceBudget(self.state.resourceBudgetMode, newTargets, self.state.resourceBudgetLocked)
	end

	self.onResourceBudgetLockedChanged = function(id: string, locked: boolean)
		local newLocked = {}
		for k, v in pairs(self.state.resourceBudgetLocked) do newLocked[k] = v end
		newLocked[id] = locked
		self:setState({ resourceBudgetLocked = newLocked })
		pushResourceBudget(self.state.resourceBudgetMode, self.state.resourceBudgetTargets, newLocked)
	end

	-- Push initial resource budget attributes
	local initResTargets = resourceDefaultTargets("Equal")
	local initResLocked  = resourceDefaultLocked("Equal")
	self.state = table.clone(self.state :: any) :: any
	;(self.state :: any).resourceBudgetTargets = initResTargets
	;(self.state :: any).resourceBudgetLocked  = initResLocked
	pushResourceBudget("Equal", initResTargets, initResLocked)
	localPlayer:SetAttribute("EditorResourceZoneOwner", 0)

	-- ── Polygon sub-mode callbacks ──────────────────────────────────────────
	self.onZoneModeChanged = function(mode: string)
		self:setState({ zoneMode = mode, polygonClosed = false, polygonNodeCount = 0 })
		localPlayer:SetAttribute("EditorZoneMode", mode)
	end

	self.onCommitPolygon = function()
		localPlayer:SetAttribute("EditorCommitPolygon", true)
		self:setState({ polygonClosed = false, polygonNodeCount = 0 })
	end

	self.onCancelPolygon = function()
		localPlayer:SetAttribute("EditorCancelPolygon", true)
		self:setState({ polygonClosed = false, polygonNodeCount = 0 })
	end

	-- Watch polygon status attributes written by MapEditorController
	self.polyClosedConn = localPlayer:GetAttributeChangedSignal("EditorPolygonClosed"):Connect(function()
		self:setState({ polygonClosed = localPlayer:GetAttribute("EditorPolygonClosed") == true })
	end)
	self.polyCountConn = localPlayer:GetAttributeChangedSignal("EditorPolygonNodeCount"):Connect(function()
		self:setState({ polygonNodeCount = localPlayer:GetAttribute("EditorPolygonNodeCount") or 0 })
	end)

	-- Live zone area updates (written by controller after ZoneStats)
	local function parseZoneAreas(raw: string?): { [number]: number }
		local result = { [0]=0, [1]=0, [2]=0, [3]=0, [4]=0 }
		if not raw or raw == "" then return result end
		local i = 0
		for part in string.gmatch(raw, "[^,]+") do
			result[i] = (tonumber(part) or 0) / 10
			i += 1
			if i > 4 then break end
		end
		return result
	end
	self.zoneAreasConn = localPlayer:GetAttributeChangedSignal("EditorZoneAreas"):Connect(function()
		local raw = localPlayer:GetAttribute("EditorZoneAreas")
		self:setState({ zoneAreas = parseZoneAreas(raw) })
	end)

	-- Live resource area updates (written by controller after ResourceStats)
	local function parseResourceAreas(raw: string?): { [string]: number }?
		if not raw or raw == "" then return nil end
		local result: { [string]: number } = {}
		for entry in string.gmatch(raw, "[^;]+") do
			local key, val = string.match(entry, "([^=]+)=([^=]+)")
			if key and val then
				result[key] = (tonumber(val) or 0) / 10
			end
		end
		return result
	end
	self.resourceAreasConn = localPlayer:GetAttributeChangedSignal("EditorResourceAreas"):Connect(function()
		local raw = localPlayer:GetAttribute("EditorResourceAreas")
		self:setState({ resourceAreas = parseResourceAreas(raw) })
	end)

	self.onBrushSettingsChanged = function(settings)
		localPlayer:SetAttribute("EditorBrushRadius", settings.radius)
		localPlayer:SetAttribute("EditorBrushMode", settings.mode)
		localPlayer:SetAttribute("EditorBrushStrength", settings.strength)
		localPlayer:SetAttribute("EditorBrushHardness", settings.hardness)
		localPlayer:SetAttribute("EditorBrushShape", settings.shape)
		localPlayer:SetAttribute("EditorBrushMaterial", settings.material)
	end

	self.onSave = function()
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("SaveMap")
			self:setState({ statusText = "Saving..." })
		end
	end

	self.onLoad = function()
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("ListMaps")
			self:setState({ statusText = "Fetching map list..." })
		end
	end

	self.onCloseLoadModal = function()
		self:setState({ showLoadModal = false, statusText = "Load cancelled." })
	end

	self.onSelectMap = function(mapId: string)
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("LoadMap", mapId)
			self:setState({ showLoadModal = false, statusText = "Loading map..." })
		end
	end

	self.onRenameMap = function(mapId: string, newName: string)
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("RenameMap", { mapId = mapId, name = newName })
			local updatedMaps = {}
			for _, entry in ipairs(self.state.loadedMaps) do
				if entry.MapId == mapId then
					local updated = {}
					for k, v in pairs(entry) do updated[k] = v end
					updated.Name = newName
					table.insert(updatedMaps, updated)
				else
					table.insert(updatedMaps, entry)
				end
			end
			self:setState({ loadedMaps = updatedMaps, statusText = "Map renamed." })
		end
	end

	self.onDeleteMap = function(mapId: string)
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("DeleteMap", mapId)
			local updatedMaps = {}
			for _, entry in ipairs(self.state.loadedMaps) do
				if entry.MapId ~= mapId then
					table.insert(updatedMaps, entry)
				end
			end
			self:setState({ loadedMaps = updatedMaps, statusText = "Map deleted." })
		end
	end

	self.onScreenshotMode = function()
		local entering = not self.state.screenshotMode
		self:setState({ screenshotMode = entering })
		localPlayer:SetAttribute("EditorScreenshotMode", entering)
		if entering then
			localPlayer:SetAttribute("EditorScreenshotMapSize", self.state.mapSize)
		end
	end

	self.onExport = function()
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("ExportMap")
		end
	end

	-- ── Overlay toggle callbacks ────────────────────────────────────────
	self.onToggleZoneOverlay = function()
		local newOn = not self.state.zoneOverlayOn
		self:setState({ zoneOverlayOn = newOn })
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer(if newOn then "ShowZoneOverlay" else "HideZoneOverlay")
		end
	end

	self.onToggleResourceOverlay = function()
		local newOn = not self.state.resourceOverlayOn
		self:setState({ resourceOverlayOn = newOn })
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer(if newOn then "ShowResourceOverlay" else "HideResourceOverlay")
		end
	end

	-- ── Activate custom map for lobby ───────────────────────────────────
	self.onActivateForGame = function()
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("ActivateCustomMap")
			self:setState({ statusText = "Activating map for game..." })
		end
	end

	self.onBack = function()
		if self.props.navigate then
			self.props.navigate("mainMenu")
		end
	end
end

function MapEditor:willUnmount()
	if self.editorConnection then
		self.editorConnection:Disconnect()
	end
	if self.polyClosedConn then self.polyClosedConn:Disconnect() end
	if self.polyCountConn then self.polyCountConn:Disconnect() end
	if self.zoneAreasConn then self.zoneAreasConn:Disconnect() end
	if self.resourceAreasConn then self.resourceAreasConn:Disconnect() end

	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local ev = RemoteEvents:FindFirstChild("MapEditorEvent")
		if ev then
			(ev :: RemoteEvent):FireServer("LeaveEditor")
		end
	end
end

function MapEditor:render()
	local screenshotMode = self.state.screenshotMode

	return React.createElement("ScreenGui", {
		Name = "MapEditorGui",
		ClipToDeviceSafeArea = true,
		DisplayOrder = 5,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		-- In screenshot mode, hide all editor UI except a small exit button
		ScreenshotOverlay = screenshotMode and React.createElement("TextButton", {
			Name = "ScreenshotExitButton",
			Size = UDim2.new(0, 140, 0, 32),
			Position = UDim2.new(0, 8, 1, -8),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Color3.fromRGB(30, 30, 45),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Text = "[] Exit Screenshot Mode",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(180, 210, 255),
			TextSize = 12,
			ZIndex = 20,
			[React.Event.MouseButton1Click] = self.onScreenshotMode,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			UIStroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(100, 130, 200),
				Thickness = 1,
			}),
		}) or nil,

		TopBar = not screenshotMode and React.createElement(EditorTopBar, {
			mapName = self.state.mapName,
			mapSize = self.state.mapSize,
			maxPlayers = self.state.maxPlayers,
			activeTool = self.state.activeTool,
			onToolSelected = self.onToolSelected,
			onNameChanged = self.onNameChanged,
			onSave = self.onSave,
			onLoad = self.onLoad,
			onExport = self.onExport,
			onActivate = self.onActivateForGame,
			onBack = self.onBack,
			onScreenshotMode = self.onScreenshotMode,
		}) or nil,

		PropertyPanel = not screenshotMode and React.createElement(EditorPropertyPanel, {
			activeTool = self.state.activeTool,
			onBrushSettingsChanged = self.onBrushSettingsChanged,
			onMapSettingsChanged = self.onMapSettingsChanged,
			mapSize = self.state.mapSize,
			maxPlayers = self.state.maxPlayers,
			description = self.state.description,
			neutralZoneWidth = self.state.neutralZoneWidth,
			resourceDensity = self.state.resourceDensity,
			-- Zone paint
			zoneAreas = self.state.zoneAreas,
			zoneBudgetMode = self.state.zoneBudgetMode,
			zoneBudgetTargets = self.state.zoneBudgetTargets,
			zoneBudgetLocked  = self.state.zoneBudgetLocked,
			onZoneBudgetModeChanged   = self.onZoneBudgetModeChanged,
			onZoneBudgetTargetChanged = self.onZoneBudgetTargetChanged,
			onZoneBudgetLockedChanged = self.onZoneBudgetLockedChanged,
			-- Polygon mode
			zoneMode = self.state.zoneMode,
			polygonClosed = self.state.polygonClosed,
			polygonNodeCount = self.state.polygonNodeCount,
			onZoneModeChanged = self.onZoneModeChanged,
			onCommitPolygon = self.onCommitPolygon,
			onCancelPolygon = self.onCancelPolygon,
			-- Resources
			selectedResourceZone = self.state.selectedResourceZone,
			resourceAreas = self.state.resourceAreas,
			resourceBudgetMode = self.state.resourceBudgetMode,
			resourceBudgetTargets = self.state.resourceBudgetTargets,
			resourceBudgetLocked  = self.state.resourceBudgetLocked,
			onResourceZoneChanged           = self.onResourceZoneChanged,
			onResourceBudgetModeChanged     = self.onResourceBudgetModeChanged,
			onResourceBudgetTargetChanged   = self.onResourceBudgetTargetChanged,
			onResourceBudgetLockedChanged   = self.onResourceBudgetLockedChanged,
			-- Overlay toggles
			zoneOverlayOn = self.state.zoneOverlayOn,
			resourceOverlayOn = self.state.resourceOverlayOn,
			onToggleZoneOverlay = self.onToggleZoneOverlay,
			onToggleResourceOverlay = self.onToggleResourceOverlay,
		}) or nil,

		StatusBar = not screenshotMode and React.createElement("Frame", {
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
				Text = "LMB: Paint | RMB: Orbit | MMB: Pan | Scroll: Zoom | Ctrl+Z: Undo",
				FontFace = UIConfig.Font.Default,
				TextColor3 = UIConfig.HUD.StrokeColor,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}) or nil,

		LoadModal = self.state.showLoadModal and React.createElement(LoadMapModal, {
			maps = self.state.loadedMaps,
			onClose = self.onCloseLoadModal,
			onSelectMap = self.onSelectMap,
			onRenameMap = self.onRenameMap,
			onDeleteMap = self.onDeleteMap,
		}) or nil,
	})
end

return MapEditor
