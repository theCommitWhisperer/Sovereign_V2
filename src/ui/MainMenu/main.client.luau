local React = require(game.ReplicatedStorage.Packages.react)
local ReactRoblox = require(game.ReplicatedStorage.Packages["react-roblox"])
local App = require(script.Parent.Parent.App)

local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local rootGui = Instance.new("ScreenGui")
rootGui.Name = "MainMenu"
rootGui.Parent = playerGui

local root = ReactRoblox.createRoot(rootGui)
root:render(React.createElement(App))

script.Destroying:Connect(function()
	root:unmount()
end)
