--!strict
-- HeroCombat: the server-authoritative state machine for the player's Lord.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS OWNS
-- ---------------------------------------------------------------------------
-- Third-person hero combat: a 3-hit light combo chain, a committed heavy, a
-- shield block with a parry window, a dodge roll with i-frames, and a bow shot.
-- The client reports INTENT ("I pressed light, I'm aiming here") and plays
-- feedback; every legality question — is that transition legal, is the cooldown
-- up, is the aim vector real, how much damage lands, did the parry connect — is
-- answered here.
--
-- All tuning lives in CombatConfig.Hero. Nothing in this file is a magic number.
--
-- ---------------------------------------------------------------------------
-- WHY THERE IS NO LOOP
-- ---------------------------------------------------------------------------
-- The combat engine ticks at COMBAT_TICK_RATE (0.1s) over potentially hundreds
-- of units. Hero state is per-PLAYER, so adding it to that tick would be a waste
-- and adding a second Heartbeat would be worse. Instead:
--
--   • every timing field is an ABSOLUTE os.clock() timestamp,
--   • `refresh()` lapses whatever has expired, and is called at the top of every
--     public entry point (a request, or a hit landing on the hero),
--   • the only scheduled work is the windup?active?recovery progression of an
--     in-flight swing, because a swing's damage has to land whether or not the
--     player touches the mouse again.
--
-- ---------------------------------------------------------------------------
-- THE STALE-CALLBACK GUARD (read this before adding a task.delay)
-- ---------------------------------------------------------------------------
-- This codebase has shipped this bug more than once: a task.delay fires after
-- the state it was written for has already been replaced, and clobbers the newer
-- state. Here, every state entry increments `stateToken`. A scheduled callback
-- captures the token it was scheduled under and `schedule()` drops it if the
-- token has moved on, or if the player has been unregistered / re-registered
-- since. The chain windup?active?recovery therefore re-captures the token at
-- each step. If you add a delayed callback, route it through `schedule()`.
--
-- ---------------------------------------------------------------------------
-- STATE TRANSITIONS
-- ---------------------------------------------------------------------------
--   Idle      ? Windup (light/heavy/ranged) | Blocking (RMB down) | Dodging
--   Windup    ? Active (timer) | Staggered (heavy hit taken)
--   Active    ? Recovery (timer)
--   Recovery  ? Idle/Blocking (timer)
--   Blocking  ? Idle (RMB up) | Windup (attacking drops the shield) | Dodging
--   Dodging   ? Recovery (timer)
--   Staggered ? Idle/Blocking (timer)
--
-- Anything else is rejected. Notably you CANNOT dodge out of Windup or Active:
-- dodge-cancelling a committed swing would make commitment free, and the heavy's
-- long windup is the only counterplay an opponent gets.
--
-- ---------------------------------------------------------------------------
-- THE DODGE OWNERSHIP SPLIT (deliberate tradeoff)
-- ---------------------------------------------------------------------------
-- The CLIENT owns the roll MOVEMENT; the SERVER owns the i-frame window and the
-- cooldown. This is not laziness — the player's character has client network
-- ownership, so a server-side CFrame write or LinearVelocity fights the client's
-- own physics simulation and produces the rubber-banding this project already
-- fought once in MovementSystem. The exploit surface is bounded and acceptable:
-- a hacked client can roll further or faster than intended (a movement-speed
-- cheat, which it already has by other means) but it CANNOT grant itself extra
-- i-frames, shorten the cooldown, or dodge while committed to a swing, because
-- none of that is client state. `dodgeUntil` is replicated back purely so the
-- client knows how long to animate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local CombatTypes = require(script.Parent.CombatTypes)
local CombatService = require(script.Parent.CombatService)
local CombatReplication = require(script.Parent.CombatReplication)

local HeroDebug = DebugManager.createChannel("HeroCombat", false)

type CombatUnit = CombatTypes.CombatUnit
type HeroState = CombatTypes.HeroState
type HeroActionState = CombatTypes.HeroActionState

local Hero = CombatConfig.Hero

local HeroCombat = {}

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------

-- Keyed by UserId. `byCharacter` is a second index so isInvulnerable() can
-- answer from a Model alone (the projectile/hit paths only have one).
local heroes: { [number]: HeroState } = {}
local byCharacter: { [Model]: HeroState } = {}

-- Per-player tuning overrides (arena vs normal game). Kept alongside the state
-- so unregister() drops both together — this codebase has a history of leaking
-- per-player tables, so every table keyed by UserId in this file is cleared in
-- exactly one place: `dropPlayer`.
export type HeroOptions = {
	maxHealth: number?,
}

local initialized = false

-- ---------------------------------------------------------------------------
-- VALIDATION (assume a hostile client)
-- ---------------------------------------------------------------------------

-- Reject NaN, zero-length, and absurd-magnitude vectors, then flatten to the XZ
-- plane and normalize. Returns nil when the caller must reject the whole request.
--
-- NaN needs an explicit test: NaN ~= NaN, so `magnitude > 1e-3` is FALSE for NaN
-- and a naive guard lets it through as "too short", but `Vector3.Unit` on a NaN
-- vector produces NaN and every downstream dot product silently becomes false —
-- which reads in-game as "my sword stopped working" rather than as an error.
local function sanitizeDirection(value: any): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local vector = value :: Vector3
	if vector.X ~= vector.X or vector.Y ~= vector.Y or vector.Z ~= vector.Z then
		return nil
	end
	local flat = Vector3.new(vector.X, 0, vector.Z)
	local magnitude = flat.Magnitude
	if magnitude < 1e-3 or magnitude > 1e6 then
		return nil
	end
	return flat / magnitude
end

HeroCombat.sanitizeDirection = sanitizeDirection

local function reject(state: HeroState?, what: string, why: string)
	-- Rejections are LOGGED, not thrown and not surfaced to the client. A
	-- legitimate client hits these constantly through simple latency (it predicts
	-- a combo chain that the server has already timed out), so a notification
	-- would be noise. A hostile client hitting them in a tight loop shows up here.
	HeroDebug:info("Rejected hero action", {
		action = what,
		reason = why,
		userId = state and state.userId or 0,
		state = state and state.state or "unregistered",
	})
end

-- ---------------------------------------------------------------------------
-- STATE MACHINE CORE
-- ---------------------------------------------------------------------------

local BLOCK_FOREVER = math.huge -- Blocking lapses on release, never on a timer

--- Enter `newState` and return the token that identifies THIS entry. Any
--- previously scheduled callback becomes stale the moment this is called.
local function enterState(state: HeroState, newState: HeroActionState, duration: number): number
	state.stateToken += 1
	state.state = newState
	state.stateExpiresAt = if duration == BLOCK_FOREVER then BLOCK_FOREVER else os.clock() + math.max(0, duration)
	return state.stateToken
end

--- Schedule `callback` in `delay` seconds, but only run it if the hero is still
--- registered as the SAME state table and is still in the state identified by
--- `token`. See "THE STALE-CALLBACK GUARD" above.
local function schedule(state: HeroState, token: number, delay: number, callback: () -> ())
	task.delay(delay, function()
		if heroes[state.userId] ~= state then
			return -- unregistered, or re-registered on a fresh character
		end
		if state.stateToken ~= token then
			return -- superseded: staggered, dodged, unblocked, killed, re-swung
		end
		callback()
	end)
end

--- True while the hero's shield is actually up. Distinguishes INTENT
--- (`state.blocking` — the client is holding RMB) from POSTURE (you cannot be
--- guarding while your own sword is mid-swing). Without this split, holding RMB
--- and spamming LMB would give permanent 65% damage reduction for free.
local function isGuarding(state: HeroState): boolean
	return state.blocking and (state.state == "Blocking" or state.state == "Idle")
end

--- Lapse everything that has expired. Idempotent and cheap; called at the top of
--- every public entry point instead of from a loop.
local function refresh(state: HeroState, now: number)
	local current = state.state
	local transient = current == "Windup"
		or current == "Active"
		or current == "Recovery"
		or current == "Dodging"
		or current == "Staggered"

	if transient and now >= state.stateExpiresAt and now >= state.nextActionAt then
		-- Return to the posture the player is actually holding. Note this does NOT
		-- touch blockStartedAt: re-entering Blocking after a swing must not re-arm
		-- the parry window, or "swing, hold block, swing" would be an infinite
		-- supply of parries off one right-click.
		if state.blocking then
			enterState(state, "Blocking", BLOCK_FOREVER)
		else
			enterState(state, "Idle", 0)
		end
	end

	if state.comboIndex > 0 and now >= state.comboExpiresAt then
		state.comboIndex = 0
	end

	-- Stamina (default OFF — see CombatConfig.Hero.stamina)
	local staminaCfg = Hero.stamina
	if staminaCfg.enabled then
		local dt = now - state.lastRefreshAt
		if dt > 0 and now - state.lastStaminaSpend >= staminaCfg.regenDelay then
			state.stamina = math.min(staminaCfg.max, state.stamina + staminaCfg.regenPerSecond * dt)
		end
	end
	state.lastRefreshAt = now
end

--- Stamina gate. When stamina is disabled this always passes and never charges,
--- so every call site can be written once and the feature is one config flip.
local function trySpendStamina(state: HeroState, cost: number, now: number): boolean
	local staminaCfg = Hero.stamina
	if not staminaCfg.enabled or cost <= 0 then
		return true
	end
	if state.stamina < cost then
		return false
	end
	state.stamina -= cost
	state.lastStaminaSpend = now
	return true
end

--- The gate every offensive action shares: registered, alive, not committed to
--- something else, and off cooldown.
local function canAct(state: HeroState, now: number): boolean
	if now < state.nextActionAt then
		return false
	end
	-- Blocking is a legal launch posture: attacking simply drops the shield.
	return state.state == "Idle" or state.state == "Blocking"
end

local function getFighter(state: HeroState): CombatUnit?
	if not state.character.Parent then
		return nil
	end
	local unit = CombatService.getPlayerFighter(state.character)
	if not unit or unit.health <= 0 then
		return nil
	end
	return unit
end

-- ---------------------------------------------------------------------------
-- MELEE (light combo + heavy)
-- ---------------------------------------------------------------------------

type MeleeShape = {
	damageMult: number,
	range: number,
	arcCos: number,
	windup: number,
	activeWindow: number,
	recovery: number,
	staminaCost: number,
}

--- Run the actual arc sweep. Called from the scheduled windup completion, i.e.
--- one frame's worth of latency after the player's click, by design: the windup
--- is the telegraph.
local function sweep(state: HeroState, aim: Vector3, shape: MeleeShape, step: number, kind: string)
	local result = CombatService.playerComboAttack(
		state.character,
		aim,
		shape.range,
		shape.arcCos,
		shape.damageMult,
		step,
		kind
	)

	if result.hits > 0 then
		local position = result.firstHitPosition
		if position then
			-- One event for the whole sweep, not one per victim: a heavy that
			-- catches eight peasants must not cost eight replication slots.
			CombatReplication.heroImpact(position, "confirm", result.damage, state.character)
		end
		HeroDebug:info("Hero swing connected", {
			userId = state.userId,
			kind = kind,
			step = step,
			hits = result.hits,
			damage = result.damage,
		})
	end
end

--- Shared launch path for light and heavy. Returns true if the swing started.
local function beginMelee(state: HeroState, aim: Vector3, shape: MeleeShape, step: number, kind: string, now: number): boolean
	if not trySpendStamina(state, shape.staminaCost, now) then
		reject(state, kind, "not enough stamina")
		return false
	end

	-- Attacking drops the shield. Intent is preserved (`state.blocking` stays
	-- true) so the posture comes back on its own in refresh() once recovery ends
	-- — the player should not have to re-press RMB after every swing.
	local token = enterState(state, "Windup", shape.windup)
	state.nextActionAt = now + shape.windup + shape.activeWindow + shape.recovery

	schedule(state, token, shape.windup, function()
		local activeToken = enterState(state, "Active", shape.activeWindow)
		-- Re-validate at the moment the hitbox opens, not at the moment of input:
		-- the hero may have died, left hero mode, or been unregistered during the
		-- windup. sweep() would be a no-op anyway (CombatService checks
		-- playerControlled) but skipping it also skips the replication event.
		if getFighter(state) then
			sweep(state, aim, shape, step, kind)
		end
		schedule(state, activeToken, shape.activeWindow, function()
			enterState(state, "Recovery", shape.recovery)
		end)
	end)

	return true
end

-- ---------------------------------------------------------------------------
-- PUBLIC API — LIFECYCLE
-- ---------------------------------------------------------------------------

--- Drop every trace of a player. The ONE place per-player state is freed, so
--- there is exactly one thing to audit for leaks.
local function dropPlayer(userId: number)
	local state = heroes[userId]
	if not state then
		return
	end
	heroes[userId] = nil
	byCharacter[state.character] = nil
	-- Break the CombatUnit -> HeroState back-reference so the damage funnel stops
	-- routing through the (now orphaned) state table.
	if state.character.Parent then
		CombatService.setHeroState(state.character, nil)
	end
	-- Bump the token one last time: any callback still in flight is now stale on
	-- both checks (token AND the heroes[] identity test).
	state.stateToken += 1
	state.state = "Idle"
	state.blocking = false
end

--- Register the player's character with the hero state machine. Call this
--- alongside CombatService.registerPlayerFighter — the fighter registration owns
--- health/damage/faction, this owns actions.
function HeroCombat.register(player: Player, character: Model, opts: HeroOptions?): boolean
	if not character.Parent then
		return false
	end
	-- Re-registering (respawn, or a fast RTS->Hero->RTS->Hero toggle) must not
	-- leave the previous character's state table indexed.
	dropPlayer(player.UserId)

	local now = os.clock()
	local state: HeroState = {
		userId = player.UserId,
		character = character,

		state = "Idle",
		stateToken = 0,
		stateExpiresAt = now,

		comboIndex = 0,
		comboExpiresAt = 0,
		nextActionAt = now,

		blocking = false,
		blockStartedAt = -math.huge, -- parry window starts CLOSED
		blockAim = Vector3.new(0, 0, -1),

		dodgeUntil = 0,
		invulnUntil = 0,
		dodgeReadyAt = now,

		riposteUntil = 0,
		rangedReadyAt = now,

		stamina = Hero.stamina.max,
		lastStaminaSpend = 0,
		lastRefreshAt = now,

		maxHealth = (opts and opts.maxHealth) or Hero.fighter.maxHealth,
	}

	heroes[player.UserId] = state
	byCharacter[character] = state
	CombatService.setHeroState(character, state)

	HeroDebug:info("Hero registered", { player = player.Name, maxHealth = state.maxHealth })
	return true
end

function HeroCombat.unregister(player: Player)
	dropPlayer(player.UserId)
end

--- Called when the hero's character dies. Separate from unregister so callers
--- can be explicit; behaviour is identical (a dead hero has no combat state).
function HeroCombat.characterDied(player: Player)
	dropPlayer(player.UserId)
end

function HeroCombat.playerRemoving(player: Player)
	dropPlayer(player.UserId)
end

function HeroCombat.isRegistered(player: Player): boolean
	return heroes[player.UserId] ~= nil
end

--- Read-only snapshot for HUD/debug. Returns the live table — callers must not
--- mutate it (Luau cannot express that here without a copy per call, and this is
--- on the hot path of nothing, so the convention is enforced by review).
function HeroCombat.getState(player: Player): HeroState?
	local state = heroes[player.UserId]
	if state then
		refresh(state, os.clock())
	end
	return state
end

-- ---------------------------------------------------------------------------
-- PUBLIC API — ACTIONS
-- ---------------------------------------------------------------------------

--- Light attack. Chains to the next combo step if the previous one's
--- comboWindow has not lapsed, otherwise restarts at step 1.
function HeroCombat.requestLight(player: Player, aim: any): boolean
	local state = heroes[player.UserId]
	if not state then
		reject(nil, "HeroLight", "player has no hero state")
		return false
	end
	local direction = sanitizeDirection(aim)
	if not direction then
		reject(state, "HeroLight", "bad aim vector")
		return false
	end

	local now = os.clock()
	refresh(state, now)
	if not getFighter(state) then
		reject(state, "HeroLight", "not a live registered fighter")
		return false
	end
	if not canAct(state, now) then
		reject(state, "HeroLight", "committed or on cooldown")
		return false
	end

	local steps = Hero.lightCombo
	local nextIndex = state.comboIndex + 1
	if nextIndex > #steps then
		nextIndex = 1 -- chain complete: wrap to the opener
	end
	local step = steps[nextIndex]

	-- Riposte: a parry within the last parryRiposteWindow seconds makes THIS
	-- swing hit far harder. Consumed whether or not it connects — the opening was
	-- spent the moment the player chose to swing into it.
	local damageMult = step.damageMult
	if now < state.riposteUntil then
		damageMult *= Hero.block.parryRiposteMult
		state.riposteUntil = 0
	end

	local shape: MeleeShape = {
		damageMult = damageMult,
		range = step.range,
		arcCos = step.arcCos,
		windup = step.windup,
		activeWindow = step.activeWindow,
		recovery = step.recovery,
		staminaCost = step.staminaCost,
	}

	if not beginMelee(state, direction :: Vector3, shape, nextIndex, "light", now) then
		return false
	end

	state.comboIndex = nextIndex
	-- comboWindow is measured from the END of recovery, so the player gets the
	-- full grace period after regaining control rather than having it eaten by
	-- his own animation.
	state.comboExpiresAt = state.nextActionAt + step.comboWindow
	return true
end

--- Heavy attack: long windup, wide arc, big damage. Cannot be chained out of a
--- late combo step (see maxComboIndexToChainFrom).
function HeroCombat.requestHeavy(player: Player, aim: any): boolean
	local state = heroes[player.UserId]
	if not state then
		reject(nil, "HeroHeavy", "player has no hero state")
		return false
	end
	local direction = sanitizeDirection(aim)
	if not direction then
		reject(state, "HeroHeavy", "bad aim vector")
		return false
	end

	local now = os.clock()
	refresh(state, now)
	if not getFighter(state) then
		reject(state, "HeroHeavy", "not a live registered fighter")
		return false
	end
	if not canAct(state, now) then
		reject(state, "HeroHeavy", "committed or on cooldown")
		return false
	end

	local heavy = Hero.heavy
	if state.comboIndex > heavy.maxComboIndexToChainFrom then
		reject(state, "HeroHeavy", `cannot chain a heavy out of combo step {state.comboIndex}`)
		return false
	end

	local shape: MeleeShape = {
		damageMult = heavy.damageMult,
		range = heavy.range,
		arcCos = heavy.arcCos,
		windup = heavy.windup,
		activeWindow = heavy.activeWindow,
		recovery = heavy.recovery,
		staminaCost = heavy.staminaCost,
	}

	-- step 0 tells the client "this is a heavy, play the overhead", and closes the
	-- light chain so heavy?light starts a fresh combo.
	if not beginMelee(state, direction :: Vector3, shape, 0, "heavy", now) then
		return false
	end
	state.comboIndex = 0
	state.comboExpiresAt = 0
	return true
end

--- Bow shot. Has its own cooldown on top of the shared action lockout so the
--- player cannot alternate melee/bow to fire faster than rangedCooldown.
function HeroCombat.requestRanged(player: Player, aim: any): boolean
	local state = heroes[player.UserId]
	if not state then
		reject(nil, "HeroRanged", "player has no hero state")
		return false
	end
	local direction = sanitizeDirection(aim)
	if not direction then
		reject(state, "HeroRanged", "bad aim vector")
		return false
	end

	local now = os.clock()
	refresh(state, now)
	if not getFighter(state) then
		reject(state, "HeroRanged", "not a live registered fighter")
		return false
	end
	if not canAct(state, now) then
		reject(state, "HeroRanged", "committed or on cooldown")
		return false
	end
	if now < state.rangedReadyAt then
		reject(state, "HeroRanged", "bow on cooldown")
		return false
	end

	local ranged = Hero.ranged
	if not trySpendStamina(state, ranged.staminaCost, now) then
		reject(state, "HeroRanged", "not enough stamina")
		return false
	end

	state.rangedReadyAt = now + ranged.cooldown
	state.nextActionAt = now + ranged.windup + ranged.recovery
	-- Drawing a bow is not a sword combo; the chain ends here.
	state.comboIndex = 0
	state.comboExpiresAt = 0

	local token = enterState(state, "Windup", ranged.windup)
	schedule(state, token, ranged.windup, function()
		-- A bow release is instantaneous — there is no active hitbox window to
		-- hold open the way a sword arc has — so Windup goes straight to Recovery
		-- and the arrow's travel time is ProjectileSystem's problem.
		if getFighter(state) then
			CombatService.playerBowShot(
				state.character,
				direction :: Vector3,
				ranged.range,
				ranged.arcCos,
				ranged.damageMult,
				ranged.projectile
			)
		end
		enterState(state, "Recovery", ranged.recovery)
	end)

	return true
end

--- Raise or lower the shield. `aim` sets the facing the shield covers when
--- directional blocking is on.
function HeroCombat.setBlocking(player: Player, blocking: any, aim: any): boolean
	local state = heroes[player.UserId]
	if not state then
		reject(nil, "HeroBlock", "player has no hero state")
		return false
	end
	if typeof(blocking) ~= "boolean" then
		reject(state, "HeroBlock", "blocking flag is not a boolean")
		return false
	end

	local now = os.clock()
	refresh(state, now)

	if blocking then
		if not getFighter(state) then
			reject(state, "HeroBlock", "not a live registered fighter")
			return false
		end
		-- Direction is optional for a block (an omnidirectional block is a valid
		-- config), but if directional blocking is on we need a real facing.
		local direction = sanitizeDirection(aim)
		if Hero.block.directional and not direction then
			reject(state, "HeroBlock", "directional block needs a valid aim vector")
			return false
		end
		if direction then
			state.blockAim = direction :: Vector3
		end

		if state.blocking then
			-- Already blocking: only the facing updates. Re-arming the parry window
			-- here would let a client spam block-on and be permanently parrying.
			return true
		end
		state.blocking = true
		state.blockStartedAt = now
		-- Only take the Blocking POSTURE if not mid-swing; refresh() will pick it
		-- up when the swing finishes.
		if state.state == "Idle" then
			enterState(state, "Blocking", BLOCK_FOREVER)
		end
		return true
	end

	state.blocking = false
	state.blockStartedAt = -math.huge
	if state.state == "Blocking" then
		enterState(state, "Idle", 0)
	end
	return true
end

--- Dodge roll. The server opens the i-frame window and starts the cooldown; the
--- CLIENT moves the character (see the ownership note at the top of this file).
--- Returns true if the dodge was accepted, which is the client's cue to roll.
function HeroCombat.requestDodge(player: Player, direction: any): boolean
	local state = heroes[player.UserId]
	if not state then
		reject(nil, "HeroDodge", "player has no hero state")
		return false
	end
	-- A zero/absent direction is legal here and means "roll backwards"; the client
	-- resolves that against the character's facing. Anything malformed is not.
	local rollDirection = sanitizeDirection(direction)
	if direction ~= nil and typeof(direction) == "Vector3" and not rollDirection then
		reject(state, "HeroDodge", "bad dodge direction")
		return false
	end

	local now = os.clock()
	refresh(state, now)
	if not getFighter(state) then
		reject(state, "HeroDodge", "not a live registered fighter")
		return false
	end
	if now < state.dodgeReadyAt then
		reject(state, "HeroDodge", "on cooldown")
		return false
	end
	-- Legal only from Idle / Blocking. Explicitly NOT from Windup or Active: see
	-- the transition table at the top.
	if state.state ~= "Idle" and state.state ~= "Blocking" then
		reject(state, "HeroDodge", `illegal from state {state.state}`)
		return false
	end

	local dodge = Hero.dodge
	if not trySpendStamina(state, dodge.staminaCost, now) then
		reject(state, "HeroDodge", "not enough stamina")
		return false
	end

	local travelTime = dodge.distance / math.max(dodge.speed, 1)
	state.dodgeUntil = now + travelTime
	state.invulnUntil = now + dodge.invulnSeconds
	state.dodgeReadyAt = now + dodge.cooldown
	state.nextActionAt = now + travelTime + dodge.recovery
	-- Rolling drops the shield entirely (both intent and posture) — you cannot
	-- come out of a roll already guarding.
	state.blocking = false
	state.blockStartedAt = -math.huge
	-- Rolling breaks the combo chain.
	state.comboIndex = 0
	state.comboExpiresAt = 0

	local token = enterState(state, "Dodging", travelTime)
	schedule(state, token, travelTime, function()
		enterState(state, "Recovery", dodge.recovery)
	end)

	local primary = state.character.PrimaryPart
	if primary then
		CombatReplication.heroImpact(primary.Position, "dodge", nil, state.character)
	end
	return true
end

-- ---------------------------------------------------------------------------
-- INCOMING DAMAGE (i-frames / block / parry / stagger)
-- ---------------------------------------------------------------------------

--- Installed on CombatService as the incoming-damage hook, so it runs inside
--- applyDamageToUnit — the single funnel every unit-vs-unit damage source in the
--- engine passes through. Returns the damage that should actually land; 0 means
--- fully negated.
---
--- Only called for defenders with `playerControlled == true`, so this adds no
--- work to the AI-vs-AI hot path.
function HeroCombat.onIncomingDamage(attacker: CombatUnit, defender: CombatUnit, damage: number): number
	local state = defender.heroState
	if not state then
		return damage -- an arena/legacy fighter registered without a hero state
	end

	local now = os.clock()
	refresh(state, now)

	-- -- 1. DODGE I-FRAMES ------------------------------------------------
	-- Checked against invulnUntil, NOT dodgeUntil: the i-frame window is
	-- deliberately shorter than the roll so the tail of a badly-timed roll can
	-- still be punished.
	if now < state.invulnUntil then
		local position = defender.model.PrimaryPart and (defender.model.PrimaryPart :: BasePart).Position
		if position then
			CombatReplication.heroImpact(position, "dodge", nil, defender.model)
		end
		return 0
	end

	-- -- 2. BLOCK / PARRY -------------------------------------------------
	if isGuarding(state) then
		local block = Hero.block
		local covered = true
		if block.directional then
			-- The shield covers where the player is FACING. Use the reported block
			-- aim (validated on receipt) rather than the character's LookVector,
			-- because in third person the body turns to follow the camera with a
			-- lag the player does not control.
			local defenderPos = defender.model.PrimaryPart and (defender.model.PrimaryPart :: BasePart).Position
			local attackerPos = attacker.model.PrimaryPart and (attacker.model.PrimaryPart :: BasePart).Position
			if defenderPos and attackerPos then
				local toAttacker = Vector3.new(attackerPos.X - defenderPos.X, 0, attackerPos.Z - defenderPos.Z)
				if toAttacker.Magnitude > 1e-3 then
					covered = toAttacker.Unit:Dot(state.blockAim) >= block.facingDot
				end
				-- Magnitude <= 1e-3 means the attacker is inside the hero's own
				-- space: no direction exists, so `covered` stays true. Failing open
				-- here favours the defender, which is the right way to be wrong
				-- about degenerate geometry.
			end
		end

		if covered then
			local position = defender.model.PrimaryPart and (defender.model.PrimaryPart :: BasePart).Position

			-- PARRY: the hit landed inside parryWindow of the shield going up.
			if now - state.blockStartedAt <= block.parryWindow then
				-- Consume the window immediately. One right-click buys one parry;
				-- otherwise every hit inside the window would parry, and a crowd of
				-- eight attackers would all be stunned by a single well-timed press.
				state.blockStartedAt = -math.huge
				trySpendStamina(state, block.staminaCostPerParry, now)
				state.riposteUntil = now + block.parryRiposteWindow
				-- Stun the attacker using the engine's existing mechanism
				-- (`stunnedUntil`, the same field Abilities.ShieldBash drives).
				CombatService.stunUnit(attacker.model, block.parryStunSeconds)
				if position then
					CombatReplication.heroImpact(position, "parry", nil, defender.model)
				end
				HeroDebug:info("Parry", { userId = state.userId, attacker = attacker.unitType })
				return 0
			end

			-- Ordinary block: reduce, don't negate.
			if position then
				CombatReplication.heroImpact(position, "block", damage, defender.model)
			end
			return math.max(1, math.floor(damage * (1 - block.damageReduction)))
		end
	end

	-- -- 3. STAGGER -------------------------------------------------------
	-- A big hit while winding up interrupts the swing. Only from Windup: once the
	-- hitbox is live (Active) the swing has earned the right to land, and
	-- interrupting Recovery would just extend an existing lockout.
	if state.state == "Windup" then
		local stagger = Hero.stagger
		if damage >= state.maxHealth * stagger.interruptDamageFraction then
			enterState(state, "Staggered", stagger.seconds)
			state.nextActionAt = now + stagger.seconds
			state.comboIndex = 0
			state.comboExpiresAt = 0
			HeroDebug:info("Hero staggered", { userId = state.userId, damage = damage })
		end
	end

	return damage
end

--- True while the given character has active dodge i-frames. Exposed for other
--- systems (e.g. an ability that wants to skip an invulnerable target) — the
--- damage pipeline itself goes through onIncomingDamage, not this.
function HeroCombat.isInvulnerable(character: Model): boolean
	local state = byCharacter[character]
	if not state then
		return false
	end
	return os.clock() < state.invulnUntil
end

-- ---------------------------------------------------------------------------
-- INIT
-- ---------------------------------------------------------------------------

function HeroCombat.init()
	if initialized then
		return
	end
	initialized = true

	-- Installing the hook here (rather than CombatService requiring us) is what
	-- keeps the dependency acyclic: HeroCombat -> CombatService, never back.
	CombatService.setIncomingDamageHook(HeroCombat.onIncomingDamage)

	Players.PlayerRemoving:Connect(HeroCombat.playerRemoving)

	HeroDebug:info("HeroCombat initialized", {
		comboSteps = #Hero.lightCombo,
		staminaEnabled = Hero.stamina.enabled,
		friendlyFire = Hero.playerAttacksHitAllies,
	})
end

return HeroCombat
