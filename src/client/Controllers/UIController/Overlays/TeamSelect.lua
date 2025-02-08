local GamepadService = game:GetService("GamepadService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameService = Knit.GetService("GameService")

local Trove = require(ReplicatedStorage.Modules.Trove)
local Zone = require(ReplicatedStorage.Modules.Zone)

local trove = Trove.new()

local serverInfo: Configuration = ReplicatedStorage.ServerInfo

local assets = ReplicatedStorage.Assets
local baseGUI = assets.GUI.Base

local localPlayer = Players.LocalPlayer

local homeTeam: Team, awayTeam: Team = Teams.Home, Teams.Away


local TeamSelect = {}
TeamSelect.__index = TeamSelect

function TeamSelect.new()
    local self = setmetatable({}, TeamSelect)
    self.gui = baseGUI.TeamSelect:Clone()

    return self
end

function TeamSelect:Init()
    self:SetupButtons()

    -- local roleSelectFrame: Frame = self.gui.RoleSelect
    -- local closeButton: TextButton = roleSelectFrame.Close
    -- BaseButton(closeButton)
    -- closeButton.Activated:Connect(function()
    --     self.gui.Enabled = false
    -- end)
    

    local function checkGameStatus()
        local gameStatus = serverInfo:GetAttribute("GameStatus")
        local enabled = (gameStatus == "InProgress" or gameStatus == "Team Selection" or gameStatus == "Paused" or gameStatus == "Practice") 
        and localPlayer.Team ~= homeTeam and localPlayer.Team ~= awayTeam
        self.gui.Enabled = enabled
    end

    task.spawn(function()
        local enterZone = Zone.new(workspace.Lobby.Zones:WaitForChild("ChooseTeamEnter"))
        enterZone.localPlayerEntered:Connect(checkGameStatus)
        serverInfo:GetAttributeChangedSignal("GameStatus"):Connect(function()
            if not enterZone:findLocalPlayer() then return end
            checkGameStatus()
        end)

        local leaveZone = Zone.new(workspace.Lobby.Zones:WaitForChild("ChooseTeamLeave"))
        leaveZone.localPlayerExited:Connect(function()
            self.gui.Enabled = false
        end)
    end)
    localPlayer:GetPropertyChangedSignal("Team"):Connect(function()
        if not self.gui.Enabled then return end
        checkGameStatus()
    end)

    self.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        trove:Clean()

        -- Gamepad Navigation
        if not UserInputService.GamepadEnabled then
            return
        end
        if self.gui.Enabled then
            GamepadService:EnableGamepadCursor(self.gui.Container)
        else
            GamepadService:DisableGamepadCursor()
        end
    end)
end

function TeamSelect:SetupButtons()
    local container = self.gui.Container
    local holder = container.Main.Holder

    local homeFrame: TextButton = holder.Home
    homeFrame.Activated:Connect(function()
        self:ShowRoles("Home")
    end)
    local awayFrame: TextButton = holder.Away
    awayFrame.Activated:Connect(function()
        self:ShowRoles("Away")
    end)
end

function TeamSelect:ShowRoles(teamName: string)
    self.gui.Container.Visible = false
    self.gui.RoleSelect.Visible = true

    trove:Add(function()
        self.gui.Container.Visible = true
        self.gui.RoleSelect.Visible = false
    end)

    local roleSelectFrame: Frame = self.gui.RoleSelect

    local roleObjects = serverInfo[teamName]
    for _, roleButton: ImageButton in pairs(roleSelectFrame.Main.Roles:GetChildren()) do
        local role = roleButton.Name
        local roleObject: ObjectValue = roleObjects:FindFirstChild(role)
        local function updateRoleOccupation()
            local playerInRole: Player = roleObject.Value
            roleButton.Player.Text = playerInRole and playerInRole.Name or "No One"
            roleButton.Player.TextColor3 = playerInRole and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(126, 126, 126)
            roleButton.ImageColor3 = playerInRole and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(126, 126, 126)
        end
        updateRoleOccupation()
        trove:Connect(roleObject.Changed, updateRoleOccupation)
        trove:Connect(roleButton.Activated, function()
            GameService:SelectTeam(teamName, role)
            self.gui.Enabled = false
        end)
    end
end

return TeamSelect