--!strict
-- BattleTicker: Top-right scrolling message ticker banner across all screens.
-- Includes a downward arrow button (▼ / ▲) below it that expands a full scrollable Battle Log history drawer.
-- Supports multi-line wrapping, increased 14px font size, and generous padding for multiple messages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local MedievalCorners = require(script.Parent.Parent.components.MedievalCorners)

export type Props = {
	messages: { { text: string, color: Color3? } }?,
}

local function BattleTicker(props: Props)
	local isDrawerOpen, setIsDrawerOpen = React.useState(false)

	local messages = props.messages or {}
	local latestMsg = messages[#messages]

	local textRef = React.useRef(nil :: TextLabel?)
	local containerRef = React.useRef(nil :: Frame?)

	local currentText = if latestMsg then latestMsg.text else "⚔ Realm is at peace. Stand ready, Sovereign."
	local textColor = if latestMsg and latestMsg.color then latestMsg.color else Theme.Color.TextSecondary

	-- Horizontal marquee scrolling when text exceeds container width
	React.useEffect(function()
		local textLabel = textRef.current
		local container = containerRef.current
		if not textLabel or not container then
			return
		end

		local textWidth = textLabel.AbsoluteSize.X
		local containerWidth = container.AbsoluteSize.X

		if textWidth > containerWidth then
			local overflow = textWidth - containerWidth + 30
			local duration = math.clamp(overflow / 30, 3, 10)

			textLabel.Position = UDim2.fromOffset(0, 0)
			local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true, 1)
			local tween = TweenService:Create(textLabel, tweenInfo, {
				Position = UDim2.fromOffset(-overflow, 0),
			})
			tween:Play()
			return function()
				tween:Cancel()
			end
		else
			textLabel.Position = UDim2.fromOffset(0, 0)
		end
		return nil
	end, { currentText })

	-- Build padded message card elements for expanded drawer with multi-line wrap
	local messageElements: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for i, msg in ipairs(messages) do
		messageElements["MsgCard_" .. i] = React.createElement("Frame", {
			Name = "MsgCard_" .. i,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -6, 0, 0),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),
			TextLabel = React.createElement("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				Text = msg.text,
				TextColor3 = msg.color or Theme.Color.TextPrimary,
				TextSize = 14, -- Increased readable font size
				FontFace = Theme.FontFace.Body,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true, -- Multi-line wrapping support
			}),
		})
	end

	local drawerHeight = 230
	local arrowYOffset = if isDrawerOpen then drawerHeight + 4 else 0

	return React.createElement("Frame", {
		Name = "BattleTicker",
		Size = UDim2.fromOffset(380, 28),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12), -- VERY TOP RIGHT OF SCREEN
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = 0.05,
		ZIndex = 90,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
		Corners = React.createElement(MedievalCorners, { size = 10, color = Theme.Color.Accent, thickness = 1.5 }),

		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),

		-- TICKER TEXT CONTAINER
		TextContainer = React.createElement("Frame", {
			ref = containerRef,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, {
			Label = React.createElement("TextLabel", {
				ref = textRef,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = currentText,
				TextColor3 = textColor,
				TextSize = 13,
				FontFace = Theme.FontFace.Display,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 1,
			}),
		}),

		-- DOWNWARD ARROW BUTTON (Rides down to bottom edge of expanded drawer)
		ExpandArrowBtn = React.createElement("TextButton", {
			Name = "ExpandArrowBtn",
			Size = UDim2.fromOffset(38, 18),
			Position = UDim2.new(0.5, 0, 1, arrowYOffset),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BackgroundTransparency = 0,
			AutoButtonColor = true,
			Text = if isDrawerOpen then "▲" else "▼",
			FontFace = Theme.FontFace.Display,
			TextSize = 12,
			TextColor3 = Theme.Color.Accent,
			TextStrokeTransparency = 1,
			ZIndex = 95,
			[React.Event.Activated] = function()
				setIsDrawerOpen(not isDrawerOpen)
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 0) }),
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
		}),

		-- EXPANDED DOWNWARD BATTLE LOG DRAWER
		LogDrawerFrame = isDrawerOpen and React.createElement("Frame", {
			Name = "LogDrawerFrame",
			Size = UDim2.new(1, 0, 0, drawerHeight),
			Position = UDim2.new(0, 0, 1, 4),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = 0.05,
			ClipsDescendants = true,
			ZIndex = 92,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Corners = React.createElement(MedievalCorners, { size = 14, color = Theme.Color.Accent, thickness = 2 }),

			ContentContainer = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 93,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
				}),

				HeaderTitle = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 22),
					Position = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
					Text = "📜 Realm Log History",
					FontFace = Theme.FontFace.Display,
					TextSize = 14,
					TextColor3 = Theme.Color.Accent,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				LogScroll = React.createElement("ScrollingFrame", {
					Size = UDim2.new(1, 0, 1, -26),
					Position = UDim2.fromOffset(0, 26),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					ScrollBarThickness = 4,
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.fromScale(0, 0),
				}, messageElements),
			}),
		}) or nil,
	})
end

return BattleTicker
