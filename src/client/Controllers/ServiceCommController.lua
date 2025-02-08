local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)

local localPlayer = Players.LocalPlayer
local currentCamera = workspace.CurrentCamera


local ServiceCommController = {
    Name = "ServiceCommController"
}

function ServiceCommController:KnitStart()
    local controllers = script.Parent
    local CharacterController = require(controllers.CharacterController)

    local GameService = Knit.GetService("GameService")

    local function onTp(freezeCFrame: CFrame, disableShiftLock: boolean)
        if disableShiftLock then
            CharacterController:ToggleShiftLock(false)
        end
    
        if freezeCFrame ~= nil then
            local character = localPlayer.Character
            local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.CFrame.Position) * freezeCFrame.Rotation
            end
    
            local _, yRot, _ = freezeCFrame:ToEulerAnglesYXZ()
            local x, _, z = currentCamera.CFrame:ToEulerAnglesYXZ()
            currentCamera.CFrame = CFrame.new(currentCamera.CFrame.Position) * CFrame.fromEulerAnglesYXZ(x, yRot, z) 
    
            localPlayer:SetAttribute("DisableFollowCamera", true)
            task.delay(0.5, function()
                localPlayer:SetAttribute("DisableFollowCamera", nil)
            end)
        end
    
        localPlayer:SetAttribute("Stamina", localPlayer:GetAttribute("MaxStamina"))
    end
    GameService.InstantTeleport:Connect(onTp)
    GameService.PlayerTeleported:Connect(function(freezeCFrame: CFrame, disableShiftLock: boolean)
        task.wait(1.25)
        onTp(freezeCFrame, disableShiftLock)
    end)
end

return ServiceCommController