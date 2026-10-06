-- Swing Test Log: records LibClassicSwingTimerAPI callbacks and combat context
-- into SwingTestLogDB, one session per login/reload. Review the file at
-- WTF\Account\<account>\SavedVariables\SwingTestLog.lua (written on /reload or logout).
-- Runs on Classic Era and WoW: Forever. Forever refuses CLEU, so there the own
-- swings and parries come from PLAYER_SWING and UNIT_COMBAT (the library's own
-- Forever sources); on Forever aura presence is probed by name
-- (C_UnitAuras.GetAuraDataBySpellName) on UNIT_AURA, combat transitions and
-- /stl aura - the 2026-10-04 aura-presence investigation. The library may be
-- standalone or embedded (4everSwingTimer on Forever), so it is looked up at
-- PLAYER_LOGIN.

local LIB_NAME = "LibClassicSwingTimerAPI"
local MAX_ENTRIES = 5000
local MAX_SESSIONS = 20
local HANDS = { "mainhand", "offhand", "ranged" }
local SWING_TYPES = { [0] = "mainhand", [1] = "offhand", [2] = "ranged" }

local GetTime, date, format, select, tostring = GetTime, date, format, select, tostring
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local issecretvalue = issecretvalue
local pcall = pcall
-- Nil-guarded 12.x namespaces: a removed global upvalues to nil, so every use
-- below checks the local first (same rule as the library and the addon).
local GetAuraByName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local GetAuraByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local IsCurrentSpell = C_Spell and C_Spell.IsCurrentSpell
local GetAuraSecrecy = C_Secrets and C_Secrets.GetSpellAuraSecrecy
local GetAuraCount = C_UnitAuras and C_UnitAuras.GetAuraCount
local GetComboPoints = GetComboPoints
local oracleBar
local oracleAnchor
local DEFAULT_WATCH = { "Slice and Dice" }
local QUEUED_SPELLS = { 78, 845, 2973, 6807 } -- Heroic Strike, Cleave, Raptor Strike, Maul

local _, _, _, interface = GetBuildInfo()
local isForever = interface >= 16000 and interface < 20000

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(spellID)
	return (GetSpellInfo(spellID))
end

local lib, libMinor
local playerGUID
local session

local function str(x)
	if issecretvalue and issecretvalue(x) then
		return "<secret>"
	end
	return tostring(x)
end

local function num(x)
	if issecretvalue and issecretvalue(x) then
		return "<secret>"
	end
	if type(x) == "number" then
		return format("%.3f", x)
	end
	return tostring(x)
end

local function log(kind, ...)
	if not session then
		return
	end
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = str((select(i, ...)))
	end
	local line = format("%s %10.3f %-9s %s", date("%H:%M:%S"), GetTime(), kind, table.concat(parts, " "))
	local entries = session.entries
	if #entries < MAX_ENTRIES then
		entries[#entries + 1] = line
	else
		session.dropped = (session.dropped or 0) + 1
	end
	if SwingTestLogDB.echo then
		print("|cff88ccff[STL]|r " .. line)
	end
end

local function GetWatch()
	if type(SwingTestLogDB.watch) == "table" and #SwingTestLogDB.watch > 0 then
		return SwingTestLogDB.watch
	end
	return DEFAULT_WATCH
end

-- The by-name aura probe (M1_SESSION_SCRIPT B4): one log line per watched
-- name. pcall catches the "Auras cannot be accessed when secret" throw, so
-- every outcome - ERROR, nil, or a table with its secrecy flags inline - is
-- the verdict evidence. num() masks secret numbers; the secDur/secExp flags
-- carry the classification.
local function AuraProbe(reason)
	if not GetAuraByName then
		return
	end
	local watch = GetWatch()
	for i = 1, #watch do
		local name = watch[i]
		local ok, d = pcall(GetAuraByName, "player", name, "HELPFUL")
		if not ok then
			log("AURA", reason, name, "ERROR", str(d))
		elseif type(d) ~= "table" then
			log("AURA", reason, name, "nil")
		else
			log("AURA", reason, name, "id=" .. str(d.spellId), "apps=" .. str(d.applications),
				"dur=" .. num(d.duration), "exp=" .. num(d.expirationTime),
				"secDur=" .. str(issecretvalue and issecretvalue(d.duration)),
				"secExp=" .. str(issecretvalue and issecretvalue(d.expirationTime)),
				"secrecy=" .. str(GetAuraSecrecy and GetAuraSecrecy(d.spellId)))
		end
	end
end


-- The count probe (UNIT_AURA edge-inference gate, findings 7.1 item 4): if
-- GetAuraCount answers a plain number mid-combat, every UNIT_AURA edge gets a
-- direction (+1/-1) and edge attribution gains its corroborator. num() masks
-- a secret count; the flag carries the verdict.
local function AuraCount(reason)
	if not GetAuraCount then
		return
	end
	local ok, c = pcall(GetAuraCount, "player", "HELPFUL")
	if not ok then
		log("COUNT", reason, "ERROR", str(c))
	else
		log("COUNT", reason, num(c), "sec=" .. str(issecretvalue and issecretvalue(c)))
	end
end

-- Combo points mid-combat (the second edge-inference gate, findings 7.1


-- The value-sink oracle probe (findings 7.1 item 4 note, 2026-10-05): the
-- 12.x notes claim widget sinks accept secret values (the client unwraps
-- them in C; Lua never sees the number - the ForeverSwing engine-timer
-- fill is this technique). If SetValue accepts a raw secret and the fill
-- GEOMETRY reads plain, the width ratio recovers the number: an oracle for
-- mid-combat speeds. The transition-parity design does NOT depend on it
-- (a closable loophole class - 12.0.1 closed the GetValue path); this
-- probe only measures. Run mid-combat.
local function Oracle()
	if not UnitAttackSpeed then
		print("|cff88ccff[STL]|r no UnitAttackSpeed on this client")
		return
	end
	local a = UnitAttackSpeed("player")
	if not oracleBar then
		oracleBar = CreateFrame("StatusBar", nil, UIParent)
		oracleBar:SetSize(200, 8)
		oracleBar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -400, -400)
		oracleBar:SetStatusBarTexture([[Interface\Buttons\WHITE8X8]])
		oracleBar:Show()
	end
	oracleBar:SetMinMaxValues(0, 10)
	local s = issecretvalue
	local ok, err = pcall(oracleBar.SetValue, oracleBar, a)
	if not ok then
		log("ORACLE", "SetValue ERROR", str(err))
		print("|cff88ccff[STL]|r oracle: SetValue rejected the value")
		return
	end
	if not (s and s(a)) then
		log("ORACLE", "input=plain", num(a), "baseline")
		print("|cff88ccff[STL]|r oracle: input is plain (out of combat baseline); run mid-combat for the probe")
		return
	end
	-- Sink verdict: SetValue ACCEPTED the secret (build 70205).
	log("ORACLE", "sink=ACCEPTED", "input=secret")
	local fill = oracleBar:GetStatusBarTexture()
	local fw = fill and fill:GetWidth() or 0
	local gv = oracleBar:GetValue()
	log("ORACLE", "fillw=" .. num(fw), "fillwSec=" .. str(s and s(fw)),
		"getValue=" .. num(gv), "gvSec=" .. str(s and s(gv)))
	if not (s and s(fw)) then
		-- Unexpected: the fill geometry reads plain; derive directly.
		local bw = oracleBar:GetWidth()
		local derived = (type(fw) == "number" and type(bw) == "number" and bw > 0) and (fw / bw * 10) or nil
		log("ORACLE", "derived=" .. num(derived), "derivedSec=" .. str(s and s(derived)))
		print("|cff88ccff[STL]|r oracle logged: derived " .. num(derived))
		return
	end
	-- Direct geometry is WRAPPED (build 70205: the fill width itself is
	-- secret - a stronger lockdown than the 12.0.1 lore). The remaining
	-- path: the layout engine positions a frame anchored to the fill's
	-- right edge in C; if that frame's geometry reads plain, the ratio
	-- recovers the number.
	if not oracleAnchor then
		oracleAnchor = CreateFrame("Frame", nil, oracleBar)
		oracleAnchor:SetPoint("LEFT", fill, "RIGHT")
		oracleAnchor:SetSize(1, 1)
	end
	local ax = oracleAnchor:GetLeft()
	local barLeft = oracleBar:GetLeft()
	local barW = oracleBar:GetWidth()
	log("ORACLE", "anchorLeft=" .. num(ax), "anchorSec=" .. str(s and s(ax)),
		"barLeft=" .. num(barLeft), "barLeftSec=" .. str(s and s(barLeft)))
	if type(ax) == "number" and not (s and s(ax))
		and type(barLeft) == "number" and not (s and s(barLeft))
		and type(barW) == "number" and barW > 0 then
		local derived = (ax - barLeft) / barW * 10
		log("ORACLE", "ANCHOR-ORACLE derived=" .. num(derived), "derivedSec=" .. str(s and s(derived)))
		print("|cff88ccff[STL]|r anchor oracle derived " .. num(derived))
	else
		log("ORACLE", "anchor path closed too")
		print("|cff88ccff[STL]|r anchor path closed too - geometry fully wrapped")
	end
end
-- The engine-drawn cooldown icon (SinkView, timeline concept 2026-10-05):
-- the oracle closed every read path but never looked at the screen - its
-- bar sat off-screen. This draws the technique where the tester can see it:
-- a 10 s StatusBar fed the cooldown's secret remaining time every frame, an
-- icon anchored to the fill's right edge, and two engine-drawn references
-- from the same DurationObject - a Cooldown swipe and a FontString sink.
-- PASS: mid-combat the icon slides right to left along the 0-10 s ticks,
-- agrees with the text, and reaches the left edge as the swipe ends.
-- Display-only: nothing here reads the geometry back.
local SINK_WINDOW = 10
local SINK_WIDTH = 300
local AUTO_ATTACK = { [6603] = true, [6803] = true } -- classic / Forever toggle IDs
local GetCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
local lastCastSpell
local sinkView

local function SinkViewCooldown(f)
	local dur = GetCooldownDuration(f.spell)
	if not dur or not f.cd.SetCooldownFromDurationObject then
		return
	end
	local ok, err = pcall(f.cd.SetCooldownFromDurationObject, f.cd, dur)
	if not ok and not f.cdErr then
		f.cdErr = true
		log("SINKVIEW", "SetCooldownFromDurationObject ERROR", str(err))
	end
end

local function SinkViewUpdate(f)
	local dur = GetCooldownDuration(f.spell)
	if not dur then
		return
	end
	local remaining = dur:GetRemainingDuration()
	local secret = issecretvalue and issecretvalue(remaining) or false
	if secret ~= f.lastSecret then
		f.lastSecret = secret
		log("SINKVIEW", "remaining=" .. (secret and "secret" or "plain"), "spell=" .. f.spell)
	end
	local ok, err = pcall(f.bar.SetValue, f.bar, remaining)
	if not ok and not f.valueErr then
		f.valueErr = true
		log("SINKVIEW", "SetValue ERROR", str(err))
	end
	if secret then
		ok, err = pcall(f.remainText.SetText, f.remainText, remaining)
		if not ok and not f.textErr then
			f.textErr = true
			log("SINKVIEW", "SetText ERROR", str(err))
		end
	else
		f.remainText:SetText(format("%.1f", remaining))
	end
end

local function SinkViewBuild()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(SINK_WIDTH + 64, 72)
	f:SetPoint("TOP", UIParent, "TOP", 0, -160)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -6)
	f.remainText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.remainText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -54, -6)

	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetSize(SINK_WIDTH, 20)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -22)
	bar:SetStatusBarTexture([[Interface\Buttons\WHITE8X8]])
	bar:SetStatusBarColor(0.48, 0.25, 0.72, 0.35)
	bar:SetMinMaxValues(0, SINK_WINDOW)
	bar:SetValue(0)
	f.bar = bar
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(1, 1, 1, 0.08)

	for s = 0, SINK_WINDOW, 2 do
		local tick = bar:CreateTexture(nil, "OVERLAY")
		tick:SetColorTexture(1, 1, 1, 0.5)
		tick:SetSize(1, 6)
		tick:SetPoint("TOP", bar, "BOTTOMLEFT", s / SINK_WINDOW * SINK_WIDTH, 0)
		local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOP", tick, "BOTTOM", 0, -1)
		label:SetText(s)
	end

	-- The technique under test: the layout engine places the icon from the
	-- secret fill width.
	f.icon = bar:CreateTexture(nil, "OVERLAY")
	f.icon:SetSize(20, 20)
	f.icon:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")

	-- Reference: the native swipe from the same DurationObject.
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetSize(36, 36)
	f.cd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -18)
	f.cd:SetHideCountdownNumbers(false)
	f.cdIcon = f:CreateTexture(nil, "ARTWORK")
	f.cdIcon:SetAllPoints(f.cd)

	f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	f:SetScript("OnEvent", SinkViewCooldown)
	f:SetScript("OnUpdate", SinkViewUpdate)
	return f
end

local function SinkView(arg)
	if arg == "off" then
		if sinkView and sinkView:IsShown() then
			sinkView:Hide()
			log("SINKVIEW", "stop")
		end
		print("|cff88ccff[STL]|r sink view hidden")
		return
	end
	if not GetCooldownDuration then
		log("SINKVIEW", "no C_Spell.GetSpellCooldownDuration on this client")
		print("|cff88ccff[STL]|r no C_Spell.GetSpellCooldownDuration on this client")
		return
	end
	local spell = tonumber(arg) or lastCastSpell
	if not spell then
		print("|cff88ccff[STL]|r cast the spell once first, or /stl sinkview <spellID>")
		return
	end
	sinkView = sinkView or SinkViewBuild()
	sinkView.spell = spell
	sinkView.lastSecret, sinkView.valueErr, sinkView.textErr, sinkView.cdErr = nil, nil, nil, nil
	local name = GetSpellName(spell) or "?"
	local texture = GetSpellTexture(spell)
	sinkView.title:SetText(format("sink view: %s (%d)", name, spell))
	sinkView.icon:SetTexture(texture)
	sinkView.cdIcon:SetTexture(texture)
	SinkViewCooldown(sinkView)
	sinkView:Show()
	log("SINKVIEW", "start", "spell=" .. spell, name)
	print(format("|cff88ccff[STL]|r sink view on %s (%d) - drag to move, /stl sinkview off to hide", name, spell))
end

-- Timeline probes (4everActionTimeline docs/PROBE_SESSION.md, probes 1-15).
-- Every read goes through num()/str(), so a secret logs as <secret> and the
-- line itself is the verdict evidence. Each API call is pcall-wrapped and
-- nothing does math on a value before checking that it is plain.
local GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local IsSpellUsable = C_Spell and C_Spell.IsSpellUsable
local GetSpellInfoTable = C_Spell and C_Spell.GetSpellInfo
local GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
local IsEventValid = C_EventUtils and C_EventUtils.IsEventValid
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local GetShapeshiftFormID, GetShapeshiftForm = GetShapeshiftFormID, GetShapeshiftForm
local UnitPower, UnitPowerType = UnitPower, UnitPowerType
local GCD_SPELL = 61304 -- the modern client's GCD spell; may not exist on Forever
local CD_WATCH_INTERVAL = 0.2
local ATLAS_VIEW_COLUMNS = 8
local ATLAS_VIEW_CELL = 48
-- docs/ASSETS.md in 4everActionTimeline: every atlas the Native skin uses.
local TIMELINE_ATLASES = {
	"combattimeline-line-left", "combattimeline-line-right", "combattimeline-line-break-mask",
	"combattimeline-cooldown-divider", "combattimeline-pip", "combattimeline-line-icontrail",
	"UI-HUD-CoolDownManager-Mask", "UI-HUD-CoolDownManager-IconOverlay",
	"UI-HUD-CoolDownManager-Bar", "UI-HUD-CoolDownManager-Bar-BG",
	"combattimeline-fx-pause", "combattimeline-fx-pause-icon", "combattimeline-fx-queued",
	"cast_standard_pipglow",
}
-- Edge-clamp chevron guesses (retail names); /stl atlas show <names> adds more.
local CHEVRON_CANDIDATES = {
	"uitools-icon-chevron-right", "uitools-icon-chevron-left", "common-icon-forwardarrow",
	"common-icon-backarrow", "NPE_ArrowRight", "NPE_ArrowLeft",
}
-- Functions the timeline would cache into upvalues (AGENTS.md: verify first).
local API_PATHS = {
	"C_SpellBook.GetNumSpellBookSkillLines", "C_SpellBook.GetSpellBookSkillLineInfo",
	"C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.GetSpellBookItemName",
	"C_SpellBook.FindSpellBookSlotForSpell", "C_SpellBook.IsSpellKnown",
	"GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemInfo", "IsSpellKnown", "FindBaseSpellByID",
	"C_Spell.GetSpellCooldown", "C_Spell.GetSpellCooldownDuration", "C_Spell.IsSpellUsable",
	"C_Spell.GetSpellInfo", "C_Spell.GetSpellTexture", "C_Spell.IsCurrentSpell", "C_Spell.IsAutoRepeatSpell",
	"UnitCastingInfo", "UnitChannelInfo", "GetShapeshiftFormID", "GetShapeshiftForm",
	"GetInventoryItemTexture", "C_Texture.GetAtlasInfo", "C_CooldownViewer.GetCooldownViewerCategorySet",
	"Settings.RegisterVerticalLayoutCategory", "Settings.RegisterProxySetting", "Settings.CreateDropdown",
	"EventRegistry.RegisterCallback", "EditModeManagerFrame.IsEditModeActive", "MenuUtil.CreateContextMenu",
	"ScriptAnimationUtil.ShakeFrame", "debugprofilestop", "C_Timer.NewTicker", "C_EventUtils.IsEventValid",
}
local API_EVENTS = {
	"CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED",
	"SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "UPDATE_SHAPESHIFT_FORM", "ENCOUNTER_START",
}
local cdWatch = {} -- spellID -> last logged state key
local cdTicker
local atlasView
local editProbe
local editActive = false

local function plain(x)
	return x ~= nil and not (issecretvalue and issecretvalue(x))
end

local function isSecret(x)
	return issecretvalue and issecretvalue(x) or false
end

-- A spell ID, a spell name the client knows, or nothing (the last spell cast).
local function ResolveSpell(arg)
	if arg == nil or arg == "" then
		return lastCastSpell
	end
	local id = tonumber(arg)
	if id then
		return id
	end
	if GetSpellInfoTable then
		local ok, info = pcall(GetSpellInfoTable, arg)
		if ok and type(info) == "table" and plain(info.spellID) then
			return info.spellID
		end
	end
end

-- "8042 8056 8050" gives three IDs; anything else is one spell name.
local function SpellList(rest)
	local list = {}
	if rest == "" or rest:match("^[%d%s]+$") then
		for id in rest:gmatch("%d+") do
			list[#list + 1] = tonumber(id)
		end
		if #list == 0 and lastCastSpell then
			list[1] = lastCastSpell
		end
	else
		list[1] = ResolveSpell(rest)
	end
	return list
end

local function CooldownLine(spell)
	if not GetSpellCooldown then
		return "no C_Spell.GetSpellCooldown"
	end
	local info = GetSpellCooldown(spell)
	if type(info) ~= "table" then
		return "info=" .. str(info)
	end
	local line = "start=" .. num(info.startTime) .. " dur=" .. num(info.duration) .. " active=" .. str(info.isActive)
		.. " enabled=" .. str(info.isEnabled) .. " mod=" .. num(info.modRate)
	if GetCooldownDuration then
		local dur = GetCooldownDuration(spell, true)
		line = line .. " remain=" .. (dur and dur.GetRemainingDuration and num(dur:GetRemainingDuration()) or "nil")
	end
	return line
end

local function UsableLine(spell)
	if not IsSpellUsable then
		return "no C_Spell.IsSpellUsable"
	end
	local usable, noPower = IsSpellUsable(spell)
	return "usable=" .. str(usable) .. " noPower=" .. str(noPower)
end

local function SpellLabel(spell)
	return tostring(spell) .. " " .. (GetSpellName(spell) or "?")
end

-- Probes 3 and 10 (isActive, GCD), calibration reads and delayed-start reads.
local function CooldownProbe(spell, reason)
	local ok, line = pcall(CooldownLine, spell)
	log("CD", reason, SpellLabel(spell), ok and line or ("ERROR " .. str(line)))
end

-- Probe 12: usability readability.
local function UsableProbe(spell, reason)
	local ok, line = pcall(UsableLine, spell)
	log("USABLE", reason, SpellLabel(spell), ok and line or ("ERROR " .. str(line)))
end

-- Probe 5: resource secrecy.
local function PowerProbe(reason)
	if not UnitPower then
		log("POWER", reason, "no UnitPower")
		return
	end
	local okT, _, token = pcall(UnitPowerType, "player")
	local ok, power = pcall(UnitPower, "player")
	log("POWER", reason, "type=" .. (okT and str(token) or "ERROR"), "power=" .. (ok and num(power) or "ERROR"))
end

-- Probe 15: the form/stance read.
local function FormProbe(reason)
	local okI, id, okF, index = true, "n/a", true, "n/a"
	if GetShapeshiftFormID then
		okI, id = pcall(GetShapeshiftFormID)
	end
	if GetShapeshiftForm then
		okF, index = pcall(GetShapeshiftForm)
	end
	log("FORM", reason, "formID=" .. (okI and str(id) or "ERROR"), "index=" .. (okF and str(index) or "ERROR"))
end

-- Probe 11: is the player's own cast time plain? len is end - start.
local function CastInfoProbe(kind, reason)
	local fn = kind == "channel" and UnitChannelInfo or UnitCastingInfo
	if not fn then
		log("CASTINFO", reason, kind, "no info API")
		return
	end
	local ok, name, _, _, startMS, endMS = pcall(fn, "player")
	if not ok then
		log("CASTINFO", reason, kind, "ERROR", str(name))
		return
	end
	local length, left
	if plain(startMS) and plain(endMS) then
		length = format("%.3f", (endMS - startMS) / 1000)
		left = format("%.3f", endMS / 1000 - GetTime())
	elseif isSecret(startMS) or isSecret(endMS) then
		length, left = "<secret>", "<secret>"
	else
		length, left = "none", "none"
	end
	log("CASTINFO", reason, kind, str(name), "len=" .. length, "left=" .. left)
end

-- Probes 3/12 mid-fight without typing: one line per watched spell whenever
-- its state changes (a plain remaining time is left out of the change test,
-- so a running cooldown does not log every tick).
local function CdWatchTick()
	for spell, last in pairs(cdWatch) do
		local okC, cd = pcall(CooldownLine, spell)
		local okU, usable = pcall(UsableLine, spell)
		local line = (okC and cd or "cd ERROR") .. " " .. (okU and usable or "usable ERROR")
		local key = line:gsub(" remain=[%d%.%-]+", "")
		if key ~= last then
			cdWatch[spell] = key
			log("CDWATCH", SpellLabel(spell), line)
		end
	end
end

local function CdWatch(rest)
	if rest == "off" then
		wipe(cdWatch)
		if cdTicker then
			cdTicker:Cancel()
			cdTicker = nil
		end
		print("|cff88ccff[STL]|r cooldown watch off")
		return
	end
	local list = SpellList(rest)
	if #list == 0 then
		print("|cff88ccff[STL]|r cast the spell once first, or /stl cdwatch <spellID ...>")
		return
	end
	for i = 1, #list do
		cdWatch[list[i]] = ""
	end
	cdTicker = cdTicker or C_Timer.NewTicker(CD_WATCH_INTERVAL, CdWatchTick)
	local names = {}
	for spell in pairs(cdWatch) do
		names[#names + 1] = SpellLabel(spell)
	end
	print("|cff88ccff[STL]|r watching cooldowns: " .. table.concat(names, ", "))
end

-- Probe 14: atlas existence, plus an on-screen preview for the by-eye look.
local function AtlasProbe(names, reason)
	if not GetAtlasInfo then
		log("ATLAS", reason, "no C_Texture.GetAtlasInfo")
		print("|cff88ccff[STL]|r no C_Texture.GetAtlasInfo on this client")
		return
	end
	local missing = 0
	for i = 1, #names do
		local ok, info = pcall(GetAtlasInfo, names[i])
		if ok and type(info) == "table" then
			log("ATLAS", reason, names[i], "found", tostring(info.width) .. "x" .. tostring(info.height))
		else
			missing = missing + 1
			log("ATLAS", reason, names[i], ok and "MISSING" or "ERROR")
		end
	end
	print(format("|cff88ccff[STL]|r atlas %s: %d checked, %d missing (details in the log)", reason, #names, missing))
end

local function AtlasShow(names)
	if not atlasView then
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.7)
		f.cells = {}
		atlasView = f
	end
	for _, cell in ipairs(atlasView.cells) do
		cell.tex:Hide()
		cell.label:Hide()
	end
	local rows = math.ceil(#names / ATLAS_VIEW_COLUMNS)
	atlasView:SetSize(math.min(#names, ATLAS_VIEW_COLUMNS) * ATLAS_VIEW_CELL + 8, rows * (ATLAS_VIEW_CELL + 12) + 8)
	for i = 1, #names do
		local cell = atlasView.cells[i]
		if not cell then
			cell = { tex = atlasView:CreateTexture(nil, "ARTWORK"), label = atlasView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
			atlasView.cells[i] = cell
		end
		local col, row = (i - 1) % ATLAS_VIEW_COLUMNS, math.floor((i - 1) / ATLAS_VIEW_COLUMNS)
		cell.tex:ClearAllPoints()
		cell.tex:SetPoint("TOPLEFT", atlasView, "TOPLEFT", 4 + col * ATLAS_VIEW_CELL + 4, -4 - row * (ATLAS_VIEW_CELL + 12))
		cell.tex:SetSize(ATLAS_VIEW_CELL - 8, ATLAS_VIEW_CELL - 8)
		local ok, set = pcall(cell.tex.SetAtlas, cell.tex, names[i])
		cell.tex:SetShown(ok and set ~= false)
		cell.label:ClearAllPoints()
		cell.label:SetPoint("TOP", cell.tex, "BOTTOM", 0, -1)
		cell.label:SetText(tostring(i))
		cell.label:Show()
		log("ATLASVIEW", tostring(i), names[i], (ok and set ~= false) and "drawn" or "not drawn")
	end
	atlasView:Show()
	print("|cff88ccff[STL]|r atlas preview: cell numbers map to names in the log - /stl atlas show off to hide")
end

local function Atlas(rest)
	local verb, args = rest:match("^(%S*)%s*(.-)$")
	if verb == "show" then
		if args == "off" then
			if atlasView then
				atlasView:Hide()
			end
			return
		end
		local names = {}
		for name in args:gmatch("%S+") do
			names[#names + 1] = name
		end
		if #names == 0 then
			for _, list in ipairs({ TIMELINE_ATLASES, CHEVRON_CANDIDATES }) do
				for i = 1, #list do
					names[#names + 1] = list[i]
				end
			end
		end
		AtlasShow(names)
	elseif rest ~= "" then
		local names = {}
		for name in rest:gmatch("%S+") do
			names[#names + 1] = name
		end
		AtlasProbe(names, "manual")
	else
		AtlasProbe(TIMELINE_ATLASES, "timeline")
		AtlasProbe(CHEVRON_CANDIDATES, "chevron")
	end
end

-- Probe 8: Cooldown Manager coverage for the current class.
local function CdmProbe()
	local cv = C_CooldownViewer
	if not cv then
		log("CDM", "no C_CooldownViewer")
		print("|cff88ccff[STL]|r no C_CooldownViewer on this client")
		return
	end
	local okA, available = true, "n/a"
	if cv.IsCooldownViewerAvailable then
		okA, available = pcall(cv.IsCooldownViewerAvailable)
	end
	local cvar = GetCVar and GetCVar("cooldownViewerEnabled")
	log("CDM", "available=" .. (okA and str(available) or "ERROR"), "cvar=" .. str(cvar))
	local categories = Enum and Enum.CooldownViewerCategory
	if not (cv.GetCooldownViewerCategorySet and categories) then
		log("CDM", "no category API")
		return
	end
	for name, value in pairs(categories) do
		local ok, set = pcall(cv.GetCooldownViewerCategorySet, value)
		if ok and type(set) == "table" then
			local spells = {}
			for i = 1, #set do
				local okI, info = pcall(cv.GetCooldownViewerCooldownInfo, set[i])
				spells[i] = (okI and type(info) == "table") and SpellLabel(info.spellID) or tostring(set[i])
			end
			log("CDM", name, "count=" .. #set, table.concat(spells, ", "))
		else
			log("CDM", name, ok and ("set=" .. str(set)) or "ERROR")
		end
	end
	print("|cff88ccff[STL]|r Cooldown Manager coverage logged")
end

-- Every function and event the timeline would rely on: present or nil.
local function ApiProbe(reason)
	local missing = {}
	for i = 1, #API_PATHS do
		local value = _G
		for part in API_PATHS[i]:gmatch("[^%.]+") do
			value = type(value) == "table" and value[part] or nil
		end
		if value == nil then
			missing[#missing + 1] = API_PATHS[i]
		end
	end
	log("API", reason, "checked=" .. #API_PATHS, "missing=" .. (#missing > 0 and table.concat(missing, ",") or "none"))
	if IsEventValid then
		local invalid = {}
		for i = 1, #API_EVENTS do
			local ok, valid = pcall(IsEventValid, API_EVENTS[i])
			if not (ok and valid) then
				invalid[#invalid + 1] = API_EVENTS[i]
			end
		end
		log("API", reason, "events=" .. #API_EVENTS, "invalid=" .. (#invalid > 0 and table.concat(invalid, ",") or "none"))
	end
end

-- Probe 9: ForeverCDM's Edit Mode pattern. It registers no Blizzard system:
-- it listens for EventRegistry EditMode.Enter/Exit, unlocks its own drag
-- handle while Edit Mode is open and stores the position itself. PASS: the
-- box turns draggable only inside Edit Mode, and survives /reload.
local function EditProbeRefresh()
	if not editProbe then
		return
	end
	editProbe:EnableMouse(editActive)
	editProbe.label:SetText(editActive and "STL Edit Mode probe - drag me" or "STL Edit Mode probe (locked)")
end

local function EditProbeBuild()
	local f = CreateFrame("Frame", "SwingTestLogEditModeProbe", UIParent)
	f:SetSize(200, 40)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.82, 0.38, 0.12, 0.35)
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.label:SetPoint("CENTER")
	local saved = SwingTestLogDB.editProbe
	f:ClearAllPoints()
	if type(saved) == "table" and saved.x then
		f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", saved.x, saved.y)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	end
	f:SetScript("OnDragStart", function(self)
		if editActive then
			self:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter()
		SwingTestLogDB.editProbe = { x = x, y = y }
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		log("EDITMODE", "moved", num(x), num(y))
	end)
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			editActive = true
			log("EDITMODE", "enter")
			EditProbeRefresh()
		end, f)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			editActive = false
			log("EDITMODE", "exit")
			EditProbeRefresh()
		end, f)
	else
		log("EDITMODE", "no EventRegistry")
	end
	local manager = EditModeManagerFrame
	if manager and manager.IsEditModeActive then
		editActive = manager:IsEditModeActive() and true or false
	end
	local systems = manager and manager.registeredSystemFrames
	log("EDITMODE", "built", "active=" .. tostring(editActive), "systems=" .. (type(systems) == "table" and #systems or "n/a"),
		"snap=" .. tostring(manager and manager.IsSnapEnabled ~= nil))
	return f
end

local function EditMode(rest)
	if rest == "off" then
		SwingTestLogDB.editProbe = nil
		if editProbe then
			editProbe:Hide()
		end
		print("|cff88ccff[STL]|r Edit Mode probe off (position forgotten)")
		return
	end
	SwingTestLogDB.editProbe = SwingTestLogDB.editProbe or {}
	editProbe = editProbe or EditProbeBuild()
	editProbe:Show()
	EditProbeRefresh()
	print("|cff88ccff[STL]|r Edit Mode probe shown - open Edit Mode, drag it, close, /reload")
end
-- The speed-secrecy probe (findings 4.2 re-check): UnitAttackSpeed's three
-- returns plus UnitRangedDamage, each masked by num() and flagged by
-- issecretvalue. /stl speed for an on-demand read (run one mid-fight); the
-- combat enter/leave hooks log it at the restriction-flip instants, and
-- login adds the out-of-combat baseline - one fight yields both states.
local function SpeedProbe(reason)
	local s = issecretvalue
	if UnitAttackSpeed then
		local a, b, c = UnitAttackSpeed("player")
		log("SPEED", reason, "mh=" .. num(a), "oh=" .. num(b), "rgd=" .. num(c),
			"sec=" .. str(s and (s(a) or s(b) or s(c))))
	else
		log("SPEED", reason, "no UnitAttackSpeed")
	end
	if UnitRangedDamage then
		local r = UnitRangedDamage("player")
		log("SPEED", reason, "rngd=" .. num(r), "sec=" .. str(s and s(r)))
	else
		log("SPEED", reason, "no UnitRangedDamage")
	end
end
-- item 2): a plain read makes a cast SnD's duration schedulable, so the
-- expiry edge gets an exact expected instant instead of a 9-21 s window.
local function ComboPoints()
	if not GetComboPoints then
		print("|cff88ccff[STL]|r no GetComboPoints on this client")
		return
	end
	local ok, cp = pcall(GetComboPoints, "player", "target")
	if not ok then
		log("CP", "ERROR", str(cp))
	else
		log("CP", num(cp), "sec=" .. str(issecretvalue and issecretvalue(cp)))
	end
	print("|cff88ccff[STL]|r combo points logged")
end
-- Index-scan dump: run it out of combat on Forever (GetAuraDataByIndex throws
-- mid-combat there). Captures every helpful aura's name and spell ID - the
-- M1 B2 route for Maelstrom Weapon.
local function Scan()
	if GetAuraByIndex then
		for i = 1, 40 do
			local ok, d = pcall(GetAuraByIndex, "player", i, "HELPFUL")
			if not ok then
				log("SCAN", "error", str(d))
				return
			end
			if not d then
				log("SCAN", "end", "count=" .. tostring(i - 1))
				return
			end
			log("SCAN", "idx=" .. tostring(i), str(d.name), "id=" .. str(d.spellId), "apps=" .. str(d.applications), "dur=" .. num(d.duration))
		end
		log("SCAN", "end", "count=40")
	elseif UnitAura then
		for i = 1, 40 do
			local n, _, _, _, _, _, _, _, _, sid = UnitAura("player", i, "HELPFUL")
			if not n then
				log("SCAN", "end", "count=" .. tostring(i - 1))
				return
			end
			log("SCAN", "idx=" .. tostring(i), str(n), "id=" .. str(sid))
		end
		log("SCAN", "end", "count=40")
	end
end

-- Queued next-melee spells (SPEC 10.5 probe 1): /stl queue dumps every base
-- ID's IsCurrentSpell boolean - the high-rank Heroic Strike probe.
local function QueueDump()
	if not IsCurrentSpell then
		print("|cff88ccff[STL]|r no C_Spell.IsCurrentSpell on this client")
		return
	end
	local parts = {}
	for i = 1, #QUEUED_SPELLS do
		local ok, v = pcall(IsCurrentSpell, QUEUED_SPELLS[i])
		parts[i] = tostring(QUEUED_SPELLS[i]) .. "=" .. str(ok and v or "error")
	end
	log("QUEUE", table.concat(parts, " "))
	print("|cff88ccff[STL]|r " .. table.concat(parts, " "))
end

-- Per-swing sampling: a QUEUE line only while something is actually queued,
-- so long unqueued fights stay quiet.
local function QueueSample()
	if not IsCurrentSpell then
		return
	end
	local queued = {}
	for i = 1, #QUEUED_SPELLS do
		local ok, v = pcall(IsCurrentSpell, QUEUED_SPELLS[i])
		if ok and v then
			queued[#queued + 1] = QUEUED_SPELLS[i]
		end
	end
	if #queued > 0 then
		log("QUEUE", "at-swing", table.concat(queued, ","))
	end
end

local function DumpState(reason)
	if not lib then
		return
	end
	local now = GetTime()
	for _, hand in ipairs(HANDS) do
		local speed, expiration, last = lib:UnitSwingTimerInfo("player", hand)
		local state
		if expiration and last and expiration == last then
			state = "PARKED"
		elseif expiration and expiration > now then
			state = "IN-FLIGHT"
		else
			state = "LANDED"
		end
		log("STATE", reason, hand, "speed=" .. num(speed), "left=" .. num(expiration and expiration - now), state)
	end
end

local function StartSession()
	SwingTestLogDB = SwingTestLogDB or {}
	SwingTestLogDB.sessions = SwingTestLogDB.sessions or {}
	local sessions = SwingTestLogDB.sessions
	while #sessions >= MAX_SESSIONS do
		table.remove(sessions, 1)
	end
	local version, build = GetBuildInfo()
	local _, class = UnitClass("player")
	session = {
		started = date("%Y-%m-%d %H:%M:%S"),
		char = UnitName("player") .. "-" .. GetRealmName(),
		class = class,
		client = version .. "." .. build,
		libMinor = libMinor,
		entries = {},
	}
	sessions[#sessions + 1] = session
	log("SESSION", session.char, class, "client=" .. session.client, "libMinor=" .. tostring(libMinor))
end

-- Library callbacks
local function OnSwing(event, unit, speed, expiration, hand)
	log(event:sub(18), unit, hand, "speed=" .. num(speed), "left=" .. num(expiration and expiration - GetTime()))
end

local function OnHand(event, unit, hand)
	log(event:sub(18), unit, hand)
end

local function OnDelta(event, unit, delta)
	log("DELTA", unit, num(delta))
end

local function OnInit(event, unit)
	log("INIT", unit)
end

-- Game events
local frame = CreateFrame("Frame")
local handlers = {}
local registerFailures = {}

function handlers.PLAYER_LOGIN()
	playerGUID = UnitGUID("player")
	if LibStub then
		lib, libMinor = LibStub(LIB_NAME, true)
	end
	StartSession()
	log("CLIENT", isForever and "forever" or "classic", "interface=" .. tostring(interface))
	log("CAPS", "count=" .. tostring(GetAuraCount ~= nil), "cp=" .. tostring(GetComboPoints ~= nil))
	SpeedProbe("login")
	ApiProbe("login")
	for i = 1, #registerFailures do
		log("REGFAIL", registerFailures[i])
	end
	PowerProbe("login")
	FormProbe("login")
	if SwingTestLogDB.editProbe then
		-- The probe was on before this reload: rebuild it at the saved spot.
		editProbe = EditProbeBuild()
		EditProbeRefresh()
	end
	if not lib then
		log("ERROR", LIB_NAME .. " not loaded")
		return
	end
	lib.RegisterCallback(frame, "UNIT_SWING_TIMER_START", OnSwing)
	lib.RegisterCallback(frame, "UNIT_SWING_TIMER_UPDATE", OnSwing)
	lib.RegisterCallback(frame, "UNIT_SWING_TIMER_STOP", OnHand)
	lib.RegisterCallback(frame, "UNIT_SWING_TIMER_CLIPPED", OnHand)
	lib.RegisterCallback(frame, "UNIT_SWING_TIMER_PAUSED", OnHand)
	lib.RegisterCallback(frame, "UNIT_SWING_TIMER_DELTA", OnDelta)
	lib.RegisterCallback(frame, "UNIT_SWING_TIMER_INFO_INITIALIZED", OnInit)
end

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
	local kind = isInitialLogin and "login" or isReloadingUi and "reload" or "zone"
	log("WORLD", kind)
	-- The library seeds on the same event; read its state once the frame settles.
	C_Timer.After(0.5, function()
		DumpState(kind)
	end)
end

function handlers.PLAYER_ENTER_COMBAT()
	log("AUTOATK", "on")
end

function handlers.PLAYER_LEAVE_COMBAT()
	log("AUTOATK", "off")
end

function handlers.PLAYER_REGEN_DISABLED()
	log("COMBAT", "enter")
	AuraProbe("combat-enter")
	SpeedProbe("combat-enter")
	AuraCount("combat-enter")
	PowerProbe("combat-enter")
	FormProbe("combat-enter")
end

function handlers.PLAYER_REGEN_ENABLED()
	log("COMBAT", "leave")
	AuraProbe("combat-leave")
	SpeedProbe("combat-leave")
	AuraCount("combat-leave")
	PowerProbe("combat-leave")
	FormProbe("combat-leave")
end

function handlers.PLAYER_DEAD()
	log("DEAD")
	DumpState("dead")
end

function handlers.PLAYER_ALIVE()
	log("ALIVE")
end

function handlers.PLAYER_UNGHOST()
	log("UNGHOST")
end

function handlers.PLAYER_EQUIPMENT_CHANGED(slot)
	log("EQUIP", "slot=" .. tostring(slot))
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
	if unit ~= "player" then
		return
	end
	if issecretvalue and issecretvalue(spellID) then
		log("CAST", spellID)
	else
		log("CAST", spellID, GetSpellName(spellID))
		if not AUTO_ATTACK[spellID] then
			lastCastSpell = spellID
			-- Probes 10 and 3 plus the calibration read: the GCD and the spell's
			-- own cooldown just after the cast (out of combat these are plain;
			-- a delayed-start spell such as Stealth reads not yet started).
			C_Timer.After(0.05, function()
				CooldownProbe(GCD_SPELL, "gcd")
				CooldownProbe(spellID, "post-cast")
			end)
		end

		-- SnD requires combo points, so its cast instant is the guaranteed
		-- positive-points read: the decisive CP sample needs no manual timing.
		if GetComboPoints and (spellID == 5171 or spellID == 6774) then
			local ok, cp = pcall(GetComboPoints, "player", "target")
			log("CP", "at-snd", num(cp), "sec=" .. str(issecretvalue and issecretvalue(cp)))
		end
	end
end

function handlers.UNIT_SPELLCAST_START(unit, _, spellID)
	if unit ~= "player" then
		return
	end
	if issecretvalue and issecretvalue(spellID) then
		log("CASTSTART", spellID)
	else
		log("CASTSTART", spellID, GetSpellName(spellID))
	end
	CastInfoProbe("cast", "start")
end

function handlers.UNIT_SPELLCAST_INTERRUPTED(unit, _, spellID)
	if unit ~= "player" then
		return
	end
	log("CASTSTOP", "interrupted", spellID)
end

-- The cast lane's remaining edges (probe 11 and the stop/fail/channel rules).
local function CastEdge(tag, kind)
	return function(unit, _, spellID)
		if unit ~= "player" then
			return
		end
		log("CASTEDGE", tag, spellID, plain(spellID) and GetSpellName(spellID) or "")
		if kind then
			CastInfoProbe(kind, tag)
		end
	end
end

handlers.UNIT_SPELLCAST_STOP = CastEdge("stop")
handlers.UNIT_SPELLCAST_FAILED = CastEdge("failed")
handlers.UNIT_SPELLCAST_DELAYED = CastEdge("delayed", "cast")
handlers.UNIT_SPELLCAST_CHANNEL_START = CastEdge("channel-start", "channel")
handlers.UNIT_SPELLCAST_CHANNEL_UPDATE = CastEdge("channel-update", "channel")
handlers.UNIT_SPELLCAST_CHANNEL_STOP = CastEdge("channel-stop")

function handlers.UPDATE_SHAPESHIFT_FORM()
	FormProbe("event")
end

-- Probe 1: marks the boss pull in the log, so the CAST lines around it can be
-- checked for secret spell IDs.
function handlers.ENCOUNTER_START(encounterID, encounterName)
	log("ENCOUNTER", "start", encounterID, encounterName)
end

function handlers.ENCOUNTER_END(encounterID, encounterName, _, _, success)
	log("ENCOUNTER", "end", encounterID, encounterName, "success=" .. str(success))
end

-- Talent changes mark the timeline's calibration cache stale: which of these
-- events exists and fires on Forever?
local function TalentEvent(name)
	return function()
		log("TALENT", name)
	end
end

handlers.CHARACTER_POINTS_CHANGED = TalentEvent("CHARACTER_POINTS_CHANGED")
handlers.PLAYER_TALENT_UPDATE = TalentEvent("PLAYER_TALENT_UPDATE")
handlers.TRAIT_CONFIG_UPDATED = TalentEvent("TRAIT_CONFIG_UPDATED")

-- Attack-speed change edge (findings section 9 item 3: fires live in combat,
-- weapon swap and SotC haste change; the UnitAttackSpeed reads behind it are
-- secret in combat). Whether it fires at dynamic/proc-haste application
-- instants is open item 4 - these lines answer it in any capture, and they
-- are the tight-semantics candidate generator for the Deadly Aspects design
-- (fires only on real attack-speed changes; on-hit procs that do not change
-- attack speed do not fire it).
function handlers.UNIT_ATTACK_SPEED(unit)
	if unit ~= "player" then
		return
	end
	if UnitAttackSpeed then
		local mh, oh, rgd = UnitAttackSpeed("player")
		local s = issecretvalue
		log("ATKSPEED", "mh=" .. num(mh), "oh=" .. num(oh), "rgd=" .. num(rgd),
			"sec=" .. str(s and (s(mh) or s(oh) or s(rgd))))
	else
		log("ATKSPEED", "no UnitAttackSpeed on this client")
	end
end

if isForever then
	-- The library's own Forever swing anchor and parry source.
	function handlers.PLAYER_SWING(swingDuration, swingType)
		log("SWING", SWING_TYPES[swingType] or str(swingType), "duration=" .. num(swingDuration))
		QueueSample()
	end

	-- UNIT_AURA fires mid-combat on this client (findings section 4); every
	-- aura change is the moment to re-run the by-name probe, so application,
	-- refresh and removal edges all land in the log.
	function handlers.UNIT_AURA(unit)
		if unit == "player" then
			AuraProbe("aura-event")
			AuraCount("aura-event")
		end
	end

	function handlers.UNIT_COMBAT(unitTarget, action)
		if unitTarget == "player" and not (issecretvalue and issecretvalue(action)) and action == "PARRY" then
			log("PARRY", "you parried (UNIT_COMBAT)")
		elseif unitTarget == "target" and (isSecret(action) or action ~= "WOUND") then
			-- Probe 2: a dodged or parried Sunder/Heroic Strike shows up here
			-- next to its CAST line (or the missing one).
			log("TGTCOMBAT", action)
		end
	end
else
	function handlers.COMBAT_LOG_EVENT_UNFILTERED()
		local _, sub, _, sourceGUID, _, _, _, destGUID, _, _, _, a12, a13, _, _, _, _, _, _, _, a21 = CombatLogGetCurrentEventInfo()
		if sourceGUID == playerGUID then
			if sub == "SWING_DAMAGE" then
				log("HIT", a21 and "offhand" or "mainhand", "dmg=" .. tostring(a12))
			elseif sub == "SWING_MISSED" then
				log("MISS", a13 and "offhand" or "mainhand", a12)
			elseif (sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REMOVED" or sub == "SPELL_AURA_REFRESH") and destGUID == playerGUID then
				log("AURA", sub:sub(12), a12, a13)
			end
		elseif destGUID == playerGUID and a12 == "PARRY" and (sub == "SWING_MISSED") then
			log("PARRY", "you parried an incoming swing")
		elseif destGUID == playerGUID and sub == "SPELL_MISSED" then
			local _, _, _, _, _, _, _, _, _, _, _, _, _, _, missType = CombatLogGetCurrentEventInfo()
			if missType == "PARRY" then
				log("PARRY", "you parried an incoming spell")
			end
		end
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
-- An event this client lacks must not break the rig: registration is
-- pcall-wrapped and failures are logged once the session starts.
for event in pairs(handlers) do
	local ok
	if event == "UNIT_COMBAT" then
		ok = pcall(frame.RegisterUnitEvent, frame, event, "player", "target")
	elseif event:match("^UNIT_") then
		ok = pcall(frame.RegisterUnitEvent, frame, event, "player")
	else
		ok = pcall(frame.RegisterEvent, frame, event)
	end
	if not ok then
		registerFailures[#registerFailures + 1] = event
	end
end

-- Slash commands
SLASH_SWINGTESTLOG1 = "/stl"
SlashCmdList.SWINGTESTLOG = function(msg)
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "note" or cmd == "test" then
		log("NOTE", rest ~= "" and rest or "(marker)")
		print("|cff88ccff[STL]|r noted: " .. rest)
	elseif cmd == "state" then
		DumpState("manual")
	elseif cmd == "aura" then
		AuraProbe("manual")
		print("|cff88ccff[STL]|r aura probe logged (" .. table.concat(GetWatch(), ", ") .. ")")
	elseif cmd == "scan" then
		Scan()
	elseif cmd == "oracle" then
		Oracle()
	elseif cmd == "sinkview" then
		SinkView(rest:lower())
	elseif cmd == "speed" then
		SpeedProbe("manual")
	elseif cmd == "cd" or cmd == "usable" then
		local list = SpellList(rest)
		if #list == 0 then
			print("|cff88ccff[STL]|r cast the spell once first, or /stl " .. cmd .. " <spellID ...|name>")
		end
		for i = 1, #list do
			if cmd == "cd" then
				CooldownProbe(list[i], "manual")
			else
				UsableProbe(list[i], "manual")
			end
		end
		if #list > 0 then
			print("|cff88ccff[STL]|r " .. cmd .. " logged for " .. #list .. " spell(s)")
		end
	elseif cmd == "cdwatch" then
		CdWatch(rest)
	elseif cmd == "power" then
		PowerProbe("manual")
		print("|cff88ccff[STL]|r power logged")
	elseif cmd == "form" then
		FormProbe("manual")
		print("|cff88ccff[STL]|r form logged")
	elseif cmd == "atlas" then
		Atlas(rest)
	elseif cmd == "cdm" then
		CdmProbe()
	elseif cmd == "editmode" then
		EditMode(rest:lower())
	elseif cmd == "api" then
		ApiProbe("manual")
		print("|cff88ccff[STL]|r API presence logged")
	elseif cmd == "cp" then
		ComboPoints()
	elseif cmd == "queue" then
		QueueDump()
	elseif cmd == "watch" then
		if rest ~= "" then
			SwingTestLogDB.watch = { rest }
		end
		print("|cff88ccff[STL]|r watching: " .. table.concat(GetWatch(), ", "))
	elseif cmd == "echo" then
		SwingTestLogDB.echo = not SwingTestLogDB.echo
		print("|cff88ccff[STL]|r chat echo " .. (SwingTestLogDB.echo and "on" or "off"))
	elseif cmd == "clear" then
		SwingTestLogDB.sessions = {}
		StartSession()
		print("|cff88ccff[STL]|r log cleared")
	else
		print("|cff88ccff[STL]|r " .. (session and #session.entries or 0) .. " entries this session. Commands:")
		print("  /stl note <text> - mark a test step   /stl state - dump swing state")
		print("  /stl aura - probe watched auras by name   /stl scan - index-scan auras")
		print("  /stl watch <name> - set the watched aura   /stl queue - queued-spell dump")
		print("  /stl oracle - value-sink geometry probe (run mid-combat)")
		print("  /stl sinkview [spellID|off] - engine-drawn cooldown icon (visual test)")
		print("  /stl cp - log combo points (mid-combat CP probe)")
		print("  /stl speed - log attack speeds + secrecy flags")
		print("  Timeline probes: /stl cd|usable [IDs|name] - cooldown / usability read")
		print("  /stl cdwatch <IDs>|off - log cooldown+usable changes every 0.2 s")
		print("  /stl power   /stl form   /stl api   /stl cdm - Cooldown Manager coverage")
		print("  /stl atlas [names] - atlas check   /stl atlas show [names|off] - preview")
		print("  /stl editmode [off] - Edit Mode drag probe (ForeverCDM pattern)")
		print("  /stl echo - toggle chat echo   /stl clear - wipe all sessions")
		print("  The file is written on /reload or logout.")
	end
end
