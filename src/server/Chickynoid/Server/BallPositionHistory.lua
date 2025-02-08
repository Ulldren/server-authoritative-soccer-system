local RunService = game:GetService("RunService")
--!native
local module = {}
module.history = {}
module.temporaryPositions = {}

local path = game.ReplicatedFirst.Chickynoid
local Enums = require(path.Shared.Enums)

function module:Setup(server)
    module.server = server
end

function module:WriteBallPosition(serverTime)
    local snapshot = {}
    snapshot.serverTime = serverTime
    local ballRecord = self.server.ballRecord
    local ballController = ballRecord.ballController
    if ballRecord.ballController then
        snapshot.claimCooldown = ballController:isOnCooldown("ClaimCooldown")
        snapshot.lagSaveLeniency = ballController:getAttribute("LagSaveLeniency")
        snapshot.ballPos = ballController.simulation.ballData:GetPosition()
    end

    table.insert(self.history, snapshot)

    for counter = #self.history, 1, -1 do
        local oldSnapshot = self.history[counter]

        --only keep 1s of history
        if oldSnapshot.serverTime < serverTime - 1 then
            table.remove(self.history, counter)
        end
    end
end

function module:GetPreviousPosition(serverTime, position: Vector3)
    --find the two records
    for counter = #self.history - 1, 1, -1 do
        local record = self.history[counter]
        local previousRecord = self.history[counter - 1] or {}
        if (record.ballPos - position).Magnitude < 0.001 then
            return record.ballPos, record.claimCooldown, previousRecord.ballPos, record.lagSaveLeniency
        end
    end

    if RunService:IsStudio() then
        -- warn("Could not find antilag time for ", serverTime)
    end
end

function module:Pop()
    local ballRecord = self.server.ballRecord
    local ballController = ballRecord.ballController
    if ballController then
        if ballController.hitBox then
            ballController.hitBox.Position = self.temporaryPosition
        end
    end

    self.temporaryPosition = nil
end

return module
