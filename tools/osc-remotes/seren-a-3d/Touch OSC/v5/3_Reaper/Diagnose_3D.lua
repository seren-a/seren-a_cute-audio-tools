-- seren.a 3D: Diagnose (einmal ausfuehren, zeigt ein Fenster mit dem Ergebnis; sendet nichts ausser einem Test-Namen)
local r = reaper
local L = {}
local function add(s) L[#L + 1] = s end
add("Reaper " .. r.GetAppVersion() .. "  /  " .. r.GetOS())
add("Audio laeuft: " .. tostring(r.Audio_IsRunning and r.Audio_IsRunning()))
add("Spuren im Projekt: " .. r.CountTracks(0))
add("")
add("MIDI-Ausgaenge (TouchOSC Bridge markiert):")
local outs = {}
for i = 0, r.GetNumMIDIOutputs() - 1 do
  local ok, n = r.GetMIDIOutputName(i, "")
  if ok then
    local hit = n:find("TouchOSC Bridge", 1, true)
    add(string.format("  %d: %s%s", i, n, hit and "   <== Bridge" or ""))
    if hit then outs[#outs + 1] = i end
  end
end
add("MIDI-Eingaenge:")
for i = 0, r.GetNumMIDIInputs() - 1 do
  local ok, n = r.GetMIDIInputName(i, "")
  if ok then add(string.format("  %d: %s%s", i, n, n:find("TouchOSC Bridge", 1, true) and "   <== Bridge" or "")) end
end
add("")
if #outs == 0 then
  add("PROBLEM: kein MIDI-Ausgang 'TouchOSC Bridge' aktiv -> Preferences > MIDI Devices, Ausgang aktivieren.")
else
  local s = "REAPER"
  local msg = string.char(0xF0, 0x7D, 0x4F, 4) .. s .. string.char(0xF7)
  for _, o in ipairs(outs) do r.SendMIDIMessageToHardware(o, msg) end
  add("Test-SysEx 'DAW = REAPER' an " .. #outs .. " Ausgang/Ausgaenge gesendet.")
  add("-> Zeigt die Oberflaeche jetzt 'REAPER'?  Ja: Verbindung ok, Fehler liegt beim Einlesen der Spuren.  Nein: Verbindung/Port.")
end
local run = {}
add("")
add("Laufende Skripte: im Action-List-Fenster pruefen (Reaper_3D.lua muss laufen).")
local f = r.GetExtState("seren_3D", "filter2")
add("")
add("Gespeicherter Spurfilter (types,plug): '" .. f .. "'   (Normal: 31,0 = alle Typen, ohne Plugin-Filter)")
r.ShowMessageBox(table.concat(L, "\n"), "seren.a 3D Diagnose", 0)
if f ~= "31,0" and f ~= "" then
  if r.ShowMessageBox("Der Spurfilter ist nicht auf 'alle Spuren' gestellt (" .. f .. ").\nDas kann alle Spuren ausblenden.\n\nJetzt auf 'alle Spuren' zuruecksetzen?\n(Danach Reaper_3D.lua neu starten.)", "seren.a 3D Diagnose", 4) == 6 then
    r.SetExtState("seren_3D", "filter2", "31,0", true)
    r.ShowMessageBox("Zurueckgesetzt. Bitte Reaper_3D.lua beenden und neu starten.", "seren.a 3D Diagnose", 0)
  end
end
