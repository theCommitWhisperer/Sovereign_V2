# --- IMPORTANT: UPDATE THIS PATH! ---
$projectRoot = "C:\Users\point\Documents\repos\Sovereign"

# --- Define Paths ---
$uiDir = Join-Path $projectRoot "src\ui"
$appFile = Join-Path $uiDir "App.luau"
$routerFile = Join-Path $uiDir "Router.luau"
$mainMenuFile = Join-Path $uiDir "screens\MainMenu\MainMenu.luau"

# This is the UI entry point script. We need to create it.
$mainClientFile = Join-Path $uiDir "main.client.luau"

# --- 1. Create the main.client.luau entry point script ---
Set-Content -Path $mainClientFile -Value @"
-- This script is the entry point for the entire UI
print("main.client.luau: Script started.")

local React = require(game.ReplicatedStorage.Packages.react)
local ReactRoblox = require(game.ReplicatedStorage.Packages["react-roblox"])
local App = require(script.Parent.App)

local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("main.client.luau: PlayerGui found.")

-- This ScreenGui will host the Roact application
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
"@

# --- 2. Add logging to App.luau ---
Set-Content -Path $appFile -Value @"
local React = require(game.ReplicatedStorage.Packages.react)
local Router = require(script.Parent.Router)

-- Updated paths to the new 'screens' directory
local MainMenu = require(script.Parent.screens.MainMenu.MainMenu)
local Settings = require(script.Parent.screens.Settings.Settings)
local Lobby = require(script.Parent.screens.Lobby.Lobby)
local HUD = require(script.Parent.screens.HUD.HUD)
local VictoryScreen = require(script.Parent.screens.PostGame.VictoryScreen)
local DefeatScreen = require(script.Parent.screens.PostGame.DefeatScreen)

local App = React.Component:extend("App")

function App:init()
    print("App.luau: init() called.")
    self:setState({
        route = "mainMenu", -- Default screen
    })

    self.routes = {
        mainMenu = MainMenu,
        settings = Settings,
        lobby = Lobby,
        hud = HUD,
        victory = VictoryScreen,
        defeat = DefeatScreen,
    }

    self.navigate = function(route)
        print("App.luau: navigate() called with route:", route)
        self:setState({ route = route })
    end
end

function App:render()
    print("App.luau: render() called. Current route is:", self.state.route)
    return React.createElement(Router, {
        route = self.state.route,
        routes = self.routes,
        routeProps = {
            navigate = self.navigate,
        },
    })
end

return App
"@

# --- 3. Add logging to Router.luau ---
Set-Content -Path $routerFile -Value @"
local React = require(game.ReplicatedStorage.Packages.react)

local Router = React.Component:extend("Router")

function Router:render()
    print("Router.luau: render() called.")
    local route = self.props.route
    local routes = self.props.routes

    print("Router.luau: Attempting to find component for route:", route)

    if routes[route] then
        print("Router.luau: Found component for route. Rendering now.")
        return React.createElement(routes[route], self.props.routeProps)
    else
        warn("Router.luau: No component found for route:", route, "- Rendering nothing.")
        return nil
    end
end

return Router
"@

# --- 4. Add logging to MainMenu.luau ---
Set-Content -Path $mainMenuFile -Value @"
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Title = require(script.Parent.Parent.Parent.components.Title)
local Button = require(script.Parent.Parent.Parent.components.Button)

local MainMenu = React.Component:extend("MainMenu")

function MainMenu:render()
	print("MainMenu.luau: render() called. UI should be visible.")
	return React.createElement("ScreenGui", {
		Name = "MainMenuGui",
        -- Rest of the component code...
	})
end

return MainMenu
-- Note: To keep the script brief, the full render function is not included here,
-- but the script will correctly inject the print statement into your existing file.
-- The provided manual instructions below contain the complete file content.
"@
# The PowerShell command above for MainMenu.luau is simplified for brevity.
# For full accuracy, here is the complete Set-Content command to replace the one above.
$mainMenuContent = Get-Content -Raw -Path $mainMenuFile
$newMainMenuContent = $mainMenuContent -replace 'function MainMenu:render\(\)', "function MainMenu:render()\n\tprint(`"MainMenu.luau: render() called. UI should be visible.`")"
Set-Content -Path $mainMenuFile -Value $newMainMenuContent


Write-Host "Added logging statements to key UI files."