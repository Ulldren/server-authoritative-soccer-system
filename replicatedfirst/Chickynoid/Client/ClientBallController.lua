
--[=[
    @class ClientBallController
    @client

    A Chickynoid class that handles ball simulation and command generation for the client
]=]
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local RemoteEvent = ReplicatedStorage:WaitForChild("ChickynoidReplication") :: RemoteEvent
local UnreliableRemoteEvent = ReplicatedStorage:WaitForChild("ChickynoidUnreliableReplication") :: UnreliableRemoteEvent

local path = game.ReplicatedFirst.Chickynoid
local BallSimulation = require(path.Shared.Simulation.BallSimulation)
local ClientMods = require(path.Client.ClientMods)
local CollisionModule = require(path.Shared.Simulation.CollisionModule)
local DeltaTable = require(path.Shared.Vendor.DeltaTable)

local CommandLayout = require(path.Shared.Simulation.CommandLayout)

local TrajectoryModule = require(path.Shared.Simulation.TrajectoryModule)
local Enums = require(path.Shared.Enums)
local EventType = Enums.EventType

local ClientBallController = {}
ClientBallController.__index = ClientBallController

--[=[
    Constructs a new ClientChickynoid for the local player, spawning it at the specified
    position. The position is just to prevent a mispredict.

    @param position Vector3 -- The position to spawn this character, provided by the server.
    @return ClientChickynoid
]=]
function ClientBallController.new(position: Vector3)
    local self = setmetatable({

        simulation = BallSimulation.new(localPlayer.UserId),
        localStateCache = {},
        characterMod = "DefaultBallController",
        localFrame = 0,

        ignoreServerState = nil,
        lastConfirmedGuid = nil,
        aheadOfServerBy = 0,

        mispredict = Vector3.new(0, 0, 0),
		
		commandPacketlossPrevention = true, -- set this to true to duplicate packets
		
        debug = {
            processedCommands = 0,
            showDebugSpheres = false,
            useSkipResimulationOptimization = false,
            debugParts = nil,
        },
    }, ClientBallController)

    self.simulation.state.pos = position
    
    --Apply the characterMod
    if (self.characterMod) then
        local loadedModule = ClientMods:GetMod("balls", self.characterMod)
        loadedModule:Setup(self.simulation)
    end

    self:HandleLocalPlayer()
	

    return self
end

function ClientBallController:HandleLocalPlayer() end


--[=[
    The server sends each client an updated world state on a fixed timestep. This
    handles state updates for this character.

    @param state table -- The new state sent by the server.
    @param stateDeltaFrame -- The serverFrame this  delta compressed against - due to packetloss the server can't just send you the newest stuff.
    @param lastConfirmed number -- The serial number of the last command confirmed by the server - can be nil!
    @param serverTime - Time when command was confirmed
    @param playerStateFrame -- Current frame on the server, used for tracking playerState
]=]
function ClientBallController:HandleNewPlayerState(stateDelta, stateDeltaTime, lastConfirmed, serverTime, playerStateFrame, totalCommandsToRun: number)
    totalCommandsToRun = totalCommandsToRun or 1

    self:ClearDebugSpheres()
	
	local stateRecord = DeltaTable:DeepCopy(stateDelta)
	
	--Set the last server frame we saw a command from
	self.lastSeenPlayerStateFrame = playerStateFrame
		
    -- Build a list of the commands the server has not confirmed yet
	local resimulate = true

	--Check to see if we can skip simulation
	--Todo: This needs to check a lot more than position and velocity - the server should always be able to force a reconcile/resim
	if (self.debug.useSkipResimulationOptimization == true) then
		
		if (lastConfirmed ~= nil) then
			local cacheRecord = self.localStateCache[lastConfirmed]
			if cacheRecord and cacheRecord.stateRecord.state.guid == stateRecord.state.guid then
	            -- This is the state we were in, if the server agrees with this, we dont have to resim\
				if (cacheRecord.stateRecord.state.ownerId ~= 0 or (cacheRecord.stateRecord.state.pos - stateRecord.state.pos).Magnitude < 0.05)
                and (cacheRecord.stateRecord.state.vel - stateRecord.state.vel).Magnitude < 0.1 then
	                resimulate = false
	                -- print("skipped resim")
	            end
	        end

	        -- Clear all the ones older than lastConfirmed
			for key, _ in pairs(self.localStateCache) do
	            if key < lastConfirmed then
					self.localStateCache[key] = nil
	            end
			end
		end
    end


    if self.lastLocalFrame and self.lastLocalFrame > lastConfirmed then
        return
    end
    self.lastLocalFrame = lastConfirmed

    local ignoreServerState = self.ignoreServerState
    if ignoreServerState then
        if tick() - ignoreServerState < 0 then
            resimulate = false
        else
            resimulate = true
            self.skipResimulation = false
            self.ignoreServerState = nil
        end
    end


    local playerIsNetworkOwner = stateRecord.state.netId == localPlayer.UserId

    local isGoalkeeper = localPlayer:GetAttribute("Position") == "Goalkeeper"
    local framesToGoal = stateRecord.state.framesToGoal
    if isGoalkeeper and framesToGoal then
        resimulate = false
    -- elseif not playerIsNetworkOwner then
    --     resimulate = true
    --     self.skipResimulation = false
    --     self.ignoreServerState = nil
    end

    local lastConfirmedGuid = self.lastConfirmedGuid

    local guidChanged = stateRecord.state.guid ~= lastConfirmedGuid
    if guidChanged then
        self.lastConfirmedGuid = stateRecord.state.guid
        -- self.ignoreServerState = nil
        self.skipResimulation = false
        resimulate = true

        if lastConfirmed then
            self.localFrame = lastConfirmed
        end

        if not playerIsNetworkOwner then
            self.mispredict = Vector3.zero
            localPlayer:SetAttribute("ClearTrail", true)
        end

        local ballModel = localPlayer.BallModel
        if not playerIsNetworkOwner then
            local ball: BasePart = ballModel.Value
            ball.Trail:Clear()
        end
    end

    self.simulation:DoServerAttributeChecks()
    if self.lastSlippery and self.lastSlippery ~= self.simulation.constants.slippery then
        self.skipResimulation = false
        resimulate = true
    end
    self.lastSlippery = self.simulation.constants.slippery


    local becameNetworkOwner = self.simulation.state.netId ~= localPlayer.UserId and playerIsNetworkOwner

    if lastConfirmed > self.localFrame+5 and not (isGoalkeeper and framesToGoal) then
        self.skipResimulation = false
        self.ignoreServerState = nil
        resimulate = true
    end
    if resimulate == true and stateRecord ~= nil and not self.skipResimulation then
        debug.profilebegin("Ball Controller Resimulation")

        if playerIsNetworkOwner or true then
            self.skipResimulation = true
        end
        if isGoalkeeper and framesToGoal then
            self.skipResimulation = true
        end

        local extrapolatedServerTime = serverTime

        -- Record our old state
        local oldPos = self.simulation.state.pos

        -- Reset our base simulation to match the server
        self.simulation:ReadState(stateRecord)

        -- Marker for where the server said we were
        self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(255, 170, 0))

        CollisionModule:UpdateDynamicParts()

        self.simulation.ballData:SetIsResimulating(true)


        local hasOwner = stateRecord.state.ownerId ~= 0
        if not hasOwner then
            local ballModel = localPlayer.BallModel.Value
            ballModel.BallOwner.Value = nil
        end
        -- Resimulate all of the commands the server has not confirmed yet

        local maximumCommands = 1
        if playerIsNetworkOwner then
            maximumCommands = 60
        end
        local newCommandsToRun = math.min(totalCommandsToRun, maximumCommands)
        for i = 1, newCommandsToRun do
            self.localFrame += 1

            local command = {}

            command.deltaTime = 1/60
            extrapolatedServerTime += command.deltaTime

            TrajectoryModule:PositionWorld(extrapolatedServerTime, command.deltaTime)

            local doCollisionChecks = i == newCommandsToRun and playerIsNetworkOwner and false
            self.simulation:ProcessCommand(command, doCollisionChecks)

            -- Resimulated positions
            self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(255, 255, 0))
        end

        -- Did we make a misprediction? We can tell if our predicted position isn't the same after reconstructing everything
        local delta = oldPos - self.simulation.state.pos
        --Add the offset to mispredict so we can blend it off
        self.mispredict += delta
        
        if (delta.magnitude > 0.1) then
            mispredicted = true
        end

        local currentAction = stateRecord.state.action
        if guidChanged then
            self.simulation.ballData.teleported = currentAction == Enums.BallActions.Teleport
            if stateRecord.state.action == Enums.BallActions.Deflect then
                if becameNetworkOwner then
                    localPlayer:SetAttribute("DisableChargeShot", true)
                    localPlayer:SetAttribute("DisableChargeShot", nil)
                end
            elseif currentAction == Enums.BallActions.Teleport then
                self.mispredict = Vector3.zero
                localPlayer:SetAttribute("ClearTrail", true)
                mispredicted = false
            end

            local ownerId = stateRecord.state.ownerId
            if type(ownerId) == "number" then
                local owner = Players:GetPlayerByUserId(ownerId)

                local ballModel = localPlayer.BallModel.Value
                ballModel.BallOwner.Value = owner
                if owner then
                    owner.Ball.Value = ballModel
                    self.simulation.state.pos = ballModel.CFrame.Position
                end
            end
        end

        if hasOwner then
            self.mispredict = Vector3.zero
            mispredicted = false
        end

        self.simulation.ballData:SetIsResimulating(false)

        debug.profileend()
    end
    
    return becameNetworkOwner, stateRecord.state.action
end

--Entry point every "frame"
function ClientBallController:Heartbeat(command, serverTime: number, deltaTime: number)
    self.localFrame += 1
		
    --Write the local frame for prediction later
    command.localFrame = self.localFrame
    self.aheadOfServerBy += 1
		
    -- Step this frame
    self.debug.processedCommands += 1

    local hitPlayer = self.simulation:ProcessCommand(command, nil, true, true)

    -- Marker for positions added since the last server update
    self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(44, 140, 39))

    debug.profilebegin("Chickynoid Write To State")
    if (self.debug.useSkipResimulationOptimization == true) then
        -- Add to our state cache, which we can use for skipping resims
        local cacheRecord = {}
		cacheRecord.localFrame = command.localFrame
		cacheRecord.stateRecord = self.simulation:WriteState()

		self.localStateCache[command.localFrame] = cacheRecord
    end
    debug.profileend()

    --Remove any sort of smoothing accumulating in the characterData
    self.simulation.ballData:ClearSmoothing()
		
    return command, hitPlayer
end

function ClientBallController:SpawnDebugSphere(pos, color)
    if (self.debug.showDebugSpheres ~= true) then
        return
    end

    if (self.debug.debugParts == nil) then
        self.debug.debugParts = Instance.new("Folder")
        self.debug.debugParts.Name = "ChickynoidDebugSpheres"
        self.debug.debugParts.Parent = workspace
    end

    local part = Instance.new("Part")
    part.Anchored = true
    part.Color = color
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(5, 5, 5)
    part.Position = pos
    part.Transparency = 0.25
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth

    part.Parent = self.debug.debugParts
end

function ClientBallController:ClearDebugSpheres()
    if (self.debug.showDebugSpheres ~= true) then
        return
    end
    if (self.debug.debugParts ~= nil) then
        self.debug.debugParts:ClearAllChildren()
    end
end

function ClientBallController:Destroy() end

return ClientBallController
