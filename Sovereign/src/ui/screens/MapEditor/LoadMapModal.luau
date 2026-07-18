--!strict
-- LoadMapModal: Overlay modal for selecting a saved map to load, with inline rename
local React = require(game.ReplicatedStorage.Packages.react)

local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local LoadMapModal = React.Component:extend("LoadMapModal")

function LoadMapModal:init()
	self:setState({
		renamingMapId = nil :: string?,
		renameText = "",
		confirmDeleteMapId = nil :: string?,
	})
end

function LoadMapModal:render()
	local maps: { any } = self.props.maps or {}
	local onClose: () -> () = self.props.onClose
	local onSelectMap: (string) -> () = self.props.onSelectMap
	local onRenameMap: ((string, string) -> ())? = self.props.onRenameMap
	local onDeleteMap: ((string) -> ())? = self.props.onDeleteMap

	local renamingMapId: string? = self.state.renamingMapId
	local renameText: string = self.state.renameText
	local confirmDeleteMapId: string? = self.state.confirmDeleteMapId

	-- Build list rows
	local rows: { [string]: any } = {
		UIListLayout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
	}

	if #maps == 0 then
		rows.Empty = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text = "No saved maps found.",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 145, 120),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	else
		for i, mapEntry in ipairs(maps) do
			local displayDate = ""
			if mapEntry.UpdatedAt then
				local ok, t = pcall(function()
					return os.date("*t", mapEntry.UpdatedAt)
				end)
				if ok and t then
					local td = t :: any
					if td.year and td.month and td.day then
						displayDate = string.format("%04d-%02d-%02d", td.year, td.month, td.day)
					end
				end
			end

			local mapId: string = mapEntry.MapId or ""
			local isRenaming = renamingMapId == mapId

			if isRenaming then
				-- Rename row: text box + confirm + cancel
				rows["Map_" .. i] = React.createElement("Frame", {
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, 44),
					BackgroundColor3 = Color3.fromRGB(50, 36, 26),
					BorderSizePixel = 0,
				}, {
					UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
					UIStroke = React.createElement("UIStroke", {
						Color = Color3.fromRGB(209, 148, 92),
						Thickness = 1,
					}),
					UIPadding = React.createElement("UIPadding", {
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10),
					}),
					UIListLayout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 6),
					}),
					NameBox = React.createElement("TextBox", {
						LayoutOrder = 1,
						Size = UDim2.new(1, -90, 0, 28),
						BackgroundColor3 = Color3.fromRGB(40, 28, 18),
						BorderSizePixel = 0,
						Text = renameText,
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(240, 220, 185),
						TextSize = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
						ClearTextOnFocus = false,
						[React.Event.FocusLost] = function(rbx, enterPressed)
							if enterPressed and onRenameMap and rbx.Text ~= "" then
								onRenameMap(mapId, rbx.Text)
								self:setState({ renamingMapId = nil, renameText = "" })
							end
						end,
						[React.Change.Text] = function(rbx)
							self:setState({ renameText = rbx.Text })
						end,
					}, {
						UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
						UIPadding = React.createElement("UIPadding", {
							PaddingLeft = UDim.new(0, 6),
							PaddingRight = UDim.new(0, 6),
						}),
					}),
					OkBtn = React.createElement("TextButton", {
						LayoutOrder = 2,
						Size = UDim2.new(0, 36, 0, 28),
						BackgroundColor3 = Color3.fromRGB(60, 100, 60),
						BorderSizePixel = 0,
						Text = "OK",
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(180, 230, 180),
						TextSize = 13,
						[React.Event.MouseButton1Click] = function()
							if onRenameMap and renameText ~= "" then
								onRenameMap(mapId, renameText)
							end
							self:setState({ renamingMapId = nil, renameText = "" })
						end,
					}, {
						UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
					}),
					CancelBtn = React.createElement("TextButton", {
						LayoutOrder = 3,
						Size = UDim2.new(0, 44, 0, 28),
						BackgroundColor3 = Color3.fromRGB(90, 50, 50),
						BorderSizePixel = 0,
						Text = "Cancel",
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(230, 180, 180),
						TextSize = 13,
						[React.Event.MouseButton1Click] = function()
							self:setState({ renamingMapId = nil, renameText = "" })
						end,
					}, {
						UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
					}),
				})
			elseif confirmDeleteMapId == mapId then
				-- Confirm delete row
				rows["Map_" .. i] = React.createElement("Frame", {
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, 44),
					BackgroundColor3 = Color3.fromRGB(70, 30, 30),
					BorderSizePixel = 0,
				}, {
					UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
					UIStroke = React.createElement("UIStroke", {
						Color = Color3.fromRGB(180, 80, 80),
						Thickness = 1,
					}),
					UIPadding = React.createElement("UIPadding", {
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10),
					}),
					UIListLayout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 6),
					}),
					ConfirmLabel = React.createElement("TextLabel", {
						LayoutOrder = 1,
						Size = UDim2.new(1, -110, 1, 0),
						BackgroundTransparency = 1,
						Text = "Delete \"" .. (mapEntry.Name or "Unnamed Map") .. "\"?",
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(240, 180, 180),
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
					}),
					YesBtn = React.createElement("TextButton", {
						LayoutOrder = 2,
						Size = UDim2.new(0, 46, 0, 28),
						BackgroundColor3 = Color3.fromRGB(140, 50, 50),
						BorderSizePixel = 0,
						Text = "Delete",
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(255, 200, 200),
						TextSize = 13,
						[React.Event.MouseButton1Click] = function()
							if onDeleteMap then
								onDeleteMap(mapId)
							end
							self:setState({ confirmDeleteMapId = nil })
						end,
					}, {
						UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
					}),
					NoBtn = React.createElement("TextButton", {
						LayoutOrder = 3,
						Size = UDim2.new(0, 50, 0, 28),
						BackgroundColor3 = Color3.fromRGB(61, 43, 31),
						BorderSizePixel = 0,
						Text = "Cancel",
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(190, 175, 155),
						TextSize = 13,
						[React.Event.MouseButton1Click] = function()
							self:setState({ confirmDeleteMapId = nil })
						end,
					}, {
						UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
					}),
				})
			else
				-- Normal row: name + date + rename + delete buttons
				rows["Map_" .. i] = React.createElement("TextButton", {
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, 44),
					BackgroundColor3 = Color3.fromRGB(61, 43, 31),
					BorderSizePixel = 0,
					Text = "",
					[React.Event.MouseButton1Click] = function()
						onSelectMap(mapId)
					end,
					[React.Event.MouseEnter] = function(rbx: GuiButton)
						rbx.BackgroundColor3 = Color3.fromRGB(90, 65, 45)
					end,
					[React.Event.MouseLeave] = function(rbx: GuiButton)
						rbx.BackgroundColor3 = Color3.fromRGB(61, 43, 31)
					end,
				}, {
					UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
					UIStroke = React.createElement("UIStroke", {
						Color = Color3.fromRGB(120, 95, 65),
						Thickness = 1,
					}),
					UIPadding = React.createElement("UIPadding", {
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10),
					}),
					NameLabel = React.createElement("TextLabel", {
						Size = UDim2.new(1, -148, 1, 0),
						BackgroundTransparency = 1,
						Text = mapEntry.Name or "Unnamed Map",
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(230, 210, 175),
						TextSize = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
					}),
					DateLabel = React.createElement("TextLabel", {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -82, 0.5, 0),
						Size = UDim2.new(0, 62, 0, 28),
						BackgroundTransparency = 1,
						Text = displayDate,
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(160, 145, 120),
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Right,
					}),
					RenameBtn = React.createElement("TextButton", {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -40, 0.5, 0),
						Size = UDim2.new(0, 32, 0, 28),
						BackgroundColor3 = Color3.fromRGB(76, 62, 62),
						BorderSizePixel = 0,
						Text = "✎",
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(199, 166, 122),
						TextSize = 16,
						ZIndex = 2,
						[React.Event.MouseButton1Click] = function()
							self:setState({
								renamingMapId = mapId,
								renameText = mapEntry.Name or "",
							})
						end,
					}, {
						UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
					}),
					DeleteBtn = React.createElement("TextButton", {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -4, 0.5, 0),
						Size = UDim2.new(0, 32, 0, 28),
						BackgroundColor3 = Color3.fromRGB(100, 45, 45),
						BorderSizePixel = 0,
						Text = "🗑",
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(230, 160, 160),
						TextSize = 14,
						ZIndex = 2,
						[React.Event.MouseButton1Click] = function()
							self:setState({ confirmDeleteMapId = mapId })
						end,
					}, {
						UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
					}),
				})
			end
		end
	end

	local listCanvasHeight = math.max(#maps * 48, 40)

	return React.createElement("Frame", {
		Name = "LoadModalOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		ZIndex = 50,
	}, {
		Modal = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 480, 0, 420),
			BackgroundColor3 = Color3.fromRGB(76, 62, 62),
			BorderSizePixel = 0,
			ZIndex = 51,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
			UIStroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(140, 115, 85),
				Thickness = 1.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			UIPadding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 14),
				PaddingLeft = UDim.new(0, 14),
				PaddingRight = UDim.new(0, 14),
				PaddingBottom = UDim.new(0, 14),
			}),
			TitleBar = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundTransparency = 1,
			}, {
				Title = React.createElement("TextLabel", {
					Size = UDim2.new(1, -40, 1, 0),
					BackgroundTransparency = 1,
					Text = "Load Map",
					FontFace = UIConfig.Font.Default,
					TextColor3 = Color3.fromRGB(209, 148, 92),
					TextSize = 18,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				CloseButton = React.createElement("TextButton", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.new(0, 30, 0, 30),
					BackgroundColor3 = Color3.fromRGB(110, 55, 55),
					BorderSizePixel = 0,
					Text = "X",
					FontFace = UIConfig.Font.Default,
					TextColor3 = Color3.fromRGB(255, 220, 200),
					TextSize = 14,
					[React.Event.MouseButton1Click] = onClose,
				}, {
					UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
				}),
			}),
			Divider = React.createElement("Frame", {
				Position = UDim2.new(0, 0, 0, 40),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Color3.fromRGB(120, 95, 65),
				BorderSizePixel = 0,
			}),
			ListScroll = React.createElement("ScrollingFrame", {
				Position = UDim2.new(0, 0, 0, 48),
				Size = UDim2.new(1, 0, 1, -48),
				BackgroundTransparency = 1,
				CanvasSize = UDim2.new(0, 0, 0, listCanvasHeight),
				ScrollBarThickness = 6,
				ScrollBarImageColor3 = Color3.fromRGB(140, 115, 85),
				BorderSizePixel = 0,
			}, rows),
		}),
	})
end

return LoadMapModal
