--!strict
-- PlayerList: the lobby roster. Every slot must answer, at a glance, who this
-- is, whether it's you, whether it's AI, whether they're ready, and what
-- faction/colour/spawn they picked -- see the Lobby rebuild brief. `maxPlayers`
-- (the map's real capacity) still bounds the flat free-for-all view's empty
-- "Add AI" invitations, but a non-FFA layout instead sizes and groups its
-- slots off `teamLayout` (TeamLayoutsData) -- a 2v2 shows exactly 4 slots
-- split into two headed pairs regardless of how many spawns the map has.
--
-- TEAM GROUPING: TeamLayoutsData.isFreeForAll gates it -- four headers each
-- holding one player would be noise for a genuine free-for-all, so that case
-- keeps the old flat, sorted list. Everything else groups by team with a
-- header, slots rendered in the layout's own order so a 2v2 reads as two
-- pairs, not four independent cards.
--
-- INTERACTIVE VS READ-ONLY: only the LOCAL player's card exposes faction and
-- colour pickers. Other players' cards show the same data as plain chips --
-- SelectFaction/SelectColor only ever target the requester on the server
-- (LobbyManager.selectFaction takes an explicit targetUserId, but nothing in
-- this UI exposes picking on someone else's behalf), so offering controls on
-- another player's card would be furniture that does nothing.
--
-- GOLD = "this is mine / active", not "success". Ready and "you" both use
-- Theme.Color.Accent per the rebuild's colour rule; taken/blocked options use
-- TextMuted, not Danger -- being unavailable isn't an error state.

local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.Parent.Parent.Theme)

-- Big enough to hit comfortably and to read as a colour rather than a pixel.
-- Big enough to hit comfortably and to read as a colour rather than a pixel.
local SWATCH = 28
-- The local player's swatch doubles as the colour dropdown trigger and carries a
-- caret inside it, so it needs to be bigger than a decorative dot.
local SWATCH_TRIGGER = 30
local TeamLayoutsData = require(ReplicatedStorage.Shared.GameData.TeamLayoutsData)

export type PlayerEntry = {
	userId: number,
	name: string,
	isAI: boolean,
	isReady: boolean,
	faction: string?,
	selectedColor: { number }?,
	teamIndex: number?,
}

export type SpawnSelection = {
	userId: number,
	name: string,
}

export type Props = {
	players: { PlayerEntry },
	maxPlayers: number,
	teamLayout: string,
	localPlayerId: number,
	spawnSelections: { [number]: SpawnSelection },
	onAddAI: () -> (),
	onRemovePlayer: (PlayerEntry) -> (),
	onSelectFaction: (string, number?) -> (),
	onSelectColor: ({ number }) -> (),
	compact: boolean,
	LayoutOrder: number?,
}

local FACTIONS = { "Kingdom", "Empire", "Tribes", "IronLegion" }

local COLOR_OPTIONS: { { r: number, g: number, b: number, name: string } } = {
	{ r = 70, g = 130, b = 200, name = "Blue" },
	{ r = 200, g = 70, b = 70, name = "Red" },
	{ r = 70, g = 180, b = 70, name = "Green" },
	{ r = 200, g = 180, b = 50, name = "Yellow" },
	{ r = 180, g = 80, b = 200, name = "Purple" },
	{ r = 220, g = 130, b = 50, name = "Orange" },
	{ r = 80, g = 200, b = 200, name = "Cyan" },
	{ r = 200, g = 100, b = 150, name = "Pink" },
	{ r = 255, g = 255, b = 255, name = "White" },
	{ r = 120, g = 120, b = 120, name = "Gray" },
	{ r = 160, g = 100, b = 60, name = "Brown" },
	{ r = 50, g = 200, b = 130, name = "Teal" },
}

local function colorsEqual(a: { number }?, r: number, g: number, b: number): boolean
	return a ~= nil and a[1] == r and a[2] == g and a[3] == b
end

--- One faction/colour pick chip. `takenBy` renders it inert and names the
--- reason -- same "say why it's unavailable" rule DesktopBuildingGrid's
--- locked tiles and ArmyPanel's blocked formations use.
--- A colour choice as a swatch, not a labelled chip.
---
--- Twelve chips each spelling out "Blue" / "Cyan" / "Teal" wrapped into several
--- rows and was a large part of why the roster column swallowed the screen. The
--- colour IS the label, so a grid of squares carries the same information in one
--- row. Blocked colours get a dimmed swatch plus a stroke, and the owner's name
--- stays reachable through the instance name for a future tooltip.
--- Picks a caret colour that survives whatever swatch it sits on. A light arrow
--- disappears on yellow and a dark one disappears on navy, so choose by the
--- swatch's own perceived brightness rather than picking one and hoping.
local function contrastOn(colour: Color3): Color3
	local luminance = 0.299 * colour.R + 0.587 * colour.G + 0.114 * colour.B
	return if luminance > 0.55 then Color3.fromRGB(20, 16, 10) else Color3.fromRGB(250, 246, 236)
end

local function colorSwatch(name: string, r: number, g: number, b: number, mine: boolean, takenBy: string?, order: number, onClick: () -> ())
	local blocked = takenBy ~= nil
	return React.createElement("TextButton", {
		Name = if blocked then `{name} (taken by {takenBy})` else name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(SWATCH, SWATCH),
		BackgroundColor3 = Color3.fromRGB(r, g, b),
		BackgroundTransparency = if blocked then 0.6 else 0,
		AutoButtonColor = not blocked,
		Text = "",
		Active = not blocked,
		[React.Event.Activated] = if blocked then nil else onClick,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		-- Gold ring marks yours; a plain hairline keeps dark swatches visible
		-- against a dark card.
		Stroke = React.createElement("UIStroke", {
			Color = if mine then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if mine then 0 else Theme.Transparency.Border,
			Thickness = if mine then 2 else 1,
		}),
	})
end

local function pickChip(label: string, mine: boolean, takenBy: string?, swatch: Color3?, order: number, onClick: () -> ())
	local blocked = takenBy ~= nil
	local children: { [string]: any } = {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", {
			Color = if mine then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if mine then 0 else Theme.Transparency.Border,
			Thickness = 1,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Label = React.createElement("TextLabel", {
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = if takenBy then `{label} · {takenBy}` else label,
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.ScreenCaption,
			TextColor3 = if blocked then Theme.Color.TextMuted elseif mine then Theme.Color.OnAccent else Theme.Color.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	}
	if swatch then
		children.Swatch = React.createElement("Frame", {
			LayoutOrder = 1,
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = swatch,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		})
	end

	return React.createElement("TextButton", {
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, Theme.Metrics.DesktopTarget),
		BackgroundColor3 = if mine then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if mine then 0 else Theme.Transparency.ScreenCard,
		AutoButtonColor = false,
		Active = not blocked,
		Text = "",
		[React.Event.Activated] = if blocked then nil else onClick,
	}, children)
end

local function readyPill(isReady: boolean, order: number)
	return React.createElement("TextLabel", {
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = if isReady then "● Ready" else "Not ready",
		FontFace = Theme.FontFace.BodyBold,
		TextSize = Theme.TextSize.ScreenCaption,
		TextColor3 = if isReady then Theme.Color.Accent else Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
end

-- `expanded` gates the faction/colour pickers and the spawn line. Those were
-- always visible on the local player's card and were most of the roster's
-- height; you set your kingdom once, so they collapse behind a toggle.
local function playerCard(entry: PlayerEntry, isLocal: boolean, spawnLabel: string, allPlayers: { PlayerEntry }, props: Props, order: number, expanded: boolean, onToggle: () -> (), colorOpen: boolean, onToggleColor: () -> ())
	local swatch = if entry.selectedColor
		then Color3.fromRGB(entry.selectedColor[1], entry.selectedColor[2], entry.selectedColor[3])
		else Theme.Color.TextMuted

	local children: { [string]: any } = {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
		Stroke = React.createElement("UIStroke", {
			Color = if isLocal then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if isLocal then Theme.Transparency.BorderStrong else Theme.Transparency.Border,
			Thickness = if isLocal then 2 else 1,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.PadTight),
			PaddingBottom = UDim.new(0, Theme.Metrics.PadTight),
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	-- Row 1: identity + ready + (AI) remove.
	local identityChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		-- Your own swatch IS the colour dropdown: a plain 16px dot gave no hint it
		-- was interactive, so it is a 30px button with the caret drawn inside it.
		-- Other players' swatches stay decorative dots.
		Swatch = if isLocal
			then React.createElement("TextButton", {
				LayoutOrder = 1,
				Size = UDim2.fromOffset(SWATCH_TRIGGER, SWATCH_TRIGGER),
				BackgroundColor3 = swatch,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Text = if colorOpen then "▴" else "▾",
				FontFace = Theme.FontFace.BodyBold,
				TextSize = Theme.TextSize.ScreenSmall,
				TextColor3 = contrastOn(swatch),
				[React.Event.Activated] = onToggleColor,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				-- Gold ring: the same "this is yours / this is active" signal the
				-- rest of the lobby uses.
				Stroke = React.createElement("UIStroke", {
					Color = Theme.Color.Accent,
					Transparency = if colorOpen then 0 else 0.4,
					Thickness = 2,
				}),
			})
			else React.createElement("Frame", {
				LayoutOrder = 1,
				Size = UDim2.fromOffset(16, 16),
				BackgroundColor3 = swatch,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),
		Name = React.createElement("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(1, -150, 1, 0),
			BackgroundTransparency = 1,
			Text = entry.name .. (if isLocal then "  (You)" elseif entry.isAI then "  (AI)" else ""),
			FontFace = Theme.FontFace.Display,
			TextSize = Theme.TextSize.ScreenBody,
			TextColor3 = if isLocal then Theme.Color.Accent else Theme.Color.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Ready = readyPill(entry.isReady, 3),
	}
	if isLocal then
		identityChildren.Edit = React.createElement("TextButton", {
			LayoutOrder = 5,
			Size = UDim2.fromOffset(Theme.Metrics.DesktopTarget, Theme.Metrics.DesktopTarget),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = if expanded then "▴" else "▾",
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.ScreenSmall,
			TextColor3 = Theme.Color.Accent,
			[React.Event.Activated] = onToggle,
		})
	end
	if entry.isAI then
		identityChildren.Remove = React.createElement("TextButton", {
			LayoutOrder = 4,
			Size = UDim2.fromOffset(Theme.Metrics.DesktopTarget, Theme.Metrics.DesktopTarget),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "✕",
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.ScreenBody,
			TextColor3 = Theme.Color.Danger,
			[React.Event.Activated] = function()
				props.onRemovePlayer(entry)
			end,
		})
	end
	children.IdentityRow = React.createElement("Frame", {
		LayoutOrder = 1,
		-- Sized to the colour trigger, not to the text: a 24px row clipped the
		-- 30px swatch button.
		Size = UDim2.new(1, 0, 0, SWATCH_TRIGGER + 2),
		BackgroundTransparency = 1,
	}, identityChildren)

	-- Row 2: faction -- interactive chips for the local player, a read-only
	-- chip for everyone else.
	if isLocal then
		local factionChildren: { [string]: any } = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, Theme.Metrics.GapTight),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Wraps = true,
			}),
		}
		for i, faction in FACTIONS do
			local takenByOther: string? = nil
			for _, other in allPlayers do
				if other.userId ~= entry.userId and other.faction == faction then
					takenByOther = other.name
					break
				end
			end
			factionChildren[faction] = pickChip(faction, entry.faction == faction, takenByOther, nil, i, function()
				props.onSelectFaction(faction, nil)
			end)
		end
		children.Factions = if expanded
			then React.createElement("Frame", {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, factionChildren)
			else nil
	else
		children.Faction = React.createElement("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = entry.faction or "No faction chosen yet",
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.ScreenCaption,
			TextColor3 = if entry.faction then Theme.Color.TextSecondary else Theme.Color.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	-- Row 3: colour -- local player only (see module comment).
	if isLocal then
		local colorChildren: { [string]: any } = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, Theme.Metrics.GapTight),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Wraps = true,
			}),
		}
		for i, opt in COLOR_OPTIONS do
			local takenByOther: string? = nil
			for _, other in allPlayers do
				if other.userId ~= entry.userId and colorsEqual(other.selectedColor, opt.r, opt.g, opt.b) then
					takenByOther = other.name
					break
				end
			end
			local mine = colorsEqual(entry.selectedColor, opt.r, opt.g, opt.b)
			colorChildren[opt.name] = colorSwatch(opt.name, opt.r, opt.g, opt.b, mine, takenByOther, i, function()
				props.onSelectColor({ opt.r, opt.g, opt.b })
			end)
		end
		colorChildren.Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Wraps = true,
		})
		children.Colors = if colorOpen
			then React.createElement("Frame", {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, SWATCH),
				BackgroundTransparency = 1,
			}, colorChildren)
			else nil
	end

	-- Row 4: spawn -- always read-only, chosen by clicking the map (MapPreview).
	children.Spawn = if expanded or not isLocal then React.createElement("TextLabel", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "Spawn: " .. spawnLabel,
		FontFace = Theme.FontFace.Body,
		TextSize = Theme.TextSize.ScreenCaption,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) else nil

	return React.createElement("Frame", {
		key = tostring(entry.userId),
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = Theme.Transparency.ScreenCard,
		BorderSizePixel = 0,
	}, children)
end

--- Empty slot: an invitation, not a blank. Every empty slot offers Add AI --
--- LobbyManager.addAI auto-assigns the next open spawn, so any of them works.
local function emptySlot(order: number, compact: boolean, onAddAI: () -> ())
	-- FIXED height, deliberately. This row used AutomaticSize.Y while its own
	-- label was sized `1, 0` -- height 100% of a parent whose height came from
	-- its children. Roblox resolves that circular constraint by growing the row,
	-- and it reached 625px, which is what made the roster swallow the screen.
	local rowHeight = if compact
		then Theme.Metrics.TouchTarget + Theme.Metrics.Pad * 2
		else Theme.Metrics.DesktopTarget + Theme.Metrics.Pad * 2
	return React.createElement("Frame", {
		key = "Empty" .. order,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, rowHeight),
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = Theme.Transparency.ScreenCard,
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
		Stroke = React.createElement("UIStroke", {
			Color = Theme.Color.Border,
			Transparency = Theme.Transparency.Border,
			Thickness = 1,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.Pad),
			PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Theme.Metrics.Gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Label = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, -100, 0, if compact then Theme.Metrics.TouchTarget else Theme.Metrics.DesktopTarget),
			BackgroundTransparency = 1,
			Text = "Waiting for players…",
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.ScreenBody,
			TextColor3 = Theme.Color.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		AddAI = React.createElement("TextButton", {
			LayoutOrder = 2,
			Size = UDim2.new(0, 90, 0, if compact then Theme.Metrics.TouchTarget else Theme.Metrics.DesktopTarget),
			BackgroundColor3 = Theme.Color.Action,
			BackgroundTransparency = Theme.Transparency.ScreenCardActive,
			AutoButtonColor = false,
			Text = "+ Add AI",
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.ScreenSmall,
			TextColor3 = Theme.Color.TextPrimary,
			[React.Event.Activated] = onAddAI,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		}),
	})
end

--- Section header for one team when the layout isn't a free-for-all -- see
--- the module comment. Plain caption text, same weight/colour as the map
--- list's "Maps" label in Lobby.luau, so it reads as structure, not a card.
--- Always-available Add AI.
---
--- The per-slot "Waiting for players" invitation only exists while a seat is
--- empty, so a full 1v1 offered no way to add a third opponent at all -- the
--- button vanished exactly when you wanted it. This one stays until the MAP is
--- out of spawns; the server grows the layout to make room (see
--- LobbyManager.addAI).
local function addAIAction(canAdd: boolean, mapSeats: number, filled: number, compact: boolean, order: number, onAddAI: () -> ())
	local height = if compact then Theme.Metrics.TouchTarget else Theme.Metrics.DesktopTarget
	return React.createElement("TextButton", {
		key = "AddAIAction",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = if canAdd then Theme.Color.Action else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if canAdd then 0 else Theme.Transparency.ScreenCard,
		AutoButtonColor = canAdd,
		Active = canAdd,
		Text = if canAdd then "+ Add AI opponent" else `Map is full ({filled}/{mapSeats})`,
		FontFace = Theme.FontFace.BodyBold,
		TextSize = Theme.TextSize.ScreenSmall,
		TextColor3 = if canAdd then Theme.Color.TextPrimary else Theme.Color.TextMuted,
		[React.Event.Activated] = if canAdd then onAddAI else nil,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", Theme.strokeProps(canAdd)),
	})
end

local function teamHeader(teamIndex: number, order: number)
	return React.createElement("TextLabel", {
		key = "TeamHeader" .. teamIndex,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = `Team {teamIndex}`,
		FontFace = Theme.FontFace.BodyBold,
		TextSize = Theme.TextSize.ScreenSmall,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

--- Blocker shown when the lobby cannot start.
---
--- The REASON comes from the server (LobbyManager broadcasts StartBlocker), not
--- from re-deriving the rule here. An earlier version computed it client-side as
--- "player count must exactly equal slot count", which stopped being true the
--- moment empty seats began auto-filling with AI -- so it showed a blocker on a
--- lobby that could in fact start.
local function rosterBlocker(message: string, order: number)
	return React.createElement("TextLabel", {
		key = "RosterBlocker",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = message,
		FontFace = Theme.FontFace.BodyBold,
		TextSize = Theme.TextSize.ScreenCaption,
		TextColor3 = Theme.Color.Warning,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function PlayerList(props: Props)
	-- Only the local player's card can expand, so one boolean is enough.
	local expanded, setExpanded = React.useState(false)
	local function toggleExpanded()
		setExpanded(function(was)
			return not was
		end)
	end
	-- Colour has its own open state: it is a dropdown off the swatch, not part
	-- of the card's general expand.
	local colorOpen, setColorOpen = React.useState(false)
	local function toggleColorOpen()
		setColorOpen(function(was)
			return not was
		end)
	end
	local players = props.players or {}
	local isFFA = TeamLayoutsData.isFreeForAll(props.teamLayout)

	local rowChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	local order = 0

	if isFFA then
		-- Four independent headers each holding one player would just be
		-- noise for a genuine free-for-all -- flat list, same as before teams
		-- existed.
		local spawnByUserId: { [number]: number } = {}
		for spawnNum, selection in pairs(props.spawnSelections or {}) do
			spawnByUserId[selection.userId] = (tonumber(spawnNum) :: number?) or spawnNum
		end

		-- Local player first, then humans before AI, alphabetical within each group.
		local sorted = table.clone(players)
		table.sort(sorted, function(a, b)
			if a.userId == props.localPlayerId then
				return true
			elseif b.userId == props.localPlayerId then
				return false
			elseif a.isAI ~= b.isAI then
				return not a.isAI
			else
				return a.name < b.name
			end
		end)

		for _, entry in sorted do
			order += 1
			local spawnNum = spawnByUserId[entry.userId]
			local spawnLabel = if spawnNum then ("#" .. spawnNum) else "not chosen"
			rowChildren["Player" .. entry.userId] = playerCard(entry, entry.userId == props.localPlayerId, spawnLabel, players, props, order, expanded, toggleExpanded, colorOpen, toggleColorOpen)
		end

		-- Seats come from the LAYOUT, not the map. Rendering maxPlayers meant a
		-- 1v1 on a four-spawn map showed four slots, two of which offered an
		-- "Add AI" that the server then refused because the layout was full.
		local seats = TeamLayoutsData.getSlotCount(props.teamLayout)
		local emptyCount = math.max(0, seats - #players)
		for i = 1, emptyCount do
			order += 1
			rowChildren["Empty" .. i] = emptySlot(order, props.compact, props.onAddAI)
		end
	else
		-- Grouped by team so a 2v2 reads as two pairs rather than four
		-- independent slots -- one section per team, slots rendered in the
		-- layout's own order (see TeamLayoutsData.slotsForTeam).
		local playerByUserId: { [number]: PlayerEntry } = {}
		for _, entry in players do
			playerByUserId[entry.userId] = entry
		end

		local userIdBySlot: { [number]: number } = {}
		for spawnNum, selection in pairs(props.spawnSelections or {}) do
			userIdBySlot[(tonumber(spawnNum) :: number?) or spawnNum] = selection.userId
		end

		local teamCount = TeamLayoutsData.getTeamCount(props.teamLayout)
		for teamIndex = 1, teamCount do
			order += 1
			rowChildren["TeamHeader" .. teamIndex] = teamHeader(teamIndex, order)

			for _, slotNum in TeamLayoutsData.slotsForTeam(props.teamLayout, teamIndex) do
				order += 1
				local userId = userIdBySlot[slotNum]
				local entry: PlayerEntry? = if userId then playerByUserId[userId] else nil
				if entry then
					rowChildren["Player" .. entry.userId] =
						playerCard(entry, entry.userId == props.localPlayerId, "#" .. slotNum, players, props, order, expanded, toggleExpanded, colorOpen, toggleColorOpen)
				else
					rowChildren["EmptySlot" .. slotNum] = emptySlot(order, props.compact, props.onAddAI)
				end
			end
		end
	end

	-- Capacity here is the MAP's, not the layout's: the layout grows to fit, so
	-- what actually limits the roster is how many spawns exist.
	order += 1
	rowChildren.AddAI = addAIAction(
		#players < props.maxPlayers,
		props.maxPlayers,
		#players,
		props.compact,
		order,
		props.onAddAI
	)

	-- Server-authored: empty seats auto-fill with AI, so the only real blocker
	-- is more humans than the layout has seats.
	local blocker = if props.startBlocker then rosterBlocker(props.startBlocker, 2) else nil

	return React.createElement("Frame", {
		Name = "PlayerList",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Header = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = `Players · {#players}/{TeamLayoutsData.getSlotCount(props.teamLayout)}`,
			FontFace = Theme.FontFace.Display,
			TextSize = Theme.TextSize.ScreenHeading,
			TextColor3 = Theme.Color.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Blocker = blocker,
		List = React.createElement("Frame", {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, rowChildren),
	})
end

return PlayerList
