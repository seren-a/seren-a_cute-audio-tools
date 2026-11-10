-- seren.a OXI Puzzle – Einstellungen (ReaImGui). Schreibt dieselben ExtStates, die Reaper_OXI_Puzzle.lua liest;
-- das laufende Puzzle-Skript übernimmt Änderungen sofort.
local r = reaper
local EXT = "seren_OXI"
if not r.ImGui_CreateContext then
  r.ShowMessageBox("Dafür braucht es die Erweiterung ReaImGui (ReaPack > ReaTeam Extensions).", "seren.a OXI", 0)
  return
end

local DEFAULTS = {
  port = "oxi", layout = "16", markerRow = "0", markerKind = "auto", cells = "auto", groups = "1", markerLane = "1", rgnRange = "", folders = "1", empty = "1", receives = "show", visible = "all",
  pinned = "1", flip = "0", mainSend = "1", tripleVol = "1", seqMute = "1", seqSolo = "1", seqState = "1", statusCol = "0", turnShow = "big", marquee = "1", select = "full", follow = "1", states = "1,2,3,4,5,6,7", sendPush = "mute", preFx = "0", handover = "1",
  s1 = "_SWS_TAKESCHANMODE0", s2 = "_SWS_TAKESCHANMODE3", s3 = "normtrack", s4 = "zoomitem",
  d1 = "copyfx", d2 = "copysends", d3 = "", d4 = "",
  l1 = "pastefx", l2 = "replacesends", l3 = "removefx", l4 = "removesends",
}
local function get(k) local v = r.GetExtState(EXT, k); return v ~= "" and v or DEFAULTS[k] end
local function set(k, v)
  r.SetExtState(EXT, k, v, true)
  r.SetExtState(EXT, "rev", tostring(r.time_precise()), false)
end

local STATE_NAMES = { "Items (Gain, Fades, Spur)", "Sends 1-4", "Sends 5-8", "Sends 9-12", "Sends 13-16",
  "Item (Position, Pitch, Rate, Länge)", "Spur (Vol, Pan, Breite, Spur)" }
local BUILTINS = { "", "copyfx", "pastefx", "removefx", "copysends", "replacesends", "removesends", "normtrack", "zoomitem" }
local BUILTIN_TXT = { "(frei / Reaper-Aktion)", "FX-Kette kopieren", "FX-Kette einfügen", "FX-Kette entfernen",
  "Sends kopieren", "Sends ersetzen", "Sends entfernen", "Spur normalisieren (BR)", "Zoom auf Item" }

-- ---------------------------------------------------------------- seren.a look (colours of the TouchOSC surfaces)
local LOOKS = {
  { name = "IEM Neon", ground = 0x0E0B1F, cell = 0x17122F, track = 0x2B2350, txt = 0xF4F0FF, dim = 0xA99FD0, acc = 0x29E7FF },
  { name = "Neon", ground = 0x0E0B1F, cell = 0x17122F, track = 0x2B2350, txt = 0xF4F0FF, dim = 0xA99FD0, acc = 0xFF3D9A },
  { name = "Kawaii Nacht", ground = 0x231628, cell = 0x2E1D35, track = 0x4A2C55, txt = 0xFFE8F4, dim = 0xD7A6C6, acc = 0xFF8FC0 },
  { name = "Klar", ground = 0x0B0C0F, cell = 0x17191E, track = 0x22252B, txt = 0xF2F4F7, dim = 0x8B93A1, acc = 0x36D0C4 },
}
local IEM = { cyan = 0x00CAFE, green = 0x50FE03, orange = 0xFE9F01, red = 0xCF021C, white = 0xFFFFFF, pink = 0xFF4FA0 }
local SECTION = { IEM.cyan, IEM.green, IEM.orange, IEM.pink, IEM.red }
local function rgba(c, a) return (c << 8) | (a or 0xFF) end
local function mix(a, b, t)
  local function ch(x, s) return (x >> s) & 0xFF end
  local function m(s) return math.floor(ch(a, s) + (ch(b, s) - ch(a, s)) * t + 0.5) end
  return (m(16) << 16) | (m(8) << 8) | m(0)
end
local function curLook()
  local n = reaper.GetExtState("seren_look", "imgui")
  for _, L in ipairs(LOOKS) do if L.name == n then return L end end
  return LOOKS[1]
end
local themeN, sectionN = 0, 0
local function pushTheme(ctx)
  local L, r = curLook(), reaper
  local cols = {
    { r.ImGui_Col_WindowBg(), L.ground }, { r.ImGui_Col_ChildBg(), L.ground }, { r.ImGui_Col_PopupBg(), L.cell },
    { r.ImGui_Col_TitleBg(), L.ground }, { r.ImGui_Col_TitleBgActive(), L.track }, { r.ImGui_Col_TitleBgCollapsed(), L.ground },
    { r.ImGui_Col_FrameBg(), L.cell }, { r.ImGui_Col_FrameBgHovered(), L.track }, { r.ImGui_Col_FrameBgActive(), mix(L.track, L.acc, 0.3) },
    { r.ImGui_Col_Button(), L.track }, { r.ImGui_Col_ButtonHovered(), mix(L.track, L.acc, 0.45) }, { r.ImGui_Col_ButtonActive(), L.acc },
    { r.ImGui_Col_Header(), L.track }, { r.ImGui_Col_HeaderHovered(), mix(L.track, L.acc, 0.45) }, { r.ImGui_Col_HeaderActive(), L.acc },
    { r.ImGui_Col_CheckMark(), L.acc }, { r.ImGui_Col_SliderGrab(), L.acc }, { r.ImGui_Col_SliderGrabActive(), L.txt },
    { r.ImGui_Col_Separator(), L.track }, { r.ImGui_Col_Border(), L.track }, { r.ImGui_Col_Text(), L.txt },
    { r.ImGui_Col_TextDisabled(), L.dim },
  }
  for _, c in ipairs(cols) do r.ImGui_PushStyleColor(ctx, c[1], rgba(c[2])) end
  themeN = #cols
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 6)
  sectionN = 0
end
local function popTheme(ctx)
  reaper.ImGui_PopStyleVar(ctx, 3)
  reaper.ImGui_PopStyleColor(ctx, themeN)
end
local function section(ctx, label)                -- section heading in the next IEM colour
  sectionN = sectionN % #SECTION + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), rgba(SECTION[sectionN]))
  reaper.ImGui_SeparatorText(ctx, label)
  reaper.ImGui_PopStyleColor(ctx, 1)
end
local function lookPicker(ctx)
  local L = curLook()
  local names, idx = {}, 0
  for i, x in ipairs(LOOKS) do names[i] = x.name; if x == L then idx = i - 1 end end
  reaper.ImGui_SetNextItemWidth(ctx, 150)
  local ch, n = reaper.ImGui_Combo(ctx, "Look", idx, table.concat(names, "\0") .. "\0")
  if ch then reaper.SetExtState("seren_look", "imgui", LOOKS[n + 1].name, true) end
end
local function swatch(ctx, id, hex)             -- small colour field
  reaper.ImGui_ColorButton(ctx, id, rgba(hex), reaper.ImGui_ColorEditFlags_NoTooltip(), 14, 14)
  reaper.ImGui_SameLine(ctx)
end

local ctx = r.ImGui_CreateContext("seren.a OXI")
local STATE_HEX = { 0xFFFFFF, 0x00CAFE, 0x008CFE, 0x505AFE, 0x963CFE, 0xFE9F01, 0x50FE03 }   -- = the state pads on the grid

local function radio(label, key, choices)
  r.ImGui_Text(ctx, label)
  local cur = get(key)
  for _, c in ipairs(choices) do
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, c[2] .. "##" .. key, cur == c[1]) then set(key, c[1]) end
  end
end
local function check(label, key)
  local ch, v = r.ImGui_Checkbox(ctx, label, get(key) == "1")
  if ch then set(key, v and "1" or "0") end
end
local function slot(label, key)
  local cur = get(key)
  local idx = 0
  for i, b in ipairs(BUILTINS) do if b == cur and b ~= "" then idx = i - 1 end end
  r.ImGui_SetNextItemWidth(ctx, 170)
  local ch, n = r.ImGui_Combo(ctx, label .. "##c" .. key, idx, table.concat(BUILTIN_TXT, "\0") .. "\0")
  if ch then set(key, BUILTINS[n + 1]); cur = BUILTINS[n + 1] end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 230)
  local ch2, txt = r.ImGui_InputText(ctx, "##t" .. key, cur)
  if ch2 then set(key, txt) end
end

local function frame()
  pushTheme(ctx)
  r.ImGui_SetNextWindowSize(ctx, 640, 720, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, "seren.a OXI Puzzle – Einstellungen", true)
  if visible then
    lookPicker(ctx)
    section(ctx, "Spurtasten (die 8 Sequencer-Tasten)")
    check("Shift + Spurtaste = Master-/Parent-Send an/aus", "mainSend")
    check("2× Spurtaste = Mute", "seqMute")
    check("Spurtaste halten = Solo", "seqSolo")
    check("Spurtasten zeigen Mute (blinkt mit der E16), Solo (2. LED, gleicher Takt) und Rec (2× kurz, Pause)", "seqState")
    check("Letzte Grid-Spalte = Spurstatus (Spurfarbe, Mute grau, Solo gelb, Rec rot)", "statusCol")
    check("3× Spurtaste = Spur 0 dB / -inf", "tripleVol")
    section(ctx, "Ansicht")
    radio("Items pro Spur:", "layout", { { "10s", "10 + States" }, { "12", "12" }, { "14", "14" }, { "16", "16" } })
    check("Oberste Zeile = erste Marker-Lane", "markerRow")
    radio("Marker-Zeile zeigt (nur die gewählte Lane):", "markerKind", { { "auto", "automatisch (Regionen, wenn es welche gibt)" }, { "marker", "Marker" }, { "region", "Regionen" }, { "both", "beides" } })
    radio("Felder im Grid:", "cells", { { "auto", "automatisch: Regionen, wenn es welche gibt" }, { "regions", "Regionen (Lücken, wo nichts liegt)" }, { "items", "Items" } })
    check("Gruppierte Items = ein Feld (bei Items)", "groups")
    radio("Marker-Lane:", "markerLane", { { "1", "1 (oberste)" }, { "2", "2" }, { "3", "3" }, { "4", "4" } })
    r.ImGui_SetNextItemWidth(ctx, 120)
    local chr, rr = r.ImGui_InputText(ctx, "statt Lane: nur Nummern (z. B. 100-199, leer = aus)", get("rgnRange"))
    if chr then set("rgnRange", rr) end
    check("Ordner/Gruppen zeigen", "folders")
    check("Leere Spuren zeigen", "empty")
    radio("Spuren mit Receives:", "receives", { { "show", "zeigen" }, { "hide", "ausblenden" }, { "page", "eigene Seite (BACK)" } })
    radio("Spuren wie:", "visible", { { "all", "alle" }, { "tcp", "Spurliste (TCP)" }, { "mcp", "Mixer (MCP)" } })
    check("Angepinnte Spuren (TCP) zuerst", "pinned")
    check("Grid umdrehen (falls oben/unten vertauscht)", "flip")

    section(ctx, "Spurauswahl")
    radio("Push auf eine Spur/ein Item:", "select", { { "full", "in Reaper auswählen + Ansicht springt" },
      { "sel", "in Reaper auswählen" }, { "oxi", "nur auf der OXI" } })
    check("Puzzle folgt der in Reaper gewählten Spur", "follow")
    section(ctx, "Display")
    radio("Wert beim Drehen:", "turnShow", { { "big", "groß (Zeile 1-3)" }, { "line", "unterste Zeile" }, { "both", "beides" }, { "off", "aus" } })
    check("Laufschrift für lange Spur- und Item-Namen", "marquee")

    section(ctx, "Encoder-States (TRACK schaltet weiter)")
    local on = {}
    for s in get("states"):gmatch("%d+") do on[tonumber(s)] = true end
    for i, n in ipairs(STATE_NAMES) do
      swatch(ctx, "##st" .. i, STATE_HEX[i])
      local ch, v = r.ImGui_Checkbox(ctx, i .. ": " .. n, on[i] == true)
      if ch then
        on[i] = v or nil
        local t = {}
        for k = 1, #STATE_NAMES do if on[k] then t[#t + 1] = tostring(k) end end
        set("states", #t > 0 and table.concat(t, ",") or "1")
      end
    end
    r.ImGui_SetNextItemWidth(ctx, 200)
    local ch, txt = r.ImGui_InputText(ctx, "Reihenfolge", get("states"))
    if ch then set("states", txt) end

    section(ctx, "Sends")
    radio("Push auf Send-Encoder:", "sendPush", { { "mute", "Mute, 2× Pre/Post" }, { "mode", "Pre/Post, 2× Mute" } })
    check("Pre-FX mit durchschalten (Post → Pre-Fader → Pre-FX)", "preFx")

    section(ctx, "Encoder-Push im State Items (eingebaut oder Reaper-Aktions-ID)")
    for e = 1, 4 do slot("Enc " .. e .. " 1×", "s" .. e) end
    for e = 1, 4 do slot("Enc " .. e .. " 2×", "d" .. e) end
    for e = 1, 4 do slot("Enc " .. e .. " lang", "l" .. e) end

    section(ctx, "Gerät")
    r.ImGui_SetNextItemWidth(ctx, 200)
    local chp, port = r.ImGui_InputText(ctx, "MIDI-Name enthält", get("port"))
    if chp then set("port", port) end
    check("Beim Beenden an DrivenByMoss zurückgeben", "handover")
    if r.ImGui_Button(ctx, "Spurliste prüfen (Konsole)") then r.SetExtState("seren_OXI", "diag", "1", false) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Alles zurücksetzen") then
      for k, v in pairs(DEFAULTS) do set(k, v) end
    end
    r.ImGui_End(ctx)
  end
  popTheme(ctx)
  if open then r.defer(frame) end
end
r.defer(frame)
