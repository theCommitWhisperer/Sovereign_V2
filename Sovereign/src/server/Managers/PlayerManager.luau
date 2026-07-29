--!strict
-- PlayerManager: Stores and manages player game state

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local ResourcesData = require(ReplicatedStorage.Shared.GameData.ResourcesData)
local channel = DebugManager.createChannel("PlayerManager", false)

local PlayerManager = {}

export type PlayerData = {
	Player: Player,
	Faction: string?,
	SpawnPoint: CFrame?,
	GameState: string,
	Resources: { [string]: number },
	Buildings: { Instance },
	Units: { Instance },
	Keep: Instance?,
    Happiness: number?,
	-- Lobby-selected kingdom color (applied to Banner/Flag meshes on the Keep)
	BannerColor: Color3?,
}

local PlayersData: { [number]: PlayerData } = {}

function PlayerManager.get(player: Player): PlayerData?
	return PlayersData[player.UserId]
end

function PlayerManager.create(player: Player): PlayerData
	local data: PlayerData = {
		Player = player,
		Faction = nil,
		SpawnPoint = nil,
		GameState = "MainMenu",
		-- Seeded from the resource registry so EVERY resource key exists and is
		-- zeroed. addResources below only credits keys that are already present;
		-- when this was a hand-written literal, six resources (Flour, Leather,
		-- Furniture, Coal, Manuscripts, Siege_Equipment) were missing from it and
		-- every attempt to credit them was silently discarded.
		Resources = ResourcesData.buildStartingTable(),
		Buildings = {},
		Units = {},
		Keep = nil,
        Happiness = 50,
	}

	PlayersData[player.UserId] = data
	channel:info(`Created data for {player.Name}`)
	return data
end

function PlayerManager.remove(player: Player)
	local data = PlayersData[player.UserId]
	if data then
		-- Clean up buildings
		for _, building in data.Buildings do
			if building and building.Parent then
				building:Destroy()
			end
		end
		-- Clean up units
		for _, unit in data.Units do
			if unit and unit.Parent then
				unit:Destroy()
			end
		end
	end

	PlayersData[player.UserId] = nil
	channel:info(`Removed data for {player.Name}`)
end

function PlayerManager.addBuilding(player: Player, building: Instance)
	local data = PlayerManager.get(player)
	if data then
		table.insert(data.Buildings, building)
		channel:info(`Added building {building.Name} for {player.Name}`)
	end
end

function PlayerManager.addUnit(player: Player, unit: Instance)
	local data = PlayerManager.get(player)
	if data then
		table.insert(data.Units, unit)
		channel:info(`Added unit {unit.Name} for {player.Name}`)
	end
end

-- Remove a unit from player's data
function PlayerManager.removeUnit(player: Player, unit: Model)
	local playerData = PlayerManager.get(player)
	if not playerData then
		channel:warn(`No player data for {player.Name}`)
		return
	end

	-- Find and remove the unit
	for i, storedUnit in playerData.Units do
		if storedUnit == unit then
			table.remove(playerData.Units, i)
			channel:info(`Removed unit {unit.Name} from {player.Name}`)
			return
		end
	end
end

function PlayerManager.hasEnoughResources(player: Player, cost: { [string]: number }): boolean
	local data = PlayerManager.get(player)
	if not data then
		return false
	end

	for resource, amount in pairs(cost) do
		if (data.Resources[resource] or 0) < amount then
			return false
		end
	end

	return true
end

function PlayerManager.addResources(player: Player, resources: { [string]: number })
	local data = PlayerManager.get(player)
	if not data then
		return
	end

	for resource, amount in pairs(resources) do
		if data.Resources[resource] ~= nil then
			data.Resources[resource] = data.Resources[resource] + amount
		elseif ResourcesData.isValid(resource) then
			-- Registry knows it but this player's table predates it (e.g. a
			-- session that started before a hot-reload added the resource).
			data.Resources[resource] = amount
		else
			-- Genuinely unknown key: loud, because the old behaviour was to
			-- silently drop it and that hid six broken production chains.
			warn(("[PlayerManager] addResources: unknown resource %q (+%d) discarded")
				:format(tostring(resource), amount))
		end
	end
end

function PlayerManager.deductResources(player: Player, cost: { [string]: number })
	local data = PlayerManager.get(player)
	if not data then
		return
	end

	for resource, amount in pairs(cost) do
		if data.Resources[resource] then
			data.Resources[resource] = math.max(0, data.Resources[resource] - amount)
		end
	end
end

function PlayerManager.updatePlayerStats(player: Player)
    local playerData = PlayerManager.get(player)
    if not playerData then
        return
    end

    local armySize = #playerData.Units

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if RemoteEvents then
        local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
        if GameEvent then
            GameEvent:FireClient(player, "UpdatePlayerStats", {
                armySize = armySize,
            })
        end
    end
end

return PlayerManager
