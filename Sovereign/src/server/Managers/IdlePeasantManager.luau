--!strict
-- IdlePeasantManager: Manages idle peasant behavior (campfire gathering + roaming)
-- Peasants not assigned to work tasks will either:
-- 1. Gather around a campfire near the Keep SpawnPoint (60% of idle peasants)
-- 2. Roam around the Keep area (40% of idle peasants)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local UnitAnimations = require(ReplicatedStorage.Shared.GameData.UnitAnimationsData)
local SpawnPointSystem = require(script.Parent.Parent.Systems.SpawnPointSystem)

local IdlePeasantManager = {}

-- Debug channel
local IdleDebug = DebugManager.createChannel("IdlePeasant", false)

-- Idle peasant behavior tracking
export type IdleBehavior = {
	peasant: Model,
	behaviorType: "Campfire" | "Roaming",
	ownerId: number,
	campfirePosition: Vector3?, -- Position to gather at (for Campfire behavior)
	-- Which of the CAMPFIRE_POSITIONS_COUNT slots this peasant owns. Held so no
	-- two peasants are ever sent to the same spot; freed when the entry is
	-- removed from IdlePeasants, which is the only place it's tracked.
	slotIndex: number?,
	campfireCenter: Vector3?, -- The fire itself, so seated peasants can face it
	seated: boolean?, -- Already arrived and sitting; stops re-facing every tick
	arriveBy: number?, -- tick() deadline; see CAMPFIRE_ARRIVAL_TIMEOUT
	roamCenter: Vector3?, -- Center point for roaming (for Roaming behavior)
	roamRadius: number, -- Roaming radius (default: 30 studs)
	roamMinRadius: number?, -- Minimum distance from center (outside obstacle)
	nextRoamTime: number, -- When to pick a new roaming destination
	targetPosition: Vector3?, -- Current roaming target
}

local IdlePeasants: { IdleBehavior } = {}
local lastBehaviorUpdate = 0
local BEHAVIOR_UPDATE_INTERVAL = 2 -- Update behaviors every 2 seconds
local ROAM_RADIUS = 30 -- Peasants roam within 30 studs of Keep
local CAMPFIRE_POSITIONS_COUNT = 6 -- 6 positions around the campfire
local CAMPFIRE_RADIUS = 8 -- 8 studs from SpawnPoint (fallback when no fire model)
-- Ring radius when we DO have a Campfire model. The fire is ~6.4 studs across,
-- so 5 studs from centre puts peasants just outside it, close enough to read as
-- huddled rather than loitering nearby.
-- The fire itself is ~6.4 studs across, i.e. ~3.2 from centre. At 5 studs a
-- peasant sat less than two studs clear of the flames, so any shove put someone
-- inside them. 7 leaves ~3.8 studs of clearance and still reads as huddled.
local CAMPFIRE_MODEL_RADIUS = 7

-- How long a peasant may spend trying to reach its campfire slot before we give
-- up and let it sit where it stands.
--
-- This exists because the campfire is INSIDE the Keep's bounding box, whereas
-- every other idle position is deliberately pushed outside it (see
-- safeIdleRadius below). If the Keep's footprint is treated as one solid
-- pathfinding obstacle, the slot is unreachable and the peasant would walk on
-- the spot forever with no error anywhere. Timing out converts that silent hang
-- into a logged warning plus a peasant that at least looks settled.
local CAMPFIRE_ARRIVAL_TIMEOUT = 30

-- Get campfire positions in a circle around Keep's SpawnPoint.
-- radius parameter overrides CAMPFIRE_RADIUS so positions can be pushed
-- outside the Keep's pathfinding obstacle.
local function getCampfirePositions(keepSpawnPoint: Vector3, count: number, radius: number?): { Vector3 }
	local positions = {}
	local r = radius or CAMPFIRE_RADIUS

	for i = 1, count do
		local angle = (math.pi * 2 * (i - 1)) / count
		local xOffset = math.cos(angle) * r
		local zOffset = math.sin(angle) * r
		local position = keepSpawnPoint + Vector3.new(xOffset, 0, zOffset)
		table.insert(positions, position)
	end

	return positions
end

-- Locate the actual fire inside a Keep.
--
-- Before this, "campfire" peasants were arranged around the Keep's SPAWN POINT
-- at a radius wide enough to clear the whole building — on the Stone Wall Large
-- Keep that works out to a 76-stud circle, so the gathering had nothing to do
-- with the fire and read as peasants loitering around the perimeter.
--
-- Returns nil when a Keep has no Campfire, and the caller falls back to the old
-- spawn-point ring. Not every Keep model is guaranteed to have one.
-- Sit down / stand up, including the hover correction.
--
-- The Humanoid parks its root a fixed height above the ground no matter what
-- the rig is doing, so a seated pose — legs folded, body lower — leaves the
-- unit hanging in mid-air. Dropping HipHeight by the clip's measured `sitHipDrop`
-- puts it back on the ground. The original height is stashed on the model rather
-- than recomputed, because the six peasant rigs each have their own (1.65–2.12).
-- Lower the seated body WITHOUT touching physics.
--
-- The obvious lever is Humanoid.HipHeight, and it is the wrong one. A skinned
-- rig's root part is its only collider, so lowering HipHeight walks the collider
-- down towards the floor; at 0 the root's bottom face is resting on the ground
-- while the Humanoid is still trying to maintain that clearance against it, and
-- the unit never settles. It reads exactly like "the ground is interfering".
--
-- These rigs stand at 1.65–2.12, so a 1.90 drop pinned five of the six at
-- HipHeight 0. Only Male_Peasant_3 (2.12, landing at 0.22) had room to spare —
-- and it was the only one that sat correctly. That was the tell.
--
-- So the whole drop goes through the RootJoint instead. It shifts the MESH
-- relative to the root, which is purely visual: the Humanoid keeps its normal
-- standing HipHeight, the collider never approaches the floor, and there is no
-- lower limit to hit. Every rig drops by exactly `sitHipDrop`.
--
-- Safe from the animation: clips drive BONES (poses named Hips, Spine, …) and
-- this Motor6D's Part1 is the mesh itself, so nothing overwrites C0.
--
-- The trade-off is that a seated peasant's collision capsule stays at standing
-- height. For a stationary unit at a campfire that is invisible, and it keeps a
-- little personal space around the fire rather than letting units walk through.
local function findRootJoint(peasant: Model): Motor6D?
	local root = peasant.PrimaryPart
	if not root then
		return nil
	end
	local joint = root:FindFirstChild("RootJoint")
	return (joint and joint:IsA("Motor6D")) and joint or nil
end

local function setSeated(peasant: Model, seated: boolean)
	local joint = findRootJoint(peasant)

	if seated then
		peasant:SetAttribute(UnitAnimations.POSE_ATTRIBUTE, "sit")

		-- Guarded on the stored drop so the 2-second update loop can call this
		-- repeatedly without sinking the peasant a little further each pass.
		if joint and peasant:GetAttribute("SitJointDrop") == nil then
			local set = UnitAnimations.getSet(peasant:GetAttribute("AnimSet") :: string?)
			local drop = set and set.sitHipDrop or 0
			if drop > 0 then
				joint.C0 = joint.C0 * CFrame.new(0, -drop, 0)
				peasant:SetAttribute("SitJointDrop", drop)
			end
		end
		return
	end

	peasant:SetAttribute(UnitAnimations.POSE_ATTRIBUTE, nil)

	-- Restore by the exact amount applied, so repeated sit/stand cycles can't
	-- accumulate drift.
	local jointDrop = peasant:GetAttribute("SitJointDrop") :: number?
	if jointDrop and joint then
		joint.C0 = joint.C0 * CFrame.new(0, jointDrop, 0)
	end
	peasant:SetAttribute("SitJointDrop", nil)
end

local function findCampfire(keep: Model): Vector3?
	local fire = keep:FindFirstChild("Campfire", true)
	if not fire then
		return nil
	end
	if fire:IsA("BasePart") then
		return fire.Position
	end
	if fire:IsA("Model") then
		-- Campfire models here have no PrimaryPart, so the bounding box centre is
		-- the only thing available.
		local cf = fire:GetBoundingBox()
		return cf.Position
	end
	return nil
end

-- Find Keep for a player
local function findPlayerKeep(ownerId: number): Model?
	local PlayerManager = require(script.Parent.PlayerManager)
	local Players = game:GetService("Players")

	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == ownerId then
			local playerData = PlayerManager.get(player)
			if playerData and playerData.Keep then
				return playerData.Keep
			end
			break
		end
	end

	return nil
end

-- Add a peasant to idle behavior
function IdlePeasantManager.addIdlePeasant(peasant: Model, ownerId: number)
	-- Remove if already exists
	for i = #IdlePeasants, 1, -1 do
		if IdlePeasants[i].peasant == peasant then
			table.remove(IdlePeasants, i)
			break
		end
	end

	-- Find the player's Keep
	local keep = findPlayerKeep(ownerId)
	if not keep then
		IdleDebug:warn(`Cannot add idle peasant - no Keep found for owner {ownerId}`)
		return
	end

	-- Get Keep's SpawnPoint
	local spawnPoint = SpawnPointSystem.getSpawnPosition(keep)
	if not spawnPoint then
		IdleDebug:warn(`Keep has no SpawnPoint - using Keep center`)
		spawnPoint = keep.PrimaryPart and keep.PrimaryPart.Position or Vector3.new(0, 0, 0)
	end

	-- Compute a safe idle radius that sits outside the Keep's pathfinding obstacle.
	-- The obstacle covers the model bounding box + 2-stud padding, so we add a margin.
	local _, keepSize = keep:GetBoundingBox()
	local safeIdleRadius = math.max(keepSize.X, keepSize.Z) / 2 + 10

	-- Gather at the fire itself when the Keep has one; otherwise fall back to the
	-- old wide ring around the spawn point, which at least keeps peasants clear
	-- of the Keep's obstacle.
	local fireCenter = findCampfire(keep)
	local ringCenter = fireCenter or spawnPoint
	local ringRadius = if fireCenter then CAMPFIRE_MODEL_RADIUS else safeIdleRadius
	local campfirePositions = getCampfirePositions(ringCenter, CAMPFIRE_POSITIONS_COUNT, ringRadius)

	-- Claim a slot EXCLUSIVELY.
	--
	-- This used to be `campfirePositions[math.random(1, #campfirePositions)]` — a
	-- random pick WITH REPLACEMENT, so two peasants could be sent to the same
	-- spot. They then shoved each other off it, and with the ring drawn tight
	-- around the fire the loser ended up standing in the flames.
	--
	-- Six slots is therefore a hard cap on how many can sit at one fire. This is
	-- resolved BEFORE choosing a behaviour, because "the fire is full" has to be
	-- able to turn a would-be sitter into a roamer.
	local taken: { [number]: boolean } = {}
	for _, existing in IdlePeasants do
		if existing.ownerId == ownerId and existing.slotIndex then
			taken[existing.slotIndex] = true
		end
	end

	local free = {}
	for i = 1, #campfirePositions do
		if not taken[i] then
			table.insert(free, i)
		end
	end

	-- 60/40 campfire/roaming as before, but a full fire forces roaming.
	local behaviorType: "Campfire" | "Roaming" = (math.random() < 0.6 and #free > 0) and "Campfire" or "Roaming"

	local behavior: IdleBehavior

	if behaviorType == "Campfire" then
		local slotIndex = free[math.random(1, #free)]
		local slotPosition = campfirePositions[slotIndex]

		behavior = {
			peasant = peasant,
			behaviorType = "Campfire",
			ownerId = ownerId,
			slotIndex = slotIndex,
			campfirePosition = slotPosition,
			campfireCenter = fireCenter,
			seated = false,
			arriveBy = tick() + CAMPFIRE_ARRIVAL_TIMEOUT,
			roamCenter = nil,
			roamRadius = ROAM_RADIUS,
			nextRoamTime = 0,
			targetPosition = slotPosition,
		}

		IdleDebug:info(
			`Peasant {peasant.Name} -> campfire slot {slotIndex}/{CAMPFIRE_POSITIONS_COUNT} at {slotPosition} `
				.. `({fireCenter and "fire model" or "spawn-point fallback"})`
		)
	else
		-- Roaming behavior — roam between safeIdleRadius and safeIdleRadius+ROAM_RADIUS
		-- so targets always land outside the Keep obstacle
		behavior = {
			peasant = peasant,
			behaviorType = "Roaming",
			ownerId = ownerId,
			campfirePosition = nil,
			roamCenter = spawnPoint,
			roamRadius = ROAM_RADIUS,
			roamMinRadius = safeIdleRadius, -- minimum distance to stay outside obstacle
			nextRoamTime = tick() + math.random(2, 5), -- Random initial delay
			targetPosition = nil,
		}

		IdleDebug:info(`Peasant {peasant.Name} assigned to Roaming around {spawnPoint}`)
	end

	table.insert(IdlePeasants, behavior)
	peasant:SetAttribute("IsIdle", true)
end

-- Remove a peasant from idle behavior (when assigned to work/hauling)
function IdlePeasantManager.removeIdlePeasant(peasant: Model)
	for i = #IdlePeasants, 1, -1 do
		if IdlePeasants[i].peasant == peasant then
			table.remove(IdlePeasants, i)
			peasant:SetAttribute("IsIdle", false)
			-- Stand up. A peasant pulled off the fire to go and work must not keep
			-- the seated pose — it would sit down again the moment it stops, and
			-- would keep the lowered HipHeight and sink into the ground.
			setSeated(peasant, false)
			IdleDebug:info(`Removed {peasant.Name} from idle behavior`)
			return true
		end
	end
	return false
end

-- Check if a peasant is idle
function IdlePeasantManager.isIdle(peasant: Model): boolean
	for _, behavior in ipairs(IdlePeasants) do
		if behavior.peasant == peasant then
			return true
		end
	end
	return false
end

-- Get all idle peasants for a specific owner
function IdlePeasantManager.getIdlePeasantsForOwner(ownerId: number): { Model }
	local peasants = {}
	for _, behavior in ipairs(IdlePeasants) do
		if behavior.ownerId == ownerId then
			table.insert(peasants, behavior.peasant)
		end
	end
	return peasants
end

-- Pathfind peasant to a position
local function pathfindToPosition(unit: Model, targetPos: Vector3, threshold: number): boolean
	if not unit.PrimaryPart then
		return false
	end

	local currentPos = unit.PrimaryPart.Position
	local distance2D = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude

	-- Check if arrived
	if distance2D <= threshold then
		unit:SetAttribute("IsMoving", false)
		unit:SetAttribute("TargetPosition", nil)
		return true
	end

	-- Set pathfinding target (MovementSystem will handle the actual pathfinding)
	local currentTarget = unit:GetAttribute("TargetPosition")
	if not currentTarget or (currentTarget - targetPos).Magnitude > 1 then
		unit:SetAttribute("TargetPosition", targetPos)
		unit:SetAttribute("IsMoving", true)
	end

	return false
end

-- Update idle behaviors
local function updateIdleBehaviors(dt: number)
	for i = #IdlePeasants, 1, -1 do
		local behavior = IdlePeasants[i]

		-- Check if peasant still exists
		if not behavior.peasant or not behavior.peasant.Parent then
			table.remove(IdlePeasants, i)
			continue
		end

		-- Check if peasant was assigned to work (should have been removed)
		if behavior.peasant:GetAttribute("IsWorking") or behavior.peasant:GetAttribute("IsHauling") then
			table.remove(IdlePeasants, i)
			behavior.peasant:SetAttribute("IsIdle", false)
			-- Second removal path (the other is removeIdlePeasant): a peasant that
			-- picked up a job while seated must stand up here too, or it would sit
			-- down again at the first pause in its work.
			setSeated(behavior.peasant, false)
			continue
		end

		if behavior.behaviorType == "Campfire" then
			-- Campfire behavior: walk to the assigned slot, then sit down.
			if behavior.campfirePosition then
				local arrived = pathfindToPosition(behavior.peasant, behavior.campfirePosition, 2)

				if not arrived and behavior.arriveBy and tick() > behavior.arriveBy then
					-- Couldn't get there. Overwhelmingly likely the slot is inside
					-- the Keep's pathfinding obstacle; say so rather than letting the
					-- peasant walk on the spot forever.
					IdleDebug:warn(
						`{behavior.peasant.Name} could not reach its campfire slot in `
							.. `{CAMPFIRE_ARRIVAL_TIMEOUT}s — sitting where it stands. If this fires for `
							.. `every peasant, the Campfire is unreachable inside the Keep's obstacle; `
							.. `move the fire outside the footprint or exclude the Keep interior.`
					)
					arrived = true
					behavior.peasant:SetAttribute("IsMoving", false)
					behavior.peasant:SetAttribute("TargetPosition", nil)
				end

				if arrived and not behavior.seated then
					behavior.seated = true
					behavior.arriveBy = nil
					-- Turn to face the fire before sitting, so the ring reads as a
					-- circle around it rather than six people facing at random.
					local root = behavior.peasant.PrimaryPart
					if root and behavior.campfireCenter then
						local here = root.Position
						local look = Vector3.new(behavior.campfireCenter.X, here.Y, behavior.campfireCenter.Z)
						if (look - here).Magnitude > 0.05 then
							behavior.peasant:PivotTo(CFrame.lookAt(here, look))
						end
					end
					-- UnitAnimator swaps idle for the seated clip. It only takes
					-- effect once the unit is actually stationary, so there's no
					-- hand-off to get wrong: an order to move elsewhere makes the
					-- peasant walk, and walking outranks the pose.
					setSeated(behavior.peasant, true)
				elseif not arrived and behavior.seated then
					-- Pushed off its slot (shoved by a crowd, or re-targeted): stand
					-- back up so it doesn't slide to the fire in a seated pose.
					behavior.seated = false
					setSeated(behavior.peasant, false)
				end
			end

		elseif behavior.behaviorType == "Roaming" then
			-- Roaming behavior: Pick random positions within radius
			if behavior.roamCenter then
				-- Time to pick a new roaming target?
				if tick() >= behavior.nextRoamTime then
					-- Pick a random position within roam radius
					local angle = math.random() * math.pi * 2
					local distance = math.random() * behavior.roamRadius
					local xOffset = math.cos(angle) * distance
					local zOffset = math.sin(angle) * distance

					behavior.targetPosition = behavior.roamCenter + Vector3.new(xOffset, 0, zOffset)
					behavior.nextRoamTime = tick() + math.random(5, 10) -- Next roam in 5-10 seconds

					IdleDebug:info(`Peasant {behavior.peasant.Name} roaming to {behavior.targetPosition}`)
				end

				-- Pathfind to current roaming target
				if behavior.targetPosition then
					local arrived = pathfindToPosition(behavior.peasant, behavior.targetPosition, 3)
					if arrived then
						-- Reached target, pick a new one soon
						behavior.nextRoamTime = tick() + math.random(2, 4)
					end
				end
			end
		end
	end
end

-- Update loop
function IdlePeasantManager.update(dt: number)
	lastBehaviorUpdate = lastBehaviorUpdate + dt

	if lastBehaviorUpdate >= BEHAVIOR_UPDATE_INTERVAL then
		updateIdleBehaviors(dt)
		lastBehaviorUpdate = 0
	end
end

return IdlePeasantManager
