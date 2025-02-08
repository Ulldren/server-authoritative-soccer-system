local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Maid = require(ReplicatedStorage.Modules.Maid)

local maid = Maid.new()


local function Lerp(a, b, t)
    return a+(b-a)*t
end


local TweenLib = {}

function TweenLib.tweenBeamTransparency(beam: Beam, tweenInfo: TweenInfo, enabled)
    if enabled then
        beam.Enabled = true
    end

    local startTrans = beam.Transparency
    if not beam:GetAttribute("Transparency") then
        beam:SetAttribute("Transparency", startTrans)
    end

    local idxMap = {}

    local goal = beam:GetAttribute("Transparency")
    if not enabled then
        local newKeypoints = {}
        for _, keypoint: NumberSequenceKeypoint in pairs(goal.Keypoints) do
            table.insert(newKeypoints, NumberSequenceKeypoint.new(keypoint.Time, 1))
        end
        goal = NumberSequence.new(newKeypoints)
    end

    for i, keypoint in pairs(goal.Keypoints) do
        for _, startKeypoint in pairs(startTrans.Keypoints) do
            if startKeypoint.Time == keypoint.Time then
                idxMap[i] = startKeypoint
            end
        end
    end

    maid[beam] = nil

    local start = time()
    maid[beam] = RunService.RenderStepped:Connect(function()
        local now = time()
        local deltaTime = now - start

        if beam == nil then
            maid[beam] = nil
            return
        end

        local alpha = math.clamp(deltaTime / tweenInfo.Time, 0, 1)
        local tweenAlpha = TweenService:GetValue(alpha, tweenInfo.EasingStyle, tweenInfo.EasingDirection)
        
        local newKeypoints = {}
        for i, keypoint: NumberSequenceKeypoint in pairs(goal.Keypoints) do
            table.insert(newKeypoints, NumberSequenceKeypoint.new(
                keypoint.Time, 
                Lerp(idxMap[i].Value, keypoint.Value, tweenAlpha)
            ))
        end
        beam.Transparency = NumberSequence.new(newKeypoints)

        if deltaTime >= tweenInfo.Time then
            beam.Enabled = enabled
            maid[beam] = nil
            return
        end
    end)
end

return TweenLib