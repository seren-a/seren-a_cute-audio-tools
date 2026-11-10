--[[ =========================================================================
  seren.a · Twister View · Root-Skript (TouchOSC 2, Handy hochkant)
  -------------------------------------------------------------------------
  Zeigt, was auf der aktuellen Bank deines Midi Fighter Twister liegt:
  4 x 4 Werte mit Namen und Balken, in der Farbe des Encoders.

  Verbindung: MIDI 1 = TouchOSC Bridge (senden + empfangen).
  Looks (Taste oben rechts): 1 Klar, 2 Spalte, 3 Neon, 4 IEM Neon. Bänke antippen = Twister-Bank wechseln.

  Woher die Daten kommen:
   - Reaper (reaper_mft_hub.lua) und Nuendo/Cubase (serena_MFTView.js) schicken
     Namen, Anzeigewerte, Bank und Spur (SysEx F0 7D 4D ...) plus die Werte als CC.
   - Ableton Live und Traktor schicken nur Werte (MIDI-Feedback an die Bridge);
     die Namen kommen dann aus PROFILES unten.
  Welche Bank: die Bankmeldung des Twisters (System-Kanal) oder des DAW-Skripts.
  Kommt keine, wechselt die Ansicht zu der Bank, deren Werte gerade ankommen.

  ENC und COL sind aus deiner .mfs erzeugt (mfs_parse.py): build.py schreibt sie neu.
========================================================================= ]]

local CFG = {
  midiConn = 1,
  nMidi = 10,
  sysCh = 3,             -- System-Kanal des Twisters (0-basiert, 3 = Kanal 4)
  autoBank = true,       -- ohne Bankmeldung: Bank nach ankommenden Werten wählen
  autoWindow = 400,      -- ms: so lange gilt eine Bank als "aktiv"
  autoMin = 3,           -- so viele Werte braucht es, bevor gewechselt wird
  hubTimeout = 15000,    -- ms ohne Meldung vom DAW-Skript: zurück zu PROFILES
  look = 1,              -- Start-Look: 1 Klar, 2 Spalte, 3 Neon, 4 IEM Neon
}

local function hex(h)
  local n = tonumber(h:sub(2), 16)
  return { math.floor(n / 65536) / 255, math.floor(n / 256) % 256 / 255, n % 256 / 255 }
end
-- ground, cell, text, dim text, bar track, accent (bank key on), bank key off,
-- bar: "h" (line at the bottom), "v" (column on the left), "k" (knob); val = value in the bar colour,
-- edge = cell outline in the bar colour, glow = halo around the bar, pill = black value pill
local LOOKS = {
  { name = "Klar", ground = "#0B0C0F", cell = "#17191E", txt = "#F2F4F7", dim = "#8B93A1", track = "#0D0F12",
    acc = "#36D0C4", off = "#22252B", bar = "h" },
  { name = "Spalte", ground = "#14161A", cell = "#1D2025", txt = "#ECEFF3", dim = "#8B93A1", track = "#0E1013",
    acc = "#36D0C4", off = "#1D2025", bar = "v" },
  { name = "Neon", ground = "#0E0B1F", cell = "#17122F", txt = "#F4F0FF", dim = "#A99FD0", track = "#2B2350",
    acc = "#FF3D9A", off = "#17122F", bar = "h", val = true, edge = true, glow = true },
  { name = "IEM Neon", ground = "#0E0B1F", cell = "#17122F", txt = "#F4F0FF", dim = "#A99FD0", track = "#2B2350",
    acc = "#29E7FF", off = "#17122F", bar = "k", val = true, edge = true, pill = "#06040F" },
  { name = "Kawaii Nacht", ground = "#231628", cell = "#2E1D35", txt = "#FFE8F4", dim = "#D7A6C6", track = "#4A2C55",
    acc = "#FF8FC0", off = "#3A2543", tabtxt = "#2A1030", bar = "h", val = true },
}
for _, L in ipairs(LOOKS) do for k, v in pairs(L) do if type(v) == "string" and v:sub(1, 1) == "#" then L[k] = hex(v) end end end

--@@ENC@@
local ENC = { { 0, 0 } }
--@@COL@@
local COL = { { 1, 1, 1 } }
--@@END@@

-- Namen für Programme ohne Namens-Rückmeldung (Ableton Live, Traktor).
-- Tippen auf das Quellen-Feld oben links wechselt das Profil.
-- names: bis zu 16 Einträge, Reihenfolge wie die Encoder (Zeile für Zeile).
local PROFILES = {
  { name = 'LIVE', banks = {
    { name = 'Bank 1', names = {} },
    { name = 'Bank 2', names = {} },
    { name = 'Bank 3', names = {} },
    { name = 'Bank 4', names = {} },
  } },
  { name = 'TRAKTOR', banks = {
    { name = 'Bank 1', names = {} },
    { name = 'Bank 2', names = {} },
    { name = 'Bank 3', names = {} },
    { name = 'Bank 4', names = {} },
  } },
}

--------------------------------------------------------------------------
local floor, max = math.floor, math.max
local NB = floor(#ENC / 16)
local MIDI_OUT = {}
for k = 1, CFG.nMidi do MIDI_OUT[k] = (k == CFG.midiConn) end

local REV = {}                         -- Kanal*128+CC -> Encoder 1..64
for i, e in ipairs(ENC) do REV[e[1] * 128 + e[2]] = i end

local val, hubName, hubText, colOv = {}, {}, {}, {}
for b = 1, NB do val[b], hubName[b], hubText[b], colOv[b] = {}, {}, {}, {} end
local look, laidOut = CFG.look, 0
local hub = { src = nil, t = -1e9, track = '', bankName = {} }
local bank, profile = 4, 1      -- start on bank 4 (seren.a mapping); follows the Twister afterwards
local explicitSeen = false
local act = {}                         -- [Bank] = { t = letzte Zeit, n = Anzahl im Fenster }
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
local function ms() return getMillis() end

local function hubActive()
  return hub.src ~= nil and hub.src ~= '' and ms() - hub.t < CFG.hubTimeout
end

local function setBank(b, explicit)
  if b < 1 or b > NB then return end
  if explicit then explicitSeen = true end
  if b ~= bank then bank = b end
  dirty = true
end

local UML = { 'ä', 'ö', 'ü', 'Ä', 'Ö', 'Ü', 'ß', '°' }   -- codes 1-8 from the DAW scripts
local function sysexText(m, from)
  local t = {}
  for i = from, #m - 1 do
    local c = m[i]
    if c == 10 or (c >= 32 and c <= 126) then t[#t + 1] = string.char(c)
    elseif c >= 1 and c <= 8 then t[#t + 1] = UML[c] end
  end
  return table.concat(t)
end

-- SysEx vom DAW-Skript: F0 7D 4D <cmd> ...
--   1 Name   <bank 0-7> <slot 0-15> <Text>      2 Anzeigewert <bank> <slot> <Text>
--   3 Spur   <Text>                             4 Bank <bank>
--   5 Quelle <Text> (Lebenszeichen)             6 Bankname <bank> <Text>
--   7 alles löschen (neue Zuordnung)        8 Balkenfarbe <bank> <slot> <r> <g> <b> (0-127),
--                                            slot 127 = alle Farben der Bank zurück
local function onHub(m)
  if m[2] ~= 0x7D or m[3] ~= 0x4D or not m[4] then return end
  local cmd = m[4]
  hub.t = ms()
  if (cmd == 1 or cmd == 2) and m[5] and m[6] then
    local b, s = m[5] + 1, m[6] + 1
    if b <= NB and s <= 16 then
      if cmd == 1 then hubName[b][s] = sysexText(m, 7) else hubText[b][s] = sysexText(m, 7) end
    end
  elseif cmd == 3 then hub.track = sysexText(m, 5)
  elseif cmd == 4 and m[5] then setBank(m[5] + 1, true)
  elseif cmd == 5 then hub.src = sysexText(m, 5)
  elseif cmd == 6 and m[5] then hub.bankName[m[5] + 1] = sysexText(m, 6)
  elseif cmd == 8 and m[5] and m[6] then
    local b, s = m[5] + 1, m[6] + 1
    if b <= NB then
      if m[6] == 127 then colOv[b] = {}
      elseif s <= 16 and m[9] then colOv[b][s] = { m[7] / 127, m[8] / 127, m[9] / 127 } end
    end
  elseif cmd == 7 then
    for b = 1, NB do hubName[b], hubText[b], colOv[b] = {}, {}, {} end
    hub.bankName = {}
  end
  dirty = true
end

function onReceiveMIDI(m, connections)
  local st = m[1]
  if not st then return false end
  if st == 0xF0 then onHub(m); return false end
  local kind, ch, d1, d2 = floor(st / 16), st % 16, m[2], m[3]
  if kind ~= 0xB or d1 == nil then return false end
  if ch == CFG.sysCh then
    if d2 == 127 and d1 < NB then setBank(d1 + 1, true) end   -- Twister meldet Bank
    return false
  end
  local i = REV[ch * 128 + d1]
  if i then
    local b, s = floor((i - 1) / 16) + 1, (i - 1) % 16 + 1
    if val[b][s] ~= d2 then
      val[b][s] = d2
      if b == bank then dirty = true end
    end
    local t, a = ms(), act[b]
    if a and t - a.t < CFG.autoWindow then a.n = a.n + 1; a.t = t else act[b] = { t = t, n = 1 } end
  end
  return false
end

local function col(c, a) return Color(c[1], c[2], c[3], a or 1) end
local function R(x, y, w, h) return Rectangle(math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5)) end
local function setVis(c, v) if c and c.visible ~= v then c.visible = v end end
local function setFrame(name, r) local c = C(name); if c then c.frame = r end end

-- where everything sits inside one cell, per look (landscape: wide flat cells, portrait: tall cells)
local NG = {}                 -- per cell: name x, y, width, max lines (render places name + plugin line)
local FS = { 26, 16, 38 }     -- name / plugin line / value text size (set from the layout in init)
local function layout()
  laidOut = look
  local L = LOOKS[look]
  local g = C('ground'); if g then g.color = col(L.ground) end
  local gf = (g and g.frame) or root.frame
  local land = gf.w > gf.h
  for s = 1, 16 do
    local n = 'c' .. s
    local bg = C(n .. '_bg')
    if bg then
      local f = bg.frame
      local x, y, w, h = f.x, f.y, f.w, f.h
      local top = L.bar == 'v' and 38 or 12
      local nameW = w - top - 12 - (land and 70 or 0)
      if L.bar == 'k' then
        if land then
          setFrame(n .. '_knob', R(x + 10, y + (h - 92) / 2, 92, 92))
          NG[s] = { x + 112, y + 6, w - 124, 2 }
          setFrame(n .. '_pill', R(x + 112, y + h - 56, math.min(w - 124, 180), 46))
          setFrame(n .. '_val', R(x + 112, y + h - 56, math.min(w - 124, 180), 46))
        else
          setFrame(n .. '_knob', R(x + (w - 100) / 2, y + 10, 100, 100))
          NG[s] = { x + 8, y + 114, w - 16, 2 }
          setFrame(n .. '_pill', R(x + 8, y + h - 58, w - 16, 46))
          setFrame(n .. '_val', R(x + 8, y + h - 58, w - 16, 46))
        end
      else
        NG[s] = { x + top, y + 6, nameW, land and 2 or 3 }
        if land then setFrame(n .. '_val', R(x + w - 168, y + h - 56, 156, 48))
        else setFrame(n .. '_val', R(x + top - 4, y + h - 96, w - top - 4, 48)) end
        if L.bar == 'v' then
          setFrame(n .. '_barbg', R(x + 10, y + 10, 16, h - 20))
        elseif land then
          setFrame(n .. '_barbg', R(x + 12, y + h - 38, w - 24 - 172, 14))
        else
          setFrame(n .. '_barbg', R(x + 12, y + h - 40, w - 24, 14))
        end
      end
      setFrame(n .. '_cc', land and R(x + w - 82, y + 8, 70, 20) or R(x + 12, y + h - 22, w - 24, 18))
      setFrame(n .. '_edge', R(x - 2, y - 2, w + 4, h + 4))
      setVis(C(n .. '_knob'), L.bar == 'k')
      setVis(C(n .. '_pill'), L.pill ~= nil)
      setVis(C(n .. '_barbg'), L.bar ~= 'k')
      setVis(C(n .. '_bar'), L.bar ~= 'k')
      setVis(C(n .. '_glow'), L.glow == true)
      setVis(C(n .. '_edge'), L.edge == true)
      setVis(C(n .. '_cc'), L.bar ~= 'k')
      local vl = C(n .. '_val'); if vl then vl.textAlignH = L.pill and AlignH.CENTER or AlignH.RIGHT end
      local bb = C(n .. '_barbg'); if bb then bb.color = col(L.track) end
      
    end
  end
  for _, nm in ipairs({ 'bankname', 'track', 'status', 'look_lbl' }) do
    local c = C(nm); if c then c.textColor = col(nm == 'bankname' and L.txt or L.dim) end
  end
  local sb = C('src'); if sb then sb.textColor = col(L.acc) end
  for _, nm in ipairs({ 'src_btn', 'look_btn' }) do local b = C(nm); if b then b.color = col(L.off) end end
  setText('look_lbl', 'Look: ' .. L.name)
end

-- how many lines a name needs (TouchOSC wraps at word ends; a glyph is at most about 0.58 of the size)
local function lines(t, fs, w, maxL)
  local per, n, cur = w / (fs * 0.58), 1, 0
  for word in t:gmatch('%S+') do
    local l = #word:gsub('[\128-\191]', '')
    if cur > 0 and cur + 1 + l > per then n = n + 1; cur = l else cur = cur + (cur > 0 and 1 or 0) + l end
  end
  return math.min(n, maxL)
end

local function render()
  dirty = false
  if laidOut ~= look then layout() end
  local L = LOOKS[look]
  local hubOn = hubActive()
  local prof = PROFILES[profile]
  local pb = (prof and prof.banks and prof.banks[bank]) or {}
  setText('src', hubOn and hub.src or (prof and prof.name or 'MIDI'))
  setText('track', hubOn and hub.track or '')
  setText('bankname', (hubOn and hub.bankName[bank]) or pb.name or ('Bank ' .. bank))
  local n = 0
  for s = 1, 16 do
    local i = (bank - 1) * 16 + s
    local name = hubOn and (hubName[bank][s] or '') or ((pb.names and pb.names[s]) or '')
    local v = val[bank][s]
    if hubOn and name == '' then v = nil end           -- im DAW-Modus zählt nur, was zugeordnet ist
    local txt = (hubOn and hubText[bank][s]) or (v and (floor(v / 127 * 100 + 0.5) .. ' %')) or ''
    local used = name ~= '' or v
    if used then n = n + 1 end
    local main, sub = name:match('^([^\n]*)\n?(.*)$')
    setText('c' .. s .. '_name', main)
    setText('c' .. s .. '_sub', (sub:gsub('\n', ' ')))
    local g = NG[s]
    if g then
      local nl = lines(main, FS[1], g[3], g[4])
      setFrame('c' .. s .. '_name', R(g[1], g[2], g[3], nl * FS[1] * 1.2 + 4))
      setFrame('c' .. s .. '_sub', R(g[1], g[2] + nl * FS[1] * 1.2 + 2, g[3], FS[2] * 1.4))
    end
    setText('c' .. s .. '_val', txt)
    setText('c' .. s .. '_cc', 'CC ' .. ENC[i][2])
    local c3 = colOv[bank][s] or COL[i] or { 1, 1, 1 }
    local a = used and 1 or 0.25
    local frac = (v or 0) / 127
    local bg, bar = C('c' .. s .. '_barbg'), C('c' .. s .. '_bar')
    if bg and bar then
      local f = bg.frame
      if L.bar == 'v' then bar.frame = Rectangle(f.x, f.y + f.h * (1 - frac), f.w, max(0, f.h * frac))
      else bar.frame = Rectangle(f.x, f.y, max(0, f.w * frac), f.h) end
      bar.color = col(c3, a)
      local gl = C('c' .. s .. '_glow')
      if gl then gl.frame = Rectangle(f.x - 3, f.y - 6, max(0, f.w * frac) + 6, f.h + 12); gl.color = col(c3, used and 0.28 or 0) end
    end
    local k = C('c' .. s .. '_knob')
    if k and L.bar == 'k' then k.values.x = frac; k.color = col(c3, a) end
    local pl = C('c' .. s .. '_pill'); if pl and L.pill then pl.color = col(L.pill, used and 1 or 0) end
    local e = C('c' .. s .. '_edge'); if e then e.color = col(c3, used and 0.55 or 0.12) end
    local cell = C('c' .. s .. '_bg'); if cell then cell.color = col(L.cell, used and 1 or 0.45) end
    local nl = C('c' .. s .. '_name'); if nl then nl.textColor = col(L.txt) end
    local sl = C('c' .. s .. '_sub'); if sl then sl.textColor = col(L.dim) end
    local vl = C('c' .. s .. '_val')
    if vl then
      vl.textColor = L.val and col(c3) or col(L.txt)
      -- long values ("-18.0 dB", preset names) shrink until they fit; never below 16
      local nch = #(txt:gsub('[\128-\191]', ''))
      local fit = floor((vl.frame.w - 6) / (max(nch, 1) * 0.56))
      local ts = math.min(FS[3], max(16, fit))
      if vl.textSize ~= ts then vl.textSize = ts end
    end
    local cl = C('c' .. s .. '_cc'); if cl then cl.textColor = col(L.dim) end
  end
  for b = 1, 4 do
    local tab = C('tab' .. b)
    if tab then tab.color = (b == bank) and col(L.acc) or col(L.off) end
    local nm = (hubOn and hub.bankName[b]) or (prof and prof.banks and prof.banks[b] and prof.banks[b].name)
    setText('tab' .. b .. '_lbl', nm or ('Bank ' .. b))
    local tl = C('tab' .. b .. '_lbl'); if tl then tl.textColor = (b == bank and look ~= 3) and col(L.tabtxt or LOOKS[1].ground) or col(L.txt) end
  end
  setText('status', 'Bank ' .. bank .. ' · ' .. n .. ' belegt' ..
    (hubOn and '' or (explicitSeen and '' or '  · Bank folgt den Werten')))
end

local function onButton(name)
  local b = tonumber(name:match('^tab(%d)$') or '')
  if b then
    setBank(b, true)
    sendMIDI({ 0xB0 + CFG.sysCh, b - 1, 127 }, MIDI_OUT)   -- an den Twister (über das DAW-Skript)
    return
  end
  if name == 'look_btn' then
    look = look % #LOOKS + 1
    dirty = true
    return
  end
  if name == 'src_btn' and not hubActive() then
    profile = profile % #PROFILES + 1
    dirty = true
  end
end

function onReceiveNotify(key, value)
  if key == 'btn' then onButton(value) end
end

local lastRender = 0
function update()
  local t = ms()
  if CFG.autoBank and not explicitSeen then
    local cand, n = nil, 0
    for b = 1, NB do
      local a = act[b]
      if a and t - a.t < CFG.autoWindow and a.n >= CFG.autoMin then cand = b; n = n + 1 end
    end
    if n == 1 and cand ~= bank then setBank(cand, false) end
  end
  if dirty or t - lastRender > 1000 then lastRender = t; render() end
end

function init()
  ctl = {}
  local nm = C('c1_name'); if nm and nm.textSize then FS[1] = nm.textSize end
  local sb = C('c1_sub'); if sb and sb.textSize then FS[2] = sb.textSize end
  local vb = C('c1_val'); if vb and vb.textSize then FS[3] = vb.textSize end
  laidOut = 0
  dirty = true
end
