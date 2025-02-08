local module = {}
 

local CrunchTable = require(script.Parent.Parent.Vendor.CrunchTable)

function module:GetCommandLayout()
	
	if (self.commandLayout == nil) then
		self.commandLayout = CrunchTable:CreateLayout()
			
		self.commandLayout:Add("localFrame",CrunchTable.Enum.INT32)
		-- self.commandLayout:Add("serverTime", CrunchTable.Enum.FLOAT)
		self.commandLayout:Add("deltaTime", CrunchTable.Enum.FLOAT)
	end
	
	return self.commandLayout	
end

function module:EncodeCommand(command)
	return CrunchTable:BinaryEncodeTable(command, self:GetCommandLayout())
end

function module:DecodeCommand(command)
	return CrunchTable:BinaryDecodeTable(command, self:GetCommandLayout()) 
end

return module
