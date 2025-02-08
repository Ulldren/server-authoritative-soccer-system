local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")

local Lib = require(ReplicatedStorage.Lib)

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterService
local EmoteService

local GameInfo = require(ReplicatedStorage.Data.GameInfo)

local Trove = require(ReplicatedStorage.Modules.Trove)
local TeamInfo = require(ReplicatedStorage.Data.TeamInfo)

local trove = Trove.new()

local MINIMUM_PLAYERS = 1

local INTERMISSION_TIME = 10
local TEAM_SELECT_TIME = 15
local GOAL_FOCUS_TIME = 10
local CELEBRATION_TIME = 10

local teamNames = {}
for teamName in pairs(TeamInfo) do
    table.insert(teamNames, teamName)
end

local serverAssets = ServerStorage.Assets
local kits: Folder = serverAssets.Kits


local privateServerInfo = ReplicatedStorage.PrivateServerInfo
local serverInfo = ReplicatedStorage.ServerInfo
if RunService:IsStudio() then
    MINIMUM_PLAYERS = 1

    INTERMISSION_TIME = 0
    VOTING_TIME = 0
    TEAM_SELECT_TIME = 0
    PRE_GAME_TIME = 0
end

local homeTeam, awayTeam = Teams.Home, Teams.Away


local function doSomethingWithPlayersInGame(callback)
    for _, player in pairs(Players:GetPlayers()) do
        if player.Team ~= homeTeam and player.Team ~= awayTeam then continue end
        callback(player)
    end
end

local function getEligiblePlayers()
    local eligiblePlayers = {}
    for _, player in pairs(Players:GetPlayers()) do
        -- if not player:GetAttribute("Loaded") then continue end
        table.insert(eligiblePlayers, player)
    end
    return eligiblePlayers
end

local function getUniqueNames()
    local clonedList = table.clone(teamNames)
    local homeIndex = math.random(1, #clonedList)
    local homeName = clonedList[homeIndex]
    table.remove(clonedList, homeIndex)

    local homeInfo = TeamInfo[homeName]
    while #clonedList > 0 do
        local awayIndex = math.random(1, #clonedList)
        local awayName = clonedList[awayIndex]
        local awayInfo = TeamInfo[awayName]
        if true then
            return homeName, awayName
        end
    end
    return
end

local function clearRole(player: Player)
    local roleObjects: {ObjectValue} = serverInfo:GetDescendants()
    for _, roleObject in pairs(roleObjects) do
        if not roleObject:IsA("ObjectValue") then continue end
        if roleObject.Value == player then
            roleObject.Value = nil
            break
        end
    end
end


local GameService = {
    Name = "GameService",
    Client = {
        InstantTeleport = Knit.CreateSignal(),
        PlayerTeleported = Knit.CreateSignal(),
    },
}

function GameService:KnitInit()
    local function changeServerAttribute(attributeName, value)
        serverInfo:SetAttribute(attributeName, serverInfo:GetAttribute(attributeName) + value)
    end
    homeTeam.PlayerAdded:Connect(function()
        changeServerAttribute("HomePlayers", 1)
    end)
    homeTeam.PlayerRemoved:Connect(function(player)
        clearRole(player)
        changeServerAttribute("HomePlayers", -1)
    end)
    awayTeam.PlayerAdded:Connect(function()
        changeServerAttribute("AwayPlayers", 1)
    end)
    awayTeam.PlayerRemoved:Connect(function(player)
        clearRole(player)
        changeServerAttribute("AwayPlayers", -1)
    end)

    local function addRoleObject(roleObject)
        local lastPlayer: Player | nil = nil
        roleObject.Changed:Connect(function(newPlayer)
            if newPlayer == nil and lastPlayer ~= nil then
                lastPlayer:SetAttribute("Position", nil)
            end
            lastPlayer = newPlayer
            if newPlayer ~= nil then
                newPlayer:SetAttribute("Position", roleObject.Name)
            end
        end)
    end
    for _, roleObject in pairs(serverInfo.Home:GetChildren()) do
        addRoleObject(roleObject)
    end
    for _, roleObject in pairs(serverInfo.Away:GetChildren()) do
        addRoleObject(roleObject)
    end
end

function GameService:KnitStart()
    local services = script.Parent
    CharacterService = require(services.CharacterService)
    EmoteService = require(services.EmoteService)

    Players.PlayerRemoving:Connect(function(player)
        self:PlayerRemoving(player)
    end)
    Players.PlayerAdded:Connect(function(player)
        self:PlayerAdded(player)
    end)
    for _, player in pairs(Players:GetPlayers()) do
        task.spawn(function()
            self:PlayerAdded(player)
        end)
    end

    serverInfo:GetAttributeChangedSignal("GameStatus"):Connect(function()
        if serverInfo:GetAttribute("GameStatus") ~= "InProgress" then 
            return 
        end
        for _, player in pairs(Players:GetPlayers()) do
            if player.Team ~= homeTeam and player.Team ~= awayTeam then continue end
            task.spawn(function()
                self:UpdateMoveability(player)
            end)
        end
        for _, goalkeeper in pairs(CollectionService:GetTagged("Goalkeeper")) do
            task.spawn(function()
                self:UpdateMoveability(goalkeeper)
            end)
        end
    end)


    -- Leaderboard Ping
    task.spawn(function()
        while task.wait(1) do
            for _, player in pairs(Players:GetPlayers()) do
                local serverNetworkPing = Lib.getHiddenAttribute(player, "ServerNetworkPing")
                if serverNetworkPing then
                    player:SetAttribute("NetworkPing", serverNetworkPing)
                else
                    player:SetAttribute("NetworkPing", math.clamp(math.floor(player:GetNetworkPing()*2000), 0, 1000))
                end
            end
        end
    end)

    self:WaitForPlayers()
end

function GameService:PlayerAdded(player: Player)
    local function characterAdded()
        local character = player.Character
        character:WaitForChild("HumanoidRootPart")
        if player.Team ~= homeTeam and player.Team ~= awayTeam then
            return
        end
        task.defer(function()
            self:TeleportPlayer(player, nil, true)
        end)
    end

    if player.Character then
        task.spawn(characterAdded)
    end
    player.CharacterAdded:Connect(characterAdded)
end

function GameService:PlayerRemoving(player: Player)
    if player:GetAttribute("Position") ~= "Goalkeeper" then
        return
    end

    if player.Team == homeTeam then
        serverInfo.Home.Goalkeeper.Value = nil
    elseif player.Team == awayTeam then
        serverInfo.Away.Goalkeeper.Value = nil
    end
end

-- Ball Utility
function GameService:ClearAllBalls()
    local function removeBall(ball: BasePart)
        ball:RemoveTag("Ball")
        ball:Destroy()
    end

    local balls = workspace.GameItems.Balls
    for _, ball: BasePart in pairs(balls:GetChildren()) do
        removeBall(ball)
    end
    for _, ball: BasePart in pairs(CollectionService:GetTagged("Ball")) do
        if not ball:IsDescendantOf(workspace) then
            continue
        end
        removeBall(ball)
    end
end

-- Round Handling
function GameService:TeleportPlayer(player: Player | Model, spawnPart: BasePart, ignoreLoadingScreen: boolean, disableShiftLock: boolean)
    if player:IsA("Player") then
        local playerRecord = CharacterService.ServerModule:GetPlayerByUserId(player.UserId)
        if playerRecord == nil then
            return
        end

        if player:IsA("Player") and player:GetAttribute("Position") == nil then
            return
        end
    
        if spawnPart == nil then
            local mapSpawns = workspace.MapItems.TeamSpawns
    
            local team = player.Team
            if player:HasTag("Goalkeeper") then
                team = team.Value
            end
    
            local teamSpawns = mapSpawns:FindFirstChild(team.Name)
            if teamSpawns == nil then
                return warn("Couldn't find team spawn for: " .. team.Name)
            end
            spawnPart = teamSpawns[player:GetAttribute("Position")]
        end
    
        local freezeCFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
        local function teleport()
            player:SetAttribute("Teleported", true)

            local _, yRot, _ = freezeCFrame:ToEulerAnglesYXZ()
            local chickynoid = playerRecord.chickynoid
            if chickynoid then
                chickynoid:SetPosition(freezeCFrame.Position, true)
                chickynoid.simulation:SetAngle(yRot, true)
                chickynoid.simulation.state.tackleCooldown = 0
            else
                playerRecord.position = freezeCFrame.Position
                playerRecord.angle = yRot
            end

            self:UpdateMoveability(player, disableShiftLock)
        end
    
        player:SetAttribute("Teleported", nil)
        if ignoreLoadingScreen then
            self.Client.InstantTeleport:Fire(player, freezeCFrame, disableShiftLock)
            teleport()
        else
            self.Client.PlayerTeleported:Fire(player, freezeCFrame, disableShiftLock)

            player:SetAttribute("Teleported", false)
            local teleportTrove = Trove.new()
            teleportTrove:AttachToInstance(player)
            teleportTrove:Connect(player:GetAttributeChangedSignal("Teleported"), function()
                teleportTrove:Destroy()
            end)
            teleportTrove:Add(task.delay(1, teleport))
        end
    else
        local character = player
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart == nil then
            return
        end

        if spawnPart == nil then
            local mapSpawns = workspace.MapItems.TeamSpawns
    
            local team = player.Team
            if player:HasTag("Goalkeeper") then
                team = team.Value
            end
    
            local teamSpawns = mapSpawns:FindFirstChild(team.Name)
            if teamSpawns == nil then
                warn("Couldn't find team spawn for: " .. team.Name)
                return
            end
            spawnPart = teamSpawns[player:GetAttribute("Position")]
        end
    
        local freezeCFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
        local function teleport()
            if not character:GetAttribute("TeleportedToField") then
                task.delay(1, function()
                    character:SetAttribute("TeleportedToField", true)
                end)
            end
            character:PivotTo(freezeCFrame)
            character:SetAttribute("FreezePosition", freezeCFrame.Position)
            self:UpdateMoveability(player)
        end
        teleport()
    end
end

function GameService:UpdateMoveability(player: Player, completeFreeze: boolean?)
    local gameStatus = serverInfo:GetAttribute("GameStatus")
    local movementDisabled = player.Team.Name ~= "Fans" and (gameStatus == "Paused" or gameStatus == "GameEnded") and not serverInfo:GetAttribute("CanStillMove")
    player:SetAttribute("MovementDisabled", movementDisabled)
    player:SetAttribute("CompleteFreeze", completeFreeze)
end

function GameService:BallPassed(passingPlayer: Player)
    -- player passed
end

function GameService:GoalScored(teamScoredOn: string)
    local ballController = CharacterService.ServerModule.ballRecord.ballController

    local oppositeTeam = teamScoredOn == "Home" and "Away" or "Home"
    local scoreAttribute = oppositeTeam .. "Score"
    serverInfo:SetAttribute(scoreAttribute, serverInfo:GetAttribute(scoreAttribute) + 1)

    serverInfo:SetAttribute("CanStillMove", true)
    serverInfo:SetAttribute("GameStatus", "Paused")


    local ballState = ballController.simulation.state
    local playerWhoScored: Player = Players:GetPlayerByUserId(ballState.netId)
    task.delay(0.5, function()
        serverInfo.SpectateOverride.Value = playerWhoScored
    end)

    if ballController:getAttribute("Team") == nil then
        ballController:setAttribute("Team", oppositeTeam)
    end
    local nameWhoScored: string = ballController:getAttribute("OwnerName") or serverInfo:GetAttribute(ballController:getAttribute("Team") .. "Name")

    local scoredOnOwnGoal = ballController:getAttribute("Team") == teamScoredOn

    local assistName: string = nil
    local assistPlayer: Player = ballController:getAttribute("AssistPlayer")
    local assistTime: number = ballController:getAttribute("AssistTime")
    if not scoredOnOwnGoal
    and assistPlayer ~= nil and assistPlayer ~= playerWhoScored and assistPlayer.Team and assistPlayer.Team.Name == ballController:getAttribute("Team")
    and assistTime and os.clock() - assistTime < GameInfo.MAX_ASSIST_TIME then
        assistName = assistPlayer.DisplayName
    end

    task.spawn(function()
        if playerWhoScored == nil or playerWhoScored:HasTag("Goalkeeper") then return end

        if scoredOnOwnGoal then
            -- playerWhoScored scored an own goal
            return
        end

        -- scored goal
    end)
    task.spawn(function()
        if assistPlayer == nil or scoredOnOwnGoal then return end

        -- assistPlayer assisted
    end)

    
    task.wait(GOAL_FOCUS_TIME)

    serverInfo:SetAttribute("CanStillMove", false)
    if serverInfo:GetAttribute("RoundTime") == 0 then
        serverInfo:SetAttribute("GameStatus", "GameEnded")
        task.wait(1)
        return
    end

    self:StartNewRound(teamScoredOn)

    doSomethingWithPlayersInGame(function(player)
        task.spawn(function()
            self:TeleportPlayer(player)
        end)
    end)
    for _, goalkeeper in pairs(CollectionService:GetTagged("Goalkeeper")) do
        task.spawn(function()
            self:TeleportPlayer(goalkeeper)
        end)
    end

    serverInfo.SpectateOverride.Value = nil
    task.wait(3)

    serverInfo:SetAttribute("GameStatus", "InProgress")
end

function GameService:StartNewRound(teamAdvantage: string)
    workspace.GameItems.Balls:ClearAllChildren()


    local ballSpawn = workspace.MapItems.BallSpawn
    local function createBall()
        local ballRecord = CharacterService.ServerModule.ballRecord
        ballRecord:Spawn(ballSpawn.CFrame.Position)
    end
    createBall()
end

-- Round Loop
function GameService:WaitForPlayers()
    trove:Clean()

    self:ClearAllBalls()

    for _, roleObject: ObjectValue in pairs(serverInfo.Home:GetChildren()) do
        roleObject.Value = nil
    end
    for _, roleObject: ObjectValue in pairs(serverInfo.Away:GetChildren()) do
        roleObject.Value = nil
    end

    serverInfo:SetAttribute("RoundTime", privateServerInfo:GetAttribute("MatchTime") * 60)
    serverInfo:SetAttribute("GameStatus", "Waiting")
    for _, player in pairs(Players:GetPlayers()) do
        self:UpdateMoveability(player)
    end

    self:StartIntermission()
end

function GameService:StartIntermission()
    serverInfo:SetAttribute("StatusTime", INTERMISSION_TIME)
    serverInfo:SetAttribute("GameStatus", "Intermission")

    repeat
        local deltaTime = task.wait(0.1)
        local newTime = math.max(0, serverInfo:GetAttribute("StatusTime") - deltaTime)
        serverInfo:SetAttribute("StatusTime", newTime)
        while #getEligiblePlayers() < MINIMUM_PLAYERS do
            self:WaitForPlayers()
            return
        end
    until newTime == 0

    self:StartTeamSelect()
end

function GameService:StartTeamSelect()
    self:MakeNewTeams()

    serverInfo:SetAttribute("StatusTime", TEAM_SELECT_TIME)
    serverInfo:SetAttribute("GameStatus", "Team Selection")
    repeat
        local deltaTime = task.wait(0.1)
        local newTime = math.max(0, serverInfo:GetAttribute("StatusTime") - deltaTime)
        serverInfo:SetAttribute("StatusTime", newTime)
    until newTime == 0

    self:StartGame()
end

function GameService:StartGame()
    serverInfo:SetAttribute("GameStatus", "Paused")
    self:StartNewRound()

    doSomethingWithPlayersInGame(function(player)
        task.spawn(function()
            self:TeleportPlayer(player)
        end)
    end)

    task.wait(2)

    serverInfo:SetAttribute("GameStatus", "InProgress")
    self:StartGameCountdown()
end

function GameService:StartGameCountdown()
    repeat
        local deltaTime = task.wait(0.1)

        local updatedTime = serverInfo:GetAttribute("RoundTime")
        if serverInfo:GetAttribute("GameStatus") == "InProgress" then
            updatedTime = math.max(0, updatedTime - deltaTime)
            serverInfo:SetAttribute("RoundTime", updatedTime)
        end
    until updatedTime == 0

    
    local function isTied()
        return serverInfo:GetAttribute("HomeScore") == serverInfo:GetAttribute("AwayScore")
    end
    if isTied() then
        -- do tied stuff idk
    end

    -- If it was a golden goal, wait until the score cutscene ends
    while serverInfo:GetAttribute("GameStatus") ~= "InProgress" and serverInfo:GetAttribute("GameStatus") ~= "GameEnded" do
        task.wait(0.1)
    end

    self:EndGame()
end

function GameService:EndGame()
    serverInfo:SetAttribute("CanStillMove", true)
    serverInfo:SetAttribute("GameStatus", "GameEnded")

    task.wait(3.5)
    serverInfo:SetAttribute("CanStillMove", false)

    self:ClearAllBalls()

    local teamWhoWon = serverInfo:GetAttribute("HomeScore") > serverInfo:GetAttribute("AwayScore") and "Home" or "Away"
    local teamWhoLost = serverInfo:GetAttribute("HomeScore") > serverInfo:GetAttribute("AwayScore") and "Away" or "Home"


    task.wait(0.5)
    doSomethingWithPlayersInGame(function(player: Player)
        local playerRecord = CharacterService.ServerModule:GetPlayerByUserId(player.UserId)
        if playerRecord == nil then
            return
        end
        playerRecord:SetCharacterMod("FieldChickynoid")

        if player.Team and player.Team.Name ~= teamWhoWon then 
            return 
        end
    end)

    
    doSomethingWithPlayersInGame(function(player: Player)
        -- send data 
    end)

    doSomethingWithPlayersInGame(function(player: Player)
        if player.Team and player.Team.Name ~= teamWhoWon then
            return
        end

        --- player won
    end)

    local realTeamName = serverInfo:GetAttribute(teamWhoWon .. "Name")

    local realLosingTeamName = serverInfo:GetAttribute(teamWhoLost .. "Name")

    task.wait(CELEBRATION_TIME)
    doSomethingWithPlayersInGame(function(player: Player)
        -- player.Team = Teams.Fans
        -- task.spawn(function()
        --     player:LoadCharacter()
        -- end)
        self:ResetBackToLobby(player)
    end)
    task.wait(1.5)
    self:WaitForPlayers()
end

-- Teams
function GameService:UpdateKit(player: Player)
    if player.Team ~= homeTeam and player.Team ~= awayTeam then return end
    local teamName = player.Team == homeTeam and serverInfo:GetAttribute("HomeName") or serverInfo:GetAttribute("AwayName")
    local kitClothing = kits:FindFirstChild(teamName)


    local playerRecord = CharacterService.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil then
        return warn("[GameService] Player record doesn't exist! | :UpdateKit()")
    end

    playerRecord.avatarDescription = {
        kitClothing.Shirt.ShirtTemplate, 
        kitClothing.Pants.PantsTemplate,
        player:GetAttribute("KitName") or player.DisplayName,
        player:GetAttribute("KitNumber") or math.random(1, 99),
        player.Team:GetAttribute("TeamColor"),
    }
    playerRecord:SetCharacterMod(if player:GetAttribute("Position") == "Goalkeeper" then "GoalkeeperChickynoid" else "FieldChickynoid")
end

function GameService:MakeNewTeams()
    local homeName, awayName = getUniqueNames()
    serverInfo:SetAttribute("HomeName", homeName)
    serverInfo:SetAttribute("AwayName", awayName)
    serverInfo:SetAttribute("HomeScore", 0)
    serverInfo:SetAttribute("AwayScore", 0)
    homeTeam:SetAttribute("TeamName", homeName)
    awayTeam:SetAttribute("TeamName", awayName)

    local homeColor = TeamInfo[homeName].MainColor
    local awayColor = TeamInfo[awayName].MainColor
    homeTeam:SetAttribute("TeamColor", homeColor)
    awayTeam:SetAttribute("TeamColor", awayColor)
    homeTeam.TeamColor = BrickColor.new(homeColor)
    awayTeam.TeamColor = BrickColor.new(awayColor)
    if homeTeam.TeamColor == awayTeam.TeamColor then
        warn("Same team colors: ", homeName, awayName)
    end 
end

function GameService:SelectTeam(player: Player, teamName: string, role: string)
    -- if not player:GetAttribute("Loaded") then
    --     return
    -- end

    local playerRecord = CharacterService.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil then
        warn("[GameService] Player record doesn't exist! | :SelectTeam()")
        return
    end


    if player.Team.Name == "Home" or player.Team.Name == "Away" then
        teamName = player.Team.Name
    end
    if type(teamName) ~= "string" or (teamName ~= "Home" and teamName ~= "Away") then
        return
    end
    local gameStatus = serverInfo:GetAttribute("GameStatus")
    if gameStatus ~= "InProgress" and gameStatus ~= "Team Selection" and gameStatus ~= "Paused" and gameStatus ~= "Practice" then
        return
    end

    if Lib.isOnHiddenCooldown(player, "TeamSelectCooldown") then
        return
    end


    local homePlayers, awayPlayers = serverInfo:GetAttribute("HomePlayers"), serverInfo:GetAttribute("AwayPlayers")
    if player:GetAttribute("Position") == "Goalkeeper" then
        if (teamName == "Home" and homePlayers - 1 > awayPlayers) or (teamName == "Away" and awayPlayers - 1 > homePlayers) then
            -- team has too many players
            return
        end
    elseif not RunService:IsStudio() then
        if (teamName == "Home" and homePlayers > awayPlayers) or (teamName == "Away" and awayPlayers > homePlayers) then
            -- team has too many players
            return
        end
    end

    if type(role) ~= "string" then
        return
    end
    local roles = serverInfo[teamName]
    local roleObject: ObjectValue = roles:FindFirstChild(role)
    if roleObject == nil or roleObject.Value ~= nil then
        -- position already taken
        return
    end

    Lib.removeHiddenCooldown(player, "BallClaimCooldown")
    Lib.setHiddenCooldown(player, "TeamSelectCooldown", 1)
    local oldPosition = player:GetAttribute("Position")
    if oldPosition == "Goalkeeper" then
        if Lib.isOnCooldown(player, "SwitchOnFieldCD") then
            -- on cd
            return
        end

        Lib.setCooldown(player, "GoalkeeperCD", 10)
        task.spawn(function()
            CharacterService:ResetBall(player, true)
        end)
        clearRole(player)
        roleObject.Value = player

        self:UpdateKit(player)
        if gameStatus == "InProgress" or gameStatus == "Paused" or gameStatus == "Practice" then
            self:TeleportPlayer(player, nil, oldPosition ~= nil)
            EmoteService:EndEmote(player)
        end
    else
        if player.Team.Name == "Home" or player.Team.Name == "Away" then
            return
        end
        local team = Teams:FindFirstChild(teamName)
        if team == nil then
            return
        end

        roleObject.Value = player
        player.Team = team
    
    
        self:UpdateKit(player)
        if gameStatus == "InProgress" or gameStatus == "Paused" or gameStatus == "Practice" then
            self:TeleportPlayer(player, nil, oldPosition ~= nil)
            EmoteService:EndEmote(player)
        end
    end
end

function GameService:ResetBackToLobby(player: Player)
    if player.Team ~= homeTeam and player.Team ~= awayTeam then
        return
    end

    local playerRecord = CharacterService.ServerModule:GetPlayerByUserId(player.UserId)
    local chickynoid = playerRecord.chickynoid
    if chickynoid == nil then
        return
    end

    local list = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") and obj.Enabled == true then
            table.insert(list, obj)
        end
    end

    if #list > 0 then
        task.delay(0.5, function()
            if player == nil or not player:IsDescendantOf(game) then
                return
            end
            playerRecord.avatarDescription = nil
            playerRecord:SetCharacterMod("HumanoidChickynoid")
        end)

        local spawn = list[math.random(1, #list)]
        self:TeleportPlayer(player, spawn)
    end

    player.Team = Teams.Fans
end

-- Goalkeeper
function GameService:BecomeGoalkeeper(player: Player)
    if not Lib.playerInGame(player) then
        return
    end

    local playerRecord = CharacterService.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil then
        warn("[GameService] Player record doesn't exist! | :BecomeGoalkeeper()")
        return
    end


    local roles = serverInfo[player.Team.Name]
    local roleObject: ObjectValue = roles.Goalkeeper
    if roleObject.Value ~= nil then
        return
    end

    local gameStatus = serverInfo:GetAttribute("GameStatus")
    if gameStatus ~= "InProgress" and gameStatus ~= "Team Selection" and gameStatus ~= "Paused" and gameStatus ~= "Practice" then
        return
    end

    if Lib.isOnCooldown(player, "GoalkeeperCD") then
        -- on cd
        return
    end

    Lib.setCooldown(player, "SwitchOnFieldCD", 10)
    task.spawn(function()
        CharacterService:ResetBall(player, true)
    end)
    clearRole(player)
    roleObject.Value = player


    self:UpdateKit(player)
    self:TeleportPlayer(player, nil, true)
end


-- Client Events

-- Goalkeeper
function GameService.Client:BecomeGoalkeeper(...)
    self.Server:BecomeGoalkeeper(...)
end

-- Teams/Leaving
function GameService.Client:ResetBackToLobby(...)
    self.Server:ResetBackToLobby(...)
end

function GameService.Client:SelectTeam(...)
    self.Server:SelectTeam(...)
end

return GameService