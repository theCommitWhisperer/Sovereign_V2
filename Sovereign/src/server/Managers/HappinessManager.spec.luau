-- HappinessManager.spec.luau
-- Tests for happiness initialization, revolt-stage threshold logic,
-- and end-to-end stage transitions (which call WorkerManager.setProductionModifier).

return function()
	local PlayerManager = require(script.Parent.PlayerManager)
	local HappinessManager = require(script.Parent.HappinessManager)

	local fakePlayer = { UserId = 888301, Name = "HappinessTest" } :: any

	beforeEach(function()
		PlayerManager.remove(fakePlayer)
		PlayerManager.create(fakePlayer)
		HappinessManager.create(fakePlayer)
	end)

	afterEach(function()
		PlayerManager.remove(fakePlayer)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- Initialization
	-- ─────────────────────────────────────────────────────────────
	describe("create and get", function()
		it("initializes with happiness = 50", function()
			local data = HappinessManager.get(fakePlayer)
			expect(data).to.be.ok()
			expect(data.happiness).to.equal(50)
		end)

		it("initializes with revoltStage = 0 (no revolt)", function()
			local data = HappinessManager.get(fakePlayer)
			expect(data.revoltStage).to.equal(0)
		end)

		it("returns nil for a player who never had data created", function()
			local ghost = { UserId = 999999, Name = "Ghost" } :: any
			expect(HappinessManager.get(ghost)).to.equal(nil)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- checkForRevolt — stage stays the same (no transition)
	-- Pre-set revoltStage to match what checkForRevolt computes so
	-- newStage == currentStage and triggerRevoltStage is never called.
	-- ─────────────────────────────────────────────────────────────
	describe("checkForRevolt — stage boundaries (no transition)", function()
		it("happiness >= 40 keeps stage at 0 (boundary = exactly 40)", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 40
			data.revoltStage = 0
			HappinessManager.checkForRevolt(fakePlayer)
			expect(data.revoltStage).to.equal(0)
		end)

		it("happiness of 50 keeps stage at 0", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 50
			data.revoltStage = 0
			HappinessManager.checkForRevolt(fakePlayer)
			expect(data.revoltStage).to.equal(0)
		end)

		it("happiness 20-39 stays at stage 1 when already at stage 1", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 30
			data.revoltStage = 1
			HappinessManager.checkForRevolt(fakePlayer)
			expect(data.revoltStage).to.equal(1)
		end)

		it("happiness 10-19 stays at stage 2 when already at stage 2", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 15
			data.revoltStage = 2
			HappinessManager.checkForRevolt(fakePlayer)
			expect(data.revoltStage).to.equal(2)
		end)

		it("happiness < 10 stays at stage 3 when already at stage 3", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 5
			data.revoltStage = 3
			HappinessManager.checkForRevolt(fakePlayer)
			expect(data.revoltStage).to.equal(3)
		end)

		it("happiness exactly 20 maps to stage 1 (< 20 is false)", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 20
			data.revoltStage = 1
			HappinessManager.checkForRevolt(fakePlayer)
			expect(data.revoltStage).to.equal(1)
		end)

		it("happiness exactly 10 maps to stage 2 (< 10 is false)", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 10
			data.revoltStage = 2
			HappinessManager.checkForRevolt(fakePlayer)
			expect(data.revoltStage).to.equal(2)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- checkForRevolt — actual stage transitions
	-- ─────────────────────────────────────────────────────────────
	describe("checkForRevolt — stage transitions", function()
		it("transitions from stage 0 to stage 1 when happiness drops below 40", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 35
			data.revoltStage = 0

			expect(function()
				HappinessManager.checkForRevolt(fakePlayer)
			end).never.to.throw()

			expect(data.revoltStage).to.equal(1)
		end)

		it("transitions to stage 2 when happiness drops below 20", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 15
			data.revoltStage = 0

			expect(function()
				HappinessManager.checkForRevolt(fakePlayer)
			end).never.to.throw()

			expect(data.revoltStage).to.equal(2)
		end)

		it("transitions to stage 3 when happiness drops below 10", function()
			local data = HappinessManager.get(fakePlayer)
			data.happiness = 5
			data.revoltStage = 0

			expect(function()
				HappinessManager.checkForRevolt(fakePlayer)
			end).never.to.throw()

			expect(data.revoltStage).to.equal(3)
		end)

		it("recovers back to stage 0 when happiness rises to 40 or above", function()
			local data = HappinessManager.get(fakePlayer)
			-- Start in stage 3, happiness improves
			data.happiness = 5
			data.revoltStage = 3

			data.happiness = 50
			expect(function()
				HappinessManager.checkForRevolt(fakePlayer)
			end).never.to.throw()

			expect(data.revoltStage).to.equal(0)
		end)
	end)
end
