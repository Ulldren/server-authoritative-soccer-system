local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)


local EffectService = {
    Name = "EffectService",
    Client = {
        OnEffectCreated = Knit.CreateUnreliableSignal(),
        OnReliableEffectCreated = Knit.CreateSignal(),
    },
}

type EffectService = typeof(EffectService)

function EffectService:CreateEffect(eventName: string, effectInfo: {any}, playerToIgnore: Player?)
    if playerToIgnore then
        self.Client.OnEffectCreated:FireExcept(playerToIgnore, eventName, effectInfo)
    else
        self.Client.OnEffectCreated:FireAll(eventName, effectInfo)
    end
end

function EffectService:CreateClientEffect(player: Player, eventName: string, effectInfo: {any})
    self.Client.OnEffectCreated:Fire(player, eventName, effectInfo)
end

function EffectService:CreateReliableEffect(eventName: string, effectInfo: {any})
    self.Client.OnReliableEffectCreated:FireAll(eventName, effectInfo)
end

function EffectService:CreateReliableClientEffect(player: Player, eventName: string, effectInfo: {any})
    self.Client.OnReliableEffectCreated:Fire(player, eventName, effectInfo)
end

return EffectService