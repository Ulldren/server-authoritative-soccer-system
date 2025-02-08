--!native
--[=[
    @class Simulation
    Simulation handles physics for characters on both the client and server.
]=]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local IsClient = RunService:IsClient()

local Simulation = {}
Simulation.__index = Simulation

local CollisionModule = require(script.Parent.CollisionModule)
local CharacterData = require(script.Parent.CharacterData)
local MathUtils = require(script.Parent.MathUtils)
local Enums = require(script.Parent.Parent.Enums)
local DeltaTable = require(script.Parent.Parent.Vendor.DeltaTable)
local Quaternion = require(script.Parent.Quaternion)

local Lib = require(ReplicatedStorage.Lib)
local GameInfo = require(ReplicatedFirst.GameInfo)

local localPlayer = Players.LocalPlayer


function Simulation.new(userId)
    local self = setmetatable({}, Simulation)

    self.userId = userId

    self.moveStates = {}
	self.moveStateNames = {}
	self.executionOrder = {}

    self.state = {}

    self.state.pos = Vector3.new(0, 5, 0)
    self.state.vel = Vector3.new(0, 0, 0)
    self.state.pushDir = Vector2.new(0, 0)

    self.state.jump = 0
    self.state.angle = 0
    self.state.targetAngle = 0
    self.state.stepUp = 0
    self.state.inAir = 0
    self.state.jumpThrust = 0
    self.state.pushing = 0 --External flag comes from server (ungh >_<')
    self.state.moveState = 0 --Walking!

    self.characterData = CharacterData.new()

    self.lastGround = nil --Used for platform stand on servers only

    --Roblox Humanoid defaultish
    self.constants = {}
    self.constants.maxSpeed = 16 --Units per second
    self.constants.accel = 40 --Units per second per second
    self.constants.jumpPunch = 60 --Raw velocity, just barely enough to climb on a 7 unit tall block
    self.constants.turnSpeedFrac = 8 --seems about right? Very fast.
    self.constants.maxGroundSlope = 0.05 --about 89o
    self.constants.jumpThrustPower = 0    --No variable height jumping 
    self.constants.jumpThrustDecay = 0
	self.constants.gravity = -196.2
	self.constants.crashLandBehavior = Enums.Crashland.FULL_BHOP_FORWARD

    self.constants.pushSpeed = 16 --set this lower than maxspeed if you want stuff to feel heavy
	self.constants.stepSize = 2.2	--How high you can step over something
	self.constants.gravity = -196.2

    self.constants.slippery = 0
    self.constants.maxStamina = GameInfo.MAX_STAMINA


    self.custom = {}
    self.custom.ballQuaternion = Quaternion.new(1, 0, 0, 1)
    self.custom.leanAngle = Vector2.new(0, 0)
    self.custom.animDir = 0

    return self
end

function Simulation:GetMoveState()
    local record = self.moveStates[self.state.moveState]
    return record
end

function Simulation:RegisterMoveState(name, updateState, alwaysThink, startState, endState, alwaysThinkLate, executionOrder)
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

function Simulation:SetMoveState(name)

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

local runningSound: Sound
function Simulation:DoPlayerAttributeChecks()
    local player = Players:GetPlayerByUserId(self.userId)
    if player == nil then
        return
    end
    self.player = player
    self.completeFreeze = player:GetAttribute("CompleteFreeze")
    self.isGoalkeeper = player:GetAttribute("Position") == "Goalkeeper"

    self.playerInGame = Lib.playerInGameOrPaused(player)
    self.playerInGameOrPausedOrEnded = Lib.playerInGameOrPausedOrEnded(player)

    self.movementDisabled = player:GetAttribute("MovementDisabled")
    self.teleported = player:GetAttribute("Teleported")
    self.emoteWalkReset = player:GetAttribute("EmoteWalkReset")

    self.groundType = workspace.MapItems.Ground:GetAttribute("GroundType")

    if self.isGoalkeeper and false then
        self.constants.gravity = -196.2+70
        self.constants.jumpPunch = 50
    else
        local gravity = privateServerInfo:GetAttribute("Gravity")
        self.constants.gravity = -gravity
        self.constants.jumpPunch = 50
    end
    self.constants.maxSpeed = privateServerInfo:GetAttribute("WalkSpeed")
    self.constants.slippery = privateServerInfo:GetAttribute("Slippery")

    local maxStamina = GameInfo.MAX_STAMINA
    if player:GetAttribute("InfiniteStamina") then
        maxStamina = math.huge
    elseif player:GetAttribute("x2Stamina") then
        maxStamina *= 2
    end
    self.constants.maxStamina = maxStamina

    if runningSound == nil then
        local character = player.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart then
            runningSound = humanoidRootPart.Running
        end
    end
    self.runningSound = runningSound
end

function Simulation:ProcessCommand(cmd, shouldDebug: boolean?)
    if shouldDebug then
        debug.profilebegin("Chickynoid Always Think")
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
        debug.profilebegin("Chickynoid Update State")
    end
    local record = self.moveStates[self.state.moveState]
    if (record and record.updateState) then
        record.updateState(self, cmd)
    else
        warn("No such updateState: ", self.state.moveState)
    end
    if shouldDebug then
        debug.profileend()
    end
    
    if shouldDebug then
        debug.profilebegin("Chickynoid Always Think Late")
    end
    for key, record in self.executionOrder do

        if (record.alwaysThinkLate) then
            record.alwaysThinkLate(self, cmd)
        end
    end
    if shouldDebug then
        debug.profileend()
    end
  
    --Input/Movement is done, do the update of timers and write out values

    --Adjust stepup
    if shouldDebug then
        debug.profilebegin("Chickynoid Decay Step Up")
    end
    self:DecayStepUp(cmd.deltaTime)
    if shouldDebug then
        debug.profileend()
    end

    --position the debug visualizer
    if self.debugModel ~= nil then
        self.debugModel:PivotTo(CFrame.new(self.state.pos))
    end

    --Do pushing animation timer
    self:DoPushingTimer(cmd)

    --Write this to the characterData
    if shouldDebug then
        debug.profilebegin("Chickynoid Write To Character Data")
    end
    self.characterData:SetTargetPosition(self.state.pos)
    self.characterData:SetAngle(self.state.angle)
    self.characterData:SetStepUp(self.state.stepUp)
    self.characterData:SetFlatSpeed( MathUtils:FlatVec(self.state.vel).Magnitude)
    if shouldDebug then
        debug.profileend()
    end
end

function Simulation:UpdatePlayerAttributes()
    if localPlayer and not self.characterData.isResimulating then
        local stamina = self.state.stam
        if stamina then
            debug.profilebegin("Chickynoid Update Stamina")
            localPlayer:SetAttribute("Stamina", stamina)
            debug.profileend()
        end
        local tackle = self.state.tackle
        if tackle then
            debug.profilebegin("Chickynoid Update Tackle/Dive")
            localPlayer:SetAttribute("Tackle", tackle > 0)
            localPlayer:SetAttribute("Dive", tackle > 0)
            debug.profileend()
        end
    end
end

function Simulation:SetAngle(angle, teleport)
    self.state.angle = angle
    if (teleport == true) then
        self.state.targetAngle = angle
        self.characterData:SetAngle(self.state.angle, true)
    end
end

function Simulation:SetPosition(position, teleport)
    self.state.position = position
    self.characterData:SetTargetPosition(self.state.pos, teleport)
end

function Simulation:CrashLand(vel, ground)
	

	if (self.constants.crashLandBehavior == Enums.Crashland.FULL_BHOP) then
		return Vector3.new(vel.x, 0, vel.z)
	end
	
	if (self.constants.crashLandBehavior == Enums.Crashland.CAPPED_BHOP) then
		--cap velocity
		local returnVel = Vector3.new(vel.x, 0, vel.z)
		returnVel = MathUtils:CapVelocity(returnVel, self.constants.maxSpeed)
		return returnVel
	end
	
	if (self.constants.crashLandBehavior == Enums.Crashland.CAPPED_BHOP_FORWARD) then
		
		local flat = Vector3.new(ground.normal.x, 0, ground.normal.z).Unit
		local forward = MathUtils:PlayerAngleToVec(self.state.angle)
					
		if (forward:Dot(flat) < 0) then --bhop forward if the slope is the way we're facing
			
			local returnVel = Vector3.new(vel.x, 0, vel.z)
			returnVel = MathUtils:CapVelocity(returnVel, self.constants.maxSpeed)
			return returnVel
		end		
		--else stop
		return Vector3.new(0,0,0)
	end
	
	if (self.constants.crashLandBehavior == Enums.Crashland.FULL_BHOP_FORWARD) then

		local flat = Vector3.new(ground.normal.x, 0, ground.normal.z).Unit
		local forward = MathUtils:PlayerAngleToVec(self.state.angle)

		if (forward:Dot(flat) < 0) then --bhop forward if the slope is the way we're facing
			return vel
		end		
		--else stop
		return Vector3.new(0,0,0)
	end
	
    --stop
	return Vector3.new(0,0,0)
end


--STEPUP - the magic that lets us traverse uneven world geometry
--the idea is that you redo the player movement but "if I was x units higher in the air"

function Simulation:DoStepUp(pos, vel, deltaTime)
    if self:IsInMatch(pos) then
        return nil
    end

    local flatVel = MathUtils:FlatVec(vel)

    local stepVec = Vector3.new(0, self.constants.stepSize, 0)
    --first move upwards as high as we can go

    local headHit = CollisionModule:Sweep(pos, pos + stepVec)

    --Project forwards
    local stepUpNewPos, stepUpNewVel, _stepHitSomething = self:ProjectVelocity(headHit.endPos, flatVel, deltaTime)

    --Trace back down
    local traceDownPos = stepUpNewPos
    local hitResult = CollisionModule:Sweep(traceDownPos, traceDownPos - stepVec)

    stepUpNewPos = hitResult.endPos

    --See if we're mostly on the ground after this? otherwise rewind it
    local ground = self:DoGroundCheck(stepUpNewPos)

    --Slope check
    if ground ~= nil then
        if ground.normal.Y < self.constants.maxGroundSlope or ground.startSolid == true then
            return nil
        end
    end

    if ground ~= nil then
        local result = {
            stepUp = self.state.pos.y - stepUpNewPos.y,
            pos = stepUpNewPos,
            vel = stepUpNewVel,
        }
        return result
    end

    return nil
end

--Magic to stick to the ground instead of falling on every stair
function Simulation:DoStepDown(pos)
    if self:IsInMatch(pos) then -- in match
        return nil
    end

    local stepVec = Vector3.new(0, self.constants.stepSize, 0)
    local hitResult = CollisionModule:Sweep(pos, pos - stepVec)

    if
        hitResult.startSolid == false
        and hitResult.fraction < 1
        and hitResult.normal.Y >= self.constants.maxGroundSlope
    then
        local delta = pos.y - hitResult.endPos.y

        if delta > 0.001 then
            local result = {

                pos = hitResult.endPos,
                stepDown = delta,
            }
            return result
        end
    end

    return nil
end

function Simulation:Destroy()
    if self.debugModel then
        self.debugModel:Destroy()
    end
end

function Simulation:DecayStepUp(deltaTime)
    self.state.stepUp = MathUtils:Friction(self.state.stepUp, 0.05, deltaTime) --higher == slower
end

function Simulation:DoGroundCheck(pos)
    if self:IsInMatch(pos) then -- in match
        local groundTopPos = 42.777+1.299/2 + 2.5
        if pos.Y - groundTopPos < 0.1 then
            local data = {}
            data.normal = Vector3.new(0, 1, 0)
            return data
        else
            return nil
        end
    end


    local results = CollisionModule:Sweep(pos + Vector3.new(0, 0.1, 0), pos + Vector3.new(0, -0.1, 0))

    if results.allSolid == true or results.startSolid == true then
        --We're stuck, pretend we're in the air

        results.fraction = 1
        return results
    end

    if results.fraction < 1 then
        return results
    end
    return nil
end

local playerSize = Vector3.new(2, 5, 2)
local boundary = {
    Position = Vector3.new(86.013, 85.303, -306.262),
    Size = Vector3.new(388.875, 83.59, 270.292) - playerSize,
}
function Simulation:ProjectVelocity(startPos: Vector3, startVel: Vector3, deltaTime: number, shouldBounce: boolean?)
    if self:IsInMatch(startPos) then -- in match
        local originalPos = startPos
        startPos += startVel*deltaTime
        local lastPos = startPos
        startPos = MathUtils:ClampToBoundary(startPos, boundary.Position, boundary.Size)
        if lastPos.Y ~= startPos.Y and startPos.Y > boundary.Position.Y then
            startVel *= Vector3.new(1, -1, 1)
        end
        if lastPos.X ~= startPos.X or lastPos.Z ~= startPos.Z then
            startVel = Vector3.new((startPos.X - originalPos.X) / deltaTime, startVel.Y, (startPos.Z - originalPos.Z) / deltaTime)
        end
        
        return startPos, startVel, false
    end


    local movePos = startPos
    local moveVel = startVel
    local hitSomething = false


    --Project our movement through the world
    local planes = {}
    local timeLeft = deltaTime

    for _ = 0, 3 do
        if moveVel.Magnitude < 0.001 then
            --done
            break
        end

        if moveVel:Dot(startVel) < 0 then
            --we projected back in the opposite direction from where we started. No.
			moveVel = Vector3.new(0, 0, 0)
            break
        end

        --We only operate on a scaled down version of velocity
        local result = CollisionModule:Sweep(movePos, movePos + (moveVel * timeLeft))

        --Update our position
        if result.fraction > 0 then
            movePos = result.endPos
        end

        --See if we swept the whole way?
        if result.fraction == 1 then
            break
        end

        if result.fraction < 1 then
            hitSomething = true
        end

        if result.allSolid == true then
            --all solid, don't do anything
            --(this doesn't mean we wont project along a normal!)
            moveVel = Vector3.new(0, 0, 0)
            break
        end

        --Hit!
        timeLeft -= (timeLeft * result.fraction)

        if planes[result.planeNum] == nil then
            planes[result.planeNum] = true

            --Deflect the velocity and keep going
            moveVel = MathUtils:ClipVelocity(moveVel, result.normal, 1.0)
        else
            --We hit the same plane twice, push off it a bit
            movePos += result.normal * 0.01
            moveVel += result.normal
            break
        end
    end

    return movePos, moveVel, hitSomething
end

function Simulation:IsInMatch(startPos: Vector3)
    startPos = startPos or self.state.pos
    return startPos.Z < -150
end


--This gets deltacompressed by the client/server chickynoids automatically
function Simulation:WriteState()
    local record = {}
    record.state = DeltaTable:DeepCopy(self.state)
    -- record.constants = DeltaTable:DeepCopy(self.constants)
    return record
end

function Simulation:ReadState(record)
    self.state = DeltaTable:DeepCopy(record.state)
    -- self.constants = DeltaTable:DeepCopy(record.constants)
end

function Simulation:DoPlatformMove(lastGround, deltaTime)
    --Do platform move
    if lastGround and lastGround.hullRecord and lastGround.hullRecord.instance then
        local instance = lastGround.hullRecord.instance
        if instance.Velocity.Magnitude > 0 then
            self.state.pos += instance.Velocity * deltaTime
        end
    end
end

function Simulation:DoPushingTimer(cmd)
    if IsClient == true then
        return
    end

    if self.state.pushing > 0 then
        self.state.pushing -= cmd.deltaTime
        if self.state.pushing < 0 then
            self.state.pushing = 0
        end
    end
end

function Simulation:GetStandingPart()
    if self.lastGround and self.lastGround.hullRecord then
        return self.lastGround.hullRecord.instance
    end
    return nil
end


function Simulation:ChangeBallRotation(rotateCFrame: CFrame)
	self.custom.ballQuaternion = self.custom.ballQuaternion:Mul(Quaternion.fromCFrame(rotateCFrame))
end

function Simulation:SetAnimDir(animDir)
	self.custom.animDir = animDir
end

function Simulation:LerpLeanAngle(newAngle: Vector2, alpha: number)
	self.custom.leanAngle = self.custom.leanAngle:Lerp(newAngle, alpha)
end

function Simulation:SetLeanAngle(newAngle: Vector2)
	self.custom.leanAngle = newAngle
end

return Simulation