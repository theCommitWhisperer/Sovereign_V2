-- Shown to the player upon winning a match.
-- Receives props.postGameData = { victoryType: string?, description: string?, stats: table? }
-- (fired from the server as GameEvent "Victory" — EliminationManager conquest
-- wins and VictoryConditionManager economic wins both land here via App.luau).
-- stats = { unitsTrained, unitsLost, kills, buildingsBuilt, gloryLifetime, matchDuration }
-- (AchievementManager.getMatchSnapshot). "Spectate" hides the panel — the RTS
-- camera stays live server-side until the player chooses Return to Menu.
local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)

local VictoryScreen = React.Component:extend("VictoryScreen")

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
			TextColor3 = Color3.fromRGB(199, 186, 160),
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
			TextColor3 = valueColor or Color3.fromRGB(230, 220, 200),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 53,
		}),
	})
end

function VictoryScreen:init()
	self:setState({
		spectating = false, -- panel hidden, player watches the world with the RTS camera
	})
end

function VictoryScreen:leaveGame()
	local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local gameEvent = remotes and remotes:FindFirstChild("GameEvent")
	if gameEvent and gameEvent:IsA("RemoteEvent") then
		-- Server tears the session down and fires "GameLeft" (App → main menu)
		gameEvent:FireServer("LeaveGame")
	elseif self.props.navigate then
		self.props.navigate("mainMenu")
	end
end

function VictoryScreen:render()
	local data = self.props.postGameData or {}
	local victoryType = data.victoryType or "Victory"
	local description = data.description or "Your banner flies over the land."
	local stats = data.stats

	-- Spectate mode: just a small pill to bring the results back
	if self.state.spectating then
		return React.createElement("Frame", {
			Name = "VictoryScreen",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 50,
		}, {
			ResultsButton = React.createElement(Button, {
				Text = "🏆 Results",
				Size = UDim2.fromOffset(150, 44),
				Position = UDim2.new(1, -16, 0, 16),
				AnchorPoint = Vector2.new(1, 0),
				TextSize = 20,
				BackgroundColor3 = Color3.fromRGB(120, 96, 48),
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
		Name = "VictoryScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(15, 25, 12),
		BackgroundTransparency = 0.25,
		ZIndex = 50,
	}, {
		Panel = React.createElement("Frame", {
			Size = UDim2.fromOffset(560, stats and 500 or 340),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(46, 38, 30),
			BorderSizePixel = 0,
			ZIndex = 51,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(214, 178, 94), -- gold
				Thickness = 3,
			}),
			Title = React.createElement("TextLabel", {
				Text = "VICTORY",
				Size = UDim2.new(1, 0, 0, 90),
				Position = UDim2.fromOffset(0, 24),
				BackgroundTransparency = 1,
				FontFace = UIConfig.Font.Title,
				TextSize = 64,
				TextColor3 = Color3.fromRGB(214, 178, 94),
				ZIndex = 52,
			}),
			Subtitle = React.createElement("TextLabel", {
				Text = victoryType,
				Size = UDim2.new(1, -60, 0, 30),
				Position = UDim2.new(0, 30, 0, 120),
				BackgroundTransparency = 1,
				FontFace = UIConfig.getFont(nil, UIConfig.Font.Title),
				TextSize = 28,
				TextColor3 = Color3.fromRGB(230, 220, 200),
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
				TextColor3 = Color3.fromRGB(199, 186, 160),
				ZIndex = 52,
			}),
			Stats = statsRows,
			LeaveButton = React.createElement(Button, {
				Text = "Return to Menu",
				Size = UDim2.fromOffset(240, 54),
				Position = UDim2.new(0.5, -128, 1, -34),
				AnchorPoint = Vector2.new(0.5, 1),
				TextSize = 24,
				BackgroundColor3 = Color3.fromRGB(120, 96, 48),
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
				BackgroundColor3 = Color3.fromRGB(70, 84, 60),
				OnClick = function()
					-- Keep the RTS camera; the server session stays alive until LeaveGame
					self:setState({ spectating = true })
				end,
			}),
		}),
	})
end

return VictoryScreen
