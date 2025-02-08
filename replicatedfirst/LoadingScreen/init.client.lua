local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer.PlayerGui

local loadingGui: ScreenGui = script:WaitForChild("LoadingScreen")
loadingGui.Parent = playerGui

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)


ContextActionService:BindAction("FreezeInputs", function()
    return Enum.ContextActionResult.Sink
end, false, unpack(Enum.PlayerActions:GetEnumItems()))

local function checkFullyLoaded()
	for _, loaded in pairs(loadingGui:GetAttributes()) do
        if not loaded then
            return
        end
    end
    loadingGui:Destroy()
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)

    ContextActionService:UnbindAction("FreezeInputs")

    localPlayer:SetAttribute("ClientLoaded", true)

    script:Destroy()
end

localPlayer.CharacterAdded:Connect(function()
    loadingGui:SetAttribute("Character", true)
end)

if not game:IsLoaded() then
    game.Loaded:Wait()
end
for attributeName in pairs(loadingGui:GetAttributes()) do
    loadingGui:GetAttributeChangedSignal(attributeName):Connect(function()
        print(attributeName .. " loaded!")
        checkFullyLoaded()
    end)
end