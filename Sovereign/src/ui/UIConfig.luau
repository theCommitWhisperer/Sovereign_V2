-- thecommitwhisperer/sovereign_v2/Sovereign_V2-a5a2c87f4791d0aeedd3f50cf89de31685a4f9fb/Sovereign/src/ui/UIConfig.luau
local UIConfig = {
	Font = {
		Default = Font.new("rbxasset://fonts/families/Fondamento.json"),
		Title = Font.new("rbxasset://fonts/families/Fondamento.json", Enum.FontWeight.Bold),
		Medieval = Font.new("rbxasset://fonts/families/Fondamento.json"),
		Button = {
			Default = Font.new("rbxasset://fonts/families/Fondamento.json"),
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
	Colors = {
		Danger = Color3.fromRGB(220, 53, 69),
		Warning = Color3.fromRGB(255, 193, 7),
		Success = Color3.fromRGB(40, 167, 69),
		Info = Color3.fromRGB(23, 162, 184),
	},
	Size = {
		Button = UDim2.new(0, 200, 0, 50),
		Title = UDim2.new(1, 0, 0, 100),
	},
	HUD = {
		-- NEW LAYOUT: Top bar with buttons + stats, Bottom bar with controls + content area
		-- Color Scheme: Tundora (#4C3E3E), Don Juan (#5A4E4E), Opium (#8A6A6A), Tan (#C7A67A), Whiskey (#D1945C)

		-- Medieval Styling
		BorderThickness = 2,
		StrokeColor = Color3.fromRGB(199, 166, 122), -- Tan - for ornamental borders
		StrokeThickness = 1.5,
		AccentGold = Color3.fromRGB(218, 165, 32), -- Goldenrod for highlights
		DarkWood = Color3.fromRGB(61, 43, 31), -- Dark wood tone

		-- Top Bar: MENU | STATS (left), Army/Honor/Glory/Date/Gold/Food/Pop (center)
		TopBarHeight = 45,
		TopBarBackground = Color3.fromRGB(90, 78, 78), -- Don Juan
		TopBarBorder = Color3.fromRGB(76, 62, 62), -- Tundora

		-- Bottom Bar: Delete/Policies (stacked) | Minimap | 5 Categories (stacked) | Content Area
		BottomBarHeight = 210,
		BottomBarBackground = Color3.fromRGB(90, 78, 78), -- Don Juan
		BottomBarBorder = Color3.fromRGB(76, 62, 62), -- Tundora

		-- Top Bar Buttons (MENU, STATS)
		TopButtonWidth = 70,
		TopButtonHeight = 35,
		TopButtonBackground = Color3.fromRGB(138, 106, 106), -- Opium
		TopButtonBorder = Color3.fromRGB(76, 62, 62), -- Tundora

		-- Top Bar Stats Display (center)
		StatBoxWidth = 80,
		StatBoxBackground = Color3.fromRGB(76, 62, 62), -- Tundora
		StatBoxBorder = Color3.fromRGB(90, 78, 78), -- Don Juan
		StatTextColor = Color3.fromRGB(199, 166, 122), -- Tan
		StatLabelColor = Color3.fromRGB(209, 148, 92), -- Whiskey

		-- Bottom Bar: Delete/Policies Buttons (stacked, left side)
		UtilityButtonWidth = 50,
		UtilityButtonHeight = 35,
		UtilityButtonBackground = Color3.fromRGB(138, 106, 106), -- Opium
		UtilityButtonBorder = Color3.fromRGB(76, 62, 62), -- Tundora

		-- Minimap (in bottom bar, next to utility buttons)
		MinimapSize = 170,
		MinimapBackground = Color3.fromRGB(76, 62, 62), -- Tundora
		MinimapBorder = Color3.fromRGB(90, 78, 78), -- Don Juan

		-- Category Buttons (5 stacked: Castle, Sword, House, Food, Hammer) - Icon only
		CategoryButtonWidth = 50,
		CategoryButtonHeight = 32,
		CategoryButtonBackground = Color3.fromRGB(138, 106, 106), -- Opium
		CategoryButtonSelected = Color3.fromRGB(209, 148, 92), -- Whiskey
		CategoryButtonBorder = Color3.fromRGB(76, 62, 62), -- Tundora

		-- Content Area (shows buildings or selected units or training)
		ContentAreaBackground = Color3.fromRGB(90, 78, 78), -- Don Juan
		ContentAreaBorder = Color3.fromRGB(76, 62, 62), -- Tundora

		-- Building Buttons (in content area)
		BuildingButtonSize = 70,
		BuildingButtonBackground = Color3.fromRGB(138, 106, 106), -- Opium
		BuildingButtonHover = Color3.fromRGB(199, 166, 122), -- Tan
		BuildingButtonAffordable = Color3.fromRGB(100, 138, 106), -- Green tint
		BuildingButtonUnaffordable = Color3.fromRGB(138, 86, 86), -- Red tint
		BuildingButtonBorder = Color3.fromRGB(76, 62, 62), -- Tundora

		-- Unit Portraits (in content area when units selected)
		UnitPortraitSize = 65,
		UnitPortraitSpacing = 8,
		UnitPortraitBackground = Color3.fromRGB(76, 62, 62), -- Tundora
		UnitPortraitBorder = Color3.fromRGB(138, 106, 106), -- Opium

		-- Training Panel (in content area when training building selected)
		TrainingUnitButtonBackground = Color3.fromRGB(138, 106, 106), -- Opium
		TrainingUnitButtonHover = Color3.fromRGB(199, 166, 122), -- Tan
		TrainingUnitButtonBorder = Color3.fromRGB(76, 62, 62), -- Tundora
		TrainingQueueBackground = Color3.fromRGB(76, 62, 62), -- Tundora
		TrainingQueueBorder = Color3.fromRGB(90, 78, 78), -- Don Juan
		TrainingProgressBar = Color3.fromRGB(209, 148, 92), -- Whiskey

		-- Happiness/Revolt Meter (horizontal bar)
		MeterWidth = 200,
		MeterHeight = 35,
		MeterBackground = Color3.fromRGB(76, 62, 62), -- Tundora
		MeterBorder = Color3.fromRGB(90, 78, 78), -- Don Juan
		MeterHappyColor = Color3.fromRGB(100, 200, 100),
		MeterRevoltColor = Color3.fromRGB(200, 100, 100),

		-- General Colors
		PanelBackground = Color3.fromRGB(90, 78, 78), -- Don Juan
		PanelBorder = Color3.fromRGB(76, 62, 62), -- Tundora
		PanelHeaderColor = Color3.fromRGB(209, 148, 92), -- Whiskey
		PanelTextColor = Color3.fromRGB(199, 166, 122), -- Tan

		-- Formation/Stance Controls
		FormationButtonSize = 50,
		FormationButtonBackground = Color3.fromRGB(138, 106, 106), -- Opium
		FormationButtonBorder = Color3.fromRGB(76, 62, 62), -- Tundora

		-- Resource Display
		ResourceBackgroundColor = Color3.fromRGB(61, 43, 31), -- Dark wood
		ResourceBorderColor = Color3.fromRGB(199, 166, 122), -- Tan border
		ResourceTextColor = Color3.fromRGB(255, 245, 220), -- Warm white
		ResourceIconSize = 18,
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
