local Players = game:GetService("Players")
local path = game.ReplicatedFirst.Chickynoid

local ChickynoidStyle = {}
ChickynoidStyle.__index = ChickynoidStyle
setmetatable(ChickynoidStyle, require(script.Parent.FieldChickynoid))

function ChickynoidStyle:GetCharacterModel(userId: string, avatarDescription: {}?)
    local srcModel = path.Assets:FindFirstChild("GoalkeeperRig"):Clone()
    srcModel.Parent = game.Lighting --needs to happen so loadAppearance works

    local result, err = pcall(function()
        srcModel:SetAttribute("userid", userId)

        local player = Players:GetPlayerByUserId(userId)
        if player then
            srcModel.Name = player.Name
        end
    
        self:DoStuffToModel(userId, srcModel, avatarDescription)
    end)
    if (result == false) then
        warn("Loading " .. userId .. ":" ..err)
    end

    return srcModel
end

return ChickynoidStyle
