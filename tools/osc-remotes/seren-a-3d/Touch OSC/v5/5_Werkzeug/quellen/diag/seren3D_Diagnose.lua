-- seren.a 3D · Diagnose für Reaper (ReaScript, Lua) · v5.0
-- Läuft 30 Sekunden, schreibt alles in die ReaScript-Konsole und schickt Test-Nachrichten
-- an die TouchOSC Bridge. Danach: Konsolentext komplett kopieren (Cmd+A, Cmd+C) und schicken.
-- Am Handy/iPad dabei Bridge-Test.tosc offen haben und einmal TEST SENDEN drücken.

local r = reaper
local MATCH = "TouchOSC Bridge"
local DURATION = 30
local out = {}
local function P(s) r.ShowConsoleMsg(tostring(s) .. "\n") end

r.ClearConsole()
P("=== seren.a 3D Diagnose · " .. os.date("%Y-%m-%d %H:%M:%S") .. " · REAPER " .. r.GetAppVersion())

-- 1. MIDI-Geräte -----------------------------------------------------------------------------
P("\n--- MIDI-Ausgänge (Index · vorhanden/aktiv · Name)")
local viewOut, viewIn
for i = 0, r.GetNumMIDIOutputs() - 1 do
  local ok, name = r.GetMIDIOutputName(i, "")
  if name ~= "" then
    P(string.format("  %2d  %-5s  %s%s", i, tostring(ok), name, name:find(MATCH, 1, true) and "   <== Bridge" or ""))
    if ok and name:find(MATCH, 1, true) and not viewOut then viewOut = i end
  end
end
P("--- MIDI-Eingänge")
for i = 0, r.GetNumMIDIInputs() - 1 do
  local ok, name = r.GetMIDIInputName(i, "")
  if name ~= "" then
    P(string.format("  %2d  %-5s  %s%s", i, tostring(ok), name, name:find(MATCH, 1, true) and "   <== Bridge" or ""))
    if ok and name:find(MATCH, 1, true) and not viewIn then viewIn = i end
  end
end
P("Bridge-Ausgang: " .. tostring(viewOut) .. " · Bridge-Eingang: " .. tostring(viewIn) ..
  "  (nil = in Einstellungen › MIDI Devices nicht aktiviert)")

-- 2. Spuren und Plugins ---------------------------------------------------------------------
local function ptype(n)
  n = (n or ""):lower()
  if n:find("multiencoder", 1, true) then return "MultiEncoder" end
  if n:find("stereoencoder", 1, true) then return "StereoEncoder" end
  if n:find("scenerotator", 1, true) then return "SceneRotator" end
  if n:find("dearvr pro", 1, true) then return "dearVR PRO" end
end
P("\n--- Spuren (" .. r.CountTracks(0) .. ")")
for t = 0, math.min(r.CountTracks(0), 32) - 1 do
  local tr = r.GetTrack(0, t)
  local _, tn = r.GetTrackName(tr, "")
  local selTxt = r.IsTrackSelected(tr) and "  [gewählt]" or ""
  P(string.format("Spur %d: %s%s", t + 1, tn, selTxt))
  for fx = 0, r.TrackFX_GetCount(tr) - 1 do
    local _, fn = r.TrackFX_GetFXName(tr, fx, "")
    local ty = ptype(fn)
    P(string.format("   FX %d: %s%s", fx + 1, fn, ty and ("   <== " .. ty) or ""))
    if ty then
      local names = {}
      local onTxt = (r.TrackFX_GetEnabled(tr, fx) and "an" or "UMGANGEN") .. ((r.TrackFX_GetOffline and r.TrackFX_GetOffline(tr, fx)) and ", offline" or "")
      P("      Zustand: " .. onTxt)
      -- dearVR: alle Parameter (Namen + Werte), damit die Erkennung angepasst werden kann
      local maxP = (ty == "dearVR PRO") and r.TrackFX_GetNumParams(tr, fx) or 14
      for i = 0, math.min(r.TrackFX_GetNumParams(tr, fx), maxP) - 1 do
        local _, pn = r.TrackFX_GetParamName(tr, fx, i, "")
        local _, pv = r.TrackFX_GetFormattedParamValue(tr, fx, i, "")
        names[#names + 1] = string.format("P%d '%s'=%s", i + 1, pn, pv)
      end
      P("      " .. table.concat(names, " | "))
    end
  end
end

-- 3. Test-Nachrichten ------------------------------------------------------------------------
if not viewOut then
  P("\nKEIN Bridge-Ausgang aktiv -> Einstellungen › MIDI Devices › TouchOSC Bridge (Ausgang) › Enable.")
  return
end
P("\n--- " .. DURATION .. " s Test: jede Sekunde 3 Wege an die Bridge. Im Bridge-Test am Gerät erscheint:")
P("    Test cmd 2 \"REAPER n\"       (SysEx über SendMIDIMessageToHardware)")
P("    CC Kanal 16 #100 = n          (über StuffMIDIMessage)")
P("    CC Kanal 16 #101 = n          (über SendMIDIMessageToHardware)")
P("    Bitte notieren, welche der drei ankommen. Und am Gerät TEST SENDEN drücken.")

local t0, lastSend, n, lastSeq = r.time_precise(), -1, 0, r.MIDI_GetRecentInputEvent(0)
local got = 0
local function loop()
  local now = r.time_precise()
  if now - lastSend >= 1 then
    lastSend = now; n = n + 1
    local txt = "REAPER " .. n
    r.SendMIDIMessageToHardware(viewOut, "\240\125\126\2" .. txt .. "\247")
    r.StuffMIDIMessage(16 + viewOut, 0xBF, 100, n % 128)
    r.SendMIDIMessageToHardware(viewOut, string.char(0xBF, 101, n % 128))
  end
  -- what comes in
  local idx, events = 0, {}
  while idx < 256 do
    local seq, buf, _, dev = r.MIDI_GetRecentInputEvent(idx)
    if seq == 0 or seq == lastSeq then break end
    table.insert(events, 1, { seq, buf, dev })
    idx = idx + 1
  end
  if #events > 0 then lastSeq = events[#events][1] end
  for _, e in ipairs(events) do
    local b = {}
    for i = 1, math.min(#e[2], 12) do b[#b + 1] = string.format("%02X", e[2]:byte(i)) end
    local dev = e[3] & 0xFFFF
    local _, dn = r.GetMIDIInputName(dev, "")
    got = got + 1
    if got <= 40 then P(string.format("  <- Eingang %d (%s): %s", dev, dn, table.concat(b, " "))) end
  end
  if now - t0 < DURATION then
    r.defer(loop)
  else
    P("\n=== fertig. " .. n .. " Testrunden gesendet, " .. got .. " Nachrichten empfangen" ..
      (viewIn and "" or " (Bridge-Eingang ist aus - dann kommt hier nichts an)") .. ".")
    P("Bitte diesen ganzen Text kopieren und an Claude schicken.")
  end
end
loop()
