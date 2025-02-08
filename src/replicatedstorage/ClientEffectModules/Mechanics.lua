local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer


local Mechanics = {}

function Mechanics.ballKicked(effectInfo)
    local ballModel = localPlayer:FindFirstChild("BallModel")
    if ballModel then
        local ball: BasePart = ballModel.Value
        ball.KickSound:Play()
    end
end

return Mechanics