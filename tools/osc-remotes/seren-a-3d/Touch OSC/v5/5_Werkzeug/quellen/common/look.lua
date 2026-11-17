--------------------------------------------------------------------------
-- AUSSEHEN (gemeinsam: IEM space iPad + IEM monitor 5:4)
-- Farben (TouchOSC-Palette oder Spurfarben), Theme, Spurtypen, Kennzeichnung, Symbole.
--------------------------------------------------------------------------
local LOOK = {
  colors = 'tosc',      -- 'tosc' = Pastell-Palette, 'daw' = Spurfarben
  theme = 'synth',      -- 'synth' (seren.a), 'nuendo', 'cute', 'girly', 'pastel' (v8.19, Farben aus den gleichnamigen VS-Code-Themes)
  mode = 'iem',         -- v8.19: Reiter, dessen Spurauswahl gerade gilt (LOOK.show zeigt auf showBy[mode])
  tabs = { iem = true, me = true, mp = true, room = true, fdn = true, mcfx = true, en = true, sp = true },
  split = { iem = true, me = true, mp = true, room = true },   -- v8.21: Split-Ansicht (Monitor): welche Felder    -- v8.19: welche Reiter sichtbar sind (Config, Seite 2)
  label = 'num',        -- v8.19: statt der Nummer: 'num' | 'name' (Spurname, gekürzt) | 'preset' (Preset, gekürzt)
  extra = {},           -- v8.19: Zusatzzeilen je Spurtyp: extra.audio = { subs = true, sends = true } ...
  show = nil,           -- (s. u.) Spurtypen des aktuellen Reiters: audio, oa3 (3OA), fx, group, instr
  marks = true,         -- Kennzeichnung: FX = Strich darunter, Gruppe/Ordner = Strich davor, MIDI/Instr = ♪
  onlyPlug = true,      -- Liste/Felder: nur Spuren mit passendem Plugin im aktuellen Modus (space/multi/panner/room)
  cpu = false,          -- dezente Auslastungsanzeige (nur Reaper liefert sie)
  icons = 'off',        -- 'off', 'dot', 'list', 'both'
  iconSize = 1.0,       -- 0.5..2
  iconAlpha = 0.9,      -- 0.2..1
}
-- Symbole: Teil des Icon-Namens (Reaper) oder des Spurnamens -> Zeichen. Gerne erweitern.
-- (TouchOSC kann keine Bilddateien anzeigen, darum Zeichen.)
local ICONS = {
  { 'kick', '◉' }, { 'snare', '◎' }, { 'drum', '◍' }, { 'tom', '○' }, { 'hat', '✳' }, { 'oh', '☄' },
  { 'cymbal', '✺' }, { 'perc', '✦' }, { 'bass', '♒' }, { 'gtr', '♯' }, { 'guitar', '♯' },
  { 'key', '▤' }, { 'piano', '▤' }, { 'synth', '∿' }, { 'pad', '☁' }, { 'string', '♭' },
  { 'vox', '♪' }, { 'voc', '♪' }, { 'voice', '♪' }, { 'choir', '♫' }, { 'fx', '✧' },
  { 'atmo', '☾' }, { 'amb', '☾' }, { 'room', '◫' }, { 'reverb', '≋' }, { 'verb', '≋' },
  { 'delay', '⋯' }, { 'brass', '♮' }, { 'sax', '♮' }, { 'click', '⌚' },
}
local PALETTE_SYNTH = {
  bg = { 0.04, 0.02, 0.08 }, panel = { 0.13, 0.05, 0.25 }, line = { 0.36, 0.20, 0.55 },
  row = { 0.17, 0.08, 0.31 }, rowCur = { 0.36, 0.16, 0.52 }, text = { 1, 0.94, 0.98 },
  accent = { 1, 0.43, 0.78 }, accent2 = { 0.37, 0.95, 1 }, pill = { 0.18, 0.08, 0.35 },
  meter = { 0.48, 0.94, 0.71 }, meterHot = { 1.00, 0.83, 0.43 }, meterHold = { 1, 0.94, 0.98 },   -- Pegel: Mint, oben Gold
}
local PALETTE_NUENDO = {
  bg = { 0.11, 0.12, 0.13 }, panel = { 0.17, 0.18, 0.19 }, line = { 0.30, 0.31, 0.33 },
  row = { 0.20, 0.21, 0.22 }, rowCur = { 0.29, 0.31, 0.34 }, text = { 0.86, 0.87, 0.88 },
  accent = { 0.96, 0.62, 0.20 }, accent2 = { 0.38, 0.67, 0.92 }, pill = { 0.24, 0.25, 0.26 },
  meter = { 0.40, 0.78, 0.45 }, meterHot = { 0.96, 0.62, 0.20 }, meterHold = { 0.86, 0.87, 0.88 },  -- wie Nuendo: grün, oben orange
}
-- v8.19: Farben aus den Visual-Studio-Code-Themes „Cute“ (WebFreak, hell rosa), „Girly Pop Dark“ (Light of the Revolution)
-- und „Dark Pastel Pink“ (dpoppe7). Werte wie im Theme (editor/sideBar/list/button/Terminal-Farben).
function hex(h) return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255 } end
do
local PALETTE_CUTE = {      -- hell: weißrosa Flächen, dunkles Violett als Schrift
  bg = hex('#fff7fa'), panel = hex('#fceaf1'), line = hex('#f4b4cc'),
  row = hex('#fcdee9'), rowCur = hex('#ff7ba2'), text = hex('#210049'),
  accent = hex('#ff4574'), accent2 = hex('#39007f'), pill = hex('#f9cfdf'),
  meter = hex('#ff7ba2'), meterHot = hex('#ff4574'), meterHold = hex('#210049'),
}
local PALETTE_GIRLY = {     -- dunkel violett mit Rosa/Flieder
  bg = hex('#180b33'), panel = hex('#2b1e47'), line = hex('#5a4580'),
  row = hex('#2c145d'), rowCur = hex('#6a3fa0'), text = hex('#fff0f5'),
  accent = hex('#fe7c8e'), accent2 = hex('#c87cfe'), pill = hex('#3a2866'),
  meter = hex('#c3e88d'), meterHot = hex('#ffcb6b'), meterHold = hex('#fff0f5'),
}
local PALETTE_PASTEL = {    -- dunkles Blaugrau mit Pastellrosa
  bg = hex('#1e2432'), panel = hex('#181c27'), line = hex('#313b52'),
  row = hex('#262d3f'), rowCur = hex('#473241'), text = hex('#d4d4d4'),
  accent = hex('#be5485'), accent2 = hex('#73d3ea'), pill = hex('#313b52'),
  meter = hex('#a0eace'), meterHot = hex('#f7f79d'), meterHold = hex('#ffcff1'),
}
THEMES = { synth = PALETTE_SYNTH, nuendo = PALETTE_NUENDO, cute = PALETTE_CUTE, girly = PALETTE_GIRLY, pastel = PALETTE_PASTEL }
end
THEME_ORDER = { 'synth', 'nuendo', 'cute', 'girly', 'pastel' }
local function theme() return THEMES[LOOK.theme] or PALETTE_SYNTH end
-- Pegelbalken in der Spurliste: eigene Farbe aus der Palette (nicht die Spurfarbe), oberstes Zehntel heiß
local function meterColor(pos) local th = theme(); return (pos >= 0.9) and th.meterHot or th.meter end

-- Spurtypen je Reiter (v8.19). oa3 = Audiospur mit 3OA (16 Kanäle oder „3OA“ im Namen, erkennt die DAW).
TYPE_ORDER = { 'audio', 'oa3', 'fx', 'group', 'instr' }
TAB_ORDER = { 'iem', 'me', 'mp', 'room', 'fdn', 'mcfx', 'en', 'sp' }   -- v8.20: + Hall-Reiter (Sends in einen FDN-/mcfx-Hall)
TAB_FILT = { 'iem', 'me', 'mp', 'room' }                       -- Reiter mit eigener Spurauswahl (Hall-Reiter zeigen Sends)
SPLIT_MODES = { 'iem', 'me', 'mp', 'room' }                    -- v8.21: Felder der Split-Ansicht (Reihenfolge = Lage)
HAS_SPLIT = false                                              -- nur die Monitore haben den Reiter „split“
HALL_KIND = { fdn = 1, mcfx = 2, en = 3 }                              -- Art, die das DAW-Skript im Hall-Reiter anzeigt
LOOK.showBy = {}
for _, m in ipairs(TAB_ORDER) do LOOK.showBy[m] = { audio = true, oa3 = true, fx = true, group = true, instr = true } end
LOOK.show = LOOK.showBy.iem
function lookMode(m)                       -- der Reiter wechselt: seine Spurauswahl gilt
  if not LOOK.showBy[m] then LOOK.showBy[m] = { audio = true, oa3 = true, fx = true, group = true, instr = true } end
  LOOK.mode = m; LOOK.show = LOOK.showBy[m]
end

local function hasBitL(f, b) return math.floor(f / b) % 2 == 1 end
-- flags der DAW: 1 Encoder, 2 MultiPanner, 4 MultiEncoder, 8 Rotator, 16 FX, 32 Gruppe/Ordner, 64 MIDI/Instrument
local function typeOf(flags, o)
  if hasBitL(flags, 16) then return 'fx' end
  if hasBitL(flags, 32) then return 'group' end
  if hasBitL(flags, 64) then return 'instr' end
  if o and o.oa3 then return 'oa3' end
  return 'audio'
end
local function typeShown(flags, o) return LOOK.show[typeOf(flags, o)] ~= false end

-- Beschriftung statt der Nummer (v8.19): Nummer, Spurname oder Preset, gekürzt auf n Zeichen
function abbr(s, n)
  s = tostring(s or '')
  if #s <= n then return s end
  local t = s:gsub('[%s_%-%.]+', ' ')
  if #t > n then                                  -- Wörter: Anfangsbuchstaben + letzte Ziffern
    local words, ini = {}, ''
    for w in t:gmatch('%S+') do words[#words + 1] = w end
    if #words > 1 then
      for i, w in ipairs(words) do ini = ini .. (i == #words and w:sub(1, math.max(1, n - #ini)) or w:sub(1, 1)) end
      if #ini <= n then return ini end
    end
    t = t:gsub('[aeiouäöü]', function() return '' end, math.max(0, #t - n))   -- Vokale hinten weglassen
  end
  return t:sub(1, n)
end
function labelFor(o, numText, n)
  if LOOK.label == 'name' and o and o.name and o.name ~= '' then return abbr(o.name, n) end
  if LOOK.label == 'preset' and o and o.preset and o.preset ~= '' then return abbr(o.preset, n) end
  return numText
end
-- Zusatzzeilen (v8.19): Subspuren und Sends (Receives) je Spurtyp, in der Config zuschaltbar
function extraText(o, typ)
  local e = LOOK.extra[typ]
  if not e or not o then return '' end
  local t = {}
  if e.subs then t[#t + 1] = '↳ ' .. (o.subs or 0) .. ' Sub' end
  if e.sends then t[#t + 1] = '← ' .. (o.sends or 0) .. ' Send' end
  return table.concat(t, '\n')
end

local function iconFor(iconName, trackName)
  local function find(s)
    s = (s or ''):lower()
    if s == '' then return nil end
    for _, e in ipairs(ICONS) do if s:find(e[1], 1, true) then return e[2] end end
  end
  return find(iconName) or find(trackName) or ''
end

-- Spurfilter in der DAW (v8.4): Spurtypen + „nur Spuren mit Plugin“ gehen als SysEx 0B an die DAW.
-- Reaper baut seine Bänke dann nur aus passenden Spuren; Nuendo kennt das nicht (dort filtert die Oberfläche).
local function filterBits()
  local b = 0
  if LOOK.show.audio ~= false then b = b + 1 end
  if LOOK.show.fx ~= false then b = b + 2 end
  if LOOK.show.group ~= false then b = b + 4 end
  if LOOK.show.instr ~= false then b = b + 8 end
  if LOOK.show.oa3 ~= false then b = b + 16 end
  return b, LOOK.onlyPlug and 1 or 0
end
local function filterFromDaw(bits, plug)        -- cmd 16 der DAW: Stand übernehmen (alle Oberflächen gleich)
  local before = table.concat({ filterBits() }, ',')
  LOOK.show.audio = hasBitL(bits, 1); LOOK.show.fx = hasBitL(bits, 2)
  LOOK.show.group = hasBitL(bits, 4); LOOK.show.instr = hasBitL(bits, 8); LOOK.show.oa3 = hasBitL(bits, 16)
  LOOK.onlyPlug = plug == 1
  return before ~= table.concat({ filterBits() }, ',')
end
