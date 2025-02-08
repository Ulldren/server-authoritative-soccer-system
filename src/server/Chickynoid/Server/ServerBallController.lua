local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
--!native
--[=[
    @class ServerChickynoid
    @server

    Server-side character which exposes methods for manipulating a player's simulation
    such as teleporting and applying impulses.
]=]

local path = game.ReplicatedFirst.Chickynoid

local Enums = require(path.Shared.Enums)
local EventType = Enums.EventType
local FastSignal = require(path.Shared.Vendor.FastSignal)

local BallSimulation = require(path.Shared.Simulation.BallSimulation)
local TrajectoryModule = require(path.Shared.Simulation.TrajectoryModule)

local DeltaTable = require(path.Shared.Vendor.DeltaTable)
local BallCommandLayout = require(path.Shared.Simulation.BallCommandLayout)

local ServerMods = require(script.Parent.ServerMods)

local ServerBallController = {}
ServerBallController.__index = ServerBallController

--[=[
	Constructs a new [ServerChickynoid] and attaches it to the specified player.
	@param playerRecord any -- The player record.
	@return ServerChickynoid
]=]
function ServerBallController.new(ballRecord)
    local self = setmetatable({
        ballRecord = ballRecord,

        simulation = BallSimulation.new(ballRecord.ballId),
		characterMod = "DefaultBallController",

		attributes = {},

        unprocessedCommands = {},
        commandSerial = 0,
        lastConfirmedCommand = nil,
        elapsedTime = 0,
		playerElapsedTime = 0,
		 		
		processedTimeSinceLastSnapshot = 0,
		
        errorState = Enums.NetworkProblemState.None,

        speedCheatThreshhold = 150  , --milliseconds
       		
		maxCommandsPerSecond = 400,  --things have gone wrong if this is hit, but it's good server protection against possible uncapped fps
		smoothFactor = 0.9999, --Smaller is smoother

		serverFrames = 0,
		
		ballSpawned = FastSignal.new(),
		attributeChanged = FastSignal.new(),
		hitBoxCreated = FastSignal.new(),
		storedStates = {}, --table of the last few states we've send the client, because we use unreliables, we need to switch to ome of these to delta comrpess against once its confirmed
		
		unreliableCommandSerials = 0, --This number only ever goes up, and discards anything out of order
		
		prevCharacterData = {}, -- Rolling history key'd to serverFrame
		
        debug = {
			processedCommands = 0,
			fakeCommandsThisSecond = 0,
			antiwarpPerSecond = 0,
			timeOfNextSecond = 0,
			ping = 0
        },
    }, ServerBallController)
        -- TODO: The simulation shouldn't create a debug model like this.
    -- For now, just delete it server-side.
    if self.simulation.debugModel then
        self.simulation.debugModel:Destroy()
        self.simulation.debugModel = nil
    end

    --Apply the characterMod
    if (self.ballRecord.characterMod) then
        local loadedModule = ServerMods:GetMod("balls", self.ballRecord.characterMod)
        if (loadedModule) then
            loadedModule:Setup(self.simulation)
        end
    end

    return self
end



-- Ulldren Edits
local Lib = require(ReplicatedStorage.Lib)

local Services = script.Parent.Parent.Parent.Services
local CharacterService = require(Services.CharacterService)
local GameService = require(Services.GameService)

local Trove = require(ReplicatedStorage.Modules.Trove)

local ballTimeTrove = Trove.new()
local highlightTrove = Trove.new()
local scoreTrove = Trove.new()

local serverInfo: Configuration = ReplicatedStorage.ServerInfo


function ServerBallController:setBallOwner(server, ownerId: number | Model)
	local ballSimulation = self.simulation
	local lastOwnerId = ballSimulation.state.ownerId
	if lastOwnerId then
		if type(lastOwnerId) == "number" then
			local playerRecord = server:GetPlayerByUserId(lastOwnerId)
			if playerRecord then
				playerRecord.hasBall = false
			end
		else
			local goalkeeper: Model = lastOwnerId
			goalkeeper:SetAttribute("HasBall", false)
		end
	end
	
	ballSimulation.state.ownerId = ownerId
	Lib.removeCooldown(serverInfo, "HoldDuration")
	ballTimeTrove:Clean()

	highlightTrove:Clean()

	if type(ownerId) == "number" then
		local player = Players:GetPlayerByUserId(ownerId)
		local playerRecord = server:GetPlayerByUserId(ownerId)
		if player ~= nil and playerRecord ~= nil then
			if not playerRecord.hasBall then
				pcall(function()
					CharacterService.BallOwnerChanged:Fire(ownerId)
				end)
			end
			playerRecord.hasBall = true

			local lastNetId = ballSimulation.state.netId
			local lastNetworkOwner = if type(lastNetId) == "number" then Players:GetPlayerByUserId(lastNetId) else lastNetId
			local lastOwnerTeam
			if lastNetworkOwner and lastNetworkOwner.Parent ~= nil then
				if lastNetworkOwner:IsA("Player") then
					lastOwnerTeam = lastNetworkOwner.Team
				else
					lastOwnerTeam = lastNetworkOwner.Team.Value
				end
			end
			local onSameTeam = lastNetworkOwner and player and lastOwnerTeam == player.Team
			if not onSameTeam then
				Lib.setHiddenCooldown(player, "TackleInvulnerability", 0.4)
			end

			self:setAttribute("LagSaveLeniency", nil)
			self:setNetworkOwner(server, ownerId)

			local isGoalkeeper = player:GetAttribute("Position") == "Goalkeeper"
			if isGoalkeeper then
				Lib.setCooldown(serverInfo, "HoldDuration", 10)
				ballTimeTrove:Connect(RunService.Heartbeat, function(deltaTime: number)
					if player == nil or player.Parent == nil or player:GetAttribute("Position") ~= "Goalkeeper" then
						ballTimeTrove:Clean()
						return
					end

					if not Lib.isOnCooldown(serverInfo, "HoldDuration") then
						Lib.setHiddenCooldown(player, "BallClaimCooldown", 10)
						server.CharacterService:ResetBall(player)
					end
				end)
			end

			self:setAttribute("Team", player.Team.Name)
		end
	else
		local goalkeeper: Model = ownerId
		goalkeeper:SetAttribute("HasBall", true)
		self:setNetworkOwner(server, ownerId)

		Lib.setCooldown(serverInfo, "HoldDuration", 10)
		ballTimeTrove:Connect(RunService.Heartbeat, function(deltaTime: number)
			if goalkeeper == nil or goalkeeper.Parent == nil then
				ballTimeTrove:Clean()
				return
			end

			if not Lib.isOnCooldown(serverInfo, "HoldDuration") then
				Lib.setCooldown(goalkeeper, "BallClaimCooldown", 10)
				server.CharacterService:ResetBall(goalkeeper)
			end
		end)

		self:setAttribute("Team", goalkeeper.Team.Value.Name)
	end
	self:setAttribute("TimeSinceChanged", os.clock()) -- use this to check if assist counts
end

function ServerBallController:setNetworkOwner(server, ownerId: number | Model)
	local ballSimulation = self.simulation
	local lastNetId = ballSimulation.state.netId
	if lastNetId ~= ownerId and ownerId ~= 0 then
		pcall(function()
			self:setAttribute("LastTouchedNet", nil)
			CharacterService.NetworkOwnerChanged:Fire(ownerId)
		end)
	end
	ballSimulation.state.netId = ownerId

	local timeSinceChanged = self:getAttribute("TimeSinceChanged")
	local isAssistEligible = timeSinceChanged and os.clock() - timeSinceChanged < 10
	if not isAssistEligible then
		self:setAttribute("AssistPlayer", nil)
	end

	local player = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else ownerId
	local lastNetworkOwner = if type(lastNetId) == "number" then Players:GetPlayerByUserId(lastNetId) else lastNetId
	if player and lastNetworkOwner and lastNetworkOwner:GetAttribute("Position") == "Goalkeeper" then
		Lib.removeHiddenCooldown(lastNetworkOwner, "BallClaimCooldown")
	end

	local lastOwnerTeam
	if lastNetworkOwner and lastNetworkOwner.Parent ~= nil then
		if lastNetworkOwner:IsA("Player") then
			lastOwnerTeam = lastNetworkOwner.Team
		else
			lastOwnerTeam = lastNetworkOwner.Team.Value
		end
	end
	local onSameTeam = lastNetworkOwner and player and lastOwnerTeam == player.Team
	if isAssistEligible and onSameTeam and lastNetworkOwner:IsA("Player") and lastNetworkOwner ~= player then
		self:setAttribute("AssistPlayer", lastNetworkOwner)
		self:setAttribute("AssistTime", os.clock())
		task.spawn(function()
			if lastNetworkOwner == nil then
				return
			end
			GameService:BallPassed(lastNetworkOwner)
		end)
	elseif not onSameTeam then
		self:setAttribute("AssistPlayer", nil)
		self:setAttribute("AssistTime", os.clock())
	end

	lastNetworkOwner = player
	if player then
		if player:IsA("Player") then
			self:setAttribute("OwnerName", player.DisplayName)
			self:setAttribute("Team", player.Team.Name)
		else
			local teamName = player.Team.Value.Name
			self:setAttribute("Team", teamName)
			self:setAttribute("OwnerName", serverInfo:GetAttribute(teamName .. "Name") .. "'s Goalkeeper")
		end
	else
		self:setAttribute("OwnerName", nil)
	end
end

function ServerBallController:setAttribute(attribute: string, value: any)
    self.attributes[attribute] = value

	pcall(function()
		self.attributeChanged:Fire(attribute, value)
	end)
end

function ServerBallController:getAttribute(attribute: string)
    return self.attributes[attribute]
end

function ServerBallController:setCooldown(attribute: string, cooldown: number)
    local now = workspace:GetServerTimeNow()
    local currentCD = self.attributes[attribute]
    if currentCD and currentCD - now > cooldown then
        return
    end
    self.attributes[attribute] = now + cooldown
end

function ServerBallController:removeCooldown(attribute: string)
    self.attributes[attribute] = nil
end

function ServerBallController:getCooldown(attribute: string)
    local value = self.attributes[attribute]
    return value and math.max(0, value - workspace:GetServerTimeNow())
end

function ServerBallController:isOnCooldown(attribute: string, lagCompensation: number | nil)
    local value = self.attributes[attribute]
    if value and lagCompensation then
        value += lagCompensation
    end
    return value and value - workspace:GetServerTimeNow() > 0
end

local flareGuid = nil
local netTouchedSignal = FastSignal.new()
function ServerBallController:CreateGoalEffect(teamScoredOn: string, callback: () -> () | nil)
    local playerWhoScored: Player = Players:GetPlayerByUserId(self.simulation.state.netId)


    local goalEffectTrove = Trove.new()
    local ballPos = self.simulation.state.pos
    local function doGoalEffect(net: MeshPart, setCFrame: boolean)
        goalEffectTrove:Destroy()

		if callback then
            task.spawn(callback)
        end

        -- do goal effect stuff

		-- if you want the ball to disappear after a goal
		-- self:SetPosition(Vector3.zero)
		-- self.simulation.state.guid += 1
		-- self.simulation.state.action = Enums.BallActions.Teleport
		self.simulation.state.netId = 0
    end

    local lastTouchedNet: MeshPart = self:getAttribute("LastTouchedNet")
    if lastTouchedNet ~= nil and lastTouchedNet.Parent.Parent.Name == teamScoredOn then
        ballPos = self:getAttribute("NetTouchedPos")
        doGoalEffect(lastTouchedNet, true)
        return
    end

    goalEffectTrove:Connect(netTouchedSignal, function(net: MeshPart)
        if not net:HasTag("Net") or net.Parent.Parent.Name ~= teamScoredOn then
            return
        end
        doGoalEffect(net, false)
    end)
    goalEffectTrove:Add(task.delay(1, doGoalEffect))
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include
overlapParams.FilterDescendantsInstances = {CollectionService:GetTagged("GoalHitbox")}
function ServerBallController:OnTouchedGoal(goalHitbox)
	local gameStatus = serverInfo:GetAttribute("GameStatus")
    if gameStatus ~= "InProgress" and gameStatus ~= "Practice" then
        return
    end
    if self:getAttribute("GoalScored") then
        return
    end
	if self.simulation.state.ownerId ~= 0 then
		return
	end

	local goalTeam = goalHitbox.Name
	self:setAttribute("GoalTeam", goalTeam)
    local function doScored()
        scoreTrove:Clean()
        
        if self:getAttribute("GoalScored") then
            return
        end
		self:setAttribute("GoalScored", true)

        if serverInfo:GetAttribute("GameStatus") == "InProgress" then
            self:CreateGoalEffect(goalTeam, function()
                GameService:GoalScored(goalTeam)
            end)
        elseif serverInfo:GetAttribute("GameStatus") == "Practice" then
            self:CreateGoalEffect(goalTeam)
        end
    end

    local teamGoalkeeper: Player = serverInfo[goalTeam].Goalkeeper.Value
    if teamGoalkeeper == nil then
        doScored()
    else
        if self:getAttribute("LagSaveLeniency") then
            return
        end
        self:setAttribute("LagSaveLeniency", true)

        local networkPing = teamGoalkeeper:GetNetworkPing()
        if teamGoalkeeper.UserId < 0 then
            networkPing = 0.5
        end
        local leniency = math.min(0.5, networkPing + 0.1)
        scoreTrove:Add(task.delay(leniency, doScored))
		scoreTrove:Connect(self.attributeChanged, function(attributeName, value)
			if attributeName == "LagSaveLeniency" and value == nil then
				scoreTrove:Clean()
			elseif attributeName.Name == "GoalkeeperConfirmed" then
				doScored()
			end
		end)
    end
end


function ServerBallController:Destroy()
    if self.pushPart then
        self.pushPart:Destroy()
        self.pushPart = nil
    end

    if self.hitBox then
        self.hitBox:Destroy()
        self.hitBox = nil
    end

    if self.pushes ~= nil then
        for _, record in pairs(self.pushes) do
            record.attachment:Destroy()
            record.pusher:Destroy()
        end
        self.pushes = {}
    end
end

function ServerBallController:HandleEvent(server, event)
    -- self:HandleClientUnreliableEvent(server, event, false)
end

--[=[
    Sets the position of the character and replicates it to clients.
]=]
function ServerBallController:SetPosition(position: Vector3, teleport)
    self.simulation.state.pos = position
    -- self.simulation.characterData:SetTargetPosition(position, teleport)
end

--[=[
    Returns the position of the character.
]=]
function ServerBallController:GetPosition()
    return self.simulation.state.pos
end

function ServerBallController:BallThink(server, deltaTime)	
    local command = {}
    command.localFrame = self.ballRecord.frame
    command.serverTime = tick()
    command.deltaTime = deltaTime
    
    local event = {}
    event[1] = BallCommandLayout:EncodeCommand(command)
    self:HandleClientUnreliableEvent(server, event, true)
end

function ServerBallController:GenerateFakeCommand(server, deltaTime, command: {}?)

	command = command or {}
	command.localFrame = self.unreliableCommandSerials + 1
	command.deltaTime = deltaTime
	
	local event = {}
	event[1] = BallCommandLayout:EncodeCommand(command)
	self:HandleClientUnreliableEvent(server, event, true)
	-- print("created fake command")
	
	
	-- self.debug.fakeCommandsThisSecond += 1
end

--[=[
	Steps the simulation forward by one frame. This loop handles the simulation
	and replication timings.
]=]
function ServerBallController:Think(server, _serverSimulationTime, deltaTime)
    --  Anticheat methods
    --  We keep X ms of commands unprocessed, so that if players stop sending upstream, we have some commands to keep going with
    --  We only allow the player to get +150ms ahead of the servers estimated sim time (Speed cheat), if they're over this, we discard commands
    --  The server will generate a fake command if you underrun (do not have any commands during time between snapshots)
    --  todo: We only allow 15 commands per server tick (ratio of 5:1) if the user somehow has more than 15 commands that are legitimately needing processing, we discard them all

	self.elapsedTime += deltaTime
 
    --Sort commands by their serial
    table.sort(self.unprocessedCommands, function(a, b)
        return a.serial < b.serial
	end)
	
    local maxCommandsPerFrame = math.ceil(self.maxCommandsPerSecond * deltaTime)
    
	local processCounter = 0
	for _, command in pairs(self.unprocessedCommands) do
 	
		processCounter += 1
		
		--print("server", command.l, command.serverTime)
		TrajectoryModule:PositionWorld(command.serverTime, command.deltaTime)
		self.debug.processedCommands += 1
				
		--Step simulation!
		self.simulation:DoServerAttributeChecks()
		local hitCharacter: BasePart | Model, hitNet, moveDelta = self.simulation:ProcessCommand(command, server)
		self:RobloxPhysicsStep(server)

		if hitCharacter then
			xpcall(function()
				if hitCharacter:HasTag("Goalkeeper") then
					CharacterService:ClaimBall(hitCharacter, true)
					return
				end

				local userId = hitCharacter:GetAttribute("player")
				if userId == nil then
					return
				end
				local actualPlayer = Players:GetPlayerByUserId(userId)
				if actualPlayer == nil then
					return
				end
				if actualPlayer:GetAttribute("Position") ~= "Goalkeeper" and moveDelta < 0.01 then -- if barely moving, don't do server claim detection
					return
				end
				CharacterService:ClaimBall(actualPlayer, true)
			end, function(errorMessage)
				warn("[ServerBallController] Think - hit player: " .. errorMessage)
			end)
		end
		local pos = self.simulation.state.pos
		local goalHitbox = workspace:GetPartBoundsInRadius(pos, 1, overlapParams)[1]
		if goalHitbox then
			xpcall(function()
				self:OnTouchedGoal(goalHitbox)
			end, function(errorMessage)
				warn("[ServerBallController] Think - touched goal failed: " .. errorMessage)
			end)
		end
		if hitNet then
			xpcall(function()
				if self:getAttribute("LastTouchedNet") == nil then
					self:setAttribute("LastTouchedNet", hitNet)
					self:setAttribute("NetTouchedPos", self.simulation.state.pos)
				end
				netTouchedSignal:Fire(hitNet)
			end, function(errorMessage)
				warn("[ServerBallController] Think - net touched signal failed: " .. errorMessage)
			end)
		end

		command.processed = true

		if command.localFrame and tonumber(command.localFrame) ~= nil then
			self.lastConfirmedCommand = command.localFrame
			self.lastProcessedCommand = command
		end
		
		self.processedTimeSinceLastSnapshot += command.deltaTime

		if (processCounter > maxCommandsPerFrame and false) then
			--dump the remaining commands
			self.errorState = Enums.NetworkProblemState.TooManyCommands
			self.unprocessedCommands = {}
			break
		end
	end
 
    local newList = {}
    for _, command in pairs(self.unprocessedCommands) do
        if command.processed ~= true then
            table.insert(newList, command)
        end
    end

	self.unprocessedCommands = newList
	
	
	--debug stuff, too many commands a second stuff
	if (tick() > self.debug.timeOfNextSecond) then
		
		self.debug.timeOfNextSecond = tick() + 1
		self.debug.antiwarpPerSecond = self.debug.fakeCommandsThisSecond
		self.debug.fakeCommandsThisSecond = 0
		
		if (self.debug.antiwarpPerSecond  > 0) then
			print("Lag: ",self.debug.antiwarpPerSecond )
		end
	end
end



--[=[
	Callback for handling movement commands from the client

	@param event table -- The event sent by the client.
	@private
]=]
function ServerBallController:HandleClientUnreliableEvent(server, event, fakeCommand)

	if (event[2] ~= nil) then
		local prevCommand = BallCommandLayout:DecodeCommand(event[2])
		self:ProcessCommand(server, prevCommand, fakeCommand, true)
	end
	
	if (event[1] ~= nil) then
		local command = BallCommandLayout:DecodeCommand(event[1])		
		self:ProcessCommand(server, command, fakeCommand, false)
	end
end

function ServerBallController:ProcessCommand(server, command, fakeCommand, resent)
	
	
	if command and typeof(command) == "table" then
		
		if (command.localFrame == nil or typeof(command.localFrame) ~= "number" or command.localFrame ~= command.localFrame) then
			if fakeCommand then
				print("1")
			end
			return
		end
		
		if (command.localFrame <= self.unreliableCommandSerials) then
			if fakeCommand then
				print("2")
				print(command.localFrame, self.unreliableCommandSerials)
			end
			return
		end
		
		if (command.localFrame - self.unreliableCommandSerials > 1) then
			-- if fakeCommand then
			-- 	print("3")
			-- end
			--warn("Skipped a packet", command.l - self.unreliableCommandSerials)
			
			if (resent) then
				self.errorState = Enums.NetworkProblemState.DroppedPacketGood
			else
				self.errorState = Enums.NetworkProblemState.DroppedPacketBad
			end
		end
		
		self.unreliableCommandSerials = command.localFrame
	
		--Sanitize
		--todo: clean this into a function per type

		if  command.deltaTime == nil
			or typeof(command.deltaTime) ~= "number"
			or command.deltaTime ~= command.deltaTime
		then
			if fakeCommand then
				print("9")
			end
			return
		end

		--sanitize
		if (fakeCommand == false) then
			if server.config.fpsMode == Enums.FpsMode.Uncapped then
				--Todo: really slow players need to be penalized harder.
				if command.deltaTime > 0.5 then
					command.deltaTime = 0.5
				end

				--500fps cap
				if command.deltaTime < 1 / 500 then
					command.deltaTime = 1 / 500
					--print("Player over 500fps:", self.playerRecord.name)
				end
			elseif server.config.fpsMode == Enums.FpsMode.Hybrid then
				--Players under 30fps are simualted at 30fps
				if command.deltaTime > 1 / 30 then
					command.deltaTime = 1 / 30
				end

				--500fps cap
				if command.deltaTime < 1 / 500 then
					command.deltaTime = 1 / 500
					--print("Player over 500fps:", self.playerRecord.name)
				end
			elseif server.config.fpsMode == Enums.FpsMode.Fixed60 then
				command.deltaTime = 1/60
			elseif server.config.fpsMode == Enums.FpsMode.Fixed30 then
				command.deltaTime = 1/20
			else
				warn("Unhandled FPS mode")
			end
		end

		if command.deltaTime then
			--On the first command, init
			if self.playerElapsedTime == 0 then
				self.playerElapsedTime = self.elapsedTime
			end
			local delta = self.playerElapsedTime - self.elapsedTime

			--see if they've fallen too far behind
			if (delta < -(self.speedCheatThreshhold / 1000)) then
				self.playerElapsedTime = self.elapsedTime
				self.errorState = Enums.NetworkProblemState.TooFarBehind
			end

			--test if this is wthin speed cheat range?
			--print("delta", self.playerElapsedTime - self.elapsedTime)
			if self.playerElapsedTime > self.elapsedTime + (self.speedCheatThreshhold / 1000) and not fakeCommand then
				--print("Player too far ahead", self.playerRecord.name)
				--Skipping this command
				self.errorState = Enums.NetworkProblemState.TooFarAhead
			else


				--write it!
				self.playerElapsedTime += command.deltaTime

				command.elapsedTime = self.elapsedTime --Players real time when this was written.

				command.playerElapsedTime = self.playerElapsedTime
				command.fakeCommand = fakeCommand
				command.serial = self.commandSerial
				self.commandSerial += 1

				--This is the only place where commands get written for the rest of the system
				table.insert(self.unprocessedCommands, command)
			end

			--Debug ping
			if (command.serverTime ~= nil and fakeCommand == false and self.playerRecord.dummy == false) then
				self.debug.ping = math.floor((server.serverSimulationTime - command.serverTime) * 1000)
				self.debug.ping -= ( (1 / server.config.serverHz) * 1000)
			end
		end
	end

end

--Constructs a playerState based on "now" delta'd against the last playerState the player has confirmed seeing (self.lastConfirmedPlayerState) 
--If they have not confirmed anything, return a whole state
function ServerBallController:ConstructBallStateDelta()

	local currentState = self.simulation:WriteState()
	local lastProcessedCommand = self.lastProcessedCommand or {}
	return currentState, lastProcessedCommand.localFrame
end


--[=[
    Picks a location to spawn the character and replicates it to the client.
    @private
]=]
function ServerBallController:SpawnChickynoid()
    
    --If you need to change anything about the chickynoid initial state like pos or rotation, use OnBeforePlayerSpawn
    -- if self.playerRecord.dummy == false then
    --     local event = {}
    --     event.t = EventType.ChickynoidAdded
    --     event.state = self.simulation:WriteState()
    --     event.characterMod = self.playerRecord.characterMod
    --     self.playerRecord:SendEventToClient(event)
    -- end
    --@@print("Spawned character and sent event for player:", self.playerRecord.name)
end

function ServerBallController:PostThink(server, deltaTime)
    self:UpdateServerCollisionBox(server)

    -- self.simulation.ballData:SmoothPosition(deltaTime, self.smoothFactor)
end

function ServerBallController:UpdateServerCollisionBox(server)
    --Update their hitbox - this is used for raycasts on the server against the player
    if self.hitBox == nil then
        --This box is also used to stop physics props from intersecting the player. Doesn't always work!
        --But if a player does get stuck, they should just be able to move away from it
        local ball = ReplicatedStorage.Assets.Ball:Clone()
		ball.Transparency = 0
        ball.Size = Vector3.new(2, 2, 2)
        ball.Parent = server.worldRoot
		ball.CFrame = CFrame.new(self.simulation.state.pos)
        ball.Anchored = true
        ball.CanTouch = true
        ball.CanCollide = false
        ball.CanQuery = true
        ball.Shape = Enum.PartType.Ball
		ball:AddTag("ServerBallHitbox")
        ball:SetAttribute("ballId", self.ballRecord.ballId)
        self.hitBox = ball
        self.hitBoxCreated:Fire(self.hitBox);
    end
    self.hitBox.CFrame = CFrame.new(self.simulation.state.pos)
    self.hitBox.Velocity = self.simulation.state.vel
end

function ServerBallController:RobloxPhysicsStep(server, _deltaTime)
	
	self:UpdateServerCollisionBox(server)
   
end

return ServerBallController
