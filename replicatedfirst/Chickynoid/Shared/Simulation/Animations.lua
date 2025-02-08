local module = {}

module.animations = {}		--num, string
module.reverseLookups = {} --string, num
	
function module:RegisterAnimation(name : string)
	if (self.reverseLookups[name] ~= nil) then
		return self.reverseLookups[name]
	end
	
	table.insert(self.animations, name)
	local index = #self.animations
	self.reverseLookups[name] = index	
end

function module:GetAnimationIndex(name : string) : number
	return self.reverseLookups[name]
end

function module:GetAnimation(index : number) : string
	return self.animations[index]
end

function module:SetAnimationsFromWorldState(animations : any)
	
	self.animations = animations
	self.reverseLookups = {}
	for key,value in self.animations do
		self.reverseLookups[value] = key 
	end
end

function module:ServerSetup()
	
	--Register some default animations
	self:RegisterAnimation("Stop")
	self:RegisterAnimation("Idle")
	self:RegisterAnimation("Walk")
	self:RegisterAnimation("Push")
	self:RegisterAnimation("Jump")
	self:RegisterAnimation("Fall")

	self:RegisterAnimation("Sprint")

	self:RegisterAnimation("ChargeShot")
	self:RegisterAnimation("RequestBall")
	self:RegisterAnimation("Shoot")
	self:RegisterAnimation("Skill")
	self:RegisterAnimation("SlideTackle")

	self:RegisterAnimation("FrontDive")
	self:RegisterAnimation("RightDive")
	self:RegisterAnimation("LeftDive")

	self:RegisterAnimation("StunLand")
	self:RegisterAnimation("StunIdle")
	self:RegisterAnimation("StunFlip")
end

return module
