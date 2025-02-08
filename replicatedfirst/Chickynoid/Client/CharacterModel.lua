--!native
local CharacterModel = {}
CharacterModel.__index = CharacterModel

--[=[
    @class CharacterModel
    @client

    Represents the client side view of a character model
    the local player and all other players get one of these each
    Todo: think about allowing a serverside version of this to exist for perhaps querying rays against?
    
    Consumes a CharacterData 
]=]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local AnimationRemoteEvent = ReplicatedStorage:WaitForChild("AnimationReplication") :: RemoteEvent

local path = game.ReplicatedFirst.Chickynoid
local Enums = require(path.Shared.Enums)
local FastSignal = require(path.Shared.Vendor.FastSignal)
local ClientMods = require(path.Client.ClientMods)
local Animations = require(path.Shared.Simulation.Animations)
local GameInfo = require(ReplicatedFirst.GameInfo)

local Quaternion = require(script.Parent.Parent.Shared.Simulation.Quaternion)

local localPlayer = Players.LocalPlayer

CharacterModel.template = nil
CharacterModel.characterModelCallbacks = {}


function CharacterModel:ModuleSetup()
	self.template = path.Assets:FindFirstChild("R6Rig")
	self.modelPool = {}
end


function CharacterModel.new(userId, characterMod)
	local self = setmetatable({
		model = nil,
		tracks = {},
		animator = nil,
		modelData = nil,
		playingTrack0 = nil,
		playingTrack1 = nil,
		runAnimTrack = nil,
		playingTrackNum0 = nil,
		playingTrackNum1 = nil,
		animCounter = -1,
		modelOffset = Vector3.new(0, 0.5, 0),
		modelReady = false,
		startingAnimation = "Idle",
		userId = userId,
		characterMod = characterMod,
		mispredict = Vector3.new(0, 0, 0),
		onModelCreated = FastSignal.new(),
		onModelDestroyed = FastSignal.new(),
		updated=false,
		 

	}, CharacterModel)

	return self
end

function CharacterModel:CreateModel(avatarDescription: {string}?)

	self:DestroyModel()

	--print("CreateModel ", self.userId)
	task.spawn(function()
		
		self.coroutineStarted = true

		local srcModel: Model = nil

		-- Download custom character
		if (self.modelPool[self.userId] == nil) then
			for _, characterModelCallback in ipairs(self.characterModelCallbacks) do
				local result = characterModelCallback(self.userId);
				if (result) then
					srcModel = result:Clone()
				end
			end

			--Check the character mod
			local success, humanoidDescription = pcall(function()
				local userId = self.userId
				if (string.sub(userId, 1, 1) == "-") then
					userId = string.sub(userId, 2, string.len(userId)) --drop the -
				end

				local humanoidDescription = Players:GetHumanoidDescriptionFromUserId(userId)
				humanoidDescription.Head = 0
				humanoidDescription.LeftArm = 0
				humanoidDescription.LeftLeg = 0
				humanoidDescription.RightArm = 0
				humanoidDescription.RightLeg = 0
				humanoidDescription.Torso = 0

				local accessoryList = humanoidDescription:GetAccessories(true)
				for _, accessoryInfo in ipairs(table.clone(accessoryList)) do
					local accessoryWhitelist = {Enum.AccessoryType.Hat, Enum.AccessoryType.Hair, Enum.AccessoryType.Face, Enum.AccessoryType.Eyebrow, Enum.AccessoryType.Eyelash}
					if not table.find(accessoryWhitelist, accessoryInfo.AccessoryType) then
						table.remove(accessoryList, table.find(accessoryList, accessoryInfo))
					end
				end
				humanoidDescription:SetAccessories(accessoryList, true)

				return humanoidDescription
			end)
			if not success then
				humanoidDescription = Instance.new("HumanoidDescription")
			end

			local originalHumanoidDescription = humanoidDescription:Clone()
			if (srcModel == nil) then
				if (self.characterMod) then
					local loadedModule = ClientMods:GetMod("characters", self.characterMod)
					if (loadedModule and loadedModule.GetCharacterModel) then
						local template = loadedModule:GetCharacterModel(self.userId, avatarDescription, humanoidDescription)
						if (template) then
							srcModel = template:Clone()
						end
					end
				end
			end

			if (srcModel == nil) then
				srcModel = self.template:Clone()
				srcModel.Parent = game.Lighting --needs to happen so loadAppearance works

				local userId = ""
				local result, err = pcall(function()

					userId = self.userId
					srcModel:SetAttribute("userid", userId)

					local player = Players:GetPlayerByUserId(userId)
					if player then
						srcModel.Name = player.Name
					end

					--Bot id?
					srcModel.Humanoid:ApplyDescriptionReset(humanoidDescription)
				end)
				if (result == false) then
					warn("Loading " .. userId .. ":" ..err)
				end
			end

			--setup the hip
			local hip = srcModel.Humanoid.HipHeight
			srcModel.Humanoid.CameraOffset = GameInfo.CAMERA_OFFSET

			self.modelData =  {
				model =	srcModel,
				modelOffset =  Vector3.new(0, hip, 0),
				humanoidDescription = originalHumanoidDescription,
			}
			self.modelPool[self.userId] = self.modelData
		end
		
		self.modelData = self.modelPool[self.userId]
		self.model = self.modelData.model
		self.primaryPart = self.model.PrimaryPart
		self.model.Parent = game.Lighting -- must happen to load animations

		--Load on the animations
		self.animator = self.model:FindFirstChild("Animator", true)
		local humanoid = self.model:FindFirstChild("Humanoid")
		if (not self.animator) then
			if (humanoid) then
				self.animator = self.template:FindFirstChild("Animator", true):Clone()
				self.animator.Parent = humanoid
			end
		end
		self.tracks = {}

		self:SetupLobbyChickynoid()
		for _, value in pairs(self.animator:GetDescendants()) do
			if value:IsA("Animation") then
				local track = self.animator:LoadAnimation(value)
				self.tracks[value.Name] = track
			end
		end

		self.modelReady = true

		if self.playingTrackNum0 then
			self:PlayAnimation(self.playingTrackNum0, false, Enums.AnimChannel.Channel0)
		else
			self:PlayAnimation(self.startingAnimation, true, Enums.AnimChannel.Channel0)
		end


		local function adjustCollisions(part: BasePart)
			if not part:IsA("BasePart") then return end
			if part:HasTag("Ball") then
				return
			end
			part.CollisionGroup = "Character"
		end
		for _, child in pairs(srcModel:GetChildren()) do
			adjustCollisions(child)
		end
		srcModel.ChildAdded:Connect(adjustCollisions)
			
		self.model.Parent = game.Workspace
		self.onModelCreated:Fire(self.model)
		self:SetupFieldChickynoid()

		local player = Players:GetPlayerByUserId(self.userId)
		if player then
			local function setEmoteData()
				self.model:SetAttribute("EmoteData", player:GetAttribute("EmoteData"))
			end
			setEmoteData()
			player:GetAttributeChangedSignal("EmoteData"):Connect(setEmoteData)
		end

		for _, stateType in pairs(Enum.HumanoidStateType:GetEnumItems()) do
			if stateType == Enum.HumanoidStateType.None then continue end
			if localPlayer == player and stateType == Enum.HumanoidStateType.Jumping then continue end
			humanoid:SetStateEnabled(stateType, false)
		end


		self.resetRagdoll = false
		self.model:GetAttributeChangedSignal("ResetRagdoll"):Connect(function()
			self.resetRagdoll = self.model:GetAttribute("ResetRagdoll")
		end)

		self.applyFreezeRotation = false
		self.model:GetAttributeChangedSignal("ApplyFreezeRotation"):Connect(function()
			self.applyFreezeRotation = self.model:GetAttribute("ApplyFreezeRotation")
		end)

		self.applyRagdollKnockback = false
		self.model:GetAttributeChangedSignal("ApplyRagdollKnockback"):Connect(function()
			self.applyRagdollKnockback = self.model:GetAttribute("ApplyRagdollKnockback")
		end)

		self.coroutineStarted = false
	end)
end

function CharacterModel:ReplaceModel(avatarDescription: {string}?)
	if self.coroutineStarted then
		return
	end

	task.spawn(function()
		
		self.coroutineStarted = true

		local srcModel = self.model
		local humanoidDescription: HumanoidDescription = self.modelData.humanoidDescription:Clone()

		local isFieldPlayer = self.characterMod == "FieldChickynoid" or self.characterMod == "GoalkeeperChickynoid"
		if isFieldPlayer then
			local userId = self.userId
			local result, err = pcall(function()
				local loadedModule = ClientMods:GetMod("characters", self.characterMod)
				loadedModule:DoStuffToModel(userId, srcModel, avatarDescription, humanoidDescription)
			end)
			if (result == false) then
				warn("Loading " .. userId .. ":" ..err)
			end
		else
			local userId = ""
			local result, err = pcall(function()

				userId = self.userId
				--Bot id?
				if (string.sub(userId, 1, 1) == "-") then
					userId = string.sub(userId, 2, string.len(userId)) --drop the -
				end
			
				srcModel.Humanoid:ApplyDescriptionReset(humanoidDescription)
				
				local torso = srcModel.Torso
				local kitInfo: SurfaceGui = torso:FindFirstChild("KitInfo")
				if kitInfo then
					kitInfo.Enabled = false
				end

				if self.userId == localPlayer.UserId then
					srcModel.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				else
					srcModel.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
				end
			end)
			if (result == false) then
				warn("Loading " .. userId .. ":" ..err)
			end
		end

		self.modelData.modelOffset = Vector3.new(0, srcModel.Humanoid.HipHeight, 0)
		self.primaryPart = self.model.PrimaryPart

		--Load on the animations
		self.animator = self.model:FindFirstChild("Animator", true)
		if (not self.animator) then
			local humanoid = self.model:FindFirstChild("Humanoid")
			if (humanoid) then
				self.animator = self.template:FindFirstChild("Animator", true):Clone()
				self.animator.Parent = humanoid
			end
		end

		for _, value in pairs(self.animator:GetPlayingAnimationTracks()) do
			value:Stop()
		end
		self.tracks = {}

		self.animator:ClearAllChildren()
		local characterWithAnims = self.template
		if self.characterMod == "FieldChickynoid" then
			characterWithAnims = path.Assets:FindFirstChild("FieldRig")
		elseif self.characterMod == "GoalkeeperChickynoid" then
			characterWithAnims = path.Assets:FindFirstChild("GoalkeeperRig")
		end
		for _, animation: Animation in pairs(characterWithAnims.Humanoid.Animator:GetChildren()) do
			animation:Clone().Parent = self.animator
		end

		self:SetupLobbyChickynoid()
		for _, value in pairs(self.animator:GetDescendants()) do
			if value:IsA("Animation") then
				local track = self.animator:LoadAnimation(value)
				self.tracks[value.Name] = track
			end
		end

		self.modelReady = true

		if self.playingTrackNum0 then
			self:PlayAnimation(self.playingTrackNum0, false, Enums.AnimChannel.Channel0)
		else
			self:PlayAnimation(self.startingAnimation, true, Enums.AnimChannel.Channel0)
		end
				
		self.onModelCreated:Fire(self.model)
		self:SetupFieldChickynoid()

		self.coroutineStarted = false
	end)
end

function CharacterModel:SetupLobbyChickynoid()
	if self.characterMod ~= "HumanoidChickynoid" then
		return
	end
	self.model:RemoveTag("ChickynoidCharacter")
	self.model:RemoveTag("BuildRagdoll")

	self.model:SetAttribute("AppliedDescription", false)
end

function CharacterModel:SetupFieldChickynoid()
	local isFieldPlayer = self.characterMod == "FieldChickynoid" or self.characterMod == "GoalkeeperChickynoid"
	if not isFieldPlayer then
		return
	end
	self.model:AddTag("ChickynoidCharacter")
	self.model:AddTag("BuildRagdoll")
	self.model.PrimaryPart.Anchored = true

	self.model:SetAttribute("AppliedDescription", true)

	local isGoalkeeper = self.characterMod == "GoalkeeperChickynoid"
	self.model:SetAttribute("Goalkeeper", isGoalkeeper)


	local player = Players:GetPlayerByUserId(self.userId) :: Player
	if player == nil then
		player = {}
		player.UserId = 0
		function player:GetAttribute()
			
		end
		function player:GetAttributeChangedSignal()
			return localPlayer:GetAttributeChangedSignal("testattribute")
		end
		function player:SetAttribute()
			
		end
	end

	local Trove = require(ReplicatedStorage.Modules.Trove)

	local assets = ReplicatedStorage.Assets
	local animationFolder = assets.Animations
	
	local trove = Trove.new()
	if type(player) ~= "table" then
		trove:AttachToInstance(player)
	end
	trove:Connect(self.onModelCreated, function()
		trove:Destroy()
	end)

	if not isGoalkeeper then
		local function updateGroundSkill()
			local skillAnimations = animationFolder.Skills
			local groundSkill: string = player:GetAttribute("GroundSkill") or "Feint"
			self.tracks.Skill:Stop()
			self.tracks.Skill = self.animator:LoadAnimation(skillAnimations.Ground[groundSkill])
		end
		updateGroundSkill()
		trove:Connect(player:GetAttributeChangedSignal("GroundSkill"), updateGroundSkill)
	end

	local character = self.model
	if self.characterMod == "GoalkeeperChickynoid" then
		local holdAnimation = self.tracks.Hold
		trove:Connect(player.Ball.Changed, function(ball: BasePart?)
			if character:GetAttribute("Goalkeeper") then
				if ball ~= nil then
					holdAnimation:Play()
				else
					holdAnimation:Stop()
				end
			end
		end)
	end
end


function CharacterModel:DestroyModel()
	
	self.destroyed = true
	
	task.spawn(function()
		
		--The coroutine for loading the appearance might still be running while we've already asked to destroy ourselves
		--We wait for it to finish, then clean up		
		while (self.coroutineStarted == true) do
			wait()
		end
		
		if (self.model == nil) then
			return
		end
		self.onModelDestroyed:Fire()

		self.playingTrack0 = nil
		self.playingTrack1 = nil
		self.modelData = nil
		self.animator = nil
		self.tracks = {}
		self.model:Destroy()

		if self.modelData and self.modelData.model then
			self.modelData.model:Destroy()
		end

		self.modelData = nil
		self.modelPool[self.userId] = nil
		self.modelReady = false
		
		
	end)
end

function CharacterModel:PlayerDisconnected(userId)

	local modelData = self.modelPool[self.userId]
	if (modelData and modelData.model) then
		modelData.model:Destroy()
	end
end


--you shouldnt ever have to call this directly, change the characterData to trigger this
function CharacterModel:PlayAnimation(enum, force, animChannel)
	
	local name = Animations:GetAnimation(enum)
	if (name == nil) then
		name = "Idle"
	end

	if self.modelReady == false then
		--Model not instantiated yet
		local startingAnimationIndex = "startingAnimation"..animChannel
		self[startingAnimationIndex] = name
		return
	end

	if not self.modelData then
		return
	end

	local tracks = self.tracks
	local track = tracks[name]

	local stunIdleAnim = tracks.StunIdle
	if stunIdleAnim and animChannel == Enums.AnimChannel.Channel1 then
		stunIdleAnim:Stop()
	end
	
	local playingTrackIndex = "playingTrack" .. animChannel
	local playingTrackNumIndex = "playingTrackNum"..animChannel
	local playingTrack = self[playingTrackIndex]
	if name == "Stop" then
	
		-- Stop anim
		if playingTrack then
			playingTrack:Stop()
			self[playingTrackIndex] = nil
			self[playingTrackNumIndex] = nil
		end
		return
	end

	if track == nil then
		return
	end
	if playingTrack == track and force ~= true then
		return
	end

	if playingTrack then
		if animChannel ~= Enums.AnimChannel.Channel1 or table.find({"StunFlip", "StunIdle", "StunLand"}, name) then
			playingTrack:Stop()
		end
	end

	local weights = {
		ChargeShot = 0.3, LowCatch = 0, HighCatch = 0,
	}
	track:Play(weights[name])
	if name == "StunLand" and stunIdleAnim then
		stunIdleAnim:Play()
	end


	if animChannel == Enums.AnimChannel.Channel1 then
		-- local priorities = {RequestBall = Enum.AnimationPriority.Action}
		-- track.Priority = priorities[name] or Enum.AnimationPriority.Action1
	elseif animChannel == Enums.AnimChannel.Channel0 then
		track.Priority = Enum.AnimationPriority.Core
	end

	self[playingTrackIndex] = track
	self[playingTrackNumIndex] = enum


	-- local player = self.player
	-- if self.player == nil then
	-- 	self.player = Players:GetPlayerByUserId(self.userId)
	-- 	player = self.player
	-- end

	-- local controllers = localPlayer.PlayerScripts.ClientScripts.Controllers
	-- local EffectController = require(controllers.EffectController)
	-- if table.find({"Shoot"}, name) then
	-- 	EffectController:CreateEffect("ballKicked", {player})
	-- end
end

function CharacterModel:Think(_deltaTime, dataRecord, bulkMoveToList, customData: {ballRotation: Vector3, w: number, leanAngle: Vector2, animDir: number})
	if self.model == nil then
		return
	end

	if self.modelData == nil then
		return
	end

	local player = self.player
	if self.player == nil then
		self.player = Players:GetPlayerByUserId(self.userId)
		player = self.player
	end
	local isLocalPlayer = localPlayer == player

	if isLocalPlayer then
		debug.profilebegin("Chickynoid Local Character Animate")
	end

	--Flag that something has changed on all channels
	for animChannel = 0,3,1 do
		
		-- get anim counter index/name from for loop counter
		local animCounterIndex = "animCounter"..animChannel
		
		if self[animCounterIndex] ~= dataRecord[animCounterIndex] then
			-- DATA CHANGED!
			
			-- update anim counter
			self[animCounterIndex] = dataRecord[animCounterIndex]
			
			-- Play animation
			local animNum = dataRecord["animNum"..animChannel]
			self:PlayAnimation(animNum, true, animChannel)
		end
	end

	if isLocalPlayer then
		debug.profileend()
	end


	local newCF

	local position = dataRecord.pos
	
	local root = self.model.HumanoidRootPart.RootJoint
	local isRagdolled = self.model:HasTag("Ragdoll")
	if isRagdolled then
		if isLocalPlayer then
			debug.profilebegin("Chickynoid Local Character Ragdolled/Frozen")
		end
		root.C0 = CFrame.new(root.C0.Position)

		if isRagdolled then
			self.primaryPart.Anchored = true
		else
			self.primaryPart.Anchored = false
		end
		local success, warning = pcall(function()
			if self.applyRagdollKnockback and isRagdolled then
				self.model:SetAttribute("ApplyRagdollKnockback", nil)
				if localPlayer == player then
					for _, animation in pairs(self.model.Humanoid.Animator:GetPlayingAnimationTracks()) do
						animation:Stop(0)
					end
				end
			end
	
			local currentPivot: CFrame = self.model:GetPivot()
			local newPosition = dataRecord.pos + self.modelData.modelOffset + self.mispredict + Vector3.new(0, dataRecord.stepUp, 0)
			if (position + self.mispredict).Y < 48 then
				newPosition = Vector3.new(newPosition.X, currentPivot.Y, newPosition.Z)
			end
			newCF = CFrame.new(newPosition) * currentPivot.Rotation
		end)
		if not success then
			warn(warning)
			newCF = CFrame.new(dataRecord.pos + self.modelData.modelOffset + self.mispredict + Vector3.new(0, dataRecord.stepUp, 0))
				* CFrame.fromEulerAnglesXYZ(0, dataRecord.angle, 0)
		end
		if isLocalPlayer then
			debug.profileend()
		end
	else
		self.primaryPart.Anchored = true


		if isLocalPlayer then
			debug.profilebegin("Chickynoid Local Character Set Lean Angle")
		end

		local leanAngle = CFrame.new()
		if self.characterMod ~= "HumanoidChickynoid" then
			if player == localPlayer then
				local newAngle = CFrame.Angles(-customData.leanAngle.X, customData.leanAngle.Y, 0)
				leanAngle = newAngle
			else
				local newAngle = CFrame.Angles(-dataRecord.leanAngle.X, dataRecord.leanAngle.Y, 0)
				leanAngle = newAngle
			end
		end
		root.C0 = CFrame.new(root.C0.Position) * CFrame.fromEulerAnglesYXZ(math.rad(-90), math.rad(-180), math.rad(0)) * leanAngle

		if isLocalPlayer then
			debug.profileend()
		end

		local animDir = customData and customData.animDir or dataRecord.animDir
		if animDir == 0 then
			animDir = 1
		else
			animDir = -1
		end
		
		if self.playingTrackNum0 == Animations:GetAnimationIndex("Sprint") then
			animDir = 1
		end

		if isLocalPlayer then
			debug.profilebegin("Chickynoid Local Character Adjust Speeds")
		end
		if self.playingTrackNum0 == Animations:GetAnimationIndex("Sprint") then
			local vel = dataRecord.flatSpeed
			local playbackSpeed = (vel / 16) --Todo: Persistant player stats
			self.playingTrack0:AdjustSpeed(playbackSpeed * animDir)
		elseif self.playingTrackNum0 == Animations:GetAnimationIndex("Walk") then
			local isFieldPlayer = self.characterMod == "FieldChickynoid" or self.characterMod == "GoalkeeperChickynoid"
			if isFieldPlayer then
				local vel = dataRecord.flatSpeed
				local playbackSpeed = vel / 16
				self.playingTrack0:AdjustSpeed(playbackSpeed * animDir)
			else
				local vel = dataRecord.flatSpeed
				local playbackSpeed = vel / 16
				self.playingTrack0:AdjustSpeed(playbackSpeed)
			end
		end
	
		if self.playingTrackNum0 == Animations:GetAnimationIndex("Push") then
			local vel = 14
			local playbackSpeed = (vel / 16) --Todo: Persistant player stats
			self.playingTrack0:AdjustSpeed(playbackSpeed * animDir)
		end
		if isLocalPlayer then
			debug.profileend()
		end

		
		if isLocalPlayer then
			debug.profilebegin("Chickynoid Local Character Reset Ragdoll")
		end
		local resetTime = self.resetRagdoll
		if resetTime then
			if localPlayer == player then
				localPlayer:SetAttribute("ClientRagdollAnimation", nil)
			end

			if self.playingTrack0 and not self.playingTrack0.IsPlaying then
				self.playingTrack0:Play()
			elseif self.playingTrack0 and self.playingTrack0.Speed == 0 then
				self.playingTrack0:AdjustSpeed(1)
			end
			
			local timePassed = os.clock() - resetTime
			local alpha = timePassed / 0.5
			if alpha > 1 then
				self.model:SetAttribute("ResetRagdoll", nil)
				newCF = CFrame.new(dataRecord.pos + self.modelData.modelOffset + self.mispredict + Vector3.new(0, dataRecord.stepUp, 0))
					* CFrame.fromEulerAnglesXYZ(0, dataRecord.angle, 0)
			else
				local currentPivot: CFrame = self.model:GetPivot()
				local goalPosition = dataRecord.pos + self.modelData.modelOffset + self.mispredict + Vector3.new(0, dataRecord.stepUp, 0)
				local currentPosition = Vector3.new(goalPosition.X, currentPivot.Y, goalPosition.Z)
				newCF = CFrame.new(currentPosition:Lerp(goalPosition, alpha)) * currentPivot.Rotation:Lerp(CFrame.fromEulerAnglesXYZ(0, dataRecord.angle, 0), alpha)
			end
		else
			newCF = CFrame.new(dataRecord.pos + self.modelData.modelOffset + self.mispredict + Vector3.new(0, dataRecord.stepUp, 0))
				* CFrame.fromEulerAnglesXYZ(0, dataRecord.angle, 0)
		end
		if isLocalPlayer then
			debug.profileend()
		end
	end

	if (bulkMoveToList) then
		table.insert(bulkMoveToList.parts, self.primaryPart)
		table.insert(bulkMoveToList.cframes, newCF)
	else
		workspace:BulkMoveTo({self.primaryPart}, {newCF}, Enum.BulkMoveMode.FireCFrameChanged)
		-- self.model:PivotTo(newCF)
	end
end

function CharacterModel:SetCharacterModel(callback)
	table.insert(self.characterModelCallbacks, callback)
end


CharacterModel:ModuleSetup()

return CharacterModel
