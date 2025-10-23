--!strict
-- MoraleManager: Handles morale effects for Irish RTS combat
-- Units fight better with high morale, flee with low morale

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MoraleDebug = DebugManager.createChannel("Morale", true)

local MoraleManager = {}

-- Morale constants
local BASE_MORALE = 75
local MAX_MORALE = 100
local MIN_MORALE = 0
local FLEE_THRESHOLD = 20
local RALLY_THRESHOLD = 40
local INSPIRED_THRESHOLD = 85

-- Irish faction morale bonuses
local IRISH_BASE_MORALE_BONUS = 10 -- Irish units start with higher morale
local BARD_AURA_RANGE = 50 -- studs
local BARD_MORALE_BOOST = 2 -- per second
local HERO_AURA_RANGE = 75
local HERO_MORALE_BOOST = 3

-- Morale factors
local FACTORS = {
	ALLY_DEATH_NEARBY = -10,
	ENEMY_DEATH_NEARBY = 5,
	WINNING_COMBAT = 2,
	LOSING_COMBAT = -3,
	OUTNUMBERED = -5,
	OUTNUMBERING = 3,
	HIGH_GROUND = 2,
	LOW_GROUND = -2,
	COMMANDER_NEARBY = 5,
	IN_FORMATION = 3,
	BROKEN_FORMATION = -5,
}

export type MoraleState = "Fleeing" | "Shaken" | "Steady" | "Confident" | "Inspired"

export type UnitMorale = {
	current: number,
	max: number,
	state: MoraleState,
	lastUpdate: number,
	modifiers: { [string]: number },
}

local UnitMoraleData: { [Model]: UnitMorale } = {}

-- Initialize morale for a unit
function MoraleManager.initializeUnit(unitModel: Model, faction: string)
	local baseMorale = BASE_MORALE

	if not faction or type(faction) ~= "string" then
		-- Handle incorrect or missing argument gracefully
		faction = "Kingdom"
		MoraleDebug:warn("Morale initialized with default faction due to missing/invalid faction argument.")
	end

	-- Irish units get morale bonus
	if faction == "Irish" or faction:lower():find("celt") then
		baseMorale = baseMorale + IRISH_BASE_MORALE_BONUS
	end

	local unitType = unitModel:GetAttribute("UnitType")

	-- Special units get morale bonuses
	if unitType == "Fianna" or unitType == "Gallowglass" then
		baseMorale = baseMorale + 10
	elseif unitType == "Bard" then
		baseMorale = MAX_MORALE -- Bards never flee
	elseif unitType == "King" or unitType:find("Hero") then
		baseMorale = 95 -- Heroes rarely flee
	end

	UnitMoraleData[unitModel] = {
		current = baseMorale,
		max = MAX_MORALE,
		state = getMoraleState(baseMorale),
		lastUpdate = tick(),
		modifiers = {},
	}

	-- Create morale indicator
	createMoraleIndicator(unitModel)

	MoraleDebug:info("Initialized unit morale", {
		unitType = unitType,
		faction = faction,
		startingMorale = baseMorale,
	})
end

-- Get morale state based on current value
function getMoraleState(morale: number): MoraleState
	if morale < FLEE_THRESHOLD then
		return "Fleeing"
	elseif morale < RALLY_THRESHOLD then
		return "Shaken"
	elseif morale < 60 then
		return "Steady"
	elseif morale < INSPIRED_THRESHOLD then
		return "Confident"
	else
		return "Inspired"
	end
end

-- Create visual morale indicator
function createMoraleIndicator(unitModel: Model)
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MoraleIndicator"
	billboard.Size = UDim2.new(3, 0, 0.5, 0)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 1
	frame.Parent = billboard

	local bar = Instance.new("Frame")
	bar.Name = "MoraleBar"
	bar.Size = UDim2.new(0.75, 0, 1, 0) -- 75% default
	bar.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
	bar.BorderSizePixel = 0
	bar.Parent = frame

	billboard.Parent = humanoid.RootPart or unitModel.PrimaryPart
end

-- Update morale bar visual
local function updateMoraleIndicator(unitModel: Model, moraleData: UnitMorale)
	local billboard = unitModel:FindFirstDescendant("MoraleIndicator")
	if not billboard then
		return
	end

	local bar = billboard:FindFirstChild("MoraleBar", true)
	if not bar or not bar:IsA("Frame") then
		return
	end

	local percentage = moraleData.current / moraleData.max
	bar.Size = UDim2.new(percentage, 0, 1, 0)

	-- Color based on state
	if moraleData.state == "Fleeing" then
		bar.BackgroundColor3 = Color3.fromRGB(255, 50, 50) -- Red
	elseif moraleData.state == "Shaken" then
		bar.BackgroundColor3 = Color3.fromRGB(255, 150, 50) -- Orange
	elseif moraleData.state == "Steady" then
		bar.BackgroundColor3 = Color3.fromRGB(200, 200, 100) -- Yellow
	elseif moraleData.state == "Confident" then
		bar.BackgroundColor3 = Color3.fromRGB(100, 200, 100) -- Green
	else -- Inspired
		bar.BackgroundColor3 = Color3.fromRGB(50, 255, 50) -- Bright green
	end
end

-- Apply morale change to unit
function MoraleManager.modifyMorale(unitModel: Model, amount: number, reason: string)
	local moraleData = UnitMoraleData[unitModel]
	if not moraleData then
		return
	end

	local oldMorale = moraleData.current
	moraleData.current = math.clamp(moraleData.current + amount, MIN_MORALE, MAX_MORALE)

	local oldState = moraleData.state
	moraleData.state = getMoraleState(moraleData.current)

	-- Log significant state changes
	if oldState ~= moraleData.state then
		MoraleDebug:info("Morale state changed", {
			unit = unitModel.Name,
			oldState = oldState,
			newState = moraleData.state,
			reason = reason,
		})

		-- Handle fleeing
		if moraleData.state == "Fleeing" then
			handleFleeing(unitModel)
		elseif oldState == "Fleeing" and moraleData.state ~= "Fleeing" then
			handleRally(unitModel)
		end
	end

	updateMoraleIndicator(unitModel, moraleData)
end

-- Handle fleeing behavior
function handleFleeing(unitModel: Model)
	MoraleDebug:info("Unit fleeing!", { unit = unitModel.Name })

	-- Set fleeing attribute for movement system
	unitModel:SetAttribute("IsFleeing", true)

	-- Visual effect - make unit slightly transparent
	for _, part in ipairs(unitModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0.3
		end
	end

	-- TODO: Integrate with movement system to make unit run away
end

-- Handle rallying from flee
function handleRally(unitModel: Model)
	MoraleDebug:info("Unit rallied!", { unit = unitModel.Name })

	unitModel:SetAttribute("IsFleeing", false)

	-- Restore transparency
	for _, part in ipairs(unitModel:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Transparency = 0
		end
	end
end

-- Check for nearby morale effects
local function checkAuraEffects(unitModel: Model): number
	local totalBonus = 0
	local unitPos = unitModel.PrimaryPart and unitModel.PrimaryPart.Position
	if not unitPos then
		return 0
	end

	-- Check for bards
	for otherModel, otherMorale in pairs(UnitMoraleData) do
		if otherModel ~= unitModel and otherModel.Parent then
			local otherType = otherModel:GetAttribute("UnitType")
			local otherOwner = otherModel:GetAttribute("Owner")
			local unitOwner = unitModel:GetAttribute("Owner")

			if otherOwner == unitOwner then
				local otherPos = otherModel.PrimaryPart and otherModel.PrimaryPart.Position
				if otherPos then
					local distance = (otherPos - unitPos).Magnitude

					-- Bard aura
					if otherType == "Bard" and distance <= BARD_AURA_RANGE then
						totalBonus = totalBonus + BARD_MORALE_BOOST
					end

					-- Hero/Commander aura
					if (otherType == "King" or otherType:find("Hero")) and distance <= HERO_AURA_RANGE then
						totalBonus = totalBonus + HERO_MORALE_BOOST
					end
				end
			end
		end
	end

	return totalBonus
end

-- Calculate combat situation morale effects
function MoraleManager.evaluateCombatSituation(unitModel: Model): number
	local modifier = 0
	local unitPos = unitModel.PrimaryPart and unitModel.PrimaryPart.Position
	if not unitPos then
		return 0
	end

	local unitOwner = unitModel:GetAttribute("Owner")
	local alliesNearby = 0
	local enemiesNearby = 0

	-- Count nearby allies and enemies
	for otherModel, _ in pairs(UnitMoraleData) do
		if otherModel ~= unitModel and otherModel.Parent then
			local otherPos = otherModel.PrimaryPart and otherModel.PrimaryPart.Position
			if otherPos and (otherPos - unitPos).Magnitude < 30 then
				if otherModel:GetAttribute("Owner") == unitOwner then
					alliesNearby = alliesNearby + 1
				else
					enemiesNearby = enemiesNearby + 1
				end
			end
		end
	end

	-- Outnumbered/outnumbering
	if enemiesNearby > alliesNearby + 1 then
		modifier = modifier + FACTORS.OUTNUMBERED
	elseif alliesNearby > enemiesNearby + 1 then
		modifier = modifier + FACTORS.OUTNUMBERING
	end

	-- Formation bonus
	if unitModel:GetAttribute("InFormation") then
		modifier = modifier + FACTORS.IN_FORMATION
	end

	return modifier
end

-- Main morale update loop
local function updateMoraleLoop()
	local currentTime = tick()

	for unitModel, moraleData in pairs(UnitMoraleData) do
		if unitModel and unitModel.Parent then
			local deltaTime = currentTime - moraleData.lastUpdate

			if deltaTime >= 1 then -- Update every second
				-- Check aura effects
				local auraBonus = checkAuraEffects(unitModel)

				-- Apply gradual morale recovery
				local naturalRecovery = 0
				if moraleData.current < BASE_MORALE and moraleData.state ~= "Fleeing" then
					naturalRecovery = 0.5 -- Slowly recover to base
				end

				local totalChange = auraBonus + naturalRecovery

				if totalChange ~= 0 then
					MoraleManager.modifyMorale(unitModel, totalChange * deltaTime, "Passive effects")
				end

				moraleData.lastUpdate = currentTime
			end
		else
			-- Clean up dead units
			UnitMoraleData[unitModel] = nil
		end
	end
end

-- Get current morale
function MoraleManager.getMorale(unitModel: Model): number?
	local moraleData = UnitMoraleData[unitModel]
	return moraleData and moraleData.current
end

-- Get morale state
function MoraleManager.getMoraleState(unitModel: Model): MoraleState?
	local moraleData = UnitMoraleData[unitModel]
	return moraleData and moraleData.state
end

-- Battle cry ability (Irish special)
function MoraleManager.battleCry(sourceUnit: Model, range: number)
	local sourcePos = sourceUnit.PrimaryPart and sourceUnit.PrimaryPart.Position
	if not sourcePos then
		return
	end

	local sourceOwner = sourceUnit:GetAttribute("Owner")

	MoraleDebug:info("Battle cry activated!", {
		source = sourceUnit.Name,
		range = range,
	})

	-- Boost morale of all nearby allies
	for unitModel, moraleData in pairs(UnitMoraleData) do
		if unitModel ~= sourceUnit and unitModel.Parent then
			if unitModel:GetAttribute("Owner") == sourceOwner then
				local unitPos = unitModel.PrimaryPart and unitModel.PrimaryPart.Position
				if unitPos and (unitPos - sourcePos).Magnitude <= range then
					MoraleManager.modifyMorale(unitModel, 15, "Battle Cry")

					-- Visual effect
					local effect = Instance.new("PointLight")
					effect.Color = Color3.fromRGB(255, 215, 0)
					effect.Brightness = 2
					effect.Range = 10
					effect.Parent = unitModel.PrimaryPart

					TweenService:Create(effect, TweenInfo.new(1), {
						Brightness = 0,
						Range = 20,
					}):Play()

					task.wait(1)
					effect:Destroy()
				end
			end
		end
	end
end

-- Initialize morale system
function MoraleManager.init()
	RunService.Heartbeat:Connect(updateMoraleLoop)
	MoraleDebug:info("Morale system initialized")
end

return MoraleManager
