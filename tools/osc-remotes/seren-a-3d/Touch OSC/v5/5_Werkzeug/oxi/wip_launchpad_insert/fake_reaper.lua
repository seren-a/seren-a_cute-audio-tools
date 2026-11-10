-- minimal Reaper API stand-in for the OXI Puzzle tests
local R = {}
reaper = R
NOW = 1000.0
OUT = {}            -- {dev, msg}
CMDS = {}           -- Main_OnCommand log
EXTS = {}
DEFER = nil
ATEXIT = nil
INQ = {}            -- recent input, newest first: {seq, buf, dev}
SEQ = 100
CONSOLE = ""
PLAYSTATE = 0
CURSOR = 0
LOOP = { 0, 0 }
UNDO = {}

local function mkTrack(name, color, nItems)
  local t = { _t = "tr", name = name, vals = { D_VOL = 1, D_PAN = 0, D_WIDTH = 1, I_FOLDERDEPTH = 0, B_SHOWINTCP = 1,
    B_SHOWINMIXER = 1, B_TCPPIN = 0, B_MAINSEND = 1 }, color = color or 0, items = {}, sends = {}, recv = 0, fx = {}, sel = false,
    guid = "{" .. name .. "}" }
  for i = 1, nItems or 0 do
    local it = { _t = "it", tr = t, vals = { D_POSITION = (i - 1) * 2, D_LENGTH = 1.5, D_VOL = 1, D_FADEINLEN = 0.01,
      D_FADEOUTLEN = 0.01, B_MUTE = 0 }, sel = false, color = 0 }
    it.take = { _t = "tk", name = name .. " " .. i, vals = { D_PITCH = 0, D_PLAYRATE = 1 } }
    t.items[#t.items + 1] = it
  end
  return t
end
TRACKS = {}
function MK(name, color, n) local t = mkTrack(name, color, n); TRACKS[#TRACKS + 1] = t; return t end
function ADDSEND(src, dst, vol)
  src.sends[#src.sends + 1] = { dest = dst, D_VOL = vol or 1, D_PAN = 0, B_MUTE = 0, B_PHASE = 0, B_MONO = 0,
    I_SENDMODE = 0, I_SRCCHAN = 0, I_DSTCHAN = 0, D_PANLAW = -1 }
  dst.recv = dst.recv + 1
end
MARKERS = {}

function R.time_precise() return NOW end
function R.defer(f) DEFER = f end
function R.atexit(f) ATEXIT = f end
function R.ShowConsoleMsg(s) CONSOLE = CONSOLE .. s end
function R.GetExtState(sec, k) return EXTS[sec .. "/" .. k] or "" end
function R.SetExtState(sec, k, v) EXTS[sec .. "/" .. k] = v end
function R.GetNumMIDIInputs() return 4 end
function R.GetNumMIDIOutputs() return 4 end
local INS = { "Midi Fighter Twister", "OXI ONE MKII", "E16", "Launchpad Pro MK3 LPProMK3 MIDI" }
function R.GetMIDIInputName(i) return true, INS[i + 1] end
function R.GetMIDIOutputName(i) return true, INS[i + 1] end
function R.SendMIDIMessageToHardware(dev, msg) OUT[#OUT + 1] = { dev, msg } end
function R.MIDI_GetRecentInputEvent(idx)
  local e = INQ[idx + 1]
  if not e then return 0, "", 0, -1 end
  return e[1], e[2], 0, e[3], 0, 0
end
function INPUT(buf, dev) SEQ = SEQ + 1; table.insert(INQ, 1, { SEQ, buf, dev or 1 }) end

function R.CountTracks() return #TRACKS end
function R.GetTrack(_, i) return TRACKS[i + 1] end
function R.GetTrackName(t) return true, t.name end
function R.GetTrackGUID(t) return t.guid end
function R.GetTrackColor(t) return t.color end
function R.ColorFromNative(c) return c & 255, (c >> 8) & 255, (c >> 16) & 255 end
function R.GetMediaTrackInfo_Value(t, k)
  if k == "IP_TRACKNUMBER" then for i, x in ipairs(TRACKS) do if x == t then return i end end end
  return t.vals[k] or 0
end
function R.SetMediaTrackInfo_Value(t, k, v) t.vals[k] = v end
function R.CountTrackMediaItems(t) return #t.items end
function R.GetTrackMediaItem(t, i) return t.items[i + 1] end
function R.GetTrackNumSends(t, cat)
  if cat == -1 then return t.recv end
  if cat == 0 then return #t.sends end
  return 0
end
function R.GetTrackSendInfo_Value(t, cat, i, k)
  local s = t.sends[i + 1]
  if k == "P_DESTTRACK" then return s.dest end
  return s[k]
end
function R.SetTrackSendInfo_Value(t, cat, i, k, v) t.sends[i + 1][k] = v end
function R.RemoveTrackSend(t, cat, i) local s = table.remove(t.sends, i + 1); s.dest.recv = s.dest.recv - 1 end
function R.CreateTrackSend(t, d) ADDSEND(t, d); return #t.sends - 1 end
function R.TrackFX_GetCount(t) return #t.fx end
SHOWN = {}
local function FX(t, i)              -- fx entries may be plain names; turn them into objects on first use
  local f = t.fx[i + 1]
  if type(f) == "string" then
    f = { name = f, enabled = true, offline = false, open = false, params = {} }
    for k = 1, 6 do f.params[k] = { name = f.name .. "P" .. k, v = 0.5 } end
    t.fx[i + 1] = f
  end
  return f
end
function R.TrackFX_GetFXName(t, i) return true, "VST3: " .. FX(t, i).name .. " (Test)" end
function R.TrackFX_GetEnabled(t, i) return FX(t, i).enabled end
function R.TrackFX_SetEnabled(t, i, v) FX(t, i).enabled = v end
function R.TrackFX_GetOffline(t, i) return FX(t, i).offline end
function R.TrackFX_SetOffline(t, i, v) FX(t, i).offline = v end
function R.TrackFX_GetOpen(t, i) return FX(t, i).open end
function R.TrackFX_Show(t, i, how) SHOWN[#SHOWN + 1] = how; FX(t, i).open = (how == 3 or how == 1) end
function R.TrackFX_GetNumParams(t, i) return #FX(t, i).params end
function R.TrackFX_GetParamName(t, i, p) return true, FX(t, i).params[p + 1].name end
function R.TrackFX_GetFormattedParamValue(t, i, p) return true, string.format("%.2f", FX(t, i).params[p + 1].v) end
function R.TrackFX_GetParamNormalized(t, i, p) return FX(t, i).params[p + 1].v end
function R.TrackFX_SetParamNormalized(t, i, p, v) FX(t, i).params[p + 1].v = v end
function R.TrackFX_CopyToTrack(s, i, d, pos) table.insert(d.fx, pos + 1, s.fx[i + 1]) end
function R.TrackFX_Delete(t, i) table.remove(t.fx, i + 1) end
function R.IsTrackSelected(t) return t.sel end
function R.GetSelectedTrack(_, i)
  local n = 0
  for _, t in ipairs(TRACKS) do if t.sel then if n == i then return t end; n = n + 1 end end
end
function R.CountSelectedTracks() local n = 0; for _, t in ipairs(TRACKS) do if t.sel then n = n + 1 end end; return n end
function R.SetOnlyTrackSelected(t) for _, x in ipairs(TRACKS) do x.sel = (x == t) end end
function R.SetMixerScroll() end
function R.ValidatePtr(p, kind) return p ~= nil end
function R.GetMediaItem_Track(it) return it.tr end
function R.IsMediaItemSelected(it) return it.sel end
function R.SetMediaItemSelected(it, v) it.sel = v end
function R.GetMediaItemInfo_Value(it, k) return it.vals[k] or 0 end
function R.SetMediaItemInfo_Value(it, k, v) it.vals[k] = v end
function R.GetActiveTake(it) return it.take end
function R.GetMediaItemTakeInfo_Value(tk, k) return tk.vals[k] or 0 end
function R.SetMediaItemTakeInfo_Value(tk, k, v) tk.vals[k] = v end
function R.GetSetMediaItemTakeInfo_String(tk, k) return true, tk.name end
function R.GetDisplayedMediaItemColor(it) return it.color ~= 0 and it.color or it.tr.color end
function R.UpdateArrange() end
function R.Main_OnCommand(c)
  CMDS[#CMDS + 1] = c
  if c == 40289 then for _, t in ipairs(TRACKS) do for _, it in ipairs(t.items) do it.sel = false end end end
end
local NAMED = { _SWS_TAKESCHANMODE0 = 53001, _SWS_TAKESCHANMODE3 = 53004, _BR_NORMALIZE_LOUDNESS_ITEMS23 = 53100 }
function R.NamedCommandLookup(s) return NAMED[s] or 0 end
function R.Undo_BeginBlock() end
function R.Undo_EndBlock(s) UNDO[#UNDO + 1] = s end
function R.Undo_OnStateChange(s) UNDO[#UNDO + 1] = s end
function R.Undo_DoUndo2() UNDO[#UNDO + 1] = "UNDO" end
function R.Undo_DoRedo2() UNDO[#UNDO + 1] = "REDO" end
function R.GetPlayState() return PLAYSTATE end
function R.GetPlayPosition() return CURSOR end
function R.GetCursorPosition() return CURSOR end
function R.SetEditCurPos(p) CURSOR = p end
function R.GetSet_LoopTimeRange2(_, set, loop, s, e) if set then LOOP = { s, e } end; return LOOP[1], LOOP[2] end
function R.GetSet_ArrangeView2() end
function R.Master_GetTempo() return 120 end
function R.EnumProjectMarkers3(_, i)
  local m = MARKERS[i + 1]
  if not m then return 0 end
  return i + 1, m.rgn, m.pos, m.rend or 0, m.name, m.idx or (i + 1), m.col or 0
end
function R.GetLastMarkerAndCurRegion() return -1, -1 end
