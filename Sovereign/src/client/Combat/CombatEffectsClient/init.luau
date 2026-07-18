--!strict
-- CombatEffectsClient: Renders combat VFX locally from batched server events.
-- The server no longer creates VFX Instances (which replicated to everyone);
-- it sends one CombatEvents payload per combat tick and each client draws it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local EffectsDebug = DebugManager.createChannel("CombatEffects", false)

local CombatEffectsClient = {}

-- Container for all client-side VFX (easy cleanup, no workspace clutter)
local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "ClientCombatEffects"
effectsFolder.Parent = Workspace

-- ═══════════════════════════════════════════════════════════════════════════
-- EFFECT PRIMITIVES
-- ═══════════════════════════════════════════════════════════════════════════

local function makePart(size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = color
	part.Material = material
	part.CastShadow = false
	return part
end

local function hitEffect(position: Vector3, damage: number)
	local isBig = damage >= 40
	local part = makePart(
		Vector3.new(0.5, 0.5, 0.5),
		isBig and Color3.fromRGB(255, 60, 40) or Color3.fromRGB(255, 100, 100),
		Enum.Material.Neon
	)
	part.Position = position
	part.Transparency = 0.3
	part.Parent = effectsFolder

	local goalSize = isBig and Vector3.new(2, 2, 2) or Vector3.new(1, 1, 1)
	TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 1, Size = goalSize }):Play()
	Debris:AddItem(part, 0.35)
end

local function deathEffect(position: Vector3)
	local ring = makePart(Vector3.new(1, 0.3, 1), Color3.fromRGB(120, 120, 120), Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Position = position
	ring.Transparency = 0.4
	ring.Parent = effectsFolder
	TweenService:Create(ring, TweenInfo.new(0.6), { Size = Vector3.new(0.3, 8, 8), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.65)
end

local function buildingHitEffect(position: Vector3, _damage: number)
	local dust = makePart(Vector3.new(1.5, 1.5, 1.5), Color3.fromRGB(150, 130, 100), Enum.Material.Sand)
	dust.Position = position + Vector3.new(math.random(-3, 3), math.random(0, 4), math.random(-3, 3))
	dust.Transparency = 0.2
	dust.Parent = effectsFolder
	TweenService:Create(dust, TweenInfo.new(0.5), { Transparency = 1, Size = Vector3.new(4, 4, 4) }):Play()
	Debris:AddItem(dust, 0.55)
end

local function buildingDestroyedEffect(position: Vector3)
	for _ = 1, 8 do
		local debris = makePart(
			Vector3.new(math.random(1, 3), math.random(1, 3), math.random(1, 3)),
			Color3.fromRGB(120, 100, 80),
			Enum.Material.Slate
		)
		debris.Position = position + Vector3.new(math.random(-6, 6), math.random(2, 8), math.random(-6, 6))
		debris.Parent = effectsFolder
		TweenService:Create(debris, TweenInfo.new(1.2), {
			Transparency = 1,
			Position = debris.Position + Vector3.new(math.random(-8, 8), -6, math.random(-8, 8)),
		}):Play()
		Debris:AddItem(debris, 1.25)
	end
end

-- ── Projectiles: animated along a parabolic arc ────────────────────────────

local PROJECTILE_LOOKS: { [string]: { size: Vector3, color: Color3, material: Enum.Material } } = {
	Arrow = { size = Vector3.new(0.15, 0.15, 2.2), color = Color3.fromRGB(140, 100, 60), material = Enum.Material.Wood },
	Bolt = { size = Vector3.new(0.15, 0.15, 1.4), color = Color3.fromRGB(90, 90, 90), material = Enum.Material.Metal },
	Javelin = { size = Vector3.new(0.2, 0.2, 3.2), color = Color3.fromRGB(120, 90, 50), material = Enum.Material.Wood },
	Stone = { size = Vector3.new(0.6, 0.6, 0.6), color = Color3.fromRGB(130, 130, 130), material = Enum.Material.Slate },
	Magic = { size = Vector3.new(0.7, 0.7, 0.7), color = Color3.fromRGB(120, 220, 160), material = Enum.Material.Neon },
}

type ActiveProjectile = {
	part: Part,
	from: Vector3,
	to: Vector3,
	startTime: number,
	flightTime: number,
	arcHeight: number,
}

local activeProjectiles: { ActiveProjectile } = {}

local function fireProjectileVisual(from: Vector3, to: Vector3, visual: string, flightTime: number)
	if flightTime <= 0 then
		return
	end
	local look = PROJECTILE_LOOKS[visual] or PROJECTILE_LOOKS.Arrow
	local part = makePart(look.size, look.color, look.material)
	part.CFrame = CFrame.lookAt(from, to)
	part.Parent = effectsFolder

	table.insert(activeProjectiles, {
		part = part,
		from = from,
		to = to,
		startTime = os.clock(),
		flightTime = flightTime,
		arcHeight = math.min(12, (to - from).Magnitude * 0.15),
	})
end

RunService.Heartbeat:Connect(function()
	if #activeProjectiles == 0 then
		return
	end
	local now = os.clock()
	for i = #activeProjectiles, 1, -1 do
		local proj = activeProjectiles[i]
		local alpha = (now - proj.startTime) / proj.flightTime
		if alpha >= 1 then
			proj.part:Destroy()
			table.remove(activeProjectiles, i)
		else
			local flat = proj.from:Lerp(proj.to, alpha)
			-- Parabolic arc: peaks at alpha = 0.5
			local height = proj.arcHeight * 4 * alpha * (1 - alpha)
			local pos = flat + Vector3.new(0, height, 0)
			-- Face along velocity for a natural look
			local nextAlpha = math.min(1, alpha + 0.05)
			local nextFlat = proj.from:Lerp(proj.to, nextAlpha)
			local nextHeight = proj.arcHeight * 4 * nextAlpha * (1 - nextAlpha)
			proj.part.CFrame = CFrame.lookAt(pos, nextFlat + Vector3.new(0, nextHeight, 0))
		end
	end
end)

-- ── Ability VFX ────────────────────────────────────────────────────────────

local function abilityEffect(name: string, position: Vector3, radius: number?)
	if name == "WarCry" or name == "BattleSong" or name == "Wail" then
		local color = if name == "WarCry"
			then Color3.fromRGB(255, 200, 0)
			elseif name == "BattleSong" then Color3.fromRGB(100, 180, 255)
			else Color3.fromRGB(180, 80, 220)
		local wave = makePart(Vector3.new(0.5, 1, 1), color, Enum.Material.Neon)
		wave.Shape = Enum.PartType.Cylinder
		wave.Orientation = Vector3.new(0, 0, 90)
		wave.Position = position
		wave.Transparency = 0.5
		wave.Parent = effectsFolder
		local r = (radius or 20) * 2
		TweenService:Create(wave, TweenInfo.new(0.5), { Size = Vector3.new(0.5, r, r), Transparency = 1 }):Play()
		Debris:AddItem(wave, 0.55)
	elseif name == "CelticFury" or name == "Berserk" then
		local color = if name == "CelticFury" then Color3.fromRGB(0, 255, 100) else Color3.fromRGB(255, 80, 0)
		local aura = makePart(Vector3.new(5, 7, 5), color, Enum.Material.Neon)
		aura.Position = position
		aura.Transparency = 0.6
		aura.Parent = effectsFolder
		TweenService:Create(aura, TweenInfo.new(1.2), { Transparency = 1, Size = Vector3.new(7, 9, 7) }):Play()
		Debris:AddItem(aura, 1.25)
	elseif name == "Heal" then
		local glow = makePart(Vector3.new(3, 0.4, 3), Color3.fromRGB(120, 255, 140), Enum.Material.Neon)
		glow.Position = position
		glow.Transparency = 0.4
		glow.Parent = effectsFolder
		TweenService:Create(glow, TweenInfo.new(0.8), {
			Transparency = 1,
			Position = position + Vector3.new(0, 5, 0),
		}):Play()
		Debris:AddItem(glow, 0.85)
	elseif name == "ShieldBash" then
		local flash = makePart(Vector3.new(2, 2, 2), Color3.fromRGB(255, 255, 180), Enum.Material.Neon)
		flash.Position = position
		flash.Transparency = 0.2
		flash.Parent = effectsFolder
		TweenService:Create(flash, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(4, 4, 4) }):Play()
		Debris:AddItem(flash, 0.3)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EVENT INTAKE
-- ═══════════════════════════════════════════════════════════════════════════

type CombatEvent = {
	t: string,
	p: Vector3?,
	p2: Vector3?,
	d: number?,
	n: string?,
	f: number?,
}

local function handleEvents(events: { CombatEvent })
	for _, event in events do
		local pos = event.p
		if not pos then
			continue
		end
		if event.t == "hit" then
			hitEffect(pos, event.d or 0)
		elseif event.t == "death" then
			deathEffect(pos)
		elseif event.t == "proj" and event.p2 then
			fireProjectileVisual(pos, event.p2 :: Vector3, event.n or "Arrow", event.f or 0.5)
		elseif event.t == "ability" and event.n then
			abilityEffect(event.n :: string, pos, event.f)
		elseif event.t == "bhit" then
			buildingHitEffect(pos, event.d or 0)
		elseif event.t == "bdeath" then
			buildingDestroyedEffect(pos)
		end
	end
end

local remoteFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local combatEvents = remoteFolder:WaitForChild("CombatEvents") :: RemoteEvent
combatEvents.OnClientEvent:Connect(handleEvents)

EffectsDebug:info("CombatEffectsClient initialized")

return CombatEffectsClient
