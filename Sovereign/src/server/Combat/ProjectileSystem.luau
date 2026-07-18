--!strict
-- ProjectileSystem: Server-side projectile simulation for ranged combat.
-- Hit/miss is decided at fire time (accuracy vs moving targets); damage lands
-- after real flight time. Visuals are replicated as one batched event and
-- rendered client-side — no server Instances per shot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local CombatReplication = require(script.Parent.CombatReplication)

local ProjectileSystem = {}

export type InFlight = {
	arriveAt: number,
	targetModel: Model,
	onImpact: (Model) -> (), -- called only on hit, only if target still alive/parented
}

local inFlight: { InFlight } = {}

-- Fire a projectile. Returns predicted flight time (0 if instant fallback).
function ProjectileSystem.fire(
	projectileKey: string,
	fromPos: Vector3,
	targetModel: Model,
	targetIsMoving: boolean,
	onImpact: (Model) -> ()
): number
	local def = CombatConfig.Projectiles[projectileKey]
	local targetPart = targetModel.PrimaryPart
	if not def or not targetPart then
		-- Unknown projectile / no target part: resolve instantly
		onImpact(targetModel)
		return 0
	end

	local targetPos = targetPart.Position
	local distance = (targetPos - fromPos).Magnitude
	local flightTime = distance / def.speed

	-- Accuracy roll at release
	local accuracy = def.baseAccuracy
	if targetIsMoving then
		accuracy -= def.movingPenalty
	end
	local isHit = math.random() <= accuracy

	-- Miss shots land offset behind/beside the target
	local visualTarget = targetPos
	if not isHit then
		local missOffset = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
		if missOffset.Magnitude < 3 then
			missOffset = Vector3.new(4, 0, 3)
		end
		visualTarget = targetPos + missOffset
	end

	CombatReplication.projectile(fromPos, visualTarget, def.visual, flightTime)

	if isHit then
		table.insert(inFlight, {
			arriveAt = os.clock() + flightTime,
			targetModel = targetModel,
			onImpact = onImpact,
		})
	end

	return flightTime
end

-- Advance simulation; called every combat tick.
function ProjectileSystem.update(now: number)
	if #inFlight == 0 then
		return
	end
	-- Iterate backwards so removals are safe
	for i = #inFlight, 1, -1 do
		local shot = inFlight[i]
		if now >= shot.arriveAt then
			table.remove(inFlight, i)
			local target = shot.targetModel
			if target and target.Parent then
				shot.onImpact(target)
			end
		end
	end
end

function ProjectileSystem.getInFlightCount(): number
	return #inFlight
end

function ProjectileSystem.clear()
	table.clear(inFlight)
end

return ProjectileSystem
