--!strict
-- TutorialModal: Guides players through building required structures (Step 1: Keep placement)
-- Updated to Theme.luau design system.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)
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
		alwaysShow = true,
	},
	{
		buildingType = "Storehouse",
		title = "Build a Storehouse",
		description = "Excellent! Now you need a Storehouse to expand your storage capacity.\n\nThe Storehouse allows you to store more building materials and weapons, which you'll need as your settlement grows. Click 'Build Storehouse' to continue.",
		isRequired = true,
		alwaysShow = false,
	},
	{
		buildingType = "Granary",
		title = "Build a Granary",
		description = "Almost done with the basics! A Granary is essential for storing food.\n\nYour people need food to survive and work. The Granary will keep your food supplies safe and organized. Click 'Build Granary' to complete your tutorial.",
		isRequired = true,
		alwaysShow = false,
	},
}

local TutorialModal = React.Component:extend("TutorialModal")

function TutorialModal:init()
	self.hasTriggeredBuild = false
end

function TutorialModal:didMount()
	local currentStep = TUTORIAL_STEPS[self.props.currentStep]
	if currentStep and currentStep.autoTrigger and not self.hasTriggeredBuild then
		self.hasTriggeredBuild = true
		if self.props.onBuildRequested then
			task.wait(0.5)
			self.props.onBuildRequested(currentStep.buildingType, true)
		end
	end
end

function TutorialModal:didUpdate(prevProps)
	if prevProps.currentStep ~= self.props.currentStep then
		self.hasTriggeredBuild = false
		local currentStep = TUTORIAL_STEPS[self.props.currentStep]
		if currentStep and currentStep.autoTrigger then
			self.hasTriggeredBuild = true
			if self.props.onBuildRequested then
				task.wait(0.5)
				self.props.onBuildRequested(currentStep.buildingType, true)
			end
		end
	end
end

function TutorialModal:render()
	if not self.props.visible then
		return nil
	end

	local currentStep = TUTORIAL_STEPS[self.props.currentStep]
	if not currentStep then
		return nil
	end

	return React.createElement(Modal, {
		visible = true,
		title = currentStep.title,
		onClose = nil, -- No close button for required tutorial
		size = self.props.size or UDim2.fromOffset(460, 320),
	}, {
		Content = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 12),
			}),

			Description = React.createElement("TextLabel", {
				Name = "Description",
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 130),
				BackgroundTransparency = 1,
				Text = currentStep.description,
				FontFace = Theme.FontFace.Body,
				TextSize = Theme.TextSize.Body,
				TextColor3 = Theme.Color.TextPrimary,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),

			ProgressInfo = React.createElement("TextLabel", {
				Name = "ProgressInfo",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = string.format("Step %d of %d", self.props.currentStep, #TUTORIAL_STEPS),
				FontFace = Theme.FontFace.Display,
				TextSize = Theme.TextSize.Caption,
				TextColor3 = Theme.Color.Accent,
			}),

			BuildButton = not currentStep.autoTrigger and React.createElement("TextButton", {
				Name = "BuildButton",
				LayoutOrder = 3,
				Size = UDim2.fromOffset(240, 40),
				BackgroundColor3 = Theme.Color.Accent,
				AutoButtonColor = true,
				Text = "🏰 Build " .. currentStep.buildingType:gsub("_", " "),
				FontFace = Theme.FontFace.Display,
				TextSize = Theme.TextSize.Header,
				TextColor3 = Theme.Color.OnAccent,
				[React.Event.Activated] = function()
					if self.props.onBuildRequested then
						self.props.onBuildRequested(currentStep.buildingType, false)
					end
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
				Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			}) or nil,
		}),
	})
end

return TutorialModal
