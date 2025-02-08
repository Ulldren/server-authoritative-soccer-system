local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local privateServerInfo: Configuration = ReplicatedStorage.PrivateServerInfo
local serverInfo: Configuration = ReplicatedStorage.ServerInfo

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterService

local GameInfo = require(ReplicatedStorage.Data.GameInfo)
local Keybinds = require(ReplicatedStorage.Data.Keybinds)

local Cooldown = require(ReplicatedStorage.Modules.Cooldown)
local Lib = require(ReplicatedStorage.Lib)
local Signal = require(ReplicatedStorage.Modules.Signal)
local SmoothShiftLock = require(ReplicatedStorage.Modules.SmoothShiftLock)
local spr = require(ReplicatedStorage.Modules.spr)
local Trove = require(ReplicatedStorage.Modules.Trove)

local trove = Trove.new()
local staminaDrainTrove = trove:Extend()
local shotTrove = trove:Extend()
local keybindTrove = trove:Extend()
local characterTrove = trove:Extend()
local gameTrove = trove:Extend()

local shootCooldown = Cooldown.new(0.1)
local skillCooldown = Cooldown.new(privateServerInfo:GetAttribute("SkillCD"))
local requestBallCooldown = Cooldown.new(2)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer.PlayerGui
local currentCamera = workspace.CurrentCamera
local realBallObject: ObjectValue = localPlayer:WaitForChild("Ball")

local action = nil

local chargingShot = false

localPlayer:SetAttribute("CurveFactor", 0)
local buttonBasedCurving = false


local shotAttachment0 = Instance.new("Attachment")
shotAttachment0.Name = "ShotAttachment0"
shotAttachment0.Parent = workspace.Terrain
local shotAttachment1 = Instance.new("Attachment")
shotAttachment1.Name = "ShotAttachment1"
shotAttachment1.Parent = workspace.Terrain


local function hasBall(): boolean
    return realBallObject.Value ~= nil
end

local function rotateVectorAround(v, amount, axis)
    return CFrame.fromAxisAngle(axis, amount):VectorToWorldSpace(v)
end

local function getClosestAngle(ang, ref)
	return (ang - ref + math.pi)%(2 * math.pi) - math.pi + ref
end

local function actionAvailable(simulation: {state: {tackle: number, dive: number}}): boolean | nil
    return not (
        simulation.state.tackle > 0
        or simulation.state.dive > 0
    )
end


local CharacterController = {
    Name = "CharacterController",
}
CharacterController.shiftLockEnabled = true

function CharacterController:KnitInit()
    local Packages = ReplicatedFirst.Chickynoid
    self.ClientModule = require(Packages.Client.ClientModule)
    self.ClientMods = require(Packages.Client.ClientMods)

    self.ClientMods:RegisterMods("clientmods", Packages.Examples.ClientMods)
    self.ClientMods:RegisterMods("characters", Packages.Examples.Characters)
    self.ClientMods:RegisterMods("balls", Packages.Examples.Balls)
     
    self.ClientModule:Setup()


    local TextChatService = game:GetService("TextChatService")
    TextChatService.OnBubbleAdded = function(message: TextChatMessage, adornee: Instance)
        -- Check if the chat message has a TextSource (sender) associated with it
        if message.TextSource then
            -- Create a new BubbleChatMessageProperties instance to customize the chat bubble
            local bubbleProperties = Instance.new("BubbleChatMessageProperties")
    
            -- Get the user who sent the chat message based on their UserId
            local player = Players:GetPlayerByUserId(message.TextSource.UserId)
            if player ~= localPlayer and adornee == nil then
                local characterData = CharacterController.ClientModule.characters[player.UserId]
                if characterData == nil then
                    return
                end
                local characterModel = characterData.characterModel
                if characterData == nil then
                    return
                end
                local character = characterModel.model
                if character == nil or not character:IsDescendantOf(workspace) then
                    return
                end
                TextChatService:DisplayBubble(character.Head, message.Text)
            end
    
            return bubbleProperties
        end
        return
    end

    task.spawn(function()
        local chickynoid = self.ClientModule:GetClientChickynoid()
        while chickynoid == nil do
            task.wait(0.5)
            chickynoid = self.ClientModule:GetClientChickynoid()
        end

        local characterModel = self.ClientModule.characterModel
        while characterModel == nil do
            task.wait(0.5)
            characterModel = self.ClientModule.characterModel
        end

        while chickynoid.mispredict.Magnitude ~= 0 do
            task.wait(0.5)
        end

        local loadingGui: ScreenGui = playerGui.LoadingScreen
        loadingGui:SetAttribute("Chickynoid", true)
    end)
    

    localPlayer:SetAttribute("Stamina", GameInfo.MAX_STAMINA)
    localPlayer:SetAttribute("MaxStamina", GameInfo.MAX_STAMINA)
    localPlayer:SetAttribute("ShotPower", 0)

    localPlayer:SetAttribute("Tackle", false)


    RunService.Heartbeat:Connect(function(deltaTime)
        if buttonBasedCurving then
            return
        end
        if localPlayer:GetAttribute("AdjustedCurve") then
            return
        end

        deltaTime *= GameInfo.CURVE_FACTOR_RECEDE_MULTIPLIER
        local curveFactor = localPlayer:GetAttribute("CurveFactor")
        local sign = math.sign(curveFactor)
        if sign == -1 then
            localPlayer:SetAttribute("CurveFactor", curveFactor - math.max(curveFactor, sign*deltaTime))
        elseif sign == 1 then
            localPlayer:SetAttribute("CurveFactor", curveFactor - math.min(curveFactor, sign*deltaTime))
        end
    end)


    CollectionService:GetInstanceAddedSignal("Ragdoll"):Connect(function(character)
        if character ~= localPlayer.Character then return end
        self:EndShot()
    end)
end

function CharacterController:KnitStart()
    local controllers = script.Parent
    UIController = require(controllers.UIController)

    CharacterService = Knit.GetService("CharacterService")

    local lastPosition: string | nil = localPlayer:GetAttribute("Position")
    self:PositionChanged()
    localPlayer:GetAttributeChangedSignal("Position"):Connect(function()
        local currentPosition = localPlayer:GetAttribute("Position")
        if lastPosition ~= nil and currentPosition ~= nil then
            lastPosition = currentPosition
            return
        end
        lastPosition = currentPosition
        self:PositionChanged()
    end)

    -- Keybinds
    SmoothShiftLock:Init()

    ContextActionService:BindAction("ShiftLock", function(_, inputState)
        self:CallKeybindFunction("ShiftLock", inputState)
    end, false, Keybinds.PC.ShiftLock, Keybinds.Console.ShiftLock)
end

function CharacterController:PositionChanged()
    if localPlayer:GetAttribute("Position") == nil then
        localPlayer:SetAttribute("ShiftLock", false)
        localPlayer:SetAttribute("JumpDisabled", false)

        self:StopSprint()
        self:UnbindKeybinds(true)
        trove:Clean()
        return
    end


    local characterAddedTrove = gameTrove:Extend()
    local function runCharacterAdded()
        local character = localPlayer.Character
        characterAddedTrove:Clean()
        characterAddedTrove:Add(task.spawn(function()
            self:CharacterAdded(character)
        end))
        characterAddedTrove:Connect(character:GetAttributeChangedSignal("Goalkeeper"), runCharacterAdded)
    end
    runCharacterAdded()

    gameTrove:Connect(serverInfo:GetAttributeChangedSignal("GameStatus"), function()
        local gameStatus = serverInfo:GetAttribute("GameStatus")
        if gameStatus ~= "GameEnded" then
            return
        end
        shotTrove:Clean()
        localPlayer:SetAttribute("ShotPower", 0)
        localPlayer:SetAttribute("LeanAngle", CFrame.new())
        self:StopSprint()
        self:EndShot()
    end)
end

function CharacterController:CharacterAdded(character)
    spr.target(currentCamera, 1, 5, {FieldOfView = 70})

    characterTrove:Clean()
    characterTrove:Add(function()
        localPlayer:SetAttribute("ShotPower", 0)
    end)

    keybindTrove:Clean()
    self:UnbindKeybinds()


    local shouldRun = true
    characterTrove:Add(function()
        shouldRun = false
    end)

    self:EndShot()
    while not Lib.playerInGameOrPaused() do
        task.wait()
        if not shouldRun then
            return
        end
    end

    self:SetKeybinds()
    self:ToggleShiftLock(self.shiftLockEnabled)
    

    characterTrove:Connect(RunService.Heartbeat, function()
        self.ClientModule.playerAction = action
    end)


    localPlayer:SetAttribute("ShotPower", 0)
    localPlayer:SetAttribute("JumpDisabled", false)

    characterTrove:Connect(localPlayer:GetAttributeChangedSignal("DisableChargeShot"), function()
        if not localPlayer:GetAttribute("DisableChargeShot") then
            return
        end
        self:EndShot()
    end)
end

-- Keybinds
local function bindAction(actionName: string)

end

local function unbindAction(actionName: string)
    ContextActionService:UnbindAction(actionName) 
end

function CharacterController:GetCurrentCommand()
    local cmd = {}
    cmd.x = 0
    cmd.y = 0
    cmd.z = 0
 
    local modules = self.ClientMods:GetMods("clientmods")

    for key, mod in modules do
        if (mod.GenerateCommand) then
            cmd = mod:GenerateCommand(cmd, nil, nil, self.ClientModule)
        end
    end
    return cmd
end

CharacterController.keybindFunctions = {
    ["Shoot"] = function(self, inputState)
        if not (shootCooldown:IsFinished() and not Lib.playerIsStunned()) then
            return
        end

        if inputState == Enum.UserInputState.Begin then
            self:BeginShot()
        elseif inputState == Enum.UserInputState.End then
            self:ShootBall("Shoot")
        end
    end,

    ["Dive"] = function(self: typeof(CharacterController), inputState)
        if Lib.playerIsStunned() then return end

        local chickynoid = self.ClientModule:GetClientChickynoid()
        if chickynoid == nil then
            return
        end
        local simulation = chickynoid.simulation

        if inputState == Enum.UserInputState.Begin and actionAvailable(simulation) then
            local cmd = self:GetCurrentCommand()

            local velocity = Vector3.new(0, 0, 0)
            if (cmd.x ~= 0 or cmd.z ~= 0) then
                velocity = Vector3.new(cmd.x, 0, cmd.z).Unit
            end
        
            local shiftLock = cmd.shiftLock
            local diveAnim: number
            if velocity.Magnitude > 0 and shiftLock then
                local movingForward, movingBackward, movingRight, movingLeft
        
                local cameraCFrame = CFrame.lookAt(Vector3.zero, cmd.fa)
                local _, y, _ = cameraCFrame:ToEulerAnglesYXZ()
    
                local movementDirection = rotateVectorAround(velocity, -y, Vector3.yAxis)
                
                -- Add 0.01 to Z to prioritize front dive if diagonal
                if math.abs(movementDirection.X) >= math.abs(movementDirection.Z) + 0.01
                --math.abs(movementDirection.X) >= math.abs(movementDirection.Z) + 0.05 
                then
                    movingRight = movementDirection.X >= 0
                    movingLeft = movementDirection.X < 0
                else
                    movingBackward = movementDirection.Z >= 0
                    movingForward = movementDirection.Z < 0
                end
        
                if movingForward or movingBackward then
                    diveAnim = 1
                elseif movingBackward then
                    return
                elseif movingRight then
                    diveAnim = 2
                    velocity = (cameraCFrame.RightVector * Vector3.new(1, 0, 1)).Unit
                elseif movingLeft then
                    diveAnim = 0
                    velocity = (-cameraCFrame.RightVector * Vector3.new(1, 0, 1)).Unit
                end
            elseif velocity.Magnitude > 0 and not shiftLock then
                diveAnim = 1
            else
                diveAnim = 1
        
                local angle = simulation.state.angle
                local characterDirection = -Vector3.new(math.sin(angle), 0, math.cos(angle))
                velocity = characterDirection
            end

            localPlayer:SetAttribute("CMDDiveDir", velocity)
            localPlayer:SetAttribute("CMDDiveAnim", diveAnim)
        else
            localPlayer:SetAttribute("CMDDiveDir", nil)
            localPlayer:SetAttribute("CMDDiveAnim", nil)
        end
    end,
    ["SlideTackle"] = function(self, inputState)
        if Lib.playerIsStunned() then return end

        local chickynoid = self.ClientModule:GetClientChickynoid()
        if chickynoid == nil then
            return
        end
        local simulation = chickynoid.simulation

        if inputState == Enum.UserInputState.Begin and actionAvailable(simulation) then
            local cmd = self:GetCurrentCommand()

            local tackleDir = Vector3.new(1, 0, 0)
            if cmd.shiftLock == 0 and (cmd.x ~= 0 or cmd.z ~= 0) then
                tackleDir = Vector3.new(cmd.x, 0, cmd.z).Unit
            elseif cmd.shiftLock == 1 and cmd.fa and typeof(cmd.fa) == "Vector3" then
                local vec = cmd.fa * Vector3.new(1, 0, 1)
                if vec.Magnitude > 0 then
                    tackleDir = vec.Unit
                end
            else
                local angle = simulation.state.angle
                local characterDirection = -Vector3.new(math.sin(angle), 0, math.cos(angle))
                tackleDir = characterDirection
            end

            localPlayer:SetAttribute("CMDTackleDir", tackleDir)
        else
            localPlayer:SetAttribute("CMDTackleDir", nil)
        end
    end,
    ["Skill"] = function(self, inputState)
        if Lib.playerIsStunned() then return end

        local chickynoid = self.ClientModule:GetClientChickynoid()
        if chickynoid == nil then
            return
        end
        local simulation = chickynoid.simulation

        if inputState == Enum.UserInputState.Begin and hasBall() and actionAvailable(simulation) then
            self:Skill()
        end
    end,

    ["RequestBall"] = function(self, inputState)
        if inputState ~= Enum.UserInputState.Begin then return end
        if Lib.playerIsStunned() then return end
        self:RequestBall()
    end,
    ["Sprint"] = function(self, inputState)
        if UserInputService.TouchEnabled or UserInputService.GamepadEnabled then
            if inputState ~= Enum.UserInputState.Begin then return end
            if localPlayer:GetAttribute("Sprinting") then
                self:StopSprint()
            else
                self:StartSprint()
            end
        else
            if inputState == Enum.UserInputState.Begin then
                self:StartSprint()
            elseif inputState == Enum.UserInputState.End then
                self:StopSprint()
            end
        end
    end,
    ["ShiftLock"] = function(self, inputState)
        if inputState ~= Enum.UserInputState.Begin then return end
        self:ToggleShiftLock()
    end,
}
CharacterController.shiftLockSignal = Signal.new() 

function CharacterController:CallKeybindFunction(actionName: string, inputState)
    local keybindFunction: (typeof(CharacterController), string) -> () = self.keybindFunctions[actionName]
    if keybindFunction == nil then
        return warn("Couldn't find keybind function for:", actionName)
    end
    keybindFunction(self, inputState)
end

function CharacterController:SetKeybinds()
    local function bindShoot()
        bindAction("Shoot")
        ContextActionService:BindActionAtPriority("Shoot", function(_, inputState)
            self:CallKeybindFunction("Shoot", inputState)
        end, false, 1, Keybinds.PC.Shoot, Keybinds.Console.Shoot)
    end

    local function bindDive()
        bindAction("Dive")
        ContextActionService:BindAction("Dive", function(_, inputState)
            self:CallKeybindFunction("Dive", inputState)
        end, false, Keybinds.PC.Dive, Keybinds.Console.Dive)
    end
    local function bindTackle()
        bindAction("SlideTackle")
        ContextActionService:BindAction("SlideTackle", function(_, inputState)
            self:CallKeybindFunction("SlideTackle", inputState)
        end, false, Keybinds.PC.Tackle, Keybinds.Console.Tackle)
    end
    local function bindSkill()
        bindAction("Skill")
        ContextActionService:BindAction("Skill", function(_, inputState)
            self:CallKeybindFunction("Skill", inputState)
        end, false, Keybinds.PC.Skill, Keybinds.Console.Skill)
    end

    local function bindRequestBall()
        bindAction("RequestBall")
        ContextActionService:BindAction("RequestBall", function(_, inputState)
            self:CallKeybindFunction("RequestBall", inputState)
        end, false, Keybinds.PC.RequestBall, Keybinds.Console.RequestBall)
    end
    local function bindSprint()
        bindAction("Sprint")
        ContextActionService:BindAction("Sprint", function(_, inputState)
            self:CallKeybindFunction("Sprint", inputState)
        end, false, Keybinds.PC.Sprint, Keybinds.Console.Sprint)
    end

    keybindTrove:Clean()

    local character = localPlayer.Character
    if character:GetAttribute("Goalkeeper") then
        bindShoot()

        bindSprint()

        local function ballChanged()
            unbindAction("Dive")
            unbindAction("RequestBall")
            if not hasBall() then
                bindRequestBall()
                bindDive()
            end
        end
        ballChanged()
        keybindTrove:Connect(realBallObject.Changed, ballChanged)
    else
        bindShoot()
    
        bindSprint()

        local function ballChanged()
            unbindAction("SlideTackle")
            unbindAction("Skill")
            unbindAction("RequestBall")
            if not hasBall() then
                bindRequestBall()
                bindTackle()
            else
                bindSkill()
            end
        end
        ballChanged()
        keybindTrove:Connect(realBallObject.Changed, ballChanged)
    end

    local lastState = Lib.playerIsStunned()
    keybindTrove:Connect(RunService.Heartbeat, function()
        local isStunned = Lib.playerIsStunned()
        if lastState == isStunned then
            return
        end

        if isStunned then
            lastState = isStunned
            self:UnbindKeybinds(true)
        else
            self:SetKeybinds()
        end
    end)
end

function CharacterController:UnbindKeybinds(ignoreShiftLock)
    unbindAction("Shoot")
    unbindAction("Dive")
    unbindAction("Sprint")
    unbindAction("SlideTackle")
    unbindAction("Skill")
    unbindAction("RequestBall")
end

-- Mechanics
function CharacterController:ToggleShiftLock(enabled)
    self.shiftLockEnabled = if enabled ~= nil then enabled else not self.shiftLockEnabled
    self.shiftLockSignal:Fire()
    localPlayer:SetAttribute("ShiftLock", self.shiftLockEnabled)
    SmoothShiftLock:ToggleShiftLock(self.shiftLockEnabled)
end

function CharacterController:RequestBall()
    if not Lib.playerInGameOrPaused() then return end
    if hasBall() then return end

    if not requestBallCooldown:IsFinished() then return end
    requestBallCooldown:Update()

    local simulation = self.ClientModule:GetClientChickynoid().simulation
    simulation.characterData:PlayAnimation("RequestBall", 1, true)

    CharacterService:RequestBall()
end

function CharacterController:Skill()
    if not Lib.playerInGameOrPaused() then return end
    if not hasBall() then return end

    skillCooldown.cooldown = privateServerInfo:GetAttribute("SkillCD") + GameInfo.SKILL_DURATION
    if not skillCooldown:IsFinished() then return end
    skillCooldown:Update()

    self:EndShot()
    self.ClientModule.skillServerTime = self.ClientModule.estimatedServerTime
end

-- Shooting
function CharacterController:ShootBall(shotType, multiplier)
    if not Lib.playerInGameOrPaused() then return end
    if not chargingShot then return end

    if not hasBall() then
        self:EndShot()
        return
    end

    multiplier = multiplier or 1
    local shotDirection = Lib.getShotDirection()
    local shotPower = localPlayer:GetAttribute("ShotPower")
    shotPower = math.clamp(shotPower, 0, privateServerInfo:GetAttribute("MaxShotPower"))

    local ballController = self.ClientModule.localBallController
    self.ClientModule.shotInfo = {
        guid = ballController.simulation.state.guid,
        shotType = shotType,
        shotPower = shotPower,
        shotDirection = shotDirection,
        curveFactor = localPlayer:GetAttribute("CurveFactor"),
    }
    self.ClientModule.doShotOnClient = true

    self:EndShot()
end

function CharacterController:BeginShot()
    if not Lib.playerInGameOrPaused() then return end

    if not shootCooldown:IsFinished() then
        return    
    end

    action = "Shoot"
    self:BeginChargeShot(action)
end

function CharacterController:BeginChargeShot(shotType: string)
    shotTrove:Clean()
    chargingShot = true

    local humanoid = Lib.getHumanoid()
    spr.target(humanoid, 1, 3, {
        CameraOffset = GameInfo.CAMERA_OFFSET + Vector3.new(1.5, 0, 0),
    })

    localPlayer:SetAttribute("ChargingShot", true)
    shotTrove:Add(function()
        localPlayer:SetAttribute("AdjustedCurve", false)
        chargingShot = false
        localPlayer:SetAttribute("ChargingShot", false)

        spr.target(humanoid, 1, 3, {
            CameraOffset = GameInfo.CAMERA_OFFSET,
        })
    end)

    local actualPower = localPlayer:GetAttribute("ShotPower")


    if shotType == "Shoot" then
        localPlayer:SetAttribute("CurveFactor", 0)
    end
    local lastCameraRotation: number
    local function chargeShot(deltaTime)
        if humanoid == nil or humanoid.Parent == nil or humanoid.Health == 0 then
            self:EndShot()
            return
        end

        local maxShotPower = privateServerInfo:GetAttribute("MaxShotPower")
        actualPower += deltaTime*maxShotPower*GameInfo.SHOT_CHARGE_MULTIPLIER

        local newPower = math.min(maxShotPower, actualPower)
        localPlayer:SetAttribute("ShotPower", newPower)

        if actualPower >= privateServerInfo:GetAttribute("MaxShotPower")*3 then
            self:ShootBall("Shoot")
            return
        end

        
        -- Curve shot updater
        if shotType == "Shoot" and not buttonBasedCurving then
            local _, cameraRotation, _ = currentCamera.CFrame:ToEulerAnglesYXZ()
            if lastCameraRotation and lastCameraRotation ~= cameraRotation then
                local difference = getClosestAngle(cameraRotation, lastCameraRotation) - lastCameraRotation 
                local increment = -difference * GameInfo.CURVE_FACTOR_CHARGE_MULTIPLIER
                local curveFactor = localPlayer:GetAttribute("CurveFactor")
                if math.sign(curveFactor) ~= math.sign(increment) then
                    local multipliedIncrement = math.sign(increment) * math.min(math.abs(increment), math.abs(curveFactor / 3))
                    curveFactor += multipliedIncrement*3
                    increment -= multipliedIncrement
                    localPlayer:SetAttribute("AdjustedCurve", true)
                else
                    localPlayer:SetAttribute("AdjustedCurve", false)
                end
                localPlayer:SetAttribute("CurveFactor", math.clamp(curveFactor + increment, -GameInfo.MAXIMUM_CURVE_FACTOR, GameInfo.MAXIMUM_CURVE_FACTOR))
            else
                localPlayer:SetAttribute("AdjustedCurve", false)
            end
            lastCameraRotation = cameraRotation 
        end
    end
    chargeShot(0)
    shotTrove:Connect(RunService.RenderStepped, chargeShot)
end

CharacterController.shotEnded = Signal.new()
function CharacterController:EndShot()
    -- if not Lib.playerInGameOrPaused() then return end

    self.shotEnded:Fire()
    shootCooldown:Update()

    action = nil
    shotTrove:Clean()

    localPlayer:SetAttribute("ShotPower", 0)
end

-- Sprint
function CharacterController:StartSprint()
    if localPlayer:GetAttribute("MovementDisabled") then
        return
    end

    if not Lib.playerInGameOrPaused() then return end

    local chickynoid = self.ClientModule:GetClientChickynoid()
    if chickynoid == nil then
        return
    end
    local simulation = chickynoid.simulation
    
    if not actionAvailable(simulation) then return end
    if Lib.playerIsStunned() then return end

    localPlayer:SetAttribute("Sprinting", true)

    local humanoid = Lib.getHumanoid()
    if humanoid == nil then return end

    staminaDrainTrove:Clean()
    staminaDrainTrove:Connect(RunService.Heartbeat, function(deltaTime)
        if humanoid == nil or humanoid.Parent == nil or humanoid.Health == 0 then
            staminaDrainTrove:Clean()
            return
        end
        if localPlayer:GetAttribute("ServerChickyRagdoll") or humanoid.MoveDirection.Magnitude == 0 or humanoid.WalkSpeed == 0 then
            spr.target(currentCamera, 1, 3, {FieldOfView = 70})
            return
        end

        if localPlayer:HasTag("Ragdoll") then
            self:StopSprint()
            return
        end

        spr.target(currentCamera, 1, 3, {FieldOfView = 80})

        if localPlayer:GetAttribute("Stamina") == 0 then
            self:StopSprint()
            staminaDrainTrove:Clean()
        end
    end)
end

function CharacterController:StopSprint()
    -- if not Lib.playerInGameOrPaused() then return end
    localPlayer:SetAttribute("Sprinting", false)

    staminaDrainTrove:Clean()

    spr.target(currentCamera, 1, 3, {FieldOfView = 70})
end

return CharacterController