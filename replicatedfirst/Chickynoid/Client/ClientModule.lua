--!native
--[=[
    @class ClientModule
    @client

    Client namespace for the Chickynoid package.
]=]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local RemoteEvent = ReplicatedStorage:WaitForChild("ChickynoidReplication") :: RemoteEvent
local UnreliableRemoteEvent = ReplicatedStorage:WaitForChild("ChickynoidUnreliableReplication") :: RemoteEvent

local path = script.Parent.Parent

local ClientChickynoid = require(script.Parent.ClientChickynoid)
local CollisionModule = require(path.Shared.Simulation.CollisionModule)
local CharacterModel = require(script.Parent.CharacterModel)
local CharacterData = require(path.Shared.Simulation.CharacterData)
local FastSignal = require(path.Shared.Vendor.FastSignal)
local ClientMods = require(path.Client.ClientMods)
local Animations = require(path.Shared.Simulation.Animations)

local ClientBallController = require(script.Parent.ClientBallController)
local BallData = require(path.Shared.Simulation.BallData)
local BallModel = require(script.Parent.BallModel)

local Enums = require(path.Shared.Enums)
local MathUtils = require(path.Shared.Simulation.MathUtils)
local CrunchTable = require(path.Shared.Vendor.CrunchTable)
local CommandLayout = require(path.Shared.Simulation.CommandLayout)
local BallInfoLayout = require(path.Shared.Simulation.BallInfoLayout)

local FpsGraph = require(path.Client.FpsGraph)
local NetGraph = require(path.Client.NetGraph)

local Lib = require(ReplicatedFirst.Lib)

local EventType = Enums.EventType
local ClientModule = {}

ClientModule.localChickynoid = nil
ClientModule.snapshots = {}

ClientModule.localBallController = nil
ClientModule.ballModel = nil
ClientModule.prevLocalBallData = nil


ClientModule.estimatedServerTime = 0 --This is the time estimated from the snapshots
ClientModule.estimatedServerTimeOffset = 0
ClientModule.snapshotServerFrame = 0	--Server frame of the last snapshot we got
ClientModule.mostRecentSnapshotComparedTo = nil --When we've successfully compared against a previous snapshot, mark what it was (so we don't delete it!)

ClientModule.validServerTime = false
ClientModule.startTime = tick()
ClientModule.characters = {}
ClientModule.localFrame = 0
ClientModule.worldState = nil
ClientModule.fpsMax = 144 --Think carefully about changing this! Every extra frame clients make, puts load on the server
ClientModule.fpsIsCapped = true --Dynamically sets to true if your fps is fpsMax + 5
ClientModule.fpsMin = 25 --If you're slower than this, your step will be broken up

ClientModule.cappedElapsedTime = 0 --
ClientModule.timeSinceLastThink = 0
ClientModule.timeUntilRetryReset = tick() + 15 -- 15 seconds grace on connection
ClientModule.frameCounter = 0
ClientModule.frameSimCounter = 0
ClientModule.frameCounterTime = 0
ClientModule.stateCounter = 0 --Num states coming in

ClientModule.accumulatedTime = 0

ClientModule.debugBoxes = {}
ClientModule.debugMarkPlayers = nil

--Netgraph settings
ClientModule.showFpsGraph = false
ClientModule.showNetGraph = false
ClientModule.showDebugMovement = true

ClientModule.ping = 0
ClientModule.pings = {}

ClientModule.useSubFrameInterpolation = true
ClientModule.prevLocalCharacterData = nil

ClientModule.timeOfLastData = tick()

--The local character
ClientModule.characterModel = nil

--Server provided collision data
ClientModule.playerSize = Vector3.new(2,5,5)
ClientModule.collisionRoot = game.Workspace

--Milliseconds of *extra* buffer time to account for ping flux
ClientModule.interpolationBuffer = 20

--Signals
ClientModule.OnNetworkEvent = FastSignal.new()
ClientModule.OnCharacterModelCreated = FastSignal.new()
ClientModule.OnCharacterModelDestroyed = FastSignal.new()

--Callbacks
ClientModule.characterModelCallbacks = {}

ClientModule.partialSnapshot = nil
ClientModule.partialSnapshotFrame = 0

ClientModule.gameRunning = false

ClientModule.flags = {
	HANDLE_CAMERA = true,
	USE_PRIMARY_PART = false,
	USE_ALTERNATE_TIMING = false,
}

ClientModule.shotInfo = nil :: {}?
ClientModule.doShotOnClient = true :: boolean
ClientModule.deflectInfo = nil :: {}?
ClientModule.doDeflectOnClient = false :: boolean
ClientModule.playerAction = nil :: string?
ClientModule.skillServerTime = nil :: number?
ClientModule.skillGuid = nil :: number?

ClientModule.lastResimulatedFrame = 0
ClientModule.lastResimulatedBallFrame = 0

local localPlayer = Players.LocalPlayer
local currentCamera = workspace.CurrentCamera



function ClientModule:Setup()
    self.localBallController = ClientBallController.new(Vector3.zero)
    self.ballModel = BallModel.new()
    self.ballModel:CreateModel()

    local eventHandler = {}

    eventHandler[EventType.DebugBox] = function(event)
        ClientModule:DebugBox(event.pos, event.text)
    end

    --EventType.ChickynoidAdded
    eventHandler[EventType.ChickynoidAdded] = function(event)
        local position = event.position
        print("Chickynoid spawned at", position)

        if self.localChickynoid == nil then
            self.localChickynoid = ClientChickynoid.new(position, event.characterMod)
        end
        --Force the state
        self.localChickynoid.simulation:ReadState(event.state)
        self.prevLocalCharacterData = nil
    end

    eventHandler[EventType.ChickynoidRemoving] = function(_event)
        print("Local chickynoid removing")

        if self.localChickynoid ~= nil then
            self.localChickynoid:Destroy()
            self.localChickynoid = nil
        end

        self.prevLocalCharacterData = nil
        self.characterModel:DestroyModel()
        self.characterModel = nil
		localPlayer.Character = nil :: any
		
		self.characters[localPlayer.UserId] = nil
    end 

    -- EventType.State
    local function ballStateChanged(becameNetworkOwner: boolean, newAction: number)
        if not becameNetworkOwner then
            return
        end

        if newAction == Enums.BallActions.Deflect then
            local playerSimulation = self.localChickynoid.simulation
            playerSimulation.characterData:PlayAnimation("Shoot", Enums.AnimChannel.Channel1, true, 0.01)
        end
        if newAction ~= Enums.BallActions.ServerClaim then
            return
        end

        local isGoalkeeper = localPlayer:GetAttribute("Position") == "Goalkeeper"
        if isGoalkeeper then
            return
        end

        local ballState = self.localBallController.simulation.state
        local deflectInfo = self.deflectInfo
        if deflectInfo == nil then
            local action = self.playerAction
            local realAction = action
            if realAction == "Shoot" then
                realAction = "DeflectShoot"
            end

            if realAction then
                
                local shotDirection = Lib.getShotDirection()
                local curveFactor = localPlayer:GetAttribute("CurveFactor")
                local shotPower = localPlayer:GetAttribute("ShotPower")
                self.deflectInfo = {
                    guid = ballState.guid,
                    shotType = realAction,
                    shotPower = shotPower,
                    shotDirection = shotDirection,
                    curveFactor = curveFactor,
                }
                deflectInfo = self.deflectInfo
            end
        end

        if deflectInfo == nil then
            return
        end
        deflectInfo.guid = ballState.guid
        deflectInfo.serverClaimOverride = true
        self.doDeflectOnClient = true
        -- ballState.ownerId = 0
        -- self:DoBallDeflectionOnClient()
    end
    eventHandler[EventType.State] = function(event)
        if self.localChickynoid == nil then
			return
        end

        if self.lastResimulatedFrame == self.localFrame then
            return
        end
        self.lastResimulatedFrame = self.localFrame

        local mispredicted, ping, commandsRun = self.localChickynoid:HandleNewPlayerState(event.playerStateDelta, event.playerStateDeltaFrame, event.lastConfirmedCommand, event.serverTime, event.serverFrame)
        if event.ballState then
            local becameNetworkOwner, newAction = self.localBallController:HandleNewPlayerState(event.ballState, nil, event.ballFrame, event.serverTime, event.serverFrame, commandsRun)
            ballStateChanged(becameNetworkOwner, newAction)
        end
      
        if (ping) then
            --Keep a rolling history of pings
            table.insert(self.pings, ping)
            if #self.pings > 20 then
                table.remove(self.pings, 1)
            end

            self.stateCounter += 1
            
            if (self.showNetGraph == true) then
                self:AddPingToNetgraph(mispredicted, event.s, event.e, ping)
            end
            
            if (mispredicted) then
                FpsGraph:SetFpsColor(Color3.new(1,1,0))
            else
                FpsGraph:SetFpsColor(Color3.new(0,1,0))
            end
        end
    end
    eventHandler[EventType.BallState] = function(event)
        if self.localChickynoid == nil then
            return
        end

        if self.lastResimulatedBallFrame == self.localFrame then
            return
        end
        self.lastResimulatedBallFrame = self.localFrame

        local remainingCommands = {}
        for _, cmd in self.localChickynoid.predictedCommands do
            if cmd.localFrame > event.lastConfirmedCommand then
                table.insert(remainingCommands, cmd)
            end
        end
        local becameNetworkOwner, newAction = self.localBallController:HandleNewPlayerState(event.ballState, nil, event.ballFrame, event.serverTime, event.serverFrame, #remainingCommands)
        ballStateChanged(becameNetworkOwner, newAction)
    end

    -- EventType.WorldState
    eventHandler[EventType.WorldState] = function(event)
        -- print("Got worldstate")
		self.worldState = event.worldState
		
		Animations:SetAnimationsFromWorldState(event.worldState.animations)
    end
	
		
    -- EventType.Snapshot
	eventHandler[EventType.Snapshot] = function(event)
		
		
        event = self:DeserializeSnapshot(event)
		
		if (event == nil) then
			return
		end
		
		
		if (self.partialSnapshot ~= nil and event.f < self.partialSnapshotFrame) then
			--Discard, part of an abandoned snapshot
			warn("Discarding old snapshot piece.")
			return
		end
		
		if (self.partialSnapshot ~= nil and event.f ~= self.partialSnapshotFrame) then
			warn("Didnt get all the pieces of a snapshot, discarding and starting anew")
			self.partialSnapshot = nil
		end
		
		if (self.partialSnapshot == nil) then
			self.partialSnapshot = {}
			self.partialSnapshotFrame = event.f
		end
		
		if (event.f == self.partialSnapshotFrame) then
			--Store it
		
			self.partialSnapshot[event.s] = event
			
			local foundAll = true
			for j=1,event.m do
			 
				if (self.partialSnapshot[j] == nil) then
					foundAll = false
					break
				end
			end
			
			if (foundAll == true) then
				
				self:SetupTime(event.serverTime)
				
				--Concatenate all the player records in here
				local newRecords = {}
				for _,snap in self.partialSnapshot do
					for key,rec in snap.charData do
						newRecords[key] = rec
					end
				end
				event.charData = newRecords			
				
				--Record our snapshotServerFrame - this is used to let the server know what we have correctly seen
				self.snapshotServerFrame = event.f
			 				
				--Record the snapshot
				table.insert(self.snapshots, event)
				self.previousSnapshot = event

				--Remove old ones, but keep the most recent one we compared to
				while (#self.snapshots > 40) do
					table.remove(self.snapshots,1)
				end
				--Clear the partial
				self.partialSnapshot = nil
			end
		end
    end

    eventHandler[EventType.CollisionData] = function(event)
        self.playerSize = event.playerSize
        self.collisionRoot = event.data
        CollisionModule:MakeWorld(self.collisionRoot, self.playerSize)
	end
	
	eventHandler[EventType.PlayerDisconnected] = function(event)
		local characterRecord = self.characters[event.userId]
        if (characterRecord and characterRecord.characterModel) then
            characterRecord.characterModel:DestroyModel()
        end
        --Final Cleanup
        CharacterModel:PlayerDisconnected(event.userId)
	end


    RemoteEvent.OnClientEvent:Connect(function(event)
        self.timeOfLastData = tick()

        local func = eventHandler[event.t]
        if func ~= nil then
            func(event)
        else
            self.OnNetworkEvent:Fire(self, event)
        end
	end)
	

	UnreliableRemoteEvent.OnClientEvent:Connect(function(event)
		self.timeOfLastData = tick()

		local func = eventHandler[event.t]
		if func ~= nil then
			func(event)
		else
			self.OnNetworkEvent:Fire(self, event)
		end
	end)


    local function Step(deltaTime)
		
		if (self.gameRunning == false) then
			return
		end
		
        if (self.showFpsGraph == false) then
            FpsGraph:Hide()
        end
        if (self.showNetGraph == false) then
            NetGraph:Hide()
        end

        self:DoFpsCount(deltaTime)
  
        --Do a framerate cap to 144? fps
        self.cappedElapsedTime += deltaTime
        self.timeSinceLastThink += deltaTime
        local fraction = 1 / self.fpsMax
		
		--Do we process a frame?
        if self.cappedElapsedTime < fraction and self.fpsIsCapped == true then
            return --If not enough time for a whole frame has elapsed
        end
		self.cappedElapsedTime = math.fmod(self.cappedElapsedTime, fraction)
		
		
		--Netgraph
        if (self.showFpsGraph == true) then
            FpsGraph:Scroll()
            local fps = 1 / self.timeSinceLastThink
            FpsGraph:AddBar(fps / 2, FpsGraph.fpsColor, 0)
        end
		
		--Think
		self:ProcessFrame(self.timeSinceLastThink)

		--Do Client Mods
        local modules = ClientMods:GetMods("clientmods")
        for _, value in pairs(modules) do
			value:Step(self, self.timeSinceLastThink)
		end
		
		self.timeSinceLastThink = 0
	end
	
	
	local bindToRenderStepLatch = false
 
	--BindToRenderStep is the correct place to step your own custom simulations. The dt is the same one used by particle systems and cameras.
	--1) The deltaTime is sampled really early in the frame and has the least flux (way less than heartbeat)
	--2) Functionally, this is similar to PreRender, but PreRender runs AFTER the camera has updated, but we need to run before it 
	--	 	(hence Enum.RenderPriority.Input)
	--3) Oh No. BindToRenderStep is not called in the background, so we use heartbeat to call Step if BindToRenderStep is not available
	RunService:BindToRenderStep("chickynoidCharacterUpdate", Enum.RenderPriority.Input.Value, function(dt) 
		
		if (self.flags.USE_ALTERNATE_TIMING == true) then
			if (dt > 0.2) then
				dt = 0.2
			end
			Step(dt)
			bindToRenderStepLatch = false
		else
			
		end
	end)
		
    -- task.spawn(function()
    --     while true do
    --         local dt = task.wait()
    --         xpcall(function()
    --             Step(dt)
    --         end, function(errorMessage)
    --             warn("[ClientModule] Failed to step: " .. errorMessage)
    --         end)
    --     end
    -- end)
	RunService.Heartbeat:Connect(function(dt)
		
		if (self.flags.USE_ALTERNATE_TIMING == true) then
			if (bindToRenderStepLatch == true) then
				Step(dt)
			end
			bindToRenderStepLatch = true
		else
			Step(dt)
		end
	end)
	
    --Load the mods
    local mods = ClientMods:GetMods("clientmods")
    for _, mod in mods do
        mod:Setup(self)
		print("Loaded", _)
    end
	
	--Wait for the game to be loaded
	task.spawn(function()
		
		while(game:IsLoaded() == false) do
			wait()
		end
		print("Sending loaded event")
		self.gameRunning = true
		
		--Notify the server
		local event = {}
		event.id = "loaded"
		RemoteEvent:FireServer(event)
	end)
	
	
end

function ClientModule:GetClientChickynoid()
    return self.localChickynoid
end

function ClientModule:GetCollisionRoot()
    return self.collisionRoot 
end

 
function ClientModule:DoFpsCount(deltaTime)
    self.frameCounter += 1
    self.frameCounterTime += deltaTime

    if self.frameCounterTime > 1 then
        while self.frameCounterTime > 1 do
            self.frameCounterTime -= 1
        end
        --print("FPS: real ", self.frameCounter, "( physics: ",self.frameSimCounter ,")")

        if self.frameCounter > self.fpsMax + 5 then
            if (self.showFpsGraph == true) then
                FpsGraph:SetWarning("(Cap your fps to " .. self.fpsMax .. ")")
            end
            self.fpsIsCapped = true
        else
            if (self.showFpsGraph == true) then
                FpsGraph:SetWarning("")
            end
            self.fpsIsCapped = false
        end
        if (self.showFpsGraph == true) then
            if self.frameCounter == self.frameSimCounter then
                FpsGraph:SetFpsText("Fps: " .. self.frameCounter .. " CmdRate: " .. self.stateCounter)
            else
                FpsGraph:SetFpsText("Fps: " .. self.frameCounter .. " Sim: " .. self.frameSimCounter)
            end
        end

        self.frameCounter = 0
        self.frameSimCounter = 0
        self.stateCounter = 0
    end
end

--Use this instead of raw tick()
function ClientModule:LocalTick()
    return tick() - self.startTime
end



local ballHitbox = Instance.new("Part")
ballHitbox.Shape = Enum.PartType.Ball
ballHitbox.Size = Vector3.new(2, 2, 2)
ballHitbox.Transparency = 1
ballHitbox.Anchored = true
ballHitbox.CanCollide = false
ballHitbox.CanQuery = true
ballHitbox.CanTouch = false
function ClientModule:DoBallDeflectionOnClient()
    local networkPing = localPlayer:GetAttribute("NetworkPing") or 0
    local lagCompensation = networkPing/1000 + 0.3

    local deflectInfo = self.deflectInfo
    local shotType, shotPower, shotDirection, curveFactor = deflectInfo.shotType, deflectInfo.shotPower, deflectInfo.shotDirection, deflectInfo.curveFactor

    local ballSimulation = self.localBallController.simulation
    local vel, angVel = Lib.getShotVelocity(ballSimulation.constants.gravity, shotType, shotPower, shotDirection, curveFactor)
    ballSimulation.state.vel = vel
    ballSimulation.state.angVel = angVel

    local boundary = workspace.MapItems.BallBoundary
    local playerSimulation = self.localChickynoid.simulation
    local playerCF = CFrame.new(playerSimulation.state.pos) * CFrame.Angles(0, playerSimulation.state.angle, 0)
    local ballPos = (playerCF * CFrame.new(0, -1.65, -2)).Position
    ballSimulation.state.pos = Lib.clampToBoundary(ballPos, boundary)
    ballSimulation.ballData:SetTargetPosition(ballSimulation.state.pos)


    ballSimulation.state.ownerId = 0
    self.localBallController.mispredict = Vector3.zero
    self.localBallController.ignoreServerState = tick() + lagCompensation


    localPlayer:SetAttribute("DisableChargeShot", true)
    localPlayer:SetAttribute("DisableChargeShot", false)

    localPlayer:SetAttribute("ClearTrail", true)

    local controllers = localPlayer.PlayerScripts.ClientScripts.Controllers
    local EffectController = require(controllers.EffectController)
    EffectController:CreateEffect("ballKicked", {localPlayer})
end

function ClientModule:ProcessFrame(deltaTime)
    if self.worldState == nil then
        --Waiting for worldstate
        return
    end
    --Have we at least tried to figure out the server time?
    if self.validServerTime == false then
        return
    end

    debug.profilebegin("Chickynoid Set Up ProcessFrame")
    --stats
    self.frameSimCounter += 1

    --Do a new frame!!
    self.localFrame += 1

    --Start building the world view, based on us having enough snapshots to do so
    self.estimatedServerTime = self:LocalTick() - self.estimatedServerTimeOffset

    --Calc the SERVER point in time to render out
    --Because we need to be between two snapshots, the minimum search time is "timeBetweenFrames"
    --But because there might be network flux, we add some extra buffer too
    local timeBetweenServerFrames = (1 / self.worldState.serverHz)
    local searchPad = math.clamp(self.interpolationBuffer, 0, 500) * 0.001
    local pointInTimeToRender = self.estimatedServerTime - (timeBetweenServerFrames + searchPad)

    local subFrameFraction = 0

    local bulkMoveToList = { parts = {}, cframes = {} }
    debug.profileend()

    --Step the chickynoid
    if self.localChickynoid then
        local fixedPhysics = nil
        if self.worldState.fpsMode == Enums.FpsMode.Hybrid then
            if deltaTime >= 1 / 30 then
                fixedPhysics = 30
            end
        elseif self.worldState.fpsMode == Enums.FpsMode.Fixed30 then
            fixedPhysics = 20
        elseif self.worldState.fpsMode == Enums.FpsMode.Fixed60 then
            fixedPhysics = 60
        elseif self.worldState.fpsMode == Enums.FpsMode.Uncapped then
            fixedPhysics = nil
        else
            warn("Unhandled FPS Mode")
        end

        if fixedPhysics ~= nil then
            --Fixed physics steps
            local frac = 1 / fixedPhysics

            deltaTime = math.min(frac*4, deltaTime)

            self.accumulatedTime += deltaTime
            local count = 0

            local simulatingFrames = self.accumulatedTime > 0
            if simulatingFrames then
                debug.profilebegin("Chickynoid Do Attribute Checks")
                self.localChickynoid.simulation:DoPlayerAttributeChecks()
                self.localBallController.simulation:DoServerAttributeChecks()
                debug.profileend()
            end

            while self.accumulatedTime > 0 do
                self.accumulatedTime -= frac

                if self.useSubFrameInterpolation == true then
                    --Todo: could do a small (rarely used) optimization here and only copy the 2nd to last one..
                    if self.localChickynoid.simulation.characterData ~= nil then
                        --Capture the state of the client before the current simulation
                        debug.profilebegin("Chickynoid Serialize CharacterData")
                        self.prevLocalCharacterData = self.localChickynoid.simulation.characterData:Serialize()
                        self.prevLocalCustomData = table.clone(self.localChickynoid.simulation.custom)
                        debug.profileend()
                    end
                    if self.localBallController.simulation.ballData ~= nil then
                        --Capture the state of the client before the current simulation
                        debug.profilebegin("Chickynoid Serialize BallData")
                        self.prevLocalBallData = self.localBallController.simulation.ballData:Serialize()
                        self.prevBallRotation = self.localBallController.simulation.rotation
                        debug.profileend()
                    end
                end

				--Step!
				 
                debug.profilebegin("Chickynoid Generate Command")
				local command = self:GenerateCommandBase(pointInTimeToRender, frac)
                debug.profileend()

                self.localChickynoid:Heartbeat(command, pointInTimeToRender, frac)
                local _, hitPlayer = self.localBallController:Heartbeat(table.clone(command), pointInTimeToRender, frac)




                
                -- Custom system to work with Power-Up Soccer
                local dataToSend = {}

                -- Shooting
                local function setShotInfo(override)
                    local info = override or self.shotInfo or {}

                    local shotSerial = {"Shoot"}
                    dataToSend.sGuid = info.guid
                    dataToSend.sType = table.find(shotSerial, info.shotType)
                    dataToSend.sPower = info.shotPower
                    dataToSend.sDirection = info.shotDirection
                    dataToSend.sCurveFactor = info.curveFactor
                end

                local Lib = require(ReplicatedStorage.Lib)

                debug.profilebegin("Chickynoid Shot Info")
                local ballSimulation = self.localBallController.simulation
                local ballState = ballSimulation.state
                local shotInfo = self.shotInfo
                if shotInfo and shotInfo.guid < ballState.guid then
                    self.shotInfo = nil
                    shotInfo = nil
                    setShotInfo()
                    Lib.removeCooldown(localPlayer, "ClientBallClaimCooldown")
                end

                local networkPing = localPlayer:GetAttribute("NetworkPing") or 0
                local lagCompensation = networkPing/1000 + 0.3
                if shotInfo and self.doShotOnClient then
                    self.doShotOnClient = false
                    task.spawn(function()
                        if not game:IsLoaded() then
                            return
                        end

                        local shotType, shotPower, shotDirection, curveFactor = shotInfo.shotType, shotInfo.shotPower, shotInfo.shotDirection, shotInfo.curveFactor
                        Lib.setCooldown(localPlayer, "ClientBallClaimCooldown", lagCompensation)
                        
                        local boundary = workspace.MapItems.BallBoundary
                        local playerSimulation = self.localChickynoid.simulation
                        local playerCF = CFrame.new(playerSimulation.state.pos) * CFrame.Angles(0, playerSimulation.state.angle, 0)
                        local ballPos = (playerCF * CFrame.new(0, -1.65, -2)).Position
                        if localPlayer:GetAttribute("Position") == "Goalkeeper" then
                            ballPos = (playerCF * CFrame.new(0, 1, -2)).Position
                        end
                        ballSimulation.state.pos = Lib.clampToBoundary(ballPos, boundary)
                        ballSimulation.ballData:SetTargetPosition(ballSimulation.state.pos)

                        local vel, angVel = Lib.getShotVelocity(ballSimulation.constants.gravity, shotType, shotPower, shotDirection, curveFactor)
                        ballSimulation.state.vel = vel
                        ballSimulation.state.angVel = angVel
                    
                        ballSimulation.state.ownerId = 0

                        self.localBallController.mispredict = Vector3.zero
                        self.localBallController.ignoreServerState = tick() + lagCompensation

                        local controllers = localPlayer.PlayerScripts.ClientScripts.Controllers
                        local EffectController = require(controllers.EffectController)
                        EffectController:CreateEffect("ballKicked", {localPlayer})
                    end)
                end
                setShotInfo() -- keep sending it in case it gets lost, shooting is something that needs to always be received by the server
                debug.profileend()


                debug.profilebegin("Chickynoid Deflect Info")
                -- Deflection
                local simulation = self.localChickynoid.simulation
                local function setDeflectInfo(override)
                    local info = override or self.deflectInfo or {}

                    local shotSerial = {"DeflectShoot"}
                    dataToSend.dGuid = info.guid
                    dataToSend.dType = table.find(shotSerial, info.shotType)
                    dataToSend.dPower = info.shotPower
                    dataToSend.dDirection = info.shotDirection
                    dataToSend.dCurveFactor = info.curveFactor
                    dataToSend.dServerDeflect = if info.serverClaimOverride then 1 else nil
                end
                local deflectInfo = self.deflectInfo
                if deflectInfo and deflectInfo.guid < ballState.guid then
                    self.deflectInfo = nil
                    deflectInfo = nil
                    setDeflectInfo()
                end
                if deflectInfo and deflectInfo.serverClaimOverride then
                    dataToSend.claimPos = ballSimulation.state.pos
                    setDeflectInfo()
                    if self.doDeflectOnClient then
                        self.doDeflectOnClient = false
                        self:DoBallDeflectionOnClient()
                    end
                elseif hitPlayer and not Lib.isOnCooldown(localPlayer, "ClientBallClaimCooldown") then
                    dataToSend.claimPos = ballSimulation.state.pos
                    setDeflectInfo()

                    local action = self.playerAction
                    local realAction = action
                    if realAction == "Shoot" then
                        realAction = "DeflectShoot"
                    end

                    if realAction == nil then
                        self.deflectInfo = nil
                    end

                    local isGoalkeeper = localPlayer:GetAttribute("Position") == "Goalkeeper"
                    local ignoreServerState = self.localBallController.ignoreServerState
                    if not isGoalkeeper and (ignoreServerState == nil or tick() - ignoreServerState > 0) and not Lib.playerIsStunned(localPlayer) then
                        -- Deflection
                        local shotDirection = Lib.getShotDirection()
                
                        local curveFactor = localPlayer:GetAttribute("CurveFactor")
                
                        if realAction then
                            if deflectInfo == nil then
                                local shotPower = localPlayer:GetAttribute("ShotPower")
                                self.deflectInfo = {
                                    guid = ballState.guid,
                                    shotType = realAction,
                                    shotPower = shotPower,
                                    shotDirection = shotDirection,
                                    curveFactor = curveFactor,
                                }
                                setDeflectInfo()

                                if ballSimulation.state.netId == localPlayer.UserId then
                                    self:DoBallDeflectionOnClient()
                                end
                            end
                        else
                            if ballSimulation.state.netId == localPlayer.UserId and not deflectInfo then
                                ballSimulation.state.ownerId = localPlayer.UserId
                                self.localBallController.ignoreServerState = tick() + lagCompensation
                            end
                        end
                    end

                    if not self.deflectInfo and realAction then
                        dataToSend.claimPos = nil
                    end
                end
                if dataToSend.claimPos == nil and localPlayer:GetAttribute("Position") == "Goalkeeper" then
                    local overlapParams = OverlapParams.new()
                    overlapParams.FilterType = Enum.RaycastFilterType.Include
                    overlapParams.FilterDescendantsInstances = CollectionService:GetTagged("GoalHitbox")
                    local goalHitBox = workspace:GetPartBoundsInRadius(ballSimulation.state.pos, 1, overlapParams)
                    if goalHitBox[1] ~= nil then
                        dataToSend.enteredGoal = 1
                    end
                end
                debug.profileend()


                debug.profilebegin("Chickynoid Tackle")
                -- Tackling
                local assets = ReplicatedStorage.Assets
                if localPlayer:GetAttribute("InGame") and simulation.state.tackle > 0 then
                    xpcall(function()
                        local tackleHitBox: BasePart = assets.Hitboxes.Tackle
                        if localPlayer:GetAttribute("Position") == "Goalkeeper" then
                            local diveHitboxTemplate = assets.Hitboxes.Dive:FindFirstChild(localPlayer:GetAttribute("ClientDiveHitbox"))
                            if diveHitboxTemplate == nil then
                                return
                            end
                            tackleHitBox = diveHitboxTemplate
                        end

                        local filter = {}
                        for _, characterInfo in pairs(self.characters) do
                            if characterInfo.userId == localPlayer.UserId then
                                continue
                            end
                            local characterModel = characterInfo.characterModel
                            if characterModel and characterModel.model then
                                table.insert(filter, characterModel.model)
                            end
                        end
    
                        local overlapParams = OverlapParams.new()
                        overlapParams.FilterType = Enum.RaycastFilterType.Include
                        overlapParams.FilterDescendantsInstances = filter
    
                        local playerSimulation = self.localChickynoid.simulation
                        local playerCF = CFrame.new(playerSimulation.state.pos) * CFrame.Angles(0, playerSimulation.state.angle, 0)
                        local charactersToTackle = workspace:GetPartBoundsInBox(playerCF * tackleHitBox.PivotOffset:Inverse(), tackleHitBox.Size, overlapParams)
                        for _, part in pairs(charactersToTackle) do
                            local character = part.Parent
                            local userid = character:GetAttribute("userid")
                            if userid == nil then continue end
                            local player = Players:GetPlayerByUserId(userid)
                            if player == nil then continue end
                            if player.Ball.Value == nil then continue end
                            dataToSend.tackledEnemy = 1
                            break
                        end
                    end, function(errorMessage)
                        warn("[ClientModule] Tackle Hitbox error: " .. errorMessage)
                    end)
                end
                debug.profileend()

                debug.profilebegin("Chickynoid Skill")
                local skillServerTime = self.skillServerTime
                local skillGuid = self.skillGuid
                if skillServerTime and (skillGuid and skillGuid ~= ballSimulation.state.guid or self.estimatedServerTime - skillServerTime > 0.5) then
                    self.skillServerTime = nil
                    self.skillGuid = nil
                    skillServerTime = nil
                end
                if skillServerTime then
                    dataToSend.skill = skillServerTime
                    setDeflectInfo({})
                    self.skillGuid = ballSimulation.state.guid
                end
                debug.profileend()

                -- Pass to server
                debug.profilebegin("Chickynoid Encode Commands")
                dataToSend = BallInfoLayout:EncodeCommand(dataToSend)
                local event = {}
                event[1] = {
                    CommandLayout:EncodeCommand(command),
                    dataToSend,
                }

                local chickynoid = self.localChickynoid
                
                local prevCommand = nil
                if (#chickynoid.predictedCommands > 1 and chickynoid.commandPacketlossPrevention == true) then
                    prevCommand = chickynoid.predictedCommands[#chickynoid.predictedCommands - 1]
                    event[2] = {
                        CommandLayout:EncodeCommand(prevCommand),
                        self.lastDataSent,
                    }
                end
                self.lastDataSent = dataToSend
                debug.profileend()
                
                debug.profilebegin("Chickynoid Send To Server")
                UnreliableRemoteEvent:FireServer(event)
                debug.profileend()

                count += 1
            end
            if simulatingFrames then
                self.localChickynoid.simulation:UpdatePlayerAttributes()
            end

            if self.useSubFrameInterpolation == true then
                --if this happens, we have over-simulated
                if self.accumulatedTime < 0 then
                    --we need to do a sub-frame positioning
                    local subFrame = math.abs(self.accumulatedTime) --How far into the next frame are we (we've already simulated 100% of this)
                    subFrame /= frac --0..1
                    if subFrame < 0 or subFrame > 1 then
                        warn("Subframe calculation wrong", subFrame)
                    end
                    subFrameFraction = 1 - subFrame
                end
            end

            if (self.showFpsGraph == true) then
                if count > 0 then
                    local pixels = 1000 / fixedPhysics
                    FpsGraph:AddPoint((count * pixels), Color3.new(0, 1, 1), 3)
                    FpsGraph:AddBar(math.abs(self.accumulatedTime * 1000), Color3.new(1, 1, 0), 2)
                else
                    FpsGraph:AddBar(math.abs(self.accumulatedTime * 1000), Color3.new(1, 1, 0), 2)
                end
            end
        else
            --For this to work, the server has to accept deltaTime from the client
			local command = self:GenerateCommandBase(pointInTimeToRender, deltaTime) 
            self.localChickynoid:Heartbeat(command, pointInTimeToRender, deltaTime)
        end

        local mod = self:GetPlayerDataByUserId(localPlayer.UserId)
        if self.characterModel == nil and self.localChickynoid ~= nil then
            debug.profilebegin("Chickynoid Local Character Creation")

            --Spawn the character in
			-- print("Creating local model for UserId", localPlayer.UserId)
			self.characterModel = CharacterModel.new(localPlayer.UserId, mod.characterMod)
            for _, characterModelCallback in ipairs(self.characterModelCallbacks) do
                self.characterModel:SetCharacterModel(characterModelCallback)
            end

            self.characterModel.onModelCreated:Connect(function()
                self.OnCharacterModelCreated:Fire(self.characterModel)
            end)
			self.characterModel:CreateModel(mod.avatar)
			
			local record = {}
			record.userId = localPlayer.UserId
			record.characterModel = self.characterModel
			record.localPlayer = true
			self.characters[record.userId] = record

            debug.profileend()
        elseif self.characterModel and self.characterModel.characterMod ~= mod.characterMod then
            if not self.characterModel.coroutineStarted then
                debug.profilebegin("Chickynoid Replace Local Character Model")
                self.characterModel.characterMod = mod.characterMod
                self.characterModel:ReplaceModel(mod.avatar)
                debug.profileend()
            end
        end

        if self.characterModel ~= nil then
            --Blend out the mispredict value

            debug.profilebegin("Chickynoid Local Character Mispredict")
            self.localChickynoid.mispredict = MathUtils:VelocityFriction(
                self.localChickynoid.mispredict,
                0.1,
                deltaTime
            )
            self.characterModel.mispredict = self.localChickynoid.mispredict

            self.localBallController.mispredict = MathUtils:VelocityFriction(
                self.localBallController.mispredict,
                0.1,
                deltaTime
            )
            self.ballModel.mispredict = self.localBallController.mispredict
            debug.profileend()

			
			local localRecord = self.characters[localPlayer.UserId]
						
            if
                self.useSubFrameInterpolation == false
                or subFrameFraction == 0
                or self.prevLocalCharacterData == nil
            then
                self.characterModel:Think(deltaTime, self.localChickynoid.simulation.characterData.serialized, bulkMoveToList, self.localChickynoid.simulation.custom)
                localRecord.characterData = self.localChickynoid.simulation.characterData
            else
                --Calculate a sub-frame interpolation
                debug.profilebegin("Chickynoid Local Character Interpolation")
                local data = CharacterData:Interpolate(
                    self.prevLocalCharacterData,
                    self.localChickynoid.simulation.characterData.serialized,
                    subFrameFraction
                )

                local currentCustomData = self.localChickynoid.simulation.custom
                local customData = table.clone(self.prevLocalCustomData)
                customData.animDir = currentCustomData.animDir
                customData.leanAngle = MathUtils:Vector2Lerp(customData.leanAngle, currentCustomData.leanAngle, subFrameFraction)
                customData.ballQuaternion = customData.ballQuaternion:Slerp(currentCustomData.ballQuaternion, subFrameFraction)
                debug.profileend()

                self.characterModel:Think(deltaTime, data, bulkMoveToList, customData)
                localRecord.characterData = data
                self.recordCustomData = customData
            end

            debug.profilebegin("Chickynoid Local Ball Think")
            local currentRotation = self.localBallController.simulation.rotation
            if
                self.useSubFrameInterpolation == false
                or subFrameFraction == 0
                or self.prevLocalBallData == nil
            then
                self.ballModel:Think(deltaTime, self.localBallController.simulation.ballData.serialized, bulkMoveToList, currentRotation)
            else
                local ballData = BallData:Interpolate(
                    self.prevLocalBallData,
                    self.localBallController.simulation.ballData.serialized,
                    subFrameFraction
                )
                self.ballModel:Think(deltaTime, ballData, bulkMoveToList, self.prevBallRotation:Slerp(currentRotation, subFrameFraction))
            end
            debug.profileend()
			
			--store local data
			localRecord.frame = self.localFrame
			localRecord.position = localRecord.characterData.pos
				
            if (self.showFpsGraph == true) then
                if self.showDebugMovement == true then
					local pos = localRecord.position
                    if self.previousPos ~= nil then
                        local delta = pos - self.previousPos
                        FpsGraph:AddPoint(delta.magnitude * 200, Color3.new(0, 0, 1), 4)
                    end
                    self.previousPos = pos
                end
            end

            -- Bind the camera
            if (self.flags.HANDLE_CAMERA ~= false) then
				local camera = game.Workspace.CurrentCamera
				
				if (self.flags.USE_PRIMARY_PART == true) then
					--if you dont care about first person, this is the correct way to do it
					--for models with no humanoid (head tracking)
					if ( self.characterModel.model and  self.characterModel.model.PrimaryPart) then
	                	if camera.CameraSubject ~= self.characterModel.model.PrimaryPart then
							camera.CameraSubject = self.characterModel.model.PrimaryPart
							camera.CameraType = Enum.CameraType.Custom
						end
					end
				else
					--if you do, set it to the model
					if self.characterModel.model and camera.CameraSubject ~= self.characterModel.model then
                        if not localPlayer:GetAttribute("Spectating") and not localPlayer:GetAttribute("GoalScoredFocus") then
                            debug.profilebegin("Chickynoid - setting camera subject")
                            camera.CameraSubject = self.characterModel.model
                            camera.CameraType = Enum.CameraType.Custom
                            debug.profileend()
                        end
					end
				end
            end

            --Bind the local character, which activates all the thumbsticks etc
            debug.profilebegin("Chickynoid Local Character Set")
            localPlayer.Character = self.characterModel.model
            debug.profileend()
        end    
    end

    debug.profilebegin("Chickynoid Snapshot Finder")
    local last = nil
    local prev = self.snapshots[1]
    for _, value in pairs(self.snapshots) do
        if value.serverTime > pointInTimeToRender then
            last = value
            break
        end
        prev = value
    end
    debug.profileend()
	
	local debugData = {}
	
    debug.profilebegin("Chickynoid Character Creation/Thinking")

	if prev and last and prev ~= last then
		
        --So pointInTimeToRender is between prev.t and last.t
        local frac = (pointInTimeToRender - prev.serverTime) / timeBetweenServerFrames
		
		debugData.frac = frac
		debugData.prev = prev.t
		debugData.last = last.t
		
		 
		for userId, lastData in last.charData do
	
            local prevData = prev.charData[userId]

            if prevData == nil then
                continue
            end
		
            local dataRecord = CharacterData:Interpolate(prevData, lastData, frac)
            local character = self.characters[userId]

            --Add the character
            local mod = self:GetPlayerDataByUserId(userId)
            if character == nil then
                local record = {}
				record.userId = userId
				record.characterModel = CharacterModel.new(userId, mod.characterMod)

                record.characterModel.onModelCreated:Connect(function()
                    self.OnCharacterModelCreated:Fire(record.characterModel)
                end)
                record.characterModel:CreateModel(mod.avatar)

                character = record
				self.characters[userId] = record
            elseif character.characterModel and mod and character.characterModel.characterMod ~= mod.characterMod then
                local characterModel = character.characterModel
                if not characterModel.coroutineStarted then
                    characterModel.characterMod = mod.characterMod
                    characterModel:ReplaceModel(mod.avatar)
                end
            end

            character.frame = self.localFrame
			character.position = dataRecord.pos
			character.characterData = dataRecord
			
			
            --Update it
            character.characterModel:Think(deltaTime, dataRecord, bulkMoveToList)
		end
	 

        --Remove any characters who were not in this snapshot
		for key, value in self.characters do
			
			if (key == localPlayer.UserId) then
				continue
			end
			
            if value.frame ~= self.localFrame then
				self.OnCharacterModelDestroyed:Fire(value.characterModel)
			 
                value.characterModel:DestroyModel()
                value.characterModel = nil

				self.characters[key] = nil
            end
        end
    end

    debug.profileend()

    --bulkMoveTo
    debug.profilebegin("Chickynoid BulkMoveTo")
	if (bulkMoveToList) then
        game.Workspace:BulkMoveTo(bulkMoveToList.parts, bulkMoveToList.cframes, Enum.BulkMoveMode.FireCFrameChanged)
        if localPlayer:GetAttribute("ClearTrail") then
            localPlayer:SetAttribute("ClearTrail", nil)
			self.ballModel.model.Trail:Clear()
        end
    end
    debug.profileend()

    --render in the rockets
    -- local timeToRenderRocketsAt = self.estimatedServerTime
	
	if (self.debugMarkPlayers ~= nil) then
		self:DrawBoxOnAllPlayers(self.debugMarkPlayers)
        self.debugMarkPlayers = nil
	end
end

function ClientModule:GetCharacters()
    return self.characters
end

-- This tries to figure out a correct delta for the server time
-- Better to update this infrequently as it will cause a "pop" in prediction
-- Thought: Replace with roblox solution or converging solution?
function ClientModule:SetupTime(serverActualTime)
    local oldDelta = self.estimatedServerTimeOffset
    local newDelta = self:LocalTick() - serverActualTime
    self.validServerTime = true

    local delta = oldDelta - newDelta
    if math.abs(delta * 1000) > 50 then --50ms out? try again
        self.estimatedServerTimeOffset = newDelta
    end
end

-- Register a callback that will determine a character model
function ClientModule:SetCharacterModel(callback)
    table.insert(self.characterModelCallbacks, callback)
end

function ClientModule:GetPlayerDataBySlotId(slotId)
	local slotString = tostring(slotId)
	if (self.worldState == nil) then
		return nil
	end
	--worldState.players is indexed by a *STRING* not a int
	return self.worldState.players[slotString]
end

function ClientModule:GetBallDataBySlotId(slotId)
	local slotString = tostring(slotId)
	if (self.worldState == nil) then
		return nil
	end
	--worldState.players is indexed by a *STRING* not a int
	return self.worldState.balls[slotString]
end

function ClientModule:GetPlayerDataByUserId(userId)

	if (self.worldState == nil) then
		return nil
	end
	for key,value in pairs(self.worldState.players) do
		if (value.userId == userId) then
			return value
		end
	end

	return nil
end


function ClientModule:DeserializeSnapshot(event)
		
	local offset = 0
	local bitBuffer = event.b
	local recordCount = buffer.readu8(bitBuffer,offset)
	offset+=1
	
	--Find what this was delta compressed against	
	local previousSnapshot = nil  

	for key, value in self.snapshots do
		if (value.f == event.cf) then
			previousSnapshot = value
			break
		end
	end
	if (previousSnapshot == nil and event.cf ~= nil) then
        if RunService:IsStudio() then
            warn("Prev snapshot not found" , event.cf)
            print("num snapshots", #self.snapshots) 
        end
		return nil
	end
	self.mostRecentSnapshotComparedTo = previousSnapshot
	
    event.charData = {}
 
	for _ = 1, recordCount do
        local record = CharacterData.new()

		--CharacterData.CopyFrom(self.previous)
		
		local slotId = buffer.readu8(bitBuffer,offset)
		offset+=1

		local user = self:GetPlayerDataBySlotId(slotId)
        if user then
            if previousSnapshot ~= nil then
                local previousRecord = previousSnapshot.charData[user.userId]
                if previousRecord then
                    record:CopySerialized(previousRecord)
				end
            end
            offset = record:DeserializeFromBitBuffer(bitBuffer, offset)
				
            event.charData[user.userId] = record.serialized
        else
            
			warn("UserId for slot " .. slotId .. " not found!")
			--So things line up
			offset = record:DeserializeFromBitBuffer(bitBuffer, offset)
        end
	end
 

    return event
end

function ClientModule:GetGui()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    return gui
end

function ClientModule:DebugMarkAllPlayers(text)
	self.debugMarkPlayers = text
end

function ClientModule:DrawBoxOnAllPlayers(text)
    if self.worldState == nil then
        return
    end
    if self.worldState.flags.DEBUG_ANTILAG ~= true then
        return
    end

    local models = self:GetCharacters()
	for _, record in pairs(models) do
		
		if (record.localPlayer == true) then
			continue
		end
		
        local instance = Instance.new("Part")
        instance.Size = Vector3.new(3, 5, 3)
        instance.Transparency = 0.5
        instance.Color = Color3.new(0, 1, 0)
        instance.Anchored = true
        instance.CanCollide = false
        instance.CanTouch = false
        instance.CanQuery = false
        instance.Position = record.position
        instance.Parent = game.Workspace

        self:AdornText(instance, Vector3.new(0,3,0), text, Color3.new(0.5,1,0.5))

        self.debugBoxes[instance] = tick() + 5
    end

    for key, value in pairs(self.debugBoxes) do
        if tick() > value then
            key:Destroy()
            self.debugBoxes[key] = nil
        end
    end
end

function ClientModule:DebugBox(pos, text)
    local instance = Instance.new("Part")
    instance.Size = Vector3.new(3, 5, 3)
    instance.Transparency = 1
    instance.Color = Color3.new(1, 0, 0)
    instance.Anchored = true
    instance.CanCollide = false
    instance.CanTouch = false
    instance.CanQuery = false
    instance.Position = pos
    instance.Parent = game.Workspace

    local adornment = Instance.new("SelectionBox")
    adornment.Adornee = instance
    adornment.Parent = instance

    self.debugBoxes[instance] = tick() + 5

    self:AdornText(instance, Vector3.new(0,6,0), text, Color3.new(0, 0.501960, 1))
end

function ClientModule:AdornText(part, offset, text, color)

    local attachment = Instance.new("Attachment")
    attachment.Parent = part
    attachment.Position = offset

    local billboard = Instance.new("BillboardGui")
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0,50,0,20)
    billboard.Adornee = attachment
    billboard.Parent = attachment
    
    local textLabel = Instance.new("TextLabel")
    textLabel.TextScaled = true
    textLabel.TextColor3 = color
    textLabel.BackgroundTransparency = 1
    textLabel.Size = UDim2.new(1,0,1,0)
    textLabel.Text = text
	textLabel.Parent = billboard
	textLabel.AutoLocalize = false
end


function ClientModule:AddPingToNetgraph(mispredicted, serverHealthFps, networkProblem, ping)

    --Ping graph
    local total = 0
    for _, ping in pairs(self.pings) do
        total += ping
    end
    total /= #self.pings

    NetGraph:Scroll()

    local color1 = Color3.new(1, 1, 1)
    local color2 = Color3.new(1, 1, 0)
	if mispredicted == false then
        NetGraph:AddPoint(ping * 0.25, color1, 4)
        NetGraph:AddPoint(total * 0.25, color2, 3)
    else
        NetGraph:AddPoint(ping * 0.25, color1, 4)
        local tint = Color3.new(0.5, 1, 0.5)
        NetGraph:AddPoint(total * 0.25, tint, 3)
        NetGraph:AddBar(10 * 0.25, tint, 1)
    end

    --Server fps
    if serverHealthFps >= 60 then
        NetGraph:AddPoint(serverHealthFps, Color3.new(0.101961, 1, 0), 2)
    elseif serverHealthFps >= 50 then
        NetGraph:AddPoint(serverHealthFps, Color3.new(1, 0.666667, 0), 2)
	else
		NetGraph:AddPoint(serverHealthFps, Color3.new(1, 0, 0), 2)
	end

    --Blue bar
    if networkProblem == Enums.NetworkProblemState.TooFarBehind then
        NetGraph:AddBar(100, Color3.new(0, 0, 1), 0)
    end
    --Yellow bar
    if networkProblem == Enums.NetworkProblemState.TooFarAhead then
        NetGraph:AddBar(100, Color3.new(1, 0.615686, 0), 0)
    end
    --Orange bar
    if networkProblem == Enums.NetworkProblemState.TooManyCommands then
        NetGraph:AddBar(100, Color3.new(1, 0.666667, 0), 0)
	end
	--teal bar
	if networkProblem == Enums.NetworkProblemState.CommandUnderrun then
		NetGraph:AddBar(100, Color3.new(0, 1, 1), 0)
	end
	
	--Yellow bar
	if networkProblem == Enums.NetworkProblemState.DroppedPacketGood then
		NetGraph:AddBar(100, Color3.new(0.898039, 1, 0), 0)
	end
	--Red Bar
	if networkProblem == Enums.NetworkProblemState.DroppedPacketBad then
		NetGraph:AddBar(100, Color3.new(1, 0, 0), 0)
	end
	
	
	NetGraph:SetFpsText("Ping: " .. math.floor(total) .. "ms")
	NetGraph:SetOtherFpsText("ServerFps: " .. serverHealthFps)
end

function ClientModule:IsConnectionBad()

    local pings 
    if #self.pings > 10 and self.ping > 2000 then
        return true
    end
    return false
end

function ClientModule:GenerateCommandBase(serverTime, deltaTime)
    
    local command = {}
    command.serverTime = serverTime								 				--For rollback - a locally interpolated value
	command.deltaTime = deltaTime								  				--How much time this command simulated
	command.snapshotServerFrame = self.snapshotServerFrame						--Confirm to the server the last snapshot we saw
	command.playerStateFrame = self.localChickynoid.lastSeenPlayerStateFrame 	--Confirm to server the last playerState we saw
		 
    command.x = 0
    command.y = 0
    command.z = 0
 
    local modules = ClientMods:GetMods("clientmods")

    for key,mod in modules do
        if (mod.GenerateCommand) then
            command = mod:GenerateCommand(command, serverTime, deltaTime, ClientModule)
        end
    end

    return command
end
 

return ClientModule
