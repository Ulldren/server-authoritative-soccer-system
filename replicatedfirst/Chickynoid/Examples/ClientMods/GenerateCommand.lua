local module = {}
--Module for how to pass user input to the chickynoid system
--It's not really an example (you need a version of this to play!) But you'll need to clone/remove/edit this to do your own input functionality

module.client = nil
module.useInbuiltDebugCheats = false
module.shiftLock = 0
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local currentCamera = workspace.CurrentCamera

--For access to control vectors
local ControlModule = nil --require(PlayerModule:WaitForChild("ControlModule"))

local function GetControlModule()
    if ControlModule == nil then
        local scripts = localPlayer:FindFirstChild("PlayerScripts")
        if scripts == nil then
            return nil
        end

        local playerModule = scripts:FindFirstChild("PlayerModule")
        if playerModule == nil then
            return nil
        end

        local controlModule = playerModule:FindFirstChild("ControlModule")
        if controlModule == nil then
            return nil
        end

        ControlModule = require(
            localPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"):WaitForChild("ControlModule")
        )
    end

    return ControlModule
end

local coreCall do
	local MAX_RETRIES = 8

	local StarterGui = game:GetService('StarterGui')
	local RunService = game:GetService('RunService')

	function coreCall(method, ...)
		local result = {}
		for retries = 1, MAX_RETRIES do
			result = {pcall(StarterGui[method], StarterGui, ...)}
			if result[1] then
				break
			end
			RunService.Stepped:Wait()
		end
		return unpack(result)
	end
end

function module:Setup(_client)
	self.client = _client
	
	UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			self.shiftLock = 1
		 
		end
		if UserInputService.MouseBehavior == Enum.MouseBehavior.Default then
			self.shiftLock = 0
			 
		end
		
	end)
	
	local resetBindable = Instance.new("BindableEvent")
	resetBindable.Event:connect(function()
		self.resetRequested = true	
	end)
	
	coreCall('SetCore', 'ResetButtonCallback', resetBindable)
end

function module:Step(_client, _deltaTime) end


function module:GenerateCommand(command, serverTime: number, dt: number, ClientModule)
    local Lib = require(ReplicatedStorage.Lib)
	
    command.x = 0
    command.y = 0
    command.z = 0

    GetControlModule()

    local chickynoid = ClientModule:GetClientChickynoid()
    local simulation = chickynoid and chickynoid.simulation

    local movementDisabled = localPlayer:GetAttribute("MovementDisabled") or localPlayer:GetAttribute("ServerChickyRagdoll") or localPlayer:GetAttribute("ServerChickyFrozen") or localPlayer:GetAttribute("StopInputs")
    if localPlayer:GetAttribute("ClientLoaded") and not movementDisabled then
        if ControlModule ~= nil then
            local moveVector = ControlModule:GetMoveVector() :: Vector3
            if moveVector.Magnitude > 0 then
                moveVector = moveVector.Unit
                command.x = moveVector.X
                command.y = moveVector.Y
                command.z = moveVector.Z
            end
        end 
    end
    
    local jumpDisabled = localPlayer:GetAttribute("JumpDisabled")
    if not UserInputService:GetFocusedTextBox() then

        local jump = UserInputService:IsKeyDown(Enum.KeyCode.Space)
        local crouch = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        command.y = 0
        if (jump and not jumpDisabled) then
            command.y = 1
        else
            if (crouch) then
                command.y = -1
            end
        end

        --Fire!
        command.f = UserInputService:IsKeyDown(Enum.KeyCode.Q) and 1 or 0
		
		
		if (self.useInbuiltDebugCheats == true) then		
	        --Fly?
	        if UserInputService:IsKeyDown(Enum.KeyCode.F8) then
	            command.flying = 1
	        end

	        --Cheat #1 - speed cheat!
	        if UserInputService:IsKeyDown(Enum.KeyCode.P) then
	            command.deltaTime *= 3
	        end

	        --Cheat #2 - suspend!
	        if UserInputService:IsKeyDown(Enum.KeyCode.L) then
	            local function test(f)
	                return f
	            end
	            for j = 1, 2000000 do
	                local a = j * 12
	                test(a)
	            end
			end
		end
    end

    local isJumping = self:GetIsJumping() == true
    if isJumping and not jumpDisabled then
        command.y = 1
    elseif not isJumping then
        localPlayer:SetAttribute("JumpDisabled", false)
    end

    local ball = localPlayer.Ball.Value

    local hasBall = ball ~= nil
    if hasBall or movementDisabled then
        command.y = 0
    end

    if command.y == 1 and Lib.playerInGameOrPaused(localPlayer) and simulation and simulation.lastGround then
        if localPlayer:GetAttribute("Position") ~= "Goalkeeper" then
            localPlayer:SetAttribute("JumpDisabled", true)
        end
    end
    
    --fire angles
	command.fa = currentCamera.CFrame.LookVector
	
	--Shiftlock
    local serverInfo: Configuration = ReplicatedStorage.ServerInfo
    local gameStatus = serverInfo:GetAttribute("GameStatus")
    local gameEnded = gameStatus == "GameEnded"
    if not gameEnded and localPlayer:GetAttribute("Sprinting") then
        command.sprinting = 1
    end

    local shiftLockDisabled
    local emoteData = localPlayer:GetAttribute("EmoteData")
    if emoteData ~= nil then
        emoteData = HttpService:JSONDecode(emoteData)
        shiftLockDisabled = emoteData[3]
    end
    if not shiftLockDisabled then
        if localPlayer:GetAttribute("ShiftLock") or currentCamera.Focus and (currentCamera.CFrame.Position - currentCamera.Focus.Position).Magnitude < 0.6 then
            command.shiftLock = 1
        end
    end

    command.tackleDir = Vector3.zero
    command.diveDir = Vector3.zero
    command.diveAnim = 0

    local cmdTackleDir = localPlayer:GetAttribute("CMDTackleDir")
    if not gameEnded and cmdTackleDir and not movementDisabled and not hasBall then
        command.tackleDir = cmdTackleDir
    end
    local cmdDiveDir = localPlayer:GetAttribute("CMDDiveDir")
    if not gameEnded and cmdDiveDir and not movementDisabled and not hasBall then
        command.diveDir = cmdDiveDir
        command.diveAnim = localPlayer:GetAttribute("CMDDiveAnim")
    end

    if localPlayer:GetAttribute("ChargingShot") then
        command.charge = 1
    end


    command.skill = 0
    if ClientModule.skillServerTime ~= nil then
        command.skill = 1
    end

     
    --Translate the move vector relative to the camera
    local rawMoveVector = self:CalculateRawMoveVector(Vector3.new(command.x, 0, command.z))
    command.x = rawMoveVector.X
	command.z = rawMoveVector.Z
	
	--reset requested?
	-- if self.resetRequested == true then
	-- 	command.reset = true
	-- 	self.resetRequested = false		
	-- end

    return command
end

function module:CalculateRawMoveVector(cameraRelativeMoveVector: Vector3)
    local Camera = workspace.CurrentCamera
    local _, yaw = Camera.CFrame:ToEulerAnglesYXZ()
    return CFrame.fromEulerAnglesYXZ(0, yaw, 0) * Vector3.new(cameraRelativeMoveVector.X, 0, cameraRelativeMoveVector.Z)
end

function module:GetIsJumping()
    if ControlModule == nil then
        return false
    end
    if ControlModule.activeController == nil then
        return false
    end

    return ControlModule.activeController:GetIsJumping()
        or (ControlModule.touchJumpController and ControlModule.touchJumpController:GetIsJumping())
end

local mouse = localPlayer:GetMouse()
function module:GetAimPoint()
    local ray = game.Workspace.CurrentCamera:ScreenPointToRay(mouse.X, mouse.Y)

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include

    local whiteList = { game.Workspace.Terrain }
    local collisionRoot = self.client:GetCollisionRoot()
    if (collisionRoot) then
        table.insert(whiteList, collisionRoot)
    end
    raycastParams.FilterDescendantsInstances = whiteList

    local raycastResults = game.Workspace:Raycast(ray.Origin, ray.Direction * 2000, raycastParams)
    if raycastResults then
        return raycastResults.Position
    end
    --We hit the sky perhaps?
    return ray.Origin + (ray.Direction * 2000)
end

return module