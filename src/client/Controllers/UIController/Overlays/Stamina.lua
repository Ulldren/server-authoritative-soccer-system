local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local assets = ReplicatedStorage.Assets
local baseGUI = assets.GUI.Base

local localPlayer = Players.LocalPlayer


local Stamina = {}
Stamina.__index = Stamina

function Stamina.new()
    local self = setmetatable({}, Stamina)
    self.gui = baseGUI.Stamina:Clone()

    return self
end

function Stamina:Init()
    local bar: Frame = self.gui.Container.Bar

    local lastStamina = localPlayer:GetAttribute("Stamina") or 100
    localPlayer:GetAttributeChangedSignal("Stamina"):Connect(function()
        local maxStamina = localPlayer:GetAttribute("MaxStamina")

        local ratio = localPlayer:GetAttribute("Stamina") / maxStamina
        bar.Size = UDim2.fromScale(1, ratio)

        local currentStamina = localPlayer:GetAttribute("Stamina")
        local difference = lastStamina - currentStamina
        lastStamina = currentStamina

        if difference > 0 then
            self.gui.Enabled = true
        elseif currentStamina == localPlayer:GetAttribute("MaxStamina") then
            self.gui.Enabled = false
        end
    end)

    localPlayer.CharacterAdded:Connect(function(character)
        self:AddCharacter(character)
    end)
    if localPlayer.Character then
        task.spawn(function()
            self:AddCharacter(localPlayer.Character)
        end)
    end
end

function Stamina:AddCharacter(character)
    self.gui.Adornee = nil
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    self.gui.Adornee = humanoidRootPart
    self.gui.Enabled = false
end

return Stamina