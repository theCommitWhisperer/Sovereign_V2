--!strict
-- TestRunner.server.luau
-- Runs all TestEZ specs in the project automatically when the game starts in Studio.
-- Results appear in the Output window. Failed tests are printed in red.
-- Add new spec files anywhere under src/shared or src/server — they're picked up automatically.

local RunService = game:GetService("RunService")

-- Only run tests in Studio (never in a live game)
if not RunService:IsStudio() then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Wait for packages to be available
local Packages = ReplicatedStorage:WaitForChild("Packages", 10)
if not Packages then
	warn("[TestRunner] Packages folder not found — did you run `wally install`?")
	return
end

local TestEZ = require(Packages.testez)

-- Collect all spec roots to scan.
-- TestEZ will recursively find any ModuleScript whose name ends in ".spec"
local testRoots = {
	ReplicatedStorage:WaitForChild("Shared", 5),
	ServerScriptService:WaitForChild("Server", 5),
}

local validRoots = {}
for _, root in testRoots do
	if root then
		table.insert(validRoots, root)
	else
		warn("[TestRunner] Could not find a test root — some specs may be skipped")
	end
end

print("\n========================================")
print("  🧪 SOVEREIGN TEST SUITE")
print("========================================\n")

local results = TestEZ.TestBootstrap:run(validRoots)

-- Summary line
local passed = results.successCount or 0
local failed = results.failureCount or 0
local skipped = results.skippedCount or 0

print("\n========================================")
if failed == 0 then
	print(string.format("  ✅ ALL TESTS PASSED  (%d passed, %d skipped)", passed, skipped))
else
	print(string.format("  ❌ %d FAILED  |  %d passed  |  %d skipped", failed, passed, skipped))
end
print("========================================\n")
