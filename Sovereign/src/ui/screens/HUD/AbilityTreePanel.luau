--!strict
-- AbilityTreePanel: Hero ability upgrade tree (MonetizationConfig.HeroAbilityTree).
-- Nodes unlock/upgrade hero abilities and are paid for with in-game Glory.
--
-- Wire-up:
--   open  ? HUD utility button (??) toggles state.showAbilityTree
--   fetch ? FireServer("GetAbilityTree")            ? "AbilityTreeData"  { ranks, glory }
--   buy   ? FireServer("PurchaseAbilityNode",{nodeId}) ? "AbilityNodeResult"
--             { nodeId, success, reason, ranks, glory }
--   live  ? "GloryUpdate" { glory, lifetime } keeps affordability tinting fresh.

local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Modal = require(script.Parent.Parent.Parent.components.Modal)
local MonetizationConfig = require(ReplicatedStorage.Shared.GameData.MonetizationConfig)

local AbilityTreePanel = React.Component:extend("AbilityTreePanel")

export type Props = {
	visible: boolean,
	onClose: () -> (),
	tooltip: any?,
}

-- Depth in the prerequisite chain (root = 1); memoised per render pass.
local function nodeDepth(nodeId: string, cache: { [string]: number }): number
	if cache[nodeId] then
		return cache[nodeId]
	end
	cache[nodeId] = 1 -- guard against accidental cycles
	local node = MonetizationConfig.findAbilityNode(nodeId)
	local depth = 1
	if node then
		for _, prereqId in node.prerequisites do
			depth = math.max(depth, nodeDepth(prereqId, cache) + 1)
		end
	end
	cache[nodeId] = depth
	return depth
end

function AbilityTreePanel:init()
	self:setState({
		ranks = {},
		glory = 0,
		message = false, -- last purchase result line (string | false)
	})
end

function AbilityTreePanel:didMount()
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	self.gameEvent = RemoteEvents and RemoteEvents:WaitForChild("GameEvent", 10)
	if not self.gameEvent then
		warn("?? [AbilityTreePanel] GameEvent not found")
		return
	end

	self.gameEvent:FireServer("GetAbilityTree")

	self.connection = self.gameEvent.OnClientEvent:Connect(function(action, data)
		if action == "AbilityTreeData" and typeof(data) == "table" then
			self:setState({
				ranks = data.ranks or {},
				glory = data.glory or 0,
			})
		elseif action == "AbilityNodeResult" and typeof(data) == "table" then
			local node = MonetizationConfig.findAbilityNode(data.nodeId or "")
			local nodeName = node and node.name or tostring(data.nodeId)
			self:setState({
				ranks = data.ranks or self.state.ranks,
				glory = data.glory or self.state.glory,
				message = if data.success
					then `? {nodeName} advanced!`
					else `? {nodeName}: {data.reason or "purchase failed"}`,
			})
		elseif action == "GloryUpdate" and typeof(data) == "table" then
			self:setState({ glory = data.glory or 0 })
		end
	end)
end

function AbilityTreePanel:willUnmount()
	if self.connection then
		self.connection:Disconnect()
	end
end

function AbilityTreePanel:render()
	if not self.props.visible then
		return nil
	end

	local ranks = self.state.ranks or {}
	local glory = self.state.glory or 0
	local depthCache: { [string]: number } = {}

	local content = {}

	-- Glory balance header row
	content.GloryHeader = React.createElement("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Text = string.format("?? Glory: %d", glory),
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		TextColor3 = Color3.fromRGB(255, 215, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 0,
	})

	-- Purchase result feedback
	content.ResultMessage = self.state.message and React.createElement("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = self.state.message,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextColor3 = string.sub(self.state.message, 1, 3) == "?" and Color3.fromRGB(120, 200, 120)
			or Color3.fromRGB(210, 110, 100),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
	}) or nil

	-- One card per node, ordered by prerequisite depth so the tree reads
	-- top-to-bottom (roots first, capstones last).
	for index, node in ipairs(MonetizationConfig.HeroAbilityTree) do
		local currentRank = ranks[node.id] or 0
		local isMaxed = currentRank >= node.maxRank
		local nextCost = if isMaxed then 0 else (node.gloryCostPerRank[currentRank + 1] or 0)

		-- Prerequisites: all must be rank >= 1
		local prereqNames = {}
		local prereqsMet = true
		for _, prereqId in node.prerequisites do
			local prereqNode = MonetizationConfig.findAbilityNode(prereqId)
			table.insert(prereqNames, prereqNode and prereqNode.name or prereqId)
			if (ranks[prereqId] or 0) < 1 then
				prereqsMet = false
			end
		end

		local canAfford = glory >= nextCost
		local canBuy = not isMaxed and prereqsMet and canAfford

		-- Rank pips, e.g. ??? for rank 2/3
		local pips = ""
		for rank = 1, node.maxRank do
			pips ..= if rank <= currentRank then "?" else "?"
		end

		local depth = nodeDepth(node.id, depthCache)

		local buttonText
		local buttonColor
		if isMaxed then
			buttonText = "MAX RANK"
			buttonColor = Color3.fromRGB(120, 96, 48) -- gold-brown
		elseif not prereqsMet then
			buttonText = "?? Locked"
			buttonColor = UIConfig.HUD.BuildingButtonUnaffordable
		else
			buttonText = string.format("%s — %d ??", if currentRank == 0 then "Unlock" else "Upgrade", nextCost)
			buttonColor = canAfford and UIConfig.HUD.BuildingButtonAffordable
				or UIConfig.HUD.BuildingButtonUnaffordable
		end

		content["Node_" .. node.id] = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 96),
			BackgroundColor3 = UIConfig.HUD.UtilityButtonBackground,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 2,
			BorderColor3 = isMaxed and Color3.fromRGB(255, 215, 0) or UIConfig.HUD.UtilityButtonBorder,
			LayoutOrder = depth * 10 + index,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 12 + (depth - 1) * 24), -- indent by tree depth
				PaddingRight = UDim.new(0, 12),
			}),

			-- Name + rank pips
			NameLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, -180, 0, 22),
				BackgroundTransparency = 1,
				Text = string.format("%s  %s", node.name, pips),
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = currentRank > 0 and Color3.fromRGB(255, 215, 0) or UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			-- Description
			DescLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, -180, 0, 34),
				Position = UDim2.fromOffset(0, 24),
				BackgroundTransparency = 1,
				Text = node.description,
				Font = Enum.Font.Gotham,
				TextSize = 14,
				TextWrapped = true,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),

			-- Prerequisite line (tree edge, rendered as text)
			PrereqLabel = #prereqNames > 0 and React.createElement("TextLabel", {
				Size = UDim2.new(1, -180, 0, 16),
				Position = UDim2.new(0, 0, 1, -16),
				BackgroundTransparency = 1,
				Text = "+ Requires: " .. table.concat(prereqNames, ", "),
				Font = Enum.Font.Gotham,
				TextSize = 13,
				TextColor3 = prereqsMet and Color3.fromRGB(120, 200, 120) or Color3.fromRGB(210, 110, 100),
				TextXAlignment = Enum.TextXAlignment.Left,
			}) or nil,

			-- Purchase button
			BuyButton = React.createElement("TextButton", {
				Size = UDim2.fromOffset(150, 40),
				Position = UDim2.new(1, -150, 0.5, -20),
				BackgroundColor3 = buttonColor,
				BorderSizePixel = 2,
				BorderColor3 = UIConfig.HUD.StrokeColor,
				Text = buttonText,
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				AutoButtonColor = canBuy,
				[React.Event.Activated] = function()
					if canBuy and self.gameEvent then
						self.gameEvent:FireServer("PurchaseAbilityNode", { nodeId = node.id })
					end
				end,
			}),
		})
	end

	return React.createElement(Modal, {
		title = "?? Hero Ability Tree",
		visible = self.props.visible,
		onClose = self.props.onClose,
	}, content)
end

return AbilityTreePanel
