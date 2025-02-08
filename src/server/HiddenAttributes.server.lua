local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Trove = require(ReplicatedStorage.Modules.Trove)

local hiddenAttributeFolder = Instance.new("Folder")
hiddenAttributeFolder.Name = "HiddenAttributes"
hiddenAttributeFolder.Parent = ServerStorage


Players.PlayerAdded:Connect(function(player)
    local trove = Trove.new()
    trove:AttachToInstance(player)

    local hiddenAttributes = Instance.new("Folder")
    hiddenAttributes.Name = player.Name
    hiddenAttributes.Parent = hiddenAttributeFolder
    trove:Add(hiddenAttributes)

    local attributeObject = Instance.new("ObjectValue")
    attributeObject.Name = "HiddenAttributes"
    attributeObject.Value = hiddenAttributes
    attributeObject.Parent = player
end)