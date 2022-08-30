local _, Private = ...

Private.isRetails = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

Private.isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

Private.isBCC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE

Private.isWarth = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_WRATH_OF_THE_LICH_KING

Private.getVersionShortName = function()
	if Private.isRetails() then
		return "RETAILS"
	elseif Private.isClassic then
		return "CLASSIC"
	elseif Private.isBCC() then
		return "BCC"
	elseif Private.isWarth() then
		return "WARTH"
	end
end
