-- TutorialModal: Guides players through building required structures
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)
local Modal = require(script.Parent.Modal)

-- Tutorial steps with required buildings
-- Step 1 (Keep) is ALWAYS shown regardless of tutorial setting
-- Steps 2+ are only shown if tutorial is enabled
local TUTORIAL_STEPS = {
	{
		buildingType = "Keep",
		title = "Build Your Keep",
		description = "Welcome to Sovereign! Every settlement needs a Keep - the heart of your realm.\n\nThe Keep serves as your main building where you can train peasants and store resources.\n\nClick the button below to begin placing your Keep!",
		isRequired = true,
		alwaysShow = true, -- Always show this step, even if tutorial is disabled
	},
	{
		buildingType = "Storehouse",
		title = "Build a Storehouse",
		description = "Excellent! Now you need a Storehouse to expand your storage capacity.\n\nThe Storehouse allows you to store more building materials and weapons, which you'll need as your settlement grows. Click 'Build Storehouse' to continue.",
		isRequired = true,
		alwaysShow = false, -- Only show if tutorial is enabled
	},
	{
		buildingType = "Granary",
		title = "Build a Granary",
		description = "Almost done with the basics! A Granary is essential for storing food.\n\nYour people need food to survive and work. The Granary will keep your food supplies safe and organized. Click 'Build Granary' to complete your tutorial.",
		isRequired = true,
		alwaysShow = false, -- Only show if tutorial is enabled
	},
}

local TutorialModal = React.Component:extend("TutorialModal")

function TutorialModal:init()
	print("[TutorialModal] init called")
	self.hasTriggeredBuild = false
end

function TutorialModal:didMount()
	print("[TutorialModal] didMount called", {
		currentStep = self.props.currentStep,
		hasAutoTrigger = TUTORIAL_STEPS[self.props.currentStep] and TUTORIAL_STEPS[self.props.currentStep].autoTrigger,
		hasTriggeredBuild = self.hasTriggeredBuild,
	})

	-- Auto-trigger building placement for steps that have autoTrigger=true
	local currentStep = TUTORIAL_STEPS[self.props.currentStep]
	if currentStep and currentStep.autoTrigger and not self.hasTriggeredBuild then
		print("[TutorialModal] Auto-triggering build for", currentStep.buildingType)
		self.hasTriggeredBuild = true
		if self.props.onBuildRequested then
			-- Small delay to let the modal render first
			task.wait(0.5)
			print("[TutorialModal] Calling onBuildRequested for", currentStep.buildingType)
			self.props.onBuildRequested(currentStep.buildingType, true) -- Pass true for isAutoTriggered
		end
	end
end

function TutorialModal:didUpdate(prevProps)
	-- Reset trigger flag when step changes
	if prevProps.currentStep ~= self.props.currentStep then
		self.hasTriggeredBuild = false
		-- Auto-trigger for new step if needed
		local currentStep = TUTORIAL_STEPS[self.props.currentStep]
		if currentStep and currentStep.autoTrigger then
			self.hasTriggeredBuild = true
			if self.props.onBuildRequested then
				task.wait(0.5)
				self.props.onBuildRequested(currentStep.buildingType, true) -- Pass true for isAutoTriggered
			end
		end
	end
end

function TutorialModal:render()
	print("[TutorialModal] render called", {
		visible = self.props.visible,
		currentStep = self.props.currentStep,
		hasCurrentStep = TUTORIAL_STEPS[self.props.currentStep] ~= nil,
	})

	if not self.props.visible then
		print("[TutorialModal] Not visible, returning nil")
		return nil
	end

	local currentStep = TUTORIAL_STEPS[self.props.currentStep]
	if not currentStep then
		print("[TutorialModal] No current step found, returning nil")
		return nil
	end

	print("[TutorialModal] Rendering modal for step:", currentStep.title)

	return React.createElement(Modal, {
		visible = true,
		title = currentStep.title,
		onClose = nil, -- No close button for required tutorial
		size = UDim2.fromScale(0.4, 0.5), -- Smaller modal
	}, {
		Content = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 1, -80),
			BackgroundTransparency = 1,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 20),
				PaddingBottom = UDim.new(0, 20),
				PaddingLeft = UDim.new(0, 20),
				PaddingRight = UDim.new(0, 20),
			}),

			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 15),
			}),

			Description = React.createElement("TextLabel", {
				Name = "Description",
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 120),
				BackgroundTransparency = 1,
				Text = currentStep.description,
				FontFace = UIConfig.Font.Default,
				TextSize = 18,
				TextColor3 = Color3.fromRGB(230, 230, 230),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),

			ProgressInfo = React.createElement("TextLabel", {
				Name = "ProgressInfo",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 25),
				BackgroundTransparency = 1,
				Text = string.format("Step %d of %d", self.props.currentStep, #TUTORIAL_STEPS),
				FontFace = UIConfig.Font.Title,
				TextSize = 16,
				TextColor3 = UIConfig.HUD.StatLabelColor,
			}),

			-- Only show build button if not auto-triggered
			BuildButton = not currentStep.autoTrigger and React.createElement("TextButton", {
				Name = "BuildButton",
				LayoutOrder = 3,
				Size = UDim2.new(0, 250, 0, 50),
				BackgroundColor3 = UIConfig.HUD.AccentGold,
				BorderSizePixel = 0,
				Text = "Build " .. currentStep.buildingType:gsub("_", " "),
				FontFace = UIConfig.Font.Title,
				TextSize = 22,
				TextColor3 = Color3.fromRGB(0, 0, 0),
				[React.Event.MouseButton1Click] = function()
					if self.props.onBuildRequested then
						self.props.onBuildRequested(currentStep.buildingType, false) -- Pass false for manual click
					end
				end,
			}, {
				Border = React.createElement("UIStroke", {
					Color = Color3.fromRGB(139, 105, 20), -- Dark goldenrod
					Thickness = 2,
				}),

				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			}) or nil,
		}),
	})
end

return TutorialModal
