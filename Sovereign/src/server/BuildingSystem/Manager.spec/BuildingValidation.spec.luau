-- BuildingManager storage tests
-- Tests for BuildingManager's storage API (addToStorage, takeFromStorage,
-- getStorageAmount, hasStorageSpace). These are the functions workers call every
-- resource cycle, so their edge-case behaviour matters for game stability.

return function()
	local BuildingManager = require(game.ServerScriptService.Server.Managers.BuildingManager)

	-- A fake building instance with no storage initialised (simulates a building
	-- that workers might reference before it's fully set up, or after it's destroyed)
	local function makeFakeBuilding(buildingType: string?): Instance
		local part = Instance.new("Part")
		part.Name = buildingType or "FakeBuilding"
		if buildingType then
			part:SetAttribute("BuildingType", buildingType)
		end
		part.Parent = game.Workspace
		return part
	end

	describe("getStorageAmount — safe defaults", function()
		it("returns 0 for a building with no storage record", function()
			local b = makeFakeBuilding()
			local amount = BuildingManager.getStorageAmount(b, "Wood")
			expect(amount).to.equal(0)
			b:Destroy()
		end)

		it("returns 0 for an unknown resource type on an unknown building", function()
			local b = makeFakeBuilding()
			expect(BuildingManager.getStorageAmount(b, "MagicDust")).to.equal(0)
			b:Destroy()
		end)
	end)

	describe("takeFromStorage — safe defaults", function()
		it("returns 0 when building has no storage record", function()
			local b = makeFakeBuilding()
			local taken = BuildingManager.takeFromStorage(b, "Wood", 50)
			expect(taken).to.equal(0)
			b:Destroy()
		end)

		it("returns 0 for unknown resource type", function()
			local b = makeFakeBuilding()
			expect(BuildingManager.takeFromStorage(b, "Unobtainium", 10)).to.equal(0)
			b:Destroy()
		end)
	end)

	describe("addToStorage — safe defaults", function()
		it("returns 0 when building has no storage record", function()
			local b = makeFakeBuilding()
			local added = BuildingManager.addToStorage(b, "Wood", 50)
			expect(added).to.equal(0)
			b:Destroy()
		end)

		it("does not error when called with a destroyed building reference", function()
			local b = makeFakeBuilding()
			b:Destroy()
			expect(function()
				BuildingManager.addToStorage(b, "Wood", 10)
			end).never.to.throw()
		end)
	end)

	describe("hasStorageSpace — safe defaults", function()
		it("returns false for a building with no storage record", function()
			local b = makeFakeBuilding()
			expect(BuildingManager.hasStorageSpace(b, "Wood", 10)).to.equal(false)
			b:Destroy()
		end)

		it("returns false for unknown resource on unknown building", function()
			local b = makeFakeBuilding()
			expect(BuildingManager.hasStorageSpace(b, "Unobtainium", 1)).to.equal(false)
			b:Destroy()
		end)
	end)
end
