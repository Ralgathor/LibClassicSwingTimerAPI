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

function handlers.PLAYER_LOGIN()
	playerGUID = UnitGUID("player")
	if LibStub then
		lib, libMinor = LibStub(LIB_NAME, true)
	end
	StartSession()
	log("CLIENT", isForever and "forever" or "classic", "interface=" .. tostring(interface))
	log("CAPS", "count=" .. tostring(GetAuraCount ~= nil), "cp=" .. tostring(GetComboPoints ~= nil))
	SpeedProbe("login")
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
end

function handlers.PLAYER_REGEN_ENABLED()
	log("COMBAT", "leave")
	AuraProbe("combat-leave")
	SpeedProbe("combat-leave")
	AuraCount("combat-leave")
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
end

function handlers.UNIT_SPELLCAST_INTERRUPTED(unit, _, spellID)
	if unit ~= "player" then
		return
	end
	log("CASTSTOP", "interrupted", spellID)
end

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
for event in pairs(handlers) do
	if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_COMBAT" or event == "UNIT_AURA" or event == "UNIT_ATTACK_SPEED" then
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
	elseif cmd == "aura" then
		AuraProbe("manual")
		print("|cff88ccff[STL]|r aura probe logged (" .. table.concat(GetWatch(), ", ") .. ")")
	elseif cmd == "scan" then
		Scan()
	elseif cmd == "oracle" then
		Oracle()
	elseif cmd == "speed" then
		SpeedProbe("manual")
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
		print("  /stl cp - log combo points (mid-combat CP probe)")
		print("  /stl speed - log attack speeds + secrecy flags")
		print("  /stl echo - toggle chat echo   /stl clear - wipe all sessions")
		print("  The file is written on /reload or logout.")
	end
end
