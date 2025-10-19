--!strict
-- sovereign_v2/src/server/BuildingSystem/Manager.spec/BuildingValidation.spec.luau

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local Test = require(ReplicatedStorage.Packages.testez)

	-- Mock Data Modules
	local mockBuildingsData = {
		Keep = { type = "Building", size = Vector3.new(24, 30, 24) },
		Hovel = { type = "Building", size = Vector3.new(8, 6, 8) },
		Barracks = { type = "Building", size = Vector3.new(15, 10, 15) },
	}

	-- Setup to be run once before all tests
	Test.setup(function(ctx: Test.TestContext)
		-- Mock the Shared GameData modules
		ctx.mock("ReplicatedStorage.Shared.GameData.BuildingsData", mockBuildingsData)

		-- Create a mock Keep model that persists for all tests
		local keepModel = Instance.new("Model")
		keepModel.Name = "Keep_1"
		local primaryPart = Instance.new("Part", keepModel)
		primaryPart.Name = "PrimaryPart"
		primaryPart.Size = Vector3.new(10, 10, 10)
		keepModel.PrimaryPart = primaryPart
		keepModel.Parent = game.Workspace
		ctx.keep = keepModel
		ctx.primaryPart = primaryPart
	end)

	-- Require the ported module after setup
	local BuildingValidation = require(ReplicatedStorage.Server.BuildingSystem.Manager.BuildingValidation)

	describe("BuildingValidation", function()
		local testPlayer: Player
		local playerData: { [string]: any }

		Test.beforeEach(function(ctx: Test.TestContext)
			testPlayer = Players:CreateNewTestPlayer(1)

			playerData = {
				Player = testPlayer,
				Keep = ctx.keep,
				BuildZoneRadius = 100,
			}
			ctx.primaryPart.Position = Vector3.new(0, 5, 0)
		end)

		Test.afterEach(function()
			Players:DestroyTestPlayer(testPlayer)
			-- Clean up any temporary parts created for overlap tests
			for _, child in ipairs(game.Workspace:GetChildren()) do
				if child.Name == "tempPart" or child.Name == "BuildingSpawnPoint" then
					child:Destroy()
				end
			end
		end)

		Test.test("isValidPlacement should allow Keep placement regardless of location", function()
			Test.expect(BuildingValidation.isValidPlacement(testPlayer, CFrame.new(1000, 10, 1000), playerData, "Keep")).to
				.equal(true)
		end)

		Test.test("isValidPlacement should pass when within the build zone radius", function()
			local nearCFrame = CFrame.new(10, 5, 0)
			Test.expect(BuildingValidation.isValidPlacement(testPlayer, nearCFrame, playerData, "Hovel")).to.equal(true)
		end)
	end)
end
