-- Usage: luajit analyze-swingtestlog.lua <SwingTestLog.lua> (see ../CLASSIC_ERA_REGRESSION_2026-10-02.md)
assert(loadfile(arg[1]))()
local db = SwingTestLogDB

local function parse(line)
	local clock, t, kind, rest = line:match("^(%S+)%s+([%d%.]+)%s+(%S+)%s*(.*)$")
	return clock, tonumber(t), kind, rest
end

for si, s in ipairs(db.sessions) do
	print(("== session %d  %s  %d entries%s"):format(si, s.started, #s.entries, s.dropped and (" DROPPED " .. s.dropped) or ""))
	local pending = {} -- hand -> {t=, landing=, line=}
	local errs, n, worst, gaps = {}, 0, 0, {}
	local lastStop = {}
	local note = ""
	for i, line in ipairs(s.entries) do
		local clock, t, kind, rest = parse(line)
		if kind == "NOTE" then
			note = rest
			print("   -- " .. clock .. " NOTE " .. rest)
		end
		local unit, hand = rest:match("^(%S+) (%S+)")
		if unit == "player" and (kind == "START" or kind == "UPDATE") then
			local left = tonumber(rest:match("left=([%-%d%.]+)"))
			if kind == "START" and lastStop[hand] then
				local g = t - lastStop[hand]
				if g > 0.05 and g < 5 then
					gaps[#gaps + 1] = ("%s %s STOP->START gap %.3f [%s]"):format(clock, hand, g, note)
				end
				lastStop[hand] = nil
			end
			if kind == "START" and pending[hand] and pending[hand].landing > t + 0.05 then
				-- restarted before predicted landing (reset/extra attack/parry)
				print(("   %s %s early restart %.3f before predicted landing  [%s]"):format(clock, hand, pending[hand].landing - t, note))
			end
			pending[hand] = { t = t, landing = t + left }
		elseif unit == "player" and kind == "STOP" then
			local p = pending[hand]
			if p then
				local e = t - p.landing
				n = n + 1
				if math.abs(e) > math.abs(worst) then worst = e end
				if math.abs(e) > 0.05 then
					print(("   %s %s STOP off predicted landing by %+.3f  [%s]"):format(clock, hand, e, note))
				end
			end
			pending[hand] = nil
			lastStop[hand] = t
		elseif kind == "PARRY" or kind == "DEAD" or kind == "ALIVE" or kind == "UNGHOST" or kind == "CLIPPED" or kind == "PAUSED" or kind == "ERROR" then
			print("   " .. line)
		end
	end
	print(("   landings checked: %d, worst error %+.3f s"):format(n, worst))
	for _, g in ipairs(gaps) do print("   " .. g) end
end
