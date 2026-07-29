--!strict
-- RevoltSystem: drives RevoltManager's per-player risk evaluation.
--
-- This module existed but was never started -- nothing called init() or
-- startLoop(), so RevoltManager.update(player) was never invoked and revolts
-- could not happen at all. RevoltManager.init() ran, which made it look wired.
--
-- That matters more after the economy rework than it did before: the whole
-- point of the popularity budget is that taxing hard has a consequence, and
-- revolt is that consequence. Without this loop, "Extortionate tax forever"
-- had no downside beyond reduced collection.
--
-- Rewritten from `RevoltSystem:init()` (colon-call, unbounded while-true with
-- no way to stop it) to the startLoop/stopLoop shape every other System in this
-- folder uses, so GameManager can start it alongside the rest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RevoltManager = require(script.Parent.Parent.Managers.RevoltManager)
local GameSettings = require(ReplicatedStorage.Shared.GameSettings)

local RevoltSystem = {}

local TICK_SECONDS = 10
local running = false

function RevoltSystem.init()
	-- RevoltManager owns its own state; nothing to set up here.
end

function RevoltSystem.startLoop()
	if running then
		return
	end
	running = true

	task.spawn(function()
		while running do
			task.wait(GameSettings.waitInterval(TICK_SECONDS))
			if not running then
				break
			end
			for _, player in Players:GetPlayers() do
				-- One player's revolt math failing must not stop everyone
				-- else's from being evaluated.
				local ok, err = pcall(RevoltManager.update, player)
				if not ok then
					warn(`[RevoltSystem] update failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

function RevoltSystem.stopLoop()
	running = false
end

return RevoltSystem
