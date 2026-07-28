--!strict
-- DamageResolver: Pure damage math for combat v2.
-- No side effects, no Instance mutation — everything is computed from inputs,
-- which keeps balance testable and the counter matrix in one place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local CombatTypes = require(script.Parent.CombatTypes)

type CombatUnit = CombatTypes.CombatUnit

local DamageResolver = {}

export type DamageContext = {
	attackerAllyCount: number, -- allies near attacker (formation cohesion / pack)
	defenderAllyCount: number, -- allies near defender
	isIrish: boolean, -- attacker belongs to an Irish faction
	moraleEnabled: boolean,
	-- Per-ATTACK damage type, overriding attacker.profile.damageType for this one
	-- resolution. Exists because the hero fighter is seeded from a melee profile
	-- (Gallowglass / Slash) yet can draw a bow: without this his arrows were
	-- scored as sword cuts against the counter matrix. It lives here instead of
	-- being written onto attacker.profile because that profile is a SHARED table
	-- owned by CombatConfig — mutating it would flip the damage type of every
	-- Gallowglass on the map for as long as the arrow was in flight.
	damageTypeOverride: CombatConfig.DamageType?,
}

export type DamageBreakdown = {
	final: number,
	counterMult: number,
	stanceMult: number,
	positionalMult: number,
	abilityMult: number,
	moraleMult: number,
	mitigationMult: number,
	braced: boolean, -- defender braced against a charge
}

local Positional = CombatConfig.Positional
local Morale = CombatConfig.Morale
local Abilities = CombatConfig.Abilities

local function getBonusVsTags(attacker: CombatUnit, defender: CombatUnit): number
	local bonuses = attacker.profile.bonusVsTags
	if not bonuses then
		return 1
	end
	local mult = 1
	local defenderTags = defender.profile.tags
	if defenderTags then
		for _, tag in defenderTags do
			local bonus = bonuses[tag]
			if bonus then
				mult *= bonus
			end
		end
	end
	return mult
end

-- A spear unit that has planted itself negates an incoming charge outright and
-- gets a counter-strike (see CombatService.resolveHit).
--
-- BUGFIX: this used to read `defender.stance == "Defensive" or == "Hold"`.
-- Neither name has existed since stances became March/Attack/Defend/Skirmish, so
-- this returned false for EVERY unit and the brace-counter branch downstream had
-- never once executed. Now driven off CombatConfig.StanceBehavior[...].braces so
-- the next stance rename breaks a table lookup instead of silently deleting a
-- mechanic. The "spear" tag gate is kept deliberately: Defend stance is
-- available to the whole army, but only spears may brace.
local function isBraced(defender: CombatUnit): boolean
	if not CombatConfig.hasTag(defender.profile, "spear") then
		return false
	end
	local behavior = CombatConfig.StanceBehavior[defender.stance]
	return behavior ~= nil and behavior.braces == true
end

-- Positional multiplier from attacker/defender world state
function DamageResolver.getPositionalMult(
	attackerPos: Vector3,
	defenderPos: Vector3,
	defenderLook: Vector3
): number
	local mult = 1
	local attackDir = attackerPos - defenderPos
	if attackDir.Magnitude > 0.001 then
		local dot = attackDir.Unit:Dot(defenderLook)
		if dot < -0.7 then
			mult *= Positional.REAR_ATTACK_BONUS
		elseif dot < -0.3 then
			mult *= Positional.FLANKING_DAMAGE_BONUS
		end
	end
	if attackerPos.Y - defenderPos.Y > Positional.HIGH_GROUND_HEIGHT then
		mult *= Positional.HIGH_GROUND_BONUS
	end
	return mult
end

function DamageResolver.calculate(
	attacker: CombatUnit,
	defender: CombatUnit,
	positionalMult: number,
	ctx: DamageContext
): DamageBreakdown
	local baseDamage = attacker.attackDamage

	-- ── Counter matrix ────────────────────────────────────────────────────
	-- ctx.damageTypeOverride lets ONE attack resolve as a different damage type
	-- (the hero's bow firing Pierce out of a Slash profile). nil for every AI
	-- attack, which therefore behaves exactly as before.
	local damageType = ctx.damageTypeOverride or attacker.profile.damageType
	local matrixRow = CombatConfig.CounterMatrix[damageType]
	local counterMult = (matrixRow and matrixRow[defender.profile.armorClass]) or 1
	counterMult *= getBonusVsTags(attacker, defender)

	-- ── Armor flat mitigation (5% per point, capped 75%) ─────────────────
	local armorReduction = math.min(defender.armor * 0.05, 0.75)
	local mitigationMult = 1 - armorReduction

	-- ── Stances ──────────────────────────────────────────────────────────
	local stanceMult = 1
	local atkStance = CombatConfig.StanceModifiers[attacker.stance]
	if atkStance then
		stanceMult *= atkStance.damage
	end
	local defStance = CombatConfig.StanceModifiers[defender.stance]
	if defStance then
		stanceMult /= defStance.defense
	end

	-- ── Abilities ────────────────────────────────────────────────────────
	local abilityMult = 1
	local braced = false

	if attacker.celticFuryActive then
		abilityMult *= Abilities.CelticFury.damageMult
	end
	if attacker.berserkActive then
		abilityMult *= Abilities.Berserk.damageMult
	end
	if defender.berserkActive then
		abilityMult /= Abilities.Berserk.defenseMult -- berserkers take more damage
	end
	if attacker.battleSongMult > 1 then
		abilityMult *= attacker.battleSongMult
	end

	-- Pack Hunter: wolfhounds hit harder per nearby packmate
	if CombatConfig.hasTag(attacker.profile, "beast") then
		local pack = Abilities.PackHunter
		abilityMult *= 1 + math.min(ctx.attackerAllyCount * pack.perAllyDamage, pack.maxBonus)
	end

	-- Ambush: first strike bonus against a fresh target
	if attacker.ambushSpentOn ~= defender.model
		and attacker.profile.abilities
		and table.find(attacker.profile.abilities :: { string }, "Ambush")
	then
		abilityMult *= Abilities.Ambush.firstStrikeMult
	end

	-- ── Charge vs Brace ──────────────────────────────────────────────────
	if attacker.isCharging then
		if isBraced(defender) then
			braced = true -- charge fully negated; CombatService lets the spear counter-strike
		else
			local chargeBonus = ctx.isIrish and Positional.IRISH_CHARGE_BONUS or Positional.CHARGE_DAMAGE_BONUS
			if CombatConfig.hasTag(attacker.profile, "cavalry")
				and attacker.profile.abilities
				and table.find(attacker.profile.abilities :: { string }, "Trample")
			then
				chargeBonus *= Abilities.Trample.chargeBonusMult
			end
			abilityMult *= chargeBonus
		end
	end

	-- ── Shield Wall / formation cohesion mitigation ──────────────────────
	if defender.inShieldWall then
		local sw = Abilities.ShieldWall
		local reduction = math.min(sw.baseReduction + #defender.shieldWallAllies * sw.perAllyReduction, sw.maxReduction)
		mitigationMult *= 1 - reduction
	elseif defender.inFormationCohesion then
		mitigationMult *= Positional.FORMATION_DEFENSE_MULT
	end

	-- ── Morale ───────────────────────────────────────────────────────────
	local moraleMult = 1
	if ctx.moraleEnabled then
		local attackerMoraleBonus = (attacker.morale / 100) * Morale.ATTACKER_SCALE + (1 - Morale.ATTACKER_SCALE / 2)
		local defenderMoralePenalty = 2 - ((defender.morale / 100) * Morale.ATTACKER_SCALE + (1 - Morale.ATTACKER_SCALE / 2))
		moraleMult = attackerMoraleBonus * defenderMoralePenalty
	end

	local final = baseDamage * counterMult * mitigationMult * stanceMult * abilityMult * positionalMult * moraleMult
	return {
		final = math.max(1, math.floor(final)),
		counterMult = counterMult,
		stanceMult = stanceMult,
		positionalMult = positionalMult,
		abilityMult = abilityMult,
		moraleMult = moraleMult,
		mitigationMult = mitigationMult,
		braced = braced,
	}
end

-- Damage vs buildings: counter matrix vs Structure, no morale/stance games.
-- Buildings carry an implicit "structure" tag, so siege engines can declare
-- anti-building bonuses via bonusVsTags (same mechanism as Pikeman vs cavalry).
function DamageResolver.calculateVsBuilding(attacker: CombatUnit): number
	local matrixRow = CombatConfig.CounterMatrix[attacker.profile.damageType]
	local counterMult = (matrixRow and matrixRow.Structure) or 0.5
	local damage = attacker.attackDamage * counterMult
	local bonuses = attacker.profile.bonusVsTags
	if bonuses and bonuses.structure then
		damage *= bonuses.structure
	end
	if attacker.berserkActive then
		damage *= Abilities.Berserk.damageMult
	end
	return math.max(1, math.floor(damage))
end

return DamageResolver
