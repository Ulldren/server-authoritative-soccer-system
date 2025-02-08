local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local EffectService

local effectMethods = {}


local EffectController = {
    Name = "EffectController"
}

function EffectController:KnitStart()
    EffectService = Knit.GetService("EffectService")
    EffectService.OnEffectCreated:Connect(function(...)
        self:CreateEffect(...)
    end)
    EffectService.OnReliableEffectCreated:Connect(function(...)
        self:CreateEffect(...)
    end)
end

function EffectController:KnitInit()
    for _, moduleScript in pairs(ReplicatedStorage.ClientEffectModules:GetDescendants()) do
        if not moduleScript:IsA("ModuleScript") then continue end
        if moduleScript.Parent:IsA("ModuleScript") then continue end

        local _, effectModule = xpcall(function()
            return require(moduleScript)
        end, function(errorMessage)
            warn("Failed to load effect: " .. moduleScript.Name .. " error - " .. errorMessage)
        end)

        if not effectModule then continue end
        for effectName, method in pairs(effectModule) do
            effectMethods[effectName] = method
        end
    end
end

function EffectController:CreateEffect(effectName, effectInfo)
    if not effectInfo then
		effectInfo = {}
	end


	local effectMethod = effectMethods[effectName]
	if effectMethod == nil then return end
    xpcall(function()
        effectMethod(effectInfo)
    end, function(errorMessage)
        warn("[EffectController] Effect method error: " .. effectName .. " - " .. errorMessage)
    end)
end

return EffectController