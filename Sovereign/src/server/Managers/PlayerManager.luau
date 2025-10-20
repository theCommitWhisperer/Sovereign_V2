--!strict
-- PlayerManager: Stores and manages player game state

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
		Resources = {
			Wood = 0,
			Stone = 0,
			Gold = 0,
			Food = 0,
			Weapons = 0,
			Iron_Bars = 0,
		},
		Buildings = {},
		Units = {},
		Keep = nil,
	}

	PlayersData[player.UserId] = data
	print(`[PlayerManager] Created data for {player.Name}`)
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
	print(`[PlayerManager] Removed data for {player.Name}`)
end

function PlayerManager.addBuilding(player: Player, building: Instance)
	local data = PlayerManager.get(player)
	if data then
		table.insert(data.Buildings, building)
		print(`[PlayerManager] Added building {building.Name} for {player.Name}`)
	end
end

function PlayerManager.addUnit(player: Player, unit: Instance)
	local data = PlayerManager.get(player)
	if data then
		table.insert(data.Units, unit)
		print(`[PlayerManager] Added unit {unit.Name} for {player.Name}`)
	end
end

-- Remove a unit from player's data
function PlayerManager.removeUnit(player: Player, unit: Model)
	local playerData = get(player)
	if not playerData then
		warn(`[PlayerManager] No player data for {player.Name}`)
		return
	end

	-- Find and remove the unit
	for i, storedUnit in playerData.Units do
		if storedUnit == unit then
			table.remove(playerData.Units, i)
			print(`[PlayerManager] Removed unit {unit.Name} from {player.Name}`)
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
		if data.Resources[resource] then
			data.Resources[resource] = data.Resources[resource] + amount
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

return PlayerManager
