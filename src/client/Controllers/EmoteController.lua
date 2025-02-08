local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local EmoteService

local controllers = script.Parent
local CharacterController = require(controllers.CharacterController)

local Trove = require(ReplicatedStorage.Modules.Trove)

local assets = ReplicatedStorage.Assets
local animations = assets.Animations

local localPlayer = Players.LocalPlayer


local EmoteController = {
    Name = "EmoteController"
}

function EmoteController:KnitInit()

end

function EmoteController:EmoteChanged(trove: typeof(Trove), player, character, endEmoteCallback: (string) -> ()?, looped: boolean?)
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

    local humanoid: Humanoid = character:FindFirstChild("Humanoid")
    local animator: Animator = humanoid:FindFirstChild("Animator")

    local emoteData = character:GetAttribute("EmoteData")
    local oldEmoteData = emoteData

    trove:Clean()
    if emoteData == nil then
        return
    end

    emoteData = HttpService:JSONDecode(emoteData)
    local emote = emoteData[1]
    if emote == nil then
        return
    end

    local canWalk = emoteData[4]
    if character == localPlayer.Character and not canWalk then
        trove:Connect(localPlayer:GetAttributeChangedSignal("EndEmote"), function()
            local emoteGUID = emoteData[2]
            EmoteService:EndEmote(emoteGUID)
            trove:Clean()
        end)

        local playerModule = localPlayer.PlayerScripts:FindFirstChild("PlayerModule")
        if playerModule then
            playerModule = require(playerModule)
            local movementController = playerModule:GetControls():GetActiveController()
            movementController:Enable(false)
            movementController:Enable(true)
        end
    end


    if oldEmoteData ~= character:GetAttribute("EmoteData") then
        return
    end
    
    local animation = animations.Emotes:FindFirstChild(emote, true)
    if animation == nil or not animation:IsA("Animation") then
        warn("Couldn't find animation for emote: " .. emote)
        return
    end
    local emoteAnim = animator:LoadAnimation(animation)
    emoteAnim.Priority = Enum.AnimationPriority.Action2
    emoteAnim:Play()
    if looped ~= nil then
        emoteAnim.Looped = looped
    end
    trove:Add(function()
        emoteAnim:Stop()
    end)

    if player == localPlayer and endEmoteCallback then
        trove:Connect(emoteAnim.Ended, function()
            local emoteGUID = emoteData[2]
            EmoteService:EndEmote(emoteGUID)
        end)
    end
    if player == nil and endEmoteCallback then
        trove:Connect(emoteAnim.Stopped, endEmoteCallback)
    end

    if emote == "Dance" then
        local characterScale = humanoidRootPart.Size.Y/2
        
        local discoBall = Instance.new("Part")
        discoBall.Name = 'DiscoBall'
        discoBall.Locked = true
        discoBall.FormFactor = Enum.FormFactor.Symmetric
        discoBall.Shape = Enum.PartType.Ball
        discoBall.Size = Vector3.new(1, 1, 1) * 4 * characterScale
        discoBall.TopSurface = Enum.SurfaceType.Smooth
        discoBall.BottomSurface = Enum.SurfaceType.Smooth
        for _, enum in next, Enum.NormalId:GetEnumItems() do
            local decal = Instance.new'Decal'
            decal.Parent = discoBall
            decal.Texture = 'http://www.roblox.com/asset/?id=27831454'
            decal.Face = enum
        end
        discoBall.Position = humanoidRootPart.CFrame.Position + Vector3.new(0, 5, 0) * characterScale -- account for different body sizes

        local discoSparkles = Instance.new('Sparkles')
        discoSparkles.Parent = discoBall
        local bodyPos = Instance.new('BodyPosition')
        bodyPos.Position = humanoidRootPart.CFrame.Position + Vector3.new(0, 8, 0) * characterScale
        bodyPos.P = 10000
        bodyPos.D = 1000
        bodyPos.maxForce = Vector3.new(1, 1, 1) * bodyPos.P
        bodyPos.Parent = discoBall
        trove:Connect(RunService.Heartbeat, function()
            local rootPos = humanoidRootPart.CFrame.Position
            discoBall.Position = Vector3.new(rootPos.X, discoBall.CFrame.Position.Y, rootPos.Z)
        end)

        local bodyAngularVelocity = Instance.new('BodyAngularVelocity')
        bodyAngularVelocity.P = 100000
        bodyAngularVelocity.angularvelocity = Vector3.new(0, 1000, 0)
        bodyAngularVelocity.maxTorque = Vector3.new(1, 1, 1)*bodyAngularVelocity.P
        bodyAngularVelocity.Parent = discoBall
        
        discoBall.Parent = workspace
        trove:Add(discoBall)
        
        local song = Instance.new("Sound")
        song.SoundId = "http://www.roblox.com/asset/?id=27808972"
        song.Volume = 2
        song.Looped = true
        song.Parent = humanoidRootPart
        song:Play()

        trove:Add(song)
    end
end

function EmoteController:KnitStart()
    EmoteService = Knit.GetService("EmoteService")

    local function characterAdded(character)
        local trove = Trove.new()
        trove:AttachToInstance(character)

        local userid = character:GetAttribute("userid")
        if userid == nil then
            return
        end
        local player = Players:GetPlayerByUserId(userid)
        if player == nil then
            return
        end

        character:GetAttributeChangedSignal("EmoteData"):Connect(function()
            self:EmoteChanged(trove, player, character)
        end)
        self:EmoteChanged(trove, player, character)
    end

    
    local clientModule = CharacterController.ClientModule
    for _, player in pairs(Players:GetPlayers()) do
        local chickynoidCharacter = clientModule.characters[player.UserId]
        local characterModel = chickynoidCharacter and chickynoidCharacter.characterModel
        if characterModel == nil then
            continue
        end
        local character = characterModel.model
        if character == nil or not character:IsDescendantOf(workspace) then
            continue
        end
        task.spawn(function()
            characterAdded(character)
        end)
    end
    clientModule.OnCharacterModelCreated:Connect(function(characterModel)
        task.spawn(function()
            characterAdded(characterModel.model)
        end)
    end)
end

return EmoteController