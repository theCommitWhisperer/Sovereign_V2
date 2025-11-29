--!strict
-- NotificationManager: Sends important economy notifications to players

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local NotificationDebug = DebugManager.createChannel("NotificationManager", false)

local NotificationManager = {}

export type NotificationType = "warning" | "alert" | "info" | "success" | "critical"

export type Notification = {
	type: NotificationType,
	title: string,
	message: string,
	timestamp: number,
}

-- Track notification history per player
local notificationHistory = {}

-- Send a notification to a player
function NotificationManager.send(player: Player, notifType: NotificationType, title: string, message: string)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	local notification: Notification = {
		type = notifType,
		title = title,
		message = message,
		timestamp = tick(),
	}

	-- Store in history
	if not notificationHistory[player.UserId] then
		notificationHistory[player.UserId] = {}
	end
	table.insert(notificationHistory[player.UserId], notification)

	-- Keep only last 20 notifications
	if #notificationHistory[player.UserId] > 20 then
		table.remove(notificationHistory[player.UserId], 1)
	end

	-- Send to client
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
		if GameEvent then
			GameEvent:FireClient(player, "EconomyNotification", notification)
		end
	end

	NotificationDebug:info(`Sent {notifType} to {player.Name}: {title}`)
end

-- Convenience functions for different notification types
function NotificationManager.warning(player: Player, title: string, message: string)
	NotificationManager.send(player, "warning", title, message)
end

function NotificationManager.alert(player: Player, title: string, message: string)
	NotificationManager.send(player, "alert", title, message)
end

function NotificationManager.info(player: Player, title: string, message: string)
	NotificationManager.send(player, "info", title, message)
end

function NotificationManager.success(player: Player, title: string, message: string)
	NotificationManager.send(player, "success", title, message)
end

function NotificationManager.critical(player: Player, title: string, message: string)
	NotificationManager.send(player, "critical", title, message)
end

-- Get notification history for a player
function NotificationManager.getHistory(player: Player): { Notification }
	return notificationHistory[player.UserId] or {}
end

-- Initialize the notification system
function NotificationManager.init()
	NotificationDebug:info("NotificationManager initialized")
end

return NotificationManager
