local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local serverInfo: Configuration = ReplicatedStorage.ServerInfo

local TeamInfo = require(ReplicatedStorage.Data.TeamInfo)

local Lib = require(ReplicatedStorage.Lib)
local spr = require(ReplicatedStorage.Modules.spr)
local Trove = require(ReplicatedStorage.Modules.Trove)
local Quaternion = require(ReplicatedStorage.Modules.Quaternion)

local assets = ReplicatedStorage.Assets
local billboardGuis: {BillboardGui} = assets.GUI.Billboard

local localPlayer = Players.LocalPlayer

-- Load texture for mobile
assets.BallOwnerCircle:Clone().Parent = workspace.Lobby


local placeholderBallObject = Instance.new("ObjectValue")
placeholderBallObject.Name = "PlaceholderBallModel"
placeholderBallObject.Parent = localPlayer


local Knit = require(ReplicatedStorage.Packages.Knit)
Knit.OnStart():await()

local controllers = script.Parent.Parent.Controllers
local CharacterController = require(controllers.CharacterController)


local troves = {}
local function tagAdded(ball: BasePart)
    if not ball:IsDescendantOf(workspace) then
        return
    end

    local trove = Trove.new()
    trove:AttachToInstance(ball)
    trove:Add(function()
        troves[ball] = nil
    end)
    troves[ball] = trove

    local ownerCircle: MeshPart = assets.BallOwnerCircle:Clone()
    ownerCircle.Parent = ReplicatedStorage.EffectStorage
    trove:Add(ownerCircle)

    local ballOwner: ObjectValue = ball:WaitForChild("BallOwner")
    local networkOwner: ObjectValue = ball:WaitForChild("NetworkOwner")

    -- Effects
    local function updateCircleCFrame(deltaTime)
        local owner: Player = ballOwner.Value
        local character = owner
        if owner:IsA("Player") then
            local chickynoidCharacter = CharacterController.ClientModule.characters[owner.UserId]
            local characterModel = chickynoidCharacter and chickynoidCharacter.characterModel
            if characterModel == nil then
                return
            end
            character = characterModel.model
        end
        local humanoidRootPart = character and character.HumanoidRootPart
        if humanoidRootPart == nil then
            return
        end

        ownerCircle.CFrame = CFrame.new(humanoidRootPart.Position + Vector3.new(0, -2.9, 0))
    end
    local function updateBallRotation(placeholderBall: BasePart, rootMotor: Motor6D, handMotor: Motor6D)
        local owner: Player = ballOwner.Value
        if owner:GetAttribute("Position") == "Goalkeeper" then
            return
        end

        if not owner:IsA("Player") then
            return
        end

        local chickynoidCharacter = CharacterController.ClientModule.characters[owner.UserId]
        local characterModel = chickynoidCharacter and chickynoidCharacter.characterModel
        if characterModel == nil then
            return
        end

        local dataRecord = if owner == localPlayer then
            CharacterController.ClientModule.recordCustomData
        else
            chickynoidCharacter.characterData

        if dataRecord == nil then
            return
        end
        local ballRotation: Vector3 = dataRecord.ballRotation
        local w: number = dataRecord.w

        local quaternion = dataRecord.ballQuaternion or Quaternion.new(ballRotation.X, ballRotation.Y, ballRotation.Z, w)
        rootMotor.C1 = quaternion:ToCFrame(Vector3.zero)

        local leanAngle = dataRecord.leanAngle
        rootMotor.C0 = CFrame.new(0, -2.15, -2) * CFrame.new(-leanAngle.Y*2, 0, leanAngle.X)
    end
    local function updateBallMotors(placeholderBall: BasePart, rootMotor: Motor6D, handMotor: Motor6D)
        local owner: Player = ballOwner.Value
        if owner == nil then
            rootMotor.Part0 = nil
            handMotor.Part0 = nil
            return
        end

        local character = owner
        if owner:IsA("Player") then
            local chickynoidCharacter = CharacterController.ClientModule.characters[owner.UserId]
            local characterModel = chickynoidCharacter and chickynoidCharacter.characterModel
            if characterModel == nil then
                return
            end
            character = characterModel.model
        end
        if character == nil then
            return
        end

        local isGoalkeeper = character == owner or character:GetAttribute("Goalkeeper")
        rootMotor.Part0 = not isGoalkeeper and character:FindFirstChild("HumanoidRootPart") or nil
        handMotor.Part0 = isGoalkeeper and character:FindFirstChild("Right Arm") or nil
    end

    local highlightTrove = trove:Extend()
    local trail: Trail = ball:WaitForChild("Trail")
    local circleTrove = trove:Extend()
    local function ballOwnerChanged()
        highlightTrove:Clean()
        trail:Clear()
        circleTrove:Clean()

        local owner: Player = ballOwner.Value
        trail.Enabled = owner == nil
        if owner == nil then
            ball.Transparency = 0
            return
        end
            
        local ownerTeam = owner.Team
        if owner:IsA("Model") then
            ownerTeam = ownerTeam.Value
        end
        local teamInfo = TeamInfo[ownerTeam:GetAttribute("TeamName")]
        local newColor: Color3 = teamInfo.MainColor

        ownerCircle.Color = newColor


        ball.Transparency = 1
        local placeholderBall: BasePart = assets.Ball:Clone()
        placeholderBall.CanCollide = false
        placeholderBall.Anchored = false
        placeholderBallObject.Value = placeholderBall
        placeholderBall:PivotTo(ball.CFrame)
        circleTrove:Add(placeholderBall)

        local rootMotor: Motor6D = placeholderBall.RootMotor
        local handMotor: Motor6D = placeholderBall.HandMotor
        updateBallMotors(placeholderBall, rootMotor, handMotor)
        updateBallRotation(placeholderBall, rootMotor, handMotor)
        updateCircleCFrame(0)
        ball:PivotTo(placeholderBall.CFrame)

        circleTrove:Connect(RunService.RenderStepped, function(deltaTime)
            updateBallMotors(placeholderBall, rootMotor, handMotor)
            updateBallRotation(placeholderBall, rootMotor, handMotor)
            updateCircleCFrame(deltaTime)
            ball:PivotTo(placeholderBall.CFrame)
        end)

        ownerCircle.Transparency = 0.015
        ownerCircle.Parent = workspace.Effects


        local character = owner
        if owner:IsA("Player") then
            local chickynoidCharacter = CharacterController.ClientModule.characters[owner.UserId]
            local characterModel = chickynoidCharacter and chickynoidCharacter.characterModel
            if characterModel then
                character = characterModel.model
                placeholderBall.Parent = character
            else
                character = nil
            end
        else
            placeholderBall.Parent = workspace
        end

        circleTrove:Add(function()
            ownerCircle.Parent = ReplicatedStorage.EffectStorage

            if owner and owner:IsDescendantOf(game) then
                if owner == localPlayer then
                    owner:SetAttribute("BallRotation", nil)
                end
            end
        end)
    end
    task.spawn(ballOwnerChanged)
    trove:Connect(ballOwner.Changed, ballOwnerChanged)
end
local function tagRemoved(instance: Instance)
    local trove = troves[instance]
    if trove == nil then
        return
    end
    trove:Clean()
end

local TAG = "Ball"
CollectionService:GetInstanceAddedSignal(TAG):Connect(tagAdded)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(tagRemoved)
for _, instance in pairs(CollectionService:GetTagged(TAG)) do
    tagAdded(instance)
end