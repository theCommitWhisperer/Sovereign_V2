--!strict
-- CombatReplication: Batches combat visual events into one RemoteEvent payload
-- per combat tick. Replaces server-side Instance VFX (parts/tweens created on
-- the server replicated everything each frame); clients now render locally.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)

local CombatReplication = {}

export type CombatEvent = {
	t: string, -- "hit" | "death" | "proj" | "ability" | "bhit" | "bdeath" | "swing"
	p: Vector3?, -- position
	p2: Vector3?, -- secondary position (projectile target)
	d: number?, -- damage
	n: string?, -- name/kind (ability name, projectile visual)
	f: number?, -- float payload (radius, flight time)
	m: Model?, -- instance payload (swinging unit)
}

local queue: { CombatEvent } = {}
local remote: RemoteEvent? = nil

-- GameManager creates the RemoteEvents folder unconditionally at startup, and
-- CombatManager.init() runs before that line — so we must NOT create the folder
-- here (we'd end up with two folders named "RemoteEvents"). Wait for it instead.
local function setupRemote()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("RemoteEvents", 15)
		if not folder then
			-- Standalone/test place without GameManager: create our own
			folder = Instance.new("Folder")
			folder.Name = "RemoteEvents"
			folder.Parent = ReplicatedStorage
		end
		local event = folder:FindFirstChild("CombatEvents") :: RemoteEvent?
		if not event then
			local newEvent = Instance.new("RemoteEvent")
			newEvent.Name = "CombatEvents"
			newEvent.Parent = folder
			event = newEvent
		end
		remote = event
	end)
end

function CombatReplication.push(event: CombatEvent)
	if #queue < CombatConfig.Engine.MAX_REPLICATION_EVENTS_PER_TICK then
		table.insert(queue, event)
	end
end

function CombatReplication.hit(position: Vector3, damage: number)
	CombatReplication.push({ t = "hit", p = position, d = damage })
end

function CombatReplication.death(position: Vector3)
	CombatReplication.push({ t = "death", p = position })
end

function CombatReplication.buildingHit(position: Vector3, damage: number)
	CombatReplication.push({ t = "bhit", p = position, d = damage })
end

function CombatReplication.buildingDestroyed(position: Vector3)
	CombatReplication.push({ t = "bdeath", p = position })
end

function CombatReplication.projectile(from: Vector3, to: Vector3, visual: string, flightTime: number)
	CombatReplication.push({ t = "proj", p = from, p2 = to, n = visual, f = flightTime })
end

function CombatReplication.ability(name: string, position: Vector3, radius: number?)
	CombatReplication.push({ t = "ability", p = position, n = name, f = radius })
end

-- Melee swing: clients animate the unit's weapon grip weld
function CombatReplication.swing(unitModel: Model)
	CombatReplication.push({ t = "swing", m = unitModel })
end

-- Called once per combat tick by CombatService
function CombatReplication.flush()
	if #queue == 0 then
		return
	end
	local activeRemote = remote
	if activeRemote then
		activeRemote:FireAllClients(queue)
	end
	queue = {} -- drop events queued before the remote is ready (pre-game VFX only)
end

function CombatReplication.init()
	setupRemote()
end

return CombatReplication
