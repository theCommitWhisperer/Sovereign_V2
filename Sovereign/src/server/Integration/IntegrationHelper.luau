--!strict
-- IntegrationHelper: Sets up a fully-wired fake player for integration tests.
-- Initialises every system the economy and victory loops depend on so that
-- calling consumeFood(), checkDefeat() etc. works exactly as it does in a
-- real game session.

local PlayerManager     = require(script.Parent.Parent.Managers.PlayerManager)
local ConsumptionManager = require(script.Parent.Parent.Managers.ConsumptionManager)
local SeasonManager     = require(script.Parent.Parent.Managers.SeasonManager)
local PopulationManager = require(script.Parent.Parent.Managers.PopulationManager)
local VictoryConditionManager = require(script.Parent.Parent.Managers.VictoryConditionManager)
local TaxManager        = require(script.Parent.Parent.Managers.TaxManager)
local WeatherManager    = require(script.Parent.Parent.Managers.WeatherManager)

local IntegrationHelper = {}

-- Creates a fully-initialised fake player (all systems wired up).
-- Call teardown() after each test to clean state.
function IntegrationHelper.setup(userId: number?)
	local id = userId or 888000
	local fake = { UserId = id, Name = "IntegrationPlayer_" .. id } :: any

	-- Tear down any leftover state from a previous run first
	IntegrationHelper.teardown(fake)

	-- Core player data
	PlayerManager.create(fake)

	-- Set GameState to InGame so victory checks run
	local pd = PlayerManager.get(fake)
	if pd then
		pd.GameState = "InGame"
		-- Start with zero resources so test assertions about exact resource values work.
		-- Tests that need resources to prevent Economic Collapse must add them explicitly.
	end

	-- All per-player systems
	ConsumptionManager.create(fake)
	SeasonManager.create(fake)
	WeatherManager.create(fake)
	PopulationManager.create(fake)
	VictoryConditionManager.create(fake)
	TaxManager.create(fake)

	-- Start with no peace time so defeat checks fire immediately
	VictoryConditionManager.setGameStarted(fake, 0)

	return fake
end

-- Adds N Peasant units parented to Workspace (needed for population/tax counts)
function IntegrationHelper.addPeasants(fake: any, count: number): { Instance }
	local pd = PlayerManager.get(fake)
	local units = {}
	for _ = 1, count do
		local m = Instance.new("Model")
		m:SetAttribute("UnitType", "Peasant")
		m.Parent = game.Workspace
		table.insert(pd.Units, m)
		table.insert(units, m)
	end
	return units
end

-- Removes all fake units and cleans up player data from all systems
function IntegrationHelper.teardown(fake: any)
	local pd = PlayerManager.get(fake)
	if pd then
		for _, u in pd.Units do
			if u and u.Parent then u:Destroy() end
		end
		for _, b in pd.Buildings do
			if b and b.Parent then b:Destroy() end
		end
	end
	PlayerManager.remove(fake)
end

return IntegrationHelper
