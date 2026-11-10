--[[ =========================================================================
  seren.a · Objekt-Übersicht v3 (v8.4: Spurnummern, leere Bänke überspringen) · Root-Skript (TouchOSC 2, Handy quer)
  -------------------------------------------------------------------------
  Alle Spuren auf einmal: Draufsicht, zweite Ansicht, Liste. Drei Modi:
    IEM        StereoEncoder/MultiEncoder (Master) jeder Spur, SceneRotator in der Detailbox
    MULTIPAN.  Nuendo MultiPanner (Mapping Assistant)
    MULTI-ENC  die Eingänge des MultiEncoders der gewählten Spur (bis 16)
  LOG: was das DAW-Skript erkannt hat, was ankommt.
  Verbindung: MIDI 1 = TouchOSC Bridge. Gegenstelle: serena_TouchOSC3D.js (Nuendo)
  oder reaper_seren3D.lua (Reaper). Protokoll: PROTOKOLL.md.
========================================================================= ]]

local CFG = {
  midiConn = 1,
  nMidi = 10,
  N = 16,
  srcTimeout = 15000,
}

local PALETTE = {
  { 0.96, 0.36, 0.36 }, { 0.98, 0.60, 0.25 }, { 0.98, 0.83, 0.25 }, { 0.70, 0.90, 0.30 },
  { 0.35, 0.85, 0.45 }, { 0.25, 0.85, 0.75 }, { 0.25, 0.75, 0.98 }, { 0.40, 0.55, 0.98 },
  { 0.60, 0.45, 0.98 }, { 0.80, 0.40, 0.95 }, { 0.98, 0.40, 0.80 }, { 0.95, 0.55, 0.60 },
  { 0.75, 0.75, 0.55 }, { 0.55, 0.80, 0.80 }, { 0.70, 0.70, 0.95 }, { 0.85, 0.85, 0.85 },
}
local DEG, MPR, GAIN = { -180, 180 }, { -100, 100 }, { -60, 10 }

--------------------------------------------------------------------------
local floor, abs, min, max = math.floor, math.abs, math.min, math.max
local sin, cos, rad = math.sin, math.cos, math.rad
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local MIDI_OUT = {}
for k = 1, CFG.nMidi do MIDI_OUT[k] = (k == CFG.midiConn) end

local N = CFG.N
local obj, me = {}, {}
for k = 1, N do
  obj[k] = { name = '', mpName = '', col = nil, flags = 0, sel = false,
             az = 0, el = 0, wid = 0, yaw = 0, pitch = 0, roll = 0, x = 0, y = 0, z = 0,
             seenEnc = false, seenMp = false, seenRot = false }
  me[k] = { az = 0, el = 0, gain = 0 }
end
local meInfo = { count = 0, name = '' }
local msb = {}
local src = { name = nil, t = -1e9 }
local bank = 0
local mode = 'iem'
local logOpen = false
local dirty = true
local slotK = {}   -- Liste zeigt nur Spuren mit passendem Plugin: slotK[i] = Spur in Zeile i

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
local function ms() return getMillis() end
local function scale(n, r) return r[1] + n * (r[2] - r[1]) end
local function fmtDeg(v) if abs(v) < 0.05 then v = 0 end return string.format('%+.1f°', v) end
local function fmtMp(v) return string.format('%+.0f', v) end
local function fmtDb(v) return string.format('%+.1f dB', v) end
local function hasBit(f, b) return floor(f / b) % 2 == 1 end

local function present(k)
  local o = obj[k]
  if mode == 'iem' then return hasBit(o.flags, 1) or o.seenEnc end
  if mode == 'mp' then return hasBit(o.flags, 2) or o.seenMp end
  return k <= meInfo.count
end
local function trackNo(k)                       -- echte Spurnummer (Reaper schickt sie seit v8.4), sonst Bankplatz
  local o = obj[k]
  if o.num and o.num > 0 then return o.num end
  return bank * N + k
end
local function colorOf(k)
  if mode == 'iem' and obj[k].col then return obj[k].col end
  return PALETTE[k]
end
local function nameOf(k)
  local o = obj[k]
  if mode == 'mp' then return o.mpName ~= '' and o.mpName or ('Objekt ' .. k) end
  if mode == 'me' then return 'Eingang ' .. k end
  local n = o.name ~= '' and o.name or ('Spur ' .. (trackNo(k)))
  if hasBit(o.flags, 4) then n = n .. ' (Multi)' end
  return n
end
local function posOf(k)          -- az, el for iem/me; x, y, z for mp
  if mode == 'me' then return me[k].az, me[k].el end
  local o = obj[k]
  if mode == 'mp' then return o.x, o.y, o.z end
  return o.az, o.el
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
    o.name, o.mpName, o.col, o.flags, o.sel = '', '', nil, 0, false
    o.seenEnc, o.seenMp, o.seenRot = false, false, false
    o.num = nil
  end
  meInfo.count, meInfo.name = 0, ''
  dirty = true
end

local function onSysex(m)
  if m[2] ~= 0x7D or m[3] ~= 0x4F or not m[4] then return end
  if monOnSysex(m) then return end
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
      for i = 1, N do obj[i].seenEnc, obj[i].seenRot, obj[i].sel = false, false, false end
    end
    BK.onBank()
  elseif cmd == 6 and k and k <= N then obj[k].mpName = sysexText(m, 6)
  elseif cmd == 17 and k and k <= N and m[7] then obj[k].num = m[6] * 128 + m[7]
  elseif cmd == 7 then
    clearAll()
  elseif cmd == 9 and m[5] then
    meInfo.count, meInfo.name = m[5], sysexText(m, 6)
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
  local n = v14 / 16383
  if ch == 8 or ch == 9 then
    me[k][part] = scale(n, part == 'gain' and GAIN or DEG)
  elseif ch == 10 or ch == 11 then
    obj[k][part] = scale(n, MPR); obj[k].seenMp = true
  elseif ch == 6 or ch == 7 then
    obj[k][part] = scale(n, DEG); obj[k].seenRot = true
  else
    obj[k][part] = scale(n, part == 'wid' and { -360, 360 } or DEG); obj[k].seenEnc = true
  end
  if isLsb then
    local label = (ch == 8 or ch == 9) and ('Eingang ' .. k) or ('Spur ' .. (trackNo(k)))
    local txt = (part == 'gain') and fmtDb(me[k].gain) or
                ((ch == 10 or ch == 11) and fmtMp(obj[k][part])) or
                fmtDeg((ch == 8 or ch == 9) and me[k][part] or obj[k][part])
    monAdd('← ' .. label .. ' ' .. part .. ' ' .. txt, 'in' .. ch .. ':' .. c)
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
    obj[m[2] + 1].sel = (kind == 0x9 and (m[3] or 0) > 0)
    dirty = true
  end
  return false
end

--------------------------------------------------------------------------
-- Zeichnen
--------------------------------------------------------------------------
local function iemTop(f, az, el)
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  local R = f.w / 2 - 14
  local r = R * (90 - clamp(el, -90, 90)) / 180
  local a = rad(az)
  return cx - r * sin(a), cy - r * cos(a)
end
local function iemPano(f, az, el)
  local a = ((az + 180) % 360) - 180
  return f.x + f.w * (0.5 - a / 360), f.y + f.h * (0.5 - clamp(el, -90, 90) / 180)
end
local function mpTop(f, x, y) return f.x + f.w * (x + 100) / 200, f.y + f.h * (1 - (y + 100) / 200) end
local function mpRear(f, x, z) return f.x + f.w * (x + 100) / 200, f.y + f.h * (1 - (z + 100) / 200) end

local function place(dotName, px, py)
  local d = C(dotName)
  if not d then return end
  local s = d.frame.w
  d.frame = Rectangle(px - s / 2, py - s / 2, s, s)
end

local TITLES = {
  iem = 'Panorama · Azimut × Elevation', mp = 'Rückansicht · X × Z', me = 'Panorama · Eingänge',
}

local function render()
  dirty = false
  local srcOn = src.name and (ms() - src.t < CFG.srcTimeout)
  setText('src', srcOn and src.name or 'keine DAW')
  if mode == 'iem' then setText('bank', (function()
    local lo, hi
    for k = 1, N do if obj[k].name ~= '' and obj[k].num then local x = obj[k].num; lo = lo or x; hi = x end end
    if not lo then return string.format('Spuren %d–%d', bank * N + 1, bank * N + N) end
    return 'Spuren ' .. (lo == hi and tostring(lo) or (lo .. '–' .. hi))
  end)())
  elseif mode == 'mp' then setText('bank', 'Objekte 1–16')
  else setText('bank', meInfo.count > 0 and (meInfo.name ~= '' and meInfo.name or 'MultiEncoder') or 'kein MultiEncoder') end
  local tf, sf = C('top_area'), C('sec_area')
  tf, sf = tf and tf.frame, sf and sf.frame
  local firstSel, count = nil, 0
  for k = 1, N do
    local o = obj[k]
    local on = present(k)
    local col = colorOf(k)
    setVisible('d' .. k, on); setVisible('e' .. k, on)
    if on then
      count = count + 1
      if tf and sf then
        local a, b, c = posOf(k)
        if mode == 'mp' then place('d' .. k, mpTop(tf, a, b)); place('e' .. k, mpRear(sf, a, c))
        else place('d' .. k, iemTop(tf, a, b)); place('e' .. k, iemPano(sf, a, b)) end
      end
      local isSel = (mode == 'iem') and o.sel
      for _, pre in ipairs({ 'd', 'e' }) do
        local dot = C(pre .. k .. '_dot')
        if dot then dot.color = Color(col[1], col[2], col[3], 1) end
        setVisible(pre .. k .. '_ring', isSel)
      end
    end
    if mode == 'iem' and on and o.sel and not firstSel then firstSel = k end
  end
  -- Liste: nur Spuren, auf denen das Plugin des Modus liegt (rückt auf)
  slotK = {}
  for k = 1, N do if present(k) then slotK[#slotK + 1] = k end end
  for i = 1, N do
    local k = slotK[i]
    local r = 'r' .. i
    for _, part in ipairs({ '_bg', '_chip', '_num', '_name', '_val', '_tap' }) do setVisible(r .. part, k ~= nil) end
    if k then
      local o, col = obj[k], colorOf(k)
      local chip = C(r .. '_chip')
      if chip then chip.color = Color(col[1], col[2], col[3], 1) end
      local row = C(r .. '_bg')
      if row then
        if mode == 'iem' and o.sel then row.color = Color(0.20, 0.23, 0.29, 1)
        else row.color = Color(0.11, 0.12, 0.14, 1) end
      end
      setText(r .. '_num', tostring(mode == 'iem' and (trackNo(k)) or k))
      setText(r .. '_name', nameOf(k))
      local a, b, c = posOf(k)
      local vals
      if mode == 'mp' then vals = 'X ' .. fmtMp(a) .. '  Y ' .. fmtMp(b) .. '  Z ' .. fmtMp(c)
      elseif mode == 'me' then vals = 'Az ' .. fmtDeg(a) .. '  El ' .. fmtDeg(b) .. '  ' .. fmtDb(me[k].gain)
      else vals = 'Az ' .. fmtDeg(a) .. '   El ' .. fmtDeg(b) end
      setText(r .. '_val', vals)
    end
  end
  if #slotK == 0 then   -- Hinweis in der ersten Zeile
    setVisible('r1_bg', true); setVisible('r1_name', true)
    setText('r1_name', mode == 'iem' and 'keine Spur mit Encoder in dieser Bank'
      or mode == 'mp' and 'keine MultiPanner-Objekte' or 'kein MultiEncoder auf der gewählten Spur')
    local row = C('r1_bg'); if row then row.color = Color(0.11, 0.12, 0.14, 0.5) end
  end
  -- Detail
  if mode == 'iem' and firstSel then
    local o = obj[firstSel]
    setText('det_name', trackNo(firstSel) .. '  ' .. nameOf(firstSel))
    local t = 'Azimuth ' .. fmtDeg(o.az) .. '\nElevation ' .. fmtDeg(o.el)
    if not hasBit(o.flags, 4) then t = t .. '\nWidth ' .. fmtDeg(o.wid) end
    if hasBit(o.flags, 8) or o.seenRot then
      t = t .. '\nRotator: Yaw ' .. fmtDeg(o.yaw) .. '  Pitch ' .. fmtDeg(o.pitch)
    end
    setText('det_vals', t)
  elseif mode == 'me' then
    setText('det_name', meInfo.count > 0 and (meInfo.name .. ' · ' .. meInfo.count .. ' Eingänge') or 'kein MultiEncoder')
    setText('det_vals', meInfo.count > 0 and 'Eingänge der gewählten Spur\nNuendo: Insert 4 · Reaper: beliebig'
                                         or 'Spur mit MultiEncoder in der DAW wählen')
  else
    setText('det_name', mode == 'iem' and 'keine Spur gewählt' or '')
    setText('det_vals', mode == 'iem' and 'Spur in der Liste antippen' or '')
  end
  setText('sec_title', TITLES[mode])
  setText('status', count .. (mode == 'me' and ' Eingänge' or ' Objekte') .. ' · ' ..
    (mode == 'iem' and 'Encoder: Insert 4 (Nuendo) / beliebig (Reaper)' or
     mode == 'mp' and 'MultiPanner (Mapping Assistant)' or 'MultiEncoder der gewählten Spur'))
  for _, m in ipairs({ 'iem', 'mp', 'me' }) do
    local b = C('mode_' .. m)
    if b then b.color = (m == mode) and Color(0.21, 0.82, 0.77, 1) or Color(0.22, 0.24, 0.27, 1) end
  end
  setVisible('bg_top_iem', mode ~= 'mp'); setVisible('bg_sec_iem', mode ~= 'mp')
  setVisible('bg_top_mp', mode == 'mp'); setVisible('bg_sec_mp', mode == 'mp')
  setVisible('mon_overlay', logOpen)
  local lb = C('log_btn')
  if lb then lb.color = logOpen and Color(0.21, 0.82, 0.77, 1) or Color(0.22, 0.24, 0.27, 1) end
end

--------------------------------------------------------------------------
-- Bedienung
--------------------------------------------------------------------------
local function note(ch, n)
  sendMIDI({ 0x90 + ch, n, 127 }, MIDI_OUT)
  sendMIDI({ 0x90 + ch, n, 0 }, MIDI_OUT)
end

local function onButton(name)
  if name == 'mode_iem' then mode = 'iem'
  elseif name == 'mode_mp' then mode = 'mp'
  elseif name == 'mode_me' then mode = 'me'
  elseif name == 'log_btn' then logOpen = not logOpen; monDraw(true)
  elseif name == 'bank_prev' then BK.press(-1); note(15, 2); monAdd('→ Bank zurück', 'bank')
  elseif name == 'bank_next' then BK.press(1); note(15, 3); monAdd('→ Bank vor', 'bank')
  else
    local slot = tonumber(name:match('^r(%d+)_tap$') or '')
    local k = slot and slotK[slot]
    if k and mode == 'iem' then
      note(14, k - 1); monAdd('→ Spur ' .. (trackNo(k)) .. ' wählen', 'sel')
    end
  end
  dirty = true
end

function onReceiveNotify(key, value)
  if key == 'btn' then onButton(value) end
end

local lastRender = 0
function update()
  local t = ms()
  if dirty or t - lastRender > 1000 then lastRender = t; render() end
  if logOpen then monDraw() end
  if mode == 'iem' then
    local n = 0
    for k = 1, N do if present(k) then n = n + 1 end end
    BK.step(n, function(d) note(15, d > 0 and 3 or 2) end)
  else BK.cancel() end
end

function init()
  ctl = {}
  dirty = true
end
