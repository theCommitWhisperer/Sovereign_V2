-- src/ui/main.client.luau
print("main.client.luau: Script started.")

local React = require(game.ReplicatedStorage.Packages.react)
local ReactRoblox = require(game.ReplicatedStorage.Packages["react-roblox"])
local App = require(script.Parent.App) -- App.luau is in the same folder as this script

local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("main.client.luau: PlayerGui found.")

local rootGui = Instance.new("ScreenGui")
rootGui.Name = "SovereignApp"
rootGui.Parent = playerGui

print("main.client.luau: SovereignApp ScreenGui created.")

local root = ReactRoblox.createRoot(rootGui)
print("main.client.luau: Roact root created. Rendering App...")

root:render(React.createElement(App))

print("main.client.luau: App rendering process initiated.")

script.Destroying:Connect(function()
	root:unmount()
end)
