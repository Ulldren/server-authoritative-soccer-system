local Constraints = {}

function Constraints.motor6D(p0, p1, name)
	local motor = Instance.new("Motor6D")
	motor.Part0 = p0
	motor.Part1 = p1
	motor.Name  = name or p1.Name
	motor.Parent = p0

	return motor
end

function Constraints.weldConstraint(p0, p1, name)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = p0
	weld.Part1 = p1
	weld.Name  = name or p1.Name
	weld.Parent = p0

	return weld
end

function Constraints.weld(p0, p1, name)
	local weld = Instance.new("Weld")
	weld.Part0 = p0
	weld.Part1 = p1
	weld.Name  = name or p1.Name
	weld.Parent = p0
	
	return weld
end

return Constraints