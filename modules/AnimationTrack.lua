local DEFAULT_FADE_TIME = 0.100000001


local AnimationTrack = {}
AnimationTrack.__index = AnimationTrack

function AnimationTrack.new(animId, character)
    if typeof(animId) == "Instance" then
        animId = animId.AnimationId
    elseif type(animId) == "number" then
        animId = "rbxassetid://" .. animId
    end

    local self = setmetatable({}, AnimationTrack)
    self._instance = Instance.new("Animation")
    self._instance.AnimationId = animId
    
    self.character = character
    self.track = self:CreateAnimationTrack()

    return self
end


function AnimationTrack:IsPlaying()
    return self.track.IsPlaying
end

function AnimationTrack:Play(weight)
    weight = weight or 1
    self.track:Play(DEFAULT_FADE_TIME, weight)
end

function AnimationTrack:AdjustSpeed(speed)
    speed = speed or 1
    self.track:AdjustSpeed(speed)
end

function AnimationTrack:Stop()
    self.track:Stop()
end

function AnimationTrack:Destroy()
    self:Stop()
    self._instance:Destroy()
end

function AnimationTrack:GetMarkerReachedSignal(name)
    return self.track:GetMarkerReachedSignal(name)
end

function AnimationTrack:OnEnded()
    return self.track.Stopped
end


function AnimationTrack:CreateAnimationTrack()
    local humanoid: Humanoid = self.character:WaitForChild("Humanoid")
    local animator: Animator = humanoid:WaitForChild("Animator")

    return animator:LoadAnimation(self._instance)
end

return AnimationTrack