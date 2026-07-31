--!strict
-- MiniMap: the single minimap component, used by both DesktopShell and
-- MobileShell.
--
-- There used to be two of these (MiniMap and MiniMapEnhanced) with duplicated
-- coordinate maths, which is how `MAP_SIZE = 1000` survived in both files while
-- the shipped map was 1600 studs -- every dot was drawn at 62% of its true
-- offset and click-to-move sent the camera to the wrong place.
--
-- Two rules hold this together:
--
--  1. Blips come from the server (MinimapService), never from scanning
--     workspace. The old version called CheckVisibility:InvokeServer() once per
--     unit twice a second, and under StreamingEnabled it could only ever see
--     objects inside the client's streaming radius.
--
--  2. Blips are painted onto a pool of reused Frames by direct property writes,
--     never through setState. Reconciling a few hundred dots at 4Hz is what made
--     the old one expensive. React here owns only the static chrome and the
--     handful of alert pings.

local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MinimapBlips = require(ReplicatedStorage.Shared.MinimapBlips)
local MinimapService = require(ReplicatedStorage.Shared.MinimapService)

local Kind = MinimapBlips.Kind
local Relation = MinimapBlips.Relation

local MiniMap = React.Component:extend("MiniMap")

-- Pool grows on demand up to MinimapBlips.MAX_BLIPS rather than allocating the
-- ceiling up front, since most matches never approach it.
local POOL_INITIAL = 64

local PING_LIFETIME = 5

local COLOR_BY_RELATION = {
	[Relation.Self] = Color3.fromRGB(90, 190, 255),
	[Relation.Ally] = Color3.fromRGB(110, 235, 200),
	[Relation.Enemy] = Color3.fromRGB(255, 95, 95),
	[Relation.Neutral] = Color3.fromRGB(180, 175, 160),
}

-- Buildings read slightly differently from units so a base is findable at a
-- glance without needing an icon per structure.
local BUILDING_COLOR_BY_RELATION = {
	[Relation.Self] = Color3.fromRGB(140, 245, 150),
	[Relation.Ally] = Color3.fromRGB(150, 230, 210),
	[Relation.Enemy] = Color3.fromRGB(255, 140, 140),
	[Relation.Neutral] = Color3.fromRGB(190, 185, 170),
}

local RESOURCE_COLOR = {
	[MinimapBlips.ResourceSubtype.Wood] = Color3.fromRGB(70, 130, 60),
	[MinimapBlips.ResourceSubtype.Stone] = Color3.fromRGB(150, 150, 155),
	[MinimapBlips.ResourceSubtype.Food] = Color3.fromRGB(215, 180, 90),
	[MinimapBlips.ResourceSubtype.Iron_Ore] = Color3.fromRGB(120, 110, 130),
	[MinimapBlips.ResourceSubtype.Gold] = Color3.fromRGB(230, 195, 80),
}

local KEEP_SUBTYPE = MinimapBlips.BuildingSubtype.Keep

function MiniMap:init()
	self:setState({
		pings = {},
		previewImage = MinimapService.getMapConfig().PreviewImage,
	})

	self.blipLayerRef = React.createRef()
	self.pool = {} :: { Frame }
	self.unsubscribe = nil :: (() -> ())?
	self.pingConnection = nil :: RBXScriptConnection?
	self.pingCleanup = nil
	self.unmounted = false
end

function MiniMap:growPool(needed: number)
	local layer = self.blipLayerRef.current
	if not layer then
		return
	end

	local target = math.min(math.max(needed, POOL_INITIAL), MinimapBlips.MAX_BLIPS)
	for i = #self.pool + 1, target do
		local frame = Instance.new("Frame")
		frame.Name = `Blip{i}`
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = layer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame

		self.pool[i] = frame
	end
end

--- Repaint every blip. Called on each server snapshot (~4Hz). Writes properties
--- directly on pooled Frames -- no allocation, no reconciliation.
function MiniMap:repaint()
	local layer = self.blipLayerRef.current
	if not layer then
		return
	end

	local buf, count = MinimapService.getBlips()
	if not buf then
		return
	end

	if count > #self.pool then
		self:growPool(count)
	end

	local drawn = 0
	for i = 0, math.min(count, #self.pool) - 1 do
		local x, z, _ownerSlot, relation, kind, subtype = MinimapBlips.read(buf, i)
		local u, v = MinimapService.worldToMinimap(x, z)

		local frame = self.pool[i + 1]
		if not frame then
			break
		end

		local size, color, zIndex
		if kind == Kind.Building then
			-- Keeps are the thing you actually navigate by, so give them a
			-- noticeably bigger footprint than ordinary structures.
			size = if subtype == KEEP_SUBTYPE then 9 else 6
			color = BUILDING_COLOR_BY_RELATION[relation] or BUILDING_COLOR_BY_RELATION[Relation.Neutral]
			zIndex = 4
		elseif kind == Kind.Resource then
			size = 4
			color = RESOURCE_COLOR[subtype] or COLOR_BY_RELATION[Relation.Neutral]
			zIndex = 2
		else
			size = 3
			color = COLOR_BY_RELATION[relation] or COLOR_BY_RELATION[Relation.Neutral]
			zIndex = 3
		end

		frame.Size = UDim2.fromOffset(size, size)
		frame.Position = UDim2.fromScale(u, v)
		frame.BackgroundColor3 = color
		frame.ZIndex = zIndex
		frame.Visible = true
		drawn += 1
	end

	for i = drawn + 1, #self.pool do
		self.pool[i].Visible = false
	end

	-- The preview image only arrives once, with GameStarted, so this settles
	-- after the first snapshot and never churns again.
	local preview = MinimapService.getMapConfig().PreviewImage
	if preview ~= self.state.previewImage then
		self:setState({ previewImage = preview })
	end
end

function MiniMap:addPing(position: Vector3?, color: Color3?, message: string?)
	if not position then
		return
	end
	local u, v = MinimapService.worldToMinimap(position.X, position.Z)

	local pings = table.clone(self.state.pings)
	table.insert(pings, {
		u = u,
		v = v,
		color = color or Color3.fromRGB(255, 80, 80),
		message = message,
		expiresAt = os.clock() + PING_LIFETIME,
	})
	self:setState({ pings = pings })
end

function MiniMap:didMount()
	MinimapService.start()

	self.unsubscribe = MinimapService.onSnapshot(function()
		self:repaint()
	end)

	self:growPool(POOL_INITIAL)
	self:repaint()

	-- Spawned rather than inline: WaitForChild in didMount would yield React's
	-- commit phase if RemoteEvents has not replicated yet. Same reason
	-- MinimapService.start and FogVisibility.start defer theirs.
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
		local gameEvent = remotes:WaitForChild("GameEvent") :: RemoteEvent
		if self.unmounted then
			return
		end
		self.pingConnection = gameEvent.OnClientEvent:Connect(function(action: string, data: any)
			if action == "MinimapPing" and typeof(data) == "table" then
				self:addPing(data.position, data.color, data.message)
			elseif action == "BuildingUnderAttack" and typeof(data) == "table" then
				self:addPing(data.position, Color3.fromRGB(255, 60, 60), "Under attack")
			end
		end)
	end)

	-- Expire pings on their own slow timer rather than inside repaint, so ping
	-- lifetime does not depend on snapshots arriving.
	self.pingCleanup = task.spawn(function()
		while true do
			task.wait(1)
			local pings = self.state.pings
			if #pings > 0 then
				local now = os.clock()
				local kept = {}
				for _, ping in pings do
					if ping.expiresAt > now then
						table.insert(kept, ping)
					end
				end
				if #kept ~= #pings then
					self:setState({ pings = kept })
				end
			end
		end
	end)
end

function MiniMap:willUnmount()
	self.unmounted = true
	if self.unsubscribe then
		self.unsubscribe()
		self.unsubscribe = nil
	end
	if self.pingConnection then
		self.pingConnection:Disconnect()
		self.pingConnection = nil
	end
	if self.pingCleanup then
		task.cancel(self.pingCleanup)
		self.pingCleanup = nil
	end
	for _, frame in self.pool do
		frame:Destroy()
	end
	self.pool = {}
end

function MiniMap:onMinimapClick(rbx: GuiObject, input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local absolutePos = rbx.AbsolutePosition
	local absoluteSize = rbx.AbsoluteSize
	if absoluteSize.X <= 0 or absoluteSize.Y <= 0 then
		return
	end

	local u = (mousePos.X - absolutePos.X) / absoluteSize.X
	local v = (mousePos.Y - absolutePos.Y) / absoluteSize.Y

	-- Both shells clip the minimap to a circle, so ignore clicks in the corners.
	local dx, dz = u - 0.5, v - 0.5
	if math.sqrt(dx * dx + dz * dz) > 0.5 then
		return
	end

	local worldX, worldZ = MinimapService.minimapToWorld(math.clamp(u, 0, 1), math.clamp(v, 0, 1))

	local camera = workspace.CurrentCamera
	if camera then
		local target = Vector3.new(worldX, camera.CFrame.Position.Y, worldZ)
		camera.CFrame = CFrame.new(target, target + camera.CFrame.LookVector)
	end
end

function MiniMap:render()
	local pingElements = {}
	for i, ping in self.state.pings do
		pingElements[`Ping{i}`] = React.createElement("Frame", {
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromScale(ping.u, ping.v),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 6,
		}, {
			Ring = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 6,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Stroke = React.createElement("UIStroke", {
					Color = ping.color,
					Thickness = 2,
					Transparency = 0.15,
				}),
			}),
		})
	end

	local previewImage = self.state.previewImage

	return React.createElement("ImageButton", {
		Name = "MiniMapButton",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 60, 40),
		BackgroundTransparency = if previewImage then 1 else 0.35,
		Image = previewImage or "",
		ScaleType = Enum.ScaleType.Stretch,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ZIndex = 1,
		[React.Event.InputBegan] = function(rbx, input)
			self:onMinimapClick(rbx, input)
		end,
	}, {
		-- Only drawn when there is no baked map image to sit behind the blips.
		GridOverlay = (not previewImage) and React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}, {
			VLine = React.createElement("Frame", {
				Size = UDim2.new(0, 1, 1, 0),
				Position = UDim2.fromScale(0.5, 0),
				BackgroundColor3 = Color3.fromRGB(100, 100, 100),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
			}),
			HLine = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.fromScale(0, 0.5),
				BackgroundColor3 = Color3.fromRGB(100, 100, 100),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
			}),
		}) or nil,

		-- Pooled blip Frames are parented here imperatively; React must never
		-- own children of this frame or it will fight the pool.
		BlipLayer = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			ref = self.blipLayerRef,
		}),

		Pings = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 6,
		}, pingElements),
	})
end

return MiniMap
