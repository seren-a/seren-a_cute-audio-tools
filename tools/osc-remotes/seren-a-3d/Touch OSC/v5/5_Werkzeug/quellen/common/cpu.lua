-- Auslastung der DAW (SysEx F0 7D 4F 0F <system %> <DAW %> <Aussetzer> F7, 127 = unbekannt).
-- Nur das Reaper-Skript schickt das (Nuendo gibt Skripten keine Auslastung). Anzeige: Option
-- "Auslastung" (LOOK.cpu), dezent neben der Versionsnummer (Label 'cpu_lbl').
local CPU = { sys = 127, app = 127, xrun = 0, t = -1e9, shown = nil }

function CPU.parse(m)                   -- true, wenn es cmd 15 war
  if m[4] ~= 15 then return false end
  CPU.sys, CPU.app, CPU.xrun, CPU.t = m[5] or 127, m[6] or 127, m[7] or 0, getMillis()
  return true
end

function CPU.text(dawName)
  if getMillis() - CPU.t > 10000 then
    return (dawName == 'NUENDO') and 'CPU –  (Nuendo meldet keine Auslastung)' or 'CPU –'
  end
  local s = (CPU.sys <= 100) and ('CPU ' .. CPU.sys .. ' %') or 'CPU –'
  if CPU.app <= 100 then s = s .. '  ·  ' .. ((dawName and dawName ~= '') and dawName or 'DAW') .. ' ' .. CPU.app .. ' %' end
  if CPU.xrun > 0 then s = s .. '  ·  Aussetzer!' end
  return s
end

-- dim = Grundfarbe (Text der Palette), hot = Warnfarbe (meterHot)
function CPU.render(dawName, dim, hot)
  local c = root:findByName('cpu_lbl', true)
  if not c then return end
  if not LOOK.cpu then
    if CPU.shown ~= false then c.visible = false; CPU.shown = false end
    return
  end
  local txt = CPU.text(dawName)
  local warn = getMillis() - CPU.t <= 10000 and (CPU.xrun > 0 or (CPU.sys <= 100 and CPU.sys >= 85))
  local key = txt .. (warn and '!' or '') .. tostring(LOOK.theme)
  if CPU.shown == key then return end
  CPU.shown = key
  c.visible = true
  c.values.text = txt
  local col = warn and hot or dim
  c.textColor = Color(col[1], col[2], col[3], warn and 0.9 or 0.45)
end
