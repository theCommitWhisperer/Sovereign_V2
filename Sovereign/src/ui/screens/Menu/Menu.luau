--!strict
-- Menu modal for in-game settings and options
local React = require(game.ReplicatedStorage.Packages.react)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modal = require(script.Parent.Parent.Parent.components.Modal)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MenuDebug = DebugManager.createChannel("Menu", false)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameEvent = RemoteEvents:WaitForChild("GameEvent")

local Menu = React.Component:extend("Menu")

export type Props = {
	visible: boolean,
	onClose: () -> (),
	navigate: ((screen: string) -> ())?,
}

-- Menu options
local MENU_OPTIONS = {
	{ name = "Resume Game", icon = "▶️", action = "resume", description = "Continue playing" },
	{ name = "Settings", icon = "⚙️", action = "settings", description = "Game settings and options" },
	{
		name = "Return to Main Menu",
		icon = "🏠",
		action = "mainmenu",
		description = "Leave game and return to menu",
	},
	{ name = "Quit Game", icon = "🚪", action = "quit", description = "Exit the game" },
}

function Menu:handleMenuAction(action: string)
	MenuDebug:info("Menu action triggered", { action = action })

	if action == "resume" then
		-- Just close the menu
		self.props.onClose()
	elseif action == "settings" then
		-- Navigate to settings screen
		if self.props.navigate then
			self.props.navigate("settings")
		end
	elseif action == "mainmenu" then
		-- Return to main menu - send LeaveGame event to server
		-- The server will send back a GameLeft event which will trigger navigation in App.luau
		MenuDebug:info("Leaving game and returning to main menu")
		GameEvent:FireServer("LeaveGame", {})
	elseif action == "quit" then
		-- Quit the game
		local player = Players.LocalPlayer
		if player then
			player:Kick("Player exited the game.")
		end
	end
end

function Menu:render()
	local menuButtons = {}

	menuButtons.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 15),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	-- Create button for each menu option
	for i, option in ipairs(MENU_OPTIONS) do
		menuButtons[option.action] = React.createElement("TextButton", {
			Size = UDim2.new(0.85, 0, 0, 80),
			BackgroundColor3 = UIConfig.HUD.UtilityButtonBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.UtilityButtonBorder,
			LayoutOrder = i,
			AutoButtonColor = true,
			Text = "",
			[React.Event.MouseButton1Click] = function()
				self:handleMenuAction(option.action)
			end,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 15),
				PaddingBottom = UDim.new(0, 15),
				PaddingLeft = UDim.new(0, 25),
				PaddingRight = UDim.new(0, 25),
			}),

			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),

			-- Top row: Icon and Name
			TopRow = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 12),
				}),

				Icon = React.createElement("TextLabel", {
					Size = UDim2.new(0, 32, 0, 32),
					BackgroundTransparency = 1,
					Text = option.icon,
					Font = Enum.Font.GothamBold,
					TextSize = 28,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				Label = React.createElement("TextLabel", {
					Size = UDim2.new(1, -44, 1, 0),
					BackgroundTransparency = 1,
					Text = option.name,
					Font = Enum.Font.GothamBold,
					TextSize = 24,
					TextColor3 = UIConfig.HUD.PanelHeaderColor,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			}),

			-- Description
			Description = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = option.description,
				Font = Enum.Font.Gotham,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				LayoutOrder = 2,
			}),
		})
	end

	return React.createElement(Modal, {
		title = "Game Menu",
		visible = self.props.visible,
		onClose = self.props.onClose,
		size = UDim2.fromScale(0.45, 0.65),
	}, {
		MenuButtons = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
		}, menuButtons),
	})
end

return Menu
