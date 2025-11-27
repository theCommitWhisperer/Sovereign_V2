--!strict
-- CameraAnimator: Provides smooth camera transitions and animations
-- Handles lerping between camera states for polish

local TweenService = game:GetService("TweenService")

export type AnimationConfig = {
	Duration: number,
	EasingStyle: Enum.EasingStyle,
	EasingDirection: Enum.EasingDirection,
}

local DEFAULT_ANIMATION: AnimationConfig = {
	Duration = 0.5,
	EasingStyle = Enum.EasingStyle.Quad,
	EasingDirection = Enum.EasingDirection.Out,
}

local CameraAnimator = {}
CameraAnimator.__index = CameraAnimator

function CameraAnimator.new(cameraRig)
	local self = setmetatable({}, CameraAnimator)

	self.cameraRig = cameraRig
	self.enabled = true

	-- Smooth damping for continuous movement
	self.useSmoothDamping = true
	self.dampingFactor = 0.15 -- Lower = smoother but slower response

	-- Inertia/momentum for input
	self.useInertia = true
	self.inertiaDecay = 0.9 -- How quickly momentum decays
	self.currentVelocity = Vector3.zero
	self.currentRotationVelocity = Vector2.zero

	-- Active tweens
	self.activeTweens = {}

	return self
end

function CameraAnimator:SetEnabled(enabled: boolean)
	self.enabled = enabled

	-- Cancel active tweens if disabled
	if not enabled then
		for _, tween in ipairs(self.activeTweens) do
			tween:Cancel()
		end
		self.activeTweens = {}
	end
end

function CameraAnimator:SetSmoothDamping(enabled: boolean, dampingFactor: number?)
	self.useSmoothDamping = enabled
	if dampingFactor then
		self.dampingFactor = math.clamp(dampingFactor, 0.01, 0.99)
	end
end

function CameraAnimator:SetInertia(enabled: boolean, decay: number?)
	self.useInertia = enabled
	if decay then
		self.inertiaDecay = math.clamp(decay, 0.5, 0.99)
	end
end

function CameraAnimator:ApplyInertia(deltaTime: number)
	if not self.enabled or not self.useInertia then
		return
	end

	-- Apply momentum decay to movement
	if self.currentVelocity.Magnitude > 0.01 then
		self.cameraRig:Move(self.currentVelocity, deltaTime)
		self.currentVelocity = self.currentVelocity * self.inertiaDecay
	else
		self.currentVelocity = Vector3.zero
	end

	-- Apply momentum decay to rotation
	if self.currentRotationVelocity.Magnitude > 0.01 then
		self.cameraRig:Rotate(self.currentRotationVelocity.X * deltaTime, self.currentRotationVelocity.Y * deltaTime)
		self.currentRotationVelocity = self.currentRotationVelocity * self.inertiaDecay
	else
		self.currentRotationVelocity = Vector2.zero
	end
end

function CameraAnimator:AddMovementVelocity(direction: Vector3, speed: number)
	if not self.useInertia then
		return
	end
	self.currentVelocity = direction.Unit * speed
end

function CameraAnimator:AddRotationVelocity(deltaX: number, deltaY: number)
	if not self.useInertia then
		return
	end
	self.currentRotationVelocity = Vector2.new(deltaX, deltaY)
end

function CameraAnimator:AnimateFocusOn(targetPosition: Vector3, targetDistance: number?, config: AnimationConfig?)
	local animConfig = config or DEFAULT_ANIMATION

	-- Cancel existing focus animations
	self:CancelAnimations("Focus")

	-- Create animation data
	local startFocal = self.cameraRig:GetFocalPoint()
	local startDistance = self.cameraRig:GetDistance()
	local endDistance = targetDistance or startDistance

	local animData = {
		Type = "Focus",
		StartTime = tick(),
		Duration = animConfig.Duration,
		EasingStyle = animConfig.EasingStyle,
		EasingDirection = animConfig.EasingDirection,
		StartFocal = startFocal,
		EndFocal = targetPosition,
		StartDistance = startDistance,
		EndDistance = endDistance,
	}

	table.insert(self.activeTweens, animData)
end

function CameraAnimator:AnimateToRotation(targetYaw: number, targetPitch: number, config: AnimationConfig?)
	local animConfig = config or DEFAULT_ANIMATION

	-- Cancel existing rotation animations
	self:CancelAnimations("Rotation")

	-- Create animation data
	local startYaw, startPitch = self.cameraRig:GetCameraRotation()

	local animData = {
		Type = "Rotation",
		StartTime = tick(),
		Duration = animConfig.Duration,
		EasingStyle = animConfig.EasingStyle,
		EasingDirection = animConfig.EasingDirection,
		StartYaw = startYaw,
		EndYaw = targetYaw,
		StartPitch = startPitch,
		EndPitch = targetPitch,
	}

	table.insert(self.activeTweens, animData)
end

function CameraAnimator:Update(deltaTime: number)
	if not self.enabled then
		return
	end

	-- Apply inertia
	self:ApplyInertia(deltaTime)

	-- Update active animations
	local currentTime = tick()
	local completedAnimations = {}

	for i, animData in ipairs(self.activeTweens) do
		local elapsed = currentTime - animData.StartTime
		local alpha = math.clamp(elapsed / animData.Duration, 0, 1)

		-- Apply easing
		local easedAlpha = TweenService:GetValue(alpha, animData.EasingStyle, animData.EasingDirection)

		if animData.Type == "Focus" then
			-- Lerp focal point and distance
			local lerpedFocal = animData.StartFocal:Lerp(animData.EndFocal, easedAlpha)
			local lerpedDistance = animData.StartDistance + (animData.EndDistance - animData.StartDistance) * easedAlpha

			self.cameraRig:SetFocalPoint(lerpedFocal)
			self.cameraRig:SetDistance(lerpedDistance)
		elseif animData.Type == "Rotation" then
			-- Lerp yaw and pitch
			local lerpedYaw = animData.StartYaw + (animData.EndYaw - animData.StartYaw) * easedAlpha
			local lerpedPitch = animData.StartPitch + (animData.EndPitch - animData.StartPitch) * easedAlpha

			self.cameraRig:SetCameraRotation(lerpedYaw, lerpedPitch)
		end

		-- Mark completed animations
		if alpha >= 1 then
			table.insert(completedAnimations, i)
		end
	end

	-- Remove completed animations (iterate backwards to maintain indices)
	for i = #completedAnimations, 1, -1 do
		table.remove(self.activeTweens, completedAnimations[i])
	end
end

function CameraAnimator:CancelAnimations(animType: string?)
	if animType then
		-- Cancel specific animation type
		for i = #self.activeTweens, 1, -1 do
			if self.activeTweens[i].Type == animType then
				table.remove(self.activeTweens, i)
			end
		end
	else
		-- Cancel all animations
		self.activeTweens = {}
	end

	-- Reset velocities when canceling
	self.currentVelocity = Vector3.zero
	self.currentRotationVelocity = Vector2.zero
end

function CameraAnimator:IsAnimating(): boolean
	return #self.activeTweens > 0
end

function CameraAnimator:GetDampingFactor(): number
	return self.dampingFactor
end

function CameraAnimator:Destroy()
	self:CancelAnimations()
end

return CameraAnimator
