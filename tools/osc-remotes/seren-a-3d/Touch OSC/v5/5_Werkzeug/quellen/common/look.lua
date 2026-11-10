--------------------------------------------------------------------------
-- AUSSEHEN (gemeinsam: IEM space iPad + IEM monitor 5:4)
-- Farben (TouchOSC-Palette oder Spurfarben), Theme, Spurtypen, Kennzeichnung, Symbole.
--------------------------------------------------------------------------
local LOOK = {
  colors = 'tosc',      -- 'tosc' = Pastell-Palette, 'daw' = Spurfarben
  theme = 'synth',      -- 'synth' (seren.a) oder 'nuendo' (dunkel, neutral)
  show = { audio = true, fx = true, group = true, instr = true },   -- welche Spurtypen erscheinen
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
local function theme() return (LOOK.theme == 'nuendo') and PALETTE_NUENDO or PALETTE_SYNTH end
-- Pegelbalken in der Spurliste: eigene Farbe aus der Palette (nicht die Spurfarbe), oberstes Zehntel heiß
local function meterColor(pos) local th = theme(); return (pos >= 0.9) and th.meterHot or th.meter end

local function hasBitL(f, b) return math.floor(f / b) % 2 == 1 end
-- flags der DAW: 1 Encoder, 2 MultiPanner, 4 MultiEncoder, 8 Rotator, 16 FX, 32 Gruppe/Ordner, 64 MIDI/Instrument
local function typeOf(flags)
  if hasBitL(flags, 16) then return 'fx' end
  if hasBitL(flags, 32) then return 'group' end
  if hasBitL(flags, 64) then return 'instr' end
  return 'audio'
end
local function typeShown(flags) return LOOK.show[typeOf(flags)] ~= false end

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
  return b, LOOK.onlyPlug and 1 or 0
end
local function filterFromDaw(bits, plug)        -- cmd 16 der DAW: Stand übernehmen (alle Oberflächen gleich)
  local before = table.concat({ filterBits() }, ',')
  LOOK.show.audio = hasBitL(bits, 1); LOOK.show.fx = hasBitL(bits, 2)
  LOOK.show.group = hasBitL(bits, 4); LOOK.show.instr = hasBitL(bits, 8)
  LOOK.onlyPlug = plug == 1
  return before ~= table.concat({ filterBits() }, ',')
end
