-- ReaScript (Lua): Midi Fighter Twister -> Reaper -> TouchOSC "Twister View".
-- Finds every FX parameter you MIDI-learned to a Twister encoder (Reaper's own MIDI learn),
-- and sends its name, display value, value and the Twister's bank to TouchOSC.
-- Load via Actions > Show action list > New action > Load ReaScript, run once; it keeps running.
-- Reaper > Preferences > MIDI Devices:
--   Midi Fighter Twister: input enabled (as for MIDI learn), output enabled if SEND_TO_MFT
--   TouchOSC Bridge: output enabled; input enabled "for control only" (bank buttons on the phone)
-- NOT TESTED INSIDE REAPER: API calls checked against reaper_plugin_functions.h, logic against a mock.
--
-- Which mapping wins when several FX listen to the same encoder: one on a selected track.
-- Mappings with "selected track only" only count while their track is selected.

local MFT_MATCH   = "Twister"           -- part of the Twister's MIDI port name
local VIEW_MATCH  = "TouchOSC Bridge"   -- part of the TouchOSC Bridge port name
local SYS_CH      = 3                   -- Twister system channel, 0-based (3 = channel 4)
local SEND_TO_MFT = true                -- also send values to the Twister (rings follow Reaper)
local RESYNC      = 5                   -- seconds between full re-sends
local EQ_BANK     = 3                   -- 0-based: bank 4 belongs to Reaper_MultiEQ.lua while it runs
local BANK_NAMES  = { "Bank 1", "Bank 2", "Bank 3", "Bank 4" }   -- names on the Twister View keys (edit freely)

--@@ENC@@
local ENC = { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 }, { 0, 6 }, { 0, 7 }, { 0, 8 }, { 0, 9 }, { 0, 10 }, { 0, 11 }, { 0, 12 }, { 0, 13 }, { 0, 14 }, { 0, 15 }, { 0, 16 }, { 0, 17 }, { 0, 18 }, { 0, 19 }, { 0, 20 }, { 0, 21 }, { 0, 22 }, { 0, 23 }, { 0, 24 }, { 0, 25 }, { 0, 26 }, { 0, 27 }, { 0, 28 }, { 0, 29 }, { 0, 30 }, { 0, 31 }, { 0, 32 }, { 0, 33 }, { 0, 34 }, { 0, 35 }, { 0, 36 }, { 0, 37 }, { 0, 38 }, { 0, 39 }, { 0, 40 }, { 0, 41 }, { 0, 42 }, { 0, 43 }, { 0, 44 }, { 0, 45 }, { 0, 46 }, { 0, 47 }, { 0, 49 }, { 0, 50 }, { 0, 51 }, { 0, 52 }, { 0, 53 }, { 0, 54 }, { 0, 55 }, { 0, 56 }, { 0, 57 }, { 0, 58 }, { 0, 59 }, { 0, 60 }, { 0, 61 }, { 0, 62 }, { 0, 63 }, { 0, 64 } }
--@@END@@

local r = reaper
local floor = math.floor
local NB = floor(#ENC / 16)
local REV = {}
for i, e in ipairs(ENC) do REV[e[1] * 128 + e[2]] = i end

local mftIn, mftOut, viewIn, viewOut
local slots = {}
local sentCC, sentName, sentText, sentTrack = {}, {}, {}, nil
local lastState, lastSel, lastScan, lastResync, lastSeq = nil, nil, -1e9, -1e9, nil
local bank = 3                       -- start on bank 4 (0-based); follows the Twister afterwards
local eqOwned = false                -- Reaper_MultiEQ.lua is running and fills bank 4 itself

-- SysEx to the view: F0 7D 4D <cmd> ... F7 ----------------------------------------------------
-- SysEx carries 7 bits: umlauts, ß and ° travel as codes 1-8, the view turns them back (v6.1)
local UML = { ["\195\164"] = "\1", ["\195\182"] = "\2", ["\195\188"] = "\3", ["\195\132"] = "\4",
              ["\195\150"] = "\5", ["\195\156"] = "\6", ["\195\159"] = "\7", ["\194\176"] = "\8" }
local function ascii7(s)
  s = (s or ""):gsub("[\194\195][\128-\191]", function(u) return UML[u] or "" end)
  return (s:gsub("[^\1-\8\10\32-\126]", "")):sub(1, 64)
end

local function sysex(head, text)
  local t = { "\240\125\77" }                    -- F0 7D 4D
  for _, b in ipairs(head) do t[#t + 1] = string.char(b) end
  if text then t[#t + 1] = ascii7(text) end
  t[#t + 1] = "\247"                             -- F7
  r.SendMIDIMessageToHardware(viewOut, table.concat(t))
end

-- mapping scan --------------------------------------------------------------------------------
local function cfg(tr, fx, key)
  local ok, v = r.TrackFX_GetNamedConfigParm(tr, fx, key)
  if ok and v ~= "" then return tonumber(v) end
end

local function shortFx(name)
  return (name:gsub("^%w+%d?i?:%s*", ""):gsub("%s*%(.-%)%s*$", ""))
end

local function scan()
  local found = {}
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    local sel = r.IsTrackSelected(tr)
    for fx = 0, r.TrackFX_GetCount(tr) - 1 do
      for p = 0, r.TrackFX_GetNumParams(tr, fx) - 1 do
        local m1 = cfg(tr, fx, "param." .. p .. ".learn.midi1")
        if m1 and floor(m1 / 16) == 0xB then              -- learned to a CC
          local m2 = cfg(tr, fx, "param." .. p .. ".learn.midi2")
          local flags = cfg(tr, fx, "param." .. p .. ".learn.flags") or 0
          local i = m2 and REV[(m1 % 16) * 128 + m2]
          if i and (sel or flags & 1 == 0) and (not found[i] or (sel and not found[i].sel)) then
            local _, pn = r.TrackFX_GetParamName(tr, fx, p, "")
            local _, fn = r.TrackFX_GetFXName(tr, fx, "")
            found[i] = { tr = tr, fx = fx, p = p, sel = sel, name = pn .. "\n" .. shortFx(fn) }
          end
        end
      end
    end
  end
  return found
end

-- input: Twister bank changes, bank buttons on the phone --------------------------------------
local function setBank(b, fromView)
  if b < 0 or b >= NB then return end
  bank = b
  sysex({ 4, b })
  if fromView and mftOut then r.SendMIDIMessageToHardware(mftOut, string.char(0xB0 + SYS_CH, b, 127)) end
end

local function readInput()
  local events, idx, newest = {}, 0, nil
  while idx < 256 do
    local seq, buf, _, dev = r.MIDI_GetRecentInputEvent(idx)
    if seq == 0 or (lastSeq and seq <= lastSeq) then break end
    if idx == 0 then newest = seq end
    table.insert(events, 1, { buf, dev & 0xFFFF })
    idx = idx + 1
  end
  if newest then lastSeq = newest end
  for _, e in ipairs(events) do
    local buf, dev = e[1], e[2]
    if #buf == 3 then
      local st, d1, d2 = buf:byte(1, 3)
      if st == 0xB0 + SYS_CH and d2 == 127 and d1 < NB then
        if dev == mftIn then setBank(d1, false) elseif dev == viewIn then setBank(d1, true) end
      end
    end
  end
end

-- main loop -----------------------------------------------------------------------------------
local function frame()
  local now = r.time_precise()
  readInput()
  local st = r.GetProjectStateChangeCount(0)
  local selTr = r.GetSelectedTrack(0, 0)
  local selKey = (selTr and r.GetTrackGUID(selTr) or "") .. ":" .. r.CountSelectedTracks(0)
  if st ~= lastState or selKey ~= lastSel or now - lastScan > 3 then
    lastState, lastSel, lastScan = st, selKey, now
    slots = scan()
  end
  if now - lastResync > RESYNC then
    lastResync = now
    sentCC, sentName, sentText, sentTrack = {}, {}, {}, nil
    sysex({ 5 }, "REAPER")
    sysex({ 4, bank })
    for b = 0, NB - 1 do if BANK_NAMES[b + 1] and b ~= EQ_BANK then sysex({ 6, b }, BANK_NAMES[b + 1]) end end
  end
  local tn = ""
  if selTr then
    local _, n = r.GetTrackName(selTr, "")
    tn = n
  end
  if tn ~= sentTrack then sentTrack = tn; sysex({ 3 }, tn) end

  local alive = tonumber(r.GetExtState("seren_MultiEQ", "alive"))
  local owned = alive ~= nil and now - alive < 2
  if owned ~= eqOwned then                 -- hand bank 4 over / take it back: send it fresh
    eqOwned = owned
    for i = EQ_BANK * 16 + 1, EQ_BANK * 16 + 16 do sentName[i], sentText[i], sentCC[i] = nil, nil, nil end
  end

  for i = 1, #ENC do
    local b, s = floor((i - 1) / 16), (i - 1) % 16
    if not (eqOwned and b == EQ_BANK) then
    local sl = slots[i]
    local name = sl and sl.name or ""
    if sentName[i] ~= name then sentName[i] = name; sysex({ 1, b, s }, name) end
    if sl then
      local v7 = floor(r.TrackFX_GetParamNormalized(sl.tr, sl.fx, sl.p) * 127 + 0.5)
      if sentCC[i] ~= v7 then
        sentCC[i] = v7
        local e = ENC[i]
        r.SendMIDIMessageToHardware(viewOut, string.char(0xB0 + e[1], e[2], v7))
        if SEND_TO_MFT and mftOut then r.SendMIDIMessageToHardware(mftOut, string.char(0xB0 + e[1], e[2], v7)) end
      end
      local _, txt = r.TrackFX_GetFormattedParamValue(sl.tr, sl.fx, sl.p, "")
      if sentText[i] ~= txt then sentText[i] = txt; sysex({ 2, b, s }, txt) end
    elseif sentText[i] ~= "" then
      sentText[i], sentCC[i] = "", nil
      sysex({ 2, b, s }, "")
    end
    end
  end
end

local function loop()
  frame()
  r.defer(loop)
end

local function find(count, name, match)
  for i = 0, count() - 1 do
    local ok, n = name(i, "")
    if ok and n:find(match, 1, true) then return i end
  end
end

local function init()
  viewOut = find(r.GetNumMIDIOutputs, r.GetMIDIOutputName, VIEW_MATCH)
  viewIn = find(r.GetNumMIDIInputs, r.GetMIDIInputName, VIEW_MATCH)
  mftIn = find(r.GetNumMIDIInputs, r.GetMIDIInputName, MFT_MATCH)
  mftOut = find(r.GetNumMIDIOutputs, r.GetMIDIOutputName, MFT_MATCH)
  if not viewOut then
    r.ShowMessageBox("No MIDI output containing '" .. VIEW_MATCH .. "' found.\n" ..
      "Enable it in Preferences > MIDI Devices.", "Twister View", 0)
    return
  end
  lastSeq = r.MIDI_GetRecentInputEvent(0)        -- ignore what happened before the start
  sysex({ 7 })
  r.atexit(function() sysex({ 7 }); sysex({ 5 }, "") end)
  loop()
end

init()
