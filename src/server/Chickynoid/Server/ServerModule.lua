--!native
--[=[
    @class ChickynoidServer
    @server

    Server namespace for the Chickynoid package.
]=]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local path = game.ReplicatedFirst.Chickynoid

local Enums = require(path.Shared.Enums)
local EventType = Enums.EventType
local ServerChickynoid = require(script.Parent.ServerChickynoid)
local ServerBallController = require(script.Parent.ServerBallController)
local CharacterData = require(path.Shared.Simulation.CharacterData)
local BallInfoLayout = require(path.Shared.Simulation.BallInfoLayout)
local DebugInfo = require(path.Shared.DebugInfo)


local DeltaTable = require(path.Shared.Vendor.DeltaTable)
local WeaponsModule = require(script.Parent.WeaponsServer)
local CollisionModule = require(path.Shared.Simulation.CollisionModule)
local Antilag = require(script.Parent.Antilag)
local BallPositionHistory = require(script.Parent.BallPositionHistory)
local FastSignal = require(path.Shared.Vendor.FastSignal)
local ServerMods = require(script.Parent.ServerMods)
local Animations = require(path.Shared.Simulation.Animations)

local Profiler = require(path.Shared.Vendor.Profiler)

local RemoteEvent = Instance.new("RemoteEvent")
RemoteEvent.Name = "ChickynoidReplication"
RemoteEvent.Parent = ReplicatedStorage

local UnreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
UnreliableRemoteEvent.Name = "ChickynoidUnreliableReplication"
UnreliableRemoteEvent.Parent = ReplicatedStorage

local ServerSnapshotGen = require(script.Parent.ServerSnapshotGen)

local ServerModule = {}

ServerModule.playerRecords = {}
ServerModule.loadingPlayerRecords = {}
ServerModule.serverStepTimer = 0
ServerModule.serverLastSnapshotFrame = -1 --Frame we last sent snapshots on
ServerModule.serverTotalFrames = 0
ServerModule.serverSimulationTime = 0
ServerModule.framesPerSecondCounter = 0 --Purely for stats
ServerModule.framesPerSecondTimer = 0 --Purely for stats
ServerModule.framesPerSecond = 0 --Purely for stats
ServerModule.accumulatedTime = 0 --fps

ServerModule.ballRecord = nil
ServerModule.serverBallStepTimer = 0
ServerModule.serverBallTotalFrames = 0

ServerModule.startTime = tick()
ServerModule.slots = {}
ServerModule.collisionRootFolder = nil
ServerModule.absoluteMaxSizeOfBuffer = 4096

ServerModule.playerSize = Vector3.new(2, 5, 2)


--[=[
	@interface ServerConfig
	@within ChickynoidServer
	.maxPlayers number -- Theoretical max, use a byte for player id
	.fpsMode FpsMode
	.serverHz number
	Server config for Chickynoid.
]=]
ServerModule.config = {
    maxPlayers = 255,
	fpsMode = Enums.FpsMode.Fixed60,
	serverHz = 20,
	antiWarp = false,
}

--API
ServerModule.OnPlayerSpawn = FastSignal.new()
ServerModule.OnPlayerDespawn = FastSignal.new()
ServerModule.OnBeforePlayerSpawn = FastSignal.new()
ServerModule.OnPlayerConnected = FastSignal.new()	--Technically this is OnPlayerLoaded


ServerModule.flags = {}
ServerModule.flags.DEBUG_ANTILAG = false
ServerModule.flags.DEBUG_BOT_BANDWIDTH = false



ServerModule.CharacterService = nil


 
--[=[
	Creates connections so that Chickynoid can run on the server.
]=]
function ServerModule:Setup()
    self.worldRoot = self:GetDoNotReplicate()

    Players.PlayerAdded:Connect(function(player)
        self:PlayerConnected(player)
    end)

    --If there are any players already connected, push them through the connection function
    for _, player in pairs(game.Players:GetPlayers()) do
        self:PlayerConnected(player)
    end

    Players.PlayerRemoving:Connect(function(player)
        self:PlayerDisconnected(player.UserId)
    end)

    RunService.Heartbeat:Connect(function(deltaTime)
        self:RobloxHeartbeat(deltaTime)
    end)

    RunService.Stepped:Connect(function(_, deltaTime)
        self:RobloxPhysicsStep(deltaTime)
    end)

    UnreliableRemoteEvent.OnServerEvent:Connect(function(player: Player, event)
        local playerRecord = self:GetPlayerByUserId(player.UserId)

        if playerRecord then
            if playerRecord.chickynoid then
                playerRecord.chickynoid:HandleEvent(self, event)
            end
        end
	end)
	
	RemoteEvent.OnServerEvent:Connect(function(player: Player, event: any)
		
		--Handle events from loading players
		local loadingPlayerRecord = ServerModule.loadingPlayerRecords[player.UserId]
		
		if (loadingPlayerRecord ~= nil) then
			if (event.id == "loaded") then
				if (loadingPlayerRecord.loaded == false) then
					loadingPlayerRecord:HandlePlayerLoaded()
				end
			end
			return
		end
		
	end)
	
	Animations:ServerSetup()	

    WeaponsModule:Setup(self)

    Antilag:Setup(self)
	BallPositionHistory:Setup(self)

    --Load the mods
    local modules = ServerMods:GetMods("servermods")
    for _, mod in pairs(modules) do
        mod:Setup(self)
		-- print("Loaded", _)
    end
end

function ServerModule:PlayerConnected(player)
    local playerRecord = self:AddConnection(player.UserId, player)
	
	if (playerRecord) then
	    --Spawn the gui
	    for _, child in pairs(game.StarterGui:GetChildren()) do
	        local clone = child:Clone() :: ScreenGui
	        if clone:IsA("ScreenGui") then
	            clone.ResetOnSpawn = false
	        end
	        clone.Parent = playerRecord.player.PlayerGui
		end
	end

end

function ServerModule:AssignSlot(playerRecord)
	
	--Only place this is assigned
    for j = 1, self.config.maxPlayers do
        if self.slots[j] == nil then
            self.slots[j] = playerRecord
            playerRecord.slot = j
            return true
        end
    end
    warn("Slot not found!")
    return false
end

type PlayerRecord = {
	userId: number,
	hasBall: boolean,

	slot: number,
	loaded: boolean,
	chickynoid: typeof(ServerChickynoid),
	frame: number,
	pendingWorldState: boolean,
	visHistoryList: {},
	characterMod: string,
	lastConfirmedSnapshotServerFrame: number,

	SendEventToClient: (self: PlayerRecord, event: {}) -> (),
	SendUnreliableEventToClient: (self: PlayerRecord, event: {}) -> (),
	SendEventToClients: (self: PlayerRecord, event: {}) -> (),
	SendEventToOtherClients: (self: PlayerRecord, event: {}) -> (),
	SendCollisionData: (self: PlayerRecord, event: {}) -> (),
	Despawn: (self: PlayerRecord, event: {}) -> (),
	SetCharacterMod: (self: PlayerRecord, event: {}) -> (),
	Spawn: (self: PlayerRecord, event: {}) -> (),
	HandlePlayerLoaded: (self: PlayerRecord, event: {}) -> (),
}

function ServerModule:AddConnection(userId, player)
    if self.playerRecords[userId] ~= nil or self.loadingPlayerRecords[userId] ~= nil then
        warn("Player was already connected.", userId)
        self:PlayerDisconnected(userId)
    end

    --Create the players server connection record
    local playerRecord = {}
    self.loadingPlayerRecords[userId] = playerRecord

    playerRecord.userId = userId
	playerRecord.hasBall = false
	
	playerRecord.slot = 0 -- starts 0, 0 is an invalid slot.
	playerRecord.loaded = false
	
    playerRecord.previousCharacterData = nil
    playerRecord.chickynoid = nil :: typeof(ServerChickynoid)
    playerRecord.frame = 0
	
	playerRecord.pendingWorldState = true
    
    playerRecord.allowedToSpawn = true
    playerRecord.respawnDelay = 1
    playerRecord.respawnTime = tick() + playerRecord.respawnDelay

	playerRecord.OnBeforePlayerSpawn = FastSignal.new()
	playerRecord.visHistoryList = {}

    playerRecord.characterMod = "HumanoidChickynoid"
	 	
	playerRecord.lastConfirmedSnapshotServerFrame = nil --Stays nil til a player confirms they've seen a whole snapshot, for delta compression purposes
		
	local assignedSlot = self:AssignSlot(playerRecord)
    self:DebugSlots()
    if (assignedSlot == false) then
		if (player ~= nil) then
			player:Kick("Server full, no free chickynoid slots")
		end
		self.loadingPlayerRecords[userId] = nil
		return nil
	end


    playerRecord.player = player
    if playerRecord.player ~= nil then
        playerRecord.dummy = false
        playerRecord.name = player.name
    else
        --Is a bot
        playerRecord.dummy = true
    end

    -- selene: allow(shadowing)
	function playerRecord:SendEventToClient(event)
		if (playerRecord.loaded == false) then
			print("warning, player not loaded yet")
		end
        if playerRecord.player then
            RemoteEvent:FireClient(playerRecord.player, event)
        end
	end
	
	-- selene: allow(shadowing)
	function playerRecord:SendUnreliableEventToClient(event)
		if (playerRecord.loaded == false) then
			print("warning, player not loaded yet")
		end
		if playerRecord.player == nil then
			return
		end
		if DebugInfo.DEBUG then
			task.delay(DebugInfo.PING/2, function()
				UnreliableRemoteEvent:FireClient(playerRecord.player, event)
			end)
		else
			UnreliableRemoteEvent:FireClient(playerRecord.player, event)
		end
	end

    -- selene: allow(shadowing)
    function playerRecord:SendEventToClients(event)
        if playerRecord.player then
			for _, record in ServerModule.playerRecords do
				if record.loaded == false or record.dummy == true then
					continue
				end
				RemoteEvent:FireClient(record.player, event)
			end
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:SendEventToOtherClients(event)
		for _, record in ServerModule.playerRecords do
			if record.loaded == false or record.dummy == true then
				continue
			end
            if record == playerRecord then
                continue
            end
            RemoteEvent:FireClient(record.player, event)
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:SendCollisionData()
       
		if ServerModule.collisionRootFolder ~= nil then
			local event = {}
			event.t = Enums.EventType.CollisionData
            event.playerSize = ServerModule.playerSize
			event.data = ServerModule.collisionRootFolder
			self:SendEventToClient(event)
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:Despawn()
        if self.chickynoid then
            ServerModule.OnPlayerDespawn:Fire(self)

            print("Despawned!")
            self.chickynoid:Destroy()
            self.chickynoid = nil
            self.respawnTime = tick() + self.respawnDelay

            local event = { t = EventType.ChickynoidRemoving }
            playerRecord:SendEventToClient(event)
        end
    end

    function playerRecord:SetCharacterMod(characterModName)
		self.characterMod = characterModName
		ServerModule:SetWorldStateDirty()
    end

    -- selene: allow(shadowing)
	function playerRecord:Spawn()
		
		if (playerRecord.loaded == false) then
			warn("Spawn() called before player loaded")
			return
		end
        self:Despawn()

        local chickynoid = ServerChickynoid.new(playerRecord)
        self.chickynoid = chickynoid
        chickynoid.playerRecord = self

		local list = {}
		for _, obj: SpawnLocation in pairs(workspace:GetDescendants()) do
			if obj:IsA("SpawnLocation") and obj.Enabled == true then
				table.insert(list, obj)
			end
		end

		if #list > 0 then
			local spawn = list[math.random(1, #list)]
			chickynoid:SetPosition(Vector3.new(spawn.Position.x, spawn.Position.y + 5, spawn.Position.z), true)

			local _, yRot, _ = spawn.CFrame:ToEulerAnglesYXZ()
			chickynoid.simulation:SetAngle(yRot, true)
		else
			chickynoid:SetPosition(Vector3.new(0, 10, 0), true)
		end

        self.OnBeforePlayerSpawn:Fire()
        ServerModule.OnBeforePlayerSpawn:Fire(self, playerRecord)

        chickynoid:SpawnChickynoid()

        ServerModule.OnPlayerSpawn:Fire(self, playerRecord)
        return self.chickynoid
    end
	
	function playerRecord:HandlePlayerLoaded()

		print("Player loaded:", playerRecord.name)
		playerRecord.loaded = true

		--Move them from loadingPlayerRecords to playerRecords
		ServerModule.playerRecords[playerRecord.userId] = playerRecord		
		ServerModule.loadingPlayerRecords[playerRecord.userId] = nil

		self:SendCollisionData()

		WeaponsModule:OnPlayerConnected(ServerModule, playerRecord)

		ServerModule.OnPlayerConnected:Fire(ServerModule, playerRecord)
		ServerModule:SetWorldStateDirty()
	end

	
    return playerRecord
end

function ServerModule:AddBall()
    if self.ballRecord ~= nil then
        return
    end

    --Create the players server connection record
    local ballRecord = {}
	ballRecord.characterMod = "DefaultBallController"
	
    ballRecord.previousCharacterData = nil

	local ballController = ServerBallController.new(ballRecord)
	ballController.playerRecord = self
	ballController:SpawnChickynoid()
    ballRecord.ballController = ballController
    ballRecord.frame = 0

	local server = self
	function ballRecord:Spawn(position: Vector3)
		ballController:SetPosition(position, true)

		local ballState = ballController.simulation.state
		ballState.vel = Vector3.zero
		ballState.angVel = Vector3.zero
		ballState.guid += 1
		ballState.action = Enums.BallActions.Teleport

		ballController:setBallOwner(server, 0)
		ballController:setNetworkOwner(server, 0)
		ballController:setAttribute("HitTime", nil)
		ballController.attributes = {}

		task.spawn(function()
			ballController.ballSpawned:Fire()
		end)

		server:SetWorldStateDirty()

        return self.ballController
    end

	self.ballRecord = ballRecord
	
    return ballRecord
end

function ServerModule:SendEventToClients(event)
    RemoteEvent:FireAllClients(event)
end

function ServerModule:SetWorldStateDirty()
	for _, data in pairs(self.playerRecords) do
		data.pendingWorldState = true
	end
end

function ServerModule:SendWorldState(playerRecord)
	
	if (playerRecord.loaded == false) then
		return
	end
	
    local event = {}
    event.t = Enums.EventType.WorldState
    event.worldState = {}
    event.worldState.flags = self.flags

    event.worldState.players = {}
    for _, data in pairs(self.playerRecords) do
        local info = {}
        info.name = data.name
		info.userId = data.userId
		info.characterMod = data.characterMod
		info.avatar = data.avatarDescription
        event.worldState.players[tostring(data.slot)] = info
    end

    event.worldState.serverHz = self.config.serverHz
    event.worldState.fpsMode = self.config.fpsMode
	event.worldState.animations = Animations.animations
		
	playerRecord:SendEventToClient(event)
	
	playerRecord.pendingWorldState = false
end

function ServerModule:PlayerDisconnected(userId)
	
	local loadingPlayerRecord = self.loadingPlayerRecords[userId]
	if (loadingPlayerRecord ~= nil) then
		print("Player ".. loadingPlayerRecord.player.Name .. " disconnected")
		self.loadingPlayerRecords[userId] = nil
	end
		
	local playerRecord = self.playerRecords[userId]
    if playerRecord then
        print("Player ".. playerRecord.player.Name .. " disconnected")

		playerRecord:Despawn()
		
		--nil this out
		playerRecord.previousCharacterData = nil
		self.slots[playerRecord.slot] = nil
		playerRecord.slot = nil
		
        self.playerRecords[userId] = nil

        self:DebugSlots()
    end

    --Tell everyone
    for _, data in pairs(self.playerRecords) do
		local event = {}
		event.t = Enums.EventType.PlayerDisconnected
		event.userId = userId
		data:SendEventToClient(event)
	end
	self:SetWorldStateDirty()
end

function ServerModule:DebugSlots()
    --print a count
    local free = 0
    local used = 0
    for j = 1, self.config.maxPlayers do
        if self.slots[j] == nil then
            free += 1
            
        else
            used += 1
        end
    end
    print("Players:", used, " (Free:", free, ")")
end

function ServerModule:GetPlayerByUserId(userId): PlayerRecord?
    return self.playerRecords[userId]
end

function ServerModule:GetPlayers()
    return self.playerRecords
end

function ServerModule:RobloxHeartbeat(deltaTime)

    if (true) then
	    self.accumulatedTime += deltaTime

		local frac = 1/30
		if self.config.fpsMode == Enums.FpsMode.Fixed60 then
			frac = 1/60
		elseif self.config.fpsMode == Enums.FpsMode.Fixed30 then
			frac = 1/20
		else
			warn("Unhandled FPS mode")
		end

	    local maxSteps = 0
	    while self.accumulatedTime > 0 do
	        self.accumulatedTime -= frac
	        self:Think(frac)
	        
	        maxSteps+=1
	        if (maxSteps > 2) then
	            self.accumulatedTime = 0
	            break
	        end
	    end

	      --Discard accumulated time if its a tiny fraction
	    local errorSize = 0.001 --1ms
	    if self.accumulatedTime > -errorSize then
	        self.accumulatedTime = 0
	    end
	else
    
	    --Much simpler - assumes server runs at 60.
	    self.accumulatedTime = 0
	    local frac = 1 / 60
		self:Think(deltaTime)
	end

  
end

function ServerModule:RobloxPhysicsStep(deltaTime)
    for _, playerRecord in pairs(self.playerRecords) do
        if playerRecord.chickynoid then
            playerRecord.chickynoid:RobloxPhysicsStep(self, deltaTime)
        end
    end
end

function ServerModule:GetDoNotReplicate()
    local camera = game.Workspace:FindFirstChild("DoNotReplicate")
    if camera == nil then
        camera = Instance.new("Camera")
        camera.Name = "DoNotReplicate"
        camera.Parent = game.Workspace
    end
    return camera
end

function ServerModule:UpdateTiming(deltaTime)
	--Do fps work
	self.framesPerSecondCounter += 1
	self.framesPerSecondTimer += deltaTime
	if self.framesPerSecondTimer > 1 then
		self.framesPerSecondTimer = math.fmod(self.framesPerSecondTimer, 1)
		self.framesPerSecond = self.framesPerSecondCounter
		self.framesPerSecondCounter = 0
	end

	self.serverSimulationTime = tick() - self.startTime
end

function ServerModule:Think(deltaTime)

	self:UpdateTiming(deltaTime)
	
	self:SendWorldStates()
		
	self:SpawnPlayers()

    CollisionModule:UpdateDynamicParts()

	self:UpdateBallThinks(deltaTime)
	self:UpdateBallPostThinks(deltaTime)
	BallPositionHistory:WriteBallPosition(self.serverSimulationTime)

	self:UpdatePlayerThinks(deltaTime)
	self:UpdatePlayerPostThinks(deltaTime)
    
    WeaponsModule:Think(self, deltaTime)
	
	self:StepServerMods(deltaTime)
	
	self:Do20HzOperations(deltaTime)
	self:UpdateBallStatesToPlayers()
end

function ServerModule:StepServerMods(deltaTime)
	--Step the server mods
	local modules = ServerMods:GetMods("servermods")
	for _, mod in pairs(modules) do
		if (mod.Step) then
			mod:Step(self, deltaTime)
		end
	end
end


function ServerModule:Do20HzOperations(deltaTime)
	
	--Calc timings
	self.serverStepTimer += deltaTime
	self.serverTotalFrames += 1

	local fraction = (1 / self.config.serverHz)
	
	--Too soon
	if self.config.fpsMode ~= Enums.FpsMode.Fixed30 then
		if self.serverStepTimer < fraction then
			return
		end
			
		while self.serverStepTimer > fraction do -- -_-'
			self.serverStepTimer -= fraction
		end
	end
	
	
	self:WriteCharacterDataForSnapshots()
	
	--Playerstate, for reconciliation of client prediction
	self:UpdatePlayerStatesToPlayers()
	
	--we write the antilag at 20hz, to match when we replicate snapshots to players
	Antilag:WritePlayerPositions(self.serverSimulationTime)
	
	--Figures out who can see who, for replication purposes
	self:DoPlayerVisibilityCalculations()
	
	--Generate the snapshots for all players
	self:WriteSnapshotsForPlayers()
 
end


function ServerModule:WriteCharacterDataForSnapshots()
	
	for userId, playerRecord in pairs(self.playerRecords) do
		if (playerRecord.chickynoid == nil) then
			continue
		end
		
		--Grab a copy at this serverTotalFrame, because we're going to be referencing this for building snapshots with
		playerRecord.chickynoid.prevCharacterData[self.serverTotalFrames] = DeltaTable:DeepCopy( playerRecord.chickynoid.simulation.characterData)
		
		--Toss it out if its over a second old
		for timeStamp, rec in playerRecord.chickynoid.prevCharacterData do
			if (timeStamp < self.serverTotalFrames - 60) then
				playerRecord.chickynoid.prevCharacterData[timeStamp] = nil
			end
		end
	end
end

function ServerModule:KnockbackPlayer(player: Player, knockback: Vector3, duration: number, freeze: boolean?, tackle: boolean?)
	if typeof(knockback) ~= "Vector3" then
		return warn("[ServerModule] KnockbackPlayer - Wrong type (knockback)!")
	end
	if type(duration) ~= "number" then
		return warn("[ServerModule] KnockbackPlayer - Wrong type (duration)!")
	end

	local playerRecord = self:GetPlayerByUserId(player.UserId)
	if playerRecord == nil then
		return
	end

	local chickynoid = playerRecord.chickynoid
	if chickynoid == nil then
		return
	end

	chickynoid:GenerateKnockbackCommand(self, knockback, duration, freeze, tackle)
	chickynoid:Think(self, self.serverSimulationTime, 0)

	playerRecord.chickynoid.processedTimeSinceLastSnapshot = 0

	--Send results of server move
	local event = {}
	event.t = EventType.State
	
	
	--bonus fields
	event.e = playerRecord.chickynoid.errorState
	event.s = self.framesPerSecond
	
	--required fields
	event.lastConfirmedCommand = playerRecord.chickynoid.lastConfirmedCommand
	event.serverTime = self.serverSimulationTime
	event.serverFrame = self.serverTotalFrames
	event.playerStateDelta, event.playerStateDeltaFrame = playerRecord.chickynoid:ConstructPlayerStateDelta(self.serverTotalFrames)

	playerRecord:SendUnreliableEventToClient(event)
	
	--Clear the error state flag 
	playerRecord.chickynoid.errorState = Enums.NetworkProblemState.None
end

function ServerModule:UpdatePlayerStatesToPlayers()
	
	for userId, playerRecord in pairs(self.playerRecords) do

		--Bots dont generate snapshots, unless we're testing for performance
		if (self.flags.DEBUG_BOT_BANDWIDTH ~= true) then
			if playerRecord.dummy == true then
				continue
			end
		end			

		if playerRecord.chickynoid ~= nil then

			--see if we need to antiwarp people

			local player = Players:GetPlayerByUserId(userId)
			if player:GetAttribute("MovementDisabled") 
			-- or playerRecord.chickynoid.simulation.state.knockback > 0 
			then
				local timeElapsed = playerRecord.chickynoid.processedTimeSinceLastSnapshot

				local possibleStep = playerRecord.chickynoid.elapsedTime - playerRecord.chickynoid.playerElapsedTime

				if (timeElapsed == 0 and playerRecord.chickynoid.lastProcessedCommand ~= nil) then
					--This player didn't move this snapshot
					playerRecord.chickynoid.errorState = Enums.NetworkProblemState.CommandUnderrun

					local timeToPatchOver = 1 / self.config.serverHz
					playerRecord.chickynoid:GenerateFakeCommand(self, timeToPatchOver)

					--print("Adding fake command ", timeToPatchOver)

					--Move them.
					playerRecord.chickynoid:Think(self, self.serverSimulationTime, 0)
				end
				--print("e:" , timeElapsed * 1000)
			end

			playerRecord.chickynoid.processedTimeSinceLastSnapshot = 0

			--Send results of server move
			local event = {}
			event.t = EventType.State
			
			
			--bonus fields
			event.e = playerRecord.chickynoid.errorState
			event.s = self.framesPerSecond
			
			--required fields
			event.lastConfirmedCommand = playerRecord.chickynoid.lastConfirmedCommand
			event.serverTime = self.serverSimulationTime
			event.serverFrame = self.serverTotalFrames
			event.playerStateDelta, event.playerStateDeltaFrame = playerRecord.chickynoid:ConstructPlayerStateDelta(self.serverTotalFrames)


			local ballRecord = self.ballRecord
			if ballRecord.ballController ~= nil then
				event.ballState, event.ballFrame = ballRecord.ballController:ConstructBallStateDelta()
			end
			

			playerRecord:SendUnreliableEventToClient(event)
			
			--Clear the error state flag
			playerRecord.chickynoid.errorState = Enums.NetworkProblemState.None
		end


	end
 	
end

function ServerModule:UpdateBallStatesToPlayers()
	if true then
		return
	end


	local ballRecord = self.ballRecord
	local ballController = ballRecord.ballController
	if ballController == nil then
		return
	end
	if self.lastGuid == ballController.simulation.state.guid then
		return
	end
	self.lastGuid = ballController.simulation.state.guid

	for userId, playerRecord in pairs(self.playerRecords) do

		--Bots dont generate snapshots, unless we're testing for performance
		if (self.flags.DEBUG_BOT_BANDWIDTH ~= true) then
			if playerRecord.dummy == true then
				continue
			end
		end			

		if playerRecord.chickynoid ~= nil then

			--Send results of server move
			local event = {}
			event.t = EventType.BallState
			
			event.serverFrame = self.serverTotalFrames

			event.lastConfirmedCommand = playerRecord.chickynoid.lastConfirmedCommand
			if event.lastConfirmedCommand == nil then
				continue
			end

			event.serverTime = self.serverSimulationTime
			-- if ballController.simulation.state.netId == playerRecord.userId then
			-- 	continue
			-- end
			

			event.ballState, event.ballFrame = ballController:ConstructBallStateDelta()
			if event.ballState == nil then
				continue
			end
			playerRecord:SendUnreliableEventToClient(event)
		end


	end
end

function ServerModule:SendWorldStates()
	--send worldstate
	for _, playerRecord in pairs(self.playerRecords) do
		if (playerRecord.pendingWorldState == true) then
			self:SendWorldState(playerRecord)
		end	
	end
end

function ServerModule:SpawnPlayers()
	--Spawn players
	for _, playerRecord in self.playerRecords do
		if (playerRecord.loaded == false) then
			continue
		end
		
		-- if (playerRecord.chickynoid ~= nil and playerRecord.reset == true) then
		-- 	playerRecord.reset = false
		-- 	playerRecord:Despawn()
		-- end
				
		if playerRecord.chickynoid == nil and playerRecord.allowedToSpawn == true then
			if tick() > playerRecord.respawnTime then
				playerRecord:Spawn()
			end
		end
	end
end

local services = script.Parent.Parent.Parent.Services
local GameService = require(services.GameService)
function ServerModule:UpdatePlayerThinks(deltaTime)
	
	debug.profilebegin("UpdatePlayerThinks")
	--1st stage, pump the commands
	for _, playerRecord in self.playerRecords do
		if playerRecord.dummy == true then
			playerRecord.BotThink(deltaTime)
		end

		if playerRecord.chickynoid then
			playerRecord.chickynoid:Think(self, self.serverSimulationTime, deltaTime)
			pcall(function()
				local selectPart = playerRecord.chickynoid.simulation:GetStandingPart()
				if selectPart == nil then
					return
				end
				if selectPart.Parent.Name ~= "MapSelect" then
					return
				end
				local player = Players:GetPlayerByUserId(playerRecord.userId)
				if player == nil then
					return
				end
				GameService:VoteForMap(player, tonumber(selectPart.Name))
			end)

			if playerRecord.chickynoid.simulation.state.pos.y < -2000 then
				playerRecord:Despawn()
			end
		end
	end
	debug.profileend()
end

function ServerModule:UpdatePlayerPostThinks(deltaTime)
	
	
	for _, playerRecord in self.playerRecords do
		if playerRecord.chickynoid then
			playerRecord.chickynoid:PostThink(self, deltaTime)
		end
	end
	
end

function ServerModule:UpdateBallThinks(deltaTime)
	
	debug.profilebegin("UpdateBallThinks")
	--1st stage, pump the commands
	local ballRecord = self.ballRecord
	if ballRecord.ballController then
		ballRecord.ballController:GenerateFakeCommand(self, deltaTime)
		ballRecord.ballController:Think(self, self.serverSimulationTime, deltaTime)

		-- if ballRecord.ballController.simulation.state.pos.y < -2000 then
		-- 	ballRecord:Despawn()
		-- end
	end
	debug.profileend()
end

function ServerModule:UpdateBallPostThinks(deltaTime)
	
	local ballRecord = self.ballRecord
	if ballRecord.ballController then
		ballRecord.ballController:PostThink(self, deltaTime)
	end
	
end

function ServerModule:DoPlayerVisibilityCalculations()
	
	debug.profilebegin("DoPlayerVisibilityCalculations")
	
	--This gets done at 20hz
	local modules = ServerMods:GetMods("servermods")
	
	for key,mod in modules do
		if (mod.UpdateVisibility ~= nil) then
			mod:UpdateVisibility(self, self.flags.DEBUG_BOT_BANDWIDTH)
		end
	end
	
	
	--Store the current visibility table for the current server frame
	for userId, playerRecord in self.playerRecords do
		playerRecord.visHistoryList[self.serverTotalFrames] = playerRecord.visibilityList
		
		--Store two seconds tops
		local cutoff = self.serverTotalFrames - 120
		if (playerRecord.lastConfirmedSnapshotServerFrame ~= nil) then
			cutoff = math.max(playerRecord.lastConfirmedSnapshotServerFrame, cutoff)
		end
		
		for timeStamp, rec in playerRecord.visHistoryList do
			if (timeStamp < cutoff) then
				playerRecord.visHistoryList[timeStamp] = nil
			end
		end
	end
	
	debug.profileend()
end

 
function ServerModule:WriteSnapshotsForPlayers()
 	
	ServerSnapshotGen:DoWork(self.playerRecords, self.serverTotalFrames, self.serverSimulationTime, self.flags.DEBUG_BOT_BANDWIDTH)
	
	self.serverLastSnapshotFrame = self.serverTotalFrames
	
end
	
function ServerModule:RecreateCollisions(rootFolder)
    self.collisionRootFolder = rootFolder

    for _, playerRecord in self.playerRecords do
        playerRecord:SendCollisionData()
    end

    CollisionModule:MakeWorld(self.collisionRootFolder, self.playerSize) 
end






-- Ball
local ballHitbox = Instance.new("Part")
ballHitbox.Shape = Enum.PartType.Ball
ballHitbox.Size = Vector3.new(2, 2, 2)
ballHitbox.Transparency = 0
ballHitbox.Anchored = true
ballHitbox.CanCollide = true
ballHitbox.CanQuery = true
ballHitbox.CanTouch = true

local characterHitbox = Instance.new("Part")
characterHitbox.Shape = Enum.PartType.Block
characterHitbox.Size = Vector3.new(4, 5, 1) + Vector3.one
characterHitbox.Transparency = 1
characterHitbox.Anchored = true
characterHitbox.CanCollide = false
characterHitbox.CanQuery = true
characterHitbox.CanTouch = false

local characterHitbox2 = Instance.new("Part")
characterHitbox2.Shape = Enum.PartType.Block
characterHitbox2.Size = Vector3.new(4, 5, 1) + Vector3.one
characterHitbox2.Transparency = 0
characterHitbox2.Anchored = true
characterHitbox2.CanCollide = false
characterHitbox2.CanQuery = false
characterHitbox2.CanTouch = false



type BallInfo = {
	tackledEnemy: number?,
	skill: number?,

	claimPos: Vector3?,
	shotInfo: {
		guid: number,
		shotType: string,
		shotPower: number,
		shotDirection: Vector3,
		curveFactor: number,
	}?,
	deflectInfo: {
		guid: number,
		shotType: string,
		shotPower: number,
		shotDirection: Vector3,
		curveFactor: number,
		serverDeflect: boolean,
	}?,

	enteredGoal: number?,
}

local Lib = require(ReplicatedStorage.Lib)

local EffectService = require(services.EffectService)

local GameInfo = require(ReplicatedStorage.Data.GameInfo)

local t = require(ReplicatedStorage.Modules.t)
local Trove = require(ReplicatedStorage.Modules.Trove)

local privateServerInfo = ReplicatedStorage.PrivateServerInfo

local assets = ReplicatedStorage.Assets


function ServerModule:HandlePlayerBallInfo(playerRecord: PlayerRecord, ballInfo: BallInfo, serverTime: number)
	-- Note: make sure to validate these types later
	if playerRecord == nil or playerRecord.chickynoid == nil then
		return
	end
	local simulation = playerRecord.chickynoid.simulation

	local ballRecord = self.ballRecord
	local ballController = ballRecord.ballController
	if ballController == nil then
		return
	end

	local ballSimulation = ballController.simulation

	local player = Players:GetPlayerByUserId(playerRecord.userId)
	if not Lib.playerInGame(player) or Lib.playerIsStunned(player) then
		return
	end

	local isGoalkeeper = player:GetAttribute("Position") == "Goalkeeper"
	characterHitbox.Size = Vector3.new(4, 5, 1) + Vector3.one


	local function pushBallForward()
		local frac = 1/60
		if self.config.FpsMode == Enums.FpsMode.Fixed30 then
			frac = 1/20
		end
		self:UpdateBallThinks(frac)
		self:UpdateBallPostThinks(frac)
		BallPositionHistory:WriteBallPosition(self.serverSimulationTime)
	end


	ballInfo = BallInfoLayout:DecodeCommand(ballInfo)

	-- sanitize
	for idx, value in pairs(table.clone(ballInfo)) do
		if type(value) == "number" then
			if value == 0 then
				ballInfo[idx] = nil
			end
		elseif typeof(value) == "Vector3" then
			if value.Magnitude == 0 then
				ballInfo[idx] = nil
			end
		end
	end

	-- convert to normal layout
	if ballInfo.sGuid then
		local shotSerial = {"Shoot"}
		ballInfo.sType = shotSerial[ballInfo.sType]
		ballInfo.shotInfo = {
			guid = ballInfo.sGuid,
			shotType = ballInfo.sType,
			shotPower = ballInfo.sPower,
			shotDirection = ballInfo.sDirection,
			curveFactor = ballInfo.sCurveFactor or 0,
		}
	end
	if ballInfo.dGuid then
		local shotSerial = {"DeflectShoot"}
		ballInfo.dType = shotSerial[ballInfo.dType]
		ballInfo.deflectInfo = {
			guid = ballInfo.dGuid,
			shotType = ballInfo.dType,
			shotPower = ballInfo.dPower or 0, -- volley compatibility
			shotDirection = ballInfo.dDirection,
			curveFactor = ballInfo.dCurveFactor or 0,
			serverDeflect = ballInfo.dServerDeflect == 1,
		}
	end


	if ballInfo.enteredGoal then
		if not isGoalkeeper then
			return
		end
		if not ballController:getAttribute("LagSaveLeniency") then
			return
		end
		if ballController:getAttribute("GoalkeeperConfirmed") then
			return
		end
		if player.Team.Name ~= ballController:getAttribute("GoalTeam") then
			return
		end
		ballController:setAttribute("GoalkeeperConfirmed", true)

		return
	end

	-- local serverTime = self.serverSimulationTime
	local skillServerTime = ballInfo.skill
	if skillServerTime then
		if type(skillServerTime) ~= "number" or skillServerTime ~= skillServerTime then
			return
		end

		if player:GetAttribute("LastSkill") ~= skillServerTime then
			if skillServerTime - serverTime > 1 then -- player probably wouldn't want to skill 1 second later
				return
			end
			if not playerRecord.hasBall then
				return
			end
			player:SetAttribute("LastSkill", skillServerTime)
			self.CharacterService:Skill(player)
		end
	end

	local networkPing = player:GetAttribute("NetworkPing") or 0
	networkPing /= 1000
	networkPing += 0.15
	networkPing = math.min(networkPing, 0.5)
	serverTime = math.max(serverTime, self.serverSimulationTime - networkPing)
	local tackledEnemy = ballInfo.tackledEnemy
	if tackledEnemy then
		if not player:GetAttribute("CanStealClient") or not player:GetAttribute("CanSteal") then
			return
		end

		local enemyId = ballSimulation.state.ownerId
		local enemyRecord = self:GetPlayerByUserId(enemyId)
		if enemyRecord == nil then
			return
		end
		local enemyChickynoid = enemyRecord.chickynoid
		if enemyChickynoid == nil then
			return
		end

		local enemyHitBox = enemyChickynoid.hitBox
		if enemyHitBox == nil then
			return
		end

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Include
		overlapParams.FilterDescendantsInstances = {enemyHitBox}

		local characterCF = CFrame.new(simulation.state.pos) * CFrame.Angles(0, simulation.state.angle, 0)

		local tackleHitBox: BasePart = assets.Hitboxes.Tackle
		if isGoalkeeper then
			local diveHitboxTemplate = assets.Hitboxes.Dive:FindFirstChild(Lib.getHiddenAttribute(player, "ServerDiveHitbox"))
			if diveHitboxTemplate == nil then
				return
			end
			tackleHitBox = diveHitboxTemplate
		end

		-- local visualHitbox = tackleHitBox:Clone()
		-- visualHitbox.Transparency = 0
		-- visualHitbox.Anchored = true
		-- visualHitbox.CFrame = characterCF * tackleHitBox.PivotOffset:Inverse()
		-- visualHitbox.Size += Vector3.one
		-- visualHitbox.Parent = workspace

		-- characterHitbox.CFrame = characterCF
		-- characterHitbox.Parent = workspace

		Antilag:PushPlayerPositionsToTime(playerRecord, serverTime)
		-- characterHitbox2.CFrame = enemyHitBox.CFrame
		-- characterHitbox2.Parent = workspace
		local enemyCharacter = workspace:GetPartBoundsInBox(characterCF * tackleHitBox.PivotOffset:Inverse(), tackleHitBox.Size + Vector3.one, overlapParams)[1]
		Antilag:Pop()

		local ballOwner = Players:GetPlayerByUserId(enemyRecord.userId)
		if enemyCharacter == nil then
			if isGoalkeeper then
				return -- Don't do "missed tackles" for goalkeeper
			end

			Lib.setHiddenAttribute(player, "CanStealClient", false)

			if ballOwner:GetAttribute("Position") == "Goalkeeper" then
				return
			end

            local tackleTrove = Trove.new()
			tackleTrove:AttachToInstance(player)
            tackleTrove:Add(task.delay(Lib.getCooldown(player, "TackleEnd"), function()
                tackleTrove:Destroy()
				if player == nil or player.Parent == nil then
					return
				end
            end))
            tackleTrove:Connect(player:GetAttributeChangedSignal("CanSteal"), function()
                tackleTrove:Destroy()
            end)

			return
		end
		local stealString = "CanSteal"
		if not isGoalkeeper and enemyCharacter:GetAttribute("Skill") then
			Lib.setHiddenAttribute(player, stealString, false)
			-- missed tackle
	
			return
		end

		self.CharacterService:StealBall(player)

		return
	end

	local claimPos = ballInfo.claimPos
	if claimPos then
		local ownerId = ballSimulation.state.ownerId
		local serverDeflect = not (
			ownerId ~= player.UserId
			or ballInfo.deflectInfo == nil
			or not ballInfo.deflectInfo.serverDeflect
			or ballSimulation.state.action ~= Enums.BallActions.ServerClaim
			or tick() - ballController.claimTime > 0.7
		)

		if ownerId ~= 0 then
			if not serverDeflect then -- For if the player wanted to deflect before the server made them automatically claim the ball, also give them only 0.7s after server claims so they can't deflect after a lot of time has passed
				return
			end
		end

		if typeof(claimPos) ~= "Vector3" or claimPos ~= claimPos then
			return
		end
		
		-- to-do: make this only go back to a certain point depending on the player's ping
		if not serverDeflect then
			local currentPos, claimCooldown, previousPos, alreadyHadLagSaveLeniency = BallPositionHistory:GetPreviousPosition(serverTime, claimPos)
			if alreadyHadLagSaveLeniency then
				return
			end
			if currentPos == nil then
				currentPos = ballSimulation.state.pos
				claimCooldown = ballController:isOnCooldown("ClaimCooldown")
				if ballController:getAttribute("LagSaveLeniency") then
					return
				end
			end
			if claimCooldown then
				return
			end
			if ballSimulation.state.netId ~= player.UserId then
				local characterCFrame = CFrame.new(simulation.state.pos) * CFrame.Angles(0, simulation.state.angle, 0)

				local filter = {characterHitbox}
				local diveHitBox: BasePart?
				if player:GetAttribute("Position") == "Goalkeeper" and Lib.isOnHiddenCooldown(player, "DiveEnd") then
					local diveHitboxTemplate = assets.Hitboxes.Dive:FindFirstChild(Lib.getHiddenAttribute(player, "ServerDiveHitbox"))
					if diveHitboxTemplate then
						diveHitBox = diveHitboxTemplate:Clone()
						diveHitBox:PivotTo(characterCFrame)
						diveHitBox.Parent = self.worldRoot
						table.insert(filter, diveHitBox)
					end
				end

				local overlapParams = OverlapParams.new()
				overlapParams.FilterType = Enum.RaycastFilterType.Include
				overlapParams.FilterDescendantsInstances = filter

				characterHitbox.CFrame = characterCFrame

				characterHitbox.Parent = self.worldRoot
				local characters = workspace:GetPartBoundsInRadius(currentPos, 1, overlapParams)
				if characters[1] == nil then
					if previousPos then
						local raycastParams = RaycastParams.new()
						raycastParams.FilterType = Enum.RaycastFilterType.Include
						raycastParams.FilterDescendantsInstances = filter
						local function doRaycast(startPos, rayDirection: Vector3): (RaycastResult?, boolean)
							local radius = 1
							local raycastResult = workspace:Spherecast(startPos, radius, rayDirection, raycastParams)
							local lineRaycast = false
							if raycastResult == nil then
								raycastResult = workspace:Raycast(startPos, rayDirection + rayDirection.Unit*radius, raycastParams)
								lineRaycast = true
							end
							return raycastResult, lineRaycast
						end

						local raycastResult = doRaycast(previousPos, (currentPos - previousPos))
						if diveHitBox then
							diveHitBox:Destroy()
						end
						if raycastResult == nil then
							return
						end
					else
						if diveHitBox then
							diveHitBox:Destroy()
						end
						return
					end
				end
			else
				-- note: extrapolate position or do something to figure out where the ball should be on the client
				local distance = (currentPos - simulation.state.pos).Magnitude
				-- print(distance)
				if distance > 8 then
					return
				end
			end
		end

		local deflectInfo = ballInfo.deflectInfo
		if deflectInfo then
			local shotType, shotPower, shotDirection, curveFactor = deflectInfo.shotType, deflectInfo.shotPower, deflectInfo.shotDirection, deflectInfo.curveFactor
			if not t.tuple(t.string, t.number, t.Vector3, t.number)(shotType, shotPower, shotDirection, curveFactor) then
				return
			end
			if not table.find({"DeflectShoot"}, shotType) then
				return
			end
			shotPower = math.clamp(shotPower, 0, privateServerInfo:GetAttribute("MaxShotPower"))
			if shotPower ~= shotPower then -- nan
				return
			end
			shotDirection = shotDirection.Unit
			if shotDirection ~= shotDirection or shotDirection.Magnitude == 0 then
				return
			end
			if curveFactor ~= curveFactor or curveFactor > GameInfo.MAXIMUM_CURVE_FACTOR then
				return
			end
			self.CharacterService:DeflectBall(player, shotType, shotPower, shotDirection, curveFactor, true)
			pushBallForward()
		else
			self.CharacterService:ClaimBall(player)
			pushBallForward()
		end

		return
	end

	local shotInfo = ballInfo.shotInfo
	if shotInfo and shotInfo.guid == ballSimulation.state.guid then
		if ballSimulation.state.ownerId ~= playerRecord.userId then
			return
		end

		local shotType, shotPower, shotDirection, curveFactor = shotInfo.shotType, shotInfo.shotPower, shotInfo.shotDirection, shotInfo.curveFactor
		if not t.tuple(t.string, t.number, t.Vector3, t.number)(shotType, shotPower, shotDirection, curveFactor) then
			return
		end
		if not table.find({"Shoot"}, shotType) then
			return
		end
		shotPower = math.clamp(shotPower, 0, privateServerInfo:GetAttribute("MaxShotPower"))
		if shotPower ~= shotPower then -- nan
			return
		end
		shotDirection = shotDirection.Unit
		if shotDirection ~= shotDirection or shotDirection.Magnitude == 0 then
			return
		end
		if curveFactor ~= curveFactor or curveFactor > GameInfo.MAXIMUM_CURVE_FACTOR then
			return
		end
		
		self.CharacterService:ShootBall(player, shotType, shotPower, shotDirection, curveFactor)
		pushBallForward()
	end
end

return ServerModule
