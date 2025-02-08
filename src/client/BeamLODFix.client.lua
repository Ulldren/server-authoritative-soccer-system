-- Credits to nurokoi

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local QualityFactor = math.max(0, math.min(1, UserSettings().GameSettings.SavedQualityLevel.Value / 10))
local function recalculateBeamSegments()
	for _, beamObject : Beam in CollectionService:GetTagged("Beam") do
		local Attachment0 = beamObject.Attachment0
		local Attachment1 = beamObject.Attachment1
		
		if not Attachment0 or not Attachment1 then continue end
		
		local SegmentCount = beamObject:GetAttribute("DesiredSegments")
		
		if not beamObject:GetAttribute("DesiredSegments") then
			SegmentCount = beamObject.Segments
			beamObject:SetAttribute("DesiredSegments", beamObject.Segments)
		end

		local CameraLocation = workspace.CurrentCamera.CFrame
		local Distance = math.max((CameraLocation.Position - Attachment0.WorldPosition).Magnitude, (CameraLocation.Position - Attachment1.WorldPosition).Magnitude)

		local QualityDistanceScalar = math.clamp((1 - (Distance - 200) / 800) * QualityFactor, 0.1, 1)

		beamObject.Segments = math.ceil(SegmentCount / QualityDistanceScalar)
	end
end

RunService:BindToRenderStep("BeamLOD", Enum.RenderPriority.Camera.Value + 1, recalculateBeamSegments)
while task.wait(1) do
	QualityFactor = math.max(0, math.min(1, UserSettings().GameSettings.SavedQualityLevel.Value / 10))
end