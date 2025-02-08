local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
--!native
local BallModel = {}
BallModel.__index = BallModel

--[=[
    @class BallModel
    @client

    Represents the client side view of a ball model
    
    Consumes a BallData
]=]

local path = game.ReplicatedFirst.Chickynoid
local Enums = require(path.Shared.Enums)
local FastSignal = require(path.Shared.Vendor.FastSignal)
local ClientMods = require(path.Client.ClientMods)
local Animations = require(path.Shared.Simulation.Animations)

local Quaternion = require(script.Parent.Parent.Shared.Simulation.Quaternion)

local localPlayer = Players.LocalPlayer

BallModel.template = nil
BallModel.characterModelCallbacks = {}


function BallModel:ModuleSetup()
	self.template = path.Assets:FindFirstChild("Ball")
	self.modelPool = {}
end


function BallModel.new(ballId)
	local self = setmetatable({
		model = nil,
		modelData = nil,
		modelReady = false,

		ballId = ballId,
		mispredict = Vector3.new(0, 0, 0),
		onModelCreated = FastSignal.new(),
		onModelDestroyed = FastSignal.new(),
		updated=false,
		 

	}, BallModel)

	return self
end

function BallModel:CreateModel()

	self:DestroyModel()

	--print("CreateModel ", self.ballId)
	task.spawn(function()
		
		self.coroutineStarted = true

		local srcModel: BasePart = self.template:Clone()
		
		self.model = srcModel
		self.modelReady = true

		srcModel:AddTag("Ball")

		local ballModelObject = Instance.new("ObjectValue")
		ballModelObject.Name = "BallModel"
		ballModelObject.Value = srcModel
		ballModelObject.Parent = localPlayer
		srcModel.CanCollide = false

		self.model.Parent = game.Workspace
		self.onModelCreated:Fire(self.model)

		self.coroutineStarted = false
	end)
end

function BallModel:DestroyModel()
	
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

		self.playingTrack = nil
		self.model:Destroy()
        
		self.modelPool[self.ballId] = nil
		self.modelReady = false
		
		
	end)
end


--you shouldnt ever have to call this directly, change the characterData to trigger this
function BallModel:Think(_deltaTime, dataRecord, bulkMoveToList, rotationQuaternion: typeof(Quaternion.new()))
	if self.model == nil then
		return
	end

	local newCF = rotationQuaternion:ToCFrame(dataRecord.pos + self.mispredict)
    if (bulkMoveToList) then
        table.insert(bulkMoveToList.parts, self.model)
        table.insert(bulkMoveToList.cframes, newCF)
    else
        self.model.CFrame = newCF
    end
end


BallModel:ModuleSetup()

return BallModel
