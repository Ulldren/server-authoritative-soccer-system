local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.Promise)

local player = Players.LocalPlayer
local playerGui = player.PlayerGui


local function deepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = deepCopy(v)
		end
		copy[k] = v
	end
	return copy
end


local UIController = {
    Name = "UIController",
    uiModules = {},

    overlayList = {},
}

function UIController:KnitStart()
    for _, module in pairs(script.Overlays:GetChildren()) do
        local uiModule = require(module).new()
        self.uiModules[module.Name] = uiModule
        table.insert(self.overlayList, module.Name)

        local screenGui = uiModule.gui
        screenGui.Parent = playerGui
    end

    local promises = {}
    for moduleName, uiModule in pairs(self.uiModules) do
        table.insert(promises, Promise.new(function(resolve, reject)
            local success, errorMessage = pcall(function()
                uiModule:Init()
            end)
            if success then
                resolve()
            else
                warn(`[UIController] Promise -- Failed to load {moduleName} -- {errorMessage}`)
                reject()
            end
        end))
    end
end

return UIController