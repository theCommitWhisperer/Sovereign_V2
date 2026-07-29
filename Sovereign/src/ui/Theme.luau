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
	Surface = Color3.fromRGB(15, 19, 25), -- panel/base
	SurfaceRaised = Color3.fromRGB(22, 28, 36), -- drawer, cards
	Overlay = Color3.fromRGB(255, 255, 255), -- used at high transparency as a wash

	Accent = Color3.fromRGB(239, 159, 39), -- gold
	AccentMuted = Color3.fromRGB(160, 106, 26),
	Action = Color3.fromRGB(24, 95, 165), -- primary buttons (assign, confirm)

	TextPrimary = Color3.fromRGB(240, 237, 230),
	TextSecondary = Color3.fromRGB(169, 167, 160),
	TextMuted = Color3.fromRGB(141, 139, 132),

	Danger = Color3.fromRGB(240, 149, 149),
	Success = Color3.fromRGB(159, 225, 203),
	Warning = Color3.fromRGB(239, 159, 39),

	Border = Color3.fromRGB(255, 255, 255), -- at BorderTransparency
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
	Panel = 0.08, -- top strip, action bar
	Card = 0.94, -- building cards: a faint wash over the world
	CardActive = 0.86,
	Drawer = 0.04, -- must be readable while scrolling a list
	Border = 0.9,
	BorderStrong = 0.75,
	Ghost = 0.88, -- placement preview fill
}

-- ============================================================
-- TYPE
-- Two weights only. Fondamento (the game's display face) is kept for headings
-- so the HUD still reads as Sovereign, but body/data uses a plain face because
-- Fondamento is genuinely hard to read at 11-12px on a phone.
-- ============================================================
Theme.Font = {
	Display = Font.new("rbxasset://fonts/families/Fondamento.json"),
	Body = Font.new("rbxasset://fonts/families/SourceSansPro.json"),
	BodyBold = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold),
	Number = Font.new("rbxasset://fonts/families/RobotoMono.json"),
}

Theme.TextSize = {
	Caption = 11,
	Small = 12,
	Body = 13,
	Heading = 15,
	Title = 18,
}

-- ============================================================
-- METRICS
--
-- Mobile hit targets are 44px minimum. That single constraint is why the old
-- bar could not be adapted: its PNG buttons are 57px wide but stacked into a
-- fixed 300px strip that assumed a landscape desktop viewport.
-- ============================================================
Theme.Metrics = {
	Radius = 8,
	RadiusSmall = 6,
	RadiusCard = 8,

	TouchTarget = 44,
	DesktopTarget = 30,

	GapTight = 5,
	Gap = 8,
	GapLoose = 12,

	PadTight = 6,
	Pad = 10,
	PadLoose = 14,

	-- Mobile: nothing interactive may sit above this line.
	TopSafeZone = 60,
	MinimapMobile = 64,
	MinimapDesktop = 84,

	DrawerMaxHeight = 330,
	CategoryRailHeight = 46,
	ActionBarHeight = 46,
}

-- ============================================================
-- HELPERS
-- ============================================================

--- Standard stroke for a panel edge. Returned as props rather than an
--- instance so callers stay declarative.
function Theme.strokeProps(strong: boolean?)
	return {
		Color = Theme.Color.Border,
		Transparency = strong and Theme.Transparency.BorderStrong or Theme.Transparency.Border,
		Thickness = 1,
	}
end

function Theme.corner(radius: number?)
	return UDim.new(0, radius or Theme.Metrics.Radius)
end

return Theme
