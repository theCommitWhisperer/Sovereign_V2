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

local function isBraced(defender: CombatUnit): boolean
	return CombatConfig.hasTag(defender.profile, "spear")
		and (defender.stance == "Defensive" or defender.stance == "Hold")
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
	local matrixRow = CombatConfig.CounterMatrix[attacker.profile.damageType]
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
function DamageResolver.calculateVsBuilding(attacker: CombatUnit): number
	local matrixRow = CombatConfig.CounterMatrix[attacker.profile.damageType]
	local counterMult = (matrixRow and matrixRow.Structure) or 0.5
	local damage = attacker.attackDamage * counterMult
	if attacker.berserkActive then
		damage *= Abilities.Berserk.damageMult
	end
	return math.max(1, math.floor(damage))
end

return DamageResolver
