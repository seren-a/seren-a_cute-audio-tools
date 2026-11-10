-- Mock of the reaper.* calls used by reaper_mft_hub.lua. Globals: OUT (captured messages), T (time)
OUT, T, HIST, SEQ = {}, 0, {}, 1000
OUTS = {"IAC Bus 1", "Midi Fighter Twister", "TouchOSC Bridge"}
INS  = {"Keystation", "Midi Fighter Twister", "TouchOSC Bridge"}
TRACKS, STATE, EXTS = {}, 1, {}
function evIn(dev, st, d1, d2) SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, string.char(st, d1, d2), dev}) end
local function info(tr, k) return tr.info[k] end
PEXT = {}
function FX(tr, f) if f >= 0x1000000 then return tr.rec[f - 0x1000000 + 1] end return tr.fx[f + 1] end
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
  GetMasterTrack = function() return MASTER end,
  GetMediaTrackInfo_Value = function(tr, k)
    tr.vals = tr.vals or {}
    if k == "IP_TRACKNUMBER" then for i, t in ipairs(TRACKS) do if t == tr then return i end end return -1 end
    local d = { D_VOL = 1, I_SOLO = 0, B_MUTE = 0 }
    return tr.vals[k] or d[k] or 0
  end,
  SetMediaTrackInfo_Value = function(tr, k, v) tr.vals = tr.vals or {}; tr.vals[k] = v; return true end,
  SetOnlyTrackSelected = function(tr) for _, t in ipairs(TRACKS) do t.sel = (t == tr) end end,
  Main_OnCommand = function(id) CMDS = (CMDS or '') .. id .. ';' end,
  ValidatePtr = function(p) return p ~= nil end,
  TrackFX_GetEnabled = function(tr, f) return FX(tr, f).enabled ~= false end,
  TrackFX_GetPreset = function(tr, f, b) local x = FX(tr, f); local ps = x.presets or {}; return #ps > 0, ps[x.preset or 1] or "" end,
  TrackFX_NavigatePresets = function(tr, f, d) local x = FX(tr, f); local ps = x.presets or {}; if #ps > 0 then x.preset = ((x.preset or 1) - 1 + d) % #ps + 1 end; return #ps > 0 end,
  TrackFX_SetEnabled = function(tr, f, on) FX(tr, f).enabled = on end,
  TrackFX_Show = function(tr, f, flag) local x = FX(tr, f); if flag == 3 then x.float = true elseif flag == 2 then x.float = false end; SHOWS = (SHOWS or 0) + 1 end,
  TrackFX_GetFloatingWindow = function(tr, f) return FX(tr, f).float and "hwnd" or nil end,
  TrackFX_GetRecCount = function(tr) return #(tr.rec or {}) end,
  TrackFX_GetFXGUID = function(tr, f) return FX(tr, f).guid end,
  TrackFX_SetParamNormalized = function(tr, f, p, v)
    assert(type(v) == "number" and v >= 0 and v <= 1, "bad norm " .. tostring(v))
    local q = FX(tr, f).params[p + 1]; q.v = q.snap and q.snap(v) or v; SETS = (SETS or 0) + 1 end,
  TrackFX_FormatParamValueNormalized = function(tr, f, p, v)
    local q = FX(tr, f).params[p + 1]; if NOFMT then return false, "" end; return true, q.fmt(q.snap and q.snap(v) or v) end,
  GetProjExtState = function(p, sec, key) local v = PEXT[sec .. '/' .. key]; return v and 1 or 0, v or '' end,
  SetProjExtState = function(p, sec, key, v) PEXT[sec .. '/' .. key] = v end,
  ShowConsoleMsg = function(s) CONSOLE = (CONSOLE or '') .. s end,
  TrackFX_GetFXName = function(tr, f) return true, FX(tr, f).name end,
  TrackFX_GetNumParams = function(tr, f) return #FX(tr, f).params end,
  TrackFX_GetParamName = function(tr, f, p) return true, FX(tr, f).params[p + 1].name end,
  TrackFX_GetParamNormalized = function(tr, f, p) return FX(tr, f).params[p + 1].v end,
  TrackFX_GetFormattedParamValue = function(tr, f, p) local q = FX(tr, f).params[p + 1]; return true, q.fmt(q.v) end,
  TrackFX_GetNamedConfigParm = function(tr, f, key)
    local p, field = key:match("^param%.(%d+)%.learn%.(%w+)$")
    local q = p and FX(tr, f).params[tonumber(p) + 1]
    if not (q and q.learn) then return false, "" end
    local v = q.learn[field]
    if v == nil then return false, "" end
    return true, tostring(v)
  end,
}
-- v8.0: sends, meters, selection (Sends/Ziele module)
reaper.GetTrackNumSends = function(tr, cat)
  if cat == -1 then local n = 0; for _, t in ipairs(TRACKS) do for _, s in ipairs(t.sends or {}) do if s.dest == tr then n = n + 1 end end end; return n end
  if cat == 0 then return #(tr.sends or {}) end
  return 0
end
reaper.GetTrackSendInfo_Value = function(tr, cat, i, k)
  local s = tr.sends[i + 1]
  if k == "P_DESTTRACK" then return s.dest end
  return s[k] or 0
end
reaper.SetTrackSendInfo_Value = function(tr, cat, i, k, v) tr.sends[i + 1][k] = v; return true end
reaper.CreateTrackSend = function(tr, dest)
  tr.sends = tr.sends or {}
  tr.sends[#tr.sends + 1] = { dest = dest, D_VOL = 1, B_MUTE = 0, I_SENDMODE = 0 }
  return #tr.sends - 1
end
reaper.RemoveTrackSend = function(tr, cat, i) table.remove(tr.sends, i + 1) end
reaper.Track_GetPeakInfo = function(tr, c) return (tr.peak or 0) end
reaper.SetTrackSelected = function(tr, v) tr.sel = v end
reaper.CountTCPFXParms = function(p, tr) return #(tr.tcp or {}) end
reaper.GetTCPFXParm = function(p, tr, i) local x = tr.tcp[i + 1]; return true, x[1], x[2] end
reaper.Undo_OnStateChange = function(s) UNDOS = (UNDOS or '') .. s .. ';' end
