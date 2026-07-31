--!strict
-- FogOfWarClient: hides enemy units, buildings and resource nodes that are not
-- in vision range, by reparenting them out of Workspace into ReplicatedStorage.
--
-- Rewritten to fix four things:
--
--  1. It called CheckVisibility:InvokeServer() once per object, twice a second.
--     Visibility now comes from Shared.FogVisibility, which makes one batched
--     call per sweep and caches the result.
--
--  2. It ran unconditionally. Fog of war is OFF by default (it is an admin
--     toggle, /fog on), so every one of those round trips answered "visible"
--     and the entire sweep was pure cost. The loop now no-ops until the server
--     pushes FogState.enabled = true.
--
--  3. It darkened Lighting at require time and never undid it -- so every
--     player played a permanently dimmed, blue-tinted game to indicate a fog
--     mode that was not on. Visuals now apply and revert with the toggle.
--
--  4. A single failed pcall did `return` out of updateVisibility(), abandoning
--     every object after it in the sweep. Failures are now contained per object.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local FogVisibility = require(ReplicatedStorage.Shared.FogVisibility)

local FogClientDebug = DebugManager.createChannel("FogOfWarClient", false)

local FogOfWarClient = {}

local SWEEP_INTERVAL = 0.5

-- Which Workspace folder each hidden model came from, so it can be put back.
local originFolder: { [Model]: string } = {}

local HiddenFolder = FogVisibility.getHiddenFolder()

local savedLighting: { Brightness: number, Ambient: Color3, OutdoorAmbient: Color3 }? = nil

local function hide(model: Model, folderName: string)
	if model.Parent == HiddenFolder then
		return
	end
	originFolder[model] = folderName
	model.Parent = HiddenFolder
	FogClientDebug:info(`Hidden: {model.Name}`)
end

local function reveal(model: Model)
	local folderName = originFolder[model]
	if not folderName then
		return
	end
	local folder = workspace:FindFirstChild(folderName)
	if folder then
		model.Parent = folder
		originFolder[model] = nil
		FogClientDebug:info(`Revealed: {model.Name}`)
	end
end

--- Put everything back where it came from. Called when fog is switched off.
local function revealAll()
	for model, _ in originFolder do
		if model.Parent then
			reveal(model)
		else
			originFolder[model] = nil
		end
	end
	table.clear(originFolder)
end

local function sweepFolder(folderName: string, ownedByPlayerIsAlwaysVisible: boolean)
	local folder = workspace:FindFirstChild(folderName)
	if not folder then
		return
	end

	for _, model in folder:GetChildren() do
		if not model:IsA("Model") or not model.PrimaryPart then
			continue
		end

		if ownedByPlayerIsAlwaysVisible and model:GetAttribute("OwnerId") == player.UserId then
			continue
		end

		-- One failing model must not abandon the rest of the sweep, which is
		-- exactly what the old `return`-inside-the-loop did.
		local ok, err = pcall(function()
			if not FogVisibility.isVisible(model) then
				hide(model, folderName)
			end
		end)
		if not ok then
			FogClientDebug:warn(`sweep failed for {model.Name}: {tostring(err)}`)
		end
	end
end

--- Anything in the hidden folder that has come back into vision.
local function sweepHidden()
	for _, model in HiddenFolder:GetChildren() do
		if model:IsA("Model") and FogVisibility.isVisible(model) then
			reveal(model)
		end
	end
end

local function updateVisibility()
	if not FogVisibility.isEnabled() then
		return
	end

	sweepFolder("Units", true)
	sweepFolder("Buildings", true)
	sweepFolder("ResourceNodes", false)
	sweepHidden()

	-- Drop tracking for anything that has been destroyed.
	for model, _ in originFolder do
		if not model.Parent then
			originFolder[model] = nil
		end
	end
end

--- Slight dimming and a blue tint, to signal that fog is active. Applied only
--- while fog is on, and reverted exactly when it goes off.
local function applyFogVisuals(enabled: boolean)
	local lighting = game:GetService("Lighting")

	if enabled then
		if savedLighting then
			return
		end
		savedLighting = {
			Brightness = lighting.Brightness,
			Ambient = lighting.Ambient,
			OutdoorAmbient = lighting.OutdoorAmbient,
		}
		lighting.Brightness = math.max(1, lighting.Brightness * 0.85)
		lighting.Ambient = Color3.new(lighting.Ambient.R * 0.8, lighting.Ambient.G * 0.8, lighting.Ambient.B * 0.9)
		lighting.OutdoorAmbient = Color3.new(
			lighting.OutdoorAmbient.R * 0.75,
			lighting.OutdoorAmbient.G * 0.75,
			lighting.OutdoorAmbient.B * 0.85
		)
		FogClientDebug:info("Applied fog of war lighting")
	else
		local saved = savedLighting
		if not saved then
			return
		end
		lighting.Brightness = saved.Brightness
		lighting.Ambient = saved.Ambient
		lighting.OutdoorAmbient = saved.OutdoorAmbient
		savedLighting = nil
		FogClientDebug:info("Reverted fog of war lighting")
	end
end

FogVisibility.start()

FogVisibility.onStateChanged(function(enabled: boolean)
	applyFogVisuals(enabled)
	if not enabled then
		revealAll()
	end
end)

task.spawn(function()
	while true do
		task.wait(SWEEP_INTERVAL)
		if FogVisibility.isEnabled() then
			local ok, err = pcall(updateVisibility)
			if not ok then
				FogClientDebug:warn(`updateVisibility failed: {tostring(err)}`)
			end
		end
	end
end)

FogClientDebug:info("FogOfWarClient initialized (idle until fog of war is enabled)")

return FogOfWarClient
