local RunService = game:GetService("RunService")
--!native
local BallData = {}
BallData.__index = BallData

local EPSILION = 0.00001
local mathUtils = require(script.Parent.MathUtils)
local Quaternion = require(script.Parent.Quaternion)



local function Lerp(a, b, frac)
    return a:Lerp(b, frac)
end

local function AngleLerp(a, b, frac)
    return mathUtils:LerpAngle(a, b, frac)
end

local function NumberLerp(a, b, frac)
    return (a * (1 - frac)) + (b * frac)
end

local function Raw(_a, b, _frac)
    return b
end

local MAX_FLOAT16 = math.pow(2, 16)
local function ValidateFloat16(float)
    return math.clamp(float, -MAX_FLOAT16, MAX_FLOAT16)
end

local MAX_BYTE = 255
local function ValidateByte(byte)
    return math.clamp(byte, 0, MAX_BYTE)
end

local function ValidateVector3(input)
    return input
end

local function ValidateNumber(input)
    return input
end

local function CompareVector3(a, b)
    if math.abs(a.x - b.x) > EPSILION or math.abs(a.y - b.y) > EPSILION or math.abs(a.z - b.z) > EPSILION then
        return false
    end
    return true
end

local function CompareByte(a, b)
    return a == b
end

local function CompareFloat16(a, b)
    return a == b
end

local function CompareNumber(a, b)
    return a == b
end

local function WriteVector3(buf : buffer, offset : number, value : Vector3 ) : number
	buffer.writef32(buf, offset, value.X)
	offset+=4
	buffer.writef32(buf, offset, value.Y)
	offset+=4
	buffer.writef32(buf, offset, value.Z)
	offset+=4
	return offset
end

local function ReadVector3(buf : buffer, offset : number) 
	local x = buffer.readf32(buf, offset)
	offset+=4
	local y = buffer.readf32(buf, offset)
	offset+=4
	local z = buffer.readf32(buf, offset)
	offset+=4
	return Vector3.new(x,y,z), offset
end

local function WriteFloat32(buf : buffer, offset : number, value : number ) : number
	buffer.writef32(buf, offset, value)
	offset+=4
	return offset
end

local function ReadFloat32(buf : buffer, offset : number) 
	local x = buffer.readf32(buf, offset)
	offset+=4
	return x, offset
end

local function WriteByte(buf : buffer, offset : number, value : number ) : number
	buffer.writeu8(buf, offset, value)
	offset+=1
	return offset
end

local function ReadByte(buf : buffer, offset : number) 
	local x = buffer.readu8(buf, offset)
	offset+=1
	return x, offset
end

local function WriteFloat16(buf : buffer, offset : number, value : number ) : number
	
	local sign = value < 0
	value = math.abs(value)

	local mantissa, exponent = math.frexp(value)

	if value == math.huge then
		if sign then
			buffer.writeu8(buf,offset,252)-- 11111100
			offset+=1
		else
			buffer.writeu8(buf,offset,124) -- 01111100
			offset+=1
		end
		buffer.writeu8(buf,offset,0) -- 00000000
		offset+=1
		return offset
	elseif value ~= value or value == 0 then
		buffer.writeu8(buf,offset,0)
		offset+=1
		buffer.writeu8(buf,offset,0)
		offset+=1
		return offset
	elseif exponent + 15 <= 1 then -- Bias for halfs is 15
		mantissa = math.floor(mantissa * 1024 + 0.5)
		if sign then
			buffer.writeu8(buf,offset,(128 + bit32.rshift(mantissa, 8))) -- Sign bit, 5 empty bits, 2 from mantissa
			offset+=1
		else
			buffer.writeu8(buf,offset,(bit32.rshift(mantissa, 8)))
			offset+=1
		end
		buffer.writeu8(buf,offset,bit32.band(mantissa, 255)) -- Get last 8 bits from mantissa
		offset+=1
		return offset
	end

	mantissa = math.floor((mantissa - 0.5) * 2048 + 0.5)

	-- The bias for halfs is 15, 15-1 is 14
	if sign then
		buffer.writeu8(buf,offset,(128 + bit32.lshift(exponent + 14, 2) + bit32.rshift(mantissa, 8)))
		offset+=1
	else
		buffer.writeu8(buf,offset,(bit32.lshift(exponent + 14, 2) + bit32.rshift(mantissa, 8)))
		offset+=1
	end
	buffer.writeu8(buf,offset,bit32.band(mantissa, 255))
	offset+=1
	
	return offset
end

local function ReadFloat16(buf : buffer, offset : number) 

	local b0 = buffer.readu8(buf, offset)
	offset+=1
	local b1 = buffer.readu8(buf, offset)
	offset+=1
	
	local sign = bit32.btest(b0, 128)
	local exponent = bit32.rshift(bit32.band(b0, 127), 2)
	local mantissa = bit32.lshift(bit32.band(b0, 3), 8) + b1

	if exponent == 31 then --2^5-1
		if mantissa ~= 0 then
			return (0 / 0), offset
		else
			return (sign and -math.huge or math.huge), offset
		end
	elseif exponent == 0 then
		if mantissa == 0 then
			return 0, offset
		else
			return (sign and -math.ldexp(mantissa / 1024, -14) or math.ldexp(mantissa / 1024, -14)), offset
		end
	end

	mantissa = (mantissa / 1024) + 1

	return (sign and -math.ldexp(mantissa, exponent - 15) or math.ldexp(mantissa, exponent - 15)), offset
end

function BallData:SetIsResimulating(bool)
    self.isResimulating = bool
end

function BallData:ModuleSetup()
    BallData.methods = {}
    BallData.methods["Vector3"] = {
        write = WriteVector3,
        read = ReadVector3,
        validate = ValidateVector3,
        compare = CompareVector3,
    }
    BallData.methods["Float16"] = {
        write = WriteFloat16,
        read = ReadFloat16,
        validate = ValidateFloat16,
        compare = CompareFloat16,
    }
    BallData.methods["Float32"] = {
        write = WriteFloat32,
        read = ReadFloat32,
        validate = ValidateNumber,
        compare = CompareNumber,
    }

    BallData.methods["Byte"] = {
        write = WriteByte,
        read = ReadByte,
        validate = ValidateByte,
        compare = CompareByte,
    }

	BallData.packFunctions = {
        pos = "Vector3",
    }
	
	BallData.keys =
	{
		"pos",
	}
	
	
	BallData.lerpFunctions = {
        pos = Lerp,
	}
	
end

function BallData.new()
    local self = setmetatable({
        serialized = {
            pos = Vector3.zero,
        },

        --Be extremely careful about having any kind of persistant nonserialized data!
        --If in doubt, stick it in the serialized!
        isResimulating = false,
        targetPosition = Vector3.zero,
        
    }, BallData)

    return self
end

--This smoothing is performed on the server only.
--On client, use GetPosition
function BallData:SmoothPosition(deltaTime, smoothScale)
    if (smoothScale == 1 or smoothScale == 0)  then
        self.serialized.pos = self.targetPosition
    else
        self.serialized.pos = mathUtils:SmoothLerp(self.serialized.pos, self.targetPosition, smoothScale, deltaTime)
    end
end

function BallData:ClearSmoothing()
    self.serialized.pos = self.targetPosition
end

--Sets the target position
function BallData:SetTargetPosition(pos, teleport)
    self.targetPosition = pos
    -- if (teleport) then
        self:ClearSmoothing()
    -- end
end
 
function BallData:GetPosition()
    return self.serialized.pos
end

function BallData:Serialize()
    local ret = {}
    --Todo: Add bitpacking
    for key, _ in pairs(self.serialized) do
        ret[key] = self.serialized[key]
    end

    return ret
end

function BallData:SerializeToBitBuffer(previousData, buf : buffer, offset: number)
	
	if (previousData == nil) then
		return self:SerializeToBitBufferFast(buf, offset)
	end
	
	local contentWritePos = offset
	offset += 2 --2 bytes contents
	
	local contentBits = 0
	local bitIndex = 0

	if previousData == nil then
		
		--Slow path that wont be hit
		contentBits = 0xFFFF
		
		for keyIndex, key in BallData.keys do
			local value = self.serialized[key]
			local func = BallData.methods[BallData.packFunctions[key]]
			offset = func.write(buf, offset, value)
		end
    else
		--calculate bits
		for keyIndex, key in BallData.keys do
			local value = self.serialized[key]
			local func = BallData.methods[BallData.packFunctions[key]]
            
            local valueA = previousData.serialized[key]
            local valueB = value

            if func.compare(valueA, valueB) == false then
				contentBits = bit32.bor(contentBits, bit32.lshift(1, bitIndex))
           		offset = func.write(buf, offset, value)
            end
			bitIndex += 1
		end
		
	end
	
	buffer.writeu16(buf, contentWritePos, contentBits)
	return offset
end


function BallData:SerializeToBitBufferFast(buf : buffer, offset: number)

	local contentWritePos = offset
	offset += 2 --2 bytes contents

	local contentBits = 0xFFFF
	
	local serialized = self.serialized
	
	offset = WriteVector3(buf, offset, serialized.pos)

	buffer.writeu16(buf, contentWritePos, contentBits)
	return offset
end



function BallData:DeserializeFromBitBuffer(buf : buffer, offset: number)
	
	local contentBits = buffer.readu16(buf, offset)
	offset+=2
	
	local bitIndex = 0
	for keyIndex, key in BallData.keys do
		local value = self.serialized[key]
		local hasBit = bit32.band(contentBits, bit32.lshift(1, bitIndex)) > 0
		
        if hasBit then
            local func = BallData.methods[BallData.packFunctions[key]]
            self.serialized[key],offset  = func.read(buf, offset)
		end
		bitIndex += 1
	end
	return offset
end

function BallData:CopySerialized(otherSerialized)
    for key, value in pairs(otherSerialized) do
        self.serialized[key] = value
    end
end

function BallData:Interpolate(dataA, dataB, fraction)
    local dataRecord = {}
    for key, _ in pairs(dataA) do
		if key == "pos" and dataA.pos == Vector3.zero or dataB.pos == Vector3.zero then
			dataRecord[key] = dataB.pos
			continue
		end

		local func = BallData.lerpFunctions[key]
        if func == nil then
            dataRecord[key] = dataB[key]
        else
            dataRecord[key] = func(dataA[key], dataB[key], fraction)
        end
    end

    return dataRecord
end

BallData:ModuleSetup()
return BallData
