-- Mock of the reaper.* calls used by reaper_mft_hub.lua. Globals: OUT (captured messages), T (time)
OUT, T, HIST, SEQ = {}, 0, {}, 1000
OUTS = {"IAC Bus 1", "Midi Fighter Twister", "TouchOSC Bridge"}
INS  = {"Keystation", "Midi Fighter Twister", "TouchOSC Bridge"}
TRACKS, STATE = {}, 1
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
  atexit = function(f) ATEXIT = f end,
  time_precise = function() return T end,
  GetOS = function() return OS or "macOS-arm64" end,
  ExecProcess = function(cmd, timeout)
    EXEC = (EXEC or 0) + 1
    if cmd:find("sysctl", 1, true) then return "0\n8\n" end
    return PS_OUT or "0\n 12.0 /Applications/REAPER.app/Contents/MacOS/REAPER\n 20,0 /usr/libexec/foo\n  0.0 bar\n"
  end,
  GetUnderrunTime = function() return XRUN or 0, 0, T * 1000 end,
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
reaper.GetTrackColor = function(tr) return tr.color or 0 end
reaper.ColorFromNative = function(c) return (c >> 16) & 255, (c >> 8) & 255, c & 255 end
reaper.SetOnlyTrackSelected = function(tr) for _, t in ipairs(TRACKS) do t.sel = (t == tr) end end
reaper.Track_GetPeakInfo = function(tr, ch) return tr.peak or 0 end
reaper.TrackFX_SetParamNormalized = function(tr, f, p, v) tr.fx[f + 1].params[p + 1].v = v; return true end
reaper.GetMediaTrackInfo_Value = function(tr, k)
  if k == "IP_TRACKNUMBER" then for i, t in ipairs(TRACKS) do if t == tr then return i end end end
  if k == "B_SHOWINTCP" then return tr.hidden and 0 or 1 end
  if k == "I_FOLDERDEPTH" then return tr.folder and 1 or 0 end
  return 0
end
reaper.TrackFX_GetInstrument = function(tr) return tr.instr and 0 or -1 end
reaper.GetSetMediaTrackInfo_String = function(tr, k, v, set) if k == "P_ICON" then return true, tr.icon or "" end return false, "" end
reaper.GetSetTrackGroupMembership = function(tr, g, m, v) return (g == "VOLUME_VCA_LEAD" and tr.vca) and 1 or 0 end
reaper.TrackFX_GetEnabled = function(tr, f) return not tr.fx[f + 1].off end
reaper.TrackFX_GetOffline = function(tr, f) return tr.fx[f + 1].offline == true end
-- v8.4: ExtState (track filter; old tests run with "all tracks" = 15,0) and receives
EXT = { ["seren_3D/filter"] = "15,0" }
reaper.GetExtState = function(s, k) return EXT[s .. "/" .. k] or "" end
reaper.SetExtState = function(s, k, v) EXT[s .. "/" .. k] = v end
reaper.GetTrackNumSends = function(tr, cat) if cat == -1 then return tr.recv or 0 end return 0 end
-- v8.14: project ExtState + parents (tr.parent)
PEXT = {}
reaper.GetProjExtState = function(p, s, k) local v = PEXT[s .. "/" .. k]; return v and 1 or 0, v or "" end
reaper.SetProjExtState = function(p, s, k, v) PEXT[s .. "/" .. k] = v end
reaper.GetParentTrack = function(tr) return tr.parent end
