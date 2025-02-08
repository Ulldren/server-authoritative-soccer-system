local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverInfo: Configuration = ReplicatedStorage.ServerInfo

local assets = ReplicatedStorage.Assets
local baseGUI = assets.GUI.Base

local localPlayer = Players.LocalPlayer


local Scoreboard = {}
Scoreboard.__index = Scoreboard

function Scoreboard.new()
    local self = setmetatable({}, Scoreboard)
    self.gui = baseGUI.Scoreboard:Clone()

    return self
end

function Scoreboard:Init()
    local container = self.gui.Container
    local timerFrame = container.Timer
    local function updateVisibility()
        local gameStatus = serverInfo:GetAttribute("GameStatus")
        timerFrame.Visible = gameStatus == "InProgress" or gameStatus == "Paused"
        self.gui.Enabled = not localPlayer:GetAttribute("FreecamEnabled") 
            and (gameStatus == "InProgress" or gameStatus == "Team Selection" or gameStatus == "Paused" or (gameStatus == "Practice" and localPlayer.Team.Name == "Fans")) 
    end
    updateVisibility()
    serverInfo:GetAttributeChangedSignal("GameStatus"):Connect(updateVisibility)
    localPlayer:GetPropertyChangedSignal("Team"):Connect(updateVisibility)


    local function updateTimerLabel()
        local roundTime = serverInfo:GetAttribute("RoundTime")
        roundTime = math.floor(roundTime)
        timerFrame.TextLabel.Text = tostring(roundTime)
        timerFrame.TextLabel.TextColor3 = roundTime > 10 and Color3.new(1, 1, 1) or Color3.new(1, 0, 0)
    end
    updateTimerLabel()
    serverInfo:GetAttributeChangedSignal("RoundTime"):Connect(updateTimerLabel)

    local function updateScore()
        container.Score.ScoreLabel.Text = `{serverInfo:GetAttribute("HomeScore")} - {serverInfo:GetAttribute("AwayScore")}`
    end
    updateScore()

    serverInfo:GetAttributeChangedSignal("HomeScore"):Connect(updateScore)
    serverInfo:GetAttributeChangedSignal("AwayScore"):Connect(updateScore)
end

return Scoreboard