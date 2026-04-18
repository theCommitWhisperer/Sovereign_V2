-- ProductionChainManager.spec.luau
-- Tests for canProduce, consumeInputs, getProductionStatus, and
-- isProductionChainBuilding.
--
-- Passive producers (e.g. "Potato Farm"): no input needed, always ready.
-- Production chain buildings (e.g. "Smelter"): needs stored inputs to produce.
--
-- NOTE: BuildingManager.addToStorage only works on buildings whose storage has
-- been initialised via createBuilding. Raw Instance fakes start with zero
-- storage (BuildingManager.getStorageAmount returns 0), which is intentionally
-- exploited in the "not enough inputs" tests below.

return function()
	local ProductionChainManager = require(script.Parent.ProductionChainManager)

	-- ── test fixture helpers ───────────────────────────────────────────────

	local function makeFarm(): Model
		local m = Instance.new("Model")
		m.Name = "TestFarm"
		m:SetAttribute("BuildingType", "Potato Farm")
		m.Parent = game.Workspace
		return m
	end

	local function makeSmelter(): Model
		local m = Instance.new("Model")
		m.Name = "TestSmelter"
		m:SetAttribute("BuildingType", "Smelter")
		m.Parent = game.Workspace
		return m
	end

	local function makeNoType(): Model
		local m = Instance.new("Model")
		m.Name = "NoType"
		m.Parent = game.Workspace
		return m
	end

	local function makeUnknown(): Model
		local m = Instance.new("Model")
		m.Name = "Unknown"
		m:SetAttribute("BuildingType", "NonExistentBuilding")
		m.Parent = game.Workspace
		return m
	end

	-- ─────────────────────────────────────────────────────────────
	-- canProduce
	-- ─────────────────────────────────────────────────────────────
	describe("canProduce", function()
		describe("passive producers", function()
			it("Potato Farm returns true — no inputs required", function()
				local farm = makeFarm()
				expect(ProductionChainManager.canProduce(farm)).to.equal(true)
				farm:Destroy()
			end)
		end)

		describe("production chain buildings", function()
			it("Smelter returns false when storage is empty (0 Iron_Ore < 2 needed)", function()
				local smelter = makeSmelter()
				-- Raw fake — BuildingStorage not initialised → getStorageAmount returns 0
				-- 0 >= 2.0 (consumption_rate) is false
				expect(ProductionChainManager.canProduce(smelter)).to.equal(false)
				smelter:Destroy()
			end)
		end)

		describe("edge cases", function()
			it("returns false for a building with no BuildingType attribute", function()
				local m = makeNoType()
				expect(ProductionChainManager.canProduce(m)).to.equal(false)
				m:Destroy()
			end)

			it("returns false for an unknown building type", function()
				local m = makeUnknown()
				expect(ProductionChainManager.canProduce(m)).to.equal(false)
				m:Destroy()
			end)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- consumeInputs
	-- ─────────────────────────────────────────────────────────────
	describe("consumeInputs", function()
		it("Potato Farm succeeds (returns true) without consuming anything", function()
			local farm = makeFarm()
			expect(ProductionChainManager.consumeInputs(farm)).to.equal(true)
			farm:Destroy()
		end)

		it("Smelter fails (returns false) when it has no Iron_Ore in storage", function()
			local smelter = makeSmelter()
			expect(ProductionChainManager.consumeInputs(smelter)).to.equal(false)
			smelter:Destroy()
		end)

		it("returns false for a building with no BuildingType attribute", function()
			local m = makeNoType()
			expect(ProductionChainManager.consumeInputs(m)).to.equal(false)
			m:Destroy()
		end)

		it("returns false for an unknown building type", function()
			local m = makeUnknown()
			expect(ProductionChainManager.consumeInputs(m)).to.equal(false)
			m:Destroy()
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- getProductionStatus
	-- ─────────────────────────────────────────────────────────────
	describe("getProductionStatus", function()
		describe("Potato Farm (passive producer)", function()
			it("canProduce is true", function()
				local farm = makeFarm()
				local status = ProductionChainManager.getProductionStatus(farm)
				expect(status.canProduce).to.equal(true)
				farm:Destroy()
			end)

			it("inputResource is nil (no inputs needed)", function()
				local farm = makeFarm()
				local status = ProductionChainManager.getProductionStatus(farm)
				expect(status.inputResource).to.equal(nil)
				farm:Destroy()
			end)

			it("outputResource is 'Food'", function()
				local farm = makeFarm()
				local status = ProductionChainManager.getProductionStatus(farm)
				expect(status.outputResource).to.equal("Food")
				farm:Destroy()
			end)
		end)

		describe("Smelter (production chain)", function()
			it("canProduce is false when no Iron_Ore in storage", function()
				local smelter = makeSmelter()
				local status = ProductionChainManager.getProductionStatus(smelter)
				expect(status.canProduce).to.equal(false)
				smelter:Destroy()
			end)

			it("inputResource is 'Iron_Ore'", function()
				local smelter = makeSmelter()
				local status = ProductionChainManager.getProductionStatus(smelter)
				expect(status.inputResource).to.equal("Iron_Ore")
				smelter:Destroy()
			end)

			it("inputNeeded is 2 (consumption_rate from GameData)", function()
				local smelter = makeSmelter()
				local status = ProductionChainManager.getProductionStatus(smelter)
				expect(status.inputNeeded).to.equal(2.0)
				smelter:Destroy()
			end)

			it("inputAvailable is 0 when storage is not initialised", function()
				local smelter = makeSmelter()
				local status = ProductionChainManager.getProductionStatus(smelter)
				expect(status.inputAvailable).to.equal(0)
				smelter:Destroy()
			end)

			it("outputResource is 'Iron_Bars'", function()
				local smelter = makeSmelter()
				local status = ProductionChainManager.getProductionStatus(smelter)
				expect(status.outputResource).to.equal("Iron_Bars")
				smelter:Destroy()
			end)
		end)

		describe("edge cases", function()
			it("returns canProduce=false for a building with no type attribute", function()
				local m = makeNoType()
				local status = ProductionChainManager.getProductionStatus(m)
				expect(status.canProduce).to.equal(false)
				m:Destroy()
			end)

			it("returns canProduce=false for an unknown building type", function()
				local m = makeUnknown()
				local status = ProductionChainManager.getProductionStatus(m)
				expect(status.canProduce).to.equal(false)
				m:Destroy()
			end)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- isProductionChainBuilding
	-- ─────────────────────────────────────────────────────────────
	describe("isProductionChainBuilding", function()
		it("Potato Farm is a resource producer → true", function()
			expect(ProductionChainManager.isProductionChainBuilding("Potato Farm")).to.equal(true)
		end)

		it("Smelter is a resource producer → true", function()
			expect(ProductionChainManager.isProductionChainBuilding("Smelter")).to.equal(true)
		end)

		it("Lumberjack is a passive resource producer → true", function()
			expect(ProductionChainManager.isProductionChainBuilding("Lumberjack")).to.equal(true)
		end)

		it("Keep does not produce resources → false", function()
			expect(ProductionChainManager.isProductionChainBuilding("Keep")).to.equal(false)
		end)

		it("Storehouse does not produce resources → false", function()
			expect(ProductionChainManager.isProductionChainBuilding("Storehouse")).to.equal(false)
		end)

		it("Granary does not produce resources → false", function()
			expect(ProductionChainManager.isProductionChainBuilding("Granary")).to.equal(false)
		end)

		it("unknown type returns false", function()
			expect(ProductionChainManager.isProductionChainBuilding("FakeBuilding123")).to.equal(false)
		end)
	end)
end
