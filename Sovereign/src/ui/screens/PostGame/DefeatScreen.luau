-- Shown to the player upon losing a match.
-- Receives props.postGameData = { lossReason: string?, description: string?, stats: table? }
-- (fired from the server as GameEvent "Defeat" — EliminationManager Direct
-- Slay / Keep Capture and VictoryConditionManager economic losses).
-- stats = { unitsTrained, unitsLost, kills, buildingsBuilt, gloryLifetime, matchDuration }
-- (AchievementManager.getMatchSnapshot). "Spectate" hides the panel — an
-- eliminated player keeps the RTS camera (GameState "Eliminated" never kicks
-- them); Return to Menu is the only path that tears the session down.
local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)

local DefeatScreen = React.Component:extend("DefeatScreen")

local REASON_TITLES = {
	LordSlain = "Your Lord Has Fallen",
	KeepCaptured = "Your Keep Was Captured",
	KeepDestroyed = "Your Keep Lies in Ruins",
}

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- One "label ........ value" stats row
local function statRow(label: string, value: string, order: number, valueColor: Color3?)
	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		ZIndex = 52,
	}, {
		Label = React.createElement("TextLabel", {
			Size = UDim2.new(0.6, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = label,
			FontFace = UIConfig.Font.Default,
			TextSize = 18,
			TextColor3 = Color3.fromRGB(190, 170, 160),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 53,
		}),
		Value = React.createElement("TextLabel", {
			Size = UDim2.new(0.4, 0, 1, 0),
			Position = UDim2.fromScale(0.6, 0),
			BackgroundTransparency = 1,
			Text = value,
			FontFace = UIConfig.Font.Title,
			TextSize = 18,
			TextColor3 = valueColor or Color3.fromRGB(220, 200, 190),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 53,
		}),
	})
end

function DefeatScreen:init()
	self:setState({
		spectating = false, -- panel hidden, defeated player watches the match play out
	})
end

function DefeatScreen:leaveGame()
	local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local gameEvent = remotes and remotes:FindFirstChild("GameEvent")
	if gameEvent and gameEvent:IsA("RemoteEvent") then
		gameEvent:FireServer("LeaveGame")
	elseif self.props.navigate then
		self.props.navigate("mainMenu")
	end
end

function DefeatScreen:render()
	local data = self.props.postGameData or {}
	local reason = data.lossReason or "Defeat"
	local subtitle = REASON_TITLES[reason] or reason
	local description = data.description or "Your kingdom has fallen."
	local stats = data.stats

	-- Spectate mode: just a small pill to bring the results back
	if self.state.spectating then
		return React.createElement("Frame", {
			Name = "DefeatScreen",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 50,
		}, {
			ResultsButton = React.createElement(Button, {
				Text = "💀 Results",
				Size = UDim2.fromOffset(150, 44),
				Position = UDim2.new(1, -16, 0, 16),
				AnchorPoint = Vector2.new(1, 0),
				TextSize = 20,
				BackgroundColor3 = Color3.fromRGB(96, 48, 44),
				OnClick = function()
					self:setState({ spectating = false })
				end,
			}),
		})
	end

	local statsRows = nil
	if stats then
		statsRows = React.createElement("Frame", {
			Size = UDim2.new(1, -80, 0, 160),
			Position = UDim2.new(0, 40, 0, 236),
			BackgroundTransparency = 1,
			ZIndex = 52,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 2),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Duration = statRow("⏱️ Match Duration", formatDuration(stats.matchDuration or 0), 1),
			Trained = statRow("⚔️ Units Trained", tostring(stats.unitsTrained or 0), 2),
			Lost = statRow("💀 Units Lost", tostring(stats.unitsLost or 0), 3),
			Kills = statRow("🗡️ Enemies Slain", tostring(stats.kills or 0), 4),
			Buildings = statRow("🏰 Buildings Raised", tostring(stats.buildingsBuilt or 0), 5),
			Glory = statRow("🏆 Glory Earned", tostring(stats.gloryLifetime or 0), 6, Color3.fromRGB(214, 178, 94)),
		})
	end

	return React.createElement("Frame", {
		Name = "DefeatScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 8, 8),
		BackgroundTransparency = 0.2,
		ZIndex = 50,
	}, {
		Panel = React.createElement("Frame", {
			Size = UDim2.fromOffset(560, stats and 500 or 340),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(40, 28, 28),
			BorderSizePixel = 0,
			ZIndex = 51,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(140, 46, 40), -- dried blood red
				Thickness = 3,
			}),
			Title = React.createElement("TextLabel", {
				Text = "DEFEAT",
				Size = UDim2.new(1, 0, 0, 90),
				Position = UDim2.fromOffset(0, 24),
				BackgroundTransparency = 1,
				FontFace = UIConfig.Font.Title,
				TextSize = 64,
				TextColor3 = Color3.fromRGB(190, 70, 60),
				ZIndex = 52,
			}),
			Subtitle = React.createElement("TextLabel", {
				Text = subtitle,
				Size = UDim2.new(1, -60, 0, 30),
				Position = UDim2.new(0, 30, 0, 120),
				BackgroundTransparency = 1,
				FontFace = UIConfig.getFont(nil, UIConfig.Font.Title),
				TextSize = 28,
				TextColor3 = Color3.fromRGB(220, 200, 190),
				ZIndex = 52,
			}),
			Description = React.createElement("TextLabel", {
				Text = description,
				Size = UDim2.new(1, -60, 0, 70),
				Position = UDim2.new(0, 30, 0, 158),
				BackgroundTransparency = 1,
				FontFace = UIConfig.getFont(nil, UIConfig.Font.Title),
				TextSize = 20,
				TextWrapped = true,
				TextColor3 = Color3.fromRGB(190, 170, 160),
				ZIndex = 52,
			}),
			Stats = statsRows,
			LeaveButton = React.createElement(Button, {
				Text = "Return to Menu",
				Size = UDim2.fromOffset(240, 54),
				Position = UDim2.new(0.5, -128, 1, -34),
				AnchorPoint = Vector2.new(0.5, 1),
				TextSize = 24,
				BackgroundColor3 = Color3.fromRGB(96, 48, 44),
				OnClick = function()
					self:leaveGame()
				end,
			}),
			SpectateButton = React.createElement(Button, {
				Text = "👁 Spectate",
				Size = UDim2.fromOffset(200, 54),
				Position = UDim2.new(0.5, 102, 1, -34),
				AnchorPoint = Vector2.new(0.5, 1),
				TextSize = 24,
				BackgroundColor3 = Color3.fromRGB(70, 60, 56),
				OnClick = function()
					-- Eliminated players keep the RTS camera; server never force-leaves
					self:setState({ spectating = true })
				end,
			}),
		}),
	})
end

return DefeatScreen
