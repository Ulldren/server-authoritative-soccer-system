--!native
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local IsClient = RunService:IsClient()

local module = {}

local path = game.ReplicatedFirst.Chickynoid
local MathUtils = require(path.Shared.Simulation.MathUtils)
local Enums = require(path.Shared.Enums)
local Animations = require(path.Shared.Simulation.Animations)


--Call this on both the client and server!
function module:ModifySimulation(simulation)
    simulation:RegisterMoveState("Ragdoll", self.ActiveThink, self.AlwaysThink, self.StartState, self.EndState)
	simulation.state.knockback = 0
end

--Imagine this is inside Simulation...
function module.AlwaysThink(simulation, cmd)
    if (simulation.state.knockback > 0) then
		simulation.state.knockback = math.max(simulation.state.knockback - cmd.deltaTime, 0)
    else
        local animChannel = Enums.AnimChannel.Channel1
        local slotString = "animNum"..animChannel
        if simulation.characterData.serialized[slotString] == Animations:GetAnimationIndex("StunLand") then
            simulation.characterData:PlayAnimation("Stop", Enums.AnimChannel.Channel1, true)
        end
	end

    local player = simulation.player
    if player == nil then
        return
    end

    if simulation.isGoalkeeper then
        simulation.state.knockback = 0
        return
    end

	if cmd.knockback ~= nil and cmd.freeze ~= 1 then
        if cmd.knockback.X == 0 and cmd.knockback.Z == 0 then
            simulation.state.vel = (simulation.state.vel * Vector3.new(1, 0, 1)) + cmd.knockback
        else
            simulation.state.vel = cmd.knockback
        end
        simulation.state.knockback = math.max(simulation.state.knockback, cmd.knockbackDuration)
        simulation:SetMoveState("Ragdoll")
        if cmd.tackleRagdoll then
            simulation.characterData:PlayAnimation("StunLand", Enums.AnimChannel.Channel1, true)
        else
            simulation.characterData:PlayAnimation("StunFlip", Enums.AnimChannel.Channel1, true)
        end
        if not IsClient then
            player:SetAttribute("ServerChickyRagdoll", true)
        end
    end
end

function module.StartState(simulation)

end

function module.EndState(simulation)
    local player = simulation.player
    if not IsClient then
        player:SetAttribute("ServerChickyRagdoll", nil)
    end
end

--Imagine this is inside Simulation...
function module.ActiveThink(simulation, cmd)
    local player: Player = simulation.player
    local walkReset = simulation.emoteWalkReset
    if not IsClient and walkReset and os.clock() - walkReset >= 0 then
        local function setNewEmote(newEmote)
            local function generateShortGUID()
                local guid = HttpService:GenerateGUID(false)
                guid = guid:gsub("-", "")
                return string.lower(guid)
            end
            player:SetAttribute("EmoteData", HttpService:JSONEncode({newEmote, generateShortGUID()}))
        end
        setNewEmote(nil)
    elseif IsClient and not simulation.characterData.isResimulating then
        player:SetAttribute("EndEmote", true)
        player:SetAttribute("EndEmote", nil)
    end
    if IsClient and not simulation.characterData.isResimulating and simulation.runningSound then
        simulation.runningSound.Playing = false
    end

    if simulation.completeFreeze then
        return
    end

    --Check ground
    local onGround = nil
    onGround = simulation:DoGroundCheck(simulation.state.pos)

    --If the player is on too steep a slope, its not ground
	if (onGround ~= nil and onGround.normal.Y < simulation.constants.maxGroundSlope) then
		
		--See if we can move downwards?
		if (simulation.state.vel.Y < 0.1) then
			onGround.normal = Vector3.new(0,1,0)
		else
			onGround = nil
		end
	end
	
	 
    local startedOnGround = onGround

	simulation.lastGround = onGround

    --Create flat velocity to operate our input command on
    --In theory this should be relative to the ground plane instead...
    local flatVel = MathUtils:FlatVec(simulation.state.vel)
    if onGround then
        local friction = 0.1 + simulation.constants.slippery
        flatVel = MathUtils:VelocityFriction(flatVel, friction, cmd.deltaTime)
    end

    --Does the player have an input?
	-- flatVel = MathUtils:VelocityFriction(flatVel, GameInfo.TACKLE_FRICTION, cmd.deltaTime)

    --Turn out flatvel back into our vel
    simulation.state.vel = Vector3.new(flatVel.x, simulation.state.vel.y, flatVel.z)

    --Do jumping?
    if simulation.state.jump > 0 then
        simulation.state.jump -= cmd.deltaTime
        if simulation.state.jump < 0 then
            simulation.state.jump = 0
        end
    end


    --In air?
    if onGround == nil then
        simulation.state.inAir += cmd.deltaTime
        if simulation.state.inAir > 10 then
            simulation.state.inAir = 10 --Capped just to keep the state var reasonable
        end

        --Jump thrust
        if cmd.y > 0 then
            if simulation.state.jumpThrust > 0 then
                simulation.state.vel += Vector3.new(0, simulation.state.jumpThrust * cmd.deltaTime, 0)
                simulation.state.jumpThrust = MathUtils:Friction(
                    simulation.state.jumpThrust,
                    simulation.constants.jumpThrustDecay,
                    cmd.deltaTime
                )
            end
            if simulation.state.jumpThrust < 0.001 then
                simulation.state.jumpThrust = 0
            end
        else
            simulation.state.jumpThrust = 0
        end

        --gravity
        simulation.state.vel += Vector3.new(0, simulation.constants.gravity * cmd.deltaTime, 0)
    else
        simulation.state.inAir = 0
    end

    --Sweep the player through the world, once flat along the ground, and once "step up'd"
    local stepUpResult = nil
    local walkNewPos, walkNewVel, hitSomething = simulation:ProjectVelocity(simulation.state.pos, simulation.state.vel, cmd.deltaTime)
	
    -- Do we attempt a stepup?                              (not jumping!)
    if onGround ~= nil and hitSomething == true and simulation.state.jump == 0 then
        stepUpResult = simulation:DoStepUp(simulation.state.pos, simulation.state.vel, cmd.deltaTime)
    end

    --Choose which one to use, either the original move or the stepup
    if stepUpResult ~= nil then
        simulation.state.stepUp += stepUpResult.stepUp
        simulation.state.pos = stepUpResult.pos
        simulation.state.vel = stepUpResult.vel
    else
        simulation.state.pos = walkNewPos
        simulation.state.vel = walkNewVel
    end

    if simulation.playerInGameOrPausedOrEnded then
        if simulation:DoGroundCheck(simulation.state.pos) and simulation.state.vel.Y < 0 then
            simulation.characterData:PlayAnimation("StunLand", Enums.AnimChannel.Channel1, false)
        else
            simulation.characterData:PlayAnimation("StunFlip", Enums.AnimChannel.Channel1, false)
        end
    end

    --Do stepDown
    if true then
        if startedOnGround ~= nil and simulation.state.jump == 0 and simulation.state.vel.y <= 0 then
            local stepDownResult = simulation:DoStepDown(simulation.state.pos)
            if stepDownResult ~= nil then
                simulation.state.stepUp += stepDownResult.stepDown
                simulation.state.pos = stepDownResult.pos
            end
        end
    end
end

return module