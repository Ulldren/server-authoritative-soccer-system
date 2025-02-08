local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local privateServerInfo: Configuration = ReplicatedStorage.PrivateServerInfo

local assets = ReplicatedStorage.Assets
local baseGUI = assets.GUI.Base

local localPlayer = Players.LocalPlayer


local PowerBar = {}
PowerBar.__index = PowerBar

function PowerBar.new()
    local self = setmetatable({}, PowerBar)
    self.gui = baseGUI.PowerBar:Clone()

    return self
end

function PowerBar:Init()
    self.gui.Enabled = false

    local container = self.gui.Container

    local lastPower = 0
    localPlayer:GetAttributeChangedSignal("ShotPower"):Connect(function()
        local ratio = localPlayer:GetAttribute("ShotPower") / privateServerInfo:GetAttribute("MaxShotPower")
        ratio = math.min(1, ratio)
        container.Background.Bar.Size = UDim2.fromScale(ratio, 1)

        local currentPower = localPlayer:GetAttribute("ShotPower")
        local difference = currentPower - lastPower
        lastPower = currentPower
        self.gui.Enabled = difference > 0
    end)
end

return PowerBar