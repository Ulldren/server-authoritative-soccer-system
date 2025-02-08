local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Sound = {}

function Sound.play(id, positionOrPart, volume)
    volume = volume or 1

    local sound
    if typeof(id) == "Instance" and id:IsA("Sound") then
        sound = id:Clone()
        if sound.SoundId == "" then
            sound.SoundId = sound:GetAttribute("SoundId")
        end
    else
        if tonumber(id) == id then
            id = "rbxassetid://".. tostring(id)
        end
        sound = Instance.new("Sound")
        sound.SoundId = id
        sound.Volume = volume
    end

    local attachment = Instance.new("Attachment")
    sound.Parent = attachment
    if typeof(positionOrPart) == "Vector3" then
        attachment.WorldPosition = positionOrPart
        attachment.Parent = workspace.Terrain
    elseif typeof(positionOrPart) == "Instance" then
        attachment.Parent = positionOrPart
    end

    local soundDelay = sound:GetAttribute("PlayDelay")
    if soundDelay and soundDelay > 0 then
        task.wait(soundDelay)
    end
    sound:Play()
    
    local fadeDelay = sound:GetAttribute("FadeDelay")
    if fadeDelay then
        task.delay(fadeDelay, function()
            local fadeTime = sound:GetAttribute("FadeTime") or 1
            TweenService:Create(sound, TweenInfo.new(fadeTime), {
                Volume = 0,
            }):Play()
        end)
    end

    sound.Ended:Connect(function()
        attachment:Destroy()
    end)
    return sound
end

function Sound.playInReplicatedStorage(sound: Sound, volume)
    volume = volume or 1

    sound = sound:Clone()
    if sound.SoundId == "" then
        sound.SoundId = sound:GetAttribute("SoundId") 
    end
    sound.Parent = ReplicatedStorage.EffectStorage

    local soundDelay = sound:GetAttribute("PlayDelay")
    if soundDelay and soundDelay > 0 then
        task.delay(soundDelay, function()
            sound:Play()
        end)
    else
        sound:Play()
    end
    
    local fadeDelay = sound:GetAttribute("FadeDelay")
    if fadeDelay then
        task.delay(fadeDelay, function()
            local fadeTime = sound:GetAttribute("FadeTime") or 1
            TweenService:Create(sound, TweenInfo.new(fadeTime), {
                Volume = 0,
            }):Play()
        end)
    end
    
    sound.Ended:Connect(function()
        sound:Destroy()
    end)

    local despawnTime = sound:GetAttribute("DespawnTime")
    if despawnTime == nil and sound.Looped then
        despawnTime = 10
    end
    if despawnTime then
        game.Debris:AddItem(sound, despawnTime)
    end

    return sound
end

return Sound