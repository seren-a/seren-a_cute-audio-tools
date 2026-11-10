--[[ =========================================================================
  seren.a ✧ IEM monitor ✧ · Root-Skript (TouchOSC 2, 1280 x 1024, 5:4-Monitor)
  -------------------------------------------------------------------------
  Draufsicht + Spurliste, ohne Auswahlknöpfe und ohne großes Detailfeld.
  Ansichten (oben):  16 · 32v (Liste zweispaltig) · 32h (Reihen oben/unten) · 64 (Felder in den Ecken)
  Modi:              space (IEM-Encoder) · multi (Eingänge des MultiEncoders der gewählten Spur)
                     · panner (Nuendo MultiPanner über Quick Controls)
                     · room (dearVR PRO: Raum mit Wänden, Hörer, Quellen; nur Anzeige)
  Ziehen:            den Punkt anfassen, der am nächsten liegt, und bewegen. Im Kreis nur die
                     Richtung (Azimut), die Höhe im Horizont-Feld.
  Kreis:             wie IEM (lineare Elevation): Mitte = über dir, Rand = Horizont, Ring alle 15°,
                     unter dem Horizont gespiegelt und hohl. Breite (StereoEncoder) = zwei kleine Ringe.
  horizont:          Panorama (bzw. Rückansicht) halbtransparent unten dazu, der Kreis wird kleiner.
  64:                kurz alle Werte des Objekts, das sich gerade bewegt, am Rand seines 4x4-Blocks.
  farben:            Spurfarben <-> TouchOSC-Palette.   ⚙: Pegel, Ballistik, Aussehen, Spurtypen, Symbole.
  Verbindung: MIDI 1 = TouchOSC Bridge. Gegenstelle: serena_TouchOSC3D.js (Nuendo, 32 Spuren)
  oder reaper_seren3D.lua (Reaper, 64 Spuren). Protokoll: PROTOKOLL.md.
========================================================================= ]]

local CFG = {
  midiConn = 1, nMidi = 10,
  layout = '16',          -- Startansicht: '16', '32v', '32h', '32r' (4 Reihen à 8 unten), '64'
  pano = false,           -- Horizont-Overlay beim Start
  selectInDaw = true, followDaw = true,
  holdMs = 400, xyYUp = true, grabPx = 70,
}
local MAXO = 64
local PASTEL = {
  { 1.00, 0.54, 0.85 }, { 1.00, 0.62, 0.48 }, { 1.00, 0.83, 0.43 }, { 0.78, 0.95, 0.42 },
  { 0.48, 0.94, 0.71 }, { 0.43, 0.95, 0.95 }, { 0.48, 0.78, 1.00 }, { 0.60, 0.65, 1.00 },
  { 0.77, 0.61, 1.00 }, { 0.95, 0.61, 1.00 }, { 1.00, 0.56, 0.66 }, { 1.00, 0.70, 0.90 },
  { 0.70, 1.00, 0.94 }, { 1.00, 0.95, 0.66 }, { 0.82, 0.70, 1.00 }, { 0.66, 0.90, 1.00 },
}
local DEG, WID, GAIN, MPR = { -180, 180 }, { -360, 360 }, { -60, 10 }, { -100, 100 }
local floor, abs, min, max, sqrt = math.floor, math.abs, math.min, math.max, math.sqrt
local sin, cos, rad, deg = math.sin, math.cos, math.rad, math.deg
local atan2 = math.atan2 or math.atan
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local MIDI_OUT = {}
for i = 1, CFG.nMidi do MIDI_OUT[i] = (i == CFG.midiConn) end

-- Geometrie je Ansicht (muss zu build.py passen)
local GEO = {
  ['16']  = { ca = { 8, 64, 924, 924 }, n = 16, pano = 1 },
  ['32v'] = { ca = { 8, 64, 924, 924 }, n = 32, pano = 1 },
  ['32h'] = { ca = { 240, 142, 800, 800 }, n = 32, pano = 2 },
  ['32r'] = { ca = { 330, 62, 620, 620 }, n = 32, pano = 4 },   -- v8.13: Ansicht oben, 32 Spuren in 4 Reihen à 8 unten
  ['64']  = { ca = { 160, 62, 960, 960 }, n = 64, pano = 3 },
}

local PH = 0.34          -- Horizont-Band unten (muss zu build.py passen)
local obj, me = {}, {}
for k = 1, MAXO do
  obj[k] = { k = k, name = '', mpName = '', icon = '', col = nil, flags = 0, sel = false,
             az = 0, el = 0, wid = 0, yaw = 0, pitch = 0, roll = 0, x = 0, y = 0, z = 0,
             seenEnc = false, seenRot = false, seenMp = false, lvlIn = 0, hold = {},
             rx = 0, ry = 0, rz = 0, room = nil, roomName = '', seenDv = false }
end
for k = 1, 16 do me[k] = { az = 0, el = 0, gain = 0, hold = {} } end
local meInfo = { count = 0, name = '' }
local msb = {}
local src = { name = nil, t = -1e9 }
local bank, win = 0, 16
local mode, layout, panoOn = 'iem', CFG.layout, CFG.pano
local cur = { iem = nil, me = nil, mp = nil, room = nil }
local roomTM, roomSM = nil, nil   -- room view mappings (metres -> screen), set while drawing
local logOpen, cfgOpen = false, false
local dirty, relayout = true, true
local dragK, dragArea = nil, nil
local moved, quietUntil = {}, 0   -- 64er-Ansicht: moved[k] = Zeit der letzten Bewegung
-- Liste/Felder: nur Spuren mit passendem Plugin (LOOK.onlyPlug). slotK[i] = Objekt in Feld i
local slotK, kSlot = {}, {}

local ctl = {}
local function C(name)
  local c = ctl[name]
  if c == nil then c = root:findByName(name, true); if c then ctl[name] = c end end
  return c
end
local cache = {}
local function setText(name, s)
  if cache['t' .. name] == s then return end
  local c = C(name); if c then c.values.text = s; cache['t' .. name] = s end
end
local function setVisible(name, v)
  if cache['v' .. name] == v then return end
  local c = C(name); if c then c.visible = v; cache['v' .. name] = v end
end
local function setColor(name, rgb, a)
  local key = string.format('%.3f%.3f%.3f%.2f', rgb[1], rgb[2], rgb[3], a)
  if cache['c' .. name] == key then return end
  local c = C(name); if c then c.color = Color(rgb[1], rgb[2], rgb[3], a); cache['c' .. name] = key end
end
local function setFrame(name, x, y, w, h)
  local key = string.format('%.1f,%.1f,%.1f,%.1f', x, y, w, h)
  if cache['f' .. name] == key then return end
  local c = C(name); if c then c.frame = Rectangle(x, y, w, h); cache['f' .. name] = key end
end
local function setSize(name, s)
  local c = C(name); if c and c.textSize ~= s then c.textSize = s end
end
local function ms() return getMillis() end
local function scale(n, r) return r[1] + n * (r[2] - r[1]) end
local function unscale(v, r) return clamp((v - r[1]) / (r[2] - r[1]), 0, 1) end
local function fmtDeg(v) if abs(v) < 0.05 then v = 0 end return string.format('%+.0f°', v) end
local function fmtMp(v) return string.format('%+.0f', v) end
local function hasBit(f, b) return floor(f / b) % 2 == 1 end

local function trackNo(k)                       -- echte Spurnummer (Reaper schickt sie seit v8.4), sonst Bankplatz
  local o = obj[k]
  if o and o.num and o.num > 0 then return o.num end
  return bank * 16 + k
end
local function nShown() return min(GEO[layout].n, mode == 'me' and 16 or 64) end
local function present(k)
  if mode == 'me' then return k <= meInfo.count end
  if k > win then return false end
  local o = obj[k]
  if o.name ~= '' and not typeShown(o.flags) then return false end
  if mode == 'iem' then return hasBit(o.flags, 1) or o.seenEnc end
  if mode == 'room' then return o.seenDv end
  return hasBit(o.flags, 2) or o.seenMp
end
local function colorOf(k)
  if mode ~= 'me' and LOOK.colors == 'daw' and obj[k].col then return obj[k].col end
  local c, f = PASTEL[(k - 1) % 16 + 1], 1 - 0.13 * floor((k - 1) / 16)
  return { c[1] * f, c[2] * f, c[3] * f }
end
local function nameOf(k)
  local o = obj[k]
  if mode == 'me' then return 'Eingang ' .. k end
  if mode == 'mp' then return o.mpName ~= '' and o.mpName or (o.name ~= '' and o.name or 'Objekt ' .. k) end
  return o.name ~= '' and o.name or ('Spur ' .. trackNo(k))
end

--------------------------------------------------------------------------
-- Senden
--------------------------------------------------------------------------
local KIND_CH = { [0] = 12, [1] = 6, [2] = 10 }
local function sendObj(kind, k, p, n)
  local o = k - 1
  local v = floor(clamp(n, 0, 1) * 16383 + 0.5)
  if o < 16 then
    local ch, cc = KIND_CH[kind] + floor(o / 8), 4 * (o % 8) + p
    sendMIDI({ 0xB0 + ch, cc, floor(v / 128) }, MIDI_OUT)
    sendMIDI({ 0xB0 + ch, cc + 32, v % 128 }, MIDI_OUT)
  else
    sendMIDI({ 0xF0, 0x7D, 0x4F, 10, kind, o, p, floor(v / 128), v % 128, 0xF7 }, MIDI_OUT)
  end
end
local function sendMe(k, p, n)
  local v = floor(clamp(n, 0, 1) * 16383 + 0.5)
  local ch, cc = 8 + floor((k - 1) / 8), 4 * ((k - 1) % 8) + p
  sendMIDI({ 0xB0 + ch, cc, floor(v / 128) }, MIDI_OUT)
  sendMIDI({ 0xB0 + ch, cc + 32, v % 128 }, MIDI_OUT)
end
local function note(ch, n) sendMIDI({ 0x90 + ch, n, 127 }, MIDI_OUT); sendMIDI({ 0x90 + ch, n, 0 }, MIDI_OUT) end

grSend = function(b) sendMIDI(b, MIDI_OUT) end
local viewLoaded, viewSent, viewAsked, viewT = false, nil, false, 0
local function viewExtra() return { mode = mode, lay = layout, pano = panoOn and 1 or 0 } end
local function viewTick()                          -- v8.15: einmal fragen, dann Änderungen nach Reaper (höchstens 1× pro s)
  if src.name ~= 'REAPER' then return end
  local t = getMillis()
  if not viewAsked then viewAsked = true; viewT = t; sendMIDI({ 0xF0, 0x7D, 0x4F, 0x0F, 1, 0xF7 }, MIDI_OUT); return end
  if not viewLoaded and t - viewT > 2000 then viewLoaded = true end   -- nichts gespeichert: so lassen
  if not viewLoaded or t - viewT < 1000 then return end
  viewT = t
  local st = cfgState(viewExtra())
  if st ~= viewSent then
    viewSent = st
    local b = { 0xF0, 0x7D, 0x4F, 0x0E, 1 }
    for i = 1, #st do b[#b + 1] = st:byte(i) % 128 end
    b[#b + 1] = 0xF7
    sendMIDI(b, MIDI_OUT)
  end
end
local filtSent = nil
local function sendFilter()                      -- Spurfilter an die DAW (nur bei Änderung)
  local b, p = filterBits()
  local key = b .. ',' .. p
  if key == filtSent then return end
  filtSent = key
  sendMIDI({ 0xF0, 0x7D, 0x4F, 0x0B, b, p, 0xF7 }, MIDI_OUT)
end

--------------------------------------------------------------------------
-- Eingang
--------------------------------------------------------------------------
local function sysexText(m, from)
  local t = {}
  for i = from, #m - 1 do local c = m[i]; if c >= 32 and c <= 126 then t[#t + 1] = string.char(c) end end
  return table.concat(t)
end
local function clearAll()
  for i = 1, MAXO do
    local o = obj[i]
    o.name, o.mpName, o.icon, o.col, o.flags, o.sel, o.lvlIn = '', '', '', nil, 0, false, 0
    o.seenEnc, o.seenRot, o.seenMp = false, false, false
    o.seenDv, o.room, o.roomName = false, nil, ''
    o.num = nil
  end
  meInfo.count, meInfo.name = 0, ''
  lvReset(); dirty = true
  moved, quietUntil = {}, ms() + 2500     -- the first full sync is not "movement"
end
local KIND_PARTS = { [0] = { 'az', 'el', 'wid' }, [1] = { 'yaw', 'pitch', 'roll' }, [2] = { 'x', 'y', 'z' }, [3] = { 'rx', 'ry', 'rz' } }
local DVR = { -32, 32 }   -- dearVR position in metres
local RANGE = { az = DEG, el = DEG, wid = WID, yaw = DEG, pitch = DEG, roll = DEG, x = MPR, y = MPR, z = MPR, gain = GAIN,
                rx = DVR, ry = DVR, rz = DVR }
local function setPart(t, kind, part, n01)
  if kind == 0 then t.seenEnc = true elseif kind == 1 then t.seenRot = true elseif kind == 2 then t.seenMp = true
  elseif kind == 3 then t.seenDv = true end
  if ms() - (t.hold[part] or -1e9) < CFG.holdMs then return end
  local v = scale(n01, RANGE[part])
  if abs(v - (t[part] or 0)) > 0.3 and t.k and ms() > quietUntil then moved[t.k] = ms() end
  t[part] = v; dirty = true
end

local function onSysex(m)
  if m[2] ~= 0x7D or m[3] ~= 0x4F or not m[4] then return end
  if monOnSysex(m) then return end
  if CPU.parse(m) then src.t = ms(); return end
  if grSysex(m) then cfgPaint(); dirty = true; return end
  if m[4] == 20 and m[5] == 1 then                -- v8.15: Voreinstellung aus Reaper, einmal nach dem Start
    if not viewLoaded then
      viewLoaded = true
      local t = {}
      for i = 6, #m - 1 do t[#t + 1] = string.char(m[i]) end
      local kv = cfgApplyState(table.concat(t))
      if kv.mode then mode = kv.mode end
      if kv.lay then layout = kv.lay; relayout = true; cache = {} end
      if kv.pano then panoOn = kv.pano == '1'; relayout = true; cache = {} end
      if cfgChanged then cfgChanged() end
      viewSent = cfgState(viewExtra())
    end
    dirty = true; return
  end
  if vsSysex(m) then cfgPaint(); dirty = true; return end
  local cmd = m[4]
  src.t = ms()
  local k = m[5] and (m[5] + 1)
  if cmd == 1 and k and k <= MAXO then obj[k].name = sysexText(m, 6)
  elseif cmd == 2 and k and k <= MAXO and m[8] then obj[k].col = { m[6] / 127, m[7] / 127, m[8] / 127 }
  elseif cmd == 3 and k and k <= MAXO and m[6] then obj[k].flags = m[6]
  elseif cmd == 4 then
    local s = sysexText(m, 5)
    if (s == '' and src.name) or (s ~= '' and src.name and s ~= src.name) then
      clearAll()
      if s ~= '' and src.switchT and ms() - src.switchT < 15000 then
        monAdd('◆ Achtung: ' .. src.name .. ' und ' .. s .. ' senden gleichzeitig - nur ein DAW-Skript laufen lassen', 'twodaw')
      end
      src.switchT = ms()
    end
    if s ~= '' and s ~= src.name then moved, quietUntil = {}, ms() + 2500 end   -- (neu) verbunden: Abgleich
    src.name = (s ~= '') and s or nil
    if src.name then monAdd('◆ verbunden: ' .. src.name, 'src') end
  elseif cmd == 5 and m[5] then
    if m[5] ~= bank then bank = m[5]; moved, quietUntil = {}, ms() + 2500; for i = 1, MAXO do obj[i].seenEnc, obj[i].seenRot, obj[i].seenMp, obj[i].sel, obj[i].seenDv = false, false, false, false, false end; cur.iem = nil; cur.room = nil end
    BK.onBank()
  elseif cmd == 6 and k and k <= MAXO then obj[k].mpName = sysexText(m, 6)
  elseif cmd == 7 then clearAll()
  elseif cmd == 9 and m[5] then
    meInfo.count, meInfo.name = m[5], sysexText(m, 6)
    if cur.me and cur.me > meInfo.count then cur.me = nil end
  elseif cmd == 10 and m[9] then
    local kind, kk, p = m[5], m[6] + 1, m[7]
    local parts = KIND_PARTS[kind]
    if parts and parts[p + 1] and kk <= MAXO then setPart(obj[kk], kind, parts[p + 1], (m[8] * 128 + m[9]) / 16383) end
  elseif cmd == 11 and k and k <= MAXO then obj[k].icon = sysexText(m, 6)
  elseif cmd == 16 and m[6] then                              -- Spurfilter der DAW (Reaper)
    if filterFromDaw(m[5], m[6]) then cfgPaint(); relayout = true end
    filtSent = table.concat({ filterBits() }, ',')
  elseif cmd == 17 and k and k <= MAXO and m[7] then obj[k].num = m[6] * 128 + m[7]
  elseif cmd == 12 and m[5] then win = clamp(m[5], 1, MAXO); relayout = true
  elseif cmd == 14 and k and k <= MAXO then        -- dearVR room: 6 walls in cm (2 bytes each) + preset name
    local o = obj[k]
    if m[17] and m[17] ~= 0xF7 then
      o.room = {}
      for i = 0, 5 do o.room[i + 1] = (m[6 + 2 * i] * 128 + m[7 + 2 * i]) / 100 end
      o.roomName = sysexText(m, 18)
    else o.room, o.roomName = nil, '' end
  end
  dirty = true
end

local CC_KIND = { [12] = 0, [13] = 0, [6] = 1, [7] = 1, [10] = 2, [11] = 2 }
local function onCC(ch, cc, val)
  if ch == 14 then if cc < MAXO then obj[cc + 1].lvlIn = val / 127 end; return end
  local isMe = (ch == 8 or ch == 9)
  if not CC_KIND[ch] and not isMe then return end
  local c, isLsb = cc, false
  if cc >= 32 then c, isLsb = cc - 32, true end
  if c >= 32 then return end
  local k, p = (ch % 2) * 8 + floor(c / 4) + 1, c % 4
  if p > 2 then return end
  local v14
  if isLsb then v14 = (msb[ch * 128 + c] or 0) * 128 + val else msb[ch * 128 + c] = val; v14 = val * 128 end
  if isMe then
    local part = ({ 'az', 'el', 'gain' })[p + 1]
    local t = me[k]
    if ms() - (t.hold[part] or -1e9) >= CFG.holdMs then t[part] = scale(v14 / 16383, RANGE[part]); dirty = true end
  else
    local kind = CC_KIND[ch]
    setPart(obj[k], kind, KIND_PARTS[kind][p + 1], v14 / 16383)
  end
end

function onReceiveMIDI(m, connections)
  local st = m[1]
  if not st then return false end
  if st == 0xF0 then onSysex(m); return false end
  local kind, ch = floor(st / 16), st % 16
  if kind == 0xB and m[2] and m[3] then onCC(ch, m[2], m[3])
  elseif (kind == 0x9 or kind == 0x8) and ch == 14 and m[2] and m[2] < MAXO then
    local k = m[2] + 1
    local on = (kind == 0x9 and (m[3] or 0) > 0)
    obj[k].sel = on
    if on and CFG.followDaw then cur.iem = k; cur.mp = k; cur.room = k end
    dirty = true
  end
  return false
end

--------------------------------------------------------------------------
-- Geometrie
--------------------------------------------------------------------------
local function CAfull() local a = GEO[layout].ca; return { x = a[1], y = a[2], w = a[3], h = a[4] } end
-- mit Horizont wird der Kreis kleiner und sitzt über dem Horizont-Band
local function CA()
  local f = CAfull()
  if not panoOn then return f end
  local s = f.h * (1 - PH) - 6
  return { x = f.x + (f.w - s) / 2, y = f.y, w = s, h = s }
end
local function PO()             -- Horizont-Band; in der 64er-Ansicht zwischen den Eckfeldern
  local a = CAfull(); local h = a.h * PH
  if layout == '64' then return { x = 240, y = a.y + a.h - h, w = 800, h = h } end
  return { x = a.x, y = a.y + a.h - h, w = a.w, h = h }
end
local function topR(f) return f.w / 2 - 14 end
-- Draufsicht wie IEM, lineare Elevation: Mitte +90°, Rand 0°; darunter gespiegelt (lower = true)
local function toTop(f, az, el)
  local e = clamp(el, -90, 90)
  local r = topR(f) * (90 - abs(e)) / 90
  local a = rad(az)
  return f.x + f.w / 2 - r * sin(a), f.y + f.h / 2 - r * cos(a), e < -0.5
end
-- im Kreis nur die Richtung: die Höhe bleibt (die stellt man im Horizont-Feld)
local function fromTop(f, px, py)
  local dx, dy = px - (f.x + f.w / 2), py - (f.y + f.h / 2)
  local r = sqrt(dx * dx + dy * dy)
  return (r > 6) and deg(atan2(-dx, -dy)) or nil, nil
end
local function toPano(f, az, el)
  local a = ((az + 180) % 360) - 180
  return f.x + f.w * (0.5 - a / 360), f.y + f.h * (0.5 - clamp(el, -90, 90) / 180)
end
local function fromPano(f, px, py)
  return clamp((0.5 - (px - f.x) / f.w) * 360, -180, 180), clamp((0.5 - (py - f.y) / f.h) * 180, -90, 90)
end
local function toSq(f, a, b) return f.x + f.w * (a + 100) / 200, f.y + f.h * (1 - (b + 100) / 200) end
local function fromSq(f, px, py) return clamp((px - f.x) / f.w * 200 - 100, -100, 100), clamp(100 - (py - f.y) / f.h * 200, -100, 100) end
local function xyPoint(xy)
  local f = xy.frame
  local y = CFG.xyYUp and (1 - xy.values.y) or xy.values.y
  return f.x + xy.values.x * f.w, f.y + y * f.h
end
local function posTop(k)
  if mode == 'room' then
    if not roomTM then return -999, -999 end
    return roomTM.map(obj[k].rx, obj[k].ry)
  end
  local f = CA()
  if mode == 'mp' then return toSq(f, obj[k].x, obj[k].y) end
  local t = (mode == 'me') and me[k] or obj[k]
  return toTop(f, t.az, t.el)
end
local function posPano(k)
  if mode == 'room' then
    if not roomSM then return -999, -999 end
    return roomSM.map(obj[k].ry, obj[k].rz)
  end
  local f = PO()
  if mode == 'mp' then return toSq(f, obj[k].x, obj[k].z) end
  local t = (mode == 'me') and me[k] or obj[k]
  return toPano(f, t.az, t.el)
end

--------------------------------------------------------------------------
-- Layout (Zellen der Liste, Punktgrößen) – bei Wechsel der Ansicht
--------------------------------------------------------------------------
local DOT = { ['16'] = 30, ['32v'] = 26, ['32h'] = 26, ['32r'] = 24, ['64'] = 20 }
local function cellRect(k)
  if layout == '16' then return 944, 64 + (k - 1) * 60, 328, 56, 'row' end
  if layout == '32v' then
    local col, r = floor((k - 1) / 16), (k - 1) % 16
    return 944 + col * 166, 64 + r * 60, 162, 56, 'narrow'
  end
  if layout == '32h' then
    local row, i = floor((k - 1) / 16), (k - 1) % 16
    return i * 80 + 1, (row == 0) and 60 or 914, 78, 108, 'tile'
  end
  if layout == '32r' then                       -- 4 Reihen à 8 unter der Ansicht
    local row, i = floor((k - 1) / 8), (k - 1) % 8
    return 4 + i * 159, 690 + row * 83, 155, 79, 'grid'
  end
  local gw, gh = CFG64.gridSize * 1280, CFG64.gridSize * 964
  local blk, i = floor((k - 1) / 16), (k - 1) % 16
  local bx = (blk % 2 == 0) and 4 or (1280 - 4 - gw)
  local by = (blk < 2) and 62 or (1024 - 4 - gh)
  local cw, ch = gw / 4, gh / 4
  return bx + (i % 4) * cw, by + floor(i / 4) * ch, cw - 2, ch - 2, 'grid'
end
local function layoutCell(k)
  local n = 'c' .. k
  local x, y, w, h, st = cellRect(k)
  setFrame(n, x, y, w, h)
  local cs = (st == 'row') and 36 or ((st == 'narrow') and 28 or ((st == 'tile') and 30 or 0))
  if st ~= 'grid' then setFrame(n .. '_numb', 0, 0, 0, 0) end
  if st == 'tile' then
    setFrame(n .. '_num', (w - cs) / 2, 6, cs, cs)
    setFrame(n .. '_name', 2, 40, w - 4, 34)
    setFrame(n .. '_val', 2, 74, w - 4, 16)
    setFrame(n .. '_glyph', w - 24, 4, 22, 22)
    setFrame(n .. '_lvl', 6, h - 10, 0, 4); setFrame(n .. '_hold', 6, h - 10, 2, 4)
    setFrame(n .. '_fx', 4, h - 3, w - 8, 2); setFrame(n .. '_grp', 0, 4, 3, h - 8)
  elseif st == 'grid' then        -- Nummer im Kreis, fett, 2 Größen größer; darunter die Werte
    local d = min(19, floor(h * 0.48))
    setFrame(n .. '_num', 2, 2, d, d); setFrame(n .. '_numb', 2.7, 2, d, d)
    setFrame(n .. '_name', d + 5, 1, w - d - 7, d + 2)
    setFrame(n .. '_val', 3, d + 3, w - 6, max(10, h - d - 10))
    setFrame(n .. '_glyph', w - 16, 1, 15, 15)
    setFrame(n .. '_lvl', 3, h - 6, 0, 3); setFrame(n .. '_hold', 3, h - 6, 2, 3)
    setFrame(n .. '_fx', 2, h - 2, w - 4, 1.5); setFrame(n .. '_grp', 0, 2, 2, h - 4)
  else
    setFrame(n .. '_num', 8, (h - cs) / 2, cs, cs)
    setFrame(n .. '_name', cs + 16, 2, w - cs - 46, h * 0.55)
    setFrame(n .. '_val', cs + 16, h * 0.52, w - cs - 22, h * 0.3)
    setFrame(n .. '_glyph', w - 30, 2, 28, h * 0.55)
    setFrame(n .. '_lvl', cs + 16, h - 8, 0, 4); setFrame(n .. '_hold', cs + 16, h - 8, 2, 4)
    setFrame(n .. '_fx', 6, h - 2, w - 12, 2); setFrame(n .. '_grp', 0, 6, 4, h - 12)
  end
  local fs = ({ row = 17, narrow = 13, tile = 12, grid = 9 })[st]
  setSize(n .. '_name', fs); setSize(n .. '_val', (st == 'row') and 12 or ((st == 'grid') and 8 or 10))
  setSize(n .. '_num', (st == 'row') and 14 or 11); setSize(n .. '_numb', 11)
  if layout == '32r' then setSize(n .. '_name', 14); setSize(n .. '_val', 12) end   -- 4×8: Felder groß genug für mehr Schrift
  local nc = C(n .. '_num'); if nc then nc.cornerRadius = (st == 'grid') and floor(min(19, h * 0.48) / 2) or 18 end
  setFrame(n .. '_tap', 0, 0, w, h)
  setFrame(n .. '_bg', 0, 0, w, h)
end
local function layoutDot(pre, k, s)
  local g = s * 2.6
  local gc = C(pre .. k)
  if gc then local f = gc.frame; setFrame(pre .. k, f.x, f.y, g, g) end
  local o = (g - s) / 2
  setFrame(pre .. k .. '_glow', o, o, s, s)
  setFrame(pre .. k .. '_dot', o, o, s, s)
  setFrame(pre .. k .. '_lo', o, o, s, s)
  setFrame(pre .. k .. '_ring', o - 5, o - 5, s + 10, s + 10)
  setFrame(pre .. k .. '_num', o, o, s, s)
  setSize(pre .. k .. '_num', (s >= 26) and 13 or 10)
end
local function doLayout()
  relayout = false
  local s = DOT[layout]
  for k = 1, MAXO do
    local inLayout = k <= GEO[layout].n
    setVisible('c' .. k, false)                 -- render() shows the ones in use
    if inLayout then layoutCell(k) end
    layoutDot('d', k, s)
  end
  for _, n in ipairs({ 'circ1', 'circ2', 'circ3', 'sq1', 'sq2', 'sq3', 'pano1', 'pano2', 'pano3',
                       'circ1s', 'circ2s', 'circ3s', 'sq1s', 'sq2s', 'sq3s' }) do setVisible(n, false) end
  local ca = CA()
  setFrame('top_xy', ca.x, ca.y, ca.w, ca.h)
  local po = PO()
  setFrame('pano_xy', po.x, po.y, po.w, po.h)
  for _, n in ipairs({ '16', '32v', '32h', '32r', '64' }) do
    setColor('lay_' .. n .. '_bg', (n == layout) and theme().accent or theme().pill, 1)
  end
  dirty = true
end

--------------------------------------------------------------------------
-- Zeichnen
--------------------------------------------------------------------------
local lvPos, lvGlow, lvHold, lvVal = {}, {}, {}, {}
local function drawDot(pre, k, px, py, glow, isCur, col, show, lower)
  setVisible(pre .. k, show)
  if not show then return end
  local g = C(pre .. k)
  if not g then return end
  local w = g.frame.w
  setFrame(pre .. k, px - w / 2, py - w / 2, w, w)
  if pre == 'p' then setColor(pre .. k, col, 0.85); return end
  local soft = (cur[mode] and not isCur) and 0.45 or 1
  local s = w / 2.6
  local gs = s + (w - s) * clamp(glow, 0, 1)
  setFrame(pre .. k .. '_glow', (w - gs) / 2, (w - gs) / 2, gs, gs)
  setColor(pre .. k .. '_glow', col, soft * (0.08 + 0.45 * glow))
  setColor(pre .. k .. '_dot', col, lower and soft * 0.18 or soft * (0.78 + 0.22 * glow))
  setVisible(pre .. k .. '_lo', lower == true)
  if lower then setColor(pre .. k .. '_lo', col, soft) end
  setVisible(pre .. k .. '_ring', isCur)
  local showIcon = LOOK.icons == 'dot' or LOOK.icons == 'both'
  local ic = (showIcon and mode ~= 'me') and iconFor(obj[k].icon, obj[k].name) or ''
  setText(pre .. k .. '_icon', ic)
  if ic ~= '' then
    local is = s * 0.9 * LOOK.iconSize
    setFrame(pre .. k .. '_icon', (w + s) / 2 - is * 0.35, (w + s) / 2 - is * 0.45, is, is)
    setSize(pre .. k .. '_icon', floor(is * 0.8))
    local c = C(pre .. k .. '_icon'); if c then c.textColor = Color(1, 1, 1, LOOK.iconAlpha) end
  end
end

local ROOM_UI = {
  frame = function(n, x, y, w, h) setFrame(n, x, y, w, h) end,
  vis = function(n, v) setVisible(n, v) end,
  col = function(n, rgb, a) setColor(n, rgb, a) end,
  text = function(n, s) setText(n, s) end,
}
local roomIn = {}          -- k -> source sits in the room that is drawn
local function renderRoom()
  local on = (mode == 'room')
  for _, n in ipairs(RM.names(true)) do setVisible(n, false) end
  if not on then
    for _, n in ipairs(RM.ZOOM_CTL) do setVisible(n, false) end
    for _, n in ipairs(RM.gridNames('rt')) do setVisible(n, false) end
    for _, n in ipairs(RM.gridNames('rs')) do setVisible(n, false) end
    roomTM, roomSM = nil, nil
    return
  end
  for _, n in ipairs({ 'rt_floor', 'rt_lis', 'rt_nose', 'rt_title', 'rt_scale' }) do setVisible(n, true) end
  for _, n in ipairs(RM.ZOOM_CTL) do setVisible(n, not cfgOpen and not logOpen) end
  for _, n in ipairs({ 'rs_floor', 'rs_lis', 'rs_nose', 'rs_title', 'rs_scale' }) do setVisible(n, panoOn) end
  if not panoOn then for _, n in ipairs(RM.gridNames('rs')) do setVisible(n, false) end end
  local objs = {}
  for k = 1, nShown() do
    if present(k) then local o = obj[k]; objs[#objs + 1] = { k = k, room = o.room, name = o.roomName, x = o.rx, y = o.ry, z = o.rz } end
  end
  local ref, name, shared, others = RM.pick(objs, cur.room)
  roomIn = {}
  for _, o in ipairs(objs) do roomIn[o.k] = o.inRoom end
  roomTM, roomSM = RM.draw(ROOM_UI, CA(), panoOn and PO() or nil, ref, name or '', shared, others, objs, theme())
  if #objs == 0 then setText('rt_title', 'kein dearVR PRO auf diesen Spuren') end
end

local function renderDots()
  renderRoom()
  local n = nShown()
  for k = 1, MAXO do
    local on = k <= n and present(k)
    local col = on and colorOf(k) or PASTEL[1]
    local isCur = on and k == cur[mode]
    if on then
      local x, y, lower = posTop(k)
      drawDot('d', k, x, y, lvGlow[k] or 0, isCur, col, true, lower)
      if mode == 'room' and not roomIn[k] then setColor('d' .. k .. '_dot', col, 0.22); setColor('d' .. k .. '_glow', col, 0.05) end
      local o = obj[k]
      local wide = mode == 'iem' and not hasBit(o.flags, 4) and abs(o.wid) >= 2
      setVisible('wl' .. k, wide); setVisible('wr' .. k, wide)
      if wide then             -- Breite: linke/rechte Kante der Stereobasis, gleiche Höhe
        local f, ws = CA(), DOT[layout] * 0.45
        for side, sgn in pairs({ wl = 1, wr = -1 }) do
          local sx, sy = toTop(f, o.az + sgn * o.wid / 2, o.el)
          setFrame(side .. k, sx - ws / 2, sy - ws / 2, ws, ws)
          setColor(side .. k, col, (cur[mode] and not isCur) and 0.35 or 0.8)
        end
      end
      if panoOn then
        local px, py = posPano(k)
        drawDot('p', k, px, py, 0, isCur, col, true)
      else setVisible('p' .. k, false) end
    else
      setVisible('d' .. k, false); setVisible('p' .. k, false)
      setVisible('wl' .. k, false); setVisible('wr' .. k, false)
    end
  end
end

-- 64er-Ansicht: unter (unten: über) dem 4x4-Block alle Werte des Objekts, das sich gerade bewegt
local INFO_MS = 3000
local function infoText(k)
  local o = obj[k]
  local head = ((mode == 'me') and k or trackNo(k)) .. ' · ' .. nameOf(k)
  if mode == 'mp' then return head .. '\nX ' .. fmtMp(o.x) .. '   Y ' .. fmtMp(o.y) .. '   Z ' .. fmtMp(o.z) end
  if mode == 'room' then
    local d = sqrt(o.rx ^ 2 + o.ry ^ 2 + o.rz ^ 2)
    return head .. '\n' .. RM.fmtPos(o) .. (string.format('   Abstand %.1f m', d):gsub('%.', ',')) ..
      (o.roomName ~= '' and ('\nRaum ' .. o.roomName) or '')
  end
  if mode == 'me' then return head .. '\nAzimut ' .. fmtDeg(me[k].az) .. '   Elevation ' .. fmtDeg(me[k].el) .. '   Gain ' .. string.format('%+.1f dB', me[k].gain) end
  local t = head .. '\nAzimut ' .. fmtDeg(o.az) .. '   Elevation ' .. fmtDeg(o.el)
  if not hasBit(o.flags, 4) then t = t .. '   Breite ' .. fmtDeg(o.wid) end
  if o.seenRot then t = t .. '\nRotator  Yaw ' .. fmtDeg(o.yaw) .. '  Pitch ' .. fmtDeg(o.pitch) .. '  Roll ' .. fmtDeg(o.roll) end
  return t
end
local function renderInfo()
  local now = ms()
  for b = 1, 4 do
    local mv = nil
    for i = (b - 1) * 16 + 1, b * 16 do
      local k = slotK[i]
      if k and moved[k] and (not mv or moved[k] > mv.t) then mv = { k = k, t = moved[k] } end
    end
    local show = layout == '64' and mv and now - mv.t < INFO_MS and present(mv.k) and not cfgOpen and not logOpen
    setVisible('blk' .. b .. '_info', show and true or false)
    if show then
      local gx, gy, gw, gh = cellRect((b - 1) * 16 + 1)
      local bw, bh = CFG64.gridSize * 1280, CFG64.gridSize * 964
      local txt = infoText(mv.k)
      local lines = select(2, txt:gsub('\n', '')) + 1
      local ih = 8 + 15 * lines
      local iy = (b <= 2) and (gy + bh + 4) or (gy - ih - 4)
      setFrame('blk' .. b .. '_info', gx, iy, bw - 4, ih)
      setText('blk' .. b .. '_info', txt)
      local c = C('blk' .. b .. '_info')
      if c then local col = colorOf(mv.k); c.textColor = Color(1, 1, 1, 1); c.color = Color(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35, 0.92) end
    end
  end
end

local function buildSlots()
  slotK, kSlot = {}, {}
  local n = nShown()
  for k = 1, n do
    local inL = (mode == 'me') and (k <= meInfo.count) or (mode ~= 'me' and k <= win)
    local o = obj[k]
    local keep
    if mode == 'me' or LOOK.onlyPlug then keep = present(k)
    else keep = (o.name ~= '' and typeShown(o.flags)) or present(k) end
    if inL and keep then slotK[#slotK + 1] = k; kSlot[k] = #slotK end
  end
end

local function renderCells()
  local th = theme()
  local cu = cur[mode]
  buildSlots()
  for i = 1, MAXO do
    local cn = 'c' .. i
    local k = slotK[i]
    setVisible(cn, k ~= nil)
    if k then
      local o = obj[k]
      local on = present(k)
      local col = colorOf(k)
      local grid = (layout == '64' or layout == '32r')
      local isCur = (k == cu)
      if grid then setColor(cn .. '_bg', isCur and th.rowCur or col, isCur and 0.95 or CFG64.gridAlpha * (on and 0.75 or 0.3))
      else setColor(cn .. '_bg', isCur and th.rowCur or th.row, on and 1 or 0.5) end
      setColor(cn .. '_num', col, on and 1 or 0.3)
      local numTxt = tostring((mode ~= 'me') and trackNo(k) or k)
      setText(cn .. '_num', numTxt); setText(cn .. '_numb', grid and numTxt or '')
      local name = nameOf(k)
      if mode == 'iem' and not on and o.name ~= '' then name = o.name .. ' · –' end
      setText(cn .. '_name', (mode ~= 'me' and o.name == '' and not on) and '' or name)
      local val = ''
      if on then
        if mode == 'mp' then val = 'X ' .. fmtMp(o.x) .. ' Y ' .. fmtMp(o.y) .. ' Z ' .. fmtMp(o.z)
        elseif mode == 'room' then val = RM.fmtPos(o)
        elseif mode == 'me' then val = 'Az ' .. fmtDeg(me[k].az) .. ' El ' .. fmtDeg(me[k].el)
        else val = 'Az ' .. fmtDeg(o.az) .. ' El ' .. fmtDeg(o.el) end
        if mode ~= 'me' and lvVal[k] and layout ~= '32h' then val = val .. '  ' .. lvFormat(lvVal[k]) end
      end
      if grid then        -- nur die Zahlen, ohne Einheit, mit Abstand
        val = ''
        if on then
          local a, b, c
          if mode == 'mp' then a, b, c = o.x, o.y, o.z
          elseif mode == 'room' then a, b, c = o.rx, o.ry, o.rz
          elseif mode == 'me' then a, b, c = me[k].az, me[k].el, me[k].gain
          else a, b, c = o.az, o.el, o.wid end
          if mode == 'room' then val = (string.format('%.1f   %.1f   %.1f', a, b, c):gsub('%.', ','))
          else val = string.format('%d   %d   %d', floor(a + 0.5), floor(b + 0.5), floor(c + 0.5)) end
        end
      end
      setText(cn .. '_val', val)
      -- Kennzeichnung + Symbol
      local typ = typeOf(o.flags)
      setVisible(cn .. '_fx', LOOK.marks and mode ~= 'me' and typ == 'fx')
      setVisible(cn .. '_grp', LOOK.marks and mode ~= 'me' and typ == 'group')
      setColor(cn .. '_fx', th.accent2, 0.9); setColor(cn .. '_grp', th.accent, 0.95)
      local g = ''
      if LOOK.marks and mode ~= 'me' and typ == 'instr' then g = '♪' end
      if (LOOK.icons == 'list' or LOOK.icons == 'both') and mode ~= 'me' then
        local ic = iconFor(o.icon, o.name); if ic ~= '' then g = (g ~= '' and (g .. ' ') or '') .. ic end
      end
      setText(cn .. '_glyph', g)
      local gc = C(cn .. '_glyph'); if gc then gc.textColor = Color(th.text[1], th.text[2], th.text[3], LOOK.iconAlpha) end
      local nc = C(cn .. '_name'); if nc then nc.textColor = Color(th.text[1], th.text[2], th.text[3], on and 1 or 0.45) end
    end
  end
  renderInfo()
end

local function renderLevels()
  for i = 1, #slotK do
    local k = slotK[i]
    local cn = 'c' .. i
    local x, y, w, h, st = cellRect(i)
    local lx, lw, ly, lh
    if st == 'tile' then lx, lw, ly, lh = 6, w - 12, h - 10, 4
    elseif st == 'grid' then lx, lw, ly, lh = 3, w - 6, h - 6, 3
    else local cs = (st == 'row') and 36 or 28; lx, lw, ly, lh = cs + 16, w - cs - 26, h - 8, 4 end
    local p = (mode == 'me') and 0 or (lvPos[k] or 0)
    setFrame(cn .. '_lvl', lx, ly, max(0, floor(lw * p + 0.5)), lh)
    setColor(cn .. '_lvl', meterColor(p), 0.95)
    local hp = (mode == 'me') and 0 or (lvHold[k] or 0)
    setFrame(cn .. '_hold', lx + floor(lw * hp + 0.5) - 1, ly, 2, lh)
    setColor(cn .. '_hold', theme().meterHold, 0.9)
  end
end

local function render()
  dirty = false
  local th = theme()
  local srcOn = src.name and (ms() - src.t < 15000)
  setText('src_lbl', srcOn and (src.name .. ' ♡') or 'keine DAW')
  local n = nShown()
  if GR.assign then setText('range_lbl', grText())
  elseif mode == 'me' then setText('range_lbl', meInfo.count > 0 and ('✧ ' .. meInfo.name) or 'kein MultiEncoder')
  else
    local lo, hi
    for k = 1, min(n, win) do if obj[k].name ~= '' and obj[k].num then local x = obj[k].num; lo = lo or x; hi = x end end
    setText('range_lbl', lo and (lo == hi and tostring(lo) or (lo .. '–' .. hi)) or string.format('%d–%d', bank * 16 + 1, bank * 16 + min(n, win)))
  end
  if cur[mode] and not present(cur[mode]) then cur[mode] = nil end
  for _, m in ipairs({ 'iem', 'me', 'mp', 'room' }) do setColor('mode_' .. m .. '_bg', m == mode and th.accent or th.pill, 1) end
  setColor('pano_btn_bg', panoOn and th.accent2 or th.pill, 1)
  setColor('col_btn_bg', LOOK.colors == 'daw' and th.accent2 or th.pill, 1)
  setText('col_btn_lbl', LOOK.colors == 'daw' and 'spurfarben' or 'tosc farben')
  setColor('cfg_btn_bg', cfgOpen and th.accent2 or th.pill, 1)
  setColor('log_btn_bg', logOpen and th.accent2 or th.pill, 1)
  local gi = GEO[layout].pano
  local sm = panoOn and 's' or ''
  setVisible('circ' .. gi .. sm, mode ~= 'mp' and mode ~= 'room'); setVisible('sq' .. gi .. sm, mode == 'mp')
  setVisible('pano' .. gi, panoOn and mode ~= 'room')
  setColor('pano' .. gi .. '_fill', th.panel, CFG64.panoAlpha)
  setText('pano' .. gi .. '_title', mode == 'mp' and 'rückansicht · X × Z' or 'horizont · azimut × elevation')
  setVisible('pano_xy', panoOn and not logOpen and not cfgOpen)
  setVisible('mon_overlay', logOpen)
  setVisible('cfg_overlay', cfgOpen)
  renderCells()
end

local themeApplied = nil
local function applyTheme()
  local th = theme()
  themeApplied = LOOK.theme
  root.color = Color(th.bg[1], th.bg[2], th.bg[3], 1)
  for _, role in ipairs({ 'panel', 'line' }) do
    local list = root:findAllByName('th_' .. role, true)
    for _, c in ipairs(list or {}) do local a = th[role]; c.color = Color(a[1], a[2], a[3], (c.color and c.color.a) or 1) end
  end
  cache = {}
  relayout = true
end

--------------------------------------------------------------------------
-- Bedienung
--------------------------------------------------------------------------
local function moveTo(k, a, b, rear)
  local now = ms()
  moved[k] = now
  if mode == 'mp' then
    local o = obj[k]
    if a and abs(a - o.x) >= 0.05 then o.x = a; o.hold.x = now; sendObj(2, k, 0, unscale(a, MPR)) end
    local part = rear and 'z' or 'y'
    if b and abs(b - o[part]) >= 0.05 then o[part] = b; o.hold[part] = now; sendObj(2, k, rear and 2 or 1, unscale(b, MPR)) end
  elseif mode == 'me' then
    local t = me[k]
    if a and abs(a - t.az) >= 0.05 then t.az = a; t.hold.az = now; sendMe(k, 0, unscale(a, DEG)) end
    if b and abs(b - t.el) >= 0.05 then t.el = b; t.hold.el = now; sendMe(k, 1, unscale(b, DEG)) end
  else
    local t = obj[k]
    if a and abs(a - t.az) >= 0.05 then t.az = a; t.hold.az = now; sendObj(0, k, 0, unscale(a, DEG)) end
    if b and abs(b - t.el) >= 0.05 then t.el = b; t.hold.el = now; sendObj(0, k, 1, unscale(b, DEG)) end
  end
  dirty = true
end

local function nearest(px, py, pano)
  local best, bd = nil, CFG.grabPx * CFG.grabPx
  for k = 1, nShown() do
    if present(k) then
      local x, y
      if pano then x, y = posPano(k) else x, y = posTop(k) end
      local d = (x - px) ^ 2 + (y - py) ^ 2
      if d < bd then best, bd = k, d end
    end
  end
  return best
end

local function selectK(k)
  cur[mode] = k
  if mode ~= 'me' and CFG.selectInDaw and not obj[k].sel then note(14, k - 1) end
  if mode == 'room' then dirty = true end
  dirty = true
end

local function onXY(name, touchStart)
  if logOpen or cfgOpen then return end
  local c = C(name); if not c then return end
  local px, py = xyPoint(c)
  local pano = (name == 'pano_xy')
  if touchStart then
    dragK = nearest(px, py, pano)
    if dragK then selectK(dragK) end
    return
  end
  if not dragK or mode == 'room' then return end   -- room: show + select only
  if mode == 'mp' then
    local a, b = fromSq(pano and PO() or CA(), px, py)
    moveTo(dragK, a, b, pano)
  elseif pano then moveTo(dragK, fromPano(PO(), px, py))
  else moveTo(dragK, fromTop(CA(), px, py)) end
end

local function onButton(name)
  if cfgOpen and name ~= 'cfg_btn' then
    if name == 'cfg_close' then cfgOpen = false; dirty = true; return end
    if cfgButton(name) then if GR.assign then cfgOpen = false end; dirty = true; return end
  end
  if RM.button(name) then dirty = true; return end
  if name == 'bank_prev' then BK.press(-1); note(15, 2); return end
  if name == 'bank_next' then BK.press(1); note(15, 3); return end
  if name:match('^mode_') then mode = name:sub(6); dirty = true; return end
  if name:match('^lay_') then layout = name:sub(5); relayout = true; cache = {}; return end
  if name == 'pano_btn' then panoOn = not panoOn; relayout = true; cache = {}; return end
  if name == 'col_btn' then LOOK.colors = (LOOK.colors == 'daw') and 'tosc' or 'daw'; cfgPaint(); dirty = true; return end
  if name == 'cfg_btn' then cfgOpen = not cfgOpen; logOpen = false; cfgPaint(); dirty = true; return end
  if name == 'log_btn' then logOpen = not logOpen; cfgOpen = false; monDraw(true); dirty = true; return end
  local slot = tonumber(name:match('^c(%d+)_tap$') or '')
  local k = slot and slotK[slot]
  if k and GR.assign then                          -- v8.14: Spur in/aus Gruppe A–D
    sendMIDI({ 0xF0, 0x7D, 0x4F, 0x0D, GR.assign - 1, k - 1, 0xF7 }, MIDI_OUT)
    return
  end
  if k and present(k) then selectK(k) end
end

function onReceiveNotify(key, value)
  if key == 'btn' then onButton(value)
  elseif key == 'drag' then onXY(value, false)
  elseif key == 'grab' then onXY(value, true)
  elseif key == 'release' then dragK = nil
  elseif key == 'cfgf' then cfgFader(value) end
end

cfgChanged = function() if themeApplied ~= LOOK.theme then applyTheme() end; sendFilter(); relayout = true; dirty = true end

local lastT, lastRender = 0, 0
VS.id = 2                                        -- v8.15: Ansicht in Reaper merken
VS.extra = function() return { m = mode, lay = layout, pano = panoOn and 1 or 0 } end
VS.applyExtra = function(key, v)
  if key == 'm' and (v == 'iem' or v == 'me' or v == 'mp' or v == 'room') then mode = v end
  if key == 'lay' and GEO[v] then layout = v; relayout = true; cache = {} end
  if key == 'pano' then panoOn = (v == '1'); relayout = true; cache = {} end
end
function update()
  viewTick()
  local t = ms()
  vsTick(t, function(b) sendMIDI(b, MIDI_OUT) end)
  local dt = (lastT > 0) and (t - lastT) / 1000 or 0.016
  lastT = t
  if themeApplied ~= LOOK.theme then applyTheme() end
  if relayout then doLayout() end
  for k = 1, min(win, MAXO) do
    local v, pos, glow, hp = lvStep(k, obj[k].lvlIn, dt, t)
    lvVal[k], lvPos[k], lvGlow[k], lvHold[k] = v, pos, glow, hp
  end
  if dirty or t - lastRender > 500 then lastRender = t; render(); CPU.render(src.name, theme().text, theme().meterHot) end
  renderDots()
  renderLevels()
  if layout == '64' then renderInfo() end
  if logOpen then monDraw() end
  if mode == 'iem' or mode == 'room' then
    local n = 0
    for k = 1, min(win, MAXO) do if present(k) then n = n + 1 end end
    BK.step(n, function(d) note(15, d > 0 and 3 or 2) end)
  else BK.cancel() end
end

function init()
  ctl = {}; cache = {}
  moved, quietUntil = {}, ms() + 2500
  dirty, relayout = true, true
  themeApplied = nil
  cfgPaint()
end
