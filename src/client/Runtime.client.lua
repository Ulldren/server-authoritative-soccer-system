local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

for _, controllerModule: ModuleScript in pairs(script.Parent.Controllers:GetChildren()) do
    if not controllerModule:IsA("ModuleScript") then continue end
    local controller = require(controllerModule)
    Knit.CreateController(controller)
end
Knit.Start()