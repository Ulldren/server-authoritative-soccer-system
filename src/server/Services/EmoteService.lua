local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterService

local Lib = require(ReplicatedStorage.Lib)
local Trove = require(ReplicatedStorage.Modules.Trove)
local Items = require(ReplicatedStorage.Data.Items)


local EmoteService = {
    Name = "EmoteService",
    Client = {},
}

function EmoteService:KnitStart()
    local services = script.Parent
    CharacterService = require(services.CharacterService)
end

function EmoteService:UseEmote(player: Player, emoteSlot: number)
    -- if not player:GetAttribute("Loaded") then
    --     return
    -- end

    local playerRecord = CharacterService.ServerModule:GetPlayerByUserId(player.UserId)
    if playerRecord == nil or playerRecord.hasBall then
        return
    end

    local selectedEmote = "Dance"
    if selectedEmote ~= nil and Lib.isOnHiddenCooldown(player, "EmoteCooldown") then
        return
    end


    Lib.setHiddenCooldown(player, "EmoteCooldown", 1)


    local emoteInfo = Items.Emote[selectedEmote]
    if emoteInfo == nil then
        return
    end


    Lib.setCooldown(player, "EmoteCooldown", 1)

    local function setNewEmote(newEmote)
        local emoteInfo = Items.Emote[newEmote]
        player:SetAttribute("EmoteData", HttpService:JSONEncode({
            newEmote, 
            Lib.generateShortGUID(), 
            emoteInfo and emoteInfo.ShiftLockDisabled, 
            emoteInfo and emoteInfo.CanWalk
        }))
    end
    setNewEmote(selectedEmote)


    if selectedEmote == nil then
        return
    end

    local trove = Trove.new()
    trove:AttachToInstance(player)
    trove:Connect(player:GetAttributeChangedSignal("EmoteData"), function()
        trove:Destroy()
    end)
    trove:Connect(CharacterService.BallOwnerChanged, function(ownerId)
        if ownerId ~= player.UserId then
            return
        end
        setNewEmote(nil)
        trove:Destroy()
    end)

    player:SetAttribute("EmoteWalkReset", nil)
    if not emoteInfo.CanWalk then
        player:SetAttribute("EmoteWalkReset", os.clock() + 1)
    end
end

function EmoteService:EndEmote(player: Player, emoteGUID: string)
    local emoteData = player:GetAttribute("EmoteData")
    if emoteData == nil then
        return
    end

    emoteData = HttpService:JSONDecode(emoteData)
    local emote = emoteData[1]
    if emote == nil then
        return
    end
    if emoteGUID and emoteGUID ~= emoteData[2] then
        return
    end

    local function setNewEmote(newEmote)
        local emoteInfo = Items.Emote[newEmote]
        player:SetAttribute("EmoteData", HttpService:JSONEncode({newEmote, Lib.generateShortGUID(), emoteInfo and emoteInfo.ShiftLockDisabled}))
    end
    setNewEmote(nil)
end

-- Client Events
function EmoteService.Client:EndEmote(...)
    self.Server:EndEmote(...)
end

function EmoteService.Client:UseEmote(...)
    self.Server:UseEmote(...)
end

return EmoteService