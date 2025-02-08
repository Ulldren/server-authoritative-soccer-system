local Players = game:GetService("Players")


local function addPlayer(player: Player)
    local ballObject = Instance.new("ObjectValue")
    ballObject.Name = "Ball"
    ballObject.Parent = player
    
    local conn: RBXScriptConnection?
    ballObject:GetPropertyChangedSignal("Parent"):Connect(function()
        if conn then
            conn:Disconnect()
            conn = nil
        end
    end)
    ballObject.Changed:Connect(function(ball: BasePart | nil)
        if conn then
            conn:Disconnect()
            conn = nil
        end
        if ball == nil then
            return
        end
        conn = ball.BallOwner.Changed:Connect(function(newOwner: Player | nil)
            if newOwner == player then return end
            ballObject.Value = nil
        end)
    end)
end

Players.PlayerAdded:Connect(addPlayer)
for _, player in pairs(Players:GetPlayers()) do
    addPlayer(player)
end