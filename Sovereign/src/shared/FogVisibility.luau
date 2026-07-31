--!strict
-- FogVisibility: the client's cached answer to "can I see this model?".
--
-- Before this, FogOfWarClient and HealthBarManager each answered that question
-- by calling CheckVisibility:InvokeServer() once per object, twice a second.
-- Two independent blocking round trips per unit per client -- and they ran
-- unconditionally, even though fog of war is OFF by default, so every one of
-- those round trips returned "visible" and changed nothing.
--
-- Now there is one refresh loop. It does nothing at all while fog is disabled,
-- and makes exactly one batched call when it is enabled. Callers read the cache
-- synchronously and never yield.
--
-- Lives in Shared so both StarterPlayerScripts.Client and .UI can require it;
-- neither script tree can require the other by a relative path.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FogVisibility = {}

local REFRESH_INTERVAL = 0.5

-- Folders swept for objects whose visibility might have changed. HiddenByFog is
-- included so things can come back out of it.
local SOURCE_FOLDERS = { "Units", "Buildings", "ResourceNodes" }

local fogEnabled = false
local cache: { [Model]: boolean } = {}
local listeners: { (boolean) -> () } = {}
local started = false
local checkVisibility: RemoteFunction? = nil
local hiddenFolder: Folder? = nil

--- Is fog actually on for this player? Almost always false -- it is an admin
--- toggle (/fog on) rather than a shipped default.
function FogVisibility.isEnabled(): boolean
	return fogEnabled
end

--- Synchronous, never yields. When fog is off everything is visible, which is
--- the answer the server would have given anyway.
function FogVisibility.isVisible(model: Model?): boolean
	if not fogEnabled then
		return true
	end
	if not model then
		return false
	end
	return cache[model] == true
end

--- Notified when fog is toggled, so consumers can restore hidden objects and
--- revert visual effects rather than polling for the change.
function FogVisibility.onStateChanged(callback: (boolean) -> ()): () -> ()
	table.insert(listeners, callback)
	return function()
		local index = table.find(listeners, callback)
		if index then
			table.remove(listeners, index)
		end
	end
end

function FogVisibility.getHiddenFolder(): Folder
	local folder = hiddenFolder
	if folder then
		return folder
	end
	folder = ReplicatedStorage:FindFirstChild("HiddenByFog") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "HiddenByFog"
		folder.Parent = ReplicatedStorage
	end
	hiddenFolder = folder
	return folder
end

local function setEnabled(enabled: boolean)
	if enabled == fogEnabled then
		return
	end
	fogEnabled = enabled
	if not enabled then
		table.clear(cache)
	end
	for _, listener in listeners do
		task.spawn(listener, enabled)
	end
end

--- One batched round trip for every candidate model. Returns silently on
--- failure -- a dropped refresh just means the cache is one interval stale,
--- which is far better than the old behaviour of aborting the entire sweep.
local function refresh()
	local remote = checkVisibility
	if not remote or not fogEnabled then
		return
	end

	local models: { Model } = {}
	for _, folderName in SOURCE_FOLDERS do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("Model") and child.PrimaryPart then
					table.insert(models, child)
				end
			end
		end
	end
	for _, child in FogVisibility.getHiddenFolder():GetChildren() do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end

	if #models == 0 then
		table.clear(cache)
		return
	end

	local ok, results = pcall(function()
		return remote:InvokeServer("Batch", models)
	end)
	if not ok or typeof(results) ~= "table" then
		return
	end

	local fresh: { [Model]: boolean } = {}
	for index, model in models do
		fresh[model] = results[index] == true
	end
	cache = fresh
end

function FogVisibility.start()
	if started or not RunService:IsClient() then
		return
	end
	started = true

	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
		checkVisibility = remotes:WaitForChild("CheckVisibility") :: RemoteFunction

		local gameEvent = remotes:WaitForChild("GameEvent") :: RemoteEvent
		gameEvent.OnClientEvent:Connect(function(action: string, data: any)
			if action == "FogState" and typeof(data) == "table" then
				setEnabled(data.enabled == true)
			end
		end)

		while true do
			task.wait(REFRESH_INTERVAL)
			-- While fog is off this is a single boolean check per interval and
			-- zero network traffic.
			if fogEnabled then
				local ok, err = pcall(refresh)
				if not ok then
					warn(`[FogVisibility] refresh failed: {tostring(err)}`)
				end
			end
		end
	end)
end

return FogVisibility
