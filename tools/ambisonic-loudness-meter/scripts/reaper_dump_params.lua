-- reaper_dump_params.lua -- Live-Werte ALLER Parameter der Ambisonic-Loudness-Meter-
-- Instanzen im Projekt in die ReaScript-Konsole schreiben (pollt TrackFX_GetParam).
--
-- Nutzung: REAPER oeffnen, Play druecken, dann Actions > ReaScript > Load diese Datei.
-- Konsole: View > ReaScript console (oder das Script-Fenster). Stop im Script-Fenster.

local PLUGIN_NAME = "Ambisonic Loudness Meter"

local function dump()
  local lines = { "--- " .. os.date("%H:%M:%S") .. " ---" }
  local found = 0
  for ti = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, ti)
    local _, tname = reaper.GetTrackName(track, "")
    local nfx = reaper.TrackFX_GetCount(track)
    for fi = 0, nfx - 1 do
      local _, fxname = reaper.TrackFX_GetFXName(track, fi, "")
      if fxname and fxname:find(PLUGIN_NAME, 1, true) then
        found = found + 1
        local np = reaper.TrackFX_GetNumParams(track, fi)
        for pi = 0, np - 1 do
          local _, pname = reaper.TrackFX_GetParamName(track, fi, pi, "")
          local norm, mn, mx = reaper.TrackFX_GetParam(track, fi, pi)
          lines[#lines+1] = string.format("tr%d [%s] fx%d  %-28s = %10.3f  (norm %.3f, range %g..%g)",
                                          ti, tname or "?", fi, pname, mn + norm * (mx - mn), norm, mn, mx)
        end
      end
    end
  end
  if found == 0 then lines[#lines+1] = "keine Meter-Instanz im Projekt gefunden" end
  reaper.ShowConsoleMsg(table.concat(lines, "\n") .. "\n")
  reaper.defer(dump)
end

dump()
