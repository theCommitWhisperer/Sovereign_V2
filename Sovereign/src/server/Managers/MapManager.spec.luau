-- MapManager.spec.luau
-- Tests for map selection and config retrieval.

return function()
	local MapManager = require(script.Parent.MapManager)

	describe("getAvailableMaps", function()
		it("returns a non-empty list of map names", function()
			local maps = MapManager.getAvailableMaps()
			expect(maps).to.be.a("table")
			expect(#maps > 0).to.equal(true)
		end)

		it("each entry is a non-empty string", function()
			for _, name in MapManager.getAvailableMaps() do
				expect(name).to.be.a("string")
				expect(#name > 0).to.equal(true)
			end
		end)
	end)

	describe("setMap and getCurrentMapName", function()
		afterEach(function()
			MapManager.unlockMatchMap()
		end)

		it("sets a valid map and getCurrentMapName reflects it", function()
			local maps = MapManager.getAvailableMaps()
			local firstName = maps[1]
			MapManager.setMap(firstName)
			expect(MapManager.getCurrentMapName()).to.equal(firstName)
		end)

		it("returns false for an unknown map name", function()
			expect(MapManager.setMap("ThisMapDoesNotExist")).to.equal(false)
		end)

		it("getCurrentMapName is unchanged after a failed setMap", function()
			local before = MapManager.getCurrentMapName()
			MapManager.setMap("ThisMapDoesNotExist")
			expect(MapManager.getCurrentMapName()).to.equal(before)
		end)
	end)

	describe("match map locking", function()
		afterEach(function()
			MapManager.unlockMatchMap()
		end)

		it("keeps a match on its first locked map", function()
			local maps = MapManager.getAvailableMaps()
			local firstMap = maps[1]
			local otherMap = maps[2] or firstMap

			expect(MapManager.lockMatchMap(firstMap)).to.equal(true)
			expect(MapManager.isMatchMapLocked()).to.equal(true)
			expect(MapManager.lockMatchMap(firstMap)).to.equal(true)
			expect(MapManager.setMap(otherMap)).to.equal(otherMap == firstMap)
			expect(MapManager.getCurrentMapName()).to.equal(firstMap)
		end)
	end)

	describe("getCurrentMap", function()
		it("returns a config table with required fields", function()
			local config = MapManager.getCurrentMap()
			expect(config).to.be.a("table")
			expect(config.Name).to.be.a("string")
			expect(config.Size).to.be.a("number")
			expect(config.MaxPlayers).to.be.a("number")
		end)

		it("Size is a positive number", function()
			expect(MapManager.getCurrentMap().Size > 0).to.equal(true)
		end)

		it("MaxPlayers is between 1 and 4", function()
			local mp = MapManager.getCurrentMap().MaxPlayers
			expect(mp >= 1 and mp <= 4).to.equal(true)
		end)
	end)

	describe("getMapConfig", function()
		it("returns config for a valid map name", function()
			local maps = MapManager.getAvailableMaps()
			local config = MapManager.getMapConfig(maps[1])
			expect(config).to.be.ok()
		end)

		it("returns nil for an unknown map name", function()
			expect(MapManager.getMapConfig("GhostMap")).never.to.be.ok()
		end)
	end)
end
