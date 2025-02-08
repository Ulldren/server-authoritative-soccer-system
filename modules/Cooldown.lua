local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Modules.Signal)


local Cooldown = {}
Cooldown.__index = Cooldown

function Cooldown.new(initial)
	local self = setmetatable({}, Cooldown)
    self.cooldown = initial
	self._time = os.clock() - initial

	self.CooldownUpdated = Signal.new()

	return self
end

function Cooldown:IsFinished()
	local now = os.clock()
	return now - self._time >= self.cooldown
end

function Cooldown:Update()
	local now = os.clock()
	self._time = now

	self.CooldownUpdated:Fire()
end

function Cooldown:SetNewCooldown(cooldown)
	cooldown = cooldown or self.cooldown

	self._time = os.clock()
	self.cooldown = cooldown
end

function Cooldown:GetRemainingTime()
	local delta = os.clock() - self._time
	return math.clamp(self.cooldown - delta, 0, self.cooldown)
end

function Cooldown:Finish()
	self._time = os.clock() - self.cooldown
end

return Cooldown
