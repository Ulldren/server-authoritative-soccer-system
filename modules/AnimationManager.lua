local ContentProvider = game:GetService("ContentProvider")


local function SetRecursive(tbl, call)
    local newTbl = {}
    for i, v in pairs(tbl) do
        if type(v) == "table" then
            newTbl[i] = SetRecursive(v, call)
            continue
        end
        newTbl[i] = call(v)
    end

    return newTbl
end

local function SetRecursiveFolder(folder, call)
    local newTbl = {}
    for _, v in pairs(folder:GetChildren()) do
        if v:IsA("Folder") then
            newTbl[v.Name] = SetRecursiveFolder(v, call)
            continue
        end
        newTbl[v.Name] = call(v)
    end

    return newTbl
end

local function LoadAnimations(animator: Animator, animations)
    if type(animations) == "table" then
        
        return SetRecursive(animations, function(animId)
            local animObject = Instance.new("Animation")
            animObject.AnimationId = "rbxassetid://" .. animId
            task.spawn(function()
                ContentProvider:PreloadAsync({animObject})
            end)
            return animator:LoadAnimation(animObject)
        end)
    elseif typeof(animations) == "Instance" and animations:IsA("Folder") then 
        
        return SetRecursiveFolder(animations, function(animObject)
            task.spawn(function()
                ContentProvider:PreloadAsync({animObject})
            end)
    
            return animator:LoadAnimation(animObject)
        end)
    else
        return warn("[Animation Manager] Did not provide a folder or table!")
    end
end


local AnimationManager = {}
AnimationManager.__index = AnimationManager

function AnimationManager.new(character, animations)
    local self = setmetatable({}, AnimationManager)
    self.character = character

    local animatorParent
    local start = time()
    while animatorParent == nil do
        if time() - start > 50 then
            return warn("[AnimationManager] Humanoid doesn't exist for character: " .. character.Name)
        end
        animatorParent = character:FindFirstChild("Humanoid") or character:FindFirstChild("AnimationController")
        if animatorParent == nil then
            task.wait()
        end
    end
    self.animator = animatorParent:WaitForChild("Animator")

    self.animations = LoadAnimations(self.animator, animations)

    return self
end

function AnimationManager:StopAll(ignoreList: {string}?)
    SetRecursive(self.animations, function(animObject)
        if ignoreList and table.find(ignoreList, animObject.Name) then
            return
        end
        animObject:Stop()
    end)
end

function AnimationManager:SetNewAnimation(animName: string, animObject)
    task.spawn(function()
        ContentProvider:PreloadAsync({animObject})
    end)

    self.animations[animName] = self.animator:LoadAnimation(animObject)
end

function AnimationManager:FindAnimation(animationToFind: string) -- Recursive
    for _, subsection: {AnimationTrack} in pairs(self.animations) do
        if type(subsection) ~= "table" then continue end
        for name, animationTrack in pairs(subsection) do
            if name == animationToFind then
                return animationTrack
            end
        end
    end
end

function AnimationManager:Destroy()
    SetRecursive(self.animations, function(animObject)
        animObject:Stop()
        animObject:Destroy()
    end)
    self.animations = nil
end

return AnimationManager