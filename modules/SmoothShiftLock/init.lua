local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorkspaceService = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Lib = require(ReplicatedStorage.Lib)

local Spring = require(ReplicatedStorage.Modules.Spring)
local Trove = require(ReplicatedStorage.Modules.Trove)

local trove = Trove.new()

local config = {
	["CHARACTER_SMOOTH_ROTATION"]   = true,                       --// If your character should rotate smoothly or not
	["MANUALLY_TOGGLEABLE"]         = true,                       --// If the shift lock an be toggled manually by player
	["CHARACTER_ROTATION_SPEED"]    = 2,                          --// How quickly character rotates smoothly
	["TRANSITION_SPRING_DAMPER"]    = 0.7,                        --// Camera transition spring damper, test it out to see what works for you
	["CAMERA_TRANSITION_IN_SPEED"]  = 10,                         --// How quickly locked camera moves to offset position
	["CAMERA_TRANSITION_OUT_SPEED"] = 14,                         --// How quickly locked camera moves back from offset position
	["LOCKED_CAMERA_OFFSET"]        = Vector3.new(0, 0, 0), 	  --// Locked camera offset
	["LOCKED_MOUSE_ICON"]           =                             --// Locked mouse icon
		"rbxasset://textures/MouseLockedCursor.png",
	["LOCKED_MOUSE_VISIBLE"]		= true,
}

local ENABLED = false

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer.PlayerGui

local mouseUnlocked = false


local SmoothShiftLock = {}

function SmoothShiftLock:Init()
	local managerTrove = Trove.new();
	managerTrove:Connect(localPlayer.CharacterAdded, function()
		self:CharacterAdded()
	end)
	if localPlayer.Character then
		task.spawn(function()
			self:CharacterAdded()
		end)
	end
end

function SmoothShiftLock:CharacterAdded()
	--// Instances
	self.Character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
	self.RootPart = self.Character:WaitForChild("HumanoidRootPart")
	self.Humanoid = self.Character:WaitForChild("Humanoid")
	self.Head = self.Character:WaitForChild("Head")
	--// Other
	self.Camera = WorkspaceService.CurrentCamera
	--// Setup
	self._connectionsTrove = Trove.new()
	self.camOffsetSpring = Spring.new(Vector3.new(0, 0, 0))
	self.camOffsetSpring.Damper = config.TRANSITION_SPRING_DAMPER

	return self
end

function SmoothShiftLock:IsEnabled(): boolean
	return ENABLED
end

function SmoothShiftLock:SetMouseState(enabled : boolean)
	enabled = enabled and not playerGui.EmoteWheel.Enabled and not playerGui.TeamSelect.Enabled and (ENABLED or localPlayer:GetAttribute("MouseLocked"))
	if mouseUnlocked then
		enabled = false
	end
	UserInputService.MouseBehavior = enabled and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	UserInputService.MouseIcon = enabled and "rbxasset://textures/MouseLockedCursor.png" or ""
	-- UserInputService.MouseIconEnabled = UserInputService.MouseBehavior == Enum.MouseBehavior.Default
end

function SmoothShiftLock:TransitionLockOffset(enable : boolean)
	if self.camOffsetSpring == nil then 
		warn("Couldn't find offset spring!")
		return
	end
	if enable then
		self.camOffsetSpring.Speed = config.CAMERA_TRANSITION_IN_SPEED;
		self.camOffsetSpring.Target = config.LOCKED_CAMERA_OFFSET;
	else
		self.camOffsetSpring.Speed = config.CAMERA_TRANSITION_OUT_SPEED;
		self.camOffsetSpring.Target = Vector3.new(0, 0, 0);
	end;
end

function SmoothShiftLock:ToggleShiftLock(enable : boolean)
	assert(typeof(enable) == typeof(false), "Enable value is not a boolean.")
	ENABLED = enable

	self:SetMouseState(ENABLED)
	self:TransitionLockOffset(ENABLED)
	
	trove:Clean()
	if self.Humanoid then
		self.Humanoid.AutoRotate = not ENABLED
	end

	mouseUnlocked = false

	if self.Character == nil or self.Character.Parent == nil then
		return
	end

	if ENABLED then
		trove:Connect(RunService.RenderStepped, function(delta)
			if not ENABLED then
				trove:Clean()
				return
			end

			local character = self.Character
			if character == nil or character:HasTag("Ragdoll") then
				return
			end
			if not self.Humanoid or not self.RootPart then
				return
			end

			local emoteData = character:GetAttribute("EmoteData")
			if emoteData ~= nil then
				emoteData = HttpService:JSONDecode(emoteData)
				local shiftLockDisabled = emoteData[3]
				if shiftLockDisabled then
					return
				end
			end
		end)
	end

	trove:Connect(playerGui.EmoteWheel:GetPropertyChangedSignal("Enabled"), function()
		self:SetMouseState(true)
		self:TransitionLockOffset(true)
	end)
	trove:Connect(playerGui.TeamSelect:GetPropertyChangedSignal("Enabled"), function()
		self:SetMouseState(true)
		self:TransitionLockOffset(true)
	end)
	trove:Add(task.spawn(function()
		while not Lib.playerInGameOrPaused() do
			task.wait()
		end
		if not ENABLED then
			local function checkMouseLocked()
				local mouseLocked = localPlayer:GetAttribute("MouseLocked")
				self:SetMouseState(mouseLocked)
				self:TransitionLockOffset(mouseLocked)
			end
			checkMouseLocked()
			trove:Connect(localPlayer:GetAttributeChangedSignal("MouseLocked"), checkMouseLocked)
		end
	end))

	return self
end

return SmoothShiftLock