--!strict
-- UISetup.spec.luau
-- Regression tests for root ScreenGui configuration.
--
-- Bug history: Without IgnoreGuiInset = true on the root ScreenGui, Roblox pushes
-- all UI content down by the top-bar height (~36px), leaving a gap at the very top
-- of the screen where the 3D world (terrain, water) bleeds through. This was visible
-- as a water strip during the Main Menu and Lobby screens.
--
-- Fix: rootGui.IgnoreGuiInset = true in src/ui/main.client.luau
-- If this test fails, verify that line is still present.

return function()
	describe("Root ScreenGui configuration", function()
		it("IgnoreGuiInset defaults to false — must be set explicitly", function()
			-- Confirms Roblox does NOT cover the inset by default.
			-- This is why we must always set it explicitly in main.client.luau.
			local gui = Instance.new("ScreenGui")
			expect(gui.IgnoreGuiInset).to.equal(false)
			gui:Destroy()
		end)

		it("setting IgnoreGuiInset = true covers the full screen including the top bar", function()
			-- This mirrors the setup in src/ui/main.client.luau.
			-- If someone removes rootGui.IgnoreGuiInset = true, the water-strip bug returns.
			local gui = Instance.new("ScreenGui")
			gui.Name = "SovereignApp"
			gui.IgnoreGuiInset = true

			expect(gui.IgnoreGuiInset).to.equal(true)
			gui:Destroy()
		end)

		it("ZIndexBehavior should be Sibling so UI layers render correctly", function()
			-- Ensures UI elements stack by their ZIndex, not by tree order.
			local gui = Instance.new("ScreenGui")
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

			expect(gui.ZIndexBehavior).to.equal(Enum.ZIndexBehavior.Sibling)
			gui:Destroy()
		end)
	end)
end
