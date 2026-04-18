--!strict
-- GameSettings: Global runtime settings set by the lobby and read by game systems.
-- Only the server writes to these; clients receive relevant values via GameStarted event.

local GameSettings = {}

local speedMultiplier = 1.0 -- Slow=0.5, Normal=1.0, Fast=2.0

-- Called by GameManager on game start with the lobby's gameSpeed setting
function GameSettings.setGameSpeed(speed: string)
	local multipliers = { Slow = 0.5, Normal = 1.0, Fast = 2.0 }
	speedMultiplier = multipliers[speed] or 1.0
end

-- Returns the interval a system should wait(), given its base interval.
-- e.g. ConsumptionSystem calls waitInterval(30) → 60s on Slow, 30s Normal, 15s Fast
function GameSettings.waitInterval(baseSeconds: number): number
	-- Faster game speed = shorter wait between ticks
	return baseSeconds / speedMultiplier
end

function GameSettings.getSpeedMultiplier(): number
	return speedMultiplier
end

return GameSettings
