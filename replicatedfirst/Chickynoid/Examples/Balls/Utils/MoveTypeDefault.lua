local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local IsClient = RunService:IsClient()

local module = {}

local localPlayer = Players.LocalPlayer

local path = game.ReplicatedFirst.Chickynoid
local MathUtils = require(path.Shared.Simulation.MathUtils)
local Enums = require(path.Shared.Enums)
local Quaternion = require(path.Shared.Simulation.Quaternion)

local GameInfo = require(game.ReplicatedFirst.GameInfo)

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include


--Call this on both the client and server!
function module:ModifySimulation(simulation)
    simulation:RegisterMoveState("Ball", self.ActiveThink, self.AlwaysThink, nil, nil)
    simulation:SetMoveState("Ball")
end

function module.AlwaysThink(simulation, cmd)
    
end

--Imagine this is inside Simulation...
function module.ActiveThink(simulation, cmd, server, doCollisionEffects)
    if simulation.state.pos.Magnitude < 1 then
        return
    end


    local ownerId: number | Model = simulation.state.ownerId
    local netId: number | Model = simulation.state.netId

    if not simulation.ballData.isResimulating then
        if IsClient then
            local ballModel = localPlayer.BallModel.Value

            if type(ownerId) == "number" then
                local owner = Players:GetPlayerByUserId(ownerId)
                ballModel.BallOwner.Value = owner
                if owner then
                    owner.Ball.Value = ballModel
                    simulation.state.pos = ballModel.CFrame.Position
                end
            elseif ownerId ~= nil then
                local humanoidRootPart = ownerId:FindFirstChild("HumanoidRootPart")
                if humanoidRootPart then
                    ballModel.BallOwner.Value = ownerId
                    local playerCF = humanoidRootPart.CFrame
                    simulation.state.pos = (playerCF * CFrame.new(0, -1.65, -2)).Position
                end
            end
            local ballOwner = ballModel.BallOwner.Value
            ballModel.Transparency = if ballOwner ~= nil then 1 else 0
        else
            if type(ownerId) == "number" then
                local playerRecord = server:GetPlayerByUserId(ownerId)
                if playerRecord then
                    simulation.state.vel = Vector3.zero
                    simulation.state.angVel = Vector3.zero

                    local playerSimulation = playerRecord.chickynoid.simulation
                    local playerCF = CFrame.new(playerSimulation.state.pos) * CFrame.Angles(0, playerSimulation.state.angle, 0)
                    simulation.state.pos = (playerCF * CFrame.new(0, -1.65, -2)).Position
                else
                    simulation.state.ownerId = 0
                end
            elseif ownerId ~= nil then
                simulation.state.vel = Vector3.zero
                simulation.state.angVel = Vector3.zero

                local humanoidRootPart = ownerId:FindFirstChild("HumanoidRootPart")
                if humanoidRootPart then
                    local playerCF = humanoidRootPart.CFrame
                    simulation.state.pos = (playerCF * CFrame.new(0, -1.65, -2)).Position
                else
                    simulation.state.ownerId = 0
                end
            end
            if type(netId) == "number" and server:GetPlayerByUserId(netId) == nil then
                simulation.state.netId = 0
            end
        end
    end

    if ownerId ~= 0 then
        return
    end


    local deltaTime = cmd.deltaTime or 1/60

    local quaternion = simulation.rotation
    local newPos, newVel, newAngularVel, newQuaternion, hitPlayer, hitNet = simulation:ProjectVelocity(simulation.state.pos, simulation.state.vel, simulation.state.angVel, quaternion, deltaTime, doCollisionEffects)
    local moveDelta = (newPos - simulation.state.pos).Magnitude

    simulation.state.pos = newPos
    simulation.state.vel = newVel
    simulation.state.angVel = newAngularVel
    simulation.rotation = newQuaternion

    if not hitPlayer and not simulation.ballData.isResimulating then
        if IsClient then
            local radius = 1
            
            local character = localPlayer.Character
            local humanoidRootPart = character and character.HumanoidRootPart
            if humanoidRootPart and (humanoidRootPart.CFrame.Position - newPos).Magnitude < 10 then
                local filter = {character}
                local diveHitBox: BasePart?

                local Lib = require(ReplicatedStorage.Lib)
                if localPlayer:GetAttribute("Position") == "Goalkeeper" and Lib.isOnCooldown(localPlayer, "ClientDiveEnd") then
                    local diveHitboxTemplate = ReplicatedStorage.Assets.Hitboxes.Dive:FindFirstChild(localPlayer:GetAttribute("ClientDiveHitbox"))
                    if diveHitboxTemplate then
                        diveHitBox = diveHitboxTemplate:Clone()
                        diveHitBox:PivotTo(humanoidRootPart.CFrame)
                        diveHitBox.Parent = workspace
                        table.insert(filter, diveHitBox)
                    end
                end
                
                overlapParams.FilterDescendantsInstances = filter
                
                local foundCharacter = workspace:GetPartBoundsInRadius(newPos, radius, overlapParams)
                if diveHitBox then
                    diveHitBox:Destroy()
                end
                if foundCharacter[1] then
                    hitPlayer = true
                end
            end
        else
            local Lib = require(ReplicatedStorage.Lib)

            local filter = {}
            local characterHitBoxFilter = CollectionService:GetTagged("ServerCharacterHitbox")
            for _, character: Model in pairs(characterHitBoxFilter) do
                local userId = character:GetAttribute("player")
                if userId == simulation.state.netId then continue end
                local player = Players:GetPlayerByUserId(userId)
                if player == nil then continue end
                if Lib.isOnCooldown(player, "BallClaimCooldown")
                or not Lib.playerInGame(player) or Lib.playerIsStunned(player) then
                    continue
                end
                table.insert(filter, character)
            end
            table.insert(filter, CollectionService:GetTagged("Goalkeeper"))
            overlapParams.FilterDescendantsInstances = filter
                
            local characters = workspace:GetPartBoundsInRadius(newPos, 1, overlapParams)
            for _, character in pairs(characters) do
                local userId = character:GetAttribute("player")
                if userId == nil then
                    character = character.Parent
                    if character:HasTag("Goalkeeper") then
                        hitPlayer = character
                        break
                    end
                    continue
                end
                if userId == simulation.state.netId then continue end
                local player = Players:GetPlayerByUserId(userId)
                if player:GetAttribute("Position") == "Goalkeeper" then -- Goalkeeper has priority over others
                    hitPlayer = character
                    break
                elseif hitPlayer == nil and moveDelta > 0.01 then  -- if barely moving, don't do server claim detection
                    hitPlayer = character
                end
            end
        end
    end
    return hitPlayer, hitNet, moveDelta
end

return module