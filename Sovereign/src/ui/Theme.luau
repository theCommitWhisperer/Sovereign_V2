--!strict
-- Theme: design tokens for the rebuilt HUD ("direction A" -- modern dark).
--
-- WHY THIS EXISTS SEPARATELY FROM UIConfig
-- ---------------------------------------
-- UIConfig describes the OLD chrome: Don Juan / Opium / Tundora browns, 2px
-- ornamental strokes, a 300px bottom bar sized to fit specific PNG artwork, and
-- fixed pixel positions that only work at desktop aspect ratios. That chrome is
-- exactly what made the HUD impossible to lay out for touch -- the images have
-- fixed proportions and cannot reflow.
--
-- This is the replacement vocabulary: flat translucent surfaces drawn with
-- Frames rather than ImageLabels, one accent colour, and sizes expressed as
-- tokens so the two shells can differ in layout without differing in look.
--
-- UIConfig is deliberately left intact -- the lobby, main menu, settings and map
-- editor still use it. This module only governs the in-match HUD.

local Theme = {}

-- ============================================================
-- COLOUR
--
-- ONE accent. Gold marks exactly four things: the active category, the
-- placement ghost, the current selection, and production output. Using it for
-- anything else is what made the first pass read as generic decoration rather
-- than signal.
-- ============================================================
Theme.Color = {
	-- Surfaces. Translucency is carried in the matching *Transparency values
	-- below, because Roblox has no alpha channel on Color3.
	Surface = Color3.fromRGB(22, 18, 12), -- deep peat brown
	SurfaceRaised = Color3.fromRGB(35, 28, 18), -- warm wood brown
	Overlay = Color3.fromRGB(255, 255, 255), -- used at high transparency as a wash

	Accent = Color3.fromRGB(212, 175, 55), -- Celtic gold
	AccentMuted = Color3.fromRGB(140, 115, 36), -- aged gold
	OnAccent = Color3.fromRGB(20, 14, 6), -- text on gold fill

	-- Celtic Irish greens for action buttons and military accents
	Action = Color3.fromRGB(34, 85, 52), -- deep Irish green
	ActionHover = Color3.fromRGB(56, 128, 72), -- brighter Irish green
	CelticGreen = Color3.fromRGB(34, 85, 52), -- alias for thematic access
	CelticGreenBright = Color3.fromRGB(56, 128, 72),

	TextPrimary = Color3.fromRGB(244, 235, 216), -- warm parchment white
	TextSecondary = Color3.fromRGB(186, 172, 148),
	TextMuted = Color3.fromRGB(150, 137, 118),

	Danger = Color3.fromRGB(240, 149, 149),
	Success = Color3.fromRGB(56, 128, 72), -- Irish green: allied, ready, output
	Warning = Color3.fromRGB(212, 175, 55), -- gold warning

	Border = Color3.fromRGB(212, 175, 55), -- Celtic gold borders
}

-- Per-resource colours so a glance at the top strip is readable without labels.
Theme.ResourceColor = {
	Wood = Color3.fromRGB(159, 225, 203),
	Stone = Color3.fromRGB(180, 178, 169),
	Gold = Color3.fromRGB(239, 159, 39),
	Food = Color3.fromRGB(245, 196, 179),
	Grain = Color3.fromRGB(250, 199, 117),
	Bread = Color3.fromRGB(245, 196, 179),
	Ale = Color3.fromRGB(250, 199, 117),
	Iron_Ore = Color3.fromRGB(180, 178, 169),
	Iron_Bars = Color3.fromRGB(133, 183, 235),
	Weapons = Color3.fromRGB(240, 149, 149),
	Hide = Color3.fromRGB(200, 170, 140),
	Leather = Color3.fromRGB(200, 170, 140),
	Coal = Color3.fromRGB(140, 140, 140),
	Flour = Color3.fromRGB(230, 220, 200),
	Vellum = Color3.fromRGB(230, 220, 200),
	Furniture = Color3.fromRGB(200, 170, 140),
	Manuscripts = Color3.fromRGB(206, 203, 246),
	Fish = Color3.fromRGB(133, 183, 235),
	Default = Color3.fromRGB(200, 198, 190),
}

function Theme.resourceColor(resource: string): Color3
	return Theme.ResourceColor[resource] or Theme.ResourceColor.Default
end

-- ============================================================
-- TRANSPARENCY
-- Flat translucent panels over the world, rather than opaque artwork.
-- ============================================================
Theme.Transparency = {
	Panel = 0.32,
	Card = 0.82,
	CardActive = 0.62,
	Drawer = 0.18,
	Border = 0.82,
	BorderStrong = 0.62,
	Ghost = 0.8,

	ScreenScrim = 0.25,
	ScreenPanel = 0.06,
	ScreenCard = 0.14,
	ScreenCardActive = 0.0,
}

-- ============================================================
-- TYPE
-- ============================================================
Theme.FontFace = {
	Display = Font.new("rbxasset://fonts/families/Fondamento.json"),
	Body = Font.new("rbxasset://fonts/families/Fondamento.json"),
	BodyBold = Font.new("rbxasset://fonts/families/Fondamento.json", Enum.FontWeight.SemiBold),
	Number = Font.new("rbxasset://fonts/families/RobotoMono.json"),
}

Theme.TextSize = {
	Caption = 16,
	Small = 18,
	Body = 20,
	Heading = 24,
	Title = 30,

	ScreenCaption = 17,
	ScreenSmall = 19,
	ScreenBody = 22,
	ScreenHeading = 26,
	ScreenTitle = 34,
}

-- ============================================================
-- METRICS
-- ============================================================
Theme.Metrics = {
	Radius = 8,
	RadiusSmall = 6,
	RadiusCard = 8,

	TouchTarget = 44,
	DesktopTarget = 36,

	GapTight = 5,
	Gap = 8,
	GapLoose = 12,

	PadTight = 6,
	Pad = 10,
	PadLoose = 14,

	TopSafeZone = 60,
	MinimapMobile = 64,
	MinimapDesktop = 180,

	DrawerMaxHeight = 330,
	CategoryRailHeight = 46,
	ActionBarHeight = 56,

	BottomBarDesktop = 220,
	BottomBarLeftCol = 200,
	BottomBarRightCol = 120,
	CategoryTabHeight = 48,
	CommandBarHeight = 60,
	BuildTileWidth = 160,
	BuildTileHeight = 150,
}

-- ============================================================
-- HELPERS
-- ============================================================

--- Standard stroke for a panel edge. Explicitly sets ApplyStrokeMode to Border so text is never stroked.
function Theme.strokeProps(strong: boolean?)
	return {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Theme.Color.Border,
		Transparency = strong and Theme.Transparency.BorderStrong or Theme.Transparency.Border,
		Thickness = strong and 2 or 1.5,
	}
end

--- Thicker gold Celtic border for prominent panels. Explicitly sets ApplyStrokeMode to Border.
function Theme.celticStrokeProps()
	return {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Theme.Color.Accent,
		Transparency = 0.15,
		Thickness = 2.5,
	}
end

function Theme.corner(radius: number?)
	return UDim.new(0, radius or Theme.Metrics.Radius)
end

Theme.MenuBackgroundImage = "rbxassetid://99876577284469"

return Theme
