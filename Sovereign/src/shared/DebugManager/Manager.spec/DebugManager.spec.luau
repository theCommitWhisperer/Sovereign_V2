return function()
	local DebugManager = require(script.Parent.Parent)

	describe("DebugManager", function()
		it("should be a table", function()
			expect(typeof(DebugManager)).to.equal("table")
		end)

		it("should log an info message without errors", function()
			expect(function()
				DebugManager.info("Test info message")
			end).never.to.throw()
		end)

		it("should handle logging with data tables", function()
			expect(function()
				DebugManager.info("Test with data", {
					key1 = "value1",
					key2 = 42,
				})
			end).never.to.throw()
		end)

		it("should handle logging with Vector3 data", function()
			expect(function()
				DebugManager.info("Test with Vector3", {
					position = Vector3.new(10, 20, 30),
				})
			end).never.to.throw()
		end)

		it("should create channels", function()
			local channel = DebugManager.createChannel("TestChannel", true)
			expect(typeof(channel)).to.equal("table")
			expect(channel.name).to.equal("TestChannel")
			expect(channel.enabled).to.equal(true)
		end)

		it("should respect channel enabled flag", function()
			local channel = DebugManager.createChannel("DisabledChannel", false)
			expect(function()
				channel:info("This should not print")
			end).never.to.throw()
		end)

		it("should allow enabling/disabling channels", function()
			DebugManager.createChannel("ToggleChannel", true)
			expect(function()
				DebugManager.setChannelEnabled("ToggleChannel", false)
				DebugManager.setChannelEnabled("ToggleChannel", true)
			end).never.to.throw()
		end)
	end)
end
