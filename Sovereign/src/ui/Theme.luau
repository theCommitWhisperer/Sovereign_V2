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
	--
	-- Lightened from 15,19,25. Combined with the near-opaque panel transparency
	-- this used to read as a solid black slab across the bottom third of the
	-- screen -- the world behind it was completely hidden, which is the opposite
	-- of what a translucent overlay is for.
	Surface = Color3.fromRGB(32, 28, 24), -- panel/base: peat, not slate
	SurfaceRaised = Color3.fromRGB(45, 39, 33), -- drawer, cards
	Overlay = Color3.fromRGB(255, 255, 255), -- used at high transparency as a wash

	Accent = Color3.fromRGB(239, 159, 39), -- gold
	AccentMuted = Color3.fromRGB(160, 106, 26),
	-- Text and icons drawn ON a gold fill. Selected controls were using Accent
	-- for BOTH the background and the label, which is gold on gold -- legible
	-- only because the fill happened to be semi-transparent, and not legible at
	-- all once it wasn't. Anything sitting on Accent uses this.
	OnAccent = Color3.fromRGB(26, 18, 4),
	Action = Color3.fromRGB(24, 95, 165), -- primary buttons (assign, confirm)

	TextPrimary = Color3.fromRGB(244, 235, 216), -- warm parchment white
	TextSecondary = Color3.fromRGB(186, 172, 148),
	TextMuted = Color3.fromRGB(150, 137, 118),

	Danger = Color3.fromRGB(240, 149, 149),
	Success = Color3.fromRGB(143, 196, 122), -- Irish green: allied, ready, output
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
-- These were far too opaque. Panel at 0.08 is 92% solid, which turned the HUD
-- into black bars rather than glass over the battlefield. An RTS overlay has to
-- let you see the ground it covers, otherwise the playable viewport is only
-- whatever is left in the middle.
Theme.Transparency = {
	Panel = 0.32, -- top strip, bottom bar: glass, not a slab
	Card = 0.82, -- building tiles: a faint wash
	CardActive = 0.62,
	Drawer = 0.18, -- denser than Panel: it holds a scrolling list that must stay legible
	Border = 0.82,
	BorderStrong = 0.62,
	Ghost = 0.8, -- placement preview fill

	-- ============================================================
	-- FULL-SCREEN MENUS (lobby, settings, post-game)
	--
	-- These are DELIBERATELY far more opaque than the in-match values above, and
	-- the distinction matters. The HUD is translucent because it sits over live
	-- gameplay you need to keep seeing -- translucency there is the point. A
	-- menu has no battlefield behind it, only a static backdrop image, so the
	-- same values buy nothing and cost legibility.
	--
	-- Applying Panel/Card to the lobby is exactly what made it unreadable:
	-- panels at 68% transparent over a fully transparent root, so text was
	-- competing with whatever happened to be behind the screen.
	-- ============================================================
	ScreenScrim = 0.25, -- darkens the backdrop image so text can sit on it
	ScreenPanel = 0.06, -- a menu card: essentially solid
	ScreenCard = 0.14, -- a row/slot inside a menu card
	ScreenCardActive = 0.0,
}

-- ============================================================
-- TYPE
--
-- NAMED FontFace, NOT Font, DELIBERATELY.
-- TextLabel has two separate properties: `Font` takes an Enum.Font, and
-- `FontFace` takes a Font object. Font.new(...) produces the latter, so
-- assigning it to `Font` throws "EnumItem, number, or string expected, got
-- Font" at render time. That happened in 37 places here, and 37 more in the
-- legacy screens which had the same confusion against UIConfig -- those errors
-- were already being thrown before this rebuild, they were just lost in the
-- noise. Naming the table FontFace makes the only correct assignment
-- (`FontFace = Theme.FontFace.Body`) read naturally and the broken one read
-- obviously wrong.
--
-- Two weights only. Fondamento (the game's display face) is kept for headings
-- so the HUD still reads as Sovereign, but body/data uses a plain face because
-- Fondamento is genuinely hard to read at 11-12px on a phone.
-- ============================================================
Theme.FontFace = {
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

	-- Full-screen menus read LARGER than the HUD, for the same reason they are
	-- more opaque. 11px is defensible for overlay data you glance at mid-battle
	-- with the whole screen as context; it is not defensible for a lobby you sit
	-- and read, and it was the main reason the lobby text was hard to make out
	-- (13 of its labels were at Caption).
	ScreenCaption = 13,
	ScreenSmall = 14,
	ScreenBody = 15,
	ScreenHeading = 17,
	ScreenTitle = 22,
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

	-- Mobile drawer. Tall is acceptable here: the drawer is transient, you open
	-- it to choose a building and it closes again.
	DrawerMaxHeight = 330,
	CategoryRailHeight = 46,
	ActionBarHeight = 46,

	-- Desktop bottom bar. DELIBERATELY MUCH SHORTER than the mobile drawer.
	-- It was originally reusing DrawerMaxHeight (330px), but unlike the drawer
	-- this bar is permanently on screen -- 330px is a third of a 1080p display
	-- given up forever. The build grid is a compact single scrolling row instead
	-- of a multi-row wall of large tiles.
	BottomBarDesktop = 164,
	BuildTileWidth = 132,
	BuildTileHeight = 116,
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

-- The shared backdrop for full-screen menus. MainMenu owns this asset; the
-- lobby and post-game screens reference it here so the whole out-of-match flow
-- is visibly one place rather than three unrelated screens.
Theme.MenuBackgroundImage = "rbxassetid://99876577284469"

return Theme
