local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local GameInfo = require(ReplicatedStorage.Data.GameInfo)

local Trove = require(ReplicatedStorage.Modules.Trove)

local serverInfo: Configuration = ReplicatedStorage.ServerInfo

local localPlayer = Players.LocalPlayer
local currentCamera = workspace.CurrentCamera

local homeTeam: Team, awayTeam: Team = Teams.Home, Teams.Away


local Lib = {}

-- Server
function Lib.clampToBoundary(position: Vector3, boundary: BasePart)
    local boundaryPos = boundary.CFrame.Position
    local boundarySize = boundary.Size
    return Vector3.new(
        math.clamp(position.X, boundaryPos.X - boundarySize.X/2, boundaryPos.X + boundarySize.X/2),
        math.clamp(position.Y, boundaryPos.Y - boundarySize.Y/2, boundaryPos.Y + boundarySize.Y/2),
        math.clamp(position.Z, boundaryPos.Z - boundarySize.Z/2, boundaryPos.Z + boundarySize.Z/2)
    )
end

-- Client
function Lib.playerInGameOrPaused(player: Player?): boolean | nil
    player = player or localPlayer
    if player == nil then
        return warn("Couldn't find player!")
    end
    local gameStatus = serverInfo:GetAttribute("GameStatus")
    return (gameStatus == "InProgress" or gameStatus == "Paused" or gameStatus == "Practice") and (player.Team == homeTeam or player.Team == awayTeam)
end

function Lib.playerInGameOrPausedOrEnded(player: Player?): boolean | nil
    player = player or localPlayer
    if player == nil then
        return warn("Couldn't find player!")
    end
    local gameStatus = serverInfo:GetAttribute("GameStatus")
    return (gameStatus == "InProgress" or gameStatus == "Paused" or gameStatus == "GameEnded" or gameStatus == "Practice") and (player.Team == homeTeam or player.Team == awayTeam)
end

function Lib.getHumanoid(player: Player?): Humanoid | nil
    player = player or localPlayer
    if player == nil then
        return warn("Couldn't find player!")
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    return humanoid
end

-- Shared
function Lib.getShotVelocity(gravity: number, shotType: string, shotPower: number, shotDirection: Vector3, curveFactor: number?)
    local basePower = 50
    if shotType == "DeflectShoot" then
        basePower = 50
    end

    local multiplier = 0.5
    shotPower *= multiplier
    shotPower += basePower

    local shotVelocity = shotDirection.Unit * shotPower * GameInfo.SHOT_DISTANCE_MULTIPLIER

    local vel, angVel = shotVelocity, Vector3.zero
    if curveFactor and math.abs(curveFactor) > GameInfo.MINIMUM_CURVE_FACTOR and shotDirection.Y > 0.3 then
        if shotPower < 70 then
            curveFactor *= ((shotPower/70)^1.6)
        end

        local realCurveFactor = curveFactor - math.sign(curveFactor) * GameInfo.MINIMUM_CURVE_FACTOR
        -- print(realCurveFactor)
        local ratio = math.abs(realCurveFactor) / (GameInfo.MAXIMUM_CURVE_FACTOR - GameInfo.MINIMUM_CURVE_FACTOR)
        vel *= Vector3.new(1 - ratio*0.2, 1 - ratio*0.2, 1 - ratio*0.2)

        angVel = -Vector3.yAxis * realCurveFactor * 8
    end
    return vel, angVel
end

function Lib.getShotDirection()
    local humanoidRootPart = localPlayer.Character.HumanoidRootPart :: BasePart

    local shotDirection = (currentCamera.CFrame.Position + currentCamera.CFrame.LookVector*1000) - humanoidRootPart.CFrame.Position
    shotDirection = (shotDirection.Unit + Vector3.new(0, 0.5, 0)).Unit
    return shotDirection
end


function Lib.playerInGame(player: Player): boolean | nil
    player = player or localPlayer
    if player == nil then
        return warn("Couldn't find player!")
    end

    local gameStatus = serverInfo:GetAttribute("GameStatus")
    return (gameStatus == "InProgress" or gameStatus == "Practice") 
        and (player.Team == homeTeam or player.Team == awayTeam)
end

function Lib.playerIsStunned(player: Player?)
    player = player or localPlayer
    return player:GetAttribute("ServerChickyRagdoll") or player:GetAttribute("ServerChickyFrozen")
end


function Lib.generateShortGUID()
    local guid = HttpService:GenerateGUID(false)
    guid = guid:gsub("-", "")
    return string.lower(guid)
end


function Lib.setCooldown(instance: Instance, attribute: string, cooldown: number)
    local now = workspace:GetServerTimeNow()
    local currentCD = instance:GetAttribute(attribute)
    if currentCD and currentCD - now > cooldown then
        return
    end
    instance:SetAttribute(attribute, now + cooldown)

    local trove = Trove.new()
    trove:AttachToInstance(instance)
    trove:Add(task.delay(cooldown, function()
        trove:Destroy()
        instance:SetAttribute(attribute, nil)
    end))
    trove:Connect(instance:GetAttributeChangedSignal(attribute), function()
        trove:Destroy()
    end)
end

function Lib.removeCooldown(instance: Instance, attribute: string)
    instance:SetAttribute(attribute, nil)
end

function Lib.getCooldown(instance: Instance, attribute: string)
    local value = instance:GetAttribute(attribute)
    return value and math.max(0, value - workspace:GetServerTimeNow())
end

function Lib.isOnCooldown(instance: Instance, attribute: string, lagCompensation: number | nil)
    local value = instance:GetAttribute(attribute)
    if value and lagCompensation then
        value += lagCompensation
    end
    return value and value - workspace:GetServerTimeNow() > 0
end


function Lib.setHiddenCooldown(instance: Instance, attribute: string, cooldown: number)
    if not instance:IsA("Player") then
        return
    end
    instance = instance.HiddenAttributes.Value

    local now = workspace:GetServerTimeNow()
    local currentCD = instance:GetAttribute(attribute)
    if currentCD and currentCD - now > cooldown then
        return
    end
    instance:SetAttribute(attribute, now + cooldown)

    local trove = Trove.new()
    trove:AttachToInstance(instance)
    trove:Add(task.delay(cooldown, function()
        trove:Destroy()
        instance:SetAttribute(attribute, nil)
    end))
    trove:Connect(instance:GetAttributeChangedSignal(attribute), function()
        trove:Destroy()
    end)
end

function Lib.removeHiddenCooldown(instance: Instance, attribute: string)
    if not instance:IsA("Player") then
        return
    end
    instance = instance.HiddenAttributes.Value

    instance:SetAttribute(attribute, nil)
end

function Lib.getHiddenCooldown(instance: Instance, attribute: string)
    if not instance:IsA("Player") then
        return
    end
    instance = instance.HiddenAttributes.Value

    local value = instance:GetAttribute(attribute)
    return value and math.max(0, value - workspace:GetServerTimeNow())
end

function Lib.isOnHiddenCooldown(instance: Instance, attribute: string, lagCompensation: number | nil)
    if not instance:IsA("Player") then
        return
    end
    instance = instance.HiddenAttributes.Value

    local value = instance:GetAttribute(attribute)
    if value and lagCompensation then
        value += lagCompensation
    end
    return value and value - workspace:GetServerTimeNow() > 0
end


function Lib.getHiddenAttribute(player: Player, attribute: string)
    if not player:IsA("Player") then
        return
    end
    local hiddenAttributes = player:WaitForChild("HiddenAttributes", 3)
    if hiddenAttributes == nil then
        return
    end
    hiddenAttributes = hiddenAttributes.Value
    return hiddenAttributes:GetAttribute(attribute)
end

function Lib.setHiddenAttribute(player: Player, attribute: string, value: any)
    if not player:IsA("Player") then
        return
    end
    local hiddenAttributes = player:WaitForChild("HiddenAttributes", 3)
    if hiddenAttributes == nil then
        return
    end
    hiddenAttributes = hiddenAttributes.Value
    return hiddenAttributes:SetAttribute(attribute, value)
end

function Lib.getHiddenAttributeChangedSignal(player: Player, attribute: string)
    if not player:IsA("Player") then
        return
    end
    local hiddenAttributes = player:WaitForChild("HiddenAttributes", 3)
    if hiddenAttributes == nil then
        return
    end
    hiddenAttributes = hiddenAttributes.Value
    return hiddenAttributes:GetAttributeChangedSignal(attribute)
end

return Lib