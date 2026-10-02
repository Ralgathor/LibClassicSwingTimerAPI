-- Swing Test Log: records LibClassicSwingTimerAPI callbacks and combat context
-- into SwingTestLogDB, one session per login/reload. Review the file at
-- WTF\Account\<account>\SavedVariables\SwingTestLog.lua (written on /reload or logout).

local LIB_NAME = "LibClassicSwingTimerAPI"
local MAX_ENTRIES = 5000
local MAX_SESSIONS = 20
local HANDS = { "mainhand", "offhand", "ranged" }

local GetTime, date, format, select, tostring = GetTime, date, format, select, tostring
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local lib, libMinor = LibStub(LIB_NAME, true)
local playerGUID
local session

local function num(x)
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
		parts[i] = tostring((select(i, ...)))
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

function handlers.PLAYER_LOGIN()
	playerGUID = UnitGUID("player")
	StartSession()
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
end

function handlers.PLAYER_REGEN_ENABLED()
	log("COMBAT", "leave")
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
	if unit == "player" then
		log("CAST", spellID, (GetSpellInfo(spellID)))
	end
end

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

frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
for event in pairs(handlers) do
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		frame:RegisterUnitEvent(event, "player")
	else
		frame:RegisterEvent(event)
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
		print("  /stl echo - toggle chat echo   /stl clear - wipe all sessions")
		print("  The file is written on /reload or logout.")
	end
end
