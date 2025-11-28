--!strict
-- KeybindingsManager: Manages customizable keybindings for camera controls
-- Handles saving/loading, conflict detection, and UI integration

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

export type KeybindingAction =
	"PanUp"
	| "PanDown"
	| "PanLeft"
	| "PanRight"
	| "RotateLeft"
	| "RotateRight"
	| "Focus"
	| "ResetCamera"
	| "ToggleCameraMode"

export type KeybindingsData = {
	[KeybindingAction]: Enum.KeyCode,
}

local DEFAULT_KEYBINDINGS: KeybindingsData = {
	PanUp = Enum.KeyCode.W,
	PanDown = Enum.KeyCode.S,
	PanLeft = Enum.KeyCode.A,
	PanRight = Enum.KeyCode.D,
	RotateLeft = Enum.KeyCode.Q,
	RotateRight = Enum.KeyCode.E,
	Focus = Enum.KeyCode.F,
	ResetCamera = Enum.KeyCode.Home,
	ToggleCameraMode = Enum.KeyCode.Tab,
}

local ACTION_DESCRIPTIONS = {
	PanUp = "Pan Camera Forward",
	PanDown = "Pan Camera Backward",
	PanLeft = "Pan Camera Left",
	PanRight = "Pan Camera Right",
	RotateLeft = "Rotate Camera Left",
	RotateRight = "Rotate Camera Right",
	Focus = "Focus on Target",
	ResetCamera = "Reset Camera Position",
	ToggleCameraMode = "Toggle Camera Mode",
}

local KeybindingsManager = {}
KeybindingsManager.__index = KeybindingsManager

function KeybindingsManager.new()
	local self = setmetatable({}, KeybindingsManager)

	self.player = Players.LocalPlayer
	self.keybindings = table.clone(DEFAULT_KEYBINDINGS)
	self.callbacks = {} -- [action] = {callback functions}

	-- Load saved keybindings
	self:LoadKeybindings()

	return self
end

function KeybindingsManager:GetKeybinding(action: KeybindingAction): Enum.KeyCode?
	return self.keybindings[action]
end

function KeybindingsManager:SetKeybinding(action: KeybindingAction, keyCode: Enum.KeyCode): boolean
	-- Check for conflicts
	if self:HasConflict(action, keyCode) then
		return false
	end

	self.keybindings[action] = keyCode
	self:SaveKeybindings()

	-- Notify callbacks
	if self.callbacks[action] then
		for _, callback in ipairs(self.callbacks[action]) do
			callback(keyCode)
		end
	end

	return true
end

function KeybindingsManager:GetAllKeybindings(): KeybindingsData
	return table.clone(self.keybindings)
end

function KeybindingsManager:GetActionDescription(action: KeybindingAction): string
	return ACTION_DESCRIPTIONS[action] or action
end

function KeybindingsManager:GetAllActions(): { KeybindingAction }
	local actions = {}
	for action, _ in pairs(self.keybindings) do
		table.insert(actions, action)
	end
	return actions
end

function KeybindingsManager:HasConflict(action: KeybindingAction, keyCode: Enum.KeyCode): (boolean, KeybindingAction?)
	for otherAction, otherKeyCode in pairs(self.keybindings) do
		if otherAction ~= action and otherKeyCode == keyCode then
			return true, otherAction
		end
	end
	return false, nil
end

function KeybindingsManager:ResetToDefaults()
	self.keybindings = table.clone(DEFAULT_KEYBINDINGS)
	self:SaveKeybindings()

	-- Notify all callbacks
	for action, callbacks in pairs(self.callbacks) do
		local keyCode = self.keybindings[action]
		for _, callback in ipairs(callbacks) do
			callback(keyCode)
		end
	end
end

function KeybindingsManager:OnKeybindingChanged(action: KeybindingAction, callback: (Enum.KeyCode) -> ())
	if not self.callbacks[action] then
		self.callbacks[action] = {}
	end
	table.insert(self.callbacks[action], callback)
end

function KeybindingsManager:SaveKeybindings()
	-- Save to DataStore (in a real game)
	-- For now, save to player attributes for persistence during session
	local data = {}
	for action, keyCode in pairs(self.keybindings) do
		-- Store as string name for compatibility with UI
		data[action] = keyCode.Name
	end

	local success, err = pcall(function()
		local jsonData = HttpService:JSONEncode(data)
		self.player:SetAttribute("CameraKeybindings", jsonData)
	end)

	if not success then
		warn("Failed to save keybindings:", err)
	end
end

function KeybindingsManager:LoadKeybindings()
	-- Load from DataStore (in a real game)
	-- For now, load from player attributes
	local success, jsonData = pcall(function()
		return self.player:GetAttribute("CameraKeybindings")
	end)

	if success and jsonData then
		local dataSuccess, data = pcall(function()
			return HttpService:JSONDecode(jsonData)
		end)

		if dataSuccess and data then
			-- Apply loaded keybindings
			for action, keyName in pairs(data) do
				-- Convert string name back to KeyCode
				local keyCode = Enum.KeyCode[keyName]
				if keyCode then
					self.keybindings[action] = keyCode
				end
			end
		end
	end

	-- Watch for changes from UI
	self.player:GetAttributeChangedSignal("CameraKeybindings"):Connect(function()
		self:LoadKeybindings()
		-- Notify callbacks about changes
		for action, callbacks in pairs(self.callbacks) do
			local keyCode = self.keybindings[action]
			if keyCode then
				for _, callback in ipairs(callbacks) do
					callback(keyCode)
				end
			end
		end
	end)
end

function KeybindingsManager:GetKeyCodeName(keyCode: Enum.KeyCode): string
	-- Convert KeyCode enum to friendly display name
	local name = tostring(keyCode.Name)

	-- Handle special cases
	if name == "LeftShift" or name == "RightShift" then
		return "Shift"
	elseif name == "LeftControl" or name == "RightControl" then
		return "Ctrl"
	elseif name == "LeftAlt" or name == "RightAlt" then
		return "Alt"
	end

	return name
end

function KeybindingsManager:IsDefaultKeybinding(action: KeybindingAction): boolean
	return self.keybindings[action] == DEFAULT_KEYBINDINGS[action]
end

function KeybindingsManager:GetDefaultKeybinding(action: KeybindingAction): Enum.KeyCode
	return DEFAULT_KEYBINDINGS[action]
end

return KeybindingsManager
