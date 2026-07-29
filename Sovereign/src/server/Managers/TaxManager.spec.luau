-- TaxManager.spec.luau
-- Tests for tax rate management and collection logic.

return function()
	local TaxManager = require(script.Parent.TaxManager)
	local PlayerManager = require(script.Parent.PlayerManager)
	local EconomyConfig = require(game:GetService("ReplicatedStorage").Shared.GameData.EconomyConfig)

	local fakePlayer = { UserId = 777005, Name = "TaxTestPlayer" } :: any

	beforeEach(function()
		PlayerManager.remove(fakePlayer)
		PlayerManager.create(fakePlayer)
		TaxManager.create(fakePlayer)
	end)

	describe("create and get", function()
		it("creates tax data without erroring", function()
			expect(function()
				TaxManager.create(fakePlayer)
			end).never.to.throw()
		end)

		it("get returns data after create", function()
			expect(TaxManager.get(fakePlayer)).to.be.ok()
		end)

		it("initial tax rate is 0.1 (10%)", function()
			local data = TaxManager.get(fakePlayer)
			expect(data.taxRate).to.equal(0.1)
		end)
	end)

	describe("setTaxRate", function()
		it("sets a valid tax rate", function()
			TaxManager.setTaxRate(fakePlayer, 0.25)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(0.25)
		end)

		it("clamps tax rate to a maximum of 1.0 (100%)", function()
			TaxManager.setTaxRate(fakePlayer, 1.5)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(1.0)
		end)

		-- The floor is no longer 0: "Generous Gifts" is a negative-rate policy
		-- where the crown pays its subjects to buy popularity back. The floor is
		-- the most generous rate in EconomyConfig.TaxPolicies, so an absurd
		-- value still clamps, just not to zero.
		it("clamps tax rate to the most generous policy rate", function()
			local minPolicyRate = 0
			for _, policy in EconomyConfig.TaxPolicies do
				if policy.rate < minPolicyRate then
					minPolicyRate = policy.rate
				end
			end

			TaxManager.setTaxRate(fakePlayer, -5)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(minPolicyRate)
		end)

		it("0% tax rate stores correctly", function()
			TaxManager.setTaxRate(fakePlayer, 0)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(0)
		end)

		it("100% tax rate stores correctly", function()
			TaxManager.setTaxRate(fakePlayer, 1.0)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(1.0)
		end)
	end)

	describe("collectTaxes", function()
		it("does not error when collecting taxes", function()
			expect(function()
				TaxManager.collectTaxes(fakePlayer)
			end).never.to.throw()
		end)

		it("adds gold based on population, tax rate and popularity gate", function()
			-- Give the player 10 peasants (population) and a 10% tax rate.
			-- Peasants must be parented + tagged to count as population.
			local playerData = PlayerManager.get(fakePlayer)
			for _ = 1, 10 do
				local fakeUnit = Instance.new("Model")
				fakeUnit:SetAttribute("UnitType", "Peasant")
				fakeUnit.Parent = workspace
				table.insert(playerData.Units, fakeUnit)
			end
			playerData.Happiness = 50 -- popularity gate multiplier 1.0
			TaxManager.setTaxRate(fakePlayer, 0.1)
			TaxManager.collectTaxes(fakePlayer)
			-- 10 population * 0.1 rate * 1.0 popularity = 1 gold (floor)
			expect(playerData.Resources.Gold).to.equal(1)
			-- Clean up
			for _, u in playerData.Units do u:Destroy() end
			playerData.Units = {}
		end)

		it("collects nothing when popularity is at revolt levels", function()
			local playerData = PlayerManager.get(fakePlayer)
			for _ = 1, 10 do
				local fakeUnit = Instance.new("Model")
				fakeUnit:SetAttribute("UnitType", "Peasant")
				fakeUnit.Parent = workspace
				table.insert(playerData.Units, fakeUnit)
			end
			playerData.Happiness = 5 -- below the lowest gate tier -> 0x income
			TaxManager.setTaxRate(fakePlayer, 0.5)
			TaxManager.collectTaxes(fakePlayer)
			expect(playerData.Resources.Gold).to.equal(0)
			for _, u in playerData.Units do u:Destroy() end
			playerData.Units = {}
		end)
	end)
end
