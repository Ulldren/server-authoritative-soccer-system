--!native
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local IsClient = RunService:IsClient()

local module = {}

local localPlayer = Players.LocalPlayer

local path = game.ReplicatedFirst.Chickynoid
local MathUtils = require(path.Shared.Simulation.MathUtils)
local Enums = require(path.Shared.Enums)
local FootstepSounds = require(path.Shared.FootstepSounds)
local Animations = require(path.Shared.Simulation.Animations)

local GameInfo = require(game.ReplicatedFirst.GameInfo)


local boundaryFolder = workspace.MapItems.GoalkeeperBoundaries
local homeBoundary = boundaryFolder:WaitForChild("Home")
local awayBoundary = boundaryFolder:WaitForChild("Away")
local boundaries = {
    Home = {
        Position = homeBoundary.Position,
        Size = homeBoundary.Size,
    },
    Away = {
        Position = awayBoundary.Position,
        Size = awayBoundary.Size,
    },
}


--Call this on both the client and server!
function module:ModifySimulation(simulation)
    simulation.state.skillCd = 0

    simulation:RegisterMoveState("Walking", self.ActiveThink, self.AlwaysThink, nil, nil)
    simulation:SetMoveState("Walking")
end

function module.AlwaysThink(simulation, cmd)
    if (simulation.state.skillCd > 0) then
		simulation.state.skillCd = math.max(simulation.state.skillCd - cmd.deltaTime, 0)
	end

    if (simulation.state.stamRegCD > 0) then
		simulation.state.stamRegCD = math.max(simulation.state.stamRegCD - cmd.deltaTime, 0)
	end
    if simulation.state.stamRegCD == 0 and simulation.state.stam < simulation.constants.maxStamina then
        simulation.state.stam = math.min(simulation.state.stam + GameInfo.STAMINA_REGEN * cmd.deltaTime, simulation.constants.maxStamina)
    end
    if simulation.state.stam <= 0 then
        simulation.state.stam = 0
        simulation.state.sprint = 0
    end

    local player = simulation.player
    if player == nil then
        return
    end

    if cmd.charge == 1 then
        simulation.characterData:PlayAnimation("ChargeShot", Enums.AnimChannel.Channel2, false, 0.3)
    else
        local animChannel = Enums.AnimChannel.Channel2
        local slotString = "animNum"..animChannel
        local animNum = simulation.characterData.serialized[slotString]
        if animNum == Animations:GetAnimationIndex("ChargeShot") then
            simulation.characterData:PlayAnimation("Shoot", Enums.AnimChannel.Channel1, true, 0.01)
        end
        if animNum ~= Animations:GetAnimationIndex("Stop") then
            simulation.characterData:PlayAnimation("Stop", Enums.AnimChannel.Channel2, true)
        end
    end

    if simulation.movementDisabled then
        simulation.state.vel *= Vector3.new(0, 1, 0)
    end

    local moveState = simulation:GetMoveState()
    if moveState.name ~= "Walking" and not (simulation.state.tackle == 0 and simulation.state.knockback == 0 or simulation.movementDisabled) or simulation.completeFreeze then
        local alpha = math.min(1, cmd.deltaTime*8)
        simulation:LerpLeanAngle(Vector2.zero, alpha)
    end

    if simulation.completeFreeze then
        if simulation.runningSound then
            simulation.runningSound.Playing = false
        end
        simulation.state.sprint = 0
        simulation.characterData:PlayAnimation("Idle", Enums.AnimChannel.Channel0, true, 0.2)
        return
    end
    if cmd.skill == 1 and simulation.state.skillCd == 0 then
        local privateServerInfo: Configuration = ReplicatedStorage.PrivateServerInfo
        simulation.state.skillCd = privateServerInfo:GetAttribute("SkillCD") + GameInfo.SKILL_DURATION

        if IsClient then
            simulation.characterData:PlayAnimation("Skill", Enums.AnimChannel.Channel1, true)
        else
            local services = ServerScriptService.ServerScripts.Services
            local CharacterService = require(services.CharacterService)
            CharacterService:Skill(player)
        end
    end

    if (moveState.name ~= "Walking") then
        if simulation.state.tackle == 0 and simulation.state.knockback == 0 or simulation.movementDisabled then
            simulation:SetMoveState("Walking")
        end
    end
	if cmd.sprinting == 1 and simulation.state.stam > 0 then
        simulation.state.sprint = 1
    else
        simulation.state.sprint = 0
    end
end

--Imagine this is inside Simulation...
function module.ActiveThink(simulation, cmd)
    local player = simulation.player
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
    if (cmd.x ~= 0 or cmd.z ~= 0) then
        wishDir = Vector3.new(cmd.x, 0, cmd.z).Unit
        simulation.state.pushDir = Vector2.new(cmd.x, cmd.z)
    else
        simulation.state.pushDir = Vector2.new(0, 0)
    end

    if simulation.state.sprint == 1 and wishDir ~= nil then
        if player and not simulation.isGoalkeeper then
            simulation.state.stam -= GameInfo.SPRINT_STAMINA_CONSUMPTION * cmd.deltaTime
            simulation.state.stamRegCD = 0.5
        end
    end

    --Create flat velocity to operate our input command on
    --In theory this should be relative to the ground plane instead...
    local flatVel = MathUtils:FlatVec(simulation.state.vel)
    if wishDir ~= nil and player then
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
    end

    --Do angles
    if (cmd.shiftLock == 1) then
    
        if (cmd.fa and typeof(cmd.fa) == "Vector3") then
            local vec = cmd.fa

            simulation.state.targetAngle  = MathUtils:PlayerVecToAngle(vec)
            simulation.state.angle = MathUtils:LerpAngle(
                simulation.state.angle,
                simulation.state.targetAngle,
                simulation.constants.turnSpeedFrac * cmd.deltaTime
            )
        end
    else    
        if wishDir ~= nil then
            simulation.state.targetAngle = MathUtils:PlayerVecToAngle(wishDir)
            simulation.state.angle = MathUtils:LerpAngle(
                simulation.state.angle,
                simulation.state.targetAngle,
                simulation.constants.turnSpeedFrac * cmd.deltaTime
            )
        end
    end


    --Does the player have an input?
    local brakeFriction = 0.02
    local slipFriction = brakeFriction
    local slipAccel = simulation.constants.accel
    if simulation:IsInMatch() then
        slipFriction += simulation.constants.slippery
        slipAccel *= (1 - simulation.constants.slippery*0.99)
    end

    local walked = false
    if wishDir ~= nil then
        local multi = simulation.state.sprint == 1 and 1.6 or 1

        -- local add = isUsingSkill and 5 or 0
        local add = 0
        if onGround then
            --Moving along the ground under player input

            flatVel = MathUtils:GroundAccelerate(
                wishDir,
                simulation.constants.maxSpeed * multi + add,
                slipAccel * multi + add,
                flatVel,
                cmd.deltaTime
            )

            --Good time to trigger our walk anim
            if simulation.state.pushing > 0 then
                simulation.characterData:PlayAnimation("Push", Enums.AnimChannel.Channel0, false)
            else
                local moveAnim = simulation.state.sprint == 1 and "Sprint" or "Walk"
                simulation.characterData:PlayAnimation(moveAnim, Enums.AnimChannel.Channel0, false)
            end
            walked = true
        else
            --Moving through the air under player control
            flatVel = MathUtils:GroundAccelerate(wishDir, simulation.constants.maxSpeed * multi, slipAccel * multi, flatVel, cmd.deltaTime)
        end
    else
        if onGround ~= nil then
            --Just standing around
            flatVel = MathUtils:VelocityFriction(flatVel, slipFriction, cmd.deltaTime)

            --Enter idle
            simulation.characterData:PlayAnimation("Idle", Enums.AnimChannel.Channel0, false)
        -- else
            --moving through the air with no input
        else
            flatVel = MathUtils:VelocityFriction(flatVel, slipFriction, cmd.deltaTime)
        end
    end

    --Turn out flatvel back into our vel
    simulation.state.vel = Vector3.new(flatVel.x, simulation.state.vel.y, flatVel.z)

    --Do jumping?
    if simulation.state.jump > 0 then
        simulation.state.jump -= cmd.deltaTime
        if simulation.state.jump < 0 then
            simulation.state.jump = 0
        end
    end

    local isGoalkeeper = simulation.isGoalkeeper

    local playerInGame = simulation.playerInGame
    if onGround ~= nil then
        --jump!
    
        if cmd.y > 0 and simulation.state.jump <= 0 and simulation.state.stam - GameInfo.JUMP_STAMINA_CONSUMPTION >= 0 then
            simulation.state.vel = Vector3.new(simulation.state.vel.X, simulation.constants.jumpPunch, simulation.state.vel.Z)
            simulation.state.jump = 0.2 --jumping has a cooldown (think jumping up a staircase)
            simulation.state.jumpThrust = simulation.constants.jumpThrustPower
            simulation.characterData:PlayAnimation("Jump", Enums.AnimChannel.Channel0, true, 0.2)
    
            if playerInGame then
                simulation.state.stam -= GameInfo.JUMP_STAMINA_CONSUMPTION
                simulation.state.stamRegCD = 0.5
            end
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
            simulation.characterData:PlayAnimation("Fall", Enums.AnimChannel.Channel0, false)
        end
    else
        simulation.state.inAir = 0
    end

    --Sweep the player through the world, once flat along the ground, and once "step up'd"
    local stepUpResult = nil
    local walkNewPos, walkNewVel, hitSomething = simulation:ProjectVelocity(simulation.state.pos, simulation.state.vel, cmd.deltaTime)

    -- Ball rotation and character lean
    if not simulation.characterData.isResimulating and simulation.playerInGameOrPausedOrEnded then
        local moveDirection: Vector3 = walkNewVel * Vector3.new(1, 0, 1)
        local vel = (moveDirection.Magnitude / 16)

        moveDirection = moveDirection.Unit
        local angle = simulation.state.angle
        local characterDirection = -Vector3.new(math.sin(angle), 0, math.cos(angle))
        local dot = moveDirection:Dot(characterDirection)

        local rightAngle = math.acos(math.min(1, math.abs(dot)))
        local cross = moveDirection:Cross(characterDirection)
        local rotateRight = math.sin(rightAngle) * math.sign(cross.Y)
    
        local rotateMulti = vel*0.125
        local rotateCFrame = CFrame.Angles(rotateMulti * dot, 0, rotateMulti * rotateRight)

        local walkAnimDir = dot
        if walkAnimDir > -0.1 then
            walkAnimDir = 0
        else
            walkAnimDir = 1
        end

        local alpha = math.min(1, cmd.deltaTime*8)

        if IsClient then
            if walked and moveDirection == moveDirection then
                simulation:ChangeBallRotation(rotateCFrame)
                simulation:SetAnimDir(walkAnimDir)
            end

            local realLeanAngle = Vector2.new(rotateMulti * dot, rotateMulti * rotateRight)
            if realLeanAngle ~= realLeanAngle then
                realLeanAngle = Vector2.zero
            end
            simulation:LerpLeanAngle(-realLeanAngle, alpha)
        else
            if walked and moveDirection == moveDirection then
                simulation.characterData:ChangeBallRotation(rotateCFrame)
                simulation.characterData:SetAnimDir(walkAnimDir)
            end

            local realLeanAngle = Vector2.new(rotateMulti * dot, rotateMulti * rotateRight)
            if realLeanAngle == realLeanAngle then
                simulation.characterData:LerpLeanAngle(-realLeanAngle, alpha)
            end
        end
    elseif player and not simulation.characterData.isResimulating then
        if IsClient and localPlayer == player then
            simulation:SetLeanAngle(Vector2.zero)
        elseif not IsClient then
            simulation.characterData:SetAnimDir(0)
        end
    end

    if IsClient and not simulation.characterData.isResimulating and simulation.playerInGameOrPausedOrEnded
    and onGround == nil and simulation.state.vel.Y < -30 then
        --Land after jump
        local groundTopPos =42.777+1.299 /2 + 2.5
        local groundCheck = walkNewPos.Y - groundTopPos < 0.1
        if groundCheck then
            -- player landed on floor
        end
    end
    if IsClient and not simulation.characterData.isResimulating and simulation.runningSound then
        if onGround then
            if wishDir ~= nil and not simulation.movementDisabled then
                local floorMaterial = "Plastic"
                if simulation.playerInGameOrPausedOrEnded then
                    floorMaterial = simulation.groundType
                end

                local materialSoundData = FootstepSounds[floorMaterial]
                simulation.runningSound.SoundId = materialSoundData.id
                simulation.runningSound.Volume = materialSoundData.volume * 2
                simulation.runningSound.PlaybackSpeed = (flatVel.Magnitude / 16) * materialSoundData.speed
                simulation.runningSound.Playing = true
            else
                simulation.runningSound.Playing = false
            end
        else
            simulation.runningSound.Playing = false
        end
    end


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

    if isGoalkeeper and simulation.teleported and simulation:IsInMatch() then
        local boundary = boundaries[player.Team.Name]
        if boundary == nil then
            return
        end

        simulation.state.pos = MathUtils:ClampToBoundary(simulation.state.pos, boundary.Position, boundary.Size)
    end
end

return module