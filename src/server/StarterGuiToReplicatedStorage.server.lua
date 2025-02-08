local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local assets = ReplicatedStorage.Assets
local baseGUI = assets.GUI.Base


for _, gui in pairs(StarterGui:GetChildren()) do
    gui.Parent = baseGUI
end