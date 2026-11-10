-- Mock of the reaper.* calls used by reaper_mft_hub.lua. Globals: OUT (captured messages), T (time)
OUT, T, HIST, SEQ = {}, 0, {}, 1000
OUTS = {"IAC Bus 1", "Midi Fighter Twister", "TouchOSC Bridge"}
INS  = {"Keystation", "Midi Fighter Twister", "TouchOSC Bridge"}
TRACKS, STATE, EXTS = {}, 1, {}
function evIn(dev, st, d1, d2) SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, string.char(st, d1, d2), dev}) end
local function info(tr, k) return tr.info[k] end
reaper = {
  GetNumMIDIOutputs = function() return #OUTS end,
  GetMIDIOutputName = function(i) if OUTS[i + 1] then return true, OUTS[i + 1] end return false, "" end,
  GetNumMIDIInputs = function() return #INS end,
  GetMIDIInputName = function(i) if INS[i + 1] then return true, INS[i + 1] end return false, "" end,
  StuffMIDIMessage = function(mode, a, b, c)
    assert(mode >= 16 and math.type(a) == "integer" and math.type(c) == "integer" and c >= 0 and c <= 127, "bad stuff")
    OUT[#OUT + 1] = {dev = mode - 16, bytes = {a, b, c}}
  end,
  SendMIDIMessageToHardware = function(dev, msg)
    local t = {}
    for i = 1, #msg do t[i] = msg:byte(i) end
    OUT[#OUT + 1] = {dev = dev, bytes = t}
  end,
  MIDI_GetRecentInputEvent = function(idx)
    local e = HIST[idx + 1]
    if not e then return 0, "", 0, 0, -1, 0 end
    return e[1], e[2], 0, e[3], -1, 0
  end,
  defer = function(f) DEFER = f end,
  GetExtState = function(sec, key) return (EXTS[sec .. '/' .. key]) or '' end,
  SetExtState = function(sec, key, v) EXTS[sec .. '/' .. key] = v end,
  atexit = function(f) ATEXIT = f end,
  time_precise = function() return T end,
  ShowMessageBox = function(m) BOX = m end,
  GetProjectStateChangeCount = function() return STATE end,
  CountTracks = function() return #TRACKS end,
  GetTrack = function(p, i) return TRACKS[i + 1] end,
  IsTrackSelected = function(tr) return tr.sel end,
  CountSelectedTracks = function() local n = 0 for _, t in ipairs(TRACKS) do if t.sel then n = n + 1 end end return n end,
  GetSelectedTrack = function(p, i) local n = 0 for _, t in ipairs(TRACKS) do if t.sel then if n == i then return t end n = n + 1 end end end,
  GetTrackGUID = function(tr) return tr.guid end,
  GetTrackName = function(tr) return true, tr.name end,
  TrackFX_GetCount = function(tr) return #tr.fx end,
  TrackFX_GetFXName = function(tr, f) return true, tr.fx[f + 1].name end,
  TrackFX_GetNumParams = function(tr, f) return #tr.fx[f + 1].params end,
  TrackFX_GetParamName = function(tr, f, p) return true, tr.fx[f + 1].params[p + 1].name end,
  TrackFX_GetParamNormalized = function(tr, f, p) return tr.fx[f + 1].params[p + 1].v end,
  TrackFX_GetFormattedParamValue = function(tr, f, p) local q = tr.fx[f + 1].params[p + 1]; return true, q.fmt(q.v) end,
  TrackFX_GetNamedConfigParm = function(tr, f, key)
    local p, field = key:match("^param%.(%d+)%.learn%.(%w+)$")
    local q = p and tr.fx[f + 1].params[tonumber(p) + 1]
    if not (q and q.learn) then return false, "" end
    local v = q.learn[field]
    if v == nil then return false, "" end
    return true, tostring(v)
  end,
}
