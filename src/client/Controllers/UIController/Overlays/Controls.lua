local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lib = require(ReplicatedStorage.Lib)

local serverInfo: Configuration = ReplicatedStorage.ServerInfo

local assets = ReplicatedStorage.Assets
local baseGUI = assets.GUI.Base

local localPlayer = Players.LocalPlayer


local Controls = {}
Controls.__index = Controls

function Controls.new()
    local self = setmetatable({}, Controls)
    self.gui = baseGUI.Controls:Clone()

    return self
end

function Controls:Init()
    self.gui.Enabled = false

    local function updateVisibility()
        self.gui.Enabled = Lib.playerInGameOrPaused()
    end
    updateVisibility()
    serverInfo:GetAttributeChangedSignal("GameStatus"):Connect(updateVisibility)
    localPlayer:GetPropertyChangedSignal("Team"):Connect(updateVisibility)
end

return Controls