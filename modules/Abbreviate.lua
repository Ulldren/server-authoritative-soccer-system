local ABBREVIATIONS = {
	Dvg = 10^69,
	Uvg = 10^66,
	Vg = 10^63,
	Nod = 10^60,
	Ocd = 10^57,
	Spd = 10^54,
	Sxd = 10^51,
	Qid = 10^48,
	Qad = 10^45,
	Td = 10^42,
	Dd = 10^39,
	Ud = 10^36,
	Dc = 10^33,
	No = 10^30,
	Oc = 10^27,
	Sp = 10^24,
	Sx = 10^21,
	Qn = 10^18,
	Qd = 10^15,
	T = 10^12,
	B = 10^9,
	M = 10^6,
	K = 10^3
}
local DECIMAL = 100

return function(number)
	if type(number) ~= "number" 
	or number < 100000 then
		return number
	end

    local abbreviatedNum = number
	local abbreviationChosen = 0

	for abbreviation, num in pairs(ABBREVIATIONS) do
		if number >= num and num > abbreviationChosen then
			local shortNum = number / num
			local intNum = math.floor(shortNum*DECIMAL)/DECIMAL

			abbreviatedNum = tostring(intNum) .. abbreviation
			abbreviationChosen = num
		end
	end

	return abbreviatedNum
end