--!strict
-- HUDStore: extracted game state + remote-event wiring for the HUD, per
-- docs/EconomyRedesign.md section 8 ("HUD decomposition"). HUD.luau
-- (src/ui/screens/HUD/HUD.luau, 1,989 lines) owned ~30 pieces of state and
-- every remote connection inside one React class component. This pulls the
-- STATE and the WIRING out into a plain-Lua observable store so panels can be
-- presentational (props in, no remote access, no direct state) and the two
-- shells (DesktopShell/MobileShell) can read the same data without either one
-- owning it.
--
-- ---------------------------------------------------------------------------
-- THIS IS NOW THE SOURCE OF TRUTH
-- ---------------------------------------------------------------------------
-- HUD.luau has been deleted; AdaptiveHUD (via DesktopShell/MobileShell) is the
-- only thing that calls HUDStore.init()/destroy(). Every remote connection,
-- BindableEvent hookup and piece of derived state HUD.luau used to own lives
-- here now -- see the per-action comments below for where each one moved from.
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
local Workspace = game:GetService("Workspace")

local React = require(game.ReplicatedStorage.Packages.react)
local GameData = require(ReplicatedStorage.Shared.GameData)

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
	gameStartData: any?, -- raw payload from App.luau's "hud" route props
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
	selectedFormation: string,

	-- Building placement
	isPlacingBuilding: boolean,
	selectedBuilding: string?,
	currentWallPiece: string,
	isPlacingWall: boolean,

	-- Building / training / production selection
	selectedTrainingBuilding: Model?,
	selectedProductionBuilding: Model?,
	trainingQueue: { any },
	selectedCategory: string, -- which building-menu category tab/drawer is active
	buildingUpgradeInfo: any?, -- never populated server-side today; kept for structural parity

	-- Delete mode
	isDeleteMode: boolean,
	showDeleteConfirmation: boolean,
	buildingToDelete: any?,
	showMultiDeleteConfirmation: boolean,
	buildingsToDelete: { any },
	multiDeleteRefund: string?,
	deletionHistory: { any },

	-- Modals
	showPoliciesModal: boolean,
	showTechTreeModal: boolean,
	showAbilityTree: boolean,
	showHeroAbilities: boolean,
	showMenuModal: boolean,
	showStatsModal: boolean,

	-- Tutorial
	tutorialEnabled: boolean,
	showKeepModal: boolean,
	tutorialStep: number,
	buildingsCompleted: { [string]: boolean },
	tutorialModalHidden: boolean,

	-- Quests / hero abilities / achievements
	activeQuests: { any },
	heroAbilities: { any },
	achievementData: any?,

	-- Misc HUD chrome
	armySize: number, -- never updated today; kept for Stats modal parity
	stats: any?,
	battleLogMessages: { any },
	battleLogExpanded: boolean,
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
		gameStartData = nil,
		peaceTimeRemaining = 0,
		victoryCondition = "Score",
		cameraMode = "RTS",
		kingHealth = 100,
		kingMaxHealth = 100,
		keepCapture = false,
		estateCapture = false,
		selectedUnits = {},
		selectedStance = "March",
		selectedFormation = "Line",
		isPlacingBuilding = false,
		selectedBuilding = nil,
		currentWallPiece = "Wall Segment",
		isPlacingWall = false,
		selectedTrainingBuilding = nil,
		selectedProductionBuilding = nil,
		trainingQueue = {},
		selectedCategory = "Defense",
		buildingUpgradeInfo = nil,
		isDeleteMode = false,
		showDeleteConfirmation = false,
		buildingToDelete = nil,
		showMultiDeleteConfirmation = false,
		buildingsToDelete = {},
		multiDeleteRefund = nil,
		deletionHistory = {},
		showPoliciesModal = false,
		showTechTreeModal = false,
		showAbilityTree = false,
		showHeroAbilities = false,
		showMenuModal = false,
		showStatsModal = false,
		tutorialEnabled = false,
		showKeepModal = true,
		tutorialStep = 1,
		buildingsCompleted = {},
		tutorialModalHidden = false,
		activeQuests = {},
		heroAbilities = {},
		achievementData = nil,
		armySize = 0,
		stats = nil,
		battleLogMessages = {},
		battleLogExpanded = false,
	}
end

local HUDStore = {}

--- Sentinel for HUDStore.setState: a plain `{ key = nil }` table literal never
--- contains `key` at all (Lua drops nil-valued fields at construction), so the
--- merge loop below would never see it and could never null a field out. This
--- mirrors React.None for exactly that reason -- HUD.luau's own `{ achievementData
--- = nil }` calls had the same bug and were silent no-ops; every clearing call in
--- this file now goes through HUDStore.None instead.
HUDStore.None = setmetatable({}, { __tostring = function()
	return "HUDStore.None"
end })

local state: State = defaultState()
local listeners: { [(State) -> ()]: true } = {}
local connections: { RBXScriptConnection } = {}
local started = false
local gameEvent: RemoteEvent? = nil
local getStatsEvent: RemoteEvent? = nil
local deleteModeEventRef: BindableEvent? = nil
local resetWallPieceFuncRef: BindableFunction? = nil
local pollingBuildingId: string? = nil
local selectionManagerRef: any = nil

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
--- already treated them (never patches Wood/Stone individually). Pass
--- HUDStore.None as a value to explicitly null out a field -- see its comment.
function HUDStore.setState(partial: { [string]: any })
	for key, value in partial do
		if value == HUDStore.None then
			(state :: any)[key] = nil
		else
			(state :: any)[key] = value
		end
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
--- at all: a single component re-rendering its entire tree on every setState
--- would re-render the building menu on a Gold tick. A panel that only cares
--- about `resources` should not re-render when `selectedUnits` changes.
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

-- ---------------------------------------------------------------------------
-- SESSION / GAME START
-- ---------------------------------------------------------------------------

--- Seeds resources + tutorial flag from App.luau's gameStartData prop, same as
--- HUD.luau's :init() reading self.props.gameStartData before the first
--- "GameStarted" remote event arrives. Also records the raw payload so shells
--- can derive Battle Arena mode (`gameStartData.mode == "BattleArena"`).
function HUDStore.setGameStartData(data: any?)
	if not data then
		return
	end
	local tutorialEnabled = if data.showTutorial ~= nil then data.showTutorial else true
	local partial: { [string]: any } = { gameStartData = data, tutorialEnabled = tutorialEnabled }
	if data.resources then
		partial.resources = data.resources
	end
	HUDStore.setState(partial)
end

-- ---------------------------------------------------------------------------
-- BUILDING PLACEMENT
-- ---------------------------------------------------------------------------

--- Ask the server to start placing a building. The one write panels are
--- allowed to trigger directly through the store, rather than reaching for
--- RemoteEvents themselves -- see the "panels never touch remotes" rule this
--- whole module exists to enforce.
function HUDStore.startPlacement(buildingName: string)
	if not gameEvent then
		warn(`[HUDStore] startPlacement({buildingName}) called before init() (or after destroy()); dropped`)
		return
	end
	HUDStore.setState({ isPlacingBuilding = true, selectedBuilding = buildingName })
	gameEvent:FireServer("StartPlacement", buildingName)
end

-- ---------------------------------------------------------------------------
-- CATEGORY / TRAINING / PRODUCTION SELECTION
-- ---------------------------------------------------------------------------

--- Switching building-menu category. Moved from HUD:createCategoryButton's
--- OnClick. Deliberately also force-clears selectedUnits: HUD.luau did this so
--- the content area always shows the building menu when a category tab is
--- clicked even if units are still selected in the world -- SelectionManager
--- will repopulate it on the next real selection change.
function HUDStore.selectCategory(category: string)
	if resetWallPieceFuncRef then
		pcall(function()
			local resetFn = resetWallPieceFuncRef :: BindableFunction
			resetFn:Invoke()
		end)
	end
	pollingBuildingId = nil
	HUDStore.setState({
		selectedCategory = category,
		selectedTrainingBuilding = HUDStore.None,
		selectedProductionBuilding = HUDStore.None,
		trainingQueue = {},
		selectedUnits = {},
	})
end

--- A building click (see src/ui/input/HUDInput.luau) resolved to a
--- trainable building. Starts polling GetTrainingQueue for it.
function HUDStore.selectTrainingBuilding(building: Model)
	pollingBuildingId = building.Name
	HUDStore.setState({
		selectedTrainingBuilding = building,
		selectedProductionBuilding = HUDStore.None,
		trainingQueue = {},
	})
	if gameEvent then
		gameEvent:FireServer("GetTrainingQueue", { buildingId = building.Name })
	end
end

--- A building click resolved to a resource-producing building.
function HUDStore.selectProductionBuilding(building: Model)
	pollingBuildingId = nil
	HUDStore.setState({
		selectedProductionBuilding = building,
		selectedTrainingBuilding = HUDStore.None,
		trainingQueue = {},
	})
end

--- Clicked on nothing / a non-training-non-production building.
function HUDStore.clearBuildingSelection()
	pollingBuildingId = nil
	HUDStore.setState({
		selectedTrainingBuilding = HUDStore.None,
		selectedProductionBuilding = HUDStore.None,
		trainingQueue = {},
	})
end

function HUDStore.startTraining(buildingId: string, unitType: string)
	if gameEvent then
		gameEvent:FireServer("StartTraining", { buildingId = buildingId, unitType = unitType })
	end
end

function HUDStore.closeTrainingPanel()
	pollingBuildingId = nil
	HUDStore.setState({ selectedTrainingBuilding = HUDStore.None, trainingQueue = {} })
end

function HUDStore.assignWorker(buildingId: string)
	if gameEvent then
		gameEvent:FireServer("AssignWorker", { buildingId = buildingId })
	end
end

function HUDStore.unassignWorker(buildingId: string)
	if gameEvent then
		gameEvent:FireServer("UnassignWorker", { buildingId = buildingId })
	end
end

function HUDStore.closeProductionPanel()
	HUDStore.setState({ selectedProductionBuilding = HUDStore.None })
end

-- ---------------------------------------------------------------------------
-- UNITS: STANCE / FORMATION / CIVILIAN ORDERS
-- ---------------------------------------------------------------------------

--- Low-level stance remote call. Prefer HUDStore.selectStance below, which
--- also updates the highlighted stance button; this is kept for callers that
--- already have a unit-id list on hand.
function HUDStore.setStance(unitIds: { string }, stanceName: string)
	if not gameEvent or #unitIds == 0 then
		return
	end
	gameEvent:FireServer("SetStance", { UnitIDs = unitIds, Stance = stanceName })
end

--- UnitSelectionPanel's onStanceSelected. Derives unit ids from the current
--- selection so the panel itself never has to.
function HUDStore.selectStance(stanceName: string)
	HUDStore.setState({ selectedStance = stanceName })
	local unitIds = {}
	for _, unit in state.selectedUnits do
		table.insert(unitIds, unit:GetAttribute("UnitId") or unit.Name)
	end
	HUDStore.setStance(unitIds, stanceName)
end

--- UnitSelectionPanel's onFormationSelected. Ported from HUD.luau's render():
--- updates SelectionManager's formation type (so future spawns/orders use it)
--- and, for 2+ selected units, immediately re-arranges them at a point offset
--- from their average position in the camera's facing direction.
function HUDStore.selectFormation(formationType: string)
	HUDStore.setState({ selectedFormation = formationType })
	if selectionManagerRef then
		selectionManagerRef.setFormationType(formationType)
	end

	local selectedUnits = state.selectedUnits
	if #selectedUnits < 2 or not gameEvent then
		return
	end

	local unitIds = {}
	local avgPosition = Vector3.new(0, 0, 0)
	for _, unit in selectedUnits do
		table.insert(unitIds, unit:GetAttribute("UnitId") or unit.Name)
		if unit.PrimaryPart then
			avgPosition = avgPosition + unit.PrimaryPart.Position
		end
	end
	avgPosition = avgPosition / #selectedUnits

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraLook = camera.CFrame.LookVector
	local horizontalLook = Vector3.new(cameraLook.X, 0, cameraLook.Z).Unit
	local targetPosition = avgPosition + horizontalLook * 8 -- forward offset so units don't collide forming up

	gameEvent:FireServer("MoveUnitsInFormation", {
		unitIds = unitIds,
		targetPosition = targetPosition,
		formationType = formationType,
	})
end

--- ReturnToKeep / UnassignWorkers for the civilian (peasant/worker) subset of
--- a selection. Moved out of UnitSelectionPanel.luau, which used to reach into
--- RemoteEvents directly -- see the "panels never touch remotes" rule.
function HUDStore.civilianOrder(selectedUnits: { Model }, action: string)
	if not gameEvent then
		return
	end
	local ids = {}
	for _, unit in selectedUnits do
		table.insert(ids, unit:GetAttribute("UnitId") or unit.Name)
	end
	gameEvent:FireServer(action, { unitIds = ids })
end

-- ---------------------------------------------------------------------------
-- DELETE MODE
-- ---------------------------------------------------------------------------

--- Turning delete mode on cancels any in-flight placement (matches HUD.luau's
--- DeleteButton.OnClick) and fires DeleteModeChanged for
--- DeletionInputHandler's visual feedback (src/client), the same BindableEvent
--- HUD.luau fired.
function HUDStore.setDeleteMode(enabled: boolean)
	HUDStore.setState({ isDeleteMode = enabled })
	if enabled and gameEvent then
		gameEvent:FireServer("PlacementEnded")
	end
	if deleteModeEventRef then
		deleteModeEventRef:Fire(enabled)
	end
end

function HUDStore.toggleDeleteMode()
	HUDStore.setDeleteMode(not state.isDeleteMode)
end

function HUDStore.confirmDelete()
	local target = state.buildingToDelete
	if target and gameEvent then
		gameEvent:FireServer("DeleteBuilding", { buildingId = target.name })
	end
	HUDStore.setState({ showDeleteConfirmation = false, buildingToDelete = HUDStore.None })
end

function HUDStore.cancelDelete()
	HUDStore.setState({ showDeleteConfirmation = false, buildingToDelete = HUDStore.None })
end

--- Confirms a multi-select deletion (drag-select -> Delete). Ported verbatim
--- from HUD.luau's MultiDeleteConfirmationModal.onConfirm: walls go through
--- RemoveWallPiece, buildings through DeleteBuilding, and the whole batch is
--- recorded as ONE undo-history entry.
function HUDStore.confirmMultiDelete(selectedBuildings: { any })
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local removePieceEvent = remoteEvents and remoteEvents:FindFirstChild("RemoveWallPiece")

	local deletionBatch = {}
	for _, buildingInfo in selectedBuildings do
		local wallPieceType = nil
		if buildingInfo.isWall then
			wallPieceType = buildingInfo.name:match("^([^_]+)")
		end
		table.insert(deletionBatch, {
			type = wallPieceType or buildingInfo.type,
			name = buildingInfo.name,
			position = buildingInfo.model.PrimaryPart and buildingInfo.model.PrimaryPart.Position
				or Vector3.new(0, 0, 0),
			rotation = buildingInfo.model.PrimaryPart and buildingInfo.model.PrimaryPart.Orientation
				or Vector3.new(0, 0, 0),
			isWall = buildingInfo.isWall or false,
		})
	end
	if #deletionBatch > 0 then
		task.defer(function()
			HUDStore.addToDeletionHistory(deletionBatch)
		end)
	end

	for _, buildingInfo in selectedBuildings do
		if buildingInfo.isWall then
			if removePieceEvent then
				(removePieceEvent :: RemoteEvent):FireServer(buildingInfo.model)
			else
				warn("[HUDStore] RemoveWallPiece event not found!")
			end
		elseif gameEvent then
			gameEvent:FireServer("DeleteBuilding", { buildingId = buildingInfo.name })
		end
	end

	HUDStore.setState({
		showMultiDeleteConfirmation = false,
		buildingsToDelete = {},
		multiDeleteRefund = HUDStore.None,
	})
end

function HUDStore.cancelMultiDelete()
	HUDStore.setState({
		showMultiDeleteConfirmation = false,
		buildingsToDelete = {},
		multiDeleteRefund = HUDStore.None,
	})
end

--- Records one deletion (or a whole multi-delete batch as a single entry) for
--- Ctrl+U / the Undo button. Trims to the last 5, same cap HUD.luau used.
function HUDStore.addToDeletionHistory(buildingDataOrBatch: any)
	local history = table.clone(state.deletionHistory)
	local isBatch = buildingDataOrBatch[1] ~= nil and type(buildingDataOrBatch[1]) == "table"

	if isBatch then
		local batch = {}
		for _, buildingData in buildingDataOrBatch do
			table.insert(batch, {
				buildingType = buildingData.type,
				buildingName = buildingData.name,
				position = buildingData.position,
				rotation = buildingData.rotation,
				isWall = buildingData.isWall,
			})
		end
		table.insert(history, { batch = batch, timestamp = os.time() })
	else
		table.insert(history, {
			buildingType = buildingDataOrBatch.type,
			buildingName = buildingDataOrBatch.name,
			position = buildingDataOrBatch.position,
			rotation = buildingDataOrBatch.rotation,
			isWall = buildingDataOrBatch.isWall,
			timestamp = os.time(),
		})
	end

	while #history > 5 do
		table.remove(history, 1)
	end
	HUDStore.setState({ deletionHistory = history })
end

--- Undo the most recent deletion (Ctrl+U or the Undo button -- both routes go
--- through this single implementation now. HUD.luau had two: this smart,
--- wall/batch-aware version for Ctrl+U, and a naive `FireServer("UndoDeletion",
--- lastDeletion)` wired to the Undo button's onClick that did not handle walls
--- or batches at all. Consolidating avoids reproducing that button-vs-hotkey
--- inconsistency.
function HUDStore.undoLastDeletion()
	local history = state.deletionHistory
	if #history == 0 then
		return
	end
	local lastDeletion = history[#history]
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")

	if lastDeletion.batch then
		local placePathEvent = remoteEvents and remoteEvents:FindFirstChild("PlaceWallPath")
		for _, item in lastDeletion.batch do
			if item.isWall then
				if placePathEvent then
					local yRotationRadians = math.rad(item.rotation and item.rotation.Y or 0)
					-- Bind the cast to a local rather than opening the next statement
					-- with "(": following a line that ends in ")", Luau parses a
					-- leading paren as a call on the previous expression and rejects
					-- the whole file as ambiguous syntax.
					local pathEvent = placePathEvent :: RemoteEvent
					pathEvent:FireServer({
						{ type = item.buildingType, position = item.position, rotation = yRotationRadians },
					})
				end
			elseif gameEvent then
				gameEvent:FireServer("UndoDeletion", {
					buildingType = item.buildingType,
					position = item.position,
					rotation = item.rotation,
				})
			end
		end
	elseif lastDeletion.isWall then
		local placePathEvent = remoteEvents and remoteEvents:FindFirstChild("PlaceWallPath")
		if placePathEvent then
			local yRotationRadians = math.rad(lastDeletion.rotation and lastDeletion.rotation.Y or 0)
			local pathEvent = placePathEvent :: RemoteEvent
			pathEvent:FireServer({
				{ type = lastDeletion.buildingType, position = lastDeletion.position, rotation = yRotationRadians },
			})
		else
			warn("[HUDStore] PlaceWallPath event not found!")
		end
	elseif gameEvent then
		gameEvent:FireServer("UndoDeletion", {
			buildingType = lastDeletion.buildingType,
			position = lastDeletion.position,
			rotation = lastDeletion.rotation,
		})
	end

	local newHistory = table.clone(history)
	table.remove(newHistory)
	HUDStore.setState({ deletionHistory = newHistory })
end

-- ---------------------------------------------------------------------------
-- MODALS
-- ---------------------------------------------------------------------------

function HUDStore.togglePoliciesModal()
	HUDStore.setState({ showPoliciesModal = not state.showPoliciesModal })
end

function HUDStore.toggleAbilityTree()
	HUDStore.setState({ showAbilityTree = not state.showAbilityTree })
end

function HUDStore.setTechTreeModal(visible: boolean)
	HUDStore.setState({ showTechTreeModal = visible })
end

function HUDStore.setMenuModal(visible: boolean)
	HUDStore.setState({ showMenuModal = visible })
end

function HUDStore.setStatsModal(visible: boolean)
	HUDStore.setState({ showStatsModal = visible })
end

function HUDStore.dismissAchievement()
	HUDStore.setState({ achievementData = HUDStore.None })
end

-- ---------------------------------------------------------------------------
-- HERO ABILITIES / BUILDING UPGRADES / RESEARCH
-- ---------------------------------------------------------------------------

function HUDStore.useAbility(abilityId: string)
	if gameEvent then
		gameEvent:FireServer("UseAbility", abilityId)
	end
end

function HUDStore.upgradeBuilding(buildingId: string)
	if gameEvent then
		gameEvent:FireServer("UpgradeBuilding", buildingId)
	end
end

function HUDStore.closeUpgradePanel()
	HUDStore.setState({ buildingUpgradeInfo = HUDStore.None })
end

function HUDStore.startResearch(techId: string)
	if gameEvent then
		gameEvent:FireServer("StartResearch", techId)
	end
end

-- ---------------------------------------------------------------------------
-- TUTORIAL
-- ---------------------------------------------------------------------------

--- Tutorial step machine, ported from HUD:onBuildingPlaced. Advances
--- Keep -> Storehouse -> Granary as each is placed; disabling `tutorialEnabled`
--- is what makes the modal stop rendering once the sequence finishes.
local function handleBuildingPlaced(buildingType: string)
	local tutorialBuildings = { "Keep", "Storehouse", "Granary" }
	local currentRequiredBuilding = tutorialBuildings[state.tutorialStep]
	if buildingType ~= currentRequiredBuilding then
		return
	end

	local newCompleted = table.clone(state.buildingsCompleted)
	newCompleted[buildingType] = true

	if state.tutorialStep == 1 then
		if state.tutorialEnabled then
			HUDStore.setState({
				buildingsCompleted = newCompleted,
				tutorialStep = 2,
				tutorialModalHidden = false,
				showKeepModal = false,
			})
		else
			HUDStore.setState({
				buildingsCompleted = newCompleted,
				showKeepModal = false,
				tutorialModalHidden = false,
			})
		end
	elseif state.tutorialStep >= #tutorialBuildings then
		HUDStore.setState({
			buildingsCompleted = newCompleted,
			tutorialEnabled = false,
			tutorialModalHidden = false,
			showKeepModal = false,
		})
	else
		HUDStore.setState({
			buildingsCompleted = newCompleted,
			tutorialStep = state.tutorialStep + 1,
			tutorialModalHidden = false,
		})
	end
end

--- TutorialModal's onBuildRequested. Manual clicks hide the modal so it isn't
--- covering the placement preview; auto-triggered steps keep it visible so the
--- player can keep reading instructions while placing.
function HUDStore.requestTutorialBuild(buildingType: string, isAutoTriggered: boolean?)
	if not isAutoTriggered then
		HUDStore.setState({ tutorialModalHidden = true })
	end
	HUDStore.startPlacement(buildingType)
end

-- ---------------------------------------------------------------------------
-- INIT / DESTROY
-- ---------------------------------------------------------------------------

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
		warn("[HUDStore] GameEvent not found after 10s; economy/selection/combat state will not update")
		return
	end
	if not started then
		return
	end
	gameEvent = event

	-- GetStats is a SEPARATE remote from GameEvent. HUD.luau's :init() treated a
	-- missing GetStats as fatal for the WHOLE HUD (it returned before wiring
	-- gameEvent at all if either lookup failed) -- exactly the "silently skips
	-- later setup" failure this migration was told to stop reproducing. Here a
	-- missing GetStats only disables the Stats modal; everything else still wires.
	local statsEvent = remoteEvents:WaitForChild("GetStats", 10) :: RemoteEvent?
	if statsEvent then
		getStatsEvent = statsEvent
		trackConnection(statsEvent.OnClientEvent:Connect(function(stats)
			HUDStore.setState({ stats = stats })
		end))
	else
		warn("[HUDStore] GetStats not found after 10s; Stats modal will show stale/no data")
	end
	if not started then
		return
	end

	-- Delete-mode visual feedback BindableEvent, shared with DeletionInputHandler
	-- (src/client). Found-or-created, same as HUD.luau did.
	local deleteModeEvent = ReplicatedStorage:FindFirstChild("DeleteModeChanged") :: BindableEvent?
	if not deleteModeEvent then
		deleteModeEvent = Instance.new("BindableEvent")
		deleteModeEvent.Name = "DeleteModeChanged"
		deleteModeEvent.Parent = ReplicatedStorage
	end
	deleteModeEventRef = deleteModeEvent

	-- Drag-select multi-delete request, fired by src/client's selection box.
	local multiDeleteEvent = ReplicatedStorage:FindFirstChild("MultiDeleteRequested") :: BindableEvent?
	if not multiDeleteEvent then
		multiDeleteEvent = Instance.new("BindableEvent")
		multiDeleteEvent.Name = "MultiDeleteRequested"
		multiDeleteEvent.Parent = ReplicatedStorage
	end
	trackConnection((multiDeleteEvent :: BindableEvent).Event:Connect(function(buildings: { Model })
		local totalRefund: { [string]: number } = {}
		local buildingInfoList = {}

		for _, building in buildings do
			local buildingType = building:GetAttribute("BuildingType")
			local isWall = building:FindFirstChild("PlacedPiece") ~= nil
			local actualType = buildingType
			if isWall and not buildingType then
				actualType = "Stone_Wall"
			end

			if actualType or isWall then
				table.insert(buildingInfoList, {
					name = building.Name,
					type = actualType or "Stone_Wall",
					model = building,
					isWall = isWall,
				})

				if buildingType and not isWall then
					local buildingInfo = GameData.Buildings[buildingType]
					if buildingInfo and buildingInfo.cost then
						for resourceType, cost in pairs(buildingInfo.cost) do
							local refund = math.floor(cost * 0.5)
							if refund > 0 then
								totalRefund[resourceType] = (totalRefund[resourceType] or 0) + refund
							end
						end
					end
				end
			end
		end

		local refundText = nil
		if next(totalRefund) then
			local refundParts = {}
			for resourceType, amount in pairs(totalRefund) do
				table.insert(refundParts, string.format("%d %s", amount, resourceType))
			end
			refundText = table.concat(refundParts, ", ")
		end

		HUDStore.setState({
			showMultiDeleteConfirmation = true,
			buildingsToDelete = buildingInfoList,
			multiDeleteRefund = refundText or HUDStore.None,
		})
	end))

	-- Wall-piece selector state, published by PlacementController (src/client).
	local wallPieceEvent = ReplicatedStorage:FindFirstChild("WallPieceChanged") :: BindableEvent?
	if not wallPieceEvent then
		wallPieceEvent = Instance.new("BindableEvent")
		wallPieceEvent.Name = "WallPieceChanged"
		wallPieceEvent.Parent = ReplicatedStorage
	end
	trackConnection((wallPieceEvent :: BindableEvent).Event:Connect(function(data)
		HUDStore.setState({ currentWallPiece = data.currentPiece, isPlacingWall = data.isPlacingWalls })
	end))

	resetWallPieceFuncRef = ReplicatedStorage:FindFirstChild("ResetWallPiece") :: BindableFunction?

	-- Request initial quest data + Glory balance (server also pushes GloryUpdate
	-- batches, but the HUD may mount after the initial flush)
	task.delay(0.5, function()
		if started and gameEvent then
			gameEvent:FireServer("GetQuests")
			gameEvent:FireServer("GetGlory")
		end
	end)

	-- Capture banners auto-expire if the server stops sending updates (the
	-- progress events only flow while a capture is actively running). Gated on
	-- `started` so this loop actually stops on destroy() instead of accumulating
	-- one live loop per init()/destroy() cycle the way HUD.luau's did.
	task.spawn(function()
		while started do
			task.wait(2)
			if not started then
				break
			end
			local now = os.clock()
			local keepCapture = state.keepCapture
			if keepCapture and now - (keepCapture.receivedAt or 0) > 4 then
				HUDStore.setState({ keepCapture = false })
			end
			local estateCapture = state.estateCapture
			if estateCapture and now - (estateCapture.receivedAt or 0) > 4 then
				HUDStore.setState({ estateCapture = false })
			end
		end
	end)

	-- Poll the selected training building's queue every 0.5s, same cadence
	-- HUD.luau used. Also gated on `started` for the same reason as above.
	task.spawn(function()
		while started do
			task.wait(0.5)
			if started and pollingBuildingId and gameEvent then
				gameEvent:FireServer("GetTrainingQueue", { buildingId = pollingBuildingId })
			end
		end
	end)

	trackConnection(event.OnClientEvent:Connect(function(action: string, data: any)
		if action == "GameStarted" and data.resources then
			local peaceTimeSecs = data.peaceTimeSeconds or 0
			local tutorialEnabled = if data.showTutorial ~= nil then data.showTutorial else true
			HUDStore.setState({
				resources = data.resources,
				tutorialEnabled = tutorialEnabled,
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
		elseif action == "BuildingPlaced" and data.buildingType then
			handleBuildingPlaced(data.buildingType)
		elseif action == "UpdateResources" and data.resources then
			HUDStore.setState({ resources = data.resources })
		elseif action == "StartPlacement" and typeof(data) == "string" then
			HUDStore.setState({ isPlacingBuilding = true, selectedBuilding = data })
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
			HUDStore.setState({ cameraMode = data, showHeroAbilities = data == "King" })
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
					HUDStore.dismissAchievement()
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
		selectionManagerRef = SelectionManager
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
--- this is what makes the store safe across an AdaptiveHUD remount.
function HUDStore.destroy()
	started = false
	gameEvent = nil
	getStatsEvent = nil
	deleteModeEventRef = nil
	resetWallPieceFuncRef = nil
	pollingBuildingId = nil
	selectionManagerRef = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	listeners = {}
	state = defaultState()
end

return HUDStore
