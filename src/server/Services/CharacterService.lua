local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local AnimationRemoteEvent = Instance.new("RemoteEvent")
AnimationRemoteEvent.Name = "AnimationReplication"
AnimationRemoteEvent.Parent = ReplicatedStorage

local Enums = require(ReplicatedFirst.Chickynoid.Shared.Enums)

local EffectService
local EmoteService

local Lib = require(ReplicatedStorage.Lib)

local GameInfo = require(ReplicatedStorage.Data.GameInfo)

local Constraints = require(ReplicatedStorage.Modules.Constraints)
local Trove = require(ReplicatedStorage.Modules.Trove)

local privateServerInfo: Configuration = ReplicatedStorage.PrivateServerInfo

local assets = ReplicatedStorage.Assets
local animations = assets.Animations


local CharacterService = {
    Name = "CharacterService",
    Client = {},
    BallOwnerChanged = Instance.new("BindableEvent").Event,
    NetworkOwnerChanged = Instance.new("BindableEvent").Event,
}

function CharacterService:KnitInit()
    local Packages = ServerScriptService.ServerScripts.Chickynoid.Server
    self.ServerModule = require(Packages.ServerModule)
    self.ServerModule.CharacterService = self
    self.ServerMods = require(Packages.ServerMods)

    self.ServerModule:RecreateCollisions(workspace.MapItems.ChickynoidCollisions)

    self.ServerMods:RegisterMods("servermods", ServerScriptService.ServerScripts.Chickynoid.Examples.ServerMods)
    self.ServerMods:RegisterMods("characters", ReplicatedFirst.Chickynoid.Examples.Characters)
    self.ServerMods:RegisterMods("balls", ReplicatedFirst.Chickynoid.Examples.Balls)

    self.ServerModule:Setup()
    self.ServerModule:AddBall()

    -- local Bots = require(ServerScriptService.ServerScripts.Chickynoid.Server.Bots)
    -- Bots:MakeBots(self.ServerModule, 11)
end

function CharacterService:KnitStart()
    local services = script.Parent
    EffectService = require(services.EffectService)
    EmoteService = require(services.EmoteService)

    for _, player in pairs(Players:GetPlayers()) do
        task.spawn(function()
            self:PlayerAdded(player)
        end)
    end
    Players.PlayerAdded:Connect(function(player)
        self:PlayerAdded(player)
    end)
    Players.PlayerRemoving:Connect(function(player)
        self:ResetBall(player)
    end)

    local function resetBall(character)
        local player = Players:GetPlayerFromCharacter(character)
        if player == nil then
            return
        end
        self:ResetBall(player)
        EmoteService:EndEmote(player)
    end
    CollectionService:GetInstanceAddedSignal("Ragdoll"):Connect(resetBall)
end

function CharacterService:PlayerAdded(player: Player)
    player:GetAttributeChangedSignal("ServerChickyRagdoll"):Connect(function()
        self:ResetBall(player)
    end)
    player:GetAttributeChangedSignal("ServerChickyFrozen"):Connect(function()
        self:ResetBall(player)
    end)

    player:GetPropertyChangedSignal("Team"):Connect(function()
        self:ResetBall(player)
    end)
end

function CharacterService:ResetBall(player: Player)
    if player:IsA("Player") then
        local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
        if playerRecord == nil then
            return
        end
        if not playerRecord.hasBall then
            return
        end
        playerRecord.hasBall = false
        local ballRecord = self.ServerModule.ballRecord
        local ballController = ballRecord.ballController
        local ballSimulation = ballController.simulation
        if ballSimulation.state.ownerId == player.UserId then
            ballSimulation.state.guid += 1
            ballSimulation.state.action = Enums.BallActions.Reset
            ballController:setBallOwner(self.ServerModule, 0)
            ballController:setNetworkOwner(self.ServerModule, 0)
        end
    else
        if not player:GetAttribute("HasBall") then
            return
        end
        local ballRecord = self.ServerModule.ballRecord
        local ballController = ballRecord.ballController
        local ballSimulation = ballController.simulation
        ballSimulation.state.guid += 1
        ballSimulation.state.action = Enums.BallActions.Reset
        ballController:setBallOwner(self.ServerModule, 0)
        ballController:setNetworkOwner(self.ServerModule, 0)
    end
end

-- Basics
local function checkSave(player: Player, ballController)
    if not Lib.playerInGame(player) or Lib.playerIsStunned(player) then
        return
    end
    if player:GetAttribute("Position") ~= "Goalkeeper" then
        return
    end

    if ballController:getAttribute("Team") == player.Team.Name then
        return
    end

    task.spawn(function()
        -- saved ball
    end)
end

function CharacterService:ClaimBall(player: Player, serverClaim: boolean?)
    if player:IsA("Player") then
        if not Lib.playerInGame(player) or Lib.playerIsStunned(player) then
            return
        end
    end

    local ballRecord = self.ServerModule.ballRecord
	local ballController = ballRecord.ballController
	if ballController == nil then
		return
	end

	local ballSimulation = ballController.simulation
    if ballSimulation.state.ownerId ~= 0 then
        return
    end

    if ballController:getAttribute("GoalScored") then
        return
    end
    if ballController:getAttribute("LagSaveLeniency") and player:GetAttribute("Position") ~= "Goalkeeper" then
        return
    end


    if player:IsA("Player") then
        local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
        if playerRecord == nil then
            return
        end
        if playerRecord.hasBall then
            return
        end

        local chickynoid = playerRecord.chickynoid
        if chickynoid == nil then
            return
        end
        local simulation = chickynoid.simulation

        local netId = ballSimulation.state.netId
        local networkOwner: Player = if type(netId) == "number" then Players:GetPlayerByUserId(netId) else netId
        if ballController:isOnCooldown("ClaimCooldown", -0.1) and player:GetAttribute("Position") ~= "Goalkeeper" -- add lag comp of -0.1 because this can only be called on the server
        and networkOwner and networkOwner ~= player then
            return
        end

        -- If the goalkeeper threw the ball, it should ignore players on the other team for a bit
        if ballController:isOnCooldown("ClaimCooldown") and networkOwner and networkOwner:GetAttribute("Position") == "Goalkeeper" and networkOwner.Team ~= player.Team then
            return
        end
        if Lib.isOnHiddenCooldown(player, "BallClaimCooldown") then
            return
        end
    
        if ballController:isOnCooldown("SpawnClaimCooldown") then
            return
        end
    
        checkSave(player, ballController)
    
        Lib.setHiddenCooldown(player, "CanJumpWithBall", 1)

        Lib.setHiddenCooldown(player, "BallClaimCooldown", 0.3)

        ballController.claimTime = tick()
        ballSimulation.state.guid += 1
        if serverClaim then
            ballSimulation.state.action = Enums.BallActions.ServerClaim
        else
            ballSimulation.state.action = Enums.BallActions.Claim
        end
		ballController:setBallOwner(self.ServerModule, player.UserId)


        if player:GetAttribute("Position") == "Goalkeeper" then
            local typeOfCatch = ballSimulation.state.pos.Y - simulation.state.pos.Y > 1 and "High" or "Low"
            simulation.characterData:PlayAnimation(typeOfCatch .. "Catch", Enums.AnimChannel.Channel1, true)
        end
    else
        if player:GetAttribute("HasBall") then
            return
        end

        local character = player
        local humanoidRootPart: BasePart = character and character:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart == nil then
            return
        end
    
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid == nil or humanoid.Health == 0 then
            return
        end
    
        if Lib.isOnHiddenCooldown(player, "BallClaimCooldown") then
            return
        end
    
        Lib.setHiddenCooldown(player, "BallClaimCooldown", 0.3)

        ballController.claimTime = tick()
        ballSimulation.state.guid += 1
        if serverClaim then
            ballSimulation.state.action = Enums.BallActions.ServerClaim
        else
            ballSimulation.state.action = Enums.BallActions.Claim
        end
		ballController:setBallOwner(self.ServerModule, player)

        local typeOfCatch = ballSimulation.state.pos.Y - humanoidRootPart.CFrame.Position.Y > 1 and "High" or "Low"
        local animator: Animator = humanoid:FindFirstChild("Animator")
        if animator == nil then
            return
        end
        local catchAnimation = animator:LoadAnimation(animations[typeOfCatch .. "Catch"])
        catchAnimation:Play(0)
    end
end

function CharacterService:StealBall(player: Player)
    if player:IsA("Player") then
        if not Lib.playerInGame(player) or Lib.playerIsStunned(player) then
            return
        end
    end

    local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil then
        return
    end
    if playerRecord.hasBall then
        return
    end

    local chickynoid = playerRecord.chickynoid
    if chickynoid == nil then
        return
    end


    local stealString = "CanSteal"
    if not Lib.getHiddenAttribute(player, stealString) then
        return
    end

    local ballRecord = self.ServerModule.ballRecord
	local ballController = ballRecord.ballController
	if ballController == nil then
		return
	end
    if ballController:getAttribute("GoalScored") then
        return
    end

	local ballSimulation = ballController.simulation

    if ballController:getAttribute("LagSaveLeniency") and player:GetAttribute("Position") ~= "Goalkeeper" then
        return
    end

    local ownerId = ballSimulation.state.ownerId
    local ballOwner = Players:GetPlayerByUserId(ownerId)
    local ballOwnerTeam
    if ballOwner then
        ballOwnerTeam = ballOwner:IsA("Player") and ballOwner.Team or ballOwner.Team.Value
    end
    local playerTeam = player:IsA("Player") and player.Team or player.Team.Value
    if ballOwner == nil or ballOwnerTeam == playerTeam or ballOwner:GetAttribute("Position") == "Goalkeeper" then
        return
    end

    local enemyPlayerRecord = self.ServerModule:GetPlayerByUserId(ownerId)
    local enemyChickynoid = enemyPlayerRecord.chickynoid
    if enemyChickynoid == nil then
        return
    end


    if not Lib.isOnHiddenCooldown(player, "TackleEnd") 
    and not Lib.isOnHiddenCooldown(player, "DiveEnd") then
        return
    end

    if Lib.isOnHiddenCooldown(player, "BallClaimCooldown") then
        return
    end

    local tackleTime = ballController:getAttribute("TackleTime")
    if player:GetAttribute("Position") ~= "Goalkeeper" and tackleTime and tackleTime > Lib.getHiddenAttribute(player, "TackleStart") then
        return
    end


    if player:GetAttribute("Position") ~= "Goalkeeper" and Lib.isOnHiddenCooldown(ballOwner, "TackleInvulnerability") then
        Lib.setHiddenAttribute(player, stealString, false)
        return
    end
    if player:GetAttribute("Position") ~= "Goalkeeper" and Lib.isOnHiddenCooldown(ballOwner, "SkillEnd") then
        Lib.setHiddenAttribute(player, stealString, false)

        -- missed tackle, player successfully used skill
        return
    end

    ballController:setAttribute("TackleTime", workspace:GetServerTimeNow())
    Lib.setHiddenAttribute(player, "CanSteal", false)
    Lib.setHiddenAttribute(player, "CanStealClient", false)

    Lib.setHiddenCooldown(player, "BallClaimCooldown", 0.3)

    ballSimulation.state.guid += 1
    ballSimulation.state.action = Enums.BallActions.Claim
    ballController:setBallOwner(self.ServerModule, player.UserId)


    local knockback = enemyChickynoid.simulation.state.vel
    if knockback then
        knockback = knockback.Unit
    end
    if knockback ~= knockback or knockback.Magnitude == 0 then
        knockback = Vector3.new(0, 3, 0)
    end
    self.ServerModule:KnockbackPlayer(ballOwner, knockback, GameInfo.TACKLE_RAGDOLL_TIME, nil, true)
    
    if player:GetAttribute("Position") == "Goalkeeper" then
        -- steal
    else
        -- tackled
    end
end

function CharacterService:AIGoalkeeperStealBall(player: Player)
    local ballRecord = self.ServerModule.ballRecord
	local ballController = ballRecord.ballController
	if ballController == nil then
		return
	end
    if ballController:getAttribute("GoalScored") then
        return
    end

    if ballController:getAttribute("LagSaveLeniency") and player:GetAttribute("Position") ~= "Goalkeeper" then
        return
    end

    local ballSimulation = ballController.simulation

    local ownerId = ballSimulation.state.ownerId
    local ballOwner = Players:GetPlayerByUserId(ownerId)
    local ballOwnerTeam
    if ballOwner then
        ballOwnerTeam = ballOwner:IsA("Player") and ballOwner.Team or ballOwner.Team.Value
    end
    local playerTeam = player:IsA("Player") and player.Team or player.Team.Value
    if ballOwner == nil or ballOwnerTeam == playerTeam or ballOwner:GetAttribute("Position") == "Goalkeeper" then
        return
    end

    local enemyPlayerRecord = self.ServerModule:GetPlayerByUserId(ownerId)
    local enemyChickynoid = enemyPlayerRecord.chickynoid
    if enemyChickynoid == nil then
        return
    end


    ballController:setAttribute("TackleTime", workspace:GetServerTimeNow())

    Lib.setHiddenCooldown(player, "BallClaimCooldown", 0.3)

    ballSimulation.state.guid += 1
    ballSimulation.state.action = Enums.BallActions.Claim
    ballController:setBallOwner(self.ServerModule, player)

    local knockback = enemyChickynoid.simulation.state.vel
    if knockback then
        knockback = knockback.Unit
    end
    if knockback ~= knockback or knockback.Magnitude == 0 then
        knockback = Vector3.new(0, 3, 0)
    end
    self.ServerModule:KnockbackPlayer(ballOwner, knockback, GameInfo.TACKLE_RAGDOLL_TIME, nil, true)
end

function CharacterService:ShootBall(player: Player, shotType: string, shotPower: number, shotDirection: Vector3, curveFactor: number)
    if player:IsA("Player") then
        if not Lib.playerInGame(player) or Lib.playerIsStunned(player) then
            return
        end 
    end

    local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil or playerRecord.chickynoid == nil then
		return
	end
	local simulation = playerRecord.chickynoid.simulation

	local ballRecord = self.ServerModule.ballRecord
	local ballController = ballRecord.ballController
	if ballController == nil then
		return
	end
    if ballController:getAttribute("GoalScored") then
        return
    end

    ballController:setAttribute("HitTime", workspace:GetServerTimeNow())

	local ballSimulation = ballController.simulation

    local boundary = workspace.MapItems.BallBoundary
    local playerCF = CFrame.new(simulation.state.pos) * CFrame.Angles(0, simulation.state.angle, 0)
    local ballPos = (playerCF * CFrame.new(0, -1.65, -2)).Position
    if player:GetAttribute("Position") == "Goalkeeper" then
        ballPos = (playerCF * CFrame.new(0, 1, -2)).Position
    end
    ballSimulation.state.pos = Lib.clampToBoundary(ballPos, boundary)

    local vel, angVel = Lib.getShotVelocity(ballSimulation.constants.gravity, shotType, shotPower, shotDirection, curveFactor)
    ballSimulation.state.vel = vel
    ballSimulation.state.angVel = angVel

    ballSimulation.state.guid += 1
    ballSimulation.state.action = Enums.BallActions.Shoot
    ballController:setBallOwner(self.ServerModule, 0)
    ballController:setNetworkOwner(self.ServerModule, player.UserId)

    EffectService:CreateEffect("ballKicked", {player}, player)


    ballController:setAttribute("ShootPosition", ballSimulation.state.pos)
    ballController:setCooldown("ClaimCooldown", 0.1)
    if player:IsA("Player") then
        Lib.setHiddenCooldown(player, "BallClaimCooldown", 0.1)
    end

    if player:GetAttribute("Position") == "Goalkeeper" then
        ballController:setCooldown("ClaimCooldown", 0.5)
        Lib.setHiddenCooldown(player, "BallClaimCooldown", 10)

        local claimCooldownTrove = Trove.new()
        claimCooldownTrove:AttachToInstance(player)
        claimCooldownTrove:Add(task.delay(10, function()
            claimCooldownTrove:Destroy()
        end))
        claimCooldownTrove:Connect(self.NetworkOwnerChanged, function()
            Lib.removeHiddenCooldown(player, "BallClaimCooldown")
            claimCooldownTrove:Destroy()
        end)
    end
end

function CharacterService:AIGoalkeeperShootBall(character: Model, shotType: string, shotPower: number, shotDirection: Vector3, curveFactor: number)
	local ballRecord = self.ServerModule.ballRecord
	local ballController = ballRecord.ballController
	if ballController == nil then
		return
	end
    if ballController:getAttribute("GoalScored") then
        return
    end

    ballController:setAttribute("HitTime", workspace:GetServerTimeNow())

	local ballSimulation = ballController.simulation

    local boundary = workspace.MapItems.BallBoundary
    local playerCF = character.HumanoidRootPart.CFrame
    local ballPos = (playerCF * CFrame.new(0, 1, -2)).Position
    ballSimulation.state.pos = Lib.clampToBoundary(ballPos, boundary)

    local vel, angVel = Lib.getShotVelocity(ballSimulation.constants.gravity, shotType, shotPower, shotDirection, curveFactor)
    ballSimulation.state.vel = vel
    ballSimulation.state.angVel = angVel

    ballSimulation.state.guid += 1
    ballSimulation.state.action = Enums.BallActions.Shoot
    ballController:setBallOwner(self.ServerModule, 0)
    ballController:setNetworkOwner(self.ServerModule, character)

    EffectService:CreateEffect("ballKicked", {})


    ballController:setAttribute("ShootPosition", ballSimulation.state.pos)

    ballController:setCooldown("ClaimCooldown", 0.1)

    ballController:setCooldown("ClaimCooldown", 0.5)
    Lib.setCooldown(character, "BallClaimCooldown", 10)

    local claimCooldownTrove = Trove.new()
    claimCooldownTrove:AttachToInstance(character)
    claimCooldownTrove:Add(task.delay(10, function()
        claimCooldownTrove:Destroy()
    end))
    claimCooldownTrove:Connect(self.NetworkOwnerChanged, function()
        Lib.removeCooldown(character, "BallClaimCooldown")
        claimCooldownTrove:Destroy()
    end)
end

function CharacterService:DeflectBall(player: Player, shotType: string, shotPower: number, shotDirection: Vector3, deflectCurveFactor: number, serverDeflect: boolean?)
    if player:IsA("Player") then
        if not Lib.playerInGame(player) or Lib.playerIsStunned(player) then
            return
        end
    end
    
    if player:GetAttribute("Position") == "Goalkeeper" then
        return
    end
    
    local ballRecord = self.ServerModule.ballRecord
    local ballController = ballRecord.ballController
    if ballController == nil then
        return
    end

    local ballSimulation = ballController.simulation
    if ballController:getAttribute("GoalScored") then
        return
    end

    local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil then
        return
    end

    local chickynoid = playerRecord.chickynoid
    if chickynoid == nil then
        return
    end
    local simulation = chickynoid.simulation

    if not serverDeflect then
        local netId = ballSimulation.state.netId
        local networkOwner: Player | Model = if type(netId) == "number" then Players:GetPlayerByUserId(netId) else netId
        if ballController:isOnCooldown("ClaimCooldown") and player:GetAttribute("Position") ~= "Goalkeeper"
        and networkOwner and networkOwner ~= player then
            return
        end
        if ballController:isOnCooldown("ClaimCooldown") and networkOwner and networkOwner:GetAttribute("Position") == "Goalkeeper" and networkOwner.Team ~= player.Team then
            return
        end
        if Lib.isOnHiddenCooldown(player, "BallClaimCooldown") then
            return
        end

        if ballController:isOnCooldown("SpawnClaimCooldown") then
            return
        end
    end

    ballController:setAttribute("HitTime", workspace:GetServerTimeNow())

    local boundary = workspace.MapItems.BallBoundary
    local playerCF = CFrame.new(simulation.state.pos) * CFrame.Angles(0, simulation.state.angle, 0)
    local ballPos = (playerCF * CFrame.new(0, -1.65, -2)).Position
    ballSimulation.state.pos = Lib.clampToBoundary(ballPos, boundary)
    
    if shotType == "Shoot" then
        shotType = "DeflectShoot"
    end
    local vel, angVel = Lib.getShotVelocity(ballSimulation.constants.gravity, shotType, shotPower, shotDirection, deflectCurveFactor)
    ballSimulation.state.vel = vel
    ballSimulation.state.angVel = angVel

    local playerIsNetworkOwner = ballSimulation.state.netId == player.UserId

    ballSimulation.state.guid += 1
    ballSimulation.state.action = Enums.BallActions.Deflect
    ballController:setBallOwner(self.ServerModule, 0)
    ballController:setNetworkOwner(self.ServerModule, player.UserId)

    ballSimulation.state.netId = player.UserId
    playerRecord.hasBall = false

    EmoteService:EndEmote(player)


    ballController:setAttribute("ShootPosition", ballSimulation.state.pos)
    ballController:setCooldown("ClaimCooldown", 0.1)
    Lib.setHiddenCooldown(player, "BallClaimCooldown", 0.1)
end

-- Mechanics
function CharacterService:CreatePlayerHitbox(player: Player, humanoidRootPart: BasePart?, hitboxTemplate: BasePart, hitboxDuration: number, tackleCallback: () -> ())
    if humanoidRootPart == nil then
        warn("[Lib] createHitbox: HumanoidRootPart doesn't exist!")
        return
    end


    local hitbox: BasePart = hitboxTemplate:Clone()
    if not player:IsA("Player") then
        local function lerp(a, b, t)
            return a + (b - a) * t
        end
        local savedShots = player:GetAttribute("SavedShots")
        if savedShots <= 1 then
            hitbox.Size *= 4
        else
            hitbox.Size *= lerp(2.5, 0.8, math.clamp((savedShots-1)*1/3, 0, 1))
        end
        if savedShots >= 3 or not player:GetAttribute("ShouldDoActions") then -- don't do dive hitboxes if this is true
            return
        end
    end
    hitbox:PivotTo(humanoidRootPart.CFrame)
    Constraints.weldConstraint(hitbox, humanoidRootPart)

    if RunService:IsServer() then
        hitbox.Color = Color3.fromRGB(0, 0, 255)
        hitbox:AddTag("ServerHitbox")
    else
        hitbox.Color = Color3.fromRGB(255, 0, 0)
    end

    if not player:IsA("Player") then
        hitbox.CollisionGroup = "Goalkeeper"
        hitbox.Parent = player
    else
        hitbox.Transparency = 0
        hitbox.Parent = self.ServerModule.worldRoot
    end
    game.Debris:AddItem(hitbox, hitboxDuration)


    if tackleCallback == nil then
        return
    end
    
    local function checkTackle(part: BasePart)
        if player:IsA("Player") then
            local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
            if playerRecord == nil or playerRecord.hasBall then
                hitbox:Destroy()
                return
            end
        end

        local ownerId = self.ServerModule.ballRecord.ballController.simulation.state.ownerId
        if part:HasTag("ServerBallHitbox") then
            if player:IsA("Player") then
                if ownerId == player.UserId then
                    return
                end
            elseif ownerId == player then
                return
            end
            hitbox:Destroy()
            if ownerId ~= 0 then
                tackleCallback()
            else
                self:ClaimBall(player, true)
            end
            return
        end

        local tackleUserId = part:GetAttribute("player")
        if tackleUserId == nil then
            return
        end
        if ownerId ~= tackleUserId then
            return
        end

        tackleCallback()
    end

    local hitboxTrove = Trove.new()
    hitboxTrove:AttachToInstance(hitbox)

    local filter = {CollectionService:GetTagged("ServerBallHitbox")}

    local userId = humanoidRootPart:GetAttribute("player") -- Chickynoid compatibility
    for _, otherPlayerHitbox in pairs(CollectionService:GetTagged("ServerCharacterHitbox")) do
        local otherPlayerUserId = otherPlayerHitbox:GetAttribute("player")
        if otherPlayerUserId == userId then continue end
        local otherPlayer = Players:GetPlayerByUserId(otherPlayerUserId)
        if not Lib.playerInGame(otherPlayer) then continue end
        
        table.insert(filter, otherPlayerHitbox)
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = filter

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Include
    overlapParams.FilterDescendantsInstances = filter

    local simulationEvent = RunService:IsServer() and RunService.Heartbeat or RunService.RenderStepped
    local lastCFrame = hitbox.CFrame
    hitboxTrove:Connect(simulationEvent, function()
        local currentCFrame = hitbox.CFrame
        for _, part in pairs(workspace:GetPartBoundsInBox(currentCFrame, hitbox.Size, overlapParams)) do
            checkTackle(part)
        end
        
        if lastCFrame.Position == currentCFrame.Position then
            return
        end
        local raycastResult = workspace:Blockcast(lastCFrame, hitbox.Size, lastCFrame.Position - currentCFrame.Position, raycastParams)
        lastCFrame = currentCFrame
        if raycastResult == nil then
            return
        end
        checkTackle(raycastResult.Instance)
    end)
end

function CharacterService:DiveStart(player: Player, diveAnimName: string)
    if player:GetAttribute("Position") ~= "Goalkeeper" then
        return
    end
    if type(diveAnimName) ~= "string" then
        return
    end
    local hitboxTemplate = assets.Hitboxes.Dive:FindFirstChild(diveAnimName)
    if hitboxTemplate == nil then
        return
    end

    if player:IsA("Player") then
        if not Lib.playerInGameOrPaused(player) or Lib.playerIsStunned(player) then
            return
        end

        local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
        if playerRecord == nil then
            return
        end
    
        local chickynoid = playerRecord.chickynoid
        if chickynoid == nil or chickynoid.hitBox == nil then
            return
        end

        Lib.setHiddenCooldown(player, "DiveEnd", GameInfo.DIVE_DURATION)
        Lib.setHiddenAttribute(player, "CanSteal", true)
    
        Lib.setHiddenAttribute(player, "ServerDiveHitbox", diveAnimName)
        self:CreatePlayerHitbox(player, chickynoid.hitBox, hitboxTemplate, GameInfo.DIVE_DURATION, function()
            self:StealBall(player)
        end)
    else
        if Lib.isOnHiddenCooldown(player, "DiveCooldown") then
            return
        end

        local goalkeeper: Model = player
        if goalkeeper:GetAttribute("HasBall") then
            return
        end

        local humanoidRootPart = goalkeeper:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart == nil then
            return
        end
    
        Lib.setHiddenCooldown(player, "DiveEnd", GameInfo.DIVE_DURATION+0.3)
        Lib.setHiddenCooldown(player, "DiveCooldown", GameInfo.DIVE_COOLDOWN-0.3)
        Lib.setHiddenAttribute(player, "CanSteal", true)
    
    
        self:CreatePlayerHitbox(goalkeeper, goalkeeper.HumanoidRootPart, hitboxTemplate, GameInfo.DIVE_DURATION, function()
            self:AIGoalkeeperStealBall(goalkeeper)
        end)
    end
end

function CharacterService:TackleStart(player: Player)
    if player:GetAttribute("Position") == "Goalkeeper" then
        return
    end
    if not Lib.playerInGameOrPaused(player) or Lib.playerIsStunned(player) then
        return
    end


    local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil then
        return
    end

    local chickynoid = playerRecord.chickynoid
    if chickynoid == nil or chickynoid.hitBox == nil then
        return
    end

    Lib.setHiddenCooldown(player, "TackleEnd", GameInfo.TACKLE_DURATION+0.3)
    Lib.setHiddenAttribute(player, "CanSteal", true)
    Lib.setHiddenAttribute(player, "CanStealClient", true)
    Lib.setHiddenAttribute(player, "TackleStart", workspace:GetServerTimeNow())

    self:CreatePlayerHitbox(player, chickynoid.hitBox, assets.Hitboxes.Tackle, GameInfo.TACKLE_DURATION, function()
        self:StealBall(player)
    end)
end

function CharacterService:Skill(player: Player)
    if player:GetAttribute("Position") == "Goalkeeper" then
        return
    end
    if not Lib.playerInGame(player) or Lib.playerIsStunned(player) then
        return
    end


    local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil then
        return
    end
    if not playerRecord.hasBall then
        return
    end

    if Lib.isOnHiddenCooldown(player, "SkillCooldown") then
        return
    end

    local chickynoid = playerRecord.chickynoid
    if chickynoid == nil then
        return
    end
    local simulation = chickynoid.simulation

    Lib.setHiddenCooldown(player, "SkillEnd", GameInfo.SKILL_DURATION)
    Lib.setHiddenCooldown(player, "SkillCooldown", privateServerInfo:GetAttribute("SkillCD") - 0.3)

    simulation.characterData:PlayAnimation("Skill", Enums.AnimChannel.Channel1, true)
end

-- Animations
function CharacterService:RequestBall(player: Player)
    if not Lib.playerInGameOrPaused(player) then
        return
    end

    local playerRecord = self.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil then
        return
    end
    if playerRecord.hasBall then
        return
    end

    local chickynoid = playerRecord.chickynoid
    if chickynoid == nil then
        return
    end
    local simulation = chickynoid.simulation

    if Lib.isOnHiddenCooldown(player, "RequestBallCooldown") then
        return
    end
    Lib.setHiddenCooldown(player, "RequestBallCooldown", 1.5)

    simulation.characterData:PlayAnimation("RequestBall", Enums.AnimChannel.Channel1, true)
end


-- Client Events

-- Animations
function CharacterService.Client:RequestBall(...)
    self.Server:RequestBall(...)
end

return CharacterService