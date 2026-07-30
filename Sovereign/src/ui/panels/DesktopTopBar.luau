--!strict
-- DesktopTopBar: the single-row status strip across the top of the desktop HUD.
--
-- Replaces screens/HUD/TopBar.luau, which was an ImageLabel stretched over a
-- fixed-proportion PNG (rbxassetid://71446311211523) with every stat hardcoded
-- to a pixel offset inside it -- exactly the chrome this rebuild is required to
-- throw away. This is flat Theme-token Frames instead, sized by AutomaticSize
-- so it holds together at any aspect ratio rather than only the one the PNG was
-- drawn for.
--
-- Self-sufficient: reads HUDStore directly rather than taking two dozen props
-- from DesktopShell, and its four utility buttons are the first working way to
-- reach the Menu/Stats/TechTree modals on desktop -- the legacy DesktopShell
-- wired their onClose handlers but never mounted a button that could open them
-- (showMenuModal/showStatsModal/showTechTreeModal could only ever be set by
-- MobileShell). Policies and AbilityTree already had desktop buttons in the old
-- bottom bar; AbilityTree's button moves to DesktopBuildingGrid's rail instead,
-- since the spec for this row names exactly four buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(game.ReplicatedStorage.Packages.react)
local ResourcesData = require(ReplicatedStorage.Shared.GameData.ResourcesData)

local Theme = require(script.Parent.Parent.Theme)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

-- Fixed order so the strip doesn't reshuffle as values change (a plain `pairs`
-- over the resources table would).
local RESOURCE_ORDER = { "Wood", "Stone", "Gold", "Food", "Weapons", "Iron_Bars" }

local WEATHER_ICON: { [string]: string } = {
	Clear = "☀️",
	Rain = "🌧️",
	Storm = "⛈️",
	Drought = "🌵",
}

local VICTORY_ICON: { [string]: string } = {
	Score = "🏆",
	Conquest = "⚔️",
	Wonder = "🏛",
	Regicide = "👑",
}

local function statusChip(text: string, color: Color3, layoutOrder: number)
	return React.createElement("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		FontFace = Theme.FontFace.Body,
		TextSize = Theme.TextSize.Body,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = layoutOrder,
	})
end

local function utilityButton(icon: string, active: boolean, layoutOrder: number, onClick: () -> ())
	return React.createElement("TextButton", {
		Size = UDim2.fromOffset(Theme.Metrics.DesktopTarget + 16, Theme.Metrics.DesktopTarget),
		BackgroundColor3 = if active then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if active then Theme.Transparency.CardActive else Theme.Transparency.Card,
		AutoButtonColor = true,
		Text = icon,
		FontFace = Theme.FontFace.Body,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = if active then Theme.Color.OnAccent else Theme.Color.TextPrimary,
		LayoutOrder = layoutOrder,
		[React.Event.Activated] = onClick,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", Theme.strokeProps()),
	})
end

local function DesktopTopBar()
	local resources = HUDStore.useHUDState(function(s)
		return s.resources
	end)
	local population = HUDStore.useHUDState(function(s)
		return s.population
	end)
	local happiness = HUDStore.useHUDState(function(s)
		return s.happiness
	end)
	local armySize = HUDStore.useHUDState(function(s)
		return s.armySize
	end)
	local date = HUDStore.useHUDState(function(s)
		return s.date
	end)
	local weather = HUDStore.useHUDState(function(s)
		return s.weather
	end)
	local peaceTimeRemaining = HUDStore.useHUDState(function(s)
		return s.peaceTimeRemaining
	end)
	local victoryCondition = HUDStore.useHUDState(function(s)
		return s.victoryCondition
	end)
	local gameStartData = HUDStore.useHUDState(function(s)
		return s.gameStartData
	end)
	local showMenuModal = HUDStore.useHUDState(function(s)
		return s.showMenuModal
	end)
	local showStatsModal = HUDStore.useHUDState(function(s)
		return s.showStatsModal
	end)
	local showPoliciesModal = HUDStore.useHUDState(function(s)
		return s.showPoliciesModal
	end)
	local showTechTreeModal = HUDStore.useHUDState(function(s)
		return s.showTechTreeModal
	end)

	-- Battle Arena has no economy: hiding the whole strip matches the legacy
	-- TopBar's `not isArenaMode and ...` gate in DesktopShell.
	local isArenaMode = gameStartData ~= nil and gameStartData.mode == "BattleArena"
	if isArenaMode then
		return nil
	end

	local happinessColor = if happiness >= 66
		then Theme.Color.Success
		elseif happiness >= 33 then Theme.Color.Warning
		else Theme.Color.Danger

	local leftChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Theme.Metrics.GapLoose),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	local order = 0
	for _, resourceName in RESOURCE_ORDER do
		order += 1
		local data = ResourcesData.get(resourceName)
		local icon = (data and data.icon) or "•"
		local amount = resources[resourceName] or 0
		leftChildren[resourceName] = statusChip(
			string.format("%s %d", icon, amount),
			Theme.resourceColor(resourceName),
			order
		)
	end

	order += 1
	leftChildren.Population = statusChip(string.format("👥 %d", population), Theme.Color.TextPrimary, order)

	order += 1
	leftChildren.Happiness = statusChip(string.format("💗 %d%%", math.floor(happiness)), happinessColor, order)

	order += 1
	leftChildren.ArmySize = statusChip(string.format("🎖 %d", armySize), Theme.Color.TextPrimary, order)

	order += 1
	leftChildren.Season = statusChip(
		string.format("%s %s", WEATHER_ICON[weather] or "☀️", date),
		Theme.Color.TextSecondary,
		order
	)

	if peaceTimeRemaining > 0 then
		order += 1
		leftChildren.PeaceTimer = statusChip(
			string.format("🕊 %d:%02d", math.floor(peaceTimeRemaining / 60), peaceTimeRemaining % 60),
			Theme.Color.Success,
			order
		)
	end

	order += 1
	leftChildren.Victory = statusChip(
		string.format("%s %s", VICTORY_ICON[victoryCondition] or "🏆", victoryCondition),
		Theme.Color.Accent,
		order
	)

	return React.createElement("Frame", {
		Name = "DesktopTopBar",
		Size = UDim2.new(1, 0, 0, Theme.Metrics.ActionBarHeight),
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = Theme.Transparency.Panel,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		Stroke = React.createElement("UIStroke", Theme.strokeProps()),

		LeftCluster = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, Theme.Metrics.Pad, 0.5, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
		}, leftChildren),

		RightCluster = React.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Theme.Metrics.Pad, 0.5, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Theme.Metrics.Gap),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Menu = utilityButton("☰", showMenuModal, 1, function()
				HUDStore.setMenuModal(not showMenuModal)
			end),
			Stats = utilityButton("🏰", showStatsModal, 2, function()
				HUDStore.setStatsModal(not showStatsModal)
			end),
			Policies = utilityButton("📜", showPoliciesModal, 3, function()
				HUDStore.togglePoliciesModal()
			end),
			TechTree = utilityButton("🔬", showTechTreeModal, 4, function()
				HUDStore.setTechTreeModal(not showTechTreeModal)
			end),
		}),
	})
end

return DesktopTopBar
