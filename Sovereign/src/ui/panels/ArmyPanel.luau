--!strict
-- ArmyPanel: what you get when units are selected.
--
-- WHY THIS IS NOT SHAPED LIKE THE BUILDING PANEL
-- ----------------------------------------------
-- A selected building has one identity and one job, so its panel is a readout.
-- A selection is a heterogeneous GROUP -- 12 pikemen, 4 archers and a stray
-- peasant -- and the useful questions are "what have I actually got" and "how
-- should they fight", neither of which the building panel's shape answers.
--
-- The old UnitSelectionPanel listed stance and formation names as bare buttons.
-- That has the same flaw the old build menu had: "Schiltron" tells you nothing
-- unless you already know the game. Both pickers here show their real numeric
-- tradeoff, read from the authoritative config (CombatConfig.StanceModifiers
-- and FormationsData) rather than re-typed, so tuning the balance updates the UI.
--
-- Formations are also gated on unit count. A formation whose minUnits you have
-- not met is shown greyed WITH the requirement, rather than hidden or silently
-- ignored -- the same "say why it is unavailable" rule the build cards follow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local FormationsData = require(ReplicatedStorage.Shared.GameData.FormationsData)

export type Props = {
	selectedUnits: { Model },
	selectedStance: string,
	selectedFormation: string,
	onStanceSelected: (string) -> (),
	onFormationSelected: (string) -> (),
	onCivilianOrder: ((string) -> ())?,
	compact: boolean?, -- mobile: fewer columns, bigger targets
	LayoutOrder: number?,
}

-- Ordered so the list reads as a spectrum from passive to committed, which is
-- also roughly the order a player escalates through.
local STANCE_ORDER = { "March", "Defend", "Skirmish", "Attack" }

local STANCE_BLURB: { [string]: string } = {
	March = "travel together, don't engage",
	Attack = "seek out and charge enemies",
	Defend = "hold ground, return to post",
	Skirmish = "engage but keep distance",
}

--- "+25% dmg / -15% def" from the real modifier table. Reads as a tradeoff
--- rather than two absolute numbers, because that is the actual decision.
local function stanceTradeoff(stance: string): string
	local mod = (CombatConfig.StanceModifiers :: any)[stance]
	if not mod then
		return ""
	end
	local function pct(v: number): string
		local delta = math.round((v - 1) * 100)
		if delta == 0 then
			return "0%"
		end
		return (delta > 0 and "+" or "") .. delta .. "%"
	end
	return ("%s dmg  %s def"):format(pct(mod.damage), pct(mod.defense))
end

local function formationTradeoff(name: string): string
	local cfg = FormationsData.get(name)
	if not cfg or not cfg.bonuses then
		return ""
	end
	local b = cfg.bonuses
	local parts = {}
	for label, value in { atk = b.attack, def = b.defense, spd = b.speed } do
		local delta = math.round((value - 1) * 100)
		if delta ~= 0 then
			table.insert(parts, ("%s%d%% %s"):format(delta > 0 and "+" or "", delta, label))
		end
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, "  ") or "no modifiers"
end

--- Counts by UnitType so the player can see composition at a glance. Falls back
--- to the model name when the attribute is missing, which is what happens to a
--- worker mid-transform.
local function composition(units: { Model }): ({ { kind: string, count: number } }, number)
	local counts: { [string]: number } = {}
	local total = 0
	for _, unit in units do
		if unit and unit.Parent then
			local kind = unit:GetAttribute("UnitType") :: string?
			kind = kind or unit.Name
			counts[kind] = (counts[kind] or 0) + 1
			total += 1
		end
	end
	local out = {}
	for kind, count in counts do
		table.insert(out, { kind = kind, count = count })
	end
	table.sort(out, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.kind < b.kind
	end)
	return out, total
end

local function chip(text: string, order: number)
	return React.createElement("TextLabel", {
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = Theme.Transparency.Card,
		Text = "  " .. text .. "  ",
		FontFace = Theme.FontFace.Body,
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Color.TextSecondary,
		LayoutOrder = order,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
	})
end

--- One picker row. `sublabel` is the tradeoff text; `blocked` renders the entry
--- inert and swaps the tradeoff for the reason.
local function optionButton(
	name: string,
	sublabel: string,
	active: boolean,
	blocked: string?,
	height: number,
	order: number,
	onClick: () -> ()
)
	local enabled = blocked == nil
	return React.createElement("TextButton", {
		Name = name,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = if active then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if active then 0 else Theme.Transparency.Card,
		AutoButtonColor = enabled,
		Text = "",
		LayoutOrder = order,
		Active = enabled,
		[React.Event.Activated] = enabled and onClick or nil,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
		Stroke = React.createElement("UIStroke", {
			Color = if active then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if active then 0 else Theme.Transparency.Border,
			Thickness = 1,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Label = React.createElement("TextLabel", {
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = name,
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.Body,
			TextColor3 = if not enabled
				then Theme.Color.TextMuted
				elseif active then Theme.Color.OnAccent
				else Theme.Color.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Detail = React.createElement("TextLabel", {
			Size = UDim2.new(0.5, 0, 1, 0),
			Position = UDim2.fromScale(0.5, 0),
			BackgroundTransparency = 1,
			Text = blocked or sublabel,
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.Caption,
			TextColor3 = if blocked
					then Theme.Color.Danger
					elseif active then Theme.Color.OnAccent
					else Theme.Color.Success,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	})
end

local function sectionLabel(text: string, order: number)
	return React.createElement("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = text,
		FontFace = Theme.FontFace.BodyBold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
	})
end

local function ArmyPanel(props: Props)
	local units = props.selectedUnits or {}
	local breakdown, total = composition(units)

	local rowHeight = if props.compact then Theme.Metrics.TouchTarget else Theme.Metrics.DesktopTarget + 6

	local children: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.Pad),
			PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
	}
	local order = 0

	-- COMPOSITION. The one thing the old panel got right was showing a count;
	-- this shows the breakdown, because "18 units" and "18 archers" are very
	-- different tactical situations.
	order += 1
	children.Header = React.createElement("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = ("%d unit%s selected"):format(total, total == 1 and "" or "s"),
		FontFace = Theme.FontFace.Display,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
	})

	order += 1
	local chips: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Wraps = true,
		}),
	}
	for i, entry in breakdown do
		chips[entry.kind] = chip(("%s x%d"):format(entry.kind, entry.count), i)
	end
	children.Composition = React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, chips)

	-- STANCE
	order += 1
	children.StanceLabel = sectionLabel("Stance", order)
	for _, stance in STANCE_ORDER do
		order += 1
		children["Stance" .. stance] = optionButton(
			stance,
			stanceTradeoff(stance),
			props.selectedStance == stance,
			nil,
			rowHeight,
			order,
			function()
				props.onStanceSelected(stance)
			end
		)
	end

	-- FORMATION. Scrolls, because ten formations will not fit a mobile detail
	-- area and truncating the list would hide the interesting ones.
	order += 1
	children.FormationLabel = sectionLabel("Formation", order)

	local formationChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, name in FormationsData.Order do
		local cfg = FormationsData.get(name)
		local minUnits = (cfg and cfg.minUnits) or 1
		local blocked: string? = nil
		if total < minUnits then
			blocked = ("needs %d"):format(minUnits)
		end
		formationChildren[name] = optionButton(
			name,
			formationTradeoff(name),
			props.selectedFormation == name,
			blocked,
			rowHeight,
			i,
			function()
				props.onFormationSelected(name)
			end
		)
	end

	order += 1
	children.Formations = React.createElement("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -(rowHeight * 5 + 92)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromScale(0, 0),
		LayoutOrder = order,
	}, formationChildren)

	-- CIVILIAN ORDERS. Only when the selection actually contains workers --
	-- showing "return to keep" for a pure cavalry selection is noise.
	local hasCivilian = false
	for _, entry in breakdown do
		if entry.kind == "Peasant" or entry.kind == "Ox" then
			hasCivilian = true
			break
		end
	end
	local civilianOrder = props.onCivilianOrder
	if hasCivilian and civilianOrder then
		order += 1
		children.CivilianLabel = sectionLabel("Workers", order)
		order += 1
		children.ReturnToKeep = optionButton(
			"Return to Keep",
			"unassign and go home",
			false,
			nil,
			rowHeight,
			order,
			function()
				civilianOrder("ReturnToKeep")
			end
		)
	end

	return React.createElement("Frame", {
		Name = "ArmyPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = Theme.Transparency.Drawer,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
		Stroke = React.createElement("UIStroke", Theme.strokeProps()),
		Content = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, children),
	})
end

return ArmyPanel
