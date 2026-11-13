--[[ =========================================================================
  seren.a ✧ IEM space ✧ v3 · Root-Skript (TouchOSC 2, iPad quer)
  -------------------------------------------------------------------------
  Drei Modi (Pillen oben rechts):
    space    alle Encoder (StereoEncoder / MultiEncoder-Master) deiner Spuren,
             Rotator der gewählten Spur über Yaw/Pitch-Fader
    multi    die Eingänge des MultiEncoders der gewählten Spur (bis 16)
    panner   Nuendo MultiPanner-Objekte (Quick Controls): Draufsicht X/Y, Rückansicht X/Z
    room     dearVR PRO: Raum mit Wänden und Hörer (wie in dearVR), Quellen darin; nur Anzeige
  Draufsicht wie IEM (lineare Elevation): Mitte = über dir, Rand = Horizont, Ring alle 15°,
  unter dem Horizont gespiegelt und hohl. Im Kreis ziehen ändert nur die Richtung (Azimut),
  die Höhe stellt man im Panorama darunter. Breite (StereoEncoder) = zwei kleine Punkte.
  Oben ein Objekt antippen, dann in Draufsicht oder Panorama ziehen. Andere werden weicher,
  Punkte leuchten mit dem Pegel. LOG zeigt, was das DAW-Skript erkannt hat und was ankommt.
  Verbindung: MIDI 1 = TouchOSC Bridge. Gegenstelle: serena_TouchOSC3D.js (Nuendo) oder
  reaper_seren3D.lua (Reaper). Protokoll: PROTOKOLL.md.
========================================================================= ]]

local CFG = {
  midiConn = 1,
  nMidi = 10,
  N = 32,               -- Objekte (v8.13: 32; ohne Option „32“ werden nur 1–16 gezeigt)
  xyYUp = true,          -- XY: y = 1 oben. Reagiert Ziehen senkrecht verkehrt -> false
  selectInDaw = true,    -- Auswählen (Modus space) wählt auch die Spur in der DAW
  followDaw = true,      -- Auswahl in der DAW wählt hier mit
  holdMs = 400,          -- so lange nach dem Ziehen werden Rückmeldungen ignoriert
}

local PASTEL = {
  { 1.00, 0.54, 0.85 }, { 1.00, 0.62, 0.48 }, { 1.00, 0.83, 0.43 }, { 0.78, 0.95, 0.42 },
  { 0.48, 0.94, 0.71 }, { 0.43, 0.95, 0.95 }, { 0.48, 0.78, 1.00 }, { 0.60, 0.65, 1.00 },
  { 0.77, 0.61, 1.00 }, { 0.95, 0.61, 1.00 }, { 1.00, 0.56, 0.66 }, { 1.00, 0.70, 0.90 },
  { 0.70, 1.00, 0.94 }, { 1.00, 0.95, 0.66 }, { 0.82, 0.70, 1.00 }, { 0.66, 0.90, 1.00 },
}
local DEG, WID, GAIN, MPR = { -180, 180 }, { -360, 360 }, { -60, 10 }, { -100, 100 }

--------------------------------------------------------------------------
local floor, abs, min, max, sqrt = math.floor, math.abs, math.min, math.max, math.sqrt
local sin, cos, rad, deg = math.sin, math.cos, math.rad, math.deg
local atan2 = math.atan2 or math.atan
local slotK, kSlot = {}, {}   -- gefilterte Liste (siehe buildSlots)
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local MIDI_OUT = {}
for k = 1, CFG.nMidi do MIDI_OUT[k] = (k == CFG.midiConn) end
local N = CFG.N
local n32 = false                              -- v8.13: Taste „32“: Spuren 17–32 als Kacheln unten
local function win() return n32 and 32 or 16 end

local obj, me = {}, {}
for k = 1, N do
  obj[k] = { name = '', mpName = '', icon = '', col = nil, flags = 0, sel = false,
             az = 0, el = 0, wid = 0, yaw = 0, pitch = 0, roll = 0, x = 0, y = 0, z = 0,
             seenEnc = false, seenRot = false, seenMp = false, lvlIn = 0, lvl = 0, hold = {},
             rx = 0, ry = 0, rz = 0, room = nil, roomName = '', seenDv = false }
  me[k] = { az = 0, el = 0, gain = 0, hold = {} }
end
local meInfo = { count = 0, name = '' }
local msb = {}
local src = { name = nil, t = -1e9 }
local bank = 0
local mode = 'iem'
local cur = { iem = nil, me = nil, mp = nil, room = nil }   -- gewähltes Objekt je Modus
local logOpen, cfgOpen = false, false
local lvPos, lvHold, lvVal = {}, {}, {}
local dirty = true

local ctl = {}
local function C(name)
  local c = ctl[name]
  if c == nil then c = root:findByName(name, true); if c then ctl[name] = c end end
  return c
end
local function setText(name, s)
  local c = C(name)
  if c and c.values.text ~= s then c.values.text = s end
end
local function setVisible(name, v)
  local c = C(name)
  if c and c.visible ~= v then c.visible = v end
end
local function setColor(name, rgb, a)
  local c = C(name)
  if c then c.color = Color(rgb[1], rgb[2], rgb[3], a) end
end
local function ms() return getMillis() end
local function scale(n, r) return r[1] + n * (r[2] - r[1]) end
local RANGE = { az = DEG, el = DEG, wid = WID, yaw = DEG, pitch = DEG, roll = DEG, x = MPR, y = MPR, z = MPR, gain = GAIN }
local function unscale(v, r) return clamp((v - r[1]) / (r[2] - r[1]), 0, 1) end
local function fmtDeg(v) if abs(v) < 0.05 then v = 0 end return string.format('%+.1f°', v) end
local function fmtMp(v) return string.format('%+.0f', v) end
local function fmtDb(v) return string.format('%+.1f dB', v) end
local function hasBit(f, b) return floor(f / b) % 2 == 1 end

local function present(k)
  if k > win() then return false end
  local o = obj[k]
  if mode ~= 'me' and o.name ~= '' and not typeShown(o.flags) then return false end
  if mode == 'iem' then return hasBit(o.flags, 1) or o.seenEnc end
  if mode == 'mp' then return hasBit(o.flags, 2) or o.seenMp end
  if mode == 'room' then return o.seenDv end
  return k <= meInfo.count
end
local function hasRot(k) return hasBit(obj[k].flags, 8) or obj[k].seenRot end
local function isMulti(k) return hasBit(obj[k].flags, 4) end
local function colorOf(k)
  if mode ~= 'me' and LOOK.colors == 'daw' and obj[k].col then return obj[k].col end
  return PASTEL[(k - 1) % #PASTEL + 1]
end
local function trackNo(k)                       -- echte Spurnummer (Reaper schickt sie seit v8.4), sonst Bankplatz
  local o = obj[k]
  if o and o.num and o.num > 0 then return o.num end
  return bank * N + k
end
local function numOf(k) return (mode == 'iem' or mode == 'room') and trackNo(k) or k end
local function rangeText()
  local lo, hi
  for k = 1, N do if obj[k].name ~= '' and obj[k].num then local n = obj[k].num; lo = lo or n; hi = n end end
  if not lo then return string.format('%d–%d', bank * N + 1, bank * N + N) end
  return lo == hi and tostring(lo) or (lo .. '–' .. hi)
end
local function nameOf(k)
  local o = obj[k]
  if mode == 'mp' then return o.mpName ~= '' and o.mpName or ('Objekt ' .. k) end
  if mode == 'me' then return 'Eingang ' .. k end
  local n = o.name ~= '' and o.name or ('Spur ' .. trackNo(k))
  if isMulti(k) then n = n .. ' ✧multi' end
  return n
end

--------------------------------------------------------------------------
-- Senden
--------------------------------------------------------------------------
local function send14(ch, k, p, n)
  local v = floor(clamp(n, 0, 1) * 16383 + 0.5)
  if k > 16 then                                 -- Objekte 17–32: SysEx 10 (wie der Monitor)
    local kind = ({ [12] = 0, [6] = 1, [10] = 2 })[ch - floor((k - 1) / 8)]
    if kind then sendMIDI({ 0xF0, 0x7D, 0x4F, 10, kind, k - 1, p, floor(v / 128), v % 128, 0xF7 }, MIDI_OUT) end
    return
  end
  local cc = 4 * ((k - 1) % 8) + p
  sendMIDI({ 0xB0 + ch, cc, floor(v / 128) }, MIDI_OUT)
  sendMIDI({ 0xB0 + ch, cc + 32, v % 128 }, MIDI_OUT)
end
local function chFor(base, k) return base + floor((k - 1) / 8) end
local function note(ch, n)
  sendMIDI({ 0x90 + ch, n, 127 }, MIDI_OUT)
  sendMIDI({ 0x90 + ch, n, 0 }, MIDI_OUT)
end
grSend = function(b) sendMIDI(b, MIDI_OUT) end
local viewLoaded, viewSent, viewAsked, viewT = false, nil, false, 0
local function viewExtra() return { mode = mode, n32 = n32 and 1 or 0 } end
local function viewTick()                          -- v8.15: einmal fragen, dann Änderungen nach Reaper (höchstens 1× pro s)
  if src.name ~= 'REAPER' then return end
  local t = getMillis()
  if not viewAsked then viewAsked = true; viewT = t; sendMIDI({ 0xF0, 0x7D, 0x4F, 0x0F, 0, 0xF7 }, MIDI_OUT); return end
  if not viewLoaded and t - viewT > 2000 then viewLoaded = true end   -- nichts gespeichert: so lassen
  if not viewLoaded or t - viewT < 1000 then return end
  viewT = t
  local st = cfgState(viewExtra())
  if st ~= viewSent then
    viewSent = st
    local b = { 0xF0, 0x7D, 0x4F, 0x0E, 0 }
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
  for i = from, #m - 1 do
    local c = m[i]
    if c >= 32 and c <= 126 then t[#t + 1] = string.char(c) end
  end
  return table.concat(t)
end

local function clearAll()
  for i = 1, N do
    local o = obj[i]
    o.name, o.mpName, o.col, o.flags, o.sel, o.lvlIn = '', '', nil, 0, false, 0
    o.seenEnc, o.seenRot, o.seenMp = false, false, false
    o.seenDv, o.room, o.roomName = false, nil, ''
    o.num = nil
  end
  meInfo.count, meInfo.name = 0, ''
  dirty = true
end

local function onSysex(m)
  if m[2] ~= 0x7D or m[3] ~= 0x4F or not m[4] then return end
  if monOnSysex(m) then return end
  if CPU.parse(m) then src.t = ms(); return end
  if grSysex(m) then cfgPaint(); dirty = true; return end
  if m[4] == 20 and m[5] == 0 then                -- v8.15: Voreinstellung aus Reaper, einmal nach dem Start
    if not viewLoaded then
      viewLoaded = true
      local t = {}
      for i = 6, #m - 1 do t[#t + 1] = string.char(m[i]) end
      local kv = cfgApplyState(table.concat(t))
      if kv.mode then mode = kv.mode end
      if kv.n32 then n32 = kv.n32 == '1' end
      if cfgChanged then cfgChanged() end
      viewSent = cfgState(viewExtra())
    end
    dirty = true; return
  end
  if vsSysex(m) then cfgPaint(); dirty = true; return end
  local cmd = m[4]
  src.t = ms()
  local k = m[5] and (m[5] + 1)
  if cmd == 1 and k and k <= N then obj[k].name = sysexText(m, 6)
  elseif cmd == 2 and k and k <= N and m[8] then obj[k].col = { m[6] / 127, m[7] / 127, m[8] / 127 }
  elseif cmd == 3 and k and k <= N and m[6] then obj[k].flags = m[6]
  elseif cmd == 4 then
    local s = sysexText(m, 5)
    -- another DAW took over (or the old one stopped): forget everything shown so far
    if (s == '' and src.name) or (s ~= '' and src.name and s ~= src.name) then
      clearAll()
      if s ~= '' and src.switchT and getMillis() - src.switchT < 15000 then
        monAdd('◆ Achtung: ' .. src.name .. ' und ' .. s .. ' senden gleichzeitig - nur ein DAW-Skript laufen lassen', 'twodaw')
      end
      src.switchT = getMillis()
    end
    src.name = (s ~= '') and s or nil
    if src.name then monAdd('◆ verbunden: ' .. src.name, 'src') end
  elseif cmd == 5 and m[5] then
    if m[5] ~= bank then
      bank = m[5]
      for i = 1, N do obj[i].seenEnc, obj[i].seenRot, obj[i].sel, obj[i].seenDv = false, false, false, false end
      cur.room = nil
      cur.iem = nil
    end
    BK.onBank()
  elseif cmd == 6 and k and k <= N then obj[k].mpName = sysexText(m, 6)
  elseif cmd == 7 then
    clearAll()
  elseif cmd == 11 and k and k <= N then obj[k].icon = sysexText(m, 6)
  elseif cmd == 16 and m[6] then                              -- Spurfilter der DAW (Reaper)
    if filterFromDaw(m[5], m[6]) then cfgPaint() end
    filtSent = table.concat({ filterBits() }, ',')
  elseif cmd == 17 and k and k <= N and m[7] then obj[k].num = m[6] * 128 + m[7]
  elseif cmd == 10 and m[9] and m[5] == 3 and m[6] < N then   -- dearVR position, metres -32..32
    local o, part = obj[m[6] + 1], ({ 'rx', 'ry', 'rz' })[m[7] + 1]
    if part then o[part] = (m[8] * 128 + m[9]) / 16383 * 64 - 32; o.seenDv = true end
  elseif cmd == 10 and m[9] and m[5] <= 2 and m[6] < N then   -- v8.13: Objekte 17+ (Encoder, Rotator, MultiPanner)
    local o = obj[m[6] + 1]
    local part = ({ [0] = { 'az', 'el', 'wid' }, [1] = { 'yaw', 'pitch', 'roll' }, [2] = { 'x', 'y', 'z' } })[m[5]][m[7] + 1]
    if part then
      if m[5] == 0 then o.seenEnc = true elseif m[5] == 1 then o.seenRot = true else o.seenMp = true end
      if ms() - (o.hold[part] or -1e9) >= CFG.holdMs then o[part] = scale((m[8] * 128 + m[9]) / 16383, RANGE[part]) end
      dirty = true
    end
  elseif cmd == 14 and k and k <= N then                      -- dearVR room: 6 walls (cm) + preset
    local o = obj[k]
    if m[17] and m[17] ~= 0xF7 then
      o.room = {}
      for i = 0, 5 do o.room[i + 1] = (m[6 + 2 * i] * 128 + m[7 + 2 * i]) / 100 end
      o.roomName = sysexText(m, 18)
    else o.room, o.roomName = nil, '' end
  elseif cmd == 9 and m[5] then
    meInfo.count, meInfo.name = m[5], sysexText(m, 6)
    if cur.me and cur.me > meInfo.count then cur.me = nil end
    monAdd('◆ MultiEncoder gewählt: ' .. (meInfo.count > 0 and (meInfo.name .. ', ' .. meInfo.count .. ' Eingänge') or 'keiner'), 'me')
  end
  dirty = true
end

local PART = {
  [12] = { 'az', 'el', 'wid' }, [13] = { 'az', 'el', 'wid' },
  [6] = { 'yaw', 'pitch', 'roll' }, [7] = { 'yaw', 'pitch', 'roll' },
  [10] = { 'x', 'y', 'z' }, [11] = { 'x', 'y', 'z' },
  [8] = { 'az', 'el', 'gain' }, [9] = { 'az', 'el', 'gain' },
}

local function onCC(ch, cc, val)
  if ch == 14 then                                     -- Pegel
    if cc < N then obj[cc + 1].lvlIn = val / 127 end
    return
  end
  local parts = PART[ch]
  if not parts then return end
  local c, isLsb = cc, false
  if cc >= 32 then c, isLsb = cc - 32, true end
  if c >= 32 then return end
  local k, p = (ch % 2) * 8 + floor(c / 4) + 1, c % 4
  local part = parts[p + 1]
  if k > N or not part then return end
  local v14
  if isLsb then v14 = (msb[ch * 128 + c] or 0) * 128 + val
  else msb[ch * 128 + c] = val; v14 = val * 128 end
  local t = (ch == 8 or ch == 9) and me[k] or obj[k]
  if ch == 12 or ch == 13 then t.seenEnc = true
  elseif ch == 6 or ch == 7 then t.seenRot = true
  elseif ch == 10 or ch == 11 then t.seenMp = true end
  if ms() - (t.hold[part] or -1e9) < CFG.holdMs then return end   -- gerade selbst gezogen
  t[part] = scale(v14 / 16383, RANGE[part])
  if isLsb then
    local who = (ch == 8 or ch == 9) and ('Eingang ' .. k) or ((ch == 10 or ch == 11) and ('Objekt ' .. k) or ('Spur ' .. trackNo(k)))
    local txt = (part == 'gain') and fmtDb(t[part]) or ((ch == 10 or ch == 11) and fmtMp(t[part]) or fmtDeg(t[part]))
    monAdd('← ' .. who .. ' ' .. part .. ' ' .. txt, 'in' .. ch .. ':' .. c)
  end
  dirty = true
end

function onReceiveMIDI(m, connections)
  local st = m[1]
  if not st then return false end
  if st == 0xF0 then onSysex(m); return false end
  local kind, ch = floor(st / 16), st % 16
  if kind == 0xB and m[2] and m[3] then
    onCC(ch, m[2], m[3])
  elseif (kind == 0x9 or kind == 0x8) and ch == 14 and m[2] and m[2] < N then
    local k = m[2] + 1
    local on = (kind == 0x9 and (m[3] or 0) > 0)
    obj[k].sel = on
    if on and CFG.followDaw then cur.iem = k; cur.room = k end
    dirty = true
  end
  return false
end

--------------------------------------------------------------------------
-- Geometrie
--------------------------------------------------------------------------
local function topR(f) return f.w / 2 - 16 end
local function toTop(f, az, el)             -- Mitte +90°, Rand 0°, darunter gespiegelt (lower)
  local cx, cy, R = f.x + f.w / 2, f.y + f.h / 2, topR(f)
  local e = clamp(el, -90, 90)
  local r = R * (90 - abs(e)) / 90
  local a = rad(az)
  return cx - r * sin(a), cy - r * cos(a), e < -0.5
end
local function fromTop(f, px, py)           -- nur die Richtung; die Höhe bleibt
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
local function fromSq(f, px, py)
  return clamp((px - f.x) / f.w * 200 - 100, -100, 100), clamp(100 - (py - f.y) / f.h * 200, -100, 100)
end
local function xyPoint(xy)
  local f = xy.frame
  local y = CFG.xyYUp and (1 - xy.values.y) or xy.values.y
  return f.x + xy.values.x * f.w, f.y + y * f.h
end

--------------------------------------------------------------------------
-- Zeichnen
--------------------------------------------------------------------------
local function placeDot(pre, k, px, py, lvl, isCur, col, lower)
  local g = C(pre .. k)
  if not g then return end
  local s = g.frame.w
  g.frame = Rectangle(px - s / 2, py - s / 2, s, s)
  local dot, glow = C(pre .. k .. '_dot'), C(pre .. k .. '_glow')
  local soft = (cur[mode] and not isCur) and 0.42 or 1
  if dot then dot.color = Color(col[1], col[2], col[3], lower and soft * 0.18 or soft * (0.75 + 0.25 * lvl)) end
  setVisible(pre .. k .. '_lo', lower == true)
  if lower then local lo = C(pre .. k .. '_lo'); if lo then lo.color = Color(col[1], col[2], col[3], soft) end end
  if glow and dot then
    local d = dot.frame.w
    local gs = d + (s - d) * clamp(lvl, 0, 1)
    glow.frame = Rectangle((s - gs) / 2, (s - gs) / 2, gs, gs)
    glow.color = Color(col[1], col[2], col[3], soft * (0.10 + 0.45 * lvl))
  end
  setVisible(pre .. k .. '_ring', isCur)
  if pre == 'd' then
    local ic = ((LOOK.icons == 'dot' or LOOK.icons == 'both') and mode ~= 'me') and iconFor(obj[k].icon, obj[k].name) or ''
    local c = C(pre .. k .. '_icon')
    if c then
      if c.values.text ~= ic then c.values.text = ic end
      if ic ~= '' then
        local is = 30 * LOOK.iconSize
        c.frame = Rectangle(42 + 15 - is * 0.35, 42 + 15 - is * 0.45, is, is)
        c.textSize = math.floor(is * 0.8)
        c.textColor = Color(1, 1, 1, LOOK.iconAlpha)
      end
    end
  end
end

local function levelOf(k)
  if mode == 'me' then return 0 end
  return obj[k].lvl
end

local ROOM_UI = {
  frame = function(n, x, y, w, h) local c = C(n); if c then c.frame = Rectangle(x, y, w, h) end end,
  vis = function(n, v) setVisible(n, v) end,
  col = function(n, rgb, a) setColor(n, rgb, a) end,
  text = function(n, s) setText(n, s) end,
}
local roomTM, roomSM, roomIn = nil, nil, {}
local function bigRoom() return mode == 'room' and RM.big end   -- v8.16: Room füllt den Bildschirm
local function renderRoom(tf, pf)
  local on = (mode == 'room')
  for _, n in ipairs(RM.names(true)) do setVisible(n, false) end
  if not on or not tf then
    for _, n in ipairs(RM.ZOOM_CTL) do setVisible(n, false) end
    for _, pre in ipairs({ 'rt', 'rs' }) do for _, n in ipairs(RM.gridNames(pre)) do setVisible(n, false) end end
    roomTM, roomSM = nil, nil
    return
  end
  for _, n in ipairs({ 'rt_floor', 'rt_lis', 'rt_nose', 'rt_title', 'rt_scale', 'rs_floor', 'rs_lis', 'rs_nose', 'rs_title', 'rs_scale' }) do setVisible(n, true) end
  for _, n in ipairs(RM.ZOOM_CTL) do setVisible(n, not cfgOpen and not logOpen) end
  local objs = {}
  for k = 1, N do
    if present(k) then local o = obj[k]; objs[#objs + 1] = { k = k, room = o.room, name = o.roomName, x = o.rx, y = o.ry, z = o.rz } end
  end
  local ref, name, shared, others = RM.pick(objs, cur.room)
  roomIn = {}
  for _, o in ipairs(objs) do roomIn[o.k] = o.inRoom end
  roomTM, roomSM = RM.draw(ROOM_UI, tf, pf, ref, name or '', shared, others, objs, theme())
  if #objs == 0 then setText('rt_title', 'kein dearVR PRO auf diesen Spuren') end
end

local function renderDots()
  local tf, pf = C('top_area'), C('pano_area')
  tf, pf = tf and tf.frame, pf and pf.frame
  if bigRoom() and tf and pf then tf, pf = Rectangle(16, 168, 1334, 600), Rectangle(16, 784, 1334, 224) end
  renderRoom(tf, pf)
  for k = 1, N do
    local on = present(k)
    setVisible('d' .. k, on)
    setVisible('e' .. k, on and not n32)
    if on and tf and pf then
      local col, isCur, lvl = colorOf(k), (k == cur[mode]), levelOf(k)
      local x, y
      if mode == 'mp' then
        local o = obj[k]
        x, y = toSq(tf, o.x, o.y); placeDot('d', k, x, y, lvl, isCur, col)
        x, y = toSq(pf, o.x, o.z); placeDot('e', k, x, y, lvl, isCur, col)
      elseif mode == 'room' and roomTM then
        local o = obj[k]
        x, y = roomTM.map(o.rx, o.ry); placeDot('d', k, x, y, lvl, isCur, col)
        x, y = roomSM.map(o.ry, o.rz); placeDot('e', k, x, y, lvl, isCur, col)
        if not roomIn[k] then
          for _, pre in ipairs({ 'd', 'e' }) do
            local dc = C(pre .. k .. '_dot'); if dc then dc.color = Color(col[1], col[2], col[3], 0.22) end
          end
        end
      else
        local t = (mode == 'me') and me[k] or obj[k]
        local lower
        x, y, lower = toTop(tf, t.az, t.el); placeDot('d', k, x, y, lvl, isCur, col, lower)
        x, y = toPano(pf, t.az, t.el); placeDot('e', k, x, y, lvl, isCur, col)
      end
    end
    -- Breite: linke/rechte Kante der Stereobasis (StereoEncoder), gleiche Höhe
    local o = obj[k]
    local wide = on and tf and mode == 'iem' and not isMulti(k) and abs(o.wid) >= 2
    setVisible('wl' .. k, wide and true or false); setVisible('wr' .. k, wide and true or false)
    if wide then
      local soft = (cur[mode] and k ~= cur[mode]) and 0.35 or 0.8
      for side, sgn in pairs({ wl = 1, wr = -1 }) do
        local c = C(side .. k)
        if c then
          local sx, sy = toTop(tf, o.az + sgn * o.wid / 2, o.el)
          c.frame = Rectangle(sx - 6.5, sy - 6.5, 13, 13)
          local col = colorOf(k); c.color = Color(col[1], col[2], col[3], soft)
        end
      end
    end
    local slot = kSlot[k]
    local bar, bg, hb
    if slot then bar, bg, hb = C('r' .. slot .. '_lvl'), C('r' .. slot .. '_lvlbg'), C('r' .. slot .. '_hold') end
    if bar and bg then
      local f = bg.frame
      local p = (mode == 'me') and 0 or (lvPos[k] or 0)
      bar.frame = Rectangle(f.x, f.y, max(0, f.w * clamp(p, 0, 1)), f.h)
      local mc = meterColor(p); bar.color = Color(mc[1], mc[2], mc[3], 0.95)   -- Pegel in eigener Palettenfarbe
      if hb then
        hb.frame = Rectangle(f.x + f.w * clamp((mode == 'me') and 0 or (lvHold[k] or 0), 0, 1) - 1, f.y, 2, f.h)
        local hc = theme().meterHold; hb.color = Color(hc[1], hc[2], hc[3], 0.9)
      end
    end
  end
  local m, mb = C('det_lvl'), C('det_lvlbg')
  if m and mb then
    local f = mb.frame
    local l = (cur[mode] and mode ~= 'me') and (lvPos[cur[mode]] or 0) or 0
    m.frame = Rectangle(f.x, f.y, max(0, f.w * l), f.h)
  end
end

local function setFader(name, v, r)
  local c = C(name)
  if c and not c.values.touch then c.values.x = unscale(v, r) end
end

-- Liste und Pillen: nur Spuren, auf denen im aktuellen Modus ein passendes Plugin liegt
-- (Einstellung LOOK.onlyPlug, Config). slotK[i] = Objekt in Zeile i, kSlot[k] = Zeile von Objekt k.
local SLOT_PARTS = {
  { 'sel', '' }, { 'sel', '_bg' }, { 'sel', '_ring' }, { 'sel', '_num' }, { 'sel', '_name' },
  { 'r', '_bg' }, { 'r', '_chip' }, { 'r', '_num' }, { 'r', '_name' }, { 'r', '_val' }, { 'r', '_lvlbg' },
  { 'r', '_lvl' }, { 'r', '_hold' }, { 'r', '_glyph' }, { 'r', '_tap' }, { 'r', '_fx' }, { 'r', '_grp' },
}
local function buildSlots()
  slotK, kSlot = {}, {}
  for k = 1, N do
    local keep = present(k) or (not LOOK.onlyPlug and (mode ~= 'me'))
    if keep then slotK[#slotK + 1] = k; kSlot[k] = #slotK end
  end
end

local function render()
  dirty = false
  local srcOn = src.name and (ms() - src.t < 15000)
  setText('src', srcOn and (src.name .. ' ♡') or 'keine DAW')
  if GR.assign then setText('bank', grText())
  elseif mode == 'iem' then setText('bank', 'Spuren ' .. rangeText())
  elseif mode == 'mp' then setText('bank', 'MultiPanner 1–16')
  elseif mode == 'room' then setText('bank', 'dearVR · Spuren ' .. rangeText())
  else setText('bank', meInfo.count > 0 and ('✧ ' .. meInfo.name) or 'kein MultiEncoder') end
  local c0 = cur[mode]
  if c0 and not present(c0) then cur[mode] = nil end
  if not cur[mode] then
    for k = 1, N do if present(k) then cur[mode] = k; break end end
  end
  local cu = cur[mode]
  buildSlots()
  for i = 1, N do
    local k = slotK[i]
    for _, sfx in ipairs(SLOT_PARTS) do setVisible(sfx[1] .. i .. sfx[2], k ~= nil and not (sfx[1] == 'r' and bigRoom())) end
    if k then
      local o = obj[k]
      local on = present(k)
      local col = colorOf(k)
      local isCur = (k == cu)
      setColor('sel' .. i .. '_bg', col, isCur and 1 or (on and 0.35 or 0.08))
      setVisible('sel' .. i .. '_ring', isCur)
      setText('sel' .. i .. '_name', on and nameOf(k):sub(1, 9) or '')
      setText('sel' .. i .. '_num', tostring(numOf(k)))
      for _, part in ipairs({ '_num', '_name' }) do
        local c = C('sel' .. i .. part)
        if c then
          if isCur then c.textColor = Color(0.14, 0.06, 0.25, 1)
          else c.textColor = Color(1, 0.94, 0.98, on and 0.9 or 0.3) end
        end
      end
      setColor('r' .. i .. '_chip', col, on and 1 or 0.25)
      local row = C('r' .. i .. '_bg')
      if row then
        if isCur then row.color = Color(0.36, 0.16, 0.52, 1)
        else row.color = Color(0.17, 0.08, 0.31, on and 1 or 0.55) end
      end
      setText('r' .. i .. '_num', tostring(numOf(k)))
      local name = ''
      if on then name = nameOf(k)
      elseif mode == 'iem' and o.name ~= '' then name = o.name .. ' · kein Encoder' end
      setText('r' .. i .. '_name', name)
      local vals = ''
      if on then
        if mode == 'mp' then vals = 'X ' .. fmtMp(o.x) .. ' Y ' .. fmtMp(o.y) .. ' Z ' .. fmtMp(o.z)
        elseif mode == 'room' then vals = RM.fmtPos(o)
        elseif mode == 'me' then vals = 'Az ' .. fmtDeg(me[k].az) .. '  El ' .. fmtDeg(me[k].el)
        else vals = 'Az ' .. fmtDeg(o.az) .. '  El ' .. fmtDeg(o.el) end
      end
      if on and mode ~= 'me' and lvVal[k] then vals = vals .. '  ' .. lvFormat(lvVal[k]) end
      if i > 16 then vals = vals:gsub('%s+El', '\nEl'):gsub('%s+–$', ''):gsub('%s+(%-?[%d%.]+ dBFS)', '\n%1') end   -- Kacheln: untereinander
      setText('r' .. i .. '_val', vals)
      local typ = typeOf(o.flags)
      setVisible('r' .. i .. '_fx', LOOK.marks and mode ~= 'me' and o.name ~= '' and typ == 'fx')
      setVisible('r' .. i .. '_grp', LOOK.marks and mode ~= 'me' and o.name ~= '' and typ == 'group')
      local g = (LOOK.marks and mode ~= 'me' and typ == 'instr') and '♪' or ''
      if (LOOK.icons == 'list' or LOOK.icons == 'both') and mode ~= 'me' then
        local ic = iconFor(o.icon, o.name); if ic ~= '' then g = (g ~= '' and (g .. ' ') or '') .. ic end
      end
      setText('r' .. i .. '_glyph', g)
      local gc = C('r' .. i .. '_glyph'); if gc then gc.textColor = Color(1, 0.94, 0.98, LOOK.iconAlpha) end
    end
  end
  -- Detail
  local showA, showRot = false, false
  if cu then
    setText('det_num', tostring(numOf(cu)))
    setColor('det_chip', colorOf(cu), 1)
    setText('det_name', nameOf(cu))
    if mode == 'room' then
      local o = obj[cu]
      local f1 = function(v) return (string.format('%+.1f m', v):gsub('%.', ',')) end
      setText('det_l1', 'X  rechts +'); setText('det_v1', f1(o.rx))
      setText('det_l2', 'Y  vorn +'); setText('det_v2', f1(o.ry))
      setText('det_l3', 'Z  oben +  · ' .. (o.roomName ~= '' and o.roomName or 'Raum ?')); setText('det_v3', f1(o.rz))
    elseif mode == 'mp' then
      local o = obj[cu]
      setText('det_l1', 'X'); setText('det_v1', fmtMp(o.x))
      setText('det_l2', 'Y'); setText('det_v2', fmtMp(o.y))
      setText('det_l3', 'Z (Höhe)'); setText('det_v3', fmtMp(o.z))
    elseif mode == 'me' then
      local t = me[cu]
      setText('det_l1', 'azimuth'); setText('det_v1', fmtDeg(t.az))
      setText('det_l2', 'elevation'); setText('det_v2', fmtDeg(t.el))
      setText('det_l3', 'gain'); setText('det_v3', fmtDb(t.gain))
      showA = true; setText('fa_lbl', 'gain'); setFader('fa', t.gain, GAIN)
    else
      local o = obj[cu]
      setText('det_l1', isMulti(cu) and 'master azimuth' or 'azimuth'); setText('det_v1', fmtDeg(o.az))
      setText('det_l2', isMulti(cu) and 'master elevation' or 'elevation'); setText('det_v2', fmtDeg(o.el))
      if isMulti(cu) then
        setText('det_l3', 'multi'); setText('det_v3', 'Eingänge: Modus multi')
      else
        setText('det_l3', 'width'); setText('det_v3', fmtDeg(o.wid))
        showA = true; setText('fa_lbl', 'width'); setFader('fa', o.wid, { -180, 180 })
      end
      if hasRot(cu) then
        showRot = true
        setText('yaw_lbl', 'rotator yaw ' .. fmtDeg(o.yaw)); setFader('yaw_fader', o.yaw, DEG)
        setText('pitch_lbl', 'rotator pitch ' .. fmtDeg(o.pitch)); setFader('pitch_fader', o.pitch, DEG)
      end
    end
  else
    setText('det_num', ''); setText('det_name', 'nichts gewählt')
    for i = 1, 3 do setText('det_l' .. i, ''); setText('det_v' .. i, '') end
  end
  for _, n in ipairs({ 'fa', 'fa_lbl' }) do setVisible(n, showA) end
  for _, n in ipairs({ 'yaw_fader', 'yaw_lbl', 'pitch_fader', 'pitch_lbl' }) do setVisible(n, showRot) end
  -- Modus, Hintergründe, LOG
  for _, m in ipairs({ 'iem', 'me', 'mp', 'room' }) do
    setColor('mode_' .. m .. '_bg', m == mode and { 1, 0.43, 0.78 } or { 0.18, 0.08, 0.35 }, 1)
  end
  setColor('log_btn_bg', logOpen and { 0.37, 0.95, 1 } or { 0.18, 0.08, 0.35 }, 1)
  setColor('cfg_btn_bg', cfgOpen and { 0.37, 0.95, 1 } or { 0.18, 0.08, 0.35 }, 1)
  setColor('col_btn_bg', LOOK.colors == 'daw' and { 0.37, 0.95, 1 } or { 0.18, 0.08, 0.35 }, 1)
  setText('col_btn_lbl', LOOK.colors == 'daw' and 'spurfarben' or 'tosc farben')
  setVisible('cfg_overlay', cfgOpen)
  setVisible('bg_top', mode ~= 'mp' and mode ~= 'room'); setVisible('bg_pano', mode ~= 'mp' and mode ~= 'room' and not n32)
  setVisible('tiles32', n32 and not bigRoom()); setVisible('pano_xy', not n32)
  setVisible('det_g', not bigRoom())
  setColor('n32_btn_bg', n32 and { 0.37, 0.95, 1 } or { 0.18, 0.08, 0.35 }, 1)
  setVisible('bg_top_mp', mode == 'mp'); setVisible('bg_pano_mp', mode == 'mp')
  setVisible('mon_overlay', logOpen)
end

--------------------------------------------------------------------------
-- Bedienung
--------------------------------------------------------------------------
local function moveTo(a, b, rear)
  local k = cur[mode]
  if not k then return end
  local now = ms()
  if mode == 'mp' then
    local o = obj[k]
    local ch = chFor(10, k)
    if a and abs(a - o.x) >= 0.05 then o.x = a; o.hold.x = now; send14(ch, k, 0, unscale(a, MPR)) end
    local part = rear and 'z' or 'y'
    if b and abs(b - o[part]) >= 0.05 then o[part] = b; o.hold[part] = now; send14(ch, k, rear and 2 or 1, unscale(b, MPR)) end
    monAdd('→ Objekt ' .. k .. ' X ' .. fmtMp(o.x) .. ' ' .. (rear and 'Z ' or 'Y ') .. fmtMp(o[part]), 'out:mp' .. k)
  else
    local t = (mode == 'me') and me[k] or obj[k]
    local ch = (mode == 'me') and chFor(8, k) or chFor(12, k)
    if a and abs(a - t.az) >= 0.05 then t.az = a; t.hold.az = now; send14(ch, k, 0, unscale(a, DEG)) end
    if b and abs(b - t.el) >= 0.05 then t.el = b; t.hold.el = now; send14(ch, k, 1, unscale(b, DEG)) end
    monAdd('→ ' .. nameOf(k) .. ' Az ' .. fmtDeg(t.az) .. ' El ' .. fmtDeg(t.el), 'out:' .. mode .. k)
  end
  dirty = true
end

local function onDrag(name)
  local c = C(name)
  local k = cur[mode]
  if not c or not k or logOpen or cfgOpen then return end
  if (name == 'top_xy' or name == 'pano_xy') and mode == 'room' then return end   -- room: nur Anzeige
  if name == 'top_xy' or name == 'pano_xy' then
    local area = C(name == 'top_xy' and 'top_area' or 'pano_area')
    if not area then return end
    local px, py = xyPoint(c)
    if mode == 'mp' then
      local a, b = fromSq(area.frame, px, py)
      moveTo(a, b, name == 'pano_xy')                  -- Rückansicht: senkrecht = Z
    elseif name == 'top_xy' then moveTo(fromTop(area.frame, px, py))
    else moveTo(fromPano(area.frame, px, py)) end
  elseif name == 'fa' then
    local now = ms()
    if mode == 'me' then
      local t = me[k]; t.gain = scale(c.values.x, GAIN); t.hold.gain = now
      send14(chFor(8, k), k, 2, unscale(t.gain, GAIN))
      monAdd('→ Eingang ' .. k .. ' gain ' .. fmtDb(t.gain), 'out:g' .. k)
    else
      local o = obj[k]; o.wid = scale(c.values.x, { -180, 180 }); o.hold.wid = now
      send14(chFor(12, k), k, 2, unscale(o.wid, WID))
      monAdd('→ ' .. nameOf(k) .. ' width ' .. fmtDeg(o.wid), 'out:w' .. k)
    end
    dirty = true
  elseif name == 'yaw_fader' or name == 'pitch_fader' then
    local o, part = obj[k], (name == 'yaw_fader') and 'yaw' or 'pitch'
    o[part] = scale(c.values.x, DEG); o.hold[part] = ms()
    send14(chFor(6, k), k, part == 'yaw' and 0 or 1, c.values.x)
    monAdd('→ ' .. nameOf(k) .. ' ' .. part .. ' ' .. fmtDeg(o[part]), 'out:' .. part .. k)
    dirty = true
  end
end

local function onButton(name)
  if cfgOpen and name ~= 'cfg_btn' then
    if name == 'cfg_close' then cfgOpen = false; dirty = true; return end
    if cfgButton(name) then if GR.assign then cfgOpen = false end; dirty = true; return end
  end
  if RM.button(name) then dirty = true; return end
  if name == 'col_btn' then LOOK.colors = (LOOK.colors == 'daw') and 'tosc' or 'daw'; cfgPaint(); dirty = true; return end
  if name == 'cfg_btn' then cfgOpen = not cfgOpen; logOpen = false; cfgPaint(); dirty = true; return end
  if name == 'n32_btn' then n32 = not n32; dirty = true; return end
  if name == 'bank_prev' then BK.press(-1); note(15, 2); if n32 then note(15, 2) end; return end   -- 32: zwei DAW-Bänke
  if name == 'bank_next' then BK.press(1); note(15, 3); if n32 then note(15, 3) end; return end
  if name == 'mode_iem' or name == 'mode_me' or name == 'mode_mp' or name == 'mode_room' then
    mode = name:sub(6); dirty = true; return
  end
  if name == 'log_btn' then logOpen = not logOpen; cfgOpen = false; monDraw(true); dirty = true; return end
  local slot = tonumber(name:match('^sel(%d+)$') or name:match('^r(%d+)_tap$') or '')
  local k = slot and slotK[slot]
  if k and GR.assign then                          -- v8.14: Spur in/aus Gruppe A–D
    sendMIDI({ 0xF0, 0x7D, 0x4F, 0x0D, GR.assign - 1, k - 1, 0xF7 }, MIDI_OUT)
    monAdd('→ ' .. nameOf(k) .. ' in/aus Gruppe ' .. ({ 'A', 'B', 'C', 'D' })[GR.assign])
    return
  end
  if k and present(k) then
    cur[mode] = k
    if mode == 'iem' and CFG.selectInDaw and not obj[k].sel then note(14, k - 1) end
    dirty = true
  end
end

function onReceiveNotify(key, value)
  if key == 'btn' then onButton(value)
  elseif key == 'drag' then onDrag(value)
  elseif key == 'cfgf' then cfgFader(value) end
end

local themeApplied = nil
local function applyTheme()
  local th = theme()
  themeApplied = LOOK.theme
  root.color = Color(th.bg[1], th.bg[2], th.bg[3], 1)
  for _, c in ipairs(root:findAllByName('th_panel', true) or {}) do
    c.color = Color(th.panel[1], th.panel[2], th.panel[3], (c.color and c.color.a) or 1)
  end
  dirty = true
end
cfgChanged = function() if themeApplied ~= LOOK.theme then applyTheme() end; sendFilter(); dirty = true end

local lastT, lastRender = 0, 0
VS.id = 1                                        -- v8.15: Ansicht in Reaper merken
VS.extra = function() return { m = mode, n32 = n32 and 1 or 0 } end
VS.applyExtra = function(key, v)
  if key == 'm' and (v == 'iem' or v == 'me' or v == 'mp' or v == 'room') then mode = v end
  if key == 'n32' then n32 = (v == '1') end
end
function update()
  viewTick()
  local t = ms()
  vsTick(t, function(b) sendMIDI(b, MIDI_OUT) end)
  local dt = (lastT > 0) and (t - lastT) / 1000 or 0.016
  lastT = t
  if themeApplied ~= LOOK.theme then applyTheme() end
  for k = 1, N do
    local o = obj[k]
    local v, pos, glow, hp = lvStep(k, o.lvlIn, dt, t)
    o.lvl, lvPos[k], lvHold[k], lvVal[k] = glow, pos, hp, v
  end
  if dirty or t - lastRender > 1000 then lastRender = t; render(); CPU.render(src.name, theme().text, theme().meterHot) end
  renderDots()
  if logOpen then monDraw() end
  if mode == 'iem' or mode == 'room' then
    local n = 0
    for k = 1, N do if present(k) then n = n + 1 end end
    BK.step(n, function(d) note(15, d > 0 and 3 or 2) end)
  else BK.cancel() end
end

function init()
  ctl = {}
  dirty = true
  themeApplied = nil
  cfgPaint()
end
