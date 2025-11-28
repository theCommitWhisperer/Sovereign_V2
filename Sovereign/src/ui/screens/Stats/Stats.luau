--!strict
-- Redesigned Stats modal for displaying kingdom statistics
local React = require(game.ReplicatedStorage.Packages.react)
local Modal = require(script.Parent.Parent.Parent.components.Modal)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local Stats = React.Component:extend("Stats")

export type Props = {
	visible: boolean,
	onClose: () -> (),
	stats: any?,
	population: number?,
	armySize: number?,
	honor: number?,
	glory: number?,
	happiness: number?,
	economySnapshot: any?,
}

-- Helper function to get health color based on value
local function getHealthColor(health: number): Color3
	if health >= 70 then
		return Color3.fromRGB(76, 175, 80) -- Green
	elseif health >= 40 then
		return Color3.fromRGB(255, 193, 7) -- Yellow
	else
		return Color3.fromRGB(244, 67, 54) -- Red
	end
end

-- Helper function to get season icon
local function getSeasonIcon(season: string?): string
	if season == "Spring" then
		return "🌸"
	elseif season == "Summer" then
		return "☀️"
	elseif season == "Autumn" then
		return "🍂"
	elseif season == "Winter" then
		return "❄️"
	end
	return "🌸"
end

-- Helper function to get weather icon
local function getWeatherIcon(weather: string?): string
	if weather == "Clear" then
		return "☀️"
	elseif weather == "Rain" then
		return "🌧️"
	elseif weather == "Storm" then
		return "⛈️"
	elseif weather == "Drought" then
		return "🌵"
	end
	return "☀️"
end

-- Create a large, prominent stat card
function Stats:createLargeStatCard(icon: string, label: string, value: any, color: Color3?, layoutOrder: number)
	return React.createElement("Frame", {
		Size = UDim2.new(0.32, -7, 0, 120),
		BackgroundColor3 = Color3.fromRGB(50, 50, 55),
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
		Stroke = React.createElement("UIStroke", {
			Color = color or UIConfig.HUD.UtilityButtonBorder,
			Thickness = 2,
			Transparency = 0.6,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 15),
			PaddingBottom = UDim.new(0, 15),
			PaddingLeft = UDim.new(0, 15),
			PaddingRight = UDim.new(0, 15),
		}),

		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),

		Icon = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 45),
			BackgroundTransparency = 1,
			Text = icon,
			Font = Enum.Font.GothamBold,
			TextSize = 42,
			TextColor3 = color or Color3.fromRGB(255, 255, 255),
		}),

		Value = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = tostring(value),
			Font = Enum.Font.GothamBold,
			TextSize = 32,
			TextColor3 = Color3.fromRGB(255, 255, 255),
		}),

		Label = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = label,
			Font = Enum.Font.Gotham,
			TextSize = 15,
			TextColor3 = Color3.fromRGB(180, 180, 180),
		}),
	})
end

-- Create economy stat row with icon, label, and value
function Stats:createEconomyStatRow(icon: string, label: string, value: string, layoutOrder: number)
	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 45),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 15),
		}),

		Icon = React.createElement("TextLabel", {
			Size = UDim2.new(0, 35, 0, 35),
			BackgroundTransparency = 1,
			Text = icon,
			Font = Enum.Font.GothamBold,
			TextSize = 28,
			TextColor3 = Color3.fromRGB(255, 255, 255),
		}),

		Label = React.createElement("TextLabel", {
			Size = UDim2.new(0.5, -50, 1, 0),
			BackgroundTransparency = 1,
			Text = label,
			Font = Enum.Font.Gotham,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		Value = React.createElement("TextLabel", {
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = value,
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextColor3 = UIConfig.HUD.CategoryButtonSelected,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

-- Create health bar indicator
function Stats:createHealthBar(icon: string, label: string, value: number, maxValue: number, layoutOrder: number)
	local percentage = math.clamp(value / maxValue * 100, 0, 100)

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 8),
		}),

		-- Header row
		HeaderRow = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 25),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
			}),

			Icon = React.createElement("TextLabel", {
				Size = UDim2.new(0, 25, 0, 25),
				BackgroundTransparency = 1,
				Text = icon,
				Font = Enum.Font.GothamBold,
				TextSize = 22,
			}),

			Label = React.createElement("TextLabel", {
				Size = UDim2.new(0.6, -35, 1, 0),
				BackgroundTransparency = 1,
				Text = label,
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(220, 220, 220),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			Value = React.createElement("TextLabel", {
				Size = UDim2.new(0.4, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = `{value} / {maxValue}`,
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(220, 220, 220),
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),

		-- Progress bar
		BarBackground = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = Color3.fromRGB(35, 35, 40),
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),

			BarFill = React.createElement("Frame", {
				Size = UDim2.fromScale(percentage / 100, 1),
				BackgroundColor3 = getHealthColor(percentage),
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
			}),

			PercentageLabel = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = `{math.floor(percentage)}%`,
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				ZIndex = 2,
			}),
		}),
	})
end

function Stats:render()
	local snapshot = self.props.economySnapshot or {}

	return React.createElement(Modal, {
		title = "🏰 Kingdom Statistics",
		visible = self.props.visible,
		onClose = self.props.onClose,
		size = UDim2.new(0, 700, 0, 750),
	}, {
		Container = React.createElement("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = UIConfig.HUD.CategoryButtonSelected,
			CanvasSize = UDim2.fromOffset(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 20),
				PaddingBottom = UDim.new(0, 30),
				PaddingLeft = UDim.new(0, 25),
				PaddingRight = UDim.new(0, 25),
			}),

			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 30),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			-- TOP STATS (Population, Happiness, Glory)
			TopStats = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 120),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 10),
				}),

				PopCard = self:createLargeStatCard(
					"👥",
					"POPULATION",
					self.props.population or 0,
					Color3.fromRGB(100, 181, 246),
					1
				),
				HappinessCard = self:createLargeStatCard(
					"😊",
					"HAPPINESS",
					(self.props.happiness or 50) .. "%",
					Color3.fromRGB(255, 193, 7),
					2
				),
				GloryCard = self:createLargeStatCard(
					"⭐",
					"GLORY",
					self.props.glory or 0,
					Color3.fromRGB(255, 152, 0),
					3
				),
			}),

			-- DIVIDER
			Divider1 = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 2),
				BackgroundColor3 = Color3.fromRGB(70, 70, 75),
				BorderSizePixel = 0,
				LayoutOrder = 2,
			}),

			-- MILITARY SECTION
			MilitarySection = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 3,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 15),
				}),

				Header = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 35),
					BackgroundTransparency = 1,
					Text = "⚔️ MILITARY",
					Font = Enum.Font.GothamBold,
					TextSize = 26,
					TextColor3 = UIConfig.HUD.CategoryButtonSelected,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				Panel = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 0),
					BackgroundColor3 = Color3.fromRGB(45, 45, 50),
					BorderSizePixel = 0,
					AutomaticSize = Enum.AutomaticSize.Y,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
					Padding = React.createElement("UIPadding", {
						PaddingTop = UDim.new(0, 20),
						PaddingBottom = UDim.new(0, 20),
						PaddingLeft = UDim.new(0, 25),
						PaddingRight = UDim.new(0, 25),
					}),
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 5),
					}),

					ArmyRow = self:createEconomyStatRow("🛡️", "Army Size", tostring(self.props.armySize or 0), 1),
					HonorRow = self:createEconomyStatRow("🏆", "Honor", tostring(self.props.honor or 0), 2),
				}),
			}),

			-- DIVIDER
			Divider2 = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 2),
				BackgroundColor3 = Color3.fromRGB(70, 70, 75),
				BorderSizePixel = 0,
				LayoutOrder = 4,
			}),

			-- ECONOMY SECTION
			EconomySection = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 5,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 15),
				}),

				Header = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 35),
					BackgroundTransparency = 1,
					Text = "💰 ECONOMY",
					Font = Enum.Font.GothamBold,
					TextSize = 26,
					TextColor3 = UIConfig.HUD.CategoryButtonSelected,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				Panel = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 0),
					BackgroundColor3 = Color3.fromRGB(45, 45, 50),
					BorderSizePixel = 0,
					AutomaticSize = Enum.AutomaticSize.Y,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
					Padding = React.createElement("UIPadding", {
						PaddingTop = UDim.new(0, 20),
						PaddingBottom = UDim.new(0, 20),
						PaddingLeft = UDim.new(0, 25),
						PaddingRight = UDim.new(0, 25),
					}),
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 12),
					}),

					-- Season and Weather
					SeasonWeatherRow = React.createElement("Frame", {
						Size = UDim2.new(1, 0, 0, 45),
						BackgroundTransparency = 1,
						LayoutOrder = 1,
					}, {
						Layout = React.createElement("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 20),
							VerticalAlignment = Enum.VerticalAlignment.Center,
						}),

						SeasonIcon = React.createElement("TextLabel", {
							Size = UDim2.new(0, 35, 0, 35),
							BackgroundTransparency = 1,
							Text = getSeasonIcon(snapshot.season),
							Font = Enum.Font.GothamBold,
							TextSize = 28,
						}),

						SeasonLabel = React.createElement("TextLabel", {
							Size = UDim2.new(0.35, -55, 1, 0),
							BackgroundTransparency = 1,
							Text = snapshot.season or "Spring",
							Font = Enum.Font.GothamBold,
							TextSize = 18,
							TextColor3 = Color3.fromRGB(220, 220, 220),
							TextXAlignment = Enum.TextXAlignment.Left,
						}),

						WeatherIcon = React.createElement("TextLabel", {
							Size = UDim2.new(0, 35, 0, 35),
							BackgroundTransparency = 1,
							Text = getWeatherIcon(snapshot.weather),
							Font = Enum.Font.GothamBold,
							TextSize = 28,
						}),

						WeatherLabel = React.createElement("TextLabel", {
							Size = UDim2.new(0.35, -55, 1, 0),
							BackgroundTransparency = 1,
							Text = snapshot.weather or "Clear",
							Font = Enum.Font.GothamBold,
							TextSize = 18,
							TextColor3 = Color3.fromRGB(220, 220, 220),
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					}),

					-- Economy Health Bar
					HealthBar = self:createHealthBar("🏰", "Economy Health", snapshot.economyHealth or 50, 100, 2),

					-- Housing Bar
					HousingBar = self:createHealthBar(
						"🏘️",
						"Housing",
						snapshot.population or 0,
						snapshot.housingCapacity or 10,
						3
					),

					Divider = React.createElement("Frame", {
						Size = UDim2.new(1, 0, 0, 1),
						BackgroundColor3 = Color3.fromRGB(60, 60, 65),
						BorderSizePixel = 0,
						LayoutOrder = 4,
					}),

					TaxRow = self:createEconomyStatRow("💸", "Tax Rate", `{snapshot.taxRate or 0}%`, 5),
					ConsumptionRow = self:createEconomyStatRow(
						"🍴",
						"Food Usage (per 30s)",
						tostring(snapshot.foodConsumptionRate or 0),
						6
					),
				}),
			}),

			-- WARNINGS
			WarningsSection = (snapshot.isStarving or (snapshot.population or 0) > (snapshot.housingCapacity or 0))
					and React.createElement("Frame", {
						Size = UDim2.new(1, 0, 0, 0),
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.Y,
						LayoutOrder = 6,
					}, {
						Layout = React.createElement("UIListLayout", {
							FillDirection = Enum.FillDirection.Vertical,
							Padding = UDim.new(0, 10),
						}),

						StarvationWarning = snapshot.isStarving and React.createElement("Frame", {
							Size = UDim2.new(1, 0, 0, 50),
							BackgroundColor3 = Color3.fromRGB(183, 28, 28),
							BorderSizePixel = 0,
						}, {
							Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
							Padding = React.createElement("UIPadding", {
								PaddingLeft = UDim.new(0, 20),
								PaddingRight = UDim.new(0, 20),
							}),

							Label = React.createElement("TextLabel", {
								Size = UDim2.fromScale(1, 1),
								BackgroundTransparency = 1,
								Text = "⚠️ CRITICAL: Your people are starving!",
								Font = Enum.Font.GothamBold,
								TextSize = 18,
								TextColor3 = Color3.fromRGB(255, 255, 255),
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
						}) or nil,

						OvercrowdingWarning = ((snapshot.population or 0) > (snapshot.housingCapacity or 0))
								and React.createElement("Frame", {
									Size = UDim2.new(1, 0, 0, 50),
									BackgroundColor3 = Color3.fromRGB(245, 124, 0),
									BorderSizePixel = 0,
								}, {
									Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
									Padding = React.createElement("UIPadding", {
										PaddingLeft = UDim.new(0, 20),
										PaddingRight = UDim.new(0, 20),
									}),

									Label = React.createElement("TextLabel", {
										Size = UDim2.fromScale(1, 1),
										BackgroundTransparency = 1,
										Text = "⚠️ WARNING: Overcrowded - Build more housing!",
										Font = Enum.Font.GothamBold,
										TextSize = 18,
										TextColor3 = Color3.fromRGB(255, 255, 255),
										TextXAlignment = Enum.TextXAlignment.Left,
									}),
								})
							or nil,
					})
				or nil,
		}),
	})
end

return Stats
