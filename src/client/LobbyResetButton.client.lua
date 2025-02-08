local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Knit = require(ReplicatedStorage.Packages.Knit)
Knit.OnStart():await()
local GameService = Knit.GetService("GameService")

local localPlayer = Players.LocalPlayer


localPlayer.Idled:Connect(function()
    if localPlayer:GetAttribute("Position") ~= "Goalkeeper" then return end
    GameService:ResetBackToLobby()
end)


local bindableEvent = Instance.new("BindableEvent")
bindableEvent.Event:Connect(function()
    GameService:ResetBackToLobby()
end)
repeat
    local success = pcall(function()
        StarterGui:SetCore("ResetButtonCallback", bindableEvent)
    end)
    task.wait()
until success