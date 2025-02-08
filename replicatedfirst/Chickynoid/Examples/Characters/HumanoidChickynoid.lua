local ReplicatedFirst = game:GetService("ReplicatedFirst")

local GameInfo = require(ReplicatedFirst:WaitForChild("GameInfo"))

local ChickynoidStyle = {}
ChickynoidStyle.__index = ChickynoidStyle

--Gets called on both client and server
function ChickynoidStyle:Setup(simulation)
    simulation.state.stam = GameInfo.MAX_STAMINA
    simulation.state.stamRegCD = 0
    simulation.state.dive = 0
    simulation.state.tackle = 0
    simulation.state.sprint = 0
    

    local MoveTypeWalking = require(script.Parent.Utils.MoveTypeWalking)
	MoveTypeWalking:ModifySimulation(simulation)

    local MoveTypeTackle = require(script.Parent.Utils.MoveTypeTackle)
	MoveTypeTackle:ModifySimulation(simulation)

    local MoveTypeDive = require(script.Parent.Utils.MoveTypeDive)
	MoveTypeDive:ModifySimulation(simulation)

    local MoveTypeRagdoll = require(script.Parent.Utils.MoveTypeRagdoll)
	MoveTypeRagdoll:ModifySimulation(simulation)
end

return ChickynoidStyle
