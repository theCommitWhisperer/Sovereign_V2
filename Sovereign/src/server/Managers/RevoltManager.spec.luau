-- RevoltManager.spec.luau
-- Tests for revolt risk calculation and recordUnitLoss.
-- calculateRevoltRisk is pure math (no side effects), so these tests don't
-- need to worry about the WorkerManager.setProductionModifier bug.
-- checkRevoltStage / triggerRevoltStage are NOT tested here because they
-- call WorkerManager.setProductionModifier (nil) and will crash.

return function()
	local PlayerManager = require(script.Parent.PlayerManager)
	local HappinessManager = require(script.Parent.HappinessManager)
	local TaxManager = require(script.Parent.TaxManager)
	local RevoltManager = require(script.Parent.RevoltManager)

	local fakePlayer = { UserId = 888401, Name = "RevoltTest" } :: any

	beforeEach(function()
		PlayerManager.remove(fakePlayer)
		PlayerManager.create(fakePlayer)
		local pd = PlayerManager.get(fakePlayer)
		if pd then pd.GameState = "InGame" end
		HappinessManager.create(fakePlayer)
		TaxManager.create(fakePlayer)
		RevoltManager.create(fakePlayer)
	end)

	afterEach(function()
		PlayerManager.remove(fakePlayer)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- Initialization
	-- ─────────────────────────────────────────────────────────────
	describe("create and get", function()
		it("creates revolt data without erroring", function()
			expect(function()
				RevoltManager.create(fakePlayer)
			end).never.to.throw()
		end)

		it("initializes revoltRisk at 0", function()
			local data = RevoltManager.get(fakePlayer)
			expect(data).to.be.ok()
			expect(data.revoltRisk).to.equal(0)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- calculateRevoltRisk formula
	-- Formula:
	--   if happiness < 50: risk += (50 - happiness)   [max 50]
	--   risk += (taxRate * 100) / 2                   [max 50]
	--   if food == 0: risk += 25
	--   clamp(risk, 0, 100)
	-- ─────────────────────────────────────────────────────────────
	describe("calculateRevoltRisk", function()
		it("returns only the tax portion when happiness=50, food>0", function()
			-- TaxManager.create sets taxRate=0.1 → (0.1*100)/2 = 5
			local hd = HappinessManager.get(fakePlayer)
			hd.happiness = 50
			PlayerManager.addResources(fakePlayer, { Food = 100 })

			local risk = RevoltManager.calculateRevoltRisk(fakePlayer)
			expect(risk).to.equal(5) -- 0 (happiness) + 5 (tax) + 0 (food) = 5
		end)

		it("adds happiness deficit when happiness < 50", function()
			-- happiness=30 → deficit=20; taxRate=0 → 0; food>0 → 0
			local hd = HappinessManager.get(fakePlayer)
			hd.happiness = 30
			TaxManager.setTaxRate(fakePlayer, 0)
			PlayerManager.addResources(fakePlayer, { Food = 100 })

			local risk = RevoltManager.calculateRevoltRisk(fakePlayer)
			expect(risk).to.equal(20)
		end)

		it("caps the happiness contribution at 50 (happiness=0)", function()
			local hd = HappinessManager.get(fakePlayer)
			hd.happiness = 0 -- deficit = 50 → capped at 50
			TaxManager.setTaxRate(fakePlayer, 0)
			PlayerManager.addResources(fakePlayer, { Food = 100 })

			local risk = RevoltManager.calculateRevoltRisk(fakePlayer)
			expect(risk).to.equal(50)
		end)

		it("adds 25 when player has no food", function()
			local hd = HappinessManager.get(fakePlayer)
			hd.happiness = 50
			TaxManager.setTaxRate(fakePlayer, 0)
			-- Food stays at 0 (default after create)

			local risk = RevoltManager.calculateRevoltRisk(fakePlayer)
			expect(risk).to.equal(25) -- 0 (happiness) + 0 (tax) + 25 (no food)
		end)

		it("does NOT add the food penalty when food > 0", function()
			local hd = HappinessManager.get(fakePlayer)
			hd.happiness = 50
			TaxManager.setTaxRate(fakePlayer, 0)
			PlayerManager.addResources(fakePlayer, { Food = 1 })

			local risk = RevoltManager.calculateRevoltRisk(fakePlayer)
			expect(risk).to.equal(0) -- no modifiers
		end)

		it("tax rate scales linearly: 50% tax = 25 risk points", function()
			local hd = HappinessManager.get(fakePlayer)
			hd.happiness = 50
			TaxManager.setTaxRate(fakePlayer, 0.5) -- (0.5*100)/2 = 25
			PlayerManager.addResources(fakePlayer, { Food = 100 })

			local risk = RevoltManager.calculateRevoltRisk(fakePlayer)
			expect(risk).to.equal(25)
		end)

		it("100% tax = 50 risk points (maximum tax contribution)", function()
			local hd = HappinessManager.get(fakePlayer)
			hd.happiness = 50
			TaxManager.setTaxRate(fakePlayer, 1.0) -- (1.0*100)/2 = 50
			PlayerManager.addResources(fakePlayer, { Food = 100 })

			local risk = RevoltManager.calculateRevoltRisk(fakePlayer)
			expect(risk).to.equal(50)
		end)

		it("clamps total risk at 100 when all factors are maxed", function()
			local hd = HappinessManager.get(fakePlayer)
			hd.happiness = 0 -- +50
			TaxManager.setTaxRate(fakePlayer, 1.0) -- +50
			-- No food → +25; total = 125 → clamped to 100

			local risk = RevoltManager.calculateRevoltRisk(fakePlayer)
			expect(risk).to.equal(100)
		end)

		it("returns 0 when all factors are zero (happiness=50, 0% tax, food=1)", function()
			local hd = HappinessManager.get(fakePlayer)
			hd.happiness = 50
			TaxManager.setTaxRate(fakePlayer, 0)
			PlayerManager.addResources(fakePlayer, { Food = 1 })

			local risk = RevoltManager.calculateRevoltRisk(fakePlayer)
			expect(risk).to.equal(0)
		end)

		it("returns 0 for a player with no happiness/tax/revolt data", function()
			local ghost = { UserId = 888499, Name = "Ghost" } :: any
			local risk = RevoltManager.calculateRevoltRisk(ghost)
			expect(risk).to.equal(0)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- recordUnitLoss
	-- ─────────────────────────────────────────────────────────────
	describe("recordUnitLoss", function()
		it("increments revoltRisk by 1", function()
			local data = RevoltManager.get(fakePlayer)
			local initial = data.revoltRisk
			RevoltManager.recordUnitLoss(fakePlayer)
			expect(data.revoltRisk).to.equal(initial + 1)
		end)

		it("can be called multiple times to accumulate risk", function()
			RevoltManager.recordUnitLoss(fakePlayer)
			RevoltManager.recordUnitLoss(fakePlayer)
			RevoltManager.recordUnitLoss(fakePlayer)
			local data = RevoltManager.get(fakePlayer)
			expect(data.revoltRisk).to.equal(3)
		end)

		it("caps revoltRisk at 100 — cannot exceed maximum", function()
			local data = RevoltManager.get(fakePlayer)
			data.revoltRisk = 100
			RevoltManager.recordUnitLoss(fakePlayer)
			expect(data.revoltRisk).to.equal(100)
		end)

		it("does not error when called for an unknown player", function()
			local ghost = { UserId = 888499, Name = "Ghost" } :: any
			expect(function()
				RevoltManager.recordUnitLoss(ghost)
			end).never.to.throw()
		end)
	end)
end
