--[[
	Deletion Effects
	Creates visual and audio feedback when buildings are deleted
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameEvent = RemoteEvents:WaitForChild("GameEvent")

-- Play deletion sound
local function playDeletionSound()
	-- Try to find sound in ReplicatedStorage/Assets/Sounds
	local soundsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if soundsFolder then
		soundsFolder = soundsFolder:FindFirstChild("Sounds")
		if soundsFolder then
			local sound = soundsFolder:FindFirstChild("DeleteBuilding")
			if sound and sound:IsA("Sound") then
				sound:Play()
				return
			end
		end
	end

	-- Fallback: create a simple sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = 0.5
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

-- Create particle effect at position
local function createDeletionEffect(position, buildingSize)
	local size = buildingSize or Vector3.new(5, 5, 5)

	-- Create temporary part for particles
	local particle = Instance.new("Part")
	particle.Size = Vector3.new(1, 1, 1)
	particle.Position = position
	particle.Anchored = true
	particle.CanCollide = false
	particle.Transparency = 1
	particle.Parent = workspace

	-- Smoke effect
	local smoke = Instance.new("ParticleEmitter")
	smoke.Parent = particle
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(100, 80, 60))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size.X * 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	smoke.Lifetime = NumberRange.new(1, 2)
	smoke.Rate = 50
	smoke.Speed = NumberRange.new(5, 10)
	smoke.SpreadAngle = Vector2.new(30, 30)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-50, 50)
	smoke.Enabled = true

	-- Dust particles
	local dust = Instance.new("ParticleEmitter")
	dust.Parent = particle
	dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 120, 90))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	dust.Lifetime = NumberRange.new(0.5, 1.5)
	dust.Rate = 100
	dust.Speed = NumberRange.new(10, 20)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Enabled = true

	-- Flash effect
	local flash = Instance.new("PointLight")
	flash.Parent = particle
	flash.Brightness = 5
	flash.Range = size.X * 2
	flash.Color = Color3.fromRGB(255, 150, 50)

	-- Tween flash out
	local flashTween = TweenService:Create(
		flash,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }
	)
	flashTween:Play()

	-- Disable emitters after short burst
	task.delay(0.3, function()
		smoke.Enabled = false
		dust.Enabled = false
	end)

	-- Cleanup after particles finish
	task.delay(3, function()
		particle:Destroy()
	end)

	-- Play sound
	playDeletionSound()
end

-- Listen for building deletion events
GameEvent.OnClientEvent:Connect(function(action, data)
	if action == "BuildingDeleted" and data.position then
		createDeletionEffect(data.position, data.size)
	elseif action == "BuildingRestored" then
		-- Play restoration sound (positive feedback)
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxasset://sounds/switch.wav"
		sound.Volume = 0.6
		sound.Parent = SoundService
		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end
end)

-- print("[DeletionEffects] Loaded")
