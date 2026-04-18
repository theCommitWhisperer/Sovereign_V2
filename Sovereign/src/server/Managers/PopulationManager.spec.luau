-- PopulationManager.spec.luau
-- Tests for population tracking (no unit AI or building logic needed).

return function()
	local PopulationManager = require(script.Parent.PopulationManager)
	local PlayerManager = require(script.Parent.PlayerManager)

	local fakePlayer = { UserId = 777006, Name = "PopTestPlayer" } :: any

	beforeEach(function()
		PlayerManager.remove(fakePlayer)
		PlayerManager.create(fakePlayer)
		PopulationManager.create(fakePlayer)
	end)

	describe("create and get", function()
		it("creates population data without erroring", function()
			expect(function()
				PopulationManager.create(fakePlayer)
			end).never.to.throw()
		end)

		it("get returns data after create", function()
			expect(PopulationManager.get(fakePlayer)).to.be.ok()
		end)

		it("initial currentPopulation is 0", function()
			local data = PopulationManager.get(fakePlayer)
			expect(data.currentPopulation).to.equal(0)
		end)

		it("initial housingCapacity is 0", function()
			local data = PopulationManager.get(fakePlayer)
			expect(data.housingCapacity).to.equal(0)
		end)

		it("initial isOvercrowded is false", function()
			local data = PopulationManager.get(fakePlayer)
			expect(data.isOvercrowded).to.equal(false)
		end)
	end)

	describe("getCurrentPopulation", function()
		it("returns 0 when player has no units", function()
			expect(PopulationManager.getCurrentPopulation(fakePlayer)).to.equal(0)
		end)

		it("counts non-military tagged instances in playerData.Units", function()
			local playerData = PlayerManager.get(fakePlayer)
			-- getCurrentPopulation checks `unit and unit.Parent`, so the unit must be parented
			local fakeUnit = Instance.new("Model")
			fakeUnit:SetAttribute("UnitType", "Peasant")
			fakeUnit.Parent = game.Workspace -- must have a parent to pass the nil-parent guard
			table.insert(playerData.Units, fakeUnit)

			local count = PopulationManager.getCurrentPopulation(fakePlayer)
			expect(count).to.equal(1)

			fakeUnit:Destroy()
			playerData.Units = {}
		end)
	end)

	describe("canGrowPopulation", function()
		it("returns false when housing capacity is 0", function()
			expect(PopulationManager.canGrowPopulation(fakePlayer)).to.equal(false)
		end)

		it("returns true when housingCapacity exceeds currentPopulation", function()
			local data = PopulationManager.get(fakePlayer)
			data.housingCapacity = 10
			data.currentPopulation = 5
			expect(PopulationManager.canGrowPopulation(fakePlayer)).to.equal(true)
		end)

		it("returns false when population equals housing capacity", function()
			local data = PopulationManager.get(fakePlayer)
			data.housingCapacity = 5
			data.currentPopulation = 5
			expect(PopulationManager.canGrowPopulation(fakePlayer)).to.equal(false)
		end)
	end)

	describe("isOvercrowded", function()
		it("returns false by default", function()
			expect(PopulationManager.isOvercrowded(fakePlayer)).to.equal(false)
		end)

		it("returns true when isOvercrowded flag is set", function()
			local data = PopulationManager.get(fakePlayer)
			data.isOvercrowded = true
			expect(PopulationManager.isOvercrowded(fakePlayer)).to.equal(true)
		end)
	end)

	describe("createAI", function()
		it("creates AI population data without erroring", function()
			expect(function()
				PopulationManager.createAI(888001, "TestAI")
			end).never.to.throw()
		end)
	end)
end
