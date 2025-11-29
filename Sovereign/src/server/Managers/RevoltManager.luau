--!strict
-- RevoltManager: Manages player revolts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local HappinessManager = require(script.Parent.HappinessManager)
local TaxManager = require(script.Parent.TaxManager)
local UnitManager = require(script.Parent.UnitManager)
local WorkerManager = require(script.Parent.WorkerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local RevoltDebug = DebugManager.createChannel("RevoltManager", false)

local RevoltManager = {}

local revoltData = {}

function RevoltManager.create(player: Player)
    local playerData = PlayerManager.get(player)
    if playerData then
        revoltData[player.UserId] = {
            revoltRisk = 0, -- Initial revolt risk
            lastUpdated = tick(),
        }
        RevoltDebug:info(`Created revolt data for {player.Name}`)
    end
end

function RevoltManager.get(player: Player)
    return revoltData[player.UserId]
end

function RevoltManager.calculateRevoltRisk(player: Player): number
    local risk = 0
    local playerData = PlayerManager.get(player)
    local happinessInfo = HappinessManager.get(player)
    local taxInfo = TaxManager.get(player)

    if not playerData or not happinessInfo or not taxInfo then
        return 0
    end

    -- Happiness factor (up to 50 points)
    local happiness = happinessInfo.happiness
    if happiness < 50 then
        risk = risk + (50 - happiness)
    end

    -- Tax rate factor (up to 50 points)
    local taxRate = taxInfo.taxRate
    risk = risk + (taxRate * 100) / 2

    -- Food availability factor (25 points)
    if playerData.Resources.Food == 0 then
        risk = risk + 25
    end

    return math.clamp(risk, 0, 100)
end

function RevoltManager.recordUnitLoss(player: Player)
    local revoltInfo = revoltData[player.UserId]
    if not revoltInfo then
        return
    end

    revoltInfo.revoltRisk = math.min(100, revoltInfo.revoltRisk + 1)
end

function RevoltManager.update(player: Player)
    local playerData = PlayerManager.get(player)
    local revoltInfo = revoltData[player.UserId]

    -- Only update revolt risk for players who are actually in a game
    if not revoltInfo or not playerData or playerData.GameState ~= "InGame" then
        return
    end

    revoltInfo.revoltRisk = RevoltManager.calculateRevoltRisk(player)
    revoltInfo.lastUpdated = tick()

    RevoltManager.checkRevoltStage(player)

    RevoltDebug:info(`Updated revolt risk for {player.Name} to {revoltInfo.revoltRisk}`)
end

function RevoltManager.checkRevoltStage(player: Player)
    local revoltInfo = revoltData[player.UserId]
    if not revoltInfo then
        return
    end

    local currentStage = revoltInfo.revoltStage
    local newStage = 0

    if revoltInfo.revoltRisk >= 75 then
        newStage = 3
    elseif revoltInfo.revoltRisk >= 50 then
        newStage = 2
    elseif revoltInfo.revoltRisk >= 25 then
        newStage = 1
    end

    if newStage ~= currentStage then
        revoltInfo.revoltStage = newStage
        RevoltManager.triggerRevoltStage(player, newStage)
    end
end

function RevoltManager.triggerRevoltStage(player: Player, stage: number)
    local playerData = PlayerManager.get(player)
    if not playerData then
        return
    end

    local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
    local GameEvent = RemoteEvents and RemoteEvents:FindFirstChild("GameEvent")

    if stage == 0 then
        RevoltDebug:info(`{player.Name} is stable.`)
        WorkerManager.setProductionModifier(player, 1.0) -- Restore production
        if GameEvent then
            GameEvent:FireClient(player, "RevoltEnded", {})
        end
    elseif stage == 1 then
        RevoltDebug:warn(`{player.Name} is in a state of unrest! Production efficiency reduced.`)
        WorkerManager.setProductionModifier(player, 0.9) -- 90% production
        if GameEvent then
            GameEvent:FireClient(player, "RevoltStageChanged", { stage = 1, message = "Production efficiency has dropped due to unrest!" })
        end
    elseif stage == 2 then
        RevoltDebug:warn(`{player.Name} is in a state of discontent! Production has been significantly reduced.`)
        WorkerManager.setProductionModifier(player, 0.75) -- 75% production
        if math.random() < 0.1 then
            UnitManager.destroyRandomUnit(player)
        end
        if GameEvent then
            GameEvent:FireClient(player, "RevoltStageChanged", { stage = 2, message = "Production has been significantly reduced due to discontent! A unit has deserted!" })
        end
    elseif stage == 3 then
        RevoltDebug:error(`{player.Name} is in open rebellion!`)
        WorkerManager.setProductionModifier(player, 0.5) -- 50% production

        local playerData = PlayerManager.get(player)
        if not playerData then
            return
        end

        local playerFaction = playerData.Faction or "Player"
        local rebelFaction = "Rebel_" .. player.UserId

        FactionManager.createFaction(rebelFaction)
        FactionManager.setRelationship(playerFaction, rebelFaction, "Enemy")

        -- Spawn rebel units
        local spawnPosition = playerData.SpawnPoint and playerData.SpawnPoint.Position or Vector3.new(0, 10, 0)
        for i = 1, 5 do
            UnitManager.createUnit("Swordsman", -1, spawnPosition + Vector3.new(math.random(-20, 20), 0, math.random(-20, 20)), rebelFaction)
        end

        if GameEvent then
            GameEvent:FireClient(player, "RevoltStageChanged", { stage = 3, message = "A rebellion has begun!" })
        end
    end
end

function RevoltManager.init()
    Players.PlayerAdded:Connect(RevoltManager.create)
end

return RevoltManager