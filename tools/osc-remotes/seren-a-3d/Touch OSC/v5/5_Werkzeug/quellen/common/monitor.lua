--------------------------------------------------------------------------
-- MONITOR (gemeinsam für alle seren.a 3D Oberflächen)
-- Zeigt in Klartext: was das DAW-Skript erkannt hat (◆), was ankommt (←)
-- und was rausgeht (→). Werte derselben Sache ersetzen ihre Zeile, damit
-- die Liste beim Ziehen nicht vollläuft. Textfeld: 'mon_text'.
--------------------------------------------------------------------------
local MON = { lines = {}, keyed = {}, max = 14, found = {}, foundMax = 40, dirty = false, lastDraw = 0 }

local function monAdd(text, key)
  local L = MON.lines
  if key and MON.keyed[key] then
    for i = #L, 1, -1 do if L[i].key == key then table.remove(L, i) end end
  end
  table.insert(L, 1, { text = text, key = key })
  if key then MON.keyed[key] = true end
  while #L > MON.max do
    local old = table.remove(L)
    if old.key then MON.keyed[old.key] = nil end
  end
  MON.dirty = true
end

local function monSysexText(m, from)
  local t = {}
  for i = from, #m - 1 do
    local c = m[i]
    if c >= 32 and c <= 126 then t[#t + 1] = string.char(c) end
  end
  return table.concat(t)
end

-- Erkennungs-Zeilen des DAW-Skripts kommen als "schluessel|text" und bleiben
-- stehen (eine pro Schlüssel), damit der Verkehr sie nicht wegschiebt.
-- Leerer Text löscht die Zeile.
local function monFound(raw)
  local key, text = raw:match('^([^|]*)|(.*)$')
  if not key then key, text = raw, raw end
  local F = MON.found
  for i, f in ipairs(F) do
    if f.key == key then
      if text == '' then table.remove(F, i) else f.text = text end
      MON.dirty = true
      return
    end
  end
  if text == '' then return end
  F[#F + 1] = { key = key, text = text }
  while #F > MON.foundMax do table.remove(F, 1) end
  MON.dirty = true
end

-- SysEx F0 7D 4F 08 <Text> F7 vom DAW-Skript
local function monOnSysex(m)
  if m[2] == 0x7D and m[3] == 0x4F and m[4] == 8 then
    monFound(monSysexText(m, 5))
    return true
  end
  if m[2] == 0x7D and m[3] == 0x4F and m[4] == 7 then MON.found = {}; MON.dirty = true end
  return false
end

local function monDraw(force)
  if not (MON.dirty or force) then return end
  local now = getMillis()
  if not force and now - MON.lastDraw < 200 then return end
  MON.lastDraw, MON.dirty = now, false
  local c = root:findByName('mon_text', true)
  if not c then return end
  local out = { 'ERKANNT (vom DAW-Skript):' }
  if #MON.found == 0 then out[#out + 1] = '   (noch nichts – läuft das DAW-Skript? Bridge 1 + MIDI 1 eingerichtet?)' end
  for _, f in ipairs(MON.found) do out[#out + 1] = '◆ ' .. f.text end
  out[#out + 1] = ''
  out[#out + 1] = 'VERKEHR (neueste oben):'
  for _, l in ipairs(MON.lines) do out[#out + 1] = l.text end
  c.values.text = table.concat(out, '\n')
end
