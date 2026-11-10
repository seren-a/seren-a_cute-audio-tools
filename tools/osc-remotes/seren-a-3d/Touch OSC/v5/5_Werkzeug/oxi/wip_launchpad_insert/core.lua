-- seren.a OXI Puzzle – Reaper script for the OXI One MkII (remote mode) and the Launchpad Pro Mk3 (programmer mode)
-- Grid: 8 tracks x up to 16 items ("Puzzle"), 4 encoders with switchable states, on-device menu (PAGE),
-- settings window: Reaper_OXI_Einstellungen.lua (same ExtState). Protocol after DrivenByMoss (OXI One).
local r = reaper
local VERSION = "v8.4"
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

--@@FONT@@

---------------------------------------------------------------------------------------------------
-- settings (ExtState, shared with the settings window)
---------------------------------------------------------------------------------------------------
local DEFAULTS = {
  port = "oxi",              -- part of the MIDI device name (in + out)
  layout = "16",             -- "10s" = 10 items + 5 state pads, or "12", "14", "16" items
  markerRow = "0",           -- top row = first marker lane
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
  turnShow = "big",          -- value while turning: big (lines 1-3) / line (bottom) / both / off
  marquee = "1",             -- long track / item names scroll
  select = "full",           -- full = select in Reaper + scroll mixer/arrange, sel = only select, oxi = only on the OXI
  follow = "1",              -- a track selected in Reaper scrolls the puzzle to it
  useOxi = "1",              -- take the OXI (0 = leave it to DrivenByMoss)
  useLp = "0",               -- take the Launchpad Pro Mk3 (0 = leave it to DrivenByMoss)
  lpPort = "LPProMK3 MIDI",  -- part of the Launchpad's MIDI name (in + out)
  lpOrient = "quer",         -- quer = tracks in rows like the OXI, laengs = tracks in columns
  lpShift = "shift",         -- Launchpad Shift: shift (like OXI) / page / menu / action
  lpShiftAct = "",           -- Reaper action ID or built-in function for lpShift = action
  pages = "puzzle,insert",   -- pages, ARRANGER (OXI) / Session (Launchpad) switches
  fxColor = "name",          -- insert colours: name = same plugin same colour, track = track colour
  fxOpen = "1",              -- insert page: selecting an FX opens its window (and closes the one opened before)
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
local lpIn, lpOut
local function findPort(count, getName, name)
  local want = (name or cfg.port):lower()
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
local view = { off = 0, colOff = 0, fxOff = 0, pbank = 0, page = 1, state = 1, menu = false, menuRow = 0, mode = "puzzle", menuPage = 1 }
local PAGE_NAMES = { puzzle = "PUZZLE", insert = "INSERTS" }   -- send pages live in DrivenByMoss (Send 16 / 32) since v8.2
local function pageList()
  local t = {}
  for s in cfg.pages:gmatch("[%a]+") do if PAGE_NAMES[s] then t[#t + 1] = s end end
  if #t == 0 then t = { "puzzle" } end
  return t
end
local tracks = {}
local function hasReceives(tr) return r.GetTrackNumSends(tr, -1) > 0 end
local function buildTracks()
  local list, pinned = {}, {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local ok = true
    local isFolder = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1
    if cfg.visible == "tcp" and r.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 0 then ok = false end
    if cfg.visible == "mcp" and r.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") == 0 then ok = false end
    if cfg.folders == "0" and isFolder then ok = false end
    if cfg.empty == "0" and not isFolder and r.CountTrackMediaItems(tr) == 0 then ok = false end
    local rc = hasReceives(tr)
    if cfg.receives == "hide" and rc then ok = false end
    if cfg.receives == "page" and ((view.page == 1 and rc) or (view.page == 2 and not rc)) then ok = false end
    if ok then
      if cfg.visible == "tcp" and cfg.pinned == "1" and r.GetMediaTrackInfo_Value(tr, "B_TCPPIN") == 1 then
        pinned[#pinned + 1] = tr
      else list[#list + 1] = tr end
    end
  end
  for k = #pinned, 1, -1 do table.insert(list, 1, pinned[k]) end
  tracks = list
end
local function rowsForTracks()
  if view.mode == "insert" then return 8 end
  return cfg.markerRow == "1" and 7 or 8
end
local function firstTrackRow() return (view.mode == "puzzle" and cfg.markerRow == "1") and 1 or 0 end
local function trackOfRow(row)        -- grid row / track button 0-7 -> track on the current page
  local k = row - firstTrackRow()
  if k < 0 or k >= rowsForTracks() then return nil end
  return tracks[view.off + k + 1]
end
local function itemCols() return cfg.layout == "10s" and 10 or (tonumber(cfg.layout) or 16) end
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
local function itemAt(tr, col)            -- col 0-based on the grid
  local idx = view.colOff + col
  if idx < r.CountTrackMediaItems(tr) then return r.GetTrackMediaItem(tr, idx) end
end
local lastItem                            -- item last touched on the grid
local function targetItems()
  local tr, t = selTrack(), {}
  if not tr then return t end
  if not oxiOnly() then
    for i = 0, r.CountTrackMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, i)
      if r.IsMediaItemSelected(it) then t[#t + 1] = it end
    end
  end
  if #t == 0 and lastItem and r.ValidatePtr(lastItem, "MediaItem*") and r.GetMediaItem_Track(lastItem) == tr then
    t[1] = lastItem
  end
  return t
end
local function markers()
  local t, i = {}, 0
  while true do
    local ok, rgn, pos, rend, name, idx, col = r.EnumProjectMarkers3(0, i)
    if ok == 0 then break end
    t[#t + 1] = { rgn = rgn, pos = pos, rend = rend, name = name, idx = idx, col = col }
    i = i + 1
  end
  return t
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
local shift, oxiShift, lpShiftDown = false, false, false
local function sendCtx() return view.mode == "puzzle" and view.state >= 2 and view.state <= 5 end
local function sendIndex(e)
  local s = view.state; if s >= 2 and s <= 5 then return (s - 2) * 4 + e - 1 end
end

-- insert page: selected FX and its parameters (4 per bank)
local function fxSel()
  local f = view.fx
  if f and r.ValidatePtr(f.tr, "MediaTrack*") and f.idx < r.TrackFX_GetCount(f.tr) then return f.tr, f.idx end
  local tr = selTrack()
  if tr and r.TrackFX_GetCount(tr) > 0 then return tr, 0 end
end
local function fxName(tr, i)
  local _, n = r.TrackFX_GetFXName(tr, i, "")
  n = n:gsub("^%u+i?:%s*", ""):gsub("%s*%(.-%)$", "")      -- "VST3: ReaEQ (Cockos)" -> "ReaEQ"
  return n
end
local function paramOf(e)
  local tr, i = fxSel()
  if not tr then return end
  local p = view.pbank * 4 + e - 1
  if p >= r.TrackFX_GetNumParams(tr, i) then return end
  return tr, i, p
end
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
  if view.mode == "insert" then
    local tr, i, p = paramOf(e)
    if not tr then notify("kein Parameter"); return end
    local v = r.TrackFX_GetParamNormalized(tr, i, p) + d * (shift and 0.001 or 0.01)
    r.TrackFX_SetParamNormalized(tr, i, p, math.max(0, math.min(1, v)))
    markUndo("OXI: FX-Parameter"); return
  end
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
local function fxToggleBypass(tr, i)
  local on = r.TrackFX_GetEnabled(tr, i)
  r.TrackFX_SetEnabled(tr, i, not on)
  r.Undo_OnStateChange("OXI: FX Bypass"); notify(fxName(tr, i) .. (on and " Bypass" or " an"))
end
local function fxToggleOffline(tr, i)
  local off = r.TrackFX_GetOffline(tr, i)
  r.TrackFX_SetOffline(tr, i, not off)
  r.Undo_OnStateChange("OXI: FX offline"); notify(fxName(tr, i) .. (off and " online" or " offline"))
end
local function fxToggleWindow(tr, i)
  local open = r.TrackFX_GetOpen(tr, i)
  r.TrackFX_Show(tr, i, open and 2 or 3)        -- 3 = floating window, 2 = close it
end
local function encPush(e, kind)                -- kind: 1 = single, 2 = double, 3 = long
  if view.mode == "insert" then                -- 1 bypass, 2 window, 3 / 4 parameter bank - / +
    local tr, i = fxSel()
    if not tr then return end
    if e == 1 then if kind == 2 then fxToggleOffline(tr, i) else fxToggleBypass(tr, i) end
    elseif e == 2 then fxToggleWindow(tr, i)
    else
      local n = math.max(1, math.ceil(r.TrackFX_GetNumParams(tr, i) / 4))
      view.pbank = (view.pbank + (e == 3 and -1 or 1)) % n
      notify(string.format("Parameter %d-%d", view.pbank * 4 + 1, view.pbank * 4 + 4))
    end
    return
  end
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
  { key = "pages", name = "Seiten", ch = { { "puzzle", "Puzzle" }, { "puzzle,insert", "+Insert" } } },
}
local function curMenu() return view.menuPage == 2 and MENU2 or MENU end
local function menuChoice(m)
  for k, c in ipairs(m.ch) do if cfg[m.key] == c[1] then return k, c[2] end end
  return 1, m.ch[1][2]
end

---------------------------------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------------------------------
local FX_PALETTE = { { 0, 202, 254 }, { 80, 254, 3 }, { 254, 159, 90 }, { 254, 90, 200 }, { 254, 230, 0 },
  { 150, 60, 254 }, { 0, 254, 190 }, { 90, 160, 254 }, { 254, 255, 255 } }
local function nameRgb(n)                              -- same plugin name -> same colour on every track
  local h = 0
  for k = 1, #n do h = (h * 31 + n:byte(k)) % 1000003 end
  return FX_PALETTE[h % #FX_PALETTE + 1]
end
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
    return want
  end
  local sel = selTrack()
  if view.mode == "insert" then
    local ftr, fi = fxSel()
    for k = 0, 7 do
      local tr = tracks[view.off + k + 1]
      if tr then
        local tcol = rgbOf(r.GetTrackColor(tr)) or DEF_RGB
        local isSel = tr == sel or (not oxiOnly() and r.IsTrackSelected(tr))
        local n = r.TrackFX_GetCount(tr)
        if view.fxOff >= n then set(k, 0, scale(tcol, isSel and 0.7 or 0.25)) end
        for c = 0, 15 do
          local i = view.fxOff + c
          if i < n then
            local col = cfg.fxColor == "track" and tcol or nameRgb(fxName(tr, i))
            local f = isSel and 0.6 or 0.35
            if tr == ftr and i == fi then f = 1 end
            if r.TrackFX_GetOffline(tr, i) then col, f = { 255, 40, 40 }, 0.2
            elseif not r.TrackFX_GetEnabled(tr, i) then f = 0.06 end
            set(k, c, scale(col, f))
          end
        end
      end
    end
    return want
  end
  local nCols = itemCols()
  if cfg.markerRow == "1" then
    local ms = markers()
    local cur = select(1, r.GetLastMarkerAndCurRegion(0, r.GetPlayState() & 1 == 1 and r.GetPlayPosition() or r.GetCursorPosition()))
    for c = 0, nCols - 1 do
      local m = ms[view.colOff + c + 1]
      if m then
        local base = rgbOf(m.col) or (m.rgn and { 120, 60, 255 } or { 255, 60, 60 })
        set(0, c, scale(base, (view.colOff + c) == cur and 1 or 0.4))
      end
    end
  end
  for k = 0, rowsForTracks() - 1 do
    local row = firstTrackRow() + k
    local tr = tracks[view.off + k + 1]
    if tr then
      local tcol = rgbOf(r.GetTrackColor(tr)) or DEF_RGB
      local isSel = tr == sel or (not oxiOnly() and r.IsTrackSelected(tr))
      local n = r.CountTrackMediaItems(tr)
      if view.colOff >= n or n == 0 then set(row, 0, scale(tcol, isSel and 0.7 or 0.25)) end
      for c = 0, nCols - 1 do
        local it = itemAt(tr, c)
        if it then
          local col = c == 0 and tcol or (rgbOf(r.GetDisplayedMediaItemColor(it)) or tcol)
          local f = isSel and 0.6 or 0.35
          if (oxiOnly() and it == lastItem) or (not oxiOnly() and r.IsMediaItemSelected(it)) then f = 1 end
          if r.GetMediaItemInfo_Value(it, "B_MUTE") == 1 then col, f = { 255, 255, 255 }, 0.05 end
          set(row, c, scale(col, f))
        end
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
  return want
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
  if view.mode == "insert" then
    for e = 1, 4 do
      local ptr, i, p = paramOf(e)
      if ptr then
        local _, pn = r.TrackFX_GetParamName(ptr, i, p, "")
        local _, pv = r.TrackFX_GetFormattedParamValue(ptr, i, p, "")
        L[e], V[e] = pn, pv
      else L[e], V[e] = "P" .. (view.pbank * 4 + e), "-" end
    end
    return L, V
  end
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
  if view.mode == "insert" then
    head = string.format("INSERTS  P%d-%d", view.pbank * 4 + 1, view.pbank * 4 + 4)
  end
  if cfg.receives == "page" then head = head .. (view.page == 2 and " RCV" or "") end
  text(1, 0, head, true, 21)
  local tr = selTrack()
  if tr then
    local num = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
    local s1 = string.format("%d %s", num, trName(tr))
    text(0, 9, s1, false, 21, marqueeOff(s1, 21))
  else text(0, 9, "keine Spur", false, 21) end
  if view.mode == "insert" then
    local ftr, fi = fxSel()
    local fn = ftr and string.format("%d %s%s", fi + 1, fxName(ftr, fi),
      r.TrackFX_GetOffline(ftr, fi) and " OFF" or (r.TrackFX_GetEnabled(ftr, fi) and "" or " BYP")) or "kein FX"
    text(0, 18, fn, false, 21, marqueeOff(fn, 21))
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
    if view.mode == "insert" then s = 0 end
    local lab = (s > 0 and LONG[s] and LONG[s][vf.e]) or L[vf.e] or ""
    local val = (V[vf.e] or "") .. ((s > 0 and UNIT[s] and V[vf.e] ~= "-" and not (V[vf.e] or ""):find("ms")) and UNIT[s][vf.e] or "")
    if s == 2 or s == 0 then val = V[vf.e] or "" end
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
  led(LED.ARRANGER, #pageList() > 1, force)
  local ps = r.GetPlayState()
  led(LED.PLAY, ps & 1 == 1, force)
  led(LED.REC, ps & 4 == 4, force)
  led(LED.STOP, ps == 0, force)
  led(LED.UP, view.off > 0, force)
  led(LED.DOWN, view.off < #tracks - rowsForTracks(), force)
  led(LED.LEFT, view.colOff > 0, force)
  led(LED.RIGHT, true, force)
  for row = 0, 7 do led(LED.SEQ1 + row, trackOfRow(row) ~= nil and not view.menu, force) end
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
local function nextPage(dir)
  local pl = pageList()
  local k = 1
  for i, m in ipairs(pl) do if m == view.mode then k = i end end
  view.mode = pl[(k - 1 + dir) % #pl + 1]
  notify(PAGE_NAMES[view.mode]); clampView()
end
local function onInsertCell(row, col, double)
  local tr = trackAtRow(row)
  if not tr then return end
  local i = view.fxOff + col
  if i >= r.TrackFX_GetCount(tr) then selectTrack(tr); notify(trName(tr)); return end
  if shift then fxToggleBypass(tr, i); return end
  local now = r.time_precise()
  if double then
    local w = view.winT
    if w and w.tr == tr and w.i == i and now - w.t < 0.5 then fxToggleWindow(tr, i) end   -- undo the 1st press
    view.winT = nil
    fxToggleOffline(tr, i); return
  end
  local ftr, fi = fxSel()
  local same = view.fx and ftr == tr and fi == i
  selectTrack(tr)
  view.fx = { tr = tr, idx = i }
  if same then fxToggleWindow(tr, i); view.winT = { tr = tr, i = i, t = now }
  elseif cfg.fxOpen == "1" then
    local o = view.opened
    if o and r.ValidatePtr(o.tr, "MediaTrack*") and o.i < r.TrackFX_GetCount(o.tr) and r.TrackFX_GetOpen(o.tr, o.i) then
      r.TrackFX_Show(o.tr, o.i, 2)
    end
    if not r.TrackFX_GetOpen(tr, i) then r.TrackFX_Show(tr, i, 3); view.winT = { tr = tr, i = i, t = now } end
    view.opened = { tr = tr, i = i }
  end
  view.pbank = same and view.pbank or 0
  notify(fxName(tr, i))
end
local function onCell(row, col)                  -- logical grid: row 0 = top, col 0 = left
  view.vf = nil
  local p = row * 16 + col
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
  if view.mode == "insert" then onInsertCell(row, col, double); return end
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
  if col >= itemCols() then return end
  local it = itemAt(tr, col)
  if shift then
    if it then
      local m = r.GetMediaItemInfo_Value(it, "B_MUTE") == 1
      r.SetMediaItemInfo_Value(it, "B_MUTE", m and 0 or 1)
      r.UpdateArrange(); r.Undo_OnStateChange("OXI: Item stumm")
      notify(m and "Item an" or "Item stumm")
    end
    return
  end
  selectTrack(tr)
  if not it then notify(trName(tr)); return end
  lastItem = it
  if double then
    local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
    r.GetSet_LoopTimeRange2(0, true, true, pos, pos + len, false)
    r.SetEditCurPos(pos, true, true)
    notify("Loop = Item")
  else
    if not oxiOnly() then
      r.Main_OnCommand(40289, 0)                     -- unselect all items
      r.SetMediaItemSelected(it, true)
    end
    r.UpdateArrange()
  end
end

local function onPad(p)                          -- raw OXI pad: y 0 = bottom row
  local row, col = p // 16, p % 16
  if cfg.flip ~= "1" then row = 7 - row end
  onCell(row, col)
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
  if n == B.SHIFT then oxiShift = down; shift = oxiShift or lpShiftDown; return end
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
  elseif (n == B.LEFT or n == B.RIGHT) and view.mode == "insert" then
    view.fxOff = math.max(0, view.fxOff + (n == B.LEFT and -1 or 1) * (shift and 8 or 1))
  elseif n == B.LEFT then view.colOff = view.colOff - (shift and itemCols() or 1)
  elseif n == B.RIGHT then view.colOff = view.colOff + (shift and itemCols() or 1)
  elseif n == B.ARRANGER then nextPage(shift and -1 or 1)
  elseif n == B.TRACK and view.mode == "insert" then
    local tr, i = fxSel()
    if tr then
      local nb = math.max(1, math.ceil(r.TrackFX_GetNumParams(tr, i) / 4))
      view.pbank = (view.pbank + (shift and -1 or 1)) % nb
      notify(string.format("Parameter %d-%d", view.pbank * 4 + 1, view.pbank * 4 + 4))
    end
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

---------------------------------------------------------------------------------------------------
-- Launchpad Pro Mk3 (programmer mode): 8 x 8 pads = notes 11-88 (row 1 = bottom), buttons = CC
---------------------------------------------------------------------------------------------------
local LP_HDR = "\240\0\32\41\2\14"             -- F0 00 20 29 02 0E
local LPB = { SHIFT = 90, LEFT = 91, RIGHT = 92, SESSION = 93, NOTE = 94, PROJECT = 98, UP = 80, DOWN = 70,
  CLEAR = 60, STOP = 30, PLAY = 20, REC = 10 }
local function lpSend(m) if lpOut then r.SendMIDIMessageToHardware(lpOut, m) end end
local lpSent = {}
local function lpLight(want, force)              -- want[led index] = rgb 0-255; one RGB SysEx for all changes
  local t = {}
  local function put(idx, c)
    local r7, g7, b7 = math.floor(c[1] / 2), math.floor(c[2] / 2), math.floor(c[3] / 2)
    local key = r7 .. "," .. g7 .. "," .. b7
    if force or lpSent[idx] ~= key then t[#t + 1] = string.char(3, idx, r7, g7, b7); lpSent[idx] = key end
  end
  for idx, c in pairs(want) do put(idx, c) end
  for idx in pairs(lpSent) do if not want[idx] then put(idx, { 0, 0, 0 }) end end
  if #t > 0 then lpSend(LP_HDR .. "\3" .. table.concat(t) .. "\247") end
end
local function lpLaengs() return cfg.lpOrient == "laengs" and not view.menu end
local function lpTrackBtn(row) return lpLaengs() and (101 + row) or ((8 - row) * 10 + 9) end
local function lpDraw(want, force)
  local L = {}
  for p, c in pairs(want) do
    local row, col = p // 16, p % 16
    local top, x = row, col
    if lpLaengs() then top, x = col, row end
    if top <= 7 and x <= 7 then L[(8 - top) * 10 + x + 1] = c end
  end
  local W, DIM = { 255, 255, 255 }, { 40, 40, 40 }
  local function on(b, c, lit) L[b] = lit and c or scale(c, 0.15) end
  local up, down = view.off > 0, view.off < #tracks - rowsForTracks()
  local left = (view.mode == "insert" and view.fxOff or view.colOff) > 0
  if lpLaengs() then
    on(LPB.LEFT, W, up); on(LPB.RIGHT, W, down); on(LPB.UP, W, left); on(LPB.DOWN, W, true)
  else
    on(LPB.UP, W, up); on(LPB.DOWN, W, down); on(LPB.LEFT, W, left); on(LPB.RIGHT, W, true)
  end
  on(LPB.SESSION, { 0, 202, 254 }, #pageList() > 1 and view.mode ~= "puzzle")
  if #pageList() <= 1 then L[LPB.SESSION] = nil end
  on(LPB.PROJECT, { 254, 90, 200 }, view.menu)
  on(LPB.NOTE, { 150, 60, 254 }, view.page == 2)
  if cfg.receives ~= "page" then L[LPB.NOTE] = nil end
  local ps = r.GetPlayState()
  on(LPB.PLAY, { 80, 254, 3 }, ps & 1 == 1)
  on(LPB.REC, { 254, 40, 40 }, ps & 4 == 4)
  on(LPB.STOP, W, ps == 0)
  L[LPB.CLEAR] = DIM
  local SH = { shift = { 254, 159, 90 }, page = { 0, 202, 254 }, menu = { 254, 90, 200 }, action = { 254, 230, 0 } }
  on(LPB.SHIFT, SH[cfg.lpShift] or W, lpShiftDown)
  local sel = selTrack()
  for row = 0, 7 do
    local tr = (not view.menu) and trackOfRow(row)
    if tr then L[lpTrackBtn(row)] = scale(rgbOf(r.GetTrackColor(tr)) or DEF_RGB, tr == sel and 1 or 0.2) end
  end
  lpLight(L, force)
end
local function lpPad(n)
  local top, x = 8 - n // 10, n % 10 - 1
  if top < 0 or top > 7 or x < 0 or x > 7 then return end
  if lpLaengs() then onCell(x, top) else onCell(top, x) end
end
local function lpButton(cc, down)
  if cc == LPB.SHIFT then
    if cfg.lpShift == "shift" or cfg.lpShift == "" then
      lpShiftDown = down; shift = oxiShift or lpShiftDown; return
    end
    lpShiftDown = down
    if not down then return end
    if cfg.lpShift == "page" then nextPage(1)
    elseif cfg.lpShift == "menu" then view.menu = not view.menu; view.menuRow = 0
    elseif cfg.lpShift == "action" then runSlot(cfg.lpShiftAct) end
    return
  end
  if not down then return end
  for row = 0, 7 do if cc == lpTrackBtn(row) then onTrackButton(row); return end end
  local map
  if lpLaengs() then
    map = { [LPB.LEFT] = B.UP, [LPB.RIGHT] = B.DOWN, [LPB.UP] = B.LEFT, [LPB.DOWN] = B.RIGHT }
  else
    map = { [LPB.UP] = B.UP, [LPB.DOWN] = B.DOWN, [LPB.LEFT] = B.LEFT, [LPB.RIGHT] = B.RIGHT }
  end
  map[LPB.SESSION], map[LPB.NOTE], map[LPB.PROJECT] = B.ARRANGER, B.BACK, B.PAGE
  map[LPB.PLAY], map[LPB.REC], map[LPB.STOP], map[LPB.CLEAR] = B.PLAY, B.REC, B.STOP, B.UNDO
  local b = map[cc]
  if b then onButton(b, true) end
end

local lastSeq = 0
local function readInput()
  local idx, evs = 0, {}
  while true do
    local seq, buf, _, dev = r.MIDI_GetRecentInputEvent(idx)
    if seq == 0 or seq <= lastSeq then break end
    if (oxiIn and dev == oxiIn) or (lpIn and dev == lpIn) then evs[#evs + 1] = { buf, dev } end
    idx = idx + 1
    if idx > 500 then break end
  end
  local top = r.MIDI_GetRecentInputEvent(0)
  if top and top > lastSeq then lastSeq = top end
  for k = #evs, 1, -1 do
    local m, dev = evs[k][1], evs[k][2]
    if lpIn and dev == lpIn then
      if #m >= 3 then
        local st, a, b = m:byte(1), m:byte(2), m:byte(3)
        if st == 0x90 and b > 0 then lpPad(a)
        elseif st == 0xB0 then lpButton(a, b > 0) end
      end
    elseif m == SX_ACK then flushGrid({}, true); sentPad = {}; sentLed = {}; lastDisp = ""
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
local lastPortTry, lastLpTry, lastBuild = 0, 0, 0
local startT, lpStartT = 0, 0
local function connect()
  oxiIn = findPort(r.GetNumMIDIInputs, r.GetMIDIInputName)
  oxiOut = findPort(r.GetNumMIDIOutputs, r.GetMIDIOutputName)
  if oxiOut then send(SX_ENTER); sentPad, sentLed, lastDisp = {}, {}, ""; startT = r.time_precise() end
end
local function connectLp()
  lpIn = findPort(r.GetNumMIDIInputs, r.GetMIDIInputName, cfg.lpPort)
  lpOut = findPort(r.GetNumMIDIOutputs, r.GetMIDIOutputName, cfg.lpPort)
  if lpOut then lpSend(LP_HDR .. "\14\1\247"); lpSent = {}; lpStartT = r.time_precise() end   -- programmer mode
end
local function releaseOxi()                       -- dark, leave remote mode, hand over to DrivenByMoss
  if not oxiOut then return end
  flushGrid({}, true)
  clr(); text(22, 28, "seren.a OXI aus"); send(packDisplay())
  for _, id in pairs(LED) do send(HDR .. string.char(2, id // 16, id % 16, 0, 0) .. "\247") end
  for row = 1, 7 do local id = LED.SEQ1 + row; send(HDR .. string.char(2, id // 16, id % 16, 0, 0) .. "\247") end
  send(SX_EXIT)
  if cfg.handover == "1" then send(SX_ENTER) end         -- device acknowledges -> DrivenByMoss repaints
  oxiIn, oxiOut = nil, nil
end
local function releaseLp()                        -- dark, back to live mode
  if not lpOut then return end
  lpLight({}, false)
  lpSend(LP_HDR .. "\14\0\247")
  lpIn, lpOut = nil, nil
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
  local rev = r.GetExtState(EXT, "rev")
  if rev ~= cfgRev then
    cfgRev = rev; loadCfg(); buildTracks(); clampView()
    local ok = false
    for _, m in ipairs(pageList()) do if m == view.mode then ok = true end end
    if not ok then view.mode = pageList()[1] end
  end
  if cfg.useOxi == "1" then
    if (not oxiIn or not oxiOut) and now - lastPortTry > 2 then lastPortTry = now; connect() end
  elseif oxiOut or oxiIn then releaseOxi() end
  if cfg.useLp == "1" then
    if (not lpIn or not lpOut) and now - lastLpTry > 2 then lastLpTry = now; connectLp() end
  elseif lpOut or lpIn then releaseLp() end
  if oxiIn or lpIn then readInput() end
  pollEncPush()
  if now - lastBuild > 0.25 then lastBuild = now; buildTracks(); clampView() end
  followReaper()
  if undoPending and now - undoT > 0.8 then r.Undo_OnStateChange(undoPending); undoPending = nil end
  if oxiOut or lpOut then
    local want = drawGrid()
    if oxiOut then flushGrid(want); drawDisplay(); drawLeds(now - startT < 1.5) end
    if lpOut then lpDraw(want, now - lpStartT < 1.5) end
  end
  r.defer(loop)
end

local function shutdown()
  if retired then return end
  releaseOxi(); releaseLp()
end

local function main()
  loadCfg()
  cfgRev = r.GetExtState(EXT, "rev")
  local s = tonumber(cfg.states:match("%d+")) or 1
  view.state = s
  view.mode = pageList()[1]
  startT = r.time_precise()
  if cfg.useOxi == "1" then connect() end
  if cfg.useLp == "1" then connectLp() end
  local miss = {}
  if cfg.useOxi == "1" and (not oxiIn or not oxiOut) then miss[#miss + 1] = "OXI ('" .. cfg.port .. "')" end
  if cfg.useLp == "1" and (not lpIn or not lpOut) then miss[#miss + 1] = "Launchpad ('" .. cfg.lpPort .. "')" end
  if #miss > 0 then
    r.ShowConsoleMsg("seren.a OXI Puzzle " .. VERSION .. ": nicht gefunden: " .. table.concat(miss, ", ") ..
      ". In Reaper Einstellungen > MIDI-Geräte Ein- und Ausgang aktivieren. Ich versuche es weiter.\n")
  end
  lastPortTry, lastLpTry = startT, startT
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
