local ContextActionService = game:GetService("ContextActionService")
local GamepadService = game:GetService("GamepadService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local EmoteService = Knit.GetService("EmoteService")

local Keybinds = require(ReplicatedStorage.Data.Keybinds)

local assets = ReplicatedStorage.Assets
local baseGUI = assets.GUI.Base

local localPlayer = Players.LocalPlayer


local EmoteWheel = {}
EmoteWheel.__index = EmoteWheel

EmoteWheel.gui = nil :: ScreenGui?

function EmoteWheel.new()
    local self = setmetatable({}, EmoteWheel)
    self.gui = baseGUI.EmoteWheel:Clone()

    return self
end

function EmoteWheel:Init()
    local container = self.gui.Container
    for _, slotButton: TextButton in pairs(container.Slots:GetChildren()) do
        self:AddEmoteSlot(slotButton) 
    end

    ContextActionService:BindActionAtPriority("Emote", function(_, inputState)
        if inputState == Enum.UserInputState.Begin then 
            local character = localPlayer.Character
            local emoteData = character and character:GetAttribute("EmoteData")
            if emoteData then
                emoteData = HttpService:JSONDecode(emoteData)
                local emote = emoteData[1]
                if emote then
                    local emoteGUID = emoteData[2]
                    EmoteService:EndEmote(emoteGUID)
                    return
                end
            end
            self.gui.Enabled = not self.gui.Enabled
        end
    end, false, 1, Keybinds.PC.Emote, Keybinds.Console.Emote)

    -- Gamepad Navigation
    if not UserInputService.GamepadEnabled then
        return
    end
    self.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if self.gui.Enabled then
            GamepadService:EnableGamepadCursor(container.Slots['1'])
        else
            GamepadService:DisableGamepadCursor() 
        end
    end)
end

function EmoteWheel:AddEmoteSlot(slotButton: TextButton)
    local slotNumber = tonumber(slotButton.Name)
    slotButton.Activated:Connect(function()
        self.gui.Enabled = false
        EmoteService:UseEmote(slotNumber)
    end)
end

return EmoteWheel