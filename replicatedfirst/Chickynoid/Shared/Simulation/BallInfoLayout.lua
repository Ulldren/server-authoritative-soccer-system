local module = {}
 

local CrunchTable = require(script.Parent.Parent.Vendor.CrunchTable)

function module:GetCommandLayout()
	
	if (self.commandLayout == nil) then
		self.commandLayout = CrunchTable:CreateLayout()	
			
		self.commandLayout:Add("tackledEnemy", CrunchTable.Enum.UBYTE)
        self.commandLayout:Add("skill", CrunchTable.Enum.FLOAT)

        self.commandLayout:Add("claimPos", CrunchTable.Enum.VECTOR3)

        self.commandLayout:Add("sGuid", CrunchTable.Enum.INT32)
        self.commandLayout:Add("sType", CrunchTable.Enum.UBYTE)
        self.commandLayout:Add("sPower", CrunchTable.Enum.FLOAT)
        self.commandLayout:Add("sDirection", CrunchTable.Enum.VECTOR3)
        self.commandLayout:Add("sCurveFactor", CrunchTable.Enum.FLOAT)

        self.commandLayout:Add("dGuid", CrunchTable.Enum.INT32)
        self.commandLayout:Add("dType", CrunchTable.Enum.UBYTE)
        self.commandLayout:Add("dPower", CrunchTable.Enum.FLOAT)
        self.commandLayout:Add("dDirection", CrunchTable.Enum.VECTOR3)
        self.commandLayout:Add("dCurveFactor", CrunchTable.Enum.FLOAT)
        self.commandLayout:Add("dServerDeflect", CrunchTable.Enum.FLOAT)

        self.commandLayout:Add("enteredGoal", CrunchTable.Enum.UBYTE)
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
