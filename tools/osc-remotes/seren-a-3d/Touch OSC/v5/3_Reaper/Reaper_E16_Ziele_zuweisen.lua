-- seren.a 3D v8.0 · Die ausgewählten Spuren werden die Ziele (Hallspuren) für Reaper_E16_Twister.lua.
-- Reihenfolge = Reihenfolge im Projekt, bis zu 32; gespeichert im Projekt. Für die Toolbar gedacht.
local r = reaper
local n = r.CountSelectedTracks(0)
if n == 0 then
  r.ShowMessageBox("Bitte zuerst die Hallspuren auswählen.", "E16: Ziele zuweisen", 0)
  return
end
local guids, names = {}, {}
for i = 0, math.min(n, 32) - 1 do
  local t = r.GetSelectedTrack(0, i)
  guids[#guids + 1] = r.GetTrackGUID(t)
  local _, nm = r.GetTrackName(t)
  names[#names + 1] = (#names + 1) .. ": " .. nm
end
r.SetProjExtState(0, "seren_E16", "targets", table.concat(guids, ","))
r.SetExtState("seren_E16", "rev", tostring(r.time_precise()), false)
r.ShowConsoleMsg("[E16] Ziele: " .. table.concat(names, " · ") .. "\n")
