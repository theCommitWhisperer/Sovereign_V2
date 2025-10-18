-- thecommitwhisperer/sovereign_v2/Sovereign_V2-a5a2c87f4791d0aeedd3f50cf89de31685a4f9fb/Sovereign/src/ui/UIConfig.luau
local UIConfig = {
	Font = {
		Default = Font.new("rbxasset://fonts/families/IndieFlower.json"),
		Title = Font.new("rbxasset://fonts/families/IndieFlower.json"),
		Button = {
			Default = Font.new("rbxasset://fonts/families/IndieFlower.json"),
		},
	},
	Color = {
		Primary = Color3.fromRGB(255, 255, 255),
		Secondary = Color3.fromRGB(170, 170, 170),
		Background = Color3.fromRGB(0, 0, 0),
		PrimaryButton = Color3.fromRGB(0, 122, 255),
		SecondaryButton = Color3.fromRGB(100, 100, 100),
		SliderTrack = Color3.fromRGB(191, 219, 254),
		SliderProgress = Color3.fromRGB(59, 130, 246),
		TooltipBackground = Color3.fromRGB(75, 85, 99),
		TooltipText = Color3.fromRGB(255, 255, 255),
	},
	Size = {
		Button = UDim2.new(0, 200, 0, 50),
		Title = UDim2.new(1, 0, 0, 100),
	},
	LobbyPage = {
		-- Panel Styling
		PanelBackgroundColor = Color3.fromRGB(0, 0, 0),
		PanelBackgroundTransparency = 0.5,

		-- Player List
		PlayerListTitleColor = Color3.fromRGB(255, 255, 255),
		PlayerListTitleSize = 28,
		PlayerListNameColor = Color3.fromRGB(220, 220, 220),
		PlayerListNameSize = 20,
		AddAIButtonTextColor = Color3.fromRGB(255, 255, 255),
		AddAIButtonTextSize = 22,
		RemoveButtonTextColor = Color3.fromRGB(255, 100, 100),
		RemoveButtonTextSize = 18,

		-- Map Preview & Selector
		MapPreviewTitleColor = Color3.fromRGB(255, 255, 255),
		MapPreviewTitleSize = 24,
		MapPreviewNameColor = Color3.fromRGB(220, 220, 220),
		MapPreviewNameSize = 22,
		MapSelectorBackgroundColor = Color3.fromRGB(100, 100, 100),
		MapSelectorTextColor = Color3.fromRGB(255, 255, 255),

		-- Game Settings Section
		GameSettingsTitleColor = Color3.fromRGB(255, 255, 255),
		GameSettingsTitleSize = 32,
		StartingResourcesTitleColor = Color3.fromRGB(240, 240, 240),
		StartingResourcesTitleSize = 24,
		GameRulesTitleColor = Color3.fromRGB(240, 240, 240),
		GameRulesTitleSize = 24,

		-- Setting Options (Rows)
		OptionsTextColor = Color3.fromRGB(220, 220, 220),
		OptionsTextSize = 20,

		-- Buttons
		StartButtonTextColor = Color3.fromRGB(255, 255, 255),
		StartButtonTextSize = 32,
		BackButtonTextColor = Color3.fromRGB(220, 220, 220),
		BackButtonTextSize = 24,

		-- Padding Configuration
		Padding = {
			-- Padding for the main Left and Right panels inside the MainFrame
			MainPanels = {
				Top = UDim.new(0, 10),
				Bottom = UDim.new(0, 10),
				Left = UDim.new(0, 10),
				Right = UDim.new(0, 10),
			},
			-- Padding inside the Left Panel (around MapPreview, Selector, etc.)
			LeftPanelSections = {
				Top = UDim.new(0, 15),
				Bottom = UDim.new(0, 15),
				Left = UDim.new(0, 15),
				Right = UDim.new(0, 15),
			},
			-- Padding inside the Right Panel (around PlayerList, GameSettings, etc.)
			RightPanelSections = {
				Top = UDim.new(0, 0),
				Bottom = UDim.new(0, 0),
				Left = UDim.new(0, 0),
				Right = UDim.new(0, 0),
			},
			-- Padding inside the GameSettingsFrame
			GameSettings = {
				Top = UDim.new(0, 20),
				Bottom = UDim.new(0, 20),
				Left = UDim.new(0, 10),
				Right = UDim.new(0, 10),
			},
			-- Padding for the columns within the SettingsContainer
			SettingsColumns = {
				Top = UDim.new(0, 5),
				Bottom = UDim.new(0, 5),
				Left = UDim.new(0, 5),
				Right = UDim.new(0, 5),
			},
			-- Padding for the individual rows (e.g., Gold, Troops)
			SettingsRows = {
				Top = UDim.new(0, 5),
				Bottom = UDim.new(0, 5),
				Left = UDim.new(0, 0),
				Right = UDim.new(0, 0),
			},
			-- Padding for the bottom buttons frame
			ButtonsFrame = {
				Top = UDim.new(0, 10),
				Bottom = UDim.new(0, 10),
				Left = UDim.new(0, 0),
				Right = UDim.new(0, 0),
			},
			-- Padding inside the PlayerList component
			PlayerListContentPadding = {
				Top = UDim.new(0, 10),
				Bottom = UDim.new(0, 10),
				Left = UDim.new(0, 15),
				Right = UDim.new(0, 15),
			},
			-- Spacing between elements inside the PlayerList (e.g., between title and names)
			PlayerListSpacing = UDim.new(0, 5),
		},
	},
}

function UIConfig.getFont(...)
	local args = { ... }
	for _, font in ipairs(args) do
		if font then
			return font
		end
	end
	return UIConfig.Font.Default
end

return UIConfig
