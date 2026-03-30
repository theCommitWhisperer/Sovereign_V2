local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("GameEvent")

local settings = {
    vikingRaids = false,
    peaceTime = "None",
    selectedMap = "ClassicPlains",
    showTutorial = false,
    startingResources = "Standard",
    startingGold = "Standard",
    startingFood = "Standard",
    startingTroops = "None"
}

GameEvent:FireServer("StartGame", settings)
print("Fired StartGame event to the server.")
