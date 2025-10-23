--!strict
-- MovementSystem: Handles server-side unit movement

local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MovementDebug = DebugManager.createChannel("Movement", false)

local MovementSystem = {}

local movingUnits: { [Model]: boolean } = {}

-- Simple movement towards target
local function moveTowardsTarget(unit: Model, target: Vector3, speed: number, deltaTime: number): boolean
	if not unit.PrimaryPart then
		return true
	end

	local currentPos = unit.PrimaryPart.Position
	local targetPos2D = Vector3.new(target.X, currentPos.Y, target.Z)
	local distance = (targetPos2D - currentPos).Magnitude

	if distance < 2 then
		-- Arrived
		return true
	end

	-- Move towards target
	local direction = (targetPos2D - currentPos).Unit
	local moveAmount = speed * deltaTime

	if moveAmount >= distance then
		-- Will arrive this frame
		unit:SetPrimaryPartCFrame(CFrame.new(targetPos2D))
		return true
	else
		-- Move closer
		local newPos = currentPos + (direction * moveAmount)
		unit:SetPrimaryPartCFrame(CFrame.new(newPos))
		return false
	end
end

-- Update all moving units
function MovementSystem.update(deltaTime: number)
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return
	end

	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model") and unit:GetAttribute("IsMoving") then
			local targetPos = unit:GetAttribute("TargetPosition")

			if targetPos and typeof(targetPos) == "Vector3" then
				-- Get unit info for speed
				local unitType = unit:GetAttribute("UnitType")
				local speed = 16 -- Default speed (studs per second)

				if unitType then
					local GameData = require(game.ReplicatedStorage.Shared.GameData)
					local unitInfo = GameData.Units[unitType]
					if unitInfo and unitInfo.movement then
						speed = unitInfo.movement.speed_meters_per_second * 16 -- Convert m/s to studs/s
					end
				end

				-- Move unit
				local arrived = moveTowardsTarget(unit, targetPos, speed, deltaTime)

				if arrived then
					-- Clear movement
					unit:SetAttribute("IsMoving", false)
					unit:SetAttribute("TargetPosition", nil)
					MovementDebug:info(`Unit {unit.Name} arrived at destination`)
				end
			else
				-- No valid target, stop moving
				unit:SetAttribute("IsMoving", false)
			end
		end
	end
end

-- Start update loop
RunService.Heartbeat:Connect(function(deltaTime)
	MovementSystem.update(deltaTime)
end)

MovementDebug:info("Initialized")

return MovementSystem