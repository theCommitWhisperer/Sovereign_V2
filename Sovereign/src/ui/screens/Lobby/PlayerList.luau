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
			TextColor3 = if blocked then Theme.Color.TextMuted elseif mine then Theme.Color.Accent else Theme.Color.TextSecondary,
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
		BackgroundTransparency = if mine then Theme.Transparency.ScreenCardActive else Theme.Transparency.ScreenCard,
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

local function playerCard(entry: PlayerEntry, isLocal: boolean, spawnLabel: string, allPlayers: { PlayerEntry }, props: Props, order: number)
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
			PaddingTop = UDim.new(0, Theme.Metrics.Pad),
			PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
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
		Swatch = React.createElement("Frame", {
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
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.ScreenBody,
			TextColor3 = if isLocal then Theme.Color.Accent else Theme.Color.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Ready = readyPill(entry.isReady, 3),
	}
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
		Size = UDim2.new(1, 0, 0, 24),
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
		children.Factions = React.createElement("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, factionChildren)
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
			colorChildren[opt.name] =
				pickChip(opt.name, mine, takenByOther, Color3.fromRGB(opt.r, opt.g, opt.b), i, function()
					props.onSelectColor({ opt.r, opt.g, opt.b })
				end)
		end
		children.Colors = React.createElement("Frame", {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, colorChildren)
	end

	-- Row 4: spawn -- always read-only, chosen by clicking the map (MapPreview).
	children.Spawn = React.createElement("TextLabel", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "Spawn: " .. spawnLabel,
		FontFace = Theme.FontFace.Body,
		TextSize = Theme.TextSize.ScreenCaption,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

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
	return React.createElement("Frame", {
		key = "Empty" .. order,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
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
			Size = UDim2.new(1, -100, 1, 0),
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

--- Blocker shown when the roster can't fill the chosen layout's teams --
--- either direction (too few or too many) means there's no valid split, so
--- Ready-driven start has to be refused (see LobbyManager.lobbyFitsLayout).
local function rosterBlocker(layoutId: string, playerCount: number, order: number)
	local layout = TeamLayoutsData.getOrDefault(layoutId)
	local needed = TeamLayoutsData.getSlotCount(layoutId)

	return React.createElement("TextLabel", {
		key = "RosterBlocker",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = `{layout.label} needs {needed} players — {playerCount} in lobby`,
		FontFace = Theme.FontFace.BodyBold,
		TextSize = Theme.TextSize.ScreenCaption,
		TextColor3 = Theme.Color.Warning,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function PlayerList(props: Props)
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
			rowChildren["Player" .. entry.userId] = playerCard(entry, entry.userId == props.localPlayerId, spawnLabel, players, props, order)
		end

		local emptyCount = math.max(0, props.maxPlayers - #players)
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
						playerCard(entry, entry.userId == props.localPlayerId, "#" .. slotNum, players, props, order)
				else
					rowChildren["EmptySlot" .. slotNum] = emptySlot(order, props.compact, props.onAddAI)
				end
			end
		end
	end

	-- A layout's teams have to be exactly full to start (see
	-- LobbyManager.lobbyFitsLayout) -- surface that as a clear blocker rather
	-- than let Ready silently do nothing.
	local neededPlayers = TeamLayoutsData.getSlotCount(props.teamLayout)
	local blocker = if #players ~= neededPlayers
		then rosterBlocker(props.teamLayout, #players, 2)
		else nil

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
			Text = `Players · {#players}/{props.maxPlayers}`,
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
