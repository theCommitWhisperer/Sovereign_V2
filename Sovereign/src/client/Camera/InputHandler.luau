--!strict
-- InputHandler: Detects platform and normalizes input from different sources
-- Provides a unified interface for desktop, mobile, and gamepad inputs

local UserInputService = game:GetService("UserInputService")

export type InputEvent = {
	Type: string, -- "Pan", "Rotate", "Zoom", "Move", "Focus"
	Delta: Vector2?,
	Position: Vector2?,
	ZoomDelta: number?,
	MoveDirection: Vector3?,
	IsActive: boolean,
}

local InputHandler = {}
InputHandler.__index = InputHandler

function InputHandler.new()
	local self = setmetatable({}, InputHandler)

	-- Platform detection
	self.isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	self.isDesktop = UserInputService.MouseEnabled and UserInputService.KeyboardEnabled
	self.isGamepad = UserInputService.GamepadEnabled

	-- Input modules
	self.desktopInput = nil
	self.mobileInput = nil
	self.gamepadInput = nil

	-- Shared state
	self.enabled = false
	self.callbacks = {}

	return self
end

function InputHandler:SetDesktopInput(desktopInput)
	self.desktopInput = desktopInput
end

function InputHandler:SetMobileInput(mobileInput)
	self.mobileInput = mobileInput
end

function InputHandler:SetGamepadInput(gamepadInput)
	self.gamepadInput = gamepadInput
end

function InputHandler:Enable()
	self.enabled = true

	-- Enable appropriate input module based on platform
	if self.isDesktop and self.desktopInput then
		self.desktopInput:Enable()
	end

	if self.isMobile and self.mobileInput then
		self.mobileInput:Enable()
	end

	if self.isGamepad and self.gamepadInput then
		self.gamepadInput:Enable()
	end
end

function InputHandler:Disable()
	self.enabled = false

	if self.desktopInput then
		self.desktopInput:Disable()
	end

	if self.mobileInput then
		self.mobileInput:Disable()
	end

	if self.gamepadInput then
		self.gamepadInput:Disable()
	end
end

function InputHandler:OnInputEvent(callback: (InputEvent) -> ())
	table.insert(self.callbacks, callback)
end

function InputHandler:FireEvent(event: InputEvent)
	if not self.enabled then
		return
	end

	for _, callback in ipairs(self.callbacks) do
		callback(event)
	end
end

function InputHandler:IsMobile(): boolean
	return self.isMobile
end

function InputHandler:IsDesktop(): boolean
	return self.isDesktop
end

function InputHandler:IsGamepad(): boolean
	return self.isGamepad
end

function InputHandler:Destroy()
	self:Disable()
	self.callbacks = {}
end

return InputHandler
