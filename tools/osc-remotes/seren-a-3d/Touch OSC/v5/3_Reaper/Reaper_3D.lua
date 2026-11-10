-- ReaScript (Lua): seren.a 3D v3 hub for Reaper. One script for all seren.a 3D surfaces over the
-- TouchOSC Bridge: Panner (Skript), Objekt-Übersicht (phone), IEM space (iPad). Protocol: PROTOKOLL.md.
-- Load via Actions > Show action list > New action > Load ReaScript, run once; it keeps running.
-- Reaper > Preferences > MIDI Devices: TouchOSC Bridge output AND input enabled.
-- NOT TESTED INSIDE REAPER: API calls checked against reaper_plugin_functions.h, logic against a mock.
--
-- Plugins are found BY NAME in any FX slot, and only ACTIVE ones count (not bypassed, not offline):
--   encoder  = the first active IEM StereoEncoder or MultiEncoder of the track
--   rotator  = the first active IEM SceneRotator
--   room     = the first active dearVR PRO (position + walls -> the surfaces' ROOM view)
-- Bypass one and the other takes over within a moment; bypass all and the track shows nothing.
-- Two active encoders on one track: the first one is used, the log says so.
-- Parameters are recognised by name ("Azimuth Angle", "Master azimuth angle", "Yaw Angle" ...);
-- nothing else is ever touched. The VST MultiPanner exists only in Nuendo.

local VIEW_MATCH = "TouchOSC Bridge"   -- part of the TouchOSC Bridge port name
local N          = 64                  -- tracks sent at once (iPad shows 16 of them, the 5:4 monitor up to 64)
local VISIBLE_ONLY = true               -- only tracks visible in the arrange view (TCP)
local ME_N       = 16                  -- MultiEncoder inputs shown for the selected track
local RESYNC     = 5                   -- seconds between full re-sends
local METER_FLOOR = -60                -- dBFS shown as level 0
local CPU_EVERY  = 3                   -- seconds between CPU readings for the surfaces (0 = off).
                                       -- macOS: reads 'ps' (takes a few ms); other systems: dropouts only
-- dearVR PRO: its manual doesn't say which way the axes point. If the ROOM view shows a source
-- mirrored, flip the matching switch here.
local DV_AZ_LEFT  = false               -- polar mode: true = +90 degrees azimuth is LEFT (IEM-style)
local DV_X_RIGHT  = true                -- cartesian mode: true = +X is RIGHT
local DV_Z_FRONT  = true                -- cartesian mode: true = +Z is IN FRONT (dearVR: Z = depth, Y = height)

local r = reaper
local floor, abs = math.floor, math.abs
local viewOut, viewIn
local bank = 0
local tracks = {}                      -- [k] = { tr, enc = {fx,type,idx,title}, rot = {...} }
local vis = {}                         -- visible tracks (no VCA leaders), in order
local selInfo = nil                    -- same for the selected track
local sent, level, msbIn = {}, {}, {}
local logged = {}
local lastState, lastScan, lastResync, lastSeq = nil, -1e9, -1e9, nil

-- out ---------------------------------------------------------------------------------------------
local function ascii7(s, n) return ((s or ""):gsub("[^\32-\126]", "")):sub(1, n or 96) end
local function sysex(id, head, text, n)
  local t = { "\240\125" .. string.char(id) }
  for _, b in ipairs(head) do t[#t + 1] = string.char(b) end
  if text then t[#t + 1] = ascii7(text, n) end
  t[#t + 1] = "\247"
  r.SendMIDIMessageToHardware(viewOut, table.concat(t))
end
local function ov(head, text) sysex(0x4F, head, text) end
-- short messages go the same way as SysEx (SendMIDIMessageToHardware), not via StuffMIDIMessage
local function send3(a, b, c) r.SendMIDIMessageToHardware(viewOut, string.char(a, b, c)) end
local function once(key, value, fn)
  if sent[key] == value then return end
  sent[key] = value
  fn()
end
local function q14(norm) return floor(math.max(0, math.min(1, norm)) * 16383 + 0.5) end
local function out14(ch, cc, norm)
  local v = q14(norm)
  once("cc" .. ch .. ":" .. cc, v, function()
    send3(0xB0 + ch, cc, floor(v / 128))
    send3(0xB0 + ch, cc + 32, v % 128)
  end)
end
local function ccOf(o, p) return 4 * (o % 8) + p end   -- o 0-based
-- objects 16+ (and dearVR always): SysEx F0 7D 4F 0A <kind 0 enc / 1 rot / 2 mp / 3 dearVR> <obj> <part> <msb> <lsb> F7
local KIND_CH = { [0] = 12, [1] = 6, [2] = 10 }
local function outObj(kind, o, p, norm)
  if o < 16 and KIND_CH[kind] then out14(KIND_CH[kind] + (o >> 3), ccOf(o, p), norm); return end
  local v = q14(norm)
  once("x" .. kind .. ":" .. o .. ":" .. p, v, function()
    r.SendMIDIMessageToHardware(viewOut, string.char(0xF0, 0x7D, 0x4F, 10, kind, o, p, v // 128, v % 128, 0xF7))
  end)
end
local dvUnknown                        -- defined with the dearVR part below
local function log(key, text)
  if logged[key] == text then return end
  logged[key] = text
  sysex(0x4F, { 8 }, key .. "|" .. text, 160)   -- key|text, empty text = remove line
end

-- recognising plugins and parameters by name -------------------------------------------------------
local function pluginType(name)
  local n = (name or ""):lower()
  if n:find("multiencoder", 1, true) or n:find("multi encoder", 1, true) then return "ME" end
  if n:find("stereoencoder", 1, true) or n:find("stereo encoder", 1, true) then return "SE" end
  if n:find("scenerotator", 1, true) or n:find("scene rotator", 1, true) then return "SR" end
  if n:find("dearvr pro", 1, true) then return "DV" end
  return nil
end
local PLUGIN = { SE = "StereoEncoder", ME = "MultiEncoder", SR = "SceneRotator", DV = "dearVR PRO" }

local function roleOf(t, title)
  local s = (title or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if t == "SE" then
    if s == "azimuth angle" then return "az" end
    if s == "elevation angle" then return "el" end
    if s == "stereo width" then return "wid" end
  elseif t == "ME" then
    if s == "master azimuth angle" then return "az" end
    if s == "master elevation angle" then return "el" end
    if s:find("^number of input channels") then return "nin" end
    local n = s:match("^azimuth angle (%d+)$"); if n then return "ia" .. n end
    n = s:match("^elevation angle (%d+)$"); if n then return "ie" .. n end
    n = s:match("^gain (%d+)$"); if n then return "ig" .. n end
  elseif t == "SR" then
    if s == "yaw angle" then return "yaw" end
    if s == "pitch angle" then return "pitch" end
    if s == "roll angle" then return "roll" end
  elseif t == "DV" then
    -- dearVR PRO: names are matched loosely (the manual doesn't list host parameter names)
    local function side()
      if s:find("left") then return "L" elseif s:find("right") then return "R"
      elseif s:find("front") then return "F" elseif s:find("back") or s:find("rear") then return "B"
      elseif s:find("top") or s:find("ceiling") then return "T"
      elseif s:find("bottom") or s:find("floor") or s:find("ground") then return "Bo" end
    end
    if s:find("wall") or s:find("auraliz") or s:find("auralis") then
      local w = side(); if w then return "w" .. w end
    end
    if s:find("scale") or s:find("gain") or s:find("pass") then return nil end
    if s:find("azimuth") then return "az" end
    if s:find("elevation") then return "el" end
    if s:find("distance") then return "dist" end
    if s:find("input mode") or s == "mode" or s:find("polar") or s:find("cartesian") then return "mode" end
    if s:find("preset") or s:find("virtual acoustic") then return "preset" end
    for _, a in ipairs({ "x", "y", "z" }) do
      if s == a or s:match("^" .. a .. "[%s_%-%(]") or s:match("[%s_%-]" .. a .. "$") or s:find("position " .. a, 1, true) then return a end
    end
  end
end

local function readPlugin(tr, fx, t)
  local p = { fx = fx, type = t, idx = {}, title = {}, names = {} }
  for i = 0, r.TrackFX_GetNumParams(tr, fx) - 1 do
    local _, name = r.TrackFX_GetParamName(tr, fx, i, "")
    p.names[#p.names + 1] = name
    local role = roleOf(t, name)
    if role and not p.idx[role] then p.idx[role] = i; p.title[role] = name end
  end
  return p
end

-- active = switched on and not offline (bypass in the FX chain = not active)
local function fxActive(tr, fx)
  if r.TrackFX_GetEnabled and not r.TrackFX_GetEnabled(tr, fx) then return false end
  if r.TrackFX_GetOffline and r.TrackFX_GetOffline(tr, fx) then return false end
  return true
end

-- every IEM/dearVR plugin of the track; the first ACTIVE one per role is used
local function scanTrack(tr)
  local info = { tr = tr, found = {} }
  for fx = 0, r.TrackFX_GetCount(tr) - 1 do
    local _, fn = r.TrackFX_GetFXName(tr, fx, "")
    local t = pluginType(fn)
    if t then
      local on = fxActive(tr, fx)
      info.found[#info.found + 1] = { fx = fx, type = t, on = on }
      local role = (t == "SE" or t == "ME") and "enc" or (t == "SR" and "rot") or "room"
      if on then
        if not info[role] then info[role] = readPlugin(tr, fx, t)
        else info.extra = (info.extra or 0) + 1; info.extraRole = role end
      end
    end
  end
  return info
end

-- one log line per track: which plugins are there and which one is used
local function plugLine(info)
  local parts = {}
  for _, f in ipairs(info.found) do
    local used = (info.enc and info.enc.fx == f.fx) or (info.rot and info.rot.fx == f.fx) or (info.room and info.room.fx == f.fx)
    parts[#parts + 1] = PLUGIN[f.type] .. " FX" .. (f.fx + 1) .. (f.on and (used and " *" or " (ignoriert)") or " (aus)")
  end
  return table.concat(parts, ", ")
end

local ROLE_NAME = { az = "Azimuth", el = "Elevation", wid = "Width", yaw = "Yaw", pitch = "Pitch", roll = "Roll",
                    dist = "Distance", x = "X", y = "Y", z = "Z", mode = "Modus", preset = "Preset",
                    wL = "Wand L", wR = "Wand R", wF = "Wand vorn", wB = "Wand hinten", wT = "Decke", wBo = "Boden" }
local function describe(p)
  if not p then return nil end
  local parts = {}
  for _, k in ipairs({ "az", "el", "wid", "yaw", "pitch", "roll", "dist", "x", "y", "z", "mode", "preset", "wL", "wR", "wF", "wB", "wT", "wBo" }) do
    if p.idx[k] then parts[#parts + 1] = ROLE_NAME[k] .. " P" .. (p.idx[k] + 1) end
  end
  return PLUGIN[p.type] .. " in FX " .. (p.fx + 1) .. " (" .. table.concat(parts, ", ") .. ")"
end

local function trackName(tr) local _, n = r.GetTrackName(tr, ""); return n end

-- track filter (v8.4, set from the surfaces' config, kept in the ExtState): the banks are built only from
-- matching tracks, so 8 tracks with a 3D plugin all sit on the first page, wherever they are in the project.
-- types: 1 audio, 2 FX (= track with receives), 4 group (= folder), 8 instrument; plug 1 = only tracks
-- with an encoder, rotator or dearVR PRO (bypassed ones count too: the track is meant for it)
local FILT = { types = 15, plug = 1 }
do
  local t, p = (r.GetExtState("seren_3D", "filter") or ""):match("^(%d+),(%d)$")
  if t then FILT.types, FILT.plug = tonumber(t), tonumber(p) end
end
local function typeBit(tr)
  if r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 then return 4 end
  if r.GetTrackNumSends(tr, -1) > 0 then return 2 end
  if r.TrackFX_GetInstrument(tr) >= 0 then return 8 end
  return 1
end
local function has3D(tr)
  for fx = 0, r.TrackFX_GetCount(tr) - 1 do
    local _, fn = r.TrackFX_GetFXName(tr, fx, "")
    if pluginType(fn) then return true end
  end
  return false
end
-- groups (v8.14): A-D made on the surface (tracks tapped in, kept in the project) + Reaper folder tracks that carry no
-- dearVR or reverb plugin (their children). Ticking groups on the surface shows only their tracks.
local GRP = { list = {}, vis = {} }
local LETTERS = { "A", "B", "C", "D" }
local function guidOf(tr) return r.GetTrackGUID(tr) end
local function grpGet(key) local _, v = r.GetProjExtState(0, "seren_3D", key); return v or "" end
local function grpSet(key, v) r.SetProjExtState(0, "seren_3D", key, v) end
local function isReverbFolder(tr)
  for fx = 0, r.TrackFX_GetCount(tr) - 1 do
    local _, fn = r.TrackFX_GetFXName(tr, fx, "")
    local n = fn:lower()
    if pluginType(fn) == "DV" or n:find("dearvr", 1, true) or n:find("reverb", 1, true) or n:find("verb", 1, true)
      or n:find("hall", 1, true) or n:find("fdn", 1, true) or n:find("convolver", 1, true) or n:find("room", 1, true) then
      return true
    end
  end
  return false
end
local function buildGroups()
  local L = {}
  for i, l in ipairs(LETTERS) do
    local set = {}
    for g in grpGet("grp_" .. l):gmatch("[^;]+") do set[g] = true end
    L[#L + 1] = { key = l, name = l, custom = true, members = set }
  end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if #L < 12 and r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 and not isReverbFolder(tr) then
      local _, nm = r.GetTrackName(tr)
      L[#L + 1] = { key = "F" .. guidOf(tr), name = nm, folder = tr }
    end
  end
  GRP.list = L
  GRP.vis = {}
  for k in grpGet("grp_vis"):gmatch("[^;]+") do GRP.vis[k] = true end
end
local function inFolder(tr, f)
  local p = tr
  while p do
    if p == f then return true end
    p = r.GetParentTrack(p)
  end
  return false
end
local function groupPasses(tr)
  local any = false
  for _, g in ipairs(GRP.list) do
    if GRP.vis[g.key] then
      any = true
      if g.custom and g.members[guidOf(tr)] then return true end
      if g.folder and inFolder(tr, g.folder) then return true end
    end
  end
  return not any
end
local function passes(tr)
  if not groupPasses(tr) then return false end
  if FILT.types & typeBit(tr) == 0 then return false end
  return FILT.plug == 0 or has3D(tr)
end
local function sendGroups()                       -- cmd 19 = count, cmd 18 = idx, flags (1 shown, 2 A-D, 4 has tracks), name
  ov({ 19, #GRP.list })
  for i, g in ipairs(GRP.list) do
    local has = g.folder ~= nil
    if g.custom then for _ in pairs(g.members) do has = true; break end end
    ov({ 18, i - 1, (GRP.vis[g.key] and 1 or 0) + (g.custom and 2 or 0) + (has and 4 or 0) }, g.name:sub(1, 24))
  end
end

local function isVcaLead(tr)
  if not r.GetSetTrackGroupMembership then return false end
  local ok, v = pcall(r.GetSetTrackGroupMembership, tr, "VOLUME_VCA_LEAD", 0, 0)
  return ok and v and v ~= 0
end
local function buildVis()
  buildGroups()
  vis = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local shown = (not VISIBLE_ONLY) or r.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") ~= 0
    if shown and not isVcaLead(tr) and passes(tr) then vis[#vis + 1] = tr end
  end
end
local function scan()
  tracks = {}
  buildVis()
  local sig = {}
  for _, g in ipairs(GRP.list) do
    local n = 0
    if g.custom then for _ in pairs(g.members) do n = n + 1 end end
    sig[#sig + 1] = g.key .. g.name .. n .. (GRP.vis[g.key] and "+" or "")
  end
  sig = table.concat(sig, "|")
  if sig ~= GRP.sig then GRP.sig = sig; sendGroups() end
  for k = 1, N do
    local tr = vis[bank * 16 + k]
    if tr then
      local info = scanTrack(tr)
      tracks[k] = info
      local no = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
      log("e" .. no, info.enc and ("Spur " .. no .. " " .. trackName(tr) .. " - " .. describe(info.enc)) or "")
      log("r" .. no, info.rot and ("Spur " .. no .. " " .. trackName(tr) .. " - " .. describe(info.rot)) or "")
      log("d" .. no, info.room and ("Spur " .. no .. " " .. trackName(tr) .. " - " .. describe(info.room)) or "")
      log("u" .. no, (#info.found > 1 or (#info.found == 1 and not info.found[1].on))
        and ("Spur " .. no .. " Plugins: " .. plugLine(info)) or "")
      if info.room and not (info.room.idx.x or info.room.idx.az) then dvUnknown(info.room) end
    end
  end
  local st = r.GetSelectedTrack(0, 0)
  selInfo = st and scanTrack(st) or nil
end

local function param(tr, p, role)
  local i = p and p.idx[role]
  if i then return r.TrackFX_GetParamNormalized(tr, p.fx, i) end
end
local function setParam(tr, p, role, norm)
  local i = p and p.idx[role]
  if not i then return false end
  r.TrackFX_SetParamNormalized(tr, p.fx, i, norm)
  return true
end

-- input from the devices --------------------------------------------------------------------------
local ENC_ROLES, ROT_ROLES = { "az", "el", "wid" }, { "yaw", "pitch", "roll" }
local PAN_ROLE = { [1] = "az", [2] = "el", [4] = "wid", [5] = "yaw", [6] = "pitch", [7] = "roll" }

-- no echo suppression: every connected surface gets the new value (surfaces ignore their own echo while touched)
local function onObj(kind, o, p, norm)
  local t = tracks[o + 1]
  if not t then return end
  if kind == 0 then setParam(t.tr, t.enc, ENC_ROLES[p + 1], norm)
  elseif kind == 1 then setParam(t.tr, t.rot, ROT_ROLES[p + 1], norm) end
end
local function onCC14(ch, c, norm)
  local o, p = (ch % 2) * 8 + floor(c / 4), c % 4      -- 0-based object, part
  if ch == 12 or ch == 13 then                          -- encoder of object
    local t = tracks[o + 1]
    if t and setParam(t.tr, t.enc, ENC_ROLES[p + 1], norm) then end
  elseif ch == 6 or ch == 7 then                        -- rotator of object
    local t = tracks[o + 1]
    if t and setParam(t.tr, t.rot, ROT_ROLES[p + 1], norm) then end
  elseif ch == 8 or ch == 9 then                        -- MultiEncoder input of the selected track
    local kind = ({ "a", "e", "g" })[p + 1]
    if selInfo and kind and setParam(selInfo.tr, selInfo.enc, "i" .. kind .. (o + 1), norm) then end
  elseif ch == 15 then                                  -- panner, selected track
    local role = PAN_ROLE[c]
    if selInfo and role then
      local p2 = (role == "yaw" or role == "pitch" or role == "roll") and selInfo.rot or selInfo.enc
      if setParam(selInfo.tr, p2, role, norm) then end
    end
  end
end

local function selectIndex(i)
  local tr = r.GetTrack(0, i)
  if tr then r.SetOnlyTrackSelected(tr) end
end

local function readInput()
  local events, idx, newest = {}, 0, nil
  while idx < 512 do
    local seq, buf, _, dev = r.MIDI_GetRecentInputEvent(idx)
    if seq == 0 or (lastSeq and seq <= lastSeq) then break end
    if idx == 0 then newest = seq end
    table.insert(events, 1, { buf, dev & 0xFFFF })
    idx = idx + 1
  end
  if newest then lastSeq = newest end
  for _, e in ipairs(events) do
    if e[2] == viewIn and #e[1] >= 10 and e[1]:byte(1) == 0xF0 and e[1]:byte(4) == 10 then
      local b = { e[1]:byte(1, 10) }
      if b[2] == 0x7D and b[3] == 0x4F and b[4] == 10 then onObj(b[5], b[6], b[7], (b[8] * 128 + b[9]) / 16383) end
    elseif e[2] == viewIn and #e[1] >= 6 and e[1]:byte(1) == 0xF0 and e[1]:byte(4) == 14 then
      local id = e[1]:byte(5)                          -- F0 7D 4F 0E <surface> <text> F7: view preset of iPad (0) / monitor (1)
      if e[1]:byte(2) == 0x7D and id <= 3 then r.SetExtState("seren_3D", "view" .. id, e[1]:sub(6, -2), true) end
    elseif e[2] == viewIn and #e[1] >= 6 and e[1]:byte(1) == 0xF0 and e[1]:byte(4) == 15 then
      local id = e[1]:byte(5)                          -- F0 7D 4F 0F <surface> F7: surface asks for its preset
      if e[1]:byte(2) == 0x7D and id <= 3 then sysex(0x4F, { 20, id }, r.GetExtState("seren_3D", "view" .. id), 1500) end
    elseif e[2] == viewIn and #e[1] >= 6 and e[1]:byte(1) == 0xF0 and e[1]:byte(4) == 12 then
      local b = { e[1]:byte(1, 6) }                     -- F0 7D 4F 0C <group idx> 0 F7: show/hide a group
      local g = GRP.list[b[5] + 1]
      if b[2] == 0x7D and b[3] == 0x4F and g then
        GRP.vis[g.key] = not GRP.vis[g.key] or nil
        local t = {}
        for k in pairs(GRP.vis) do t[#t + 1] = k end
        grpSet("grp_vis", table.concat(t, ";"))
        bank = 0; sent = {}; level = {}; lastScan = -1e9
        ov({ 5, 0 }); buildGroups(); sendGroups()
      end
    elseif e[2] == viewIn and #e[1] >= 7 and e[1]:byte(1) == 0xF0 and e[1]:byte(4) == 13 then
      local b = { e[1]:byte(1, 7) }                     -- F0 7D 4F 0D <A-D 0-3> <obj> F7: track in/out of group
      local l, info = LETTERS[b[5] + 1], tracks[b[6] + 1]
      if b[2] == 0x7D and b[3] == 0x4F and l and info then
        local set, list = {}, {}
        for g in grpGet("grp_" .. l):gmatch("[^;]+") do set[g] = true end
        local id = guidOf(info.tr)
        set[id] = not set[id] or nil
        for g in pairs(set) do list[#list + 1] = g end
        grpSet("grp_" .. l, table.concat(list, ";"))
        lastScan = -1e9; buildGroups(); sendGroups()
      end
    elseif e[2] == viewIn and #e[1] >= 6 and e[1]:byte(1) == 0xF0 and e[1]:byte(4) == 11 then
      local b = { e[1]:byte(1, 6) }                     -- F0 7D 4F 0B <types> <plug> F7: track filter from a surface
      if b[2] == 0x7D and b[3] == 0x4F and b[5] <= 15 and b[6] <= 1 and (b[5] ~= FILT.types or b[6] ~= FILT.plug) then
        FILT.types, FILT.plug = b[5], b[6]
        r.SetExtState("seren_3D", "filter", FILT.types .. "," .. FILT.plug, true)
        bank = 0; sent = {}; level = {}; lastScan = -1e9
        ov({ 5, 0 }); ov({ 16, FILT.types, FILT.plug })
      end
    elseif e[2] == viewIn and #e[1] == 3 then
      local st, d1, d2 = e[1]:byte(1, 3)
      local kind, ch = st >> 4, st & 15
      if kind == 0xB and d1 < 64 then
        if d1 < 32 then msbIn[ch * 128 + d1] = d2
        else onCC14(ch, d1 - 32, ((msbIn[ch * 128 + d1 - 32] or 0) * 128 + d2) / 16383) end
      elseif kind == 0x9 and d2 > 0 then
        if ch == 14 and d1 < N then
          local tr = vis[bank * 16 + d1 + 1]
          if tr then r.SetOnlyTrackSelected(tr) end
        elseif ch == 15 and (d1 == 0 or d1 == 1) then
          local cur = r.GetSelectedTrack(0, 0)
          local i = cur and (r.GetMediaTrackInfo_Value(cur, "IP_TRACKNUMBER") - 1) or -1
          selectIndex(math.max(0, math.min(r.CountTracks(0) - 1, i + (d1 == 1 and 1 or -1))))
        elseif ch == 15 and (d1 == 2 or d1 == 3) then
          local nb = bank + (d1 == 3 and 1 or -1)
          if nb >= 0 and nb * 16 < #vis then
            bank = nb; sent = {}; level = {}; lastScan = -1e9
            ov({ 5, bank })
          end
        end
      end
    end
  end
end

-- dearVR PRO -------------------------------------------------------------------------------------
-- The manual's 46 presets with their wall distances in metres: left, front, right, top, back, bottom
local DV_ROOMS = {
  ["Concert Hall 1"] = { 12.9, 14.0, 10.5, 20.8, 25.1, 1.8 }, ["Concert Hall 2"] = { 14.1, 16.6, 13.3, 21.5, 28.3, 1.8 },
  ["Large Recording Hall"] = { 15.7, 12.1, 15.9, 22.2, 19.3, 1.8 }, ["Small Recording Hall"] = { 7.7, 5.4, 7.9, 12.0, 9.3, 1.8 },
  ["Kings Hall"] = { 13.7, 10.4, 13.9, 20.3, 7.3, 1.8 }, ["Cathedral"] = { 27.5, 24.2, 29.0, 30.0, 30.0, 1.8 },
  ["Church"] = { 13.9, 17.9, 11.5, 25.5, 22.1, 1.8 }, ["Chapel"] = { 14.7, 12.4, 14.1, 23.0, 16.3, 1.8 },
  ["Large Room"] = { 7.9, 4.4, 6.9, 10.0, 5.5, 1.8 }, ["Medium Room"] = { 3.8, 2.1, 4.1, 4.0, 2.8, 1.8 },
  ["Small Room"] = { 2.7, 1.5, 2.6, 3.6, 2.2, 1.8 }, ["Office 1"] = { 3.2, 1.9, 3.9, 4.5, 2.8, 1.8 },
  ["Office 2"] = { 6.7, 2.4, 6.9, 5.3, 3.3, 1.8 }, ["Small Studio"] = { 2.7, 2.0, 3.4, 4.7, 2.1, 1.8 },
  ["Medium Conference Hall"] = { 6.7, 3.4, 6.9, 7.0, 3.3, 1.8 }, ["Cellar"] = { 2.5, 2.8, 3.0, 3.2, 2.1, 1.8 },
  ["Empty Room"] = { 5.0, 3.2, 3.7, 5.8, 4.3, 1.8 }, ["Small Livingroom"] = { 2.3, 3.1, 2.7, 2.9, 2.6, 1.8 },
  ["Staircase"] = { 4.7, 3.5, 4.9, 8.0, 3.3, 1.8 }, ["Corridor"] = { 2.7, 2.0, 2.6, 8.8, 4.5, 1.8 },
  ["Bathroom"] = { 2.1, 2.0, 2.3, 2.8, 1.6, 1.8 }, ["Restroom"] = { 2.7, 1.5, 3.2, 4.2, 2.3, 1.8 },
  ["Car 1"] = { 0.6, 0.7, 1.7, 1.6, 1.9, 1.3 }, ["Car 2"] = { 0.5, 0.7, 1.0, 1.3, 1.6, 1.2 },
  ["Booth"] = { 3.7, 2.1, 3.3, 2.5, 1.3, 1.8 }, ["Cinema"] = { 8.0, 7.0, 9.0, 14.0, 9.0, 1.3 },
  ["Warehouse"] = { 12.0, 10.0, 8.0, 20.0, 15.0, 1.8 }, ["Outdoor Street"] = { 24.9, 0.0, 22.5, 0.0, 0.0, 1.8 },
  ["Outdoor Alley"] = { 14.2, 0.0, 16.5, 0.0, 3.1, 1.8 }, ["Studio Room"] = { 6.7, 3.4, 6.9, 8.0, 3.3, 1.8 },
  ["Live Stage"] = { 11.7, 5.4, 11.9, 16.5, 14.3, 1.8 }, ["Live Arena"] = { 20.2, 17.0, 21.5, 25.0, 15.7, 1.8 },
  ["Heavy Ambience"] = { 6.7, 3.1, 6.9, 8.0, 3.3, 1.8 }, ["Plate Ambience"] = { 6.7, 3.1, 6.9, 8.0, 3.3, 1.8 },
  ["Medium Ambience"] = { 6.7, 3.1, 6.9, 8.0, 3.3, 1.8 }, ["Small Ambience"] = { 6.7, 3.1, 6.9, 8.0, 3.3, 1.8 },
  ["Vocal Hall 1"] = { 20.2, 15.0, 21.5, 25.0, 12.7, 1.8 }, ["Vocal Hall 2"] = { 20.2, 15.0, 21.5, 25.0, 12.7, 1.8 },
  ["Vocal Plate"] = { 20.2, 15.0, 21.5, 25.0, 12.7, 1.8 }, ["Drum Room 1"] = { 6.7, 3.1, 6.9, 8.0, 3.3, 1.8 },
  ["Drum Room 2"] = { 2.7, 3.1, 2.9, 6.0, 4.3, 1.8 }, ["Percussion Plate"] = { 6.7, 3.4, 6.9, 8.0, 4.3, 1.8 },
  ["Percussion Ambience"] = { 6.7, 3.4, 6.9, 8.0, 4.3, 1.8 }, ["Acoustic Hall"] = { 20.2, 15.0, 21.5, 25.0, 12.7, 1.8 },
  ["String Hall"] = { 20.2, 15.0, 21.5, 25.0, 12.7, 1.8 }, ["String Plate"] = { 20.2, 15.0, 21.5, 25.0, 12.7, 1.8 },
}
local DV_RANGE = 32                    -- metres: positions go out as -32..+32 (14 bit = 4 mm)

local function fmtNum(tr, p, role)
  local i = p and p.idx[role]
  if not i then return nil, nil end
  local _, txt = r.TrackFX_GetFormattedParamValue(tr, p.fx, i, "")
  local num = ((txt or ""):match("[-+]?%d+[%.,]?%d*") or ""):gsub(",", ".")
  local n = tonumber(num)
  return n, txt
end

-- position relative to the listener in metres: x right, y front, z up
local function dvPosition(tr, p)
  local _, modeTxt = fmtNum(tr, p, "mode")
  local polar = modeTxt and modeTxt:lower():find("polar") ~= nil
  if p.idx.x and not polar then
    local x, y, z = fmtNum(tr, p, "x"), fmtNum(tr, p, "y"), fmtNum(tr, p, "z")
    if x and y and z then             -- dearVR: X sideways, Y height, Z depth
      return (DV_X_RIGHT and x or -x), (DV_Z_FRONT and z or -z), y
    end
  end
  local az, el, d = fmtNum(tr, p, "az"), fmtNum(tr, p, "el"), fmtNum(tr, p, "dist")
  if az and d then
    local a, e = math.rad(az), math.rad(el or 0)
    local side = d * math.cos(e) * math.sin(a)
    return (DV_AZ_LEFT and -side or side), d * math.cos(e) * math.cos(a), d * math.sin(e)
  end
end

-- walls: from the wall parameters if the plugin exposes them, else from the preset's table entry
local function dvRoom(tr, p)
  local w = {}
  for i, k in ipairs({ "wL", "wF", "wR", "wT", "wB", "wBo" }) do w[i] = fmtNum(tr, p, k) end
  local _, preset = fmtNum(tr, p, "preset")
  preset = (preset or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if not (w[1] and w[2] and w[3] and w[5]) then
    local t = DV_ROOMS[preset]
    if not t then return nil, preset end
    w = t
  end
  return w, preset
end

dvUnknown = function(p)
  -- position parameters not recognised: show the names once, so the matching can be fixed
  local s = table.concat(p.names, " | ")
  for i = 1, 3 do log("dvn" .. i, i == 1 and ("dearVR: Position nicht erkannt. Parameter: " .. s:sub(1, 50)) or s:sub(50 * i - 49, 50 * i)) end
end

-- output -------------------------------------------------------------------------------------------
local function sendOverview()
  for k = 1, N do
    local t = tracks[k]
    local o = k - 1
    local name, flags, col, isSel = "", 0, nil, false
    if t then
      name = trackName(t.tr)
      if t.enc then flags = flags | 1; if t.enc.type == "ME" then flags = flags | 4 end end
      if t.rot then flags = flags | 8 end
      local tb = typeBit(t.tr)                -- folder = group (32), receives = FX (16), instrument (64)
      if tb == 4 then flags = flags | 32 elseif tb == 2 then flags = flags | 16 elseif tb == 8 then flags = flags | 64 end
      local c = r.GetTrackColor(t.tr)
      if c ~= 0 then
        local cr, cg, cb = r.ColorFromNative(c & 0xFFFFFF)
        col = floor(cr / 2) .. "," .. floor(cg / 2) .. "," .. floor(cb / 2)
      end
      isSel = r.IsTrackSelected(t.tr)
    end
    once("n" .. k, name, function() ov({ 1, o }, name) end)
    local no = t and math.floor(r.GetMediaTrackInfo_Value(t.tr, "IP_TRACKNUMBER")) or 0
    once("no" .. k, no, function() ov({ 17, o, no // 128, no % 128 }) end)   -- real track number (v8.4)
    once("f" .. k, flags, function() ov({ 3, o, flags }) end)
    local icon = ""
    if t then
      local _, path = r.GetSetMediaTrackInfo_String(t.tr, "P_ICON", "", false)
      icon = (path or ""):match("([^/\\]+)$") or ""
      icon = icon:gsub("%.[%w]+$", "")
    end
    once("i" .. k, icon, function() ov({ 11, o }, icon) end)
    if col then
      once("c" .. k, col, function()
        local a, b, c2 = col:match("(%d+),(%d+),(%d+)")
        ov({ 2, o, tonumber(a), tonumber(b), tonumber(c2) })
      end)
    end
    once("s" .. k, isSel, function() send3(0x9E, o, isSel and 127 or 0) end)
    local lv = 0
    if t then
      local pk = math.max(r.Track_GetPeakInfo(t.tr, 0), r.Track_GetPeakInfo(t.tr, 1))
      if pk > 0 then
        lv = floor(math.max(0, math.min(1, (20 * math.log(pk, 10) - METER_FLOOR) / -METER_FLOOR)) * 127 + 0.5)
      end
    end
    local old = level[k]
    if old == nil or abs(lv - old) >= 2 or (lv == 0 and old ~= 0) then
      level[k] = lv
      send3(0xBE, o, lv)
    end
    if t then
      for p, role in ipairs(ENC_ROLES) do
        local v = param(t.tr, t.enc, role)
        if v then outObj(0, o, p - 1, v) end
      end
      for p, role in ipairs(ROT_ROLES) do
        local v = param(t.tr, t.rot, role)
        if v then outObj(1, o, p - 1, v) end
      end
    end
    -- dearVR PRO: position (SysEx 10, kind 3, metres -32..32) and room (cmd 14, walls in cm)
    local pos, room, preset = nil, nil, ""
    if t and t.room then
      pos = { dvPosition(t.tr, t.room) }
      room, preset = dvRoom(t.tr, t.room)
    end
    if pos and pos[1] then
      for p = 1, 3 do outObj(3, o, p - 1, (pos[p] + DV_RANGE) / (2 * DV_RANGE)) end
    end
    local key = room and (table.concat(room, ",") .. "|" .. preset) or (t and t.room and ("?|" .. preset) or "")
    once("rm" .. k, key, function()
      if room then
        local b = { 14, o }
        for i = 1, 6 do local cm = floor(math.min(163.83, math.max(0, room[i])) * 100 + 0.5); b[#b + 1] = cm // 128; b[#b + 1] = cm % 128 end
        ov(b, preset)
      else
        ov({ 14, o })                    -- no dearVR / room unknown
      end
    end)
  end
end

local PAN_CC = { az = 1, el = 2, wid = 4, yaw = 5, pitch = 6, roll = 7 }
local function sendSelected()
  local s = selInfo
  local name = s and trackName(s.tr) or ""
  once("p0", name, function() sysex(0x54, { 0 }, name) end)
  local encName = s and s.enc and PLUGIN[s.enc.type] or ""
  local rotName = s and s.rot and PLUGIN[s.rot.type] or ""
  once("p20", encName, function() sysex(0x54, { 20 }, encName) end)
  once("p21", rotName, function() sysex(0x54, { 21 }, rotName) end)
  log("sel", s and ("Gewaehlt: " .. name .. " - " .. (describe(s.enc) or "kein Encoder") ..
    " / " .. (describe(s.rot) or "kein Rotator")) or "")
  if not s then return end
  for role, cc in pairs(PAN_CC) do
    local p = (role == "yaw" or role == "pitch" or role == "roll") and s.rot or s.enc
    local v = param(s.tr, p, role)
    if v then
      out14(15, cc, v)
      local title = (p.type == "ME" and ("Master " .. ROLE_NAME[role])) or p.title[role]
      once("pt" .. cc, title, function() sysex(0x54, { cc }, title) end)
      local _, txt = r.TrackFX_GetFormattedParamValue(s.tr, p.fx, p.idx[role], "")
      once("pv" .. cc, txt, function() sysex(0x54, { 10 + cc }, txt) end)
    end
  end
  -- MultiEncoder inputs
  local count = 0
  if s.enc and s.enc.type == "ME" then
    local nin = param(s.tr, s.enc, "nin")
    count = nin and floor(nin * 64 + 0.5) or ME_N
    for n = 1, ME_N do
      for p, kind in ipairs({ "a", "e", "g" }) do
        local v = param(s.tr, s.enc, "i" .. kind .. n)
        if v then out14(8 + ((n - 1) >> 3), ccOf(n - 1, p - 1), v) end
      end
    end
  end
  once("me", count .. ":" .. name, function() ov({ 9, math.min(count, ME_N) }, name) end)
end

local function frame()
  local now = r.time_precise()
  readInput()
  local st = r.GetProjectStateChangeCount(0)
  local selTr = r.GetSelectedTrack(0, 0)
  if st ~= lastState or now - lastScan > 2 or (selInfo and selInfo.tr) ~= selTr then
    if bank > 0 and bank * 16 >= #vis then bank = 0; ov({ 5, 0 }) end
    lastState, lastScan = st, now
    scan()
  end
  if now - lastResync > RESYNC then
    lastResync = now; sent = {}
    ov({ 4 }, "REAPER"); ov({ 5, bank }); ov({ 12, N }); ov({ 16, FILT.types, FILT.plug }); sendGroups()
  end
  sendOverview()
  sendSelected()
end

-- CPU / dropouts (cmd 15) ------------------------------------------------------------------------
-- REAPER has no API for its own performance meter. macOS: sum of 'ps' %cpu over all processes
-- (and the REAPER process), divided by the number of cores. Dropouts: GetUnderrunTime changes.
local cpu = { t = -1e9, ncpu = nil, lastX = nil, xT = -1e9 }
local isMac = (r.GetOS() or ""):lower():find("osx") or (r.GetOS() or ""):lower():find("mac")
local function cpuPoll(now)
  if CPU_EVERY <= 0 or now - cpu.t < CPU_EVERY then return end
  cpu.t = now
  local sys, app = 127, 127
  if isMac and r.ExecProcess then
    if not cpu.ncpu then
      local o = r.ExecProcess("/usr/sbin/sysctl -n hw.ncpu", 1000) or ""
      cpu.ncpu = tonumber(o:match("\n%s*(%d+)")) or 1
    end
    local out = r.ExecProcess("/bin/ps -A -o %cpu=,comm=", 1000) or ""
    local rc, body = out:match("^(%-?%d+)\n(.*)$")
    if rc == "0" and body then
      local tot, ap = 0, 0
      for line in body:gmatch("[^\n]+") do
        local v, cmd = line:match("^%s*([%d%.,]+)%s+(.*)$")
        v = v and tonumber((v:gsub(",", ".")))
        if v then
          tot = tot + v
          if cmd:find("REAPER", 1, true) then ap = ap + v end
        end
      end
      sys = math.min(100, floor(tot / cpu.ncpu + 0.5))
      app = math.min(100, floor(ap / cpu.ncpu + 0.5))
    end
  end
  local x = r.GetUnderrunTime and r.GetUnderrunTime() or 0
  if cpu.lastX and x ~= cpu.lastX then cpu.xT = now end
  cpu.lastX = x
  ov({ 15, sys, app, (now - cpu.xT < 10) and 1 or 0 })
end

local function loop() frame(); cpuPoll(r.time_precise()); r.defer(loop) end

local function find(count, name, match)
  for i = 0, count() - 1 do
    local ok, n = name(i, "")
    if ok and n:find(match, 1, true) then return i end
  end
end

viewOut = find(r.GetNumMIDIOutputs, r.GetMIDIOutputName, VIEW_MATCH)
viewIn = find(r.GetNumMIDIInputs, r.GetMIDIInputName, VIEW_MATCH)
if not viewOut then
  r.ShowMessageBox("No MIDI output containing '" .. VIEW_MATCH .. "' found.\n" ..
    "Enable it in Preferences > MIDI Devices.", "seren.a 3D", 0)
else
  lastSeq = r.MIDI_GetRecentInputEvent(0)
  ov({ 7 })
  ov({ 8 }, "hello|3D v8.15 aktiv (Reaper) - Plugins in beliebigem FX-Slot, Spurfilter in der Config")
  if not viewIn then ov({ 8 }, "bridge|Achtung: Bridge-Eingang in Reaper aus - Bewegen vom Geraet geht nicht") end
  r.atexit(function() ov({ 7 }); ov({ 4 }, "") end)
  loop()
end
