--!native
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local IsClient = RunService:IsClient()

local module = {}

local path = game.ReplicatedFirst.Chickynoid
local MathUtils = require(path.Shared.Simulation.MathUtils)
local Enums = require(path.Shared.Enums)

local GameInfo = require(game.ReplicatedFirst.GameInfo)


--Call this on both the client and server!
function module:ModifySimulation(simulation)
    simulation:RegisterMoveState("Tackle", self.ActiveThink, self.AlwaysThink, self.StartState, nil)
	simulation.state.tackleCooldown = 0
    simulation.state.tackleDir = Vector3.new(1, 0, 0)
    simulation.state.tackle = 0
end

--Imagine this is inside Simulation...
function module.AlwaysThink(simulation, cmd)
	if (simulation.state.tackleCooldown > 0) then
		simulation.state.tackleCooldown = math.max(simulation.state.tackleCooldown - cmd.deltaTime, 0)
	end
    if (simulation.state.tackle > 0) then
		simulation.state.tackle = math.max(simulation.state.tackle - cmd.deltaTime, 0)
	end

    local tackleDir = cmd.tackleDir
	if (simulation.state.tackleCooldown == 0 and tackleDir and tackleDir.Magnitude > 0) then
        local privateServerInfo: Configuration = ReplicatedStorage.PrivateServerInfo

        simulation.state.tackleDir = tackleDir
        simulation.state.vel += tackleDir * 80 * (simulation.constants.maxSpeed/16)

        local tackleDuration = GameInfo.TACKLE_VELOCITY_DURATION
        simulation.state.tackle = tackleDuration
        simulation.state.tackleCooldown = privateServerInfo:GetAttribute("TackleCD") + tackleDuration
        simulation:SetMoveState("Tackle")
        simulation.characterData:PlayAnimation("SlideTackle", Enums.AnimChannel.Channel1, true)
    end
end

function module.StartState(simulation, cmd)
    if not simulation.characterData.isResimulating then
        local player = simulation.player
        if player == nil then
            return
        end

        if IsClient then
            player:SetAttribute("CMDTackleDir", nil)
        else
            local services = ServerScriptService.ServerScripts.Services
            local CharacterService = require(services.CharacterService)

            CharacterService:TackleStart(player)
        end
    end
end

--Imagine this is inside Simulation...
function module.ActiveThink(simulation, cmd)
    local player = simulation.player
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
	
	 
    --Mark if we were onground at the start of the frame
    local startedOnGround = onGround
	
	--Simplify - whatever we are at the start of the frame goes.
	simulation.lastGround = onGround
	

    --Did the player have a movement request?
    local wishDir = nil
    if cmd.x ~= 0 or cmd.z ~= 0 then
        wishDir = Vector3.new(cmd.x, 0, cmd.z).Unit
        simulation.state.pushDir = Vector2.new(cmd.x, cmd.z)
    else
        simulation.state.pushDir = Vector2.new(0, 0)
    end
    if simulation.state.sprint == 1 and wishDir ~= nil then
        simulation.state.stam -= GameInfo.SPRINT_STAMINA_CONSUMPTION * cmd.deltaTime
        simulation.state.stamRegCD = 0.5
    end

    --Create flat velocity to operate our input command on
    --In theory this should be relative to the ground plane instead...
    local flatVel = MathUtils:FlatVec(simulation.state.vel)

    --Does the player have an input?
    local friction = GameInfo.TACKLE_FRICTION
    if simulation:IsInMatch() then
        friction += simulation.constants.slippery * 0.1
    end
	flatVel = MathUtils:VelocityFriction(flatVel, friction, cmd.deltaTime)

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

        --Switch to falling if we've been off the ground for a bit
        if simulation.state.vel.y <= 0.01 and simulation.state.inAir > 0.5 then
			-- simulation.characterData:PlayAnimation("Fall", Enums.AnimChannel.Channel0, false)
        end
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

	--Do angles
    if cmd.shiftLock == 1 and cmd.fa and typeof(cmd.fa) == "Vector3" then
        local vec = cmd.fa

        simulation.state.targetAngle  = MathUtils:PlayerVecToAngle(vec)
        simulation.state.angle = MathUtils:LerpAngle(
            simulation.state.angle,
            simulation.state.targetAngle,
            simulation.constants.turnSpeedFrac * cmd.deltaTime
        )
    else    
        simulation.state.targetAngle = MathUtils:PlayerVecToAngle(simulation.state.tackleDir)
        simulation.state.angle = MathUtils:LerpAngle(
            simulation.state.angle,
            simulation.state.targetAngle,
            simulation.constants.turnSpeedFrac * cmd.deltaTime
        )
    end
end

return module