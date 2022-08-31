local lib = LibStub("LibClassicSwingTimerAPI", true)
if not lib then return end

lib.isRetails = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

lib.isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

lib.isBCC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE

lib.isWarth = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_WRATH_OF_THE_LICH_KING

lib.getVersionShortName = function()
	if lib.isRetails() then
		return "RETAILS"
	elseif lib.isClassic then
		return "CLASSIC"
	elseif lib.isBCC() then
		return "BCC"
	elseif lib.isWarth() then
		return "WARTH"
	end
end
