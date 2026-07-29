--!strict
-- HUDStore: extracted game state + remote-event wiring for the HUD, per
-- docs/EconomyRedesign.md section 8 ("HUD decomposition"). HUD.luau
-- (src/ui/screens/HUD/HUD.luau, 1,989 lines) owns ~30 pieces of state and
-- every remote connection inside one React class component. This pulls the
-- STATE and the WIRING out into a plain-Lua observable store so panels can be
-- presentational (props in, no remote access, no direct state) and the two
-- shells (DesktopShell/MobileShell) can read the same data without either one
-- owning it.
--
-- ---------------------------------------------------------------------------
-- RUNS ALONGSIDE HUD.luau, NOT INSTEAD OF IT (for now)
-- ---------------------------------------------------------------------------
-- HUD.luau is still the live "hud" route in App.luau and still has its own
-- copy of these connections. This module is the foundation for AdaptiveHUD,
-- which is not yet wired into the router. Once mounted, this opens a SECOND
-- set of listeners on the same RemoteEvents -- Roblox remotes support any
-- number of listeners, so that's an extra table write per event, not a
-- correctness problem. Do not treat this as the source of truth until
-- HUD.luau is retired.
--
-- ---------------------------------------------------------------------------
-- WHY A PLAIN MODULE, NOT A REACT CONTEXT
-- ---------------------------------------------------------------------------
-- A React Context would force every reader to sit under one Provider and
-- would not help non-panel code (e.g. a future minimap click handler outside
-- the component tree). A plain table + subscribe list works from anywhere,
-- same reasoning as Platform.luau and shared/ViewMode.luau.
--
-- init()/destroy() are idempotent and re-entrant on purpose: the documented
-- failure mode this is fixing is "HUD leaks connections on re-mount" -- calling
-- init() twice without destroy() is a no-op, and destroy() always leaves the
-- store in a state where init() can run again cleanly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(game.ReplicatedStorage.Packages.react)

export type State = {
	-- Resources / economy
	resources: { [string]: number },
	honor: number,
	glory: number, -- spendable balance (GloryUpdate)
	gloryLifetime: number, -- lifetime total (Prestige/Hero Hub unlocks)
	population: number,
	happiness: number, -- 0-100, revolt meter
	weather: string,
	date: string,
	economySnapshot: any?,

	-- Session / match
	peaceTimeRemaining: number,
	victoryCondition: string,
	cameraMode: string, -- "RTS" | "King"
	kingHealth: number,
	kingMaxHealth: number,
	keepCapture: any, -- false | { fraction, secondsRemaining, attacker, keepOwnerName, receivedAt }
	estateCapture: any, -- false | { estateId, fraction, attacker, receivedAt }

	-- Selection (from SelectionManager, src/client/Selection)
	selectedUnits: { Model },
	selectedStance: string,

	-- Building / training
	trainingQueue: { any },
	selectedCategory: string, -- which building-menu category tab/drawer is active

	-- Quests / hero abilities / achievements
	activeQuests: { any },
	heroAbilities: { any },
	achievementData: any?,
}

local function defaultState(): State
	return {
		resources = { Wood = 0, Stone = 0, Gold = 0, Food = 0, Weapons = 0, Iron_Bars = 0 },
		honor = 0,
		glory = 0,
		gloryLifetime = 0,
		population = 0,
		happiness = 50,
		weather = "Clear",
		date = "Y1 M1",
		economySnapshot = nil,
		peaceTimeRemaining = 0,
		victoryCondition = "Score",
		cameraMode = "RTS",
		kingHealth = 100,
		kingMaxHealth = 100,
		keepCapture = false,
		estateCapture = false,
		selectedUnits = {},
		selectedStance = "March",
		trainingQueue = {},
		selectedCategory = "Defense",
		activeQuests = {},
		heroAbilities = {},
		achievementData = nil,
	}
end

local HUDStore = {}

local state: State = defaultState()
local listeners: { [(State) -> ()]: true } = {}
local connections: { RBXScriptConnection } = {}
local started = false
local gameEvent: RemoteEvent? = nil

function HUDStore.get(): State
	return state
end

local function notify()
	-- Snapshot before iterating: a subscriber is allowed to unsubscribe itself
	-- (or another) from inside its own callback (same defensive pattern as
	-- ViewMode's signal in src/shared/ViewMode.luau).
	for listener in table.clone(listeners) do
		local ok, err = pcall(listener, state)
		if not ok then
			warn(`[HUDStore] subscriber errored: {err}`)
		end
	end
end

--- Shallow-merges `partial` into the store and notifies every subscriber.
--- Shallow on purpose: nested tables (e.g. `resources`) are always replaced
--- wholesale by the event handlers below, mirroring how HUD.luau's setState
--- already treats them (never patches Wood/Stone individually).
function HUDStore.setState(partial: { [string]: any })
	for key, value in partial do
		(state :: any)[key] = value
	end
	notify()
end

--- Fires on every setState call. Prefer HUDStore.select or useHUDState for a
--- single field -- this is the escape hatch for something that genuinely needs
--- the whole state table (e.g. a debug overlay).
function HUDStore.subscribe(callback: (State) -> ()): () -> ()
	listeners[callback] = true
	local disconnected = false
	return function()
		if disconnected then
			return
		end
		disconnected = true
		listeners[callback] = nil
	end
end

--- Narrow subscription: fires only when `key`'s value actually changes (`~=`
--- comparison, so a replaced-but-equal table still counts as unchanged only if
--- it's the same reference -- fine here since every writer replaces the whole
--- value rather than mutating in place). This is the point of extracting state
--- at all: HUD.luau re-renders its entire 1,989-line tree on every setState
--- because it is one component with one state table, so a Gold tick would also
--- re-render the building menu. A panel that only cares about `resources`
--- should not re-render when `selectedUnits` changes.
local function select<T>(key: string, callback: (T) -> ()): () -> ()
	local lastValue = (state :: any)[key]
	return HUDStore.subscribe(function(newState)
		local newValue = (newState :: any)[key]
		if newValue ~= lastValue then
			lastValue = newValue
			callback(newValue)
		end
	end)
end
HUDStore.select = select

--- React hook wrapper so function components can read a slice of the store
--- without hand-rolling useState+useEffect+subscribe every time. `selector` is
--- captured once at mount (deps = {}); it is expected to be a stable pure
--- function of State, same convention as HUDStore.select's `key`.
local function useHUDState<T>(selector: (State) -> T): T
	local value, setValue = React.useState(function()
		return selector(state)
	end)

	React.useEffect(function()
		-- The store may have changed between the initial useState() call above
		-- and this effect committing, so re-derive once before subscribing.
		setValue(selector(state))
		return HUDStore.subscribe(function(newState)
			setValue(selector(newState))
		end)
	end, {})

	return value
end
HUDStore.useHUDState = useHUDState

local function trackConnection(connection: RBXScriptConnection)
	table.insert(connections, connection)
end

--- Ask the server to start placing a building. The one write panels are
--- allowed to trigger directly through the store, rather than reaching for
--- RemoteEvents themselves -- see the "panels never touch remotes" rule this
--- whole module exists to enforce.
function HUDStore.startPlacement(buildingName: string)
	if not gameEvent then
		warn(`[HUDStore] startPlacement({buildingName}) called before init() (or after destroy()); dropped`)
		return
	end
	gameEvent:FireServer("StartPlacement", buildingName)
end

--- Ask the server to assign/unassign a worker on the currently selected
--- production building. Mirrors HUD.luau's WorkerAssignmentPanel wiring.
function HUDStore.setStance(unitIds: { string }, stanceName: string)
	if not gameEvent or #unitIds == 0 then
		return
	end
	gameEvent:FireServer("SetStance", { UnitIDs = unitIds, Stance = stanceName })
end

--- Wires every remote-driven piece of HUD state. Safe to call more than once;
--- a second call before destroy() is a no-op so a re-mounting AdaptiveHUD
--- cannot double-subscribe.
function HUDStore.init()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer

	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEvents then
		warn("[HUDStore] RemoteEvents folder not found after 10s; store will not receive updates")
		return
	end
	if not started then
		return -- destroy() ran while we were yielding on WaitForChild
	end

	local event = remoteEvents:WaitForChild("GameEvent", 10) :: RemoteEvent?
	if not event then
		warn("[HUDStore] GameEvent not found after 10s")
		return
	end
	if not started then
		return
	end
	gameEvent = event

	trackConnection(event.OnClientEvent:Connect(function(action: string, data: any)
		if action == "GameStarted" and data.resources then
			local peaceTimeSecs = data.peaceTimeSeconds or 0
			HUDStore.setState({
				resources = data.resources,
				peaceTimeRemaining = peaceTimeSecs,
				victoryCondition = data.victoryCondition or "Score",
			})
			-- Server sends the starting value once; client counts it down
			-- locally rather than being pushed a tick every second. Mirrors
			-- HUD.luau's own countdown loop exactly.
			if peaceTimeSecs > 0 then
				task.spawn(function()
					local remaining = peaceTimeSecs
					while remaining > 0 and started do
						task.wait(1)
						remaining -= 1
						HUDStore.setState({ peaceTimeRemaining = remaining })
					end
				end)
			end
		elseif action == "UpdateResources" and data.resources then
			HUDStore.setState({ resources = data.resources })
		elseif action == "TrainingQueueUpdate" and data.buildingId and data.queue then
			HUDStore.setState({ trainingQueue = data.queue })
		elseif action == "UpdateHappiness" and data.happiness then
			HUDStore.setState({ happiness = data.happiness })
		elseif action == "UpdatePopulation" and data.current then
			HUDStore.setState({ population = data.current })
		elseif action == "EconomyDashboardUpdate" and data.snapshot then
			HUDStore.setState({
				economySnapshot = data.snapshot,
				weather = data.snapshot.weather,
			})
		elseif action == "GloryUpdate" and typeof(data) == "table" then
			HUDStore.setState({
				glory = data.glory or 0,
				gloryLifetime = data.lifetime or state.gloryLifetime,
			})
		elseif action == "KingHealthUpdate" and data.health and data.maxHealth then
			HUDStore.setState({ kingHealth = data.health, kingMaxHealth = data.maxHealth })
		elseif action == "CameraModeChanged" and typeof(data) == "string" then
			HUDStore.setState({ cameraMode = data })
			if data == "King" and gameEvent then
				gameEvent:FireServer("GetAbilities")
			end
		elseif action == "KeepCaptureProgress" and typeof(data) == "table" then
			local fraction = data.fraction or (data.percent or 0) / 100
			if fraction <= 0 then
				HUDStore.setState({ keepCapture = false })
			else
				HUDStore.setState({
					keepCapture = {
						fraction = fraction,
						secondsRemaining = data.secondsRemaining or 0,
						attacker = data.attacker == true,
						keepOwnerName = data.keepOwnerName,
						receivedAt = os.clock(),
					},
				})
			end
		elseif action == "EstateCaptureProgress" and typeof(data) == "table" then
			if data.capturing and (data.fraction or 0) > 0 then
				HUDStore.setState({
					estateCapture = {
						estateId = data.estateId,
						fraction = data.fraction,
						attacker = data.attacker == true,
						receivedAt = os.clock(),
					},
				})
			else
				HUDStore.setState({ estateCapture = false })
			end
		elseif action == "EstateCaptured" or action == "EstateLost" then
			HUDStore.setState({ estateCapture = false })
		elseif action == "AchievementUnlocked" then
			HUDStore.setState({ achievementData = data })
			task.delay(6, function()
				if started and HUDStore.get().achievementData == data then
					HUDStore.setState({ achievementData = nil })
				end
			end)
		elseif action == "QuestsData" then
			HUDStore.setState({ activeQuests = data.activeQuests or {} })
		elseif action == "QuestCompleted" or action == "QuestProgress" then
			if gameEvent then
				gameEvent:FireServer("GetQuests")
			end
		elseif action == "AbilitiesData" then
			HUDStore.setState({ heroAbilities = data.abilities or {} })
		elseif action == "AbilityCooldownUpdate" and data.abilityId then
			local current = HUDStore.get().heroAbilities
			if current then
				local abilities = table.clone(current)
				for _, ability in abilities do
					if ability.id == data.abilityId then
						ability.remainingCooldown = data.remainingCooldown
						ability.isOnCooldown = data.isOnCooldown
						break
					end
				end
				HUDStore.setState({ heroAbilities = abilities })
			end
		end
	end))

	task.delay(0.5, function()
		if started and gameEvent then
			gameEvent:FireServer("GetQuests")
			gameEvent:FireServer("GetGlory")
		end
	end)

	-- Selection lives under StarterPlayerScripts.Client, a different script
	-- tree than this one (StarterPlayerScripts.UI); neither can require the
	-- other by a relative path, same split ViewToggleButton documents. Yielded
	-- onto its own task.spawn so a slow/never-arriving Client tree can't block
	-- the rest of init().
	task.spawn(function()
		local playerScripts = player:WaitForChild("PlayerScripts", 10)
		local client = playerScripts and playerScripts:WaitForChild("Client", 10)
		if not client then
			warn("[HUDStore] PlayerScripts.Client not found after 10s; selection state will not update")
			return
		end
		if not started then
			return
		end
		local ok, SelectionManager = pcall(function()
			return require(client.Selection.SelectionManager :: any)
		end)
		if not ok or not SelectionManager then
			warn(`[HUDStore] failed to require SelectionManager: {tostring(SelectionManager)}`)
			return
		end
		if not started then
			return -- destroyed while we were yielding above
		end
		local connection = (SelectionManager :: any).SelectionChanged:Connect(function(selectedUnits: { Model })
			local firstStance = nil
			if selectedUnits[1] then
				firstStance = selectedUnits[1]:GetAttribute("Stance")
			end
			HUDStore.setState({
				selectedUnits = selectedUnits,
				selectedStance = firstStance or "March",
			})
		end)
		trackConnection(connection)
	end)
end

--- Disconnects every connection this store opened and resets state to
--- defaults. Safe to call multiple times. After this, init() can run again --
--- this is what makes the store safe across an AdaptiveHUD remount, unlike
--- HUD.luau's willUnmount (see HUD.luau's header comment).
function HUDStore.destroy()
	started = false
	gameEvent = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	listeners = {}
	state = defaultState()
end

return HUDStore
