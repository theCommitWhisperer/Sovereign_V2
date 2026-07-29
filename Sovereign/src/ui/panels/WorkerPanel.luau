--!strict
-- WorkerPanel: the BUILDING SELECTED bottom-zone state for a production
-- building (a training building instead renders the existing TrainingPanel --
-- see MobileShell). Bespoke rather than a port of WorkerAssignmentPanel: the
-- brief asks for a specific compact layout (name/output/worker count/storage
-- bar/four actions) that the old panel's per-worker list doesn't match.
--
-- Reads live worker count and storage straight off the building Model's
-- attributes (WorkerCount, Storage_<resource>), the same instance-attribute
-- pattern WorkerAssignmentPanel and UnitSelectionPanel already use -- these are
-- server-replicated Instance state, not a RemoteEvent call, so it doesn't
-- violate the "panels never touch remotes" rule.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)
local BuildingCatalog = require(script.Parent.Parent.BuildingCatalog)
local BuildingSpec = require(ReplicatedStorage.Shared.GameData.BuildingSpec)

export type Props = {
	building: Model,
	onAddWorker: () -> (),
	onRemoveWorker: () -> (),
	onDelete: () -> (),
	onClose: () -> (),
	LayoutOrder: number?,
}

-- Highest-capacity storage slot is the one worth a progress bar; a building
-- storing several resources still only gets one bar, same "pick the headline"
-- call BuildingCatalog.describeOutput already makes for the output string.
local function primaryStorageResource(spec: BuildingSpec.Spec?): string?
	if not spec then
		return nil
	end
	local best, bestAmount = nil, 0
	for resource, amount in spec.storage do
		if amount > bestAmount then
			best, bestAmount = resource, amount
		end
	end
	return best
end

local function actionButton(text: string, layoutOrder: number, color: Color3, onClick: () -> ())
	return React.createElement("TextButton", {
		LayoutOrder = layoutOrder,
		Size = UDim2.new(0.25, -Theme.Metrics.GapTight, 1, 0),
		BackgroundColor3 = color,
		BackgroundTransparency = Theme.Transparency.CardActive,
		AutoButtonColor = false,
		Text = text,
		Font = Theme.Font.BodyBold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextPrimary,
		[React.Event.Activated] = onClick,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
	})
end

local function WorkerPanel(props: Props)
	local building = props.building
	local buildingType = building:GetAttribute("BuildingType") :: string?
	local entry = buildingType and BuildingCatalog.get(buildingType) or nil
	local spec = buildingType and BuildingSpec.get(buildingType) or nil
	local resource = primaryStorageResource(spec)

	local workerCount, setWorkerCount = React.useState(0)
	local stored, setStored = React.useState(0)

	React.useEffect(function()
		setWorkerCount(building:GetAttribute("WorkerCount") or 0)
		if resource then
			setStored(building:GetAttribute(`Storage_{resource}`) or 0)
		end

		local connections: { RBXScriptConnection } = {}
		table.insert(
			connections,
			building:GetAttributeChangedSignal("WorkerCount"):Connect(function()
				setWorkerCount(building:GetAttribute("WorkerCount") or 0)
			end)
		)
		if resource then
			table.insert(
				connections,
				building:GetAttributeChangedSignal(`Storage_{resource}`):Connect(function()
					setStored(building:GetAttribute(`Storage_{resource}`) or 0)
				end)
			)
		end

		return function()
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end, { building, resource })

	local capacity = (spec and spec.work and spec.work.slots) or 0
	local storageCapacity = (resource and spec and spec.storage[resource]) or 0
	local fraction = if storageCapacity > 0 then math.clamp(stored / storageCapacity, 0, 1) else 0

	return React.createElement("Frame", {
		Name = "WorkerPanel",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, Theme.Metrics.DrawerMaxHeight),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = Theme.Transparency.Drawer,
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusCard) }),
		Stroke = React.createElement("UIStroke", Theme.strokeProps()),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.PadLoose),
			PaddingBottom = UDim.new(0, Theme.Metrics.PadLoose),
			PaddingLeft = UDim.new(0, Theme.Metrics.PadLoose),
			PaddingRight = UDim.new(0, Theme.Metrics.PadLoose),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.Gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		Header = React.createElement("Frame", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
		}, {
			Name = React.createElement("TextLabel", {
				Size = UDim2.new(0.6, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = (entry and entry.name) or buildingType or "Building",
				Font = Theme.Font.BodyBold,
				TextSize = Theme.TextSize.Title,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Output = (entry and entry.output) and React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0.4, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = entry.output,
				Font = Theme.Font.BodyBold,
				TextSize = Theme.TextSize.Body,
				TextColor3 = Theme.Color.Success,
				TextXAlignment = Enum.TextXAlignment.Right,
			}) or nil,
		}),

		Workers = React.createElement("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = `{workerCount} of {capacity} workers`,
			Font = Theme.Font.Body,
			TextSize = Theme.TextSize.Body,
			TextColor3 = Theme.Color.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		StorageBar = resource and React.createElement("Frame", {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Text = `Storage: {stored}/{storageCapacity} {resource}`,
				Font = Theme.Font.Body,
				TextSize = Theme.TextSize.Small,
				TextColor3 = Theme.Color.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Track = React.createElement("Frame", {
				Position = UDim2.fromOffset(0, 18),
				Size = UDim2.new(1, 0, 0, 10),
				BackgroundColor3 = Theme.Color.Surface,
				BackgroundTransparency = Theme.Transparency.Card,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(fraction, 1),
					BackgroundColor3 = Theme.Color.Success,
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				}),
			}),
		}) or nil,

		Buttons = React.createElement("Frame", {
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, Theme.Metrics.TouchTarget),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, Theme.Metrics.GapTight),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Add = actionButton("+ Add", 1, Theme.Color.Action, props.onAddWorker),
			Remove = actionButton("− Remove", 2, Theme.Color.Surface, props.onRemoveWorker),
			Delete = actionButton("Delete", 3, Theme.Color.Danger, props.onDelete),
			Close = actionButton("Close", 4, Theme.Color.Surface, props.onClose),
		}),
	})
end

return WorkerPanel
