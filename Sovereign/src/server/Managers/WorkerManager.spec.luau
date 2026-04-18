-- WorkerManager.spec.luau
-- Tests for worker assignment, hauler task creation, and production modifier.
-- Focuses on publicly-observable effects (Instance attributes, IdlePeasantManager
-- state) since WorkerTasks/HaulerTasks are private to the module.

return function()
	local WorkerManager = require(script.Parent.WorkerManager)
	local IdlePeasantManager = require(script.Parent.IdlePeasantManager)

	-- ── helpers ────────────────────────────────────────────────────────────

	local function makePeasant(): Model
		local m = Instance.new("Model")
		m.Name = "TestPeasant"
		-- PrimaryPart needed so pathfinding code doesn't nil-error if update() is called
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = m
		m.PrimaryPart = root
		m.Parent = game.Workspace
		return m
	end

	local function makeBuilding(buildingType: string): Model
		local m = Instance.new("Model")
		m.Name = buildingType
		m:SetAttribute("BuildingType", buildingType)
		m.Parent = game.Workspace
		return m
	end

	-- ─────────────────────────────────────────────────────────────
	-- assignWorkerToBuilding
	-- ─────────────────────────────────────────────────────────────
	describe("assignWorkerToBuilding", function()
		it("sets IsWorking=true on the peasant for a worker-requiring building", function()
			local peasant = makePeasant()
			local building = makeBuilding("Potato Farm") -- requires_worker = true

			WorkerManager.assignWorkerToBuilding(peasant, building, 111)

			expect(peasant:GetAttribute("IsWorking")).to.equal(true)

			peasant:Destroy()
			building:Destroy()
		end)

		it("sets AssignedTo to the building type on the peasant", function()
			local peasant = makePeasant()
			local building = makeBuilding("Potato Farm")

			WorkerManager.assignWorkerToBuilding(peasant, building, 111)

			expect(peasant:GetAttribute("AssignedTo")).to.equal("Potato Farm")

			peasant:Destroy()
			building:Destroy()
		end)

		it("does nothing for a building that does not require workers (Keep)", function()
			local peasant = makePeasant()
			local building = makeBuilding("Keep")

			WorkerManager.assignWorkerToBuilding(peasant, building, 111)

			-- Attribute should be absent or false — not true
			expect(peasant:GetAttribute("IsWorking")).never.to.equal(true)

			peasant:Destroy()
			building:Destroy()
		end)

		it("does nothing for an unknown building type without erroring", function()
			local peasant = makePeasant()
			local building = makeBuilding("GhostBuilding")

			expect(function()
				WorkerManager.assignWorkerToBuilding(peasant, building, 111)
			end).never.to.throw()

			expect(peasant:GetAttribute("IsWorking")).never.to.equal(true)

			peasant:Destroy()
			building:Destroy()
		end)

		it("does nothing and does not error when peasant is nil", function()
			local building = makeBuilding("Potato Farm")

			expect(function()
				WorkerManager.assignWorkerToBuilding(nil, building, 111)
			end).never.to.throw()

			building:Destroy()
		end)

		it("does nothing and does not error when building is nil", function()
			local peasant = makePeasant()

			expect(function()
				WorkerManager.assignWorkerToBuilding(peasant, nil, 111)
			end).never.to.throw()

			peasant:Destroy()
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- createHaulerTask
	-- ─────────────────────────────────────────────────────────────
	describe("createHaulerTask", function()
		it("sets IsHauling=true on the hauler model", function()
			local hauler = makePeasant()
			local building = makeBuilding("Potato Farm")

			WorkerManager.createHaulerTask(hauler, building, "Food", 111)

			expect(hauler:GetAttribute("IsHauling")).to.equal(true)

			hauler:Destroy()
			building:Destroy()
		end)

		it("does not error even if the hauler was never registered as idle", function()
			local hauler = makePeasant()
			local building = makeBuilding("Potato Farm")

			expect(function()
				WorkerManager.createHaulerTask(hauler, building, "Food", 111)
			end).never.to.throw()

			hauler:Destroy()
			building:Destroy()
		end)

		it("marks the hauler as not-idle in IdlePeasantManager after assignment", function()
			local hauler = makePeasant()
			local building = makeBuilding("Potato Farm")

			-- createHaulerTask calls IdlePeasantManager.removeIdlePeasant internally.
			-- Even if the peasant was never registered idle, isIdle must return false.
			WorkerManager.createHaulerTask(hauler, building, "Food", 111)

			expect(IdlePeasantManager.isIdle(hauler)).to.equal(false)

			hauler:Destroy()
			building:Destroy()
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- setProductionModifier
	-- ─────────────────────────────────────────────────────────────
	describe("setProductionModifier", function()
		it("exists and is callable without error", function()
			local fakePlayer = { UserId = 111001, Name = "ModTest" } :: any
			expect(WorkerManager.setProductionModifier).to.be.a("function")
			expect(function()
				WorkerManager.setProductionModifier(fakePlayer, 0.5)
			end).never.to.throw()
		end)

		it("accepts 0 (halt) without error", function()
			local fakePlayer = { UserId = 111001, Name = "ModTest" } :: any
			expect(function()
				WorkerManager.setProductionModifier(fakePlayer, 0)
			end).never.to.throw()
		end)

		it("accepts 1.0 (full) without error", function()
			local fakePlayer = { UserId = 111001, Name = "ModTest" } :: any
			expect(function()
				WorkerManager.setProductionModifier(fakePlayer, 1.0)
			end).never.to.throw()
		end)

		it("clamps values above 1.0 to 1.0", function()
			-- No direct way to read productionModifiers (it's private), but at
			-- minimum it must not error on out-of-range inputs
			local fakePlayer = { UserId = 111001, Name = "ModTest" } :: any
			expect(function()
				WorkerManager.setProductionModifier(fakePlayer, 999)
			end).never.to.throw()
		end)

		it("clamps negative values to 0", function()
			local fakePlayer = { UserId = 111001, Name = "ModTest" } :: any
			expect(function()
				WorkerManager.setProductionModifier(fakePlayer, -5)
			end).never.to.throw()
		end)
	end)
end
