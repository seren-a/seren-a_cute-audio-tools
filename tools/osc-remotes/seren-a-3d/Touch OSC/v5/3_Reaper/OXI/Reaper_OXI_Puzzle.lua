-- seren.a OXI Puzzle – Reaper script for the OXI One MkII (remote mode)
-- Grid: 8 tracks x up to 16 items ("Puzzle"), 4 encoders with switchable states, on-device menu (PAGE),
-- settings window: Reaper_OXI_Einstellungen.lua (same ExtState). Protocol after DrivenByMoss (OXI One).
local r = reaper
local VERSION = "v8.12.3"
local EXT = "seren_OXI"

---------------------------------------------------------------------------------------------------
-- OXI One MkII protocol
---------------------------------------------------------------------------------------------------
local HDR = "\240\0\33\91\1\1"                 -- F0 00 21 5B 01 01
local SX_ENTER = HDR .. "\6\85\247"            -- enter remote mode (device answers ... 06 53 F7)
local SX_EXIT  = HDR .. "\0\247"
local SX_ACK   = HDR .. "\6\83\247"
local PAD_ON, PAD_OFF = 0x90, 0x80             -- pads: notes on channel 1, note = row * 16 + column
local BTN_ON, BTN_OFF = 0x91, 0x81             -- buttons: notes on channel 2
local KNOB_CC = 0xB0                           -- encoders: CC 0-3 on channel 1, two's complement
local B = { ARP = 0, FLOW = 1, LEFT = 2, END_ = 3, KEYB = 4, GEN = 5, UP = 6, INIT = 7, ARRANGER = 8, MOD = 9,
  DOWN = 10, SAVE = 11, BACK = 12, PERF = 13, RIGHT = 14, LOAD = 15, ENC1 = 16, SHIFT = 17, PAGE = 18,
  COPY = 19, ENC2 = 20, STOP = 21, TRACK = 22, PASTE = 23, ENC3 = 24, PLAY = 25, LFO = 26, UNDO = 27,
  ENC4 = 28, REC = 29, STEPCHORD = 30, RANDOM = 31, MUTE = 32, SEQ1 = 33 }
local LED = { SHIFT = 9, STOP = 10, REC = 12, PLAY = 14, MUTE = 16, UNDO = 26, COPY = 28, PASTE = 34,
  PAGE = 40, TRACK = 46, RIGHT = 50, DOWN = 52, UP = 54, LEFT = 56, BACK = 0, ARRANGER = 2, SEQ1 = 58 }
local ENC_BTN = { [16] = 1, [20] = 2, [24] = 3, [28] = 4 }

-- 5x7 font (X11 misc-fixed 5x7, public domain), 8 rows, 5 bits per row (bit 4 = left)
local FONT = {
  [32] = {0,0,0,0,0,0,0,0},
  [33] = {0,4,4,4,4,0,4,0},
  [34] = {0,10,10,10,0,0,0,0},
  [35] = {0,0,10,31,10,31,10,0},
  [36] = {0,0,14,20,14,5,14,0},
  [37] = {0,16,18,4,8,18,2,0},
  [38] = {0,0,8,20,8,20,10,0},
  [39] = {0,4,4,4,0,0,0,0},
  [40] = {0,4,8,8,8,8,4,0},
  [41] = {0,8,4,4,4,4,8,0},
  [42] = {0,0,10,4,14,4,10,0},
  [43] = {0,0,4,4,31,4,4,0},
  [44] = {0,0,0,0,0,6,4,8},
  [45] = {0,0,0,0,30,0,0,0},
  [46] = {0,0,0,0,0,12,12,0},
  [47] = {0,0,2,4,8,16,0,0},
  [48] = {0,4,10,10,10,10,4,0},
  [49] = {0,4,12,4,4,4,14,0},
  [50] = {0,12,18,2,4,8,30,0},
  [51] = {0,30,2,12,2,18,12,0},
  [52] = {0,4,12,20,30,4,4,0},
  [53] = {0,30,16,28,2,18,12,0},
  [54] = {0,12,16,28,18,18,12,0},
  [55] = {0,30,2,4,4,8,8,0},
  [56] = {0,12,18,12,18,18,12,0},
  [57] = {0,12,18,18,14,2,12,0},
  [58] = {0,0,12,12,0,12,12,0},
  [59] = {0,0,12,12,0,12,8,16},
  [60] = {0,0,2,4,8,4,2,0},
  [61] = {0,0,0,30,0,30,0,0},
  [62] = {0,0,8,4,2,4,8,0},
  [63] = {0,4,10,2,4,0,4,0},
  [64] = {0,12,18,22,22,16,12,0},
  [65] = {0,12,18,18,30,18,18,0},
  [66] = {0,28,18,28,18,18,28,0},
  [67] = {0,12,18,16,16,18,12,0},
  [68] = {0,28,18,18,18,18,28,0},
  [69] = {0,30,16,28,16,16,30,0},
  [70] = {0,30,16,28,16,16,16,0},
  [71] = {0,12,18,16,22,18,14,0},
  [72] = {0,18,18,30,18,18,18,0},
  [73] = {0,14,4,4,4,4,14,0},
  [74] = {0,2,2,2,2,18,12,0},
  [75] = {0,18,20,24,24,20,18,0},
  [76] = {0,16,16,16,16,16,30,0},
  [77] = {0,18,30,30,18,18,18,0},
  [78] = {0,18,26,26,22,22,18,0},
  [79] = {0,12,18,18,18,18,12,0},
  [80] = {0,28,18,18,28,16,16,0},
  [81] = {0,12,18,18,18,26,12,2},
  [82] = {0,28,18,18,28,20,18,0},
  [83] = {0,12,18,8,4,18,12,0},
  [84] = {0,14,4,4,4,4,4,0},
  [85] = {0,18,18,18,18,18,12,0},
  [86] = {0,18,18,18,18,12,12,0},
  [87] = {0,18,18,18,30,30,18,0},
  [88] = {0,18,18,12,12,18,18,0},
  [89] = {0,10,10,10,4,4,4,0},
  [90] = {0,30,2,4,8,16,30,0},
  [91] = {0,14,8,8,8,8,14,0},
  [92] = {0,0,16,8,4,2,0,0},
  [93] = {0,14,2,2,2,2,14,0},
  [94] = {0,4,10,0,0,0,0,0},
  [95] = {0,0,0,0,0,0,30,0},
  [96] = {0,8,4,0,0,0,0,0},
  [97] = {0,0,0,14,18,22,10,0},
  [98] = {0,16,16,28,18,18,28,0},
  [99] = {0,0,0,12,16,16,12,0},
  [100] = {0,2,2,14,18,18,14,0},
  [101] = {0,0,0,12,22,24,12,0},
  [102] = {0,4,10,8,28,8,8,0},
  [103] = {0,0,0,14,18,12,16,14},
  [104] = {0,16,16,28,18,18,18,0},
  [105] = {0,4,0,12,4,4,14,0},
  [106] = {0,2,0,2,2,2,10,4},
  [107] = {0,16,16,20,24,20,18,0},
  [108] = {0,12,4,4,4,4,14,0},
  [109] = {0,0,0,20,30,18,18,0},
  [110] = {0,0,0,28,18,18,18,0},
  [111] = {0,0,0,12,18,18,12,0},
  [112] = {0,0,0,28,18,18,28,16},
  [113] = {0,0,0,14,18,18,14,2},
  [114] = {0,0,0,28,18,16,16,0},
  [115] = {0,0,0,14,24,6,28,0},
  [116] = {0,8,8,28,8,8,6,0},
  [117] = {0,0,0,18,18,18,14,0},
  [118] = {0,0,0,10,10,10,4,0},
  [119] = {0,0,0,18,18,30,30,0},
  [120] = {0,0,0,18,12,12,18,0},
  [121] = {0,0,0,18,18,10,4,8},
  [122] = {0,0,0,30,4,8,30,0},
  [123] = {0,2,4,12,4,4,2,0},
  [124] = {0,4,4,4,4,4,4,0},
  [125] = {0,8,4,6,4,4,8,0},
  [126] = {0,10,20,0,0,0,0,0},
  [228] = {0,10,0,14,18,22,10,0},
  [246] = {0,10,0,12,18,18,12,0},
  [252] = {0,10,0,18,18,18,14,0},
  [196] = {0,18,12,18,30,18,18,0},
  [214] = {0,18,12,18,18,18,12,0},
  [220] = {0,18,0,18,18,18,12,0},
  [223] = {0,12,18,20,18,18,20,0},
  [176] = {0,4,10,4,0,0,0,0},
}


---------------------------------------------------------------------------------------------------
-- settings (ExtState, shared with the settings window)
---------------------------------------------------------------------------------------------------
local DEFAULTS = {
  port = "oxi",              -- part of the MIDI device name (in + out)
  layout = "16",             -- "10s" = 10 items + 5 state pads, or "12", "14", "16" items
  markerRow = "0",           -- top row = first marker lane
  markerKind = "auto",       -- marker row: auto (regions if lane 1 has any) / marker / region / both
  cells = "auto",            -- grid columns: auto (regions if there are any) / regions / items
  groups = "1",              -- items mode: grouped items = one field
  rgnRange = "",             -- e.g. "100-199": only markers/regions with these numbers (instead of the lane)
  markerLane = "1",          -- which marker lane counts (1 = topmost used lane, 2 = next ...)
  folders = "1",             -- show folders / groups
  empty = "1",               -- show tracks without items
  receives = "show",         -- show / hide / page (tracks with receives on their own page, BACK switches)
  visible = "all",           -- all / tcp / mcp  (visibility like the track list or the mixer)
  pinned = "1",              -- tracks pinned in the TCP come first (with visible = tcp)
  flip = "0",                -- grid upside down
  states = "1,2,3,4,5,6,7",  -- encoder states in order (TRACK cycles)
  sendPush = "mute",         -- mute = push mutes, 2x = pre/post | mode = push pre/post, 2x mutes
  preFx = "0",               -- pre/post also steps through pre-FX
  handover = "1",            -- on exit hand the OXI back to DrivenByMoss (asks it to repaint)
  mainSend = "1",            -- Shift + track button = master/parent send on/off
  tripleVol = "1",           -- 3x track button = track 0 dB <-> -inf
  seqMute = "1",             -- 2x track button = mute
  seqSolo = "1",             -- hold track button = solo
  seqState = "1",            -- track button LEDs: muted blinks slowly, solo fast, 2nd LED = rec arm
  statusCol = "0",           -- last grid column = track status (colour / mute / solo / rec)
  turnShow = "big",          -- value while turning: big (lines 1-3) / line (bottom) / both / off
  marquee = "1",             -- long track / item names scroll
  select = "full",           -- full = select in Reaper + scroll mixer/arrange, sel = only select, oxi = only on the OXI
  follow = "1",              -- a track selected in Reaper scrolls the puzzle to it
  s1 = "_SWS_TAKESCHANMODE0", s2 = "_SWS_TAKESCHANMODE3", s3 = "normtrack", s4 = "zoomitem",
  d1 = "copyfx", d2 = "copysends", d3 = "", d4 = "",
  l1 = "pastefx", l2 = "replacesends", l3 = "removefx", l4 = "removesends",
}
local cfg = {}
local function loadCfg()
  for k, v in pairs(DEFAULTS) do
    local s = r.GetExtState(EXT, k)
    cfg[k] = (s ~= nil and s ~= "") and s or v
  end
end
local function setCfg(k, v)
  cfg[k] = v
  r.SetExtState(EXT, k, v, true)
  r.SetExtState(EXT, "rev", tostring(r.time_precise()), false)
end
local cfgRev = ""

local STATE_NAMES = { "Items", "Sends 1-4", "Sends 5-8", "Sends 9-12", "Sends 13-16", "Item", "Spur" }
local STATE_RGB = { { 255, 255, 255 }, { 0, 202, 254 }, { 0, 140, 254 }, { 80, 90, 254 }, { 150, 60, 254 },
  { 254, 159, 1 }, { 80, 254, 3 } }
local function stateList()
  local t = {}
  for s in cfg.states:gmatch("%d+") do local n = tonumber(s); if STATE_NAMES[n] then t[#t + 1] = n end end
  if #t == 0 then t = { 1 } end
  return t
end

---------------------------------------------------------------------------------------------------
-- MIDI ports
---------------------------------------------------------------------------------------------------
local oxiIn, oxiOut
local function findPort(count, getName)
  local want = cfg.port:lower()
  for i = 0, count() - 1 do
    local ok, n = getName(i, "")
    if ok and n:lower():find(want, 1, true) then return i, n end
  end
end
local function send(msg) if oxiOut then r.SendMIDIMessageToHardware(oxiOut, msg) end end

---------------------------------------------------------------------------------------------------
-- display 128 x 64
---------------------------------------------------------------------------------------------------
local FB = {}
local lastDisp, lastDispT = "", 0
local function clr() for i = 0, 128 * 64 - 1 do FB[i] = false end end
local function px(x, y, on) if x >= 0 and x < 128 and y >= 0 and y < 64 then FB[y * 128 + x] = on end end
local UML = { ["ä"] = 0xe4, ["ö"] = 0xf6, ["ü"] = 0xfc, ["Ä"] = 0xc4, ["Ö"] = 0xd6, ["Ü"] = 0xdc, ["ß"] = 0xdf, ["°"] = 0xb0 }
local function chars(s)
  local out, i = {}, 1
  while i <= #s do
    local c = s:byte(i)
    if c >= 0xC2 and c <= 0xC3 and i < #s then
      local u = UML[s:sub(i, i + 1)]
      out[#out + 1] = u or 63; i = i + 2
    elseif c >= 0x80 then
      out[#out + 1] = 63; i = i + 1
      while i <= #s and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i + 1 end
    else out[#out + 1] = c; i = i + 1 end
  end
  return out
end
local function text(x, y, s, inv, maxw, off)
  local cs = chars(s)
  off = off or 0
  local n = maxw and math.min(#cs - off, maxw) or #cs - off
  for k = 1, n do
    local g = FONT[cs[k + off]] or FONT[63]
    for row = 0, 7 do
      local bits = g[row + 1]
      for col = 0, 5 do
        local on = col < 5 and ((bits >> (4 - col)) & 1) == 1
        if inv then on = not on end
        if on or inv then px(x + (k - 1) * 6 + col, y + row, on) end
      end
    end
  end
end
local function bar(y) for x = 0, 127 do for yy = y, y + 7 do px(x, yy, true) end end end
local function bigText(x, y, s, maxw)          -- double size (12 x 16 per character)
  local cs = chars(s)
  for k = 1, math.min(#cs, maxw or 10) do
    local g = FONT[cs[k]] or FONT[63]
    for row = 0, 7 do
      for col = 0, 4 do
        if ((g[row + 1] >> (4 - col)) & 1) == 1 then
          local bx, by = x + (k - 1) * 12 + col * 2, y + row * 2
          px(bx, by, true); px(bx + 1, by, true); px(bx, by + 1, true); px(bx + 1, by + 1, true)
        end
      end
    end
  end
end
local function marqueeOff(s, n)                 -- running text: pause, one character every 0.3 s, pause
  local len = #chars(s)
  if cfg.marquee ~= "1" or len <= n then return 0 end
  local steps = len - n
  local period = 1.5 + steps * 0.3 + 1.5
  local t = r.time_precise() % period
  if t < 1.5 then return 0 end
  return math.min(steps, math.floor((t - 1.5) / 0.3))
end
local function packDisplay()
  local t = { HDR, "\3" }
  for y = 0, 63, 8 do
    for x = 0, 127 do
      local n1, n2 = 0, 0
      for bit = 0, 7 do
        if FB[(y + bit) * 128 + x] then
          if bit > 3 then n1 = n1 | (1 << (bit - 4)) else n2 = n2 | (1 << bit) end
        end
      end
      t[#t + 1] = string.char(n1, n2)
    end
  end
  t[#t + 1] = "\247"
  return table.concat(t)
end
local function flushDisplay(force)
  local m = packDisplay()
  local now = r.time_precise()
  if m ~= lastDisp or force or now - lastDispT > 2.5 then          -- resend keeps the OLED awake
    send(m); lastDisp, lastDispT = m, now
  end
end

---------------------------------------------------------------------------------------------------
-- grid LEDs
---------------------------------------------------------------------------------------------------
local sentPad = {}
local LEVELS = { 1, 9, 15, 255 }             -- like DrivenByMoss: 4 brightness steps per colour channel
local function crush(v)
  if v <= 0 then return 0 end
  return LEVELS[math.floor(v / 255 * 3 + 0.5) + 1] or 255
end
local function padBytes(p, rgb)
  local y, x = p // 16, p % 16
  if cfg.flip ~= "1" then y = 7 - y end          -- OXI y 0 = bottom row
  local rr, gg, bb = crush(rgb[1]), crush(rgb[2]), crush(rgb[3])
  return string.char(y, x, rr >> 4, rr & 15, gg >> 4, gg & 15, bb >> 4, bb & 15)
end
local function flushGrid(want, force)
  local t = {}
  for p = 0, 127 do
    local c = want[p] or { 0, 0, 0 }
    local key = crush(c[1]) .. "," .. crush(c[2]) .. "," .. crush(c[3])
    if force or sentPad[p] ~= key then t[#t + 1] = padBytes(p, c); sentPad[p] = key end
  end
  if #t > 0 then send(HDR .. "\1" .. table.concat(t) .. "\247") end
end
local sentLed = {}
local function led(id, on, force)
  local v = on and 1 or 0
  if force or sentLed[id] ~= v then
    send(HDR .. string.char(2, id // 16, id % 16, 0, v) .. "\247"); sentLed[id] = v
  end
end

---------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------
local function rgbOf(native)
  if not native or native & 0x1000000 == 0 then return nil end
  local rr, gg, bb = r.ColorFromNative(native & 0xFFFFFF)
  return { rr, gg, bb }
end
local function scale(c, f) return { math.floor(c[1] * f), math.floor(c[2] * f), math.floor(c[3] * f) } end
local DEF_RGB = { 120, 140, 160 }
local function trName(tr)
  local _, n = r.GetTrackName(tr)
  return n
end
local function dB(v) if v < 1e-6 then return -150 end return 20 * math.log(v, 10) end
local function amp(db) if db <= -149 then return 0 end return 10 ^ (db / 20) end
local function fmtDb(v) local d = dB(v); if d <= -149 then return "-inf" end return string.format("%+.1f", d) end
local note, noteT = "", 0
local function notify(s) note, noteT = s, r.time_precise() end
local undoPending, undoT = nil, 0
local function markUndo(s) undoPending, undoT = s, r.time_precise() end

---------------------------------------------------------------------------------------------------
-- model: visible tracks
---------------------------------------------------------------------------------------------------
local view = { off = 0, colOff = 0, page = 1, state = 1, menu = false, menuRow = 0, mode = "puzzle", sgroup = 0, menuPage = 1 }
local PAGE_NAMES = { puzzle = "PUZZLE" }      -- the send pages live in DrivenByMoss (Send 16 / Send 32) since v8.2
local function pageList()
  local t = {}

  if #t == 0 then t = { "puzzle" } end
  return t
end
local tracks = {}
local function hasReceives(tr) return r.GetTrackNumSends(tr, -1) > 0 end
local function buildTracks(diag)
  local list, pinned = {}, {}
  local out = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local ok = true
    local why = {}
    local isFolder = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1
    if cfg.visible == "tcp" and r.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 0 then ok = false; why[#why + 1] = "in TCP ausgeblendet" end
    if cfg.visible == "mcp" and r.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") == 0 then ok = false; why[#why + 1] = "im Mixer ausgeblendet" end
    if cfg.folders == "0" and isFolder then ok = false; why[#why + 1] = "Ordner (Ordner aus)" end
    if cfg.empty == "0" and not isFolder and r.CountTrackMediaItems(tr) == 0 then ok = false; why[#why + 1] = "keine Items (leere Spuren aus)" end
    local rc = hasReceives(tr)
    if cfg.receives == "hide" and rc then ok = false; why[#why + 1] = "hat Receives (Receives aus)" end
    if cfg.receives == "page" and ((view.page == 1 and rc) or (view.page == 2 and not rc)) then
      ok = false; why[#why + 1] = rc and "hat Receives (eigene Seite, BACK)" or "keine Receives (Receives-Seite)"
    end
    if diag then
      local _, nm = r.GetTrackName(tr)
      out[#out + 1] = string.format("%3d %-24s %s%s", i + 1, nm, ok and "ja" or "NEIN: ", table.concat(why, ", "))
    end
    if ok then
      if cfg.visible == "tcp" and cfg.pinned == "1" and r.GetMediaTrackInfo_Value(tr, "B_TCPPIN") == 1 then
        pinned[#pinned + 1] = tr
      else list[#list + 1] = tr end
    end
  end
  for k = #pinned, 1, -1 do table.insert(list, 1, pinned[k]) end
  tracks = list
  if diag then
    r.ShowConsoleMsg("seren.a OXI Puzzle " .. VERSION .. " – Spurliste (Spur, Name, im Grid?)\n" .. table.concat(out, "\n") ..
      string.format("\nIm Grid: %d Spuren, Ansicht ab Spur %d der Liste\n", #list, view.off + 1))
  end
end
local function rowsForTracks()
  if view.mode == "s32" then return 4 end
  if view.mode == "s16" then return 8 end
  return cfg.markerRow == "1" and 7 or 8
end
local function firstTrackRow() return (view.mode == "puzzle" and cfg.markerRow == "1") and 1 or 0 end
local function trackOfRow(row)        -- grid row / track button 0-7 -> track on the current page
  if view.mode == "s32" then return tracks[view.off + row // 2 + 1] end
  if view.mode == "s16" then return tracks[view.off + row + 1] end
  local k = row - firstTrackRow()
  if k < 0 or k >= rowsForTracks() then return nil end
  return tracks[view.off + k + 1]
end
local function itemCols()
  local n = cfg.layout == "10s" and 10 or (tonumber(cfg.layout) or 16)
  if cfg.statusCol == "1" and n >= 16 then n = 15 end   -- column 16 = status
  return n
end
local function clampView()
  local maxOff = math.max(0, #tracks - rowsForTracks())
  if view.off > maxOff then view.off = maxOff end
  if view.off < 0 then view.off = 0 end
  if view.colOff < 0 then view.colOff = 0 end
end
local function trackAtRow(row)
  local k = row - firstTrackRow()
  if k < 0 or k >= rowsForTracks() then return nil end
  return tracks[view.off + k + 1]
end
local function oxiOnly() return cfg.select == "oxi" end
local function selTrack()                        -- the track the encoders work on
  if oxiOnly() then
    if view.focus and r.ValidatePtr(view.focus, "MediaTrack*") then return view.focus end
  end
  return r.GetSelectedTrack(0, 0)
end
local lastItem                            -- item last touched on the grid
local lastCell                            -- all items of the field last touched
local function targetItems()
  local tr, t = selTrack(), {}
  if not tr then return t end
  if not oxiOnly() then
    for i = 0, r.CountTrackMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, i)
      if r.IsMediaItemSelected(it) then t[#t + 1] = it end
    end
  end
  if #t == 0 and lastCell then
    for _, it in ipairs(lastCell) do
      if r.ValidatePtr(it, "MediaItem*") and r.GetMediaItem_Track(it) == tr then t[#t + 1] = it end
    end
  end
  if #t == 0 and lastItem and r.ValidatePtr(lastItem, "MediaItem*") and r.GetMediaItem_Track(lastItem) == tr then
    t[1] = lastItem
  end
  return t
end
-- markers and regions of ruler lane 1 (REAPER 7 lanes; older REAPER: all count as lane 1)
local function laneOf(i)
  if r.GetRegionOrMarker and r.GetRegionOrMarkerInfo_Value then
    local ok, m = pcall(r.GetRegionOrMarker, 0, i, "")
    if ok and m then
      local ok2, l = pcall(r.GetRegionOrMarkerInfo_Value, 0, m, "I_LANENUMBER")
      if ok2 and type(l) == "number" then return l end
    end
  end
  return 0
end
local function allMarks()                         -- only the chosen lane (markerLane: 1 = the topmost used lane)
  local t, i, lanes, seen = {}, 0, {}, {}
  while true do
    local ok, rgn, pos, rend, name, idx, col = r.EnumProjectMarkers3(0, i)
    if ok == 0 then break end
    local l = laneOf(i)
    if not seen[l] then seen[l] = true; lanes[#lanes + 1] = l end
    t[#t + 1] = { rgn = rgn, pos = pos, rend = rend, name = name, idx = idx, col = col, lane = l }
    i = i + 1
  end
  table.sort(lanes)
  local want = lanes[tonumber(cfg.markerLane) or 1] or lanes[1]
  local lo, hi = cfg.rgnRange:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")   -- optional: only numbers lo-hi
  lo, hi = tonumber(lo), tonumber(hi)
  local out = {}
  for _, m in ipairs(t) do
    if lo then
      if m.idx >= lo and m.idx <= hi then out[#out + 1] = m end
    elseif m.lane == want then out[#out + 1] = m end
  end
  return out
end
local function regions()
  local t = {}
  for _, m in ipairs(allMarks()) do if m.rgn then t[#t + 1] = m end end
  table.sort(t, function(a, b) return a.pos < b.pos end)
  return t
end
local function regionMode()
  if cfg.cells == "items" then return false end
  return #regions() > 0
end
local function markers()                         -- what the marker row shows
  local k = cfg.markerKind
  if regionMode() then k = "region" end         -- region columns: the row lines up with them
  local t = {}
  local all = allMarks()
  if k == "auto" then
    k = "marker"
    for _, m in ipairs(all) do if m.rgn then k = "region" end end
  end
  for _, m in ipairs(all) do if k == "both" or (k == "region") == (m.rgn == true) then t[#t + 1] = m end end
  table.sort(t, function(a, b) return a.pos < b.pos end)
  return t
end

-- fields of a track: one per region (items inside it, false = gap), or per item (grouped items together)
local cellCache = {}
local function cellsOf(tr)
  local c = cellCache[tr]
  if c then return c end
  c = {}
  local n = r.CountTrackMediaItems(tr)
  if regionMode() then
    for k, rg in ipairs(regions()) do
      local f = {}
      for i = 0, n - 1 do
        local it = r.GetTrackMediaItem(tr, i)
        local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
        local e = p + r.GetMediaItemInfo_Value(it, "D_LENGTH")
        if p < rg.rend - 1e-6 and e > rg.pos + 1e-6 then f[#f + 1] = it end
      end
      c[k] = #f > 0 and { items = f, pos = rg.pos, len = rg.rend - rg.pos, rgn = rg } or false
    end
  else
    local byGroup = {}
    for i = 0, n - 1 do
      local it = r.GetTrackMediaItem(tr, i)
      local g = cfg.groups == "1" and r.GetMediaItemInfo_Value(it, "I_GROUPID") or 0
      local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local e = p + r.GetMediaItemInfo_Value(it, "D_LENGTH")
      if g > 0 and byGroup[g] then
        local f = byGroup[g]
        f.items[#f.items + 1] = it
        local fe = math.max(f.pos + f.len, e); f.pos = math.min(f.pos, p); f.len = fe - f.pos
      else
        local f = { items = { it }, pos = p, len = e - p }
        c[#c + 1] = f
        if g > 0 then byGroup[g] = f end
      end
    end
  end
  cellCache[tr] = c
  return c
end
local function cellAt(tr, col)
  local c = cellsOf(tr)[view.colOff + col + 1]
  return c or nil
end

---------------------------------------------------------------------------------------------------
-- built-in actions (push slots)
---------------------------------------------------------------------------------------------------
local clip = {}
local function forTargets(fn)                  -- selected tracks (OXI-only mode: the OXI's track)
  if oxiOnly() then local t = selTrack(); if t then fn(t); return 1 end; return 0 end
  local n = r.CountSelectedTracks(0)
  for i = 0, n - 1 do fn(r.GetSelectedTrack(0, i)) end
  return n
end
local SEND_KEYS = { "D_VOL", "D_PAN", "B_MUTE", "B_PHASE", "B_MONO", "I_SENDMODE", "I_SRCCHAN", "I_DSTCHAN", "D_PANLAW" }
local BUILTIN = {
  copyfx = function(tr)
    clip.fx = r.GetTrackGUID(tr)
    notify(string.format("FX kopiert (%d)", r.TrackFX_GetCount(tr)))
  end,
  pastefx = function(tr)
    local src = clip.fx and r.BR_GetMediaTrackByGUID and r.BR_GetMediaTrackByGUID(0, clip.fx)
    if not src then
      for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i); if r.GetTrackGUID(t) == clip.fx then src = t end
      end
    end
    if not src then notify("erst FX kopieren"); return end
    r.Undo_BeginBlock()
    local n = 0
    forTargets(function(dst)
      if dst ~= src then
        for i = 0, r.TrackFX_GetCount(src) - 1 do r.TrackFX_CopyToTrack(src, i, dst, r.TrackFX_GetCount(dst), false) end
        n = n + 1
      end
    end)
    r.Undo_EndBlock("OXI: FX einfügen", -1)
    notify(string.format("FX eingefügt (%d Spur)", n))
  end,
  removefx = function()
    r.Undo_BeginBlock()
    forTargets(function(dst) for i = r.TrackFX_GetCount(dst) - 1, 0, -1 do r.TrackFX_Delete(dst, i) end end)
    r.Undo_EndBlock("OXI: FX entfernen", -1)
    notify("FX entfernt")
  end,
  copysends = function(tr)
    local t = {}
    for i = 0, r.GetTrackNumSends(tr, 0) - 1 do
      local s = { dest = r.GetTrackSendInfo_Value(tr, 0, i, "P_DESTTRACK") }
      for _, k in ipairs(SEND_KEYS) do s[k] = r.GetTrackSendInfo_Value(tr, 0, i, k) end
      t[#t + 1] = s
    end
    clip.sends = t
    notify(string.format("%d Sends kopiert", #t))
  end,
  replacesends = function()
    if not clip.sends then notify("erst Sends kopieren"); return end
    r.Undo_BeginBlock()
    forTargets(function(dst)
      for i = r.GetTrackNumSends(dst, 0) - 1, 0, -1 do r.RemoveTrackSend(dst, 0, i) end
      for _, s in ipairs(clip.sends) do
        if s.dest ~= dst and r.ValidatePtr(s.dest, "MediaTrack*") then
          local k = r.CreateTrackSend(dst, s.dest)
          for _, key in ipairs(SEND_KEYS) do r.SetTrackSendInfo_Value(dst, 0, k, key, s[key]) end
        end
      end
    end)
    r.Undo_EndBlock("OXI: Sends ersetzen", -1)
    notify(string.format("Sends ersetzt (%d)", #clip.sends))
  end,
  removesends = function()
    r.Undo_BeginBlock()
    forTargets(function(dst) for i = r.GetTrackNumSends(dst, 0) - 1, 0, -1 do r.RemoveTrackSend(dst, 0, i) end end)
    r.Undo_EndBlock("OXI: Sends entfernen", -1)
    notify("Sends entfernt")
  end,
  normtrack = function(tr)
    local cmd = r.NamedCommandLookup("_BR_NORMALIZE_LOUDNESS_ITEMS23")
    if cmd == 0 then notify("SWS fehlt"); return end
    r.Undo_BeginBlock()
    r.Main_OnCommand(40289, 0)                 -- unselect all items
    for i = 0, r.CountTrackMediaItems(tr) - 1 do r.SetMediaItemSelected(r.GetTrackMediaItem(tr, i), true) end
    r.Main_OnCommand(cmd, 0)
    r.Undo_EndBlock("OXI: Spur normalisieren", -1)
    notify("normalisiert")
  end,
  zoomitem = function()
    local t = targetItems()
    if #t == 0 then notify("kein Item"); return end
    local p = r.GetMediaItemInfo_Value(t[1], "D_POSITION")
    local l = r.GetMediaItemInfo_Value(t[1], "D_LENGTH")
    r.GetSet_ArrangeView2(0, true, 0, 0, p - l * 0.1, p + l * 1.1)
    notify("Zoom auf Item")
  end,
}
local BUILTIN_NAME = { copyfx = "FX kopieren", pastefx = "FX einfügen", removefx = "FX entfernen",
  copysends = "Sends kop.", replacesends = "Sends ersetzen", removesends = "Sends entf.",
  normtrack = "Normalisieren", zoomitem = "Zoom Item" }
local function runSlot(id)
  if not id or id == "" then notify("frei (Einstellungen)"); return end
  local tr = selTrack()
  if BUILTIN[id] then
    if not tr then notify("keine Spur"); return end
    BUILTIN[id](tr); return
  end
  local cmd = tonumber(id) or r.NamedCommandLookup(id)
  if not cmd or cmd == 0 then notify("Aktion fehlt: " .. id); return end
  r.Main_OnCommand(cmd, 0)
  notify(id:gsub("^_", ""):sub(1, 21))
end

---------------------------------------------------------------------------------------------------
-- encoders
---------------------------------------------------------------------------------------------------
local shift = false
local function sendCtx() return view.mode ~= "puzzle" or (view.state >= 2 and view.state <= 5) end
local function sendIndex(e)
  if view.mode ~= "puzzle" then return view.sgroup * 4 + e - 1 end
  local s = view.state; if s >= 2 and s <= 5 then return (s - 2) * 4 + e - 1 end
end
local function groupCount() return view.mode == "s32" and 8 or 4 end
local function stepDb(v, d, lo, hi)
  local db = dB(v)
  if db <= -149 then db = d > 0 and -60.5 or -150 end
  db = db + d
  if db < -60 then return 0 end
  return amp(math.min(hi or 12, db))
end
local MODES = { [0] = "Post", [3] = "Pre", [1] = "PreFX" }   -- Pre = pre-fader (post-FX)
local function cycleMode(m)
  if cfg.preFx == "1" then
    if m == 0 then return 3 elseif m == 3 then return 1 else return 0 end
  end
  return m == 0 and 3 or 0
end
local function turnRaw(e, d)
  local tr = selTrack()
  local s = sendCtx() and 2 or view.state
  local acc = math.abs(d) > 2 and 4 or 1
  if s == 1 then
    if e == 4 then view.off = view.off + (d > 0 and 1 or -1); clampView(); return end
    local its = targetItems()
    if #its == 0 then notify("kein Item"); return end
    for _, it in ipairs(its) do
      if e == 1 then
        r.SetMediaItemInfo_Value(it, "D_VOL", stepDb(r.GetMediaItemInfo_Value(it, "D_VOL"), d * 0.5, nil, 24))
      else
        local key = e == 2 and "D_FADEINLEN" or "D_FADEOUTLEN"
        local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
        local v = r.GetMediaItemInfo_Value(it, key) + d * 0.01 * acc
        r.SetMediaItemInfo_Value(it, key, math.max(0, math.min(len, v)))
      end
    end
    r.UpdateArrange(); markUndo("OXI: Item")
  elseif s >= 2 and s <= 5 then
    if not tr then return end
    local i = sendIndex(e)
    if i >= r.GetTrackNumSends(tr, 0) then notify("kein Send " .. (i + 1)); return end
    r.SetTrackSendInfo_Value(tr, 0, i, "D_VOL", stepDb(r.GetTrackSendInfo_Value(tr, 0, i, "D_VOL"), d * 0.5))
    markUndo("OXI: Send")
  elseif s == 6 then
    local its = targetItems()
    if #its == 0 then notify("kein Item"); return end
    for _, it in ipairs(its) do
      local tk = r.GetActiveTake(it)
      if e == 1 then
        local step = shift and (60 / r.Master_GetTempo()) or 0.01 * acc
        r.SetMediaItemInfo_Value(it, "D_POSITION", math.max(0, r.GetMediaItemInfo_Value(it, "D_POSITION") + d * step))
      elseif e == 2 and tk then
        r.SetMediaItemTakeInfo_Value(tk, "D_PITCH", r.GetMediaItemTakeInfo_Value(tk, "D_PITCH") + d * (shift and 0.1 or 1))
      elseif e == 3 and tk then
        local v = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") + d * 0.01
        r.SetMediaItemTakeInfo_Value(tk, "D_PLAYRATE", math.max(0.1, math.min(4, v)))
      elseif e == 4 then
        local v = r.GetMediaItemInfo_Value(it, "D_LENGTH") + d * 0.01 * acc
        r.SetMediaItemInfo_Value(it, "D_LENGTH", math.max(0.01, v))
      end
    end
    r.UpdateArrange(); markUndo("OXI: Item")
  elseif s == 7 then
    if e == 4 then view.off = view.off + (d > 0 and 1 or -1); clampView(); return end
    if not tr then return end
    if e == 1 then r.SetMediaTrackInfo_Value(tr, "D_VOL", stepDb(r.GetMediaTrackInfo_Value(tr, "D_VOL"), d * 0.5))
    elseif e == 2 then
      r.SetMediaTrackInfo_Value(tr, "D_PAN", math.max(-1, math.min(1, r.GetMediaTrackInfo_Value(tr, "D_PAN") + d * 0.02)))
    else
      r.SetMediaTrackInfo_Value(tr, "D_WIDTH", math.max(-1, math.min(1, r.GetMediaTrackInfo_Value(tr, "D_WIDTH") + d * 0.02)))
    end
    markUndo("OXI: Spur")
  end
end
local function turn(e, d)
  local n0 = noteT
  turnRaw(e, d)
  if noteT == n0 then view.vf = { e = e, t = r.time_precise() } end    -- show the value while turning
end
local function encPush(e, kind)                -- kind: 1 = single, 2 = double, 3 = long
  local s = sendCtx() and 2 or view.state
  local tr = selTrack()
  if s == 1 then
    runSlot(cfg[({ "s", "d", "l" })[kind] .. e]); return
  end
  if s >= 2 and s <= 5 then
    if not tr then return end
    local i = sendIndex(e)
    if i >= r.GetTrackNumSends(tr, 0) then return end
    local wantMute = (cfg.sendPush == "mute") == (kind == 1)
    if kind == 3 then
      r.SetTrackSendInfo_Value(tr, 0, i, "D_VOL", 1); notify("Send " .. (i + 1) .. " 0 dB")
    elseif wantMute then
      local m = r.GetTrackSendInfo_Value(tr, 0, i, "B_MUTE") == 1
      r.SetTrackSendInfo_Value(tr, 0, i, "B_MUTE", m and 0 or 1)
      notify("Send " .. (i + 1) .. (m and " an" or " stumm"))
    else
      local m = cycleMode(math.floor(r.GetTrackSendInfo_Value(tr, 0, i, "I_SENDMODE")))
      r.SetTrackSendInfo_Value(tr, 0, i, "I_SENDMODE", m)
      notify("Send " .. (i + 1) .. " " .. MODES[m])
    end
    markUndo("OXI: Send")
    return
  end
  -- Item / Spur: push resets the value under the encoder
  if s == 6 then
    for _, it in ipairs(targetItems()) do
      local tk = r.GetActiveTake(it)
      if e == 2 and tk then r.SetMediaItemTakeInfo_Value(tk, "D_PITCH", 0)
      elseif e == 3 and tk then r.SetMediaItemTakeInfo_Value(tk, "D_PLAYRATE", 1) end
    end
    if e == 2 or e == 3 then notify(e == 2 and "Pitch 0" or "Rate 1.00"); r.UpdateArrange(); markUndo("OXI: Item") end
  elseif s == 7 and tr then
    if e == 1 then r.SetMediaTrackInfo_Value(tr, "D_VOL", 1); notify("Spur 0 dB")
    elseif e == 2 then r.SetMediaTrackInfo_Value(tr, "D_PAN", 0); notify("Pan Mitte")
    elseif e == 3 then r.SetMediaTrackInfo_Value(tr, "D_WIDTH", 1); notify("Breite 100%") end
    markUndo("OXI: Spur")
  end
end

---------------------------------------------------------------------------------------------------
-- on-device menu (PAGE): one option per row, choices in columns
---------------------------------------------------------------------------------------------------
local MENU = {
  { key = "markerRow", name = "Marker", ch = { { "0", "aus" }, { "1", "an" } } },
  { key = "folders", name = "Ordner", ch = { { "0", "aus" }, { "1", "zeigen" } } },
  { key = "empty", name = "Leere Sp.", ch = { { "0", "aus" }, { "1", "zeigen" } } },
  { key = "receives", name = "Receives", ch = { { "show", "zeigen" }, { "hide", "aus" }, { "page", "eig.Seite" } } },
  { key = "visible", name = "Spuren", ch = { { "all", "alle" }, { "tcp", "wie TCP" }, { "mcp", "wie MCP" } } },
  { key = "layout", name = "Items", ch = { { "10s", "10+State" }, { "12", "12" }, { "14", "14" }, { "16", "16" } } },
  { key = "sendPush", name = "Send-Push", ch = { { "mute", "Mute" }, { "mode", "Pre/Post" } } },
  { key = "preFx", name = "Pre-FX", ch = { { "0", "aus" }, { "1", "mit" } } },
}
local MENU2 = {
  { key = "mainSend", name = "Sh+Spur", ch = { { "0", "aus" }, { "1", "MasterSnd" } } },
  { key = "tripleVol", name = "3x Spur", ch = { { "0", "aus" }, { "1", "0dB/-inf" } } },
  { key = "flip", name = "Grid", ch = { { "0", "normal" }, { "1", "umgedreht" } } },
  { key = "select", name = "Auswahl", ch = { { "full", "+Ansicht" }, { "sel", "Reaper" }, { "oxi", "nur OXI" } } },
  { key = "follow", name = "Folgen", ch = { { "0", "aus" }, { "1", "an" } } },
  { key = "turnShow", name = "Drehen", ch = { { "big", "groß" }, { "line", "unten" }, { "both", "beides" }, { "off", "aus" } } },
  { key = "marquee", name = "Laufschr.", ch = { { "0", "aus" }, { "1", "an" } } },
  { key = "cells", name = "Felder", ch = { { "auto", "auto" }, { "regions", "Regionen" }, { "items", "Items" } } },
}
local function curMenu() return view.menuPage == 2 and MENU2 or MENU end
local function menuChoice(m)
  for k, c in ipairs(m.ch) do if cfg[m.key] == c[1] then return k, c[2] end end
  return 1, m.ch[1][2]
end

---------------------------------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------------------------------
local function drawGrid()
  local want = {}
  local function set(row, col, c)
    if row >= 0 and row < 8 and col >= 0 and col < 16 then want[row * 16 + col] = c end
  end
  if view.menu then
    for row, m in ipairs(curMenu()) do
      local cur = menuChoice(m)
      for k = 1, #m.ch do set(row - 1, k - 1, k == cur and { 0, 255, 255 } or { 40, 40, 60 }) end
    end
    flushGrid(want); return
  end
  local sel = selTrack()
  local nCols = itemCols()
  cellCache = {}
  if cfg.markerRow == "1" then
    -- v8.12.1: loop = the marker/region the loop sits on (full; with repeat on it blinks like mute in the
    -- E16 tempo), play position = brighter, others as before (0.4) so their colours stay visible
    local ms = markers()
    local pos = r.GetPlayState() & 1 == 1 and r.GetPlayPosition() or r.GetCursorPosition()
    local ls, le = r.GetSet_LoopTimeRange2(0, false, true, 0, 0, false)
    local rep = r.GetSetRepeat(-1) == 1
    local ph = math.floor(r.time_precise() / 0.4) % 2 == 0
    for c = 0, nCols - 1 do
      local k = view.colOff + c + 1
      local m = ms[k]
      if m then
        local s0 = m.pos
        local e0 = m.rgn and m.rend or (ms[k + 1] and ms[k + 1].pos or m.pos + 4)
        local base = rgbOf(m.col) or (m.rgn and { 200, 160, 40 } or { 255, 60, 60 })   -- regions without colour: subtle yellow
        local looped = le > ls and math.abs(ls - s0) < 0.01 and math.abs(le - e0) < 0.01
        local here = pos >= s0 - 1e-6 and pos < e0
        local c2
        -- v8.12.3: every marker/region in its true colour (full level: dimming shifts the hue on the OXI's
        -- 4 steps per channel); loop + cycle = dips darker in the E16 tempo, loop without cycle = short dip every 1.6 s
        local dip = math.floor(r.time_precise() / 0.2) % 8 == 0
        if looped and rep then c2 = ph and base or scale(base, 0.06)
        elseif looped then c2 = dip and scale(base, 0.06) or base
        else c2 = base end
        set(0, c, c2)
      end
    end
  end
  for k = 0, rowsForTracks() - 1 do
    local row = firstTrackRow() + k
    local tr = tracks[view.off + k + 1]
    if tr then
      local tcol = rgbOf(r.GetTrackColor(tr)) or DEF_RGB
      local isSel = tr == sel or (not oxiOnly() and r.IsTrackSelected(tr))
      local cl = cellsOf(tr)
      local any = false
      for _, f in ipairs(cl) do if f then any = true end end
      if view.colOff >= #cl or not any then set(row, 0, scale(tcol, isSel and 0.7 or 0.25)) end
      for c = 0, nCols - 1 do
        local fld = cellAt(tr, c)
        if fld then
          local it = fld.items[1]
          local col = (c == 0 and not regionMode()) and tcol or (rgbOf(r.GetDisplayedMediaItemColor(it)) or tcol)
          local f = isSel and 0.6 or 0.35
          local allMuted = true
          for _, x in ipairs(fld.items) do
            if (oxiOnly() and x == lastItem) or (not oxiOnly() and r.IsMediaItemSelected(x)) then f = 1 end
            if r.GetMediaItemInfo_Value(x, "B_MUTE") ~= 1 then allMuted = false end
          end
          if allMuted then col, f = { 255, 255, 255 }, 0.05 end
          set(row, c, scale(col, f))
        end
      end
      if cfg.statusCol == "1" and cfg.layout ~= "10s" then
        local st
        if r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then st = { 255, 30, 30 }
        elseif r.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0 then st = { 255, 230, 0 }
        elseif r.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 then st = { 60, 60, 60 }
        else st = scale(tcol, isSel and 1 or 0.35) end
        set(row, 15, st)
      end
      if cfg.layout == "10s" then
        local sl = stateList()
        for k2 = 1, math.min(5, #sl) do
          local st = sl[k2]
          set(row, 10 + k2, scale(STATE_RGB[st], (isSel and view.state == st) and 1 or 0.12))
        end
      end
    end
  end
  flushGrid(want)
end

local ENC_LABELS = {
  { "Gain", "F-In", "F-Out", "Spur" }, nil, nil, nil, nil,
  { "Pos", "Pitch", "Rate", "Länge" }, { "Vol", "Pan", "Breite", "Spur" },
}
local LONG = { { "Gain", "Fade-in", "Fade-out", "Spur" }, nil, nil, nil, nil, { "Position", "Pitch", "Rate", "Länge" },
  { "Volume", "Pan", "Breite", "Spur" } }
local UNIT = { { " dB", "", "", "" }, nil, nil, nil, nil, { " s", " HT", "x", " s" }, { " dB", "", "", "" } }
local function encValues()
  local tr, s = selTrack(), sendCtx() and 2 or view.state
  local L, V = {}, {}
  if s >= 2 and s <= 5 then
    for e = 1, 4 do
      local i = sendIndex(e)
      if tr and i < r.GetTrackNumSends(tr, 0) then
        local dest = r.GetTrackSendInfo_Value(tr, 0, i, "P_DESTTRACK")
        local n = dest and trName(dest) or ("S" .. (i + 1))
        L[e] = n
        local muted = r.GetTrackSendInfo_Value(tr, 0, i, "B_MUTE") == 1
        local mode = MODES[math.floor(r.GetTrackSendInfo_Value(tr, 0, i, "I_SENDMODE"))] or "?"
        V[e] = muted and "MUTE" or fmtDb(r.GetTrackSendInfo_Value(tr, 0, i, "D_VOL"))
        L[e] = n; V[e] = V[e] .. (mode ~= "Post" and "*" or "")
      else L[e], V[e] = "S" .. (i + 1), "-" end
    end
    return L, V
  end
  L = ENC_LABELS[s]
  local its = targetItems()
  local it = its[1]
  if s == 1 then
    V[1] = it and fmtDb(r.GetMediaItemInfo_Value(it, "D_VOL")) or "-"
    V[2] = it and string.format("%dms", math.floor(r.GetMediaItemInfo_Value(it, "D_FADEINLEN") * 1000 + 0.5)) or "-"
    V[3] = it and string.format("%dms", math.floor(r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") * 1000 + 0.5)) or "-"
    V[4] = string.format("%d/%d", math.min(#tracks, view.off + 1), #tracks)
  elseif s == 6 then
    local tk = it and r.GetActiveTake(it)
    V[1] = it and string.format("%.2f", r.GetMediaItemInfo_Value(it, "D_POSITION")) or "-"
    V[2] = tk and string.format("%+.1f", r.GetMediaItemTakeInfo_Value(tk, "D_PITCH")) or "-"
    V[3] = tk and string.format("%.2f", r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")) or "-"
    V[4] = it and string.format("%.2f", r.GetMediaItemInfo_Value(it, "D_LENGTH")) or "-"
  else
    V[1] = tr and fmtDb(r.GetMediaTrackInfo_Value(tr, "D_VOL")) or "-"
    V[2] = tr and string.format("%+d", math.floor(r.GetMediaTrackInfo_Value(tr, "D_PAN") * 100 + 0.5)) or "-"
    V[3] = tr and string.format("%d%%", math.floor(r.GetMediaTrackInfo_Value(tr, "D_WIDTH") * 100 + 0.5)) or "-"
    V[4] = string.format("%d/%d", math.min(#tracks, view.off + 1), #tracks)
  end
  return L, V
end

local function drawDisplay()
  clr()
  if view.menu then
    if view.menuPage == 2 then text(1, 56, "Menü 2/2  < >", false, 21) else text(97, 56, "1/2>", false, 5) end
    for row, m in ipairs(curMenu()) do             -- one line per grid row; the last touched one inverted
      local _, v = menuChoice(m)
      local y = (row - 1) * 8
      if row == view.menuRow then bar(y) end
      text(1, y, string.format("%-10s %s", m.name, v), row == view.menuRow, 21)
    end
    flushDisplay(); return
  end
  bar(0)
  local head = "PUZZLE " .. STATE_NAMES[view.state]
  if view.mode ~= "puzzle" then
    head = string.format("%s  %d-%d", PAGE_NAMES[view.mode], view.sgroup * 4 + 1, view.sgroup * 4 + 4)
  end
  if cfg.receives == "page" then head = head .. (view.page == 2 and " RCV" or "") end
  text(1, 0, head, true, 21)
  local tr = selTrack()
  if tr then
    local num = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
    local s1 = string.format("%d %s", num, trName(tr))
    text(0, 9, s1, false, 21, marqueeOff(s1, 21))
  else text(0, 9, "keine Spur", false, 21) end
  if view.mode ~= "puzzle" then
    if tr then
      local ms = r.GetMediaTrackInfo_Value(tr, "B_MAINSEND") == 1
      text(0, 18, string.format("Vol %s  Master %s", fmtDb(r.GetMediaTrackInfo_Value(tr, "D_VOL")), ms and "an" or "AUS"), false, 21)
    end
  else
    local it = targetItems()[1]
    local tk = it and r.GetActiveTake(it)
    local iname = tk and select(2, r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)) or (it and "Item" or "kein Item")
    text(0, 18, iname, false, 21, marqueeOff(iname, 21))
  end
  local L, V = encValues()
  for e = 1, 4 do
    text((e - 1) * 32, 34, L[e] or "", false, 5)
    text((e - 1) * 32, 43, V[e] or "", false, 5)
  end
  for x = 0, 127 do px(x, 31, true) end
  local now = r.time_precise()
  local vf = view.vf
  if vf and now - vf.t < 1.5 and cfg.turnShow ~= "off" and not (note ~= "" and noteT > vf.t) then
    local s = sendCtx() and 2 or view.state
    local lab = (LONG[s] and LONG[s][vf.e]) or L[vf.e] or ""
    local val = (V[vf.e] or "") .. ((UNIT[s] and V[vf.e] ~= "-" and not (V[vf.e] or ""):find("ms")) and UNIT[s][vf.e] or "")
    if s == 2 then val = V[vf.e] or "" end
    if cfg.turnShow == "big" or cfg.turnShow == "both" then
      for y = 0, 30 do for x = 0, 127 do FB[y * 128 + x] = false end end
      bar(0); text(1, 0, lab, true, 21)
      bigText(0, 11, val, 10)
    end
    if cfg.turnShow == "line" or cfg.turnShow == "both" then
      bar(55); text(1, 55, lab .. " " .. val, true, 21)
    end
  elseif note ~= "" and now - noteT < 1.8 then
    bar(55); text(1, 55, note, true, 21)
  end
  flushDisplay()
end

local function drawLeds(force)
  led(LED.SHIFT, shift, force)
  led(LED.PAGE, view.menu, force)
  led(LED.TRACK, true, force)
  local ps = r.GetPlayState()
  led(LED.PLAY, ps & 1 == 1, force)
  led(LED.REC, ps & 4 == 4, force)
  led(LED.STOP, ps == 0, force)
  led(LED.UP, view.off > 0, force)
  led(LED.DOWN, view.off < #tracks - rowsForTracks(), force)
  led(LED.LEFT, view.colOff > 0, force)
  led(LED.RIGHT, true, force)
  local now = r.time_precise()
  -- v8.9: mute blinks in step with the E16 (0.4 s on / 0.4 s off, same clock), solo = 2nd LED,
  -- rec arm = two short flicks every 1.6 s on top of whatever the LED shows (inverts it briefly)
  local mutePh = math.floor(now / 0.4) % 2 == 0
  local t = now % 1.6
  local flick = (t < 0.1) or (t >= 0.22 and t < 0.32)
  for row = 0, 7 do
    local tr = (not view.menu) and trackOfRow(row)
    local on, second = tr ~= nil and tr ~= false, false
    if tr and cfg.seqState == "1" then
      if r.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 then on = mutePh end
      second = r.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0 and mutePh   -- solo blinks in the same tempo
      if r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 and flick then on = not on end
    end
    led(LED.SEQ1 + row, on, force)
    led(LED.SEQ1 + 8 + row, second, force)
  end
end

---------------------------------------------------------------------------------------------------
-- input
---------------------------------------------------------------------------------------------------
local lastPad, lastPadT = -1, 0
local function selectTrack(tr)
  view.focus = tr
  if oxiOnly() then return end                   -- option: the OXI keeps its own track, Reaper stays as it is
  r.SetOnlyTrackSelected(tr)
  if cfg.select == "full" then
    r.SetMixerScroll(tr)
    r.Main_OnCommand(40913, 0)                    -- scroll the arrange view to the selected track
  end
end
local function onPad(p)
  view.vf = nil
  local row, col = p // 16, p % 16
  if cfg.flip ~= "1" then row = 7 - row end
  local now = r.time_precise()
  local double = (p == lastPad and now - lastPadT < 0.35)
  lastPad, lastPadT = p, double and 0 or now
  if view.menu then
    local m = curMenu()[row + 1]
    if m and m.ch[col + 1] then
      setCfg(m.key, m.ch[col + 1][1]); view.menuRow = row + 1
      notify(m.name .. ": " .. m.ch[col + 1][2])
      if m.key == "receives" then view.page = 1 end
      buildTracks(); clampView()
    end
    return
  end
  if cfg.markerRow == "1" and row == 0 then
    local m = markers()[view.colOff + col + 1]
    if not m then return end
    if double then
      local e = m.rgn and m.rend or nil
      if not e then
        local nx = markers()[view.colOff + col + 2]; e = nx and nx.pos or m.pos + 4
      end
      r.GetSet_LoopTimeRange2(0, true, true, m.pos, e, false)
      notify("Loop " .. (m.name ~= "" and m.name or m.idx))
    else
      r.SetEditCurPos(m.pos, true, true)
      notify((m.rgn and "Region " or "Marker ") .. (m.name ~= "" and m.name or m.idx))
    end
    return
  end
  local tr = trackAtRow(row)
  if not tr then return end
  if cfg.layout == "10s" and col >= 10 then
    local st = stateList()[col - 10]
    selectTrack(tr)
    if st then view.state = st; notify(STATE_NAMES[st]) end
    return
  end
  if cfg.statusCol == "1" and cfg.layout ~= "10s" and col == 15 then   -- status: push = mute, shift = solo, 2x = rec arm
    local key, name = "B_MUTE", "Mute"
    if shift then key, name = "I_SOLO", "Solo" elseif double then key, name = "I_RECARM", "Rec" end
    if double then        -- the 1st press muted: undo it
      r.SetMediaTrackInfo_Value(tr, "B_MUTE", 1 - r.GetMediaTrackInfo_Value(tr, "B_MUTE"))
    end
    local v = r.GetMediaTrackInfo_Value(tr, key)
    r.SetMediaTrackInfo_Value(tr, key, v > 0 and 0 or (key == "I_SOLO" and 2 or 1))
    r.Undo_OnStateChange("OXI: " .. name); notify(name .. (v > 0 and " aus" or " an"))
    return
  end
  if col >= itemCols() then return end
  cellCache = {}
  local fld = cellAt(tr, col)
  if shift then
    if fld then                                  -- all items of the field: any playing -> all muted, else all on
      local anyOn = false
      for _, x in ipairs(fld.items) do if r.GetMediaItemInfo_Value(x, "B_MUTE") ~= 1 then anyOn = true end end
      for _, x in ipairs(fld.items) do r.SetMediaItemInfo_Value(x, "B_MUTE", anyOn and 1 or 0) end
      r.UpdateArrange(); r.Undo_OnStateChange("OXI: Items stumm")
      notify((#fld.items > 1 and (#fld.items .. " Items ") or "Item ") .. (anyOn and "stumm" or "an"))
    end
    return
  end
  selectTrack(tr)
  if not fld then notify(trName(tr)); return end
  lastItem, lastCell = fld.items[1], fld.items
  if double then
    r.GetSet_LoopTimeRange2(0, true, true, fld.pos, fld.pos + fld.len, false)
    r.SetEditCurPos(fld.pos, true, true)
    notify(fld.rgn and ("Loop = Region " .. (fld.rgn.name ~= "" and fld.rgn.name or fld.rgn.idx)) or "Loop = Item")
  else
    if not oxiOnly() then
      r.Main_OnCommand(40289, 0)                     -- unselect all items
      for _, x in ipairs(fld.items) do r.SetMediaItemSelected(x, true) end
    end
    r.UpdateArrange()
    if #fld.items > 1 then notify(#fld.items .. " Items") end
  end
end

local encDown, encCount, encT, encLong = {}, {}, {}, {}
local seqT, seqN, seqHeld = {}, {}, {}
local function onTrackButton(row)               -- the 8 sequencer buttons = track select per grid row
  local tr = trackOfRow(row)
  if not tr then return end
  if shift and cfg.mainSend == "1" then
    local on = r.GetMediaTrackInfo_Value(tr, "B_MAINSEND") == 1
    r.SetMediaTrackInfo_Value(tr, "B_MAINSEND", on and 0 or 1)
    r.Undo_OnStateChange("OXI: Master-Send"); notify("Master-Send " .. (on and "aus" or "an"))
    return
  end
  local now = r.time_precise()
  if seqT[row] and now - seqT[row] < 0.4 then seqN[row] = (seqN[row] or 0) + 1 else seqN[row] = 1 end
  seqT[row] = now
  seqHeld[row] = { t = now, tr = tr }
  selectTrack(tr)
  if seqN[row] == 2 and cfg.seqMute == "1" then
    local m = r.GetMediaTrackInfo_Value(tr, "B_MUTE")
    r.SetMediaTrackInfo_Value(tr, "B_MUTE", m == 1 and 0 or 1)
    r.Undo_OnStateChange("OXI: Spur stumm"); notify(m == 1 and "Mute aus" or "MUTE")
    return
  end
  if seqN[row] == 3 and cfg.tripleVol == "1" then
    if cfg.seqMute == "1" then                   -- the 2nd press muted: undo that
      local m = r.GetMediaTrackInfo_Value(tr, "B_MUTE")
      r.SetMediaTrackInfo_Value(tr, "B_MUTE", m == 1 and 0 or 1)
    end
    local v = r.GetMediaTrackInfo_Value(tr, "D_VOL")
    r.SetMediaTrackInfo_Value(tr, "D_VOL", v > 0 and 0 or 1)
    r.Undo_OnStateChange("OXI: Spur 0 dB/-inf"); notify(v > 0 and "Spur -inf" or "Spur 0 dB")
    seqN[row] = 0
  else notify(trName(tr)) end
end
local function seqTick(now)                      -- hold a track button 0.5 s = solo
  for row, h in pairs(seqHeld) do
    if now - h.t > 0.5 then
      seqHeld[row] = nil
      if cfg.seqSolo == "1" and r.ValidatePtr(h.tr, "MediaTrack*") then
        local so = r.GetMediaTrackInfo_Value(h.tr, "I_SOLO")
        r.SetMediaTrackInfo_Value(h.tr, "I_SOLO", so > 0 and 0 or 2)
        r.Undo_OnStateChange("OXI: Solo"); notify(so > 0 and "Solo aus" or "SOLO")
        seqN[row] = 0
      end
    end
  end
end
local function onButton(n, down)
  if n == B.SHIFT then shift = down; return end
  if down then view.vf = nil end
  if n >= B.SEQ1 and n <= B.SEQ1 + 7 then
    if down then onTrackButton(n - B.SEQ1) else seqHeld[n - B.SEQ1] = nil end
    return
  end
  if down and view.menu and (n == B.LEFT or n == B.RIGHT) then
    view.menuPage = 3 - view.menuPage; view.menuRow = 0; return
  end
  local e = ENC_BTN[n]
  if e then
    local now = r.time_precise()
    if down then encDown[e], encLong[e] = now, false
    else
      if encDown[e] and not encLong[e] then encCount[e] = (encCount[e] or 0) + 1; encT[e] = now end
      encDown[e] = nil
    end
    return
  end
  if not down then return end
  local rows = rowsForTracks()
  if n == B.UP then view.off = view.off - (shift and rows or 1)
  elseif n == B.DOWN then view.off = view.off + (shift and rows or 1)
  elseif n == B.LEFT then view.colOff = view.colOff - (shift and itemCols() or 1)
  elseif n == B.RIGHT then view.colOff = view.colOff + (shift and itemCols() or 1)
  elseif n == B.TRACK then
    local sl = stateList()
    local k = 1
    for i, s in ipairs(sl) do if s == view.state then k = i end end
    k = (k + (shift and -2 or 0)) % #sl + 1
    view.state = sl[k]; notify(STATE_NAMES[view.state])
  elseif n == B.PAGE then view.menu = not view.menu
  elseif n == B.BACK then
    if cfg.receives == "page" then view.page = 3 - view.page; buildTracks(); view.off = 0
      notify(view.page == 2 and "Spuren mit Receives" or "Spuren")
    end
  elseif n == B.PLAY then r.Main_OnCommand(40073, 0)
  elseif n == B.STOP then r.Main_OnCommand(1016, 0)
  elseif n == B.REC then r.Main_OnCommand(1013, 0)
  elseif n == B.UNDO then
    if shift then r.Undo_DoRedo2(0); notify("Redo") else r.Undo_DoUndo2(0); notify("Undo") end
  end
  clampView()
end
local function pollEncPush()
  local now = r.time_precise()
  for e = 1, 4 do
    if encDown[e] and not encLong[e] and now - encDown[e] > 0.5 then
      encLong[e] = true; encCount[e] = 0; encPush(e, 3)
    elseif not encDown[e] and (encCount[e] or 0) > 0 and now - encT[e] > 0.28 then
      local c = encCount[e]; encCount[e] = 0
      encPush(e, c >= 2 and 2 or 1)
    end
  end
end

local lastSeq = 0
local function readInput()
  local idx, evs = 0, {}
  while true do
    local seq, buf, _, dev = r.MIDI_GetRecentInputEvent(idx)
    if seq == 0 or seq <= lastSeq then break end
    if dev == oxiIn then evs[#evs + 1] = buf end
    idx = idx + 1
    if idx > 500 then break end
  end
  local top = r.MIDI_GetRecentInputEvent(0)
  if top and top > lastSeq then lastSeq = top end
  for k = #evs, 1, -1 do
    local m = evs[k]
    if m == SX_ACK then flushGrid({}, true); sentPad = {}; sentLed = {}; lastDisp = ""
    elseif #m >= 3 then
      local st, a, b = m:byte(1), m:byte(2), m:byte(3)
      if st == PAD_ON and b > 0 then onPad(a)
      elseif st == BTN_ON or st == BTN_OFF then onButton(a, st == BTN_ON and b > 0)
      elseif st == KNOB_CC and a <= 3 then
        local d = b < 64 and b or b - 128
        if d ~= 0 then turn(a + 1, d) end
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- main loop
---------------------------------------------------------------------------------------------------
local lastPortTry, lastBuild = 0, 0
local startT
local function connect()
  oxiIn = findPort(r.GetNumMIDIInputs, r.GetMIDIInputName)
  oxiOut = findPort(r.GetNumMIDIOutputs, r.GetMIDIOutputName)
  if oxiOut then send(SX_ENTER); sentPad, sentLed, lastDisp = {}, {}, "" end
end
local token, retired = tostring(math.random()) .. tostring(os.time()), false
local lastReaperSel
local function followReaper()                    -- option: a track selected in Reaper scrolls the puzzle to it
  local rs = r.GetSelectedTrack(0, 0)
  if rs == lastReaperSel then return end
  lastReaperSel = rs
  if not rs or cfg.follow ~= "1" then return end
  if oxiOnly() then view.focus = rs end
  for i, t in ipairs(tracks) do
    if t == rs then
      local rows = rowsForTracks()
      if i - 1 < view.off or i - 1 >= view.off + rows then view.off = i - 1; clampView() end
    end
  end
end
local function loop()
  seqTick(r.time_precise())
  if r.GetExtState(EXT, "running") ~= token then retired = true; return end   -- a newer instance took over
  local now = r.time_precise()
  if (not oxiIn or not oxiOut) and now - lastPortTry > 2 then lastPortTry = now; connect() end
  local rev = r.GetExtState(EXT, "rev")
  if rev ~= cfgRev then cfgRev = rev; loadCfg(); buildTracks(); clampView() end
  if oxiIn then readInput() end
  pollEncPush()
  if now - lastBuild > 0.25 then
    lastBuild = now
    local dg = r.GetExtState(EXT, "diag") == "1"
    if dg then r.SetExtState(EXT, "diag", "", false) end
    buildTracks(dg); clampView()
  end
  followReaper()
  if undoPending and now - undoT > 0.8 then r.Undo_OnStateChange(undoPending); undoPending = nil end
  if oxiOut then
    drawGrid(); drawDisplay(); drawLeds(now - startT < 1.5)
  end
  r.defer(loop)
end

local function shutdown()
  if not oxiOut or retired then return end
  local off = {}
  flushGrid(off, true)
  clr(); text(22, 28, "seren.a OXI aus"); send(packDisplay())
  for _, id in pairs(LED) do send(HDR .. string.char(2, id // 16, id % 16, 0, 0) .. "\247") end
  for row = 0, 15 do local id = LED.SEQ1 + row; send(HDR .. string.char(2, id // 16, id % 16, 0, 0) .. "\247") end
  send(SX_EXIT)
  if cfg.handover == "1" then send(SX_ENTER) end         -- device acknowledges -> DrivenByMoss repaints
end

local function main()
  loadCfg()
  cfgRev = r.GetExtState(EXT, "rev")
  local s = tonumber(cfg.states:match("%d+")) or 1
  view.state = s
  view.mode = pageList()[1]
  startT = r.time_precise()
  connect()
  if not oxiIn or not oxiOut then
    r.ShowConsoleMsg("seren.a OXI Puzzle " .. VERSION .. ": OXI nicht gefunden (Name enthält '" .. cfg.port ..
      "'). In Reaper Einstellungen > MIDI-Geräte Ein- und Ausgang aktivieren. Ich versuche es weiter.\n")
  end
  lastSeq = r.MIDI_GetRecentInputEvent(0)
  buildTracks()
  lastReaperSel = r.GetSelectedTrack(0, 0)
  view.focus = lastReaperSel
  local sel = selTrack()                         -- start with the selected track in the top row
  for i, t in ipairs(tracks) do if t == sel then view.off = i - 1 end end
  clampView()
  r.SetExtState(EXT, "running", token, false)
  r.atexit(function()
    if r.GetExtState(EXT, "running") == token then r.SetExtState(EXT, "running", "", false) end
    shutdown()
  end)
  loop()
end
main()
