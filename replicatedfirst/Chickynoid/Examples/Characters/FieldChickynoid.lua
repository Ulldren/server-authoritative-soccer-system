local Players = game:GetService("Players")
local path = game.ReplicatedFirst.Chickynoid

local ChickynoidStyle = {}
ChickynoidStyle.__index = ChickynoidStyle
setmetatable(ChickynoidStyle, require(script.Parent.HumanoidChickynoid))

function ChickynoidStyle:GetCharacterModel(userId: string, avatarDescription: {}?, humanoidDescription: HumanoidDescription?)
    local srcModel = path.Assets:FindFirstChild("FieldRig"):Clone()
    srcModel.Parent = game.Lighting --needs to happen so loadAppearance works

    local result, err = pcall(function()
        srcModel:SetAttribute("userid", userId)

        local player = Players:GetPlayerByUserId(userId)
        if player then
            srcModel.Name = player.Name
        end
    
        self:DoStuffToModel(userId, srcModel, avatarDescription, humanoidDescription)
    end)
    if (result == false) then
        warn("Loading " .. userId .. ":" ..err)
    end

    return srcModel
end

function ChickynoidStyle:DoStuffToModel(userId: string, srcModel: Model, avatarDescription: {}?, humanoidDescription: HumanoidDescription?)
    local player = Players:GetPlayerByUserId(userId)

    if (string.sub(userId, 1, 1) == "-") then
        userId = string.sub(userId, 2, string.len(userId)) --drop the -
    end

    local torso = srcModel.Torso
    local kitInfo: SurfaceGui = torso:FindFirstChild("KitInfo")
    if kitInfo == nil then
        kitInfo = path.Assets.KitInfo:Clone()
        kitInfo.Parent = torso
    end
    kitInfo.DisplayName.Text = avatarDescription[3]
    kitInfo.PlayerNumber.Text = avatarDescription[4]
    kitInfo.Enabled = true

    srcModel.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

    humanoidDescription = humanoidDescription or game.Players:GetHumanoidDescriptionFromUserId(userId)
    humanoidDescription.Shirt = 0
    humanoidDescription.Pants = 0
    humanoidDescription.GraphicTShirt = 0

    humanoidDescription.Head = 0
    humanoidDescription.LeftArm = 0
    humanoidDescription.LeftLeg = 0
    humanoidDescription.RightArm = 0
    humanoidDescription.RightLeg = 0
    humanoidDescription.Torso = 0

    humanoidDescription.FrontAccessory = ""
    humanoidDescription.BackAccessory = ""
    humanoidDescription.NeckAccessory = ""
    humanoidDescription.ShouldersAccessory = ""
    humanoidDescription.WaistAccessory = ""
    local accessoryList = humanoidDescription:GetAccessories(true)
    for _, accessoryInfo in ipairs(table.clone(accessoryList)) do
        local accessoryWhitelist = {Enum.AccessoryType.Hat, Enum.AccessoryType.Hair, Enum.AccessoryType.Face, Enum.AccessoryType.Eyebrow, Enum.AccessoryType.Eyelash}
        if not table.find(accessoryWhitelist, accessoryInfo.AccessoryType) then
            table.remove(accessoryList, table.find(accessoryList, accessoryInfo))
        end
    end
    humanoidDescription:SetAccessories(accessoryList, true)
    
    srcModel.Humanoid:ApplyDescriptionReset(humanoidDescription)

    local shirt = srcModel:FindFirstChildOfClass("Shirt")
    local pants = srcModel:FindFirstChildOfClass("Pants")
    if not shirt then
        shirt = Instance.new("Shirt")
        shirt.Parent = srcModel
    end
    if not pants then
        pants = Instance.new("Pants")
        pants.Parent = srcModel
    end

    shirt.ShirtTemplate = avatarDescription[1]
    pants.PantsTemplate = avatarDescription[2]
end

return ChickynoidStyle
