local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")

local GameInfo = require(ReplicatedFirst:WaitForChild("GameInfo"))

local BallControllerStyle = {}
BallControllerStyle.__index = BallControllerStyle

--Gets called on both client and server
function BallControllerStyle:Setup(simulation)
    local MoveTypeDefault = require(script.Parent.Utils.MoveTypeDefault)
	MoveTypeDefault:ModifySimulation(simulation)
end

return BallControllerStyle
