-- src/ui/main.client.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MainClientDebug = DebugManager.createChannel("MainUI", false)

MainClientDebug:info("Main Client Script started.")

local React = require(game.ReplicatedStorage.Packages.react)
local ReactRoblox = require(game.ReplicatedStorage.Packages["react-roblox"])
local App = require(script.Parent.App) -- App.luau is in the same folder as this script

local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

MainClientDebug:info("PlayerGui found.")

local rootGui = Instance.new("ScreenGui")
rootGui.Name = "SovereignApp"
rootGui.Parent = playerGui

MainClientDebug:info("SovereignApp ScreenGui created.")

local root = ReactRoblox.createRoot(rootGui)
MainClientDebug:info("Roact root created. Rendering App...")

root:render(React.createElement(App))

MainClientDebug:info("App rendering process initiated.")

script.Destroying:Connect(function()
	root:unmount()
end)
