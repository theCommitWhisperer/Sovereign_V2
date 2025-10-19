-- Sovereign_V2/src/shared/DebugSystem/Manager.spec/DebugManager.spec.luau

return function()
	local DebugManager = require(script.Parent.Parent.Manager.DebugManager)

	describe("DebugManager", function()
		it("should be a table", function()
			expect(typeof(DebugManager)).to.equal("table")
		end)

		it("should log an info message without errors", function()
			expect(function()
				DebugManager.info("TestSystem", "This is an info message.")
			end).to.be.ok()
		end)

		it("should handle logging with data tables", function()
			expect(function()
				DebugManager.info("TestSystem", "Logging with data.", {
					testKey = "testValue",
					testNumber = 42,
				})
			end).to.be.ok()
		end)

		it("should handle logging with Vector3 data", function()
			expect(function()
				DebugManager.info("TestSystem", "Logging with Vector3.", {
					position = Vector3.new(10, 20, 30),
				})
			end).to.be.ok()
		end)
	end)
end
