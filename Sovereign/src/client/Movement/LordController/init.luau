--!strict
-- LordController: click-to-move for the LOCAL player's Lord while he is in RTS view.
--
-- ---------------------------------------------------------------------------
-- WHY THIS IS CLIENT-AUTHORITATIVE (and why you must not "fix" it)
-- ---------------------------------------------------------------------------
-- Every other unit is moved by the server: the order goes over
-- RemoteEvents.GameEvent, the server resolves the id with
-- `workspace.Units:FindFirstChild(unitId)`, and MovementSystem drives it with a
-- server-side `Humanoid:MoveTo`. The Lord cannot use that road at all:
--
--   * The Lord IS the player's Character. It has no `UnitId` attribute and it is
--     not parented under `workspace.Units`, so `findUnit()` returns nil and
--     EVERY existing order action ("MoveUnit", "MoveUnitsInFormation",
--     "MoveWorkers", "AttackTarget") is a guaranteed silent no-op for him.
--
--   * The obvious "fix" — parent the Character into `workspace.Units` so it
--     looks like a normal unit — breaks at least ten systems. This has been
--     traced; do not try it:
--       1. The Character is CLIENT-network-owned. A server `Humanoid:MoveTo`
--          fights the client's own control module ? permanent jitter.
--       2. Combat/FogOfWarClient reparents non-visible models into
--          ReplicatedStorage.HiddenByFog. It only skips models owned by ITS
--          LocalPlayer, so every OTHER client would yank your Character out of
--          Workspace — killing the humanoid/camera and tripping the camera's
--          AncestryChanged "Lord removed" cleanup.
--       3. EliminationManager.despawnUnitsForOwner sweeps workspace.Units by
--          OwnerId and DESTROYS matches ? it would destroy the player Character.
--       4. UnitAnimator.watchUnitsFolder would load RTS rig animations onto the
--          R15 avatar and fight the default Animate script.
--       5. HealthBarManager would stack a world health bar on top of the HUD's
--          own KingHealthUpdate bar.
--       6. AIManager / AbilityManager AoE / FogOfWarManager / MiniMap /
--          WorkerAssignmentPanel all blanket-iterate workspace.Units.
--       7. CombatManager.applyGroupMarch rewrites Humanoid.WalkSpeed on every
--          model handed to it even when unregistered — it would clamp the Lord
--          to the slowest peasant's speed and set Marching, only ever restored
--          by MovementSystem's arrival logic, which never runs for a Character
--          outside the Units folder.
--       8. `#playerData.Units` feeds army size / population / tax maths.
--
-- The client already OWNS the network for its own character, so a client-driven
-- `Humanoid:MoveTo` here is smooth and replicates to everyone else for free.
-- That makes this the correct architecture for the Lord specifically, not a
-- shortcut around the server.
--
-- ---------------------------------------------------------------------------
-- INTERACTION WITH THE RTS CAMERA
-- ---------------------------------------------------------------------------
-- In RTS view StudioCameraController calls `_SetCharacterControlsEnabled(false)`
-- because WASD pans the camera. That only Disable()s the PlayerModule
-- ControlModule, which is the thing that writes `Humanoid:Move(dir)` each frame.
-- `Humanoid:MoveTo` sets the humanoid's own walk-to state and is untouched by
-- that — in fact with controls disabled nothing is calling `:Move(0,0,0)` over
-- the top of us each frame, so pathing here is CLEANER in RTS view than it would
-- be in hero view.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local ViewMode = require(ReplicatedStorage.Shared.ViewMode)
local LordDebug = DebugManager.createChannel("LordMovement", false)

local player = Players.LocalPlayer

export type LordControllerModule = {
	init: () -> (),
	moveTo: (position: Vector3) -> boolean,
	stop: () -> (),
	isMoving: () -> boolean,
	getDestination: () -> Vector3?,
	destroy: () -> (),
}

local LordController = {}

-- ---------------------------------------------------------------------------
-- TUNING
-- ---------------------------------------------------------------------------

-- Humanoid:MoveTo silently gives up after 8 seconds. MovementSystem learned this
-- the hard way (`lastMoveToTimes`, ~L107) and re-issues at 0.35s; mirror it or a
-- long march just stops halfway with no error anywhere.
local MOVE_TO_REFRESH: number = 0.35
-- Waypoints are ~4 studs apart; anything tighter than this and the humanoid
-- oscillates around the node instead of advancing.
local WAYPOINT_REACHED: number = 4
local DESTINATION_REACHED: number = 3.5
-- Stuck = less than this much displacement over STUCK_WINDOW while a move is
-- live. R15 gets wedged on doorframes and unit crowds constantly.
local STUCK_WINDOW: number = 1.0
local STUCK_DISPLACEMENT: number = 1.5
local MAX_REPATHS: number = 2

local AGENT_PARAMS = {
	AgentRadius = 2.5,
	AgentHeight = 6,
	AgentCanJump = true,
	WaypointSpacing = 4,
}

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------

local initialized: boolean = false

-- This codebase has a history of leaked connections. EVERY connection made here
-- goes in one of these two lists and is torn down in destroy(); character-scoped
-- ones are additionally cleared on each respawn.
local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
-- ViewMode.Changed hands back a plain disconnect closure, not an RBXScriptConnection.
local viewModeDisconnects: { () -> () } = {}

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

local moving: boolean = false
local destination: Vector3? = nil
local waypoints: { PathWaypoint } = {}
local waypointIndex: number = 1
local lastMoveToTime: number = 0
local repathCount: number = 0
local lastProgressTime: number = 0
local lastProgressPosition: Vector3? = nil
-- Bumped on every moveTo/stop. A ComputeAsync that yields across a newer order
-- compares this and throws its stale path away instead of dragging the Lord back
-- to where the player clicked two orders ago.
local moveGeneration: number = 0

-- ---------------------------------------------------------------------------
-- INTERNALS
-- ---------------------------------------------------------------------------

local function clearCharacterConnections()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function issueMoveTo(target: Vector3)
	local h = humanoid
	if not h then
		return
	end
	h:MoveTo(target)
	lastMoveToTime = os.clock()
end

--- Hard stop. Safe to call when nothing is moving.
function LordController.stop()
	if not moving and destination == nil then
		return
	end

	moving = false
	destination = nil
	table.clear(waypoints)
	waypointIndex = 1
	repathCount = 0
	lastProgressPosition = nil
	moveGeneration += 1

	local h = humanoid
	local root = rootPart
	if h and root then
		-- MoveTo to where we already are, rather than leaving the humanoid's
		-- walk-to state pointing at the old goal — otherwise it keeps drifting
		-- for up to 8 seconds after the "stop".
		h:MoveTo(root.Position)
	end

	LordDebug:info("Movement stopped")
end

function LordController.isMoving(): boolean
	return moving
end

function LordController.getDestination(): Vector3?
	return destination
end

local function startDirect(target: Vector3, generation: number)
	if generation ~= moveGeneration then
		return
	end
	table.clear(waypoints)
	waypointIndex = 1
	issueMoveTo(target)
end

--- Computes a path on a worker thread. Falls back to a straight MoveTo — a Lord
--- that walks into a wall is still better feedback than a click that does
--- nothing, and PathfindingService::ComputeAsync throws on unloaded terrain.
local function computePath(target: Vector3, generation: number)
	local root = rootPart
	if not root then
		return
	end
	local origin = root.Position

	task.spawn(function()
		local path = PathfindingService:CreatePath(AGENT_PARAMS)
		local ok = pcall(function()
			path:ComputeAsync(origin, target)
		end)

		-- The player may have clicked again (or pressed V) while ComputeAsync
		-- yielded. Anything computed for a superseded order is discarded.
		if generation ~= moveGeneration or not moving then
			return
		end

		if not ok or path.Status ~= Enum.PathStatus.Success then
			LordDebug:info("Path failed, walking direct", { status = tostring(path.Status) })
			startDirect(target, generation)
			return
		end

		local computed = path:GetWaypoints()
		if #computed <= 1 then
			startDirect(target, generation)
			return
		end

		waypoints = computed
		-- Waypoint 1 is always the origin; starting there makes the Lord take a
		-- step backwards on every order.
		waypointIndex = 2
		issueMoveTo(waypoints[waypointIndex].Position)
	end)
end

--- Order the Lord to walk to a world position. Returns false when there is no
--- living Lord to order.
function LordController.moveTo(position: Vector3): boolean
	local h = humanoid
	local root = rootPart
	if not h or not root or h.Health <= 0 then
		LordDebug:warn("moveTo with no living Lord")
		return false
	end

	moveGeneration += 1
	local generation = moveGeneration

	moving = true
	destination = position
	repathCount = 0
	lastProgressTime = os.clock()
	lastProgressPosition = root.Position

	-- Move immediately on the direct line so the Lord reacts on the same frame
	-- as the click; the path (one frame later, at best) refines it.
	table.clear(waypoints)
	waypointIndex = 1
	issueMoveTo(position)

	computePath(position, generation)

	LordDebug:info("Lord ordered to move", { target = position })
	return true
end

local function step()
	if not moving then
		return
	end

	local h = humanoid
	local root = rootPart
	local dest = destination
	if not h or not root or not dest or h.Health <= 0 then
		LordController.stop()
		return
	end

	local now = os.clock()
	local position = root.Position

	-- -- Arrival ----------------------------------------------------------
	local flatToDest = (Vector3.new(dest.X, 0, dest.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
	if flatToDest <= DESTINATION_REACHED then
		LordController.stop()
		return
	end

	-- -- Follow the path --------------------------------------------------
	local target: Vector3 = dest
	local waypoint = waypoints[waypointIndex]
	if waypoint then
		target = waypoint.Position
		local flatToWaypoint =
			(Vector3.new(target.X, 0, target.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
		if flatToWaypoint <= WAYPOINT_REACHED then
			waypointIndex += 1
			local nextWaypoint = waypoints[waypointIndex]
			if nextWaypoint then
				-- Jump is a property of the waypoint you are heading TOWARDS, so
				-- it has to be triggered as we commit to it, not on arrival.
				if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
					h.Jump = true
				end
				target = nextWaypoint.Position
			else
				table.clear(waypoints)
				waypointIndex = 1
				target = dest
			end
			issueMoveTo(target)
			return
		end
	end

	-- -- Re-issue before MoveTo's 8s timeout ------------------------------
	if now - lastMoveToTime >= MOVE_TO_REFRESH then
		issueMoveTo(target)
	end

	-- -- Stuck detection --------------------------------------------------
	local previous = lastProgressPosition
	if not previous then
		lastProgressPosition = position
		lastProgressTime = now
		return
	end

	if (position - previous).Magnitude > STUCK_DISPLACEMENT then
		lastProgressPosition = position
		lastProgressTime = now
		return
	end

	if now - lastProgressTime >= STUCK_WINDOW then
		lastProgressPosition = position
		lastProgressTime = now
		if repathCount < MAX_REPATHS then
			repathCount += 1
			LordDebug:info("Lord stuck, recomputing path", { attempt = repathCount })
			computePath(dest, moveGeneration)
		else
			-- Wedged on geometry with no path out. Giving up beats leaving him
			-- grinding into a wall forever with an active "moving" state.
			LordDebug:warn("Lord stuck with no path, abandoning order")
			LordController.stop()
		end
	end
end

-- ---------------------------------------------------------------------------
-- CHARACTER LIFECYCLE
-- ---------------------------------------------------------------------------

local function bindCharacter(newCharacter: Model)
	clearCharacterConnections()

	humanoid = newCharacter:FindFirstChildOfClass("Humanoid")
	rootPart = (newCharacter:FindFirstChild("HumanoidRootPart") :: any) :: BasePart?

	-- Any queued order belongs to the previous body.
	moving = false
	destination = nil
	table.clear(waypoints)
	waypointIndex = 1
	moveGeneration += 1

	local h = humanoid
	if h then
		table.insert(
			characterConnections,
			h.Died:Connect(function()
				LordController.stop()
			end)
		)
	end

	table.insert(
		characterConnections,
		newCharacter.AncestryChanged:Connect(function(_, parent)
			if not parent then
				LordController.stop()
			end
		end)
	)
end

-- ---------------------------------------------------------------------------
-- MANUAL-CONTROL CANCELLATION
-- ---------------------------------------------------------------------------

local MANUAL_CONTROL_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Space] = true,
}

function LordController.init()
	if initialized then
		return
	end
	initialized = true

	if player.Character then
		bindCharacter(player.Character)
	end

	table.insert(
		connections,
		player.CharacterAdded:Connect(function(newCharacter)
			-- HumanoidRootPart is not guaranteed to exist the instant
			-- CharacterAdded fires.
			newCharacter:WaitForChild("HumanoidRootPart", 10)
			newCharacter:WaitForChild("Humanoid", 10)
			bindCharacter(newCharacter)
		end)
	)

	table.insert(
		connections,
		player.CharacterRemoving:Connect(function()
			LordController.stop()
			clearCharacterConnections()
			humanoid = nil
			rootPart = nil
		end)
	)

	-- Entering hero view means the player has taken the wheel. A queued RTS
	-- click-move that keeps dragging him around mid-fight is the single most
	-- infuriating failure mode this system has, so kill it the moment the mode
	-- flips — not when the blend finishes.
	table.insert(
		viewModeDisconnects,
		ViewMode.Changed:connect(function(newMode: ViewMode.Mode)
			if newMode ~= "RTS" then
				LordController.stop()
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed or not moving then
				return
			end
			-- In RTS view WASD pans the CAMERA (character controls are disabled),
			-- so cancelling on it there would abort the order every time the
			-- player scrolled the map. Only treat movement keys as "manual
			-- control" once we are out of RTS, where they actually drive the Lord.
			if ViewMode.isRTS() then
				return
			end
			if input.UserInputType == Enum.UserInputType.Keyboard and MANUAL_CONTROL_KEYS[input.KeyCode] then
				LordController.stop()
			end
		end)
	)

	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			step()
		end)
	)

	LordDebug:info("Initialized")
end

--- Full teardown. Only used by tests / hot reload, but it exists so no
--- connection made here can outlive the module.
function LordController.destroy()
	LordController.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearCharacterConnections()
	for _, disconnect in viewModeDisconnects do
		disconnect()
	end
	table.clear(viewModeDisconnects)
	initialized = false
end

LordController.init()

return LordController
