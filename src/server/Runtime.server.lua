local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)


for _, serviceModule: ModuleScript in pairs(script.Parent.Services:GetChildren()) do
    if not serviceModule:IsA("ModuleScript") then continue end
    local service = require(serviceModule)
    Knit.CreateService(service)
end
Knit.Start()