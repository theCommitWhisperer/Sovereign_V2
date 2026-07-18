--!strict
-- AbilitySystem: Passive + triggered flavor abilities for combat v2.
-- Keeps the Irish core (Celtic Fury, War Cry, Shield Wall) and adds the
-- expanded roster abilities declared in CombatConfig.Abilities / UnitProfiles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local CombatTypes = require(script.Parent.CombatTypes)
local CombatReplication = require(script.Parent.CombatReplication)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local MoraleManager = require(script.Parent.Parent.Managers.MoraleManager)

local AbilityDebug = DebugManager.createChannel("CombatAbilities", false)

type CombatUnit = CombatTypes.CombatUnit

local Abilities = CombatConfig.Abilities

local AbilitySystem = {}

export type AbilityContext = {
	units: { [Model]: CombatUnit },
	moraleEnabled: boolean,
	-- visitor over allied combat units within radius of `unit` (excluding itself)
	forEachAllyInRadius: (unit: CombatUnit, radius: number, visitor: (CombatUnit) -> ()) -> (),
	forEachEnemyInRadius: (unit: CombatUnit, radius: number, visitor: (CombatUnit) -> ()) -> (),
}

local function hasAbility(unit: CombatUnit, name: string): boolean
	local abilities = unit.profile.abilities
	return abilities ~= nil and table.find(abilities :: { string }, name) ~= nil
end

local function isIrish(unit: CombatUnit): boolean
	return unit.faction == "Irish" or unit.faction == "Kingdom"
end

local function offCooldown(unit: CombatUnit, name: string, now: number, cooldown: number): boolean
	local last = unit.lastAbilityTimes[name]
	return last == nil or (now - last) >= cooldown
end

local function getPosition(unit: CombatUnit): Vector3?
	local part = unit.model.PrimaryPart
	return part and part.Position or nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- IRISH CORE
-- ═══════════════════════════════════════════════════════════════════════════

local function updateCelticFury(unit: CombatUnit, ctx: AbilityContext)
	if not ctx.moraleEnabled or not isIrish(unit) then
		return
	end
	local cfg = Abilities.CelticFury
	local shouldBeActive = unit.morale >= cfg.moraleThreshold

	if shouldBeActive and not unit.celticFuryActive then
		unit.celticFuryActive = true
		local humanoid = unit.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed *= cfg.speedMult
		end
		local pos = getPosition(unit)
		if pos then
			CombatReplication.ability("CelticFury", pos, nil)
		end
	elseif not shouldBeActive and unit.celticFuryActive then
		unit.celticFuryActive = false
		local humanoid = unit.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed /= cfg.speedMult
		end
	end
end

local function tryWarCry(unit: CombatUnit, now: number, ctx: AbilityContext)
	if not (isIrish(unit) or hasAbility(unit, "WarCry")) then
		return
	end
	local cfg = Abilities.WarCry
	if not offCooldown(unit, "WarCry", now, cfg.cooldown) then
		return
	end
	if unit.morale < cfg.minMorale or not unit.targetModel then
		return
	end
	local pos = getPosition(unit)
	if not pos then
		return
	end

	unit.lastAbilityTimes.WarCry = now
	CombatReplication.ability("WarCry", pos, cfg.radius)

	local boosted = 0
	ctx.forEachAllyInRadius(unit, cfg.radius, function(ally)
		MoraleManager.modifyMorale(ally.model, cfg.moraleBoost, "War Cry")
		boosted += 1
	end)
	AbilityDebug:info("War Cry!", { unit = unit.unitType, alliesBoosted = boosted })
end

local function updateShieldWall(unit: CombatUnit, ctx: AbilityContext)
	if unit.stance ~= "Defensive" then
		unit.inShieldWall = false
		if #unit.shieldWallAllies > 0 then
			table.clear(unit.shieldWallAllies)
		end
		return
	end
	local cfg = Abilities.ShieldWall
	table.clear(unit.shieldWallAllies)
	ctx.forEachAllyInRadius(unit, cfg.radius, function(ally)
		if ally.stance == "Defensive" then
			table.insert(unit.shieldWallAllies, ally.model)
		end
	end)
	unit.inShieldWall = #unit.shieldWallAllies >= cfg.minAllies
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPANDED ROSTER
-- ═══════════════════════════════════════════════════════════════════════════

local function tryHeal(unit: CombatUnit, now: number, ctx: AbilityContext)
	if not hasAbility(unit, "Heal") then
		return
	end
	local cfg = Abilities.Heal
	if not offCooldown(unit, "Heal", now, cfg.cooldown) then
		return
	end

	-- Heal the most wounded ally in radius
	local bestAlly: CombatUnit? = nil
	local worstRatio = 0.999
	ctx.forEachAllyInRadius(unit, cfg.radius, function(ally)
		local ratio = ally.health / ally.maxHealth
		if ratio < worstRatio then
			worstRatio = ratio
			bestAlly = ally
		end
	end)

	local target = bestAlly
	if not target then
		return
	end

	unit.lastAbilityTimes.Heal = now
	target.health = math.min(target.maxHealth, target.health + cfg.amount)
	target.model:SetAttribute("CurrentHealth", target.health)
	local humanoid = target.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = target.health
	end
	local pos = getPosition(target)
	if pos then
		CombatReplication.ability("Heal", pos, nil)
	end
end

local function updateBattleSong(unit: CombatUnit, now: number, ctx: AbilityContext)
	if not hasAbility(unit, "BattleSong") then
		return
	end
	local cfg = Abilities.BattleSong
	if not offCooldown(unit, "BattleSong", now, cfg.tickEvery) then
		return
	end
	unit.lastAbilityTimes.BattleSong = now

	local pos = getPosition(unit)
	if pos then
		CombatReplication.ability("BattleSong", pos, cfg.radius)
	end
	-- Aura is timestamp-based so it survives update-order races and expires
	-- naturally when the bard dies or allies leave the radius.
	ctx.forEachAllyInRadius(unit, cfg.radius, function(ally)
		ally.battleSongMult = cfg.damageMult
		ally.battleSongUntil = now + cfg.tickEvery + 1
		if ctx.moraleEnabled then
			MoraleManager.modifyMorale(ally.model, cfg.moralePerTick, "Battle Song")
		end
	end)
end

local function tryWail(unit: CombatUnit, now: number, ctx: AbilityContext)
	if not hasAbility(unit, "Wail") then
		return
	end
	local cfg = Abilities.Wail
	if not offCooldown(unit, "Wail", now, cfg.cooldown) then
		return
	end
	if not unit.targetModel then
		return
	end
	local pos = getPosition(unit)
	if not pos then
		return
	end

	unit.lastAbilityTimes.Wail = now
	CombatReplication.ability("Wail", pos, cfg.radius)
	ctx.forEachEnemyInRadius(unit, cfg.radius, function(enemy)
		if ctx.moraleEnabled then
			MoraleManager.modifyMorale(enemy.model, cfg.moraleDamage, "Banshee Wail")
		end
	end)
end

local function updateBerserk(unit: CombatUnit)
	if not hasAbility(unit, "Berserk") then
		return
	end
	local cfg = Abilities.Berserk
	local shouldBeActive = unit.health / unit.maxHealth <= cfg.healthPct
	if shouldBeActive and not unit.berserkActive then
		unit.berserkActive = true
		local pos = getPosition(unit)
		if pos then
			CombatReplication.ability("Berserk", pos, nil)
		end
	elseif not shouldBeActive then
		unit.berserkActive = false
	end
end

local function updateHitAndRun(unit: CombatUnit)
	if not hasAbility(unit, "HitAndRun") then
		return
	end
	local cfg = Abilities.HitAndRun
	local wounded = unit.health / unit.maxHealth <= cfg.retreatHealthPct
	local humanoid = unit.model:FindFirstChildOfClass("Humanoid")
	local flagged = unit.model:GetAttribute("HitAndRunActive") == true

	if wounded and not flagged then
		unit.model:SetAttribute("HitAndRunActive", true)
		if humanoid then
			humanoid.WalkSpeed *= cfg.speedMult
		end
		-- Disengage: drop target so movement can carry the unit away
		unit.targetModel = nil
	elseif not wounded and flagged then
		unit.model:SetAttribute("HitAndRunActive", false)
		if humanoid then
			humanoid.WalkSpeed /= cfg.speedMult
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

-- Per-tick passive/aura updates. `battleSongMult` decays here and is re-applied
-- by any bard still in range.
function AbilitySystem.update(unit: CombatUnit, now: number, ctx: AbilityContext)
	-- Expire stale bard buffs
	if unit.battleSongMult > 1 and now > unit.battleSongUntil then
		unit.battleSongMult = 1
	end

	updateCelticFury(unit, ctx)
	tryWarCry(unit, now, ctx)
	updateShieldWall(unit, ctx)
	tryHeal(unit, now, ctx)
	updateBattleSong(unit, now, ctx)
	tryWail(unit, now, ctx)
	updateBerserk(unit)
	updateHitAndRun(unit)
end

-- Called when `attacker` lands a melee/ranged hit. Returns bonus effects.
export type OnHitResult = {
	stunTarget: number?, -- seconds of stun applied to defender
	extraShots: number?, -- Volley: extra projectiles to fire
}

function AbilitySystem.onHit(attacker: CombatUnit, defender: CombatUnit, now: number): OnHitResult
	local result: OnHitResult = {}

	-- Shield Bash: periodic stun
	if hasAbility(attacker, "ShieldBash") then
		local cfg = Abilities.ShieldBash
		if offCooldown(attacker, "ShieldBash", now, cfg.cooldown) then
			attacker.lastAbilityTimes.ShieldBash = now
			result.stunTarget = cfg.stunSeconds
			local pos = getPosition(defender)
			if pos then
				CombatReplication.ability("ShieldBash", pos, nil)
			end
		end
	end

	-- Volley: periodic multi-shot for ranged units
	if hasAbility(attacker, "Volley") and attacker.attackType == "Ranged" then
		local cfg = Abilities.Volley
		if offCooldown(attacker, "Volley", now, cfg.cooldown) then
			attacker.lastAbilityTimes.Volley = now
			result.extraShots = cfg.extraShots
		end
	end

	-- Ambush bookkeeping: first strike is spent on this target
	if hasAbility(attacker, "Ambush") then
		attacker.ambushSpentOn = defender.model
	end

	return result
end

return AbilitySystem
