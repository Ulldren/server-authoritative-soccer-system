--!native
--[=[
    @class BallSimulation
    BallSimulation handles physics for characters on both the client and server.
]=]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local IsClient = RunService:IsClient()

local localPlayer = Players.LocalPlayer

local BallSimulation = {}
BallSimulation.__index = BallSimulation

local CollisionModule = require(script.Parent.CollisionModule)
local BallData = require(script.Parent.BallData)
local MathUtils = require(script.Parent.MathUtils)
local Enums = require(script.Parent.Parent.Enums)
local DeltaTable = require(script.Parent.Parent.Vendor.DeltaTable)
local Quaternion = require(script.Parent.Quaternion)


function BallSimulation.new(ballId)
    local self = setmetatable({}, BallSimulation)

    self.ballId = ballId

    self.moveStates = {}
	self.moveStateNames = {}
	self.executionOrder = {}

    self.state = {}

    self.state.pos = Vector3.new(0, 0, 0)
    self.state.vel = Vector3.new(0, 0, 0)
    self.state.angVel = Vector3.new(0, 0, 0)
    self.state.ownerId = 0
    self.state.netId = 0
    self.state.guid = 1
    self.state.action = 0
    self.state.framesToGoal = nil
    self.state.refFrame = nil

    self.state.moveState = 0

    self.state.curve = 0

    self.ballData = BallData.new()

    self.constants = {}
    self.constants.elasticity = 0.4
    self.constants.gravity = -153.7 -- adjusted for ball

    self.rotation = Quaternion.new(1, 0, 0, 1) -- don't keep it in state because resimulating can make it look weird

    self.radius = 1

    return self
end

function BallSimulation:GetMoveState()
    local record = self.moveStates[self.state.moveState]
    return record
end

function BallSimulation:RegisterMoveState(name, updateState, alwaysThink, startState, endState, alwaysThinkLate, executionOrder)
    local index = 0
    for key,value in pairs(self.moveStateNames) do
        index+=1
    end
    self.moveStateNames[name] = index

    local record = {}
    record.name = name
    record.updateState = updateState
    record.alwaysThink = alwaysThink
    record.startState = startState
	record.endState = endState
	record.alwaysThinkLate = alwaysThinkLate
	record.executionOrder = executionOrder or 0
	self.moveStates[index] = record
	
	self.executionOrder = {}
	for key,value in self.moveStates do
		table.insert(self.executionOrder, value)
	end
	
	table.sort(self.executionOrder, function(a,b)
		return a.executionOrder < b.executionOrder
	end)
end

function BallSimulation:SetMoveState(name)

    local index = self.moveStateNames[name]
    if (index) then

        local record = self.moveStates[index]
        if (record) then
            
            local prevRecord = self.moveStates[self.state.moveState]
            if (prevRecord and prevRecord.endState) then
                prevRecord.endState(self, name)
            end
            if (record.startState) then
                if (prevRecord) then
                    record.startState(self, prevRecord.name)
                else
                    record.startState(self, "")
                end
            end
            self.state.moveState = index
        end
    end
end


--	It is very important that this method rely only on whats in the cmd object
--	and no other client or server state can "leak" into here
--	or the server and client state will get out of sync.
local privateServerInfo: Configuration = ReplicatedStorage:WaitForChild("PrivateServerInfo")
function BallSimulation:DoServerAttributeChecks()
    self.constants.slippery = privateServerInfo:GetAttribute("Slippery")
    self.constants.gravity = -153.7 / (196.2 / privateServerInfo:GetAttribute("Gravity"))
end

function BallSimulation:ProcessCommand(cmd: {}, server, doCollisionEffects: boolean, shouldDebug: boolean?)
    if shouldDebug then
        debug.profilebegin("Ball Always Think")
    end
	for key,record in self.executionOrder do
	 
        if (record.alwaysThink) then
            record.alwaysThink(self, cmd)
        end
    end
    if shouldDebug then
        debug.profileend()
    end

    if shouldDebug then
        debug.profilebegin("Ball Update State")
    end
    local hitPlayer, hitNet, moveDelta
    local record = self.moveStates[self.state.moveState]
    if (record and record.updateState) then
        hitPlayer, hitNet, moveDelta = record.updateState(self, cmd, server, doCollisionEffects)
    else
        warn("No such updateState: ", self.state.moveState)
    end
    if shouldDebug then
        debug.profileend()
    end
	
    if shouldDebug then
        debug.profilebegin("Ball Always Think Late")
    end
	for key,record in self.executionOrder do
		if (record.alwaysThinkLate) then
			record.alwaysThinkLate(self, cmd)
		end
	end
    if shouldDebug then
        debug.profileend()
    end
  
    --Input/Movement is done, do the update of timers and write out values

    --position the debug visualizer
    if self.debugModel ~= nil then
        self.debugModel:PivotTo(CFrame.new(self.state.pos))
    end

    --Write this to the characterData
    self.ballData:SetTargetPosition(self.state.pos)

    return hitPlayer, hitNet, moveDelta
end

function BallSimulation:SetAngle(angle, teleport)
    -- self.state.angle = angle
    -- if (teleport == true) then
    --     self.state.targetAngle = angle
    --     self.characterData:SetAngle(self.state.angle, true)
    -- end
end

function BallSimulation:SetPosition(position, teleport)
    self.state.position = position
    self.ballData:SetTargetPosition(self.state.pos, teleport)
end

function BallSimulation:Destroy()
    if self.debugModel then
        self.debugModel:Destroy()
    end
end


local function ballHitPart(raycastResult: RaycastResult)
    if not game:IsLoaded() then
        return
    end

    local Lib = require(ReplicatedStorage.Lib)

    local Sound = require(ReplicatedStorage.Modules.Sound)

    local assets = ReplicatedStorage.Assets

    local hitPosition = raycastResult.Position

    local part = raycastResult.Instance
    -- do something with the part that was hit, sounds etc.
end

local magnusCoefficient = 0.5 -- Arbitrary coefficient to scale Magnus force
local airDensity = 1.225 -- Air density in kg/m^3 for the Magnus effect

local function calculateMagnusForce(velocity, angularVelocity)
    local magnusForce = magnusCoefficient * airDensity * (1 ^ 3) * angularVelocity:Cross(velocity)
    return magnusForce
end

local mapItems = workspace:WaitForChild("MapItems")

function BallSimulation:ProjectVelocity(startPos: Vector3, linearVelocity: Vector3, angularVelocity: Vector3, quaternion: typeof(Quaternion), deltaTime: number, doCollisionEffects: boolean)
    local radius = 1
    local floorHeight = 42.777+1.299/2+radius
    startPos = Vector3.new(startPos.X, math.max(floorHeight, startPos.Y), startPos.Z)

    local filter = {mapItems}

    local Lib = require(ReplicatedStorage.Lib)
    if not self.ballData.isResimulating then
        if IsClient then
            local character = localPlayer and localPlayer.Character
            if character then
                table.insert(filter, character)
            end
        else
            local characterHitBoxFilter = CollectionService:GetTagged("ServerCharacterHitbox")
            for _, character: Model in pairs(characterHitBoxFilter) do
                local userId = character:GetAttribute("player")
                if userId == self.state.netId then continue end
                local player = Players:GetPlayerByUserId(userId)
                if player == nil then continue end
                if Lib.isOnCooldown(player, "BallClaimCooldown")
                or not Lib.playerInGame(player) or Lib.playerIsStunned(player) then
                    continue
                end
                table.insert(filter, character)
            end
            table.insert(filter, CollectionService:GetTagged("Goalkeeper"))
        end
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.CollisionGroup = "Ball"
    raycastParams.RespectCanCollide = true
    raycastParams.FilterDescendantsInstances = filter

    local gravity = Vector3.new(0, self.constants.gravity, 0)
    local elasticity = self.constants.elasticity

    local acceleration = Vector3.zero
	local oldVelocity = linearVelocity
	

    local distanceToGround = startPos.Y - floorHeight
	if distanceToGround < 0.1 and linearVelocity.Y <= 0 then
		linearVelocity = MathUtils:VelocityFriction(linearVelocity, 0.6, deltaTime)
        -- if linearVelocity.Magnitude < 4 then
        --     linearVelocity = Vector3.zero
        --     oldVelocity = linearVelocity
        -- end
	elseif distanceToGround >= 0 then
		acceleration = gravity
        local magnusForce = calculateMagnusForce(linearVelocity.Unit, angularVelocity * Vector3.yAxis * 12)
        if magnusForce == magnusForce and magnusForce.Magnitude > 0 then
            acceleration += magnusForce
        end

        local function solveQuadratic(a, b, c, operation)
            if operation == "+" then
                return (-b + math.sqrt((b^2) - (4*a*c))) / (2*a)
            else
                return (-b - math.sqrt((b^2) - (4*a*c))) / (2*a)
            end
        end

        local a, b, c = gravity.Y, linearVelocity.Y, distanceToGround
        local quadratic = solveQuadratic(a, b, c, "-")
		linearVelocity += acceleration*math.min(deltaTime, quadratic)
	end
	
	local direction = acceleration * deltaTime^2 + oldVelocity * deltaTime

    local function doRaycast(rayDirection: Vector3): (RaycastResult?, boolean)
        local length = rayDirection.Magnitude
        if length == 0 or length > 1_000 then
            return
        end

        local unitDirection = rayDirection.Unit
        if unitDirection ~= unitDirection or length ~= length then
            length = 1
            unitDirection = Vector3.one
        end

        local skinThickness = 0.01
        local raycastResult = workspace:Spherecast(startPos - unitDirection*skinThickness, radius, (unitDirection * (length + skinThickness*2)), raycastParams)
        local distance = nil
        if raycastResult then
            distance = raycastResult.Distance + skinThickness
        end
        return raycastResult, distance
    end

    local hitPlayer: Player?, hitNet: BasePart?
    if direction.Magnitude > 0 then
        local raycastResult, distance = doRaycast(direction)

        if raycastResult and not self.ballData.isResimulating and IsClient then
            local character = localPlayer.Character
            if character and raycastResult.Instance:IsDescendantOf(character) then
                table.remove(filter, table.find(filter, character))
                raycastParams.FilterDescendantsInstances = filter

                hitPlayer = true
                raycastResult, distance = doRaycast(direction)
            end
        end
        local function checkIfHitPlayer()
            local character = raycastResult.Instance
            if not character:HasTag("ServerCharacterHitbox") then
                character = character.Parent
                if not character:HasTag("Goalkeeper") then
                    return
                end
            end
            filter = {mapItems}
            raycastParams.FilterDescendantsInstances = filter

            hitPlayer = character
            raycastResult, distance = doRaycast(direction)
        end
        if raycastResult and not IsClient then
            checkIfHitPlayer()
        end

        doCollisionEffects = doCollisionEffects or not self.ballData.isResimulating
        if raycastResult then
            local newElasticity = elasticity
            if raycastResult.Instance:HasTag("InvisibleBorder") then
                newElasticity = 0.5
            elseif raycastResult.Instance:HasTag("Net") then
                newElasticity = 0.2
                hitNet = raycastResult.Instance
            end

            local hitNormal = raycastResult.Normal
            local hitPoint = raycastResult.Position
    
            startPos = hitPoint + hitNormal * radius
    
            local normalVelocityComponent = linearVelocity:Dot(hitNormal) * hitNormal
            local tangentVelocityComponent = linearVelocity - normalVelocityComponent
    
            normalVelocityComponent *= -newElasticity
            tangentVelocityComponent *= 0.7
    
            linearVelocity = normalVelocityComponent + tangentVelocityComponent
            if linearVelocity.Y >= 1 then
                angularVelocity = Vector3.new(tangentVelocityComponent.Z, 0, -tangentVelocityComponent.X) * newElasticity
            end

            if localPlayer and doCollisionEffects then
                task.spawn(function()
                    ballHitPart(raycastResult)
                end)
            end
            
            if linearVelocity.Y < 0.1 then
                linearVelocity *= Vector3.new(1, 0, 1)
            end
            angularVelocity *= Vector3.new(1, 0, 1)
        else
            startPos += direction
        end	
    end
	
	
	if angularVelocity.Magnitude < 0.01 then
		return startPos, linearVelocity, angularVelocity, quaternion, hitPlayer, hitNet
	end
	
	distanceToGround = startPos.Y - floorHeight
	if distanceToGround < 0.1 then
        local friction = 1.5 + self.constants.slippery*6
		angularVelocity = MathUtils:VelocityFriction(angularVelocity, friction, deltaTime)

		local realAngularVelocity = angularVelocity * deltaTime
		local velocity = realAngularVelocity:Cross(Vector3.yAxis)
        local raycastResult, distance = doRaycast(velocity)
        local function checkIfHitPlayer()
            local character = raycastResult.Instance
            if not character:HasTag("ServerCharacterHitbox") then
                character = character.Parent
                if not character:HasTag("Goalkeeper") then
                    return
                end
            end
            filter = {mapItems}
            raycastParams.FilterDescendantsInstances = filter

            hitPlayer = character
            raycastResult, distance = doRaycast(velocity)
        end
        if raycastResult and not IsClient then
            checkIfHitPlayer()
        end

		if raycastResult then
            local newElasticity = elasticity
            if raycastResult.Instance:HasTag("Net") then
                hitNet = raycastResult.Instance
                newElasticity = 0.5
            end
			local reflect = MathUtils:Reflect(velocity / deltaTime, raycastResult.Normal) * newElasticity
            angularVelocity = Vector3.yAxis:Cross(reflect)

            local hitNormal = raycastResult.Normal
            local hitPoint = raycastResult.Position
            startPos = hitPoint + hitNormal * radius

            if localPlayer and doCollisionEffects then
                task.spawn(function()
                    ballHitPart(raycastResult)
                end)
            end

            angularVelocity *= Vector3.new(1, 0, 1)
		else
			startPos += velocity
		end

        local rotateCF = CFrame.fromAxisAngle(realAngularVelocity, realAngularVelocity.Magnitude)
        if rotateCF == rotateCF and not self.ballData.isResimulating then
            local moveQuaternion = Quaternion.fromCFrame(CFrame.fromAxisAngle(realAngularVelocity, realAngularVelocity.Magnitude))
            quaternion = moveQuaternion:Mul(quaternion)
        end
	else
		local realAngularVelocity = angularVelocity * deltaTime
        local rotateCF = CFrame.fromAxisAngle(realAngularVelocity, realAngularVelocity.Magnitude)
        if rotateCF == rotateCF and not self.ballData.isResimulating then
            local moveQuaternion = Quaternion.fromCFrame(CFrame.fromAxisAngle(realAngularVelocity, realAngularVelocity.Magnitude))
            quaternion = moveQuaternion:Mul(quaternion)
        end
	end

    return startPos, linearVelocity, angularVelocity, quaternion, hitPlayer, hitNet
end


--This gets deltacompressed by the client/server chickynoids automatically
function BallSimulation:WriteState()
    local record = {}
    record.state = DeltaTable:DeepCopy(self.state)
    return record
end

function BallSimulation:ReadState(record)
    self.state = DeltaTable:DeepCopy(record.state)
end

return BallSimulation