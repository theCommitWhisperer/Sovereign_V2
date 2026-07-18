--!strict
-- BuildingScaleConfig: Global building size control.
--
-- Every building model cloned from ReplicatedStorage.Assets.Buildings is
-- scaled by GlobalScale at placement time — server placement, wall piece
-- swaps, client ghost previews, and AI placement all read this value, so
-- previews always match what actually spawns.
--
-- The source assets in Studio are never modified; only clones are scaled.
-- Downstream systems (worker points, pathfinding obstacles, wall connection
-- points) measure real model geometry, so they follow automatically.
--
-- Tune this single number to give players more buildable room:
--   1.0  = native asset size
--   0.7  = 30% smaller (recommended starting point for the current maps)
--   0.5  = half size

local BuildingScaleConfig = {}

BuildingScaleConfig.GlobalScale = 0.7

-- Clearance distances (building-to-building spacing checks) scale with the
-- buildings themselves so smaller buildings can also pack closer together.
function BuildingScaleConfig.scaleDistance(distance: number): number
	return distance * BuildingScaleConfig.GlobalScale
end

-- Apply the global scale to a cloned building model (no-op at 1.0).
-- Safe for Models only; callers pass clones, never the original assets.
function BuildingScaleConfig.applyToModel(model: Model)
	if BuildingScaleConfig.GlobalScale ~= 1 then
		model:ScaleTo(model:GetScale() * BuildingScaleConfig.GlobalScale)
	end
end

return BuildingScaleConfig
