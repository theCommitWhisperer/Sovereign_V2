--!strict
-- KeybindingsManager: Manages customizable keybindings for camera controls
-- Handles saving/loading, conflict detection, and UI integration
-- THIS IS A SINGLETON MODULE

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
	| "RotatePlacement"
	| "CyclePlacementType"
	| "CyclePivot"
	| "AdjustPlacementHeight"

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
	RotatePlacement = Enum.KeyCode.R,
	CyclePlacementType = Enum.KeyCode.T,
	CyclePivot = Enum.KeyCode.F,
	AdjustPlacementHeight = Enum.KeyCode.LeftShift,
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
	RotatePlacement = "Rotate Building",
	CyclePlacementType = "Cycle Wall Type",
	CyclePivot = "Cycle Placement Pivot",
	AdjustPlacementHeight = "Adjust Wall Height (hold + mouse wheel)",
}

local KeybindingsManager = {}
KeybindingsManager.player = Players.LocalPlayer
KeybindingsManager.keybindings = table.clone(DEFAULT_KEYBINDINGS)
KeybindingsManager.callbacks = {} -- [action] = {callback functions}

function KeybindingsManager.GetKeybinding(action: KeybindingAction): Enum.KeyCode?
	return KeybindingsManager.keybindings[action]
end

function KeybindingsManager.SetKeybinding(action: KeybindingAction, keyCode: Enum.KeyCode): boolean
	-- Check for conflicts
	if KeybindingsManager.HasConflict(action, keyCode) then
		return false
	end

	KeybindingsManager.keybindings[action] = keyCode
	KeybindingsManager.SaveKeybindings()

	-- Notify callbacks
	if KeybindingsManager.callbacks[action] then
		for _, callback in ipairs(KeybindingsManager.callbacks[action]) do
			callback(keyCode)
		end
	end

	return true
end

function KeybindingsManager.GetAllKeybindings(): KeybindingsData
	return table.clone(KeybindingsManager.keybindings)
end

function KeybindingsManager.GetActionDescription(action: KeybindingAction): string
	return ACTION_DESCRIPTIONS[action] or action
end

function KeybindingsManager.GetAllActions(): { KeybindingAction }
	local actions = {}
	for action, _ in pairs(DEFAULT_KEYBINDINGS) do -- Iterate over defaults to maintain order and include all
		table.insert(actions, action)
	end
	return actions
end

function KeybindingsManager.HasConflict(action: KeybindingAction, keyCode: Enum.KeyCode): (boolean, KeybindingAction?)
	for otherAction, otherKeyCode in pairs(KeybindingsManager.keybindings) do
		if otherAction ~= action and otherKeyCode == keyCode then
			return true, otherAction
		end
	end
	return false, nil
end

function KeybindingsManager.ResetToDefaults()
	KeybindingsManager.keybindings = table.clone(DEFAULT_KEYBINDINGS)
	KeybindingsManager.SaveKeybindings()

	-- Notify all callbacks
	for action, callbacks in pairs(KeybindingsManager.callbacks) do
		local newKeyCode = KeybindingsManager.keybindings[action]
		if newKeyCode then
			for _, callback in ipairs(callbacks) do
				callback(newKeyCode)
			end
		end
	end
end

function KeybindingsManager.OnKeybindingChanged(action: KeybindingAction, callback: (Enum.KeyCode) -> ())
	if not KeybindingsManager.callbacks[action] then
		KeybindingsManager.callbacks[action] = {}
	end
	table.insert(KeybindingsManager.callbacks[action], callback)

	-- Return a disconnect function
	return {
		Disconnect = function()
			if KeybindingsManager.callbacks[action] then
				for i, cb in ipairs(KeybindingsManager.callbacks[action]) do
					if cb == callback then
						table.remove(KeybindingsManager.callbacks[action], i)
						break
					end
				end
			end
		end,
	}
end

function KeybindingsManager.SaveKeybindings()
	local data = {}
	for action, keyCode in pairs(KeybindingsManager.keybindings) do
		data[action] = keyCode.Name
	end

	local success, err = pcall(function()
		local jsonData = HttpService:JSONEncode(data)
		KeybindingsManager.player:SetAttribute("CameraKeybindings", jsonData)
	end)

	if not success then
		warn("Failed to save keybindings:", err)
	end
end

function KeybindingsManager.LoadKeybindings()
	local success, jsonData = pcall(function()
		return KeybindingsManager.player:GetAttribute("CameraKeybindings")
	end)

	if success and jsonData and typeof(jsonData) == "string" then
		local dataSuccess, data = pcall(function()
			return HttpService:JSONDecode(jsonData)
		end)

		if dataSuccess and typeof(data) == "table" then
			for action, keyName in pairs(data) do
				local keyCode = Enum.KeyCode[keyName]
				if keyCode and DEFAULT_KEYBINDINGS[action] then
					KeybindingsManager.keybindings[action] = keyCode
				end
			end
		end
	end
end

function KeybindingsManager.GetKeyCodeName(keyCode: Enum.KeyCode): string
	local name = tostring(keyCode.Name)
	if name == "LeftShift" or name == "RightShift" then return "Shift" end
	if name == "LeftControl" or name == "RightControl" then return "Ctrl" end
	if name == "LeftAlt" or name == "RightAlt" then return "Alt" end
	return name
end

function KeybindingsManager.IsDefaultKeybinding(action: KeybindingAction): boolean
	return KeybindingsManager.keybindings[action] == DEFAULT_KEYBINDINGS[action]
end

function KeybindingsManager.GetDefaultKeybinding(action: KeybindingAction): Enum.KeyCode
	return DEFAULT_KEYBINDINGS[action]
end

-- Initialization logic
KeybindingsManager.LoadKeybindings()

KeybindingsManager.player:GetAttributeChangedSignal("CameraKeybindings"):Connect(function()
	KeybindingsManager.LoadKeybindings()
	-- Notify callbacks about changes
	for action, callbacks in pairs(KeybindingsManager.callbacks) do
		local keyCode = KeybindingsManager.keybindings[action]
		if keyCode then
			for _, callback in ipairs(callbacks) do
				callback(keyCode)
			end
		end
	end
end)


return KeybindingsManager