--!strict
-- ErrorBoundary: Catches React errors and displays fallback UI instead of crashing
local React = require(game.ReplicatedStorage.Packages.react)

local ErrorBoundary = React.Component:extend("ErrorBoundary")

function ErrorBoundary:init()
	self:setState({
		hasError = false,
		errorMessage = nil,
	})
end

function ErrorBoundary:getDerivedStateFromError(error: any)
	return {
		hasError = true,
		errorMessage = tostring(error),
	}
end

function ErrorBoundary:componentDidCatch(error: any, errorInfo: any)
	-- Log the error for debugging
	warn("🔴 [ErrorBoundary] Caught error:", error)
	if errorInfo and errorInfo.componentStack then
		warn("Component stack:", errorInfo.componentStack)
	end
end

function ErrorBoundary:render()
	if self.state.hasError then
		-- Show fallback UI instead of crashing
		return React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(40, 20, 20),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		}, {
			ErrorText = React.createElement("TextLabel", {
				Size = UDim2.fromScale(0.8, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = `⚠️ UI Error\n\n{self.state.errorMessage or "Unknown error"}\n\nCheck the console for details.`,
				TextColor3 = Color3.fromRGB(255, 200, 200),
				TextSize = 18,
				Font = Enum.Font.GothamBold,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
			}),
		})
	end

	-- Normal rendering - pass through to children
	return self.props.children
end

return ErrorBoundary
