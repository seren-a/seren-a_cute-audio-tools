--[[ =========================================================================
  seren.a · 3D-Panner (+ TotalMix)  ·  Root-Skript (TouchOSC 2), v3
  -------------------------------------------------------------------------
  Alle OSC-Messages, die TouchOSC selbst kann, stehen direkt an den
  Controls (Editor > Control > Messages). Hier steht nur, was Rechnen braucht:
  Kreis-Mathematik, MultiPanner-Modes/MIDI, Peak-Hold, EQ-Kurve,
  Snapshot-Blinken, DAW-MIDI-Weg, Monitor (Seite MONITOR).

  VERBINDUNGEN (TouchOSC → Connections → OSC / MIDI):
    OSC 1  TotalMix FX           Send 7001, Receive 9001 (nur *_TotalMix)
    OSC 2  IEM StereoEncoder     Host = Rechner-IP, Send 8001, Receive 9101   (nur OSC-Fassung)
    OSC 3  IEM SceneRotator      Host = Rechner-IP, Send 8002, Receive 9102   (nur OSC-Fassung)
    OSC 4  IEM MultiEncoder      Host = Rechner-IP, Send 8003, Receive 9103   (nur OSC-Fassung)
    MIDI 1 TouchOSC Bridge  → serena_TouchOSC3D.js (Nuendo) / reaper_seren3D.lua (Reaper)
  Alles Anpassbare steht in CFG / MP / IEM / PAD_MODES direkt hier drunter.
========================================================================= ]]

local CFG = {
  conn = { tm = 1, enc = 2, rot = 3, menc = 4 },   -- OSC 1 TotalMix, 2 StereoEncoder, 3 SceneRotator, 4 MultiEncoder
  nOsc = 10,            -- Anzahl OSC-Verbindungen deiner TouchOSC-Version
  midiConn = 1,
  nMidi = 10,
  withTM = true,        -- false = Panner ohne TotalMix-Spalte (seren-a_3D-Panner*.tosc)

  -- TotalMix FX (UCX, Output-Bus, Stereo-Paar = 1 Strip)
  -- (Strip-Nummern stehen jetzt direkt in den Messages: /1/volume4, /1/level1Left ...)
  levelIsLinear = true, -- Meterwert als lineare Amplitude deuten (nur für die dB-Zahl)
  holdMs = 1500,
  snapBlink = true,     -- Snapshot blinkt, wenn nach dem Laden etwas geändert wurde
  snapGraceMs = 2500,   -- so lange nach Laden/Sync werden Änderungen ignoriert

  -- Touch-Geometrie
  xyYUp = true,         -- true: XY-Wert y=1 ist oben. Falls Pads vertikal
                        -- verkehrt reagieren -> false
  -- Nuendo MultiPanner: 'pb' = Pitchbend, je Parameter eigener MIDI-Kanal
  -- (14 bit), 'cc' = Control Change auf Kanal 1 ab ccBase (7 bit)
  mpMode = 'pb',
  -- IEM: 'osc'  = direct to the plugins (any DAW, one fixed plugin instance per port)
  --      'midi' = via Nuendo/Cubase MIDI Remote (serena_TouchOSC3D.js): follows the selected
  --               track, 14-bit CC on channel 16 over MIDI connection midiConn
  iemVia = 'osc',
  iemCh = 15,
  ccBase = 20,
}

-- Nuendo VST MultiPanner. Reihenfolge = MIDI-Kanal (pb) bzw. CC-Offset (cc).
-- min/max/unit sind NUR für die Zahlenanzeige; Nuendo skaliert selbst.
local MP = {
  { id = 'x',     name = 'X',           min = -100, max = 100, unit = '',  fmt = '%+.0f' },
  { id = 'y',     name = 'Y',           min = -100, max = 100, unit = '',  fmt = '%+.0f' },
  { id = 'z',     name = 'Z',           min = -100, max = 100, unit = '',  fmt = '%+.0f' },
  { id = 'rotz',  name = 'Rot Z',       min = -180, max = 180, unit = '°', fmt = '%+.0f' },
  { id = 'tilty', name = 'Tilt Y',      min = -180, max = 180, unit = '°', fmt = '%+.0f' },
  { id = 'tiltx', name = 'Tilt X',      min = -180, max = 180, unit = '°', fmt = '%+.0f' },
  { id = 'dist',  name = 'Distance',    min = 0,    max = 100, unit = '%', fmt = '%.0f' },
  { id = 'div',   name = 'Divergence',  min = 0,    max = 100, unit = '%', fmt = '%.0f' },
  { id = 'field', name = 'Field Size',  min = 0,    max = 100, unit = '%', fmt = '%.0f' },
  { id = 'src',   name = 'Source Size', min = 0,    max = 100, unit = '%', fmt = '%.0f' },
  { id = 'width', name = 'Width',       min = 0,    max = 100, unit = '%', fmt = '%.0f' },
  { id = 'depth', name = 'Depth',       min = 0,    max = 100, unit = '%', fmt = '%.0f' },
}

-- IEM (Werte in echten Einheiten, so erwartet es die IEM-OSC-Schnittstelle)
-- min/max = Bedienbereich hier; cc/pmin/pmax = MIDI-Weg: CC-Nummer (MSB, LSB = cc+32) und der
-- volle Parameterbereich des Plugins, auf den Nuendo 0..1 abbildet
local IEM = {
  az    = { conn = 'enc', addr = '/StereoEncoder/azimuth',   min = -180, max = 180, name = 'Azimuth',
            cc = 1, pmin = -180, pmax = 180 },
  el    = { conn = 'enc', addr = '/StereoEncoder/elevation', min = -90,  max = 90,  name = 'Elevation',
            cc = 2, pmin = -180, pmax = 180 },
  wid   = { conn = 'enc', addr = '/StereoEncoder/width',     min = -180, max = 180, name = 'Width',
            cc = 4, pmin = -360, pmax = 360 },
  yaw   = { conn = 'rot', addr = '/SceneRotator/yaw',        min = -180, max = 180, name = 'Yaw',
            cc = 5, pmin = -180, pmax = 180 },
  pitch = { conn = 'rot', addr = '/SceneRotator/pitch',      min = -90,  max = 90,  name = 'Pitch',
            cc = 6, pmin = -180, pmax = 180 },
  -- MultiEncoder Master (nur OSC-Fassung; die Skript-Fassung nimmt Insert 4 automatisch)
  maz   = { conn = 'menc', addr = '/MultiEncoder/masterAzimuth',   min = -180, max = 180, name = 'Master Azimuth' },
  mel   = { conn = 'menc', addr = '/MultiEncoder/masterElevation', min = -90,  max = 90,  name = 'Master Elevation' },
}

-- MODE-Button: welche Parameter liegen auf den beiden XY-Pads (Seite 1 + 3)
local PAD_MODES = {
  { name = 'POSITION', pad1 = { 'x', 'y', 'TOP VIEW' },         pad2 = { 'x', 'z', 'REAR VIEW' } },
  { name = 'SIZE',     pad1 = { 'width', 'depth', 'WIDTH / DEPTH' }, pad2 = { 'field', 'src', 'FIELD / SOURCE' } },
  { name = 'SPREAD',   pad1 = { 'dist', 'div', 'DIST / DIVERG.' },   pad2 = { 'rotz', 'tiltx', 'ROT Z / TILT X' } },
}

--------------------------------------------------------------------------
-- ab hier Logik
--------------------------------------------------------------------------
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local atan2 = math.atan2 or math.atan
local log10 = function(v) return math.log(v) / math.log(10) end

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

local function conns(i, n)
  local t = {}
  for k = 1, n do t[k] = (k == i) end
  return t
end

local OSC = {}
for k, i in pairs(CFG.conn) do OSC[k] = conns(i, CFG.nOsc) end
local MIDI_OUT = conns(CFG.midiConn, CFG.nMidi)
local CONN_NAME = {}
for k, i in pairs(CFG.conn) do CONN_NAME[i] = k end

local function sendF(conn, path, v)
  sendOSC({ path, { { tag = 'f', value = v } } }, OSC[conn])
end
local function sendBare(conn, path)
  sendOSC({ path, {} }, OSC[conn])
end

local ctl = {}           -- name -> control
local function C(name)
  local c = ctl[name]
  if c == nil then
    c = root:findByName(name, true)
    if c then ctl[name] = c end
  end
  return c
end
local function setText(name, txt)
  local c = C(name)
  if c then c.values.text = txt end
end
local function setX(name, v)
  local c = C(name)
  if c and not c.values.touch then c.values.x = v end
end
local function setColor(name, r, g, b, a)
  local c = C(name)
  if c then c.color = Color(r, g, b, a or 1) end
end

local now = 0
local function ms() return getMillis() end

--------------------------------------------------------------------------
-- Nuendo MultiPanner (MIDI)
--------------------------------------------------------------------------
local mpIdx, mpVal = {}, {}
for i, p in ipairs(MP) do
  mpIdx[p.id] = i
  mpVal[p.id] = (p.min < 0) and 0.5 or 0.0
end

local mode = 1
local PAGES = { 'p1', 'p3' }

local function mpText(id)
  local p = MP[mpIdx[id]]
  local v = p.min + mpVal[id] * (p.max - p.min)
  return string.format(p.fmt, v) .. p.unit
end

local function mpSendMidi(id)
  local i = mpIdx[id]
  local n = mpVal[id]
  if CFG.mpMode == 'pb' then
    local v = clamp(floor(n * 16383 + 0.5), 0, 16383)
    sendMIDI({ 0xE0 + ((i - 1) % 16), v % 128, floor(v / 128) }, MIDI_OUT)
  else
    local v = clamp(floor(n * 127 + 0.5), 0, 127)
    sendMIDI({ 0xB0, CFG.ccBase + i - 1, v }, MIDI_OUT)
  end
end

local function yToCtl(n) if CFG.xyYUp then return n end return 1 - n end

local function mpRefresh(id)
  for _, pg in ipairs(PAGES) do
    -- Potis
    setX(pg .. '_k_' .. id, mpVal[id])
    setText(pg .. '_k_' .. id .. '_val', mpText(id))
    -- Pads, falls im aktuellen Mode belegt
    local m = PAD_MODES[mode]
    for _, pad in ipairs({ 'pad1', 'pad2' }) do
      local c = C(pg .. '_' .. pad)
      local b = m[pad]
      if c and not c.values.touch then
        if b[1] == id then c.values.x = mpVal[id] end
        if b[2] == id then c.values.y = yToCtl(mpVal[id]) end
      end
      if b[1] == id or b[2] == id then
        local p1, p2 = MP[mpIdx[b[1]]], MP[mpIdx[b[2]]]
        setText(pg .. '_' .. pad .. '_val',
          p1.name .. ' ' .. mpText(b[1]) .. '    ' .. p2.name .. ' ' .. mpText(b[2]))
      end
    end
  end
end

local function applyMode()
  local m = PAD_MODES[mode]
  for _, pg in ipairs(PAGES) do
    setText(pg .. '_modeLbl', 'MODE\n' .. m.name)
    for _, pad in ipairs({ 'pad1', 'pad2' }) do
      local b = m[pad]
      local p1, p2 = MP[mpIdx[b[1]]], MP[mpIdx[b[2]]]
      setText(pg .. '_' .. pad .. '_title', b[3] .. '  ·  ' .. p1.name .. ' / ' .. p2.name)
    end
  end
  for _, p in ipairs(MP) do mpRefresh(p.id) end
end

local function mpSet(id, n, send)
  mpVal[id] = clamp(n, 0, 1)
  if send then mpSendMidi(id); monAdd('→ MultiPanner ' .. MP[mpIdx[id]].name .. ' ' .. mpText(id), 'out:mp' .. id)
  else monAdd('← MultiPanner ' .. MP[mpIdx[id]].name .. ' ' .. mpText(id), 'in:mp' .. id) end
  mpRefresh(id)
end

--------------------------------------------------------------------------
-- IEM (OSC)
--------------------------------------------------------------------------
local iemVal = { az = 0, el = 0, wid = 0, yaw = 0, pitch = 0, maz = 0, mel = 0 }

local nuVal, nuTitle, nuPlug, iemMsb = {}, {}, {}, {}
local IEM_BY_CC = {}
for id, p in pairs(IEM) do if p.cc then IEM_BY_CC[p.cc] = id end end

local function degText(v) return string.format('%+.1f°', v) end
-- im MIDI-Weg zeigt das Feld Nuendos eigenen Anzeigewert, sobald einer da ist
local function valText(id, v)
  if CFG.iemVia == 'midi' and nuVal[id] then return nuVal[id] end
  return degText(v)
end

local function placeMarker(circleName, markName, deg)
  local cc, mk = C(circleName), C(markName)
  if not (cc and mk) then return end
  local f = cc.frame
  local r = math.rad(deg)
  local R = 0.46
  -- 0° = oben (vorn), positive Winkel = links (IEM-Konvention)
  local cx = f.x + f.w * (0.5 - R * math.sin(r))
  local cy = f.y + f.h * (0.5 - R * math.cos(r))
  local s = mk.frame.w
  mk.frame = Rectangle(cx - s / 2, cy - s / 2, s, s)
end

-- osc-Variante: Fader/Potis haben eigene OSC-Messages und bekommen ihren Wert vom Plugin;
-- das Skript setzt dort nur noch Text (sonst würde es dieselben Werte doppelt senden)
local NATIVE = { p2_el = true, p2_pitch = true, p3_az = true, p3_el = true, p3_wid = true, p4_el = true }
local function setIEMx(name, n)
  if CFG.iemVia == 'osc' and NATIVE[name] then return end
  setX(name, n)
end

local function iemRefresh(id)
  local p, v = IEM[id], iemVal[id]
  local n = (v - p.min) / (p.max - p.min)
  if id == 'az' then
    placeMarker('p2_encCircle', 'p2_encMark', v)
    setText('p2_encCircle_val', valText(id, v))
    setIEMx('p3_az', n); setText('p3_az_val', valText(id, v))
  elseif id == 'yaw' then
    placeMarker('p2_rotCircle', 'p2_rotMark', v)
    setText('p2_rotCircle_val', valText(id, v))
  elseif id == 'el' then
    setIEMx('p2_el', n); setText('p2_el_val', valText(id, v))
    setIEMx('p3_el', n); setText('p3_el_val', valText(id, v))
  elseif id == 'pitch' then
    setIEMx('p2_pitch', n); setText('p2_pitch_val', valText(id, v))
  elseif id == 'wid' then
    setIEMx('p3_wid', n); setText('p3_wid_val', valText(id, v))
  elseif id == 'maz' then
    placeMarker('p4_encCircle', 'p4_encMark', v)
    setText('p4_encCircle_val', degText(v))
  elseif id == 'mel' then
    setIEMx('p4_el', n); setText('p4_el_val', degText(v))
  end
end

local function iemSendMidi(id, v)
  local p = IEM[id]
  if not p.cc then return end
  local v14 = floor(clamp((v - p.pmin) / (p.pmax - p.pmin), 0, 1) * 16383 + 0.5)
  sendMIDI({ 0xB0 + CFG.iemCh, p.cc, floor(v14 / 128) }, MIDI_OUT)
  sendMIDI({ 0xB0 + CFG.iemCh, p.cc + 32, v14 % 128 }, MIDI_OUT)
end

local function iemSet(id, v, send)
  local p = IEM[id]
  v = clamp(v, p.min, p.max)
  iemVal[id] = v
  if send then
    monAdd('→ ' .. p.name .. ' ' .. degText(v), 'out:' .. id)
    if CFG.iemVia == 'midi' and p.cc then nuVal[id] = nil; iemSendMidi(id, v) else sendF(p.conn, p.addr, v) end
  end
  iemRefresh(id)
end

-- Text von Nuendo (SysEx F0 7D 54 <Feld> <ASCII> F7): 0 Spur, 1-7 Parametername,
-- 11-17 Anzeigewert, 20/21 Pluginname (Encoder/Rotator)
local function nuHeaders()
  setText('p2_encTitle', (nuPlug[20] or 'IEM StereoEncoder') .. ' · ' .. (nuTitle[1] or 'Azimuth'))
  setText('p2_rotTitle', (nuPlug[21] or 'IEM SceneRotator') .. ' · ' .. (nuTitle[5] or 'Yaw'))
  setText('p2_el_title', nuTitle[2] or 'ELEV')
  setText('p2_pitch_title', nuTitle[6] or 'PITCH')
  setText('p3_az_title', nuTitle[1] or 'IEM Azimuth')
  setText('p3_el_title', nuTitle[2] or 'IEM Elevation')
  setText('p3_wid_title', nuTitle[4] or 'IEM Width')
end

local function onSysex(m)
  if m[2] ~= 0x7D or m[3] ~= 0x54 or not m[4] then return end
  local f, chars = m[4], {}
  for i = 5, #m - 1 do chars[#chars + 1] = string.char(m[i]) end
  local s = table.concat(chars):match('^%s*(.-)%s*$')
  if f == 0 then
    setText('nu_track', s ~= '' and s or '–')
    monAdd('◆ gewählte Spur: ' .. (s ~= '' and s or '–'), 'trk')
  elseif f >= 1 and f <= 7 then
    nuTitle[f] = s; nuHeaders()
  elseif f >= 11 and f <= 17 then
    local id = IEM_BY_CC[f - 10]
    if id then
      if s:match('^[-+]?%d+%.?%d*$') then s = s .. '°' end
      nuVal[id] = s; iemRefresh(id)
    end
  elseif f == 20 or f == 21 then
    nuPlug[f] = s; nuHeaders()
    monAdd('◆ ' .. (f == 20 and 'Insert 4' or 'Insert 5') .. ': ' .. (s ~= '' and s or 'kein IEM-Plugin erkannt'), 'plug' .. f)
  end
end

local function circleToDeg(c)
  local dx = c.values.x - 0.5
  local dy = c.values.y - 0.5
  if not CFG.xyYUp then dy = -dy end
  if dx * dx + dy * dy < 0.0064 then return nil end   -- Mitte ignorieren
  return math.deg(atan2(-dx, dy))                        -- links = +
end

--------------------------------------------------------------------------
-- TotalMix: Lautstärken, Labels, DIM, Mute, Meter, Snapshot-LEDs laufen über die
-- eigenen Messages der Controls. Hier nur: Start-Sync, Snapshot-Blinken,
-- Peak-Hold, EQ-Kurve, EQ-Fenster auf/zu.
--------------------------------------------------------------------------
local tm = { snap = nil, snapMod = false, snapT = -100000, syncT = -100000, cache = {}, lastRx = -100000 }

local function tmSync()                       -- wie die SYNC-Taste: Seite 1, Output-Bus
  sendBare('tm', '/1')
  sendF('tm', '/1/busOutput', 1)
  sendF('tm', '/setBankStart', 0)
  tm.syncT = ms()
end

local function markChanged(key, v)
  local old = tm.cache[key]
  tm.cache[key] = v
  if old == nil or old == v then return end
  local t = ms()
  if tm.snap and t - tm.snapT > CFG.snapGraceMs and t - tm.syncT > CFG.snapGraceMs then
    tm.snapMod = true
  end
end

local function snapPaint(blinkOn)
  for i = 1, 4 do
    local led = 'snap' .. i .. '_led'
    if tm.snap == i and tm.snapMod and CFG.snapBlink and not blinkOn then
      setColor(led, 0.45, 0.28, 0.06, 1)      -- dunkle Phase beim Blinken
    else
      setColor(led, 0.95, 0.64, 0.23, 1)
    end
  end
end

-- Peak-Hold über den nativen Metern (Fader mt_main_L ... bekommen /1/levelN... direkt)
local METERS = { 'mt_main_L', 'mt_main_R', 'mt_ph_L', 'mt_ph_R' }
local hold = {}
for _, n in ipairs(METERS) do hold[n] = { v = 0, t = 0 } end

local function levelDb(v)
  if v <= 0 then return nil end
  if CFG.levelIsLinear then return 20 * log10(v) end
  return nil
end

local function drawHolds(t, dt)
  for _, n in ipairs(METERS) do
    local f, hb = C(n), C(n .. '_hold')
    if f and hb then
      local h, v = hold[n], f.values.x
      if v >= h.v then h.v = v; h.t = t
      elseif t - h.t > CFG.holdMs then h.v = max(v, h.v - dt * 0.5) end
      local fr = f.frame
      hb.frame = Rectangle(fr.x, fr.y + fr.h * (1 - h.v) - 1, fr.w, 2)
    end
  end
  for _, out in ipairs({ 'main', 'ph' }) do
    local v = max(hold['mt_' .. out .. '_L'].v, hold['mt_' .. out .. '_R'].v)
    local db = levelDb(v)
    if db and abs(db) < 0.05 then db = 0 end
    setText('mt_' .. out .. '_peak', db and string.format('%.1f', db) or '-∞')
  end
end

-- EQ (TotalMix Seite 2, eine Spur: Main oder Phones) ------------------------
local eq = { en = 0, lcEn = 0, lcFreq = 20, lcGrade = 6, side = 'MAIN', seenVal = {}, dirty = true,
             b = { { t = 'Low Shelf', f = 100, g = 0, q = 0.7 },
                   { t = 'Bell', f = 1000, g = 0, q = 0.7 },
                   { t = 'High Shelf', f = 8000, g = 0, q = 0.7 } } }

local function parseNum(s)
  if type(s) ~= 'string' then return tonumber(s) end
  local n = tonumber(s:match('[-+]?%d+%.?%d*'))
  if n and s:match('%d%s*[kK]') then n = n * 1000 end
  return n
end

local function eqHandle(key, val)
  local e = eq
  local band = tonumber(key:match('(%d)Val$') or key:match('(%d)$'))
  local isVal = key:match('Val$') ~= nil
  local base = key:gsub('Val$', ''):gsub('%d$', '')
  if base == 'eqEnable' then e.en = (tonumber(val) or 0) > 0.5 and 1 or 0
  elseif base == 'lowcutEnable' then e.lcEn = (tonumber(val) or 0) > 0.5 and 1 or 0
  elseif isVal then
    e.seenVal[base .. (band or '')] = true
    local n = parseNum(val)
    if base == 'lowcutFreq' and n then e.lcFreq = n
    elseif base == 'lowcutGrade' and n then e.lcGrade = n
    elseif band and e.b[band] then
      if base == 'eqType' then e.b[band].t = tostring(val)
      elseif base == 'eqFreq' and n then e.b[band].f = n
      elseif base == 'eqGain' and n then e.b[band].g = n
      elseif base == 'eqQ' and n then e.b[band].q = n
      end
    end
  elseif band and e.b[band] and not e.seenVal[base .. band] and type(val) == 'number' then
    if base == 'eqFreq' then e.b[band].f = math.exp(val * (math.log(20000) - math.log(20)) + math.log(20))
    elseif base == 'eqGain' then e.b[band].g = val * 40 - 20
    elseif base == 'eqQ' then e.b[band].q = 0.4 + val * 9.5
    end
  else
    return
  end
  e.dirty = true
end

local FS = 48000
local function biquad(t, f0, g, q)
  local A = 10 ^ (g / 40)
  local w0 = 2 * math.pi * f0 / FS
  local cs, sn = math.cos(w0), math.sin(w0)
  local al = sn / (2 * max(q, 0.1))
  local sA = math.sqrt(A)
  local lt = string.lower(t or '')
  if lt:find('shelf') and lt:find('low') then
    return A * ((A + 1) - (A - 1) * cs + 2 * sA * al), 2 * A * ((A - 1) - (A + 1) * cs),
           A * ((A + 1) - (A - 1) * cs - 2 * sA * al),
           (A + 1) + (A - 1) * cs + 2 * sA * al, -2 * ((A - 1) + (A + 1) * cs),
           (A + 1) + (A - 1) * cs - 2 * sA * al
  elseif lt:find('shelf') then
    return A * ((A + 1) + (A - 1) * cs + 2 * sA * al), -2 * A * ((A - 1) + (A + 1) * cs),
           A * ((A + 1) + (A - 1) * cs - 2 * sA * al),
           (A + 1) - (A - 1) * cs + 2 * sA * al, 2 * ((A - 1) - (A + 1) * cs),
           (A + 1) - (A - 1) * cs - 2 * sA * al
  elseif lt:find('pass') and (lt:find('high') or lt:find('hi')) then
    return (1 + cs) / 2, -(1 + cs), (1 + cs) / 2, 1 + al, -2 * cs, 1 - al
  elseif lt:find('pass') then
    return (1 - cs) / 2, 1 - cs, (1 - cs) / 2, 1 + al, -2 * cs, 1 - al
  end
  return 1 + al * A, -2 * cs, 1 - al * A, 1 + al / A, -2 * cs, 1 - al / A
end

local function magDb(b0, b1, b2, a0, a1, a2, f)
  local w = 2 * math.pi * f / FS
  local c1, s1, c2, s2 = math.cos(w), math.sin(w), math.cos(2 * w), math.sin(2 * w)
  local nr, ni = b0 + b1 * c1 + b2 * c2, -(b1 * s1 + b2 * s2)
  local dr, di = a0 + a1 * c1 + a2 * c2, -(a1 * s1 + a2 * s2)
  return 10 * log10((nr * nr + ni * ni) / max(dr * dr + di * di, 1e-12))
end

local EQ_BARS, EQ_RANGE = 48, 20
local function eqResponse(e, f)
  local db = 0
  if e.en == 1 then
    for i = 1, 3 do
      local b = e.b[i]
      local t = (i == 2) and 'Bell' or b.t
      local b0, b1, b2, a0, a1, a2 = biquad(t, b.f, b.g, b.q)
      db = db + magDb(b0, b1, b2, a0, a1, a2, f)
    end
  end
  if e.lcEn == 1 then
    local n = max(1, floor((e.lcGrade or 6) / 6 + 0.5))
    db = db - 10 * log10(1 + (e.lcFreq / f) ^ (2 * n))
  end
  return db
end

local function fmtFreq(f)
  if f >= 1000 then return string.format('%.2f k', f / 1000) end
  return string.format('%.0f', f)
end

local function eqDraw()
  local e = eq
  if not e.dirty then return end
  local ov = C('eq_overlay')
  if not (ov and ov.visible) then return end
  e.dirty = false
  local bg = C('eq_bg')
  if not bg then return end
  local f = bg.frame
  local bw = f.w / EQ_BARS
  local mid = f.y + f.h / 2
  for i = 1, EQ_BARS do
    local fr = 20 * (1000 ^ ((i - 0.5) / EQ_BARS))
    local db = clamp(eqResponse(e, fr), -EQ_RANGE, EQ_RANGE)
    local h = abs(db) / EQ_RANGE * (f.h / 2)
    local bar = C('eq_b' .. i)
    if bar then
      if db >= 0 then
        bar.frame = Rectangle(f.x + (i - 1) * bw + 1, mid - h, bw - 2, max(h, 1))
      else
        bar.frame = Rectangle(f.x + (i - 1) * bw + 1, mid, bw - 2, max(h, 1))
      end
      if e.en == 1 or e.lcEn == 1 then bar.color = Color(1.0, 0.6, 0.15, 0.9)
      else bar.color = Color(0.5, 0.5, 0.5, 0.5) end
    end
  end
end

local function eqShow(side)
  eq.side = side
  eq.seenVal, eq.dirty = {}, true
  setText('eq_title', 'EQ · ' .. side)
  local ov = C('eq_overlay')
  if ov then ov.visible = true end
end

--------------------------------------------------------------------------
-- Eingehende Nachrichten (der Root sieht jede Nachricht zuerst)
--------------------------------------------------------------------------
local function arg1(message)
  local a = message[2]
  if a and a[1] then return a[1].value end
  return nil
end

local function connIndex(connections)
  if not connections then return nil end
  for i = 1, #connections do if connections[i] then return i end end
  return nil
end

local function onTM(path, v)
  local row = path:match('^/3/snapshots/(%d)/1$')
  if row then
    local idx = 9 - tonumber(row)
    if (v or 0) > 0.5 then
      if tm.snap ~= idx then tm.snapMod = false end
      tm.snap = idx; tm.snapT = ms()
    elseif tm.snap == idx then
      tm.snap = nil; tm.snapMod = false
    end
    snapPaint(true)
    return
  end
  local key = path:match('^/2/(.+)$')
  if key then
    if key:match('^eq') or key:match('^lowcut') then
      if not key:match('Val$') then markChanged('eq' .. eq.side .. key, v) end
      eqHandle(key, v)
    end
    return
  end
  if path:match('^/1/volume%d+$') or path:match('^/1/mute/') or path:match('^/1/pan%d+$') then
    markChanged(path, v)
  end
end

local tmSeenLevel = false
function onReceiveOSC(message, connections)
  local path = message[1]
  local v = arg1(message)
  local ci = connIndex(connections)
  local cn = ci and CONN_NAME[ci]
  if cn == 'enc' or cn == 'rot' or cn == 'menc' then
    local param = path:match('/([%w]+)$')
    local map = (cn == 'enc') and { azimuth = 'az', elevation = 'el', width = 'wid' }
             or (cn == 'rot') and { yaw = 'yaw', pitch = 'pitch' }
             or { masterAzimuth = 'maz', masterElevation = 'mel' }
    local id = map[param]
    if id and type(v) == 'number' then
      iemSet(id, v, false)
      monAdd('← OSC ' .. ci .. ' ' .. path .. ' ' .. string.format('%.1f', v), 'in:' .. path)
    end
  elseif cn == 'tm' then
    tm.lastRx = ms()
    onTM(path, v)
    if not path:find('level', 1, true) then
      monAdd('← TotalMix (OSC ' .. ci .. ') ' .. path .. ' ' .. tostring(v), 'tm:' .. path)
    elseif not tmSeenLevel then
      tmSeenLevel = true
      monAdd('← TotalMix (OSC ' .. ci .. ') sendet Pegel', 'tmlevel')
    end
  else
    monAdd('← OSC ' .. tostring(ci or '?') .. ' ' .. path .. ' (keine Verbindung zugeordnet: TotalMix = OSC 1)', 'unk:' .. path)
  end
  return false
end

function onReceiveMIDI(message, connections)
  local st, d1, d2 = message[1], message[2], message[3]
  if not st then return false end
  if st == 0xF0 then
    if not monOnSysex(message) then onSysex(message) end
    return false
  end
  local kind, ch = floor(st / 16), st % 16
  if CFG.iemVia == 'midi' and kind == 0xB and ch == CFG.iemCh then
    local id, v14 = IEM_BY_CC[d1], nil
    if id then
      iemMsb[d1] = d2; v14 = d2 * 128                  -- grob, das LSB folgt
    elseif d1 > 32 and IEM_BY_CC[d1 - 32] then
      id = IEM_BY_CC[d1 - 32]; v14 = (iemMsb[d1 - 32] or 0) * 128 + d2
    end
    if id then
      local p = IEM[id]
      iemSet(id, p.pmin + v14 / 16383 * (p.pmax - p.pmin), false)
      if d1 > 32 then monAdd('← ' .. p.name .. ' ' .. degText(iemVal[id]), 'in:' .. id) end
    end
    return false
  end
  if CFG.mpMode == 'pb' and kind == 0xE then
    local p = MP[ch + 1]
    if p then mpSet(p.id, (d1 + d2 * 128) / 16383, false) end
  elseif CFG.mpMode == 'cc' and kind == 0xB and ch == 0 then
    local p = MP[d1 - CFG.ccBase + 1]
    if p then mpSet(p.id, d2 / 127, false) end
  end
  return false
end

--------------------------------------------------------------------------
-- Bedienung (Controls melden sich per notify)
--------------------------------------------------------------------------
local IEM_CTL = { p2_el = 'el', p2_pitch = 'pitch', p3_az = 'az', p3_el = 'el', p3_wid = 'wid', p4_el = 'mel' }

local function onUI(name, touched)
  local c = C(name)
  if not c then return end
  -- MultiPanner Pads / Potis (MIDI, über das Skript)
  local pg, pad = name:match('^(p[13])_(pad[12])$')
  if pad then
    if not touched then return end
    local b = PAD_MODES[mode][pad]
    mpSet(b[1], c.values.x, true)
    mpSet(b[2], CFG.xyYUp and c.values.y or 1 - c.values.y, true)
    return
  end
  local id = name:match('^p[13]_k_(%w+)$')
  if id and mpIdx[id] then
    if touched then mpSet(id, c.values.x, true) end
    return
  end
  -- IEM-Kreise (Mathematik, Senden im Skript)
  if name == 'p2_encCircle' or name == 'p2_rotCircle' or name == 'p4_encCircle' then
    if not touched then return end
    local d = circleToDeg(c)
    if d then iemSet(({ p2_encCircle = 'az', p2_rotCircle = 'yaw', p4_encCircle = 'maz' })[name], d, true) end
    return
  end
  -- IEM-Fader/Potis: osc-Variante sendet selbst (eigene Message), Skript macht nur Text;
  -- MIDI-Variante sendet über das Skript
  local iid = IEM_CTL[name]
  if iid then
    local p = IEM[iid]
    local v = p.min + c.values.x * (p.max - p.min)
    if CFG.iemVia == 'osc' then
      iemVal[iid] = v; iemRefresh(iid)
    elseif touched then
      iemSet(iid, v, true)
    end
  end
end

local function onButton(name)
  if name == 'p1_mode' or name == 'p3_mode' then
    mode = mode % #PAD_MODES + 1; applyMode(); return
  end
  if name:match('^snap%d_?') then return end      -- Senden: eigene Messages
  if name == 'tm_sync' then tm.syncT = ms(); return end
  if name == 'tm_eqMain' or name == 'eq_sel_m' then eqShow('MAIN'); return end
  if name == 'tm_eqPh' or name == 'eq_sel_p' then eqShow('PHONES'); return end
  if name == 'eq_close' then
    local ov = C('eq_overlay'); if ov then ov.visible = false end
    return
  end
  if name == 'nu_prev' or name == 'nu_next' then
    local n = name == 'nu_prev' and 0 or 1
    sendMIDI({ 0x90 + CFG.iemCh, n, 127 }, MIDI_OUT)
    sendMIDI({ 0x90 + CFG.iemCh, n, 0 }, MIDI_OUT)
  end
end

function onReceiveNotify(key, value)
  if key == 'ui' then onUI(value, true)
  elseif key == 'fb' then onUI(value, false)
  elseif key == 'btn' then onButton(value)
  elseif key == 'release' then
    if value == 'p2_encCircle' or value == 'p2_rotCircle' or value == 'p4_encCircle' then
      local c = C(value)
      if c then c.values.x = 0.5; c.values.y = 0.5 end
    end
  end
end

--------------------------------------------------------------------------
-- Frame-Update: Peak-Hold, Blinken, EQ-Kurve
--------------------------------------------------------------------------
-- Panner ohne TotalMix: Werteübersicht rechts (Labels ro_<id>), 10x pro Sekunde
local lastRo = 0
local function roRefresh(t)
  if t - lastRo < 100 then return end
  lastRo = t
  for _, p in ipairs(MP) do setText('ro_' .. p.id, mpText(p.id)) end
  for id, v in pairs(iemVal) do setText('ro_' .. id, valText(id, v)) end
end

local lastT, didSync, blinkOn = 0, false, true
function update()
  local t = ms()
  local dt = (lastT > 0) and (t - lastT) / 1000 or 0.016
  lastT = t
  monDraw()
  if not CFG.withTM then roRefresh(t); return end
  if not didSync and t > 1000 then didSync = true; tmSync(); monAdd('→ TotalMix: Sync gesendet (/1, OSC ' .. CFG.conn.tm .. ')', 'tmsync') end
  if didSync and t - tm.lastRx > 6000 and t - tm.syncT > 6000 then   -- no answer yet: ask again
    tmSync(); monAdd('→ TotalMix: noch keine Antwort, Sync erneut gesendet (OSC ' .. CFG.conn.tm .. ')', 'tmsync')
  end
  drawHolds(t, dt)
  local b = (floor(t / 400) % 2) == 0
  if b ~= blinkOn then blinkOn = b; snapPaint(blinkOn) end
  eqDraw()
end

function init()
  ctl = {}
  applyMode()
  for id in pairs(iemVal) do iemRefresh(id) end
  snapPaint(true)
  local ov = C('eq_overlay'); if ov then ov.visible = false end
end
