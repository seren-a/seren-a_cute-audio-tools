--------------------------------------------------------------------------
-- MONITOR (gemeinsam für alle seren.a 3D Oberflächen)
-- Zeigt in Klartext: was das DAW-Skript erkannt hat (◆), was ankommt (←)
-- und was rausgeht (→). Werte derselben Sache ersetzen ihre Zeile, damit
-- die Liste beim Ziehen nicht vollläuft. Textfeld: 'mon_text'.
--------------------------------------------------------------------------
-- v8.22.6: Umlaute/ß/Akzente kommen als Steuerbytes 1-31 (SysEx ist 7 Bit), siehe SX_MAP in Reaper_3D.lua
SX_HI = { [1] = 'Ä', [2] = 'Ö', [3] = 'Ü', [4] = 'ä', [5] = 'ö', [6] = 'ü', [7] = 'ß', [8] = 'é', [11] = 'è', [12] = 'à',
  [14] = 'ê', [15] = 'ç', [16] = '–', [17] = '°', [18] = '·', [19] = '’', [20] = 'ñ', [21] = 'á', [22] = 'ó', [23] = 'í', [24] = 'ú',
  [25] = 'É', [26] = '…', [27] = 'â', [28] = 'ô', [29] = 'î', [30] = 'û', [31] = 'ë' }
function sxChar(c) if c >= 32 and c <= 126 then return string.char(c) end return SX_HI[c] end
function sxEnc(s)                                 -- UTF-8 -> ein Byte je Zeichen (zum Kürzen)
  if not s:find('[\128-\255]') then return s end
  for c, u in pairs(SX_HI) do s = s:gsub(u, string.char(c)) end
  return (s:gsub('[\128-\255]', ''))
end
function sxDec(s)                                 -- zurück zu UTF-8
  if not s:find('[\1-\8\11\12\14-\31]') then return s end
  return (s:gsub('[\1-\8\11\12\14-\31]', function(ch) return SX_HI[ch:byte()] or '' end))
end
DAW_VER = false                                   -- v8.22.6: Version des DAW-Skripts (aus „hello|3D vX aktiv“)
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
    local ch = sxChar(c); if ch then t[#t + 1] = ch end
  end
  return table.concat(t)
end

-- Erkennungs-Zeilen des DAW-Skripts kommen als "schluessel|text" und bleiben
-- stehen (eine pro Schlüssel), damit der Verkehr sie nicht wegschiebt.
-- Leerer Text löscht die Zeile.
local function monFound(raw)
  local key, text = raw:match('^([^|]*)|(.*)$')
  if not key then key, text = raw, raw end
  if key == 'hello' then DAW_VER = text:match('(v[%d%.]+)') or DAW_VER end
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
