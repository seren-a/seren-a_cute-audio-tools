-- seren.a 3D v8.1 · Einstellungen für Reaper_E16_Twister.lua (Sends / Ziele auf E16 Seite 1 und Twister Ebene 6).
-- Braucht ReaImGui (ReaPack > ReaTeam Extensions). Schreibt die ExtStates "seren_E16"; das laufende Skript übernimmt sofort.
-- Dieselben Optionen gibt es am E16 auf der Unterseite Menü (Seite 1, Encoder 16 halten).
local r = reaper
local SEXT = "seren_E16"
if not r.ImGui_CreateContext then
  r.ShowMessageBox("Dafür braucht es die Erweiterung ReaImGui (ReaPack > ReaTeam Extensions).\n" ..
    "Alle Optionen gibt es auch am E16: Seite 1, Encoder 16 halten bis Menü.", "seren.a E16", 0)
  return
end
--@@THEME@@
local DEF = { eqScope = "sel", capSend = "1", capTrack = "0", capGroup = "0", capRecv = "0", masterNav = "1", layout = "split", dedicated = "1", push = "prepost", preFx = "0", targets = "assigned", prefix = "RVB",
  cSend = "cyan", cPre = "weiss", cMute = "rot", cMeter = "pink", cFader = "hellblau", cMaster = "orange",
  cTrack = "weiss", triple = "1", dbl = "0", twister = "1", spur = "1" }
local COLS = { { "cyan", "Cyan", 0x00CAFE }, { "gruen", "Grün", 0x50FE03 }, { "orange", "Pfirsich/Orange", 0xFE9F01 },
  { "rot", "Rot", 0xCF021C }, { "weiss", "Weiß", 0xD9D9D9 }, { "gelb", "Gelb", 0xFFFF00 }, { "pink", "Pink", 0xFF4FA0 },
  { "hellblau", "Hellblau", 0x6495ED }, { "violett", "Violett", 0x9370DB }, { "tuerkis", "Türkis", 0x02FFFF } }
local function get(k) local v = r.GetExtState(SEXT, k); return v ~= "" and v or DEF[k] end
local function bump() r.SetExtState(SEXT, "rev", tostring(r.time_precise()), false) end
local function set(k, v) r.SetExtState(SEXT, k, v, true); bump() end

local ctx = r.ImGui_CreateContext("seren.a E16")
local function radio(label, key, choices)
  if label ~= "" then r.ImGui_Text(ctx, label) end
  local cur = get(key)
  for i, c in ipairs(choices) do
    if i > 1 then r.ImGui_SameLine(ctx) end
    if r.ImGui_RadioButton(ctx, c[2] .. "##" .. key, cur == c[1]) then set(key, c[1]) end
  end
end
local function check(label, key)
  local ch, v = r.ImGui_Checkbox(ctx, label, get(key) == "1")
  if ch then set(key, v and "1" or "0") end
end
local function colour(label, key)
  local cur, idx = get(key), 0
  local names = {}
  for i, c in ipairs(COLS) do names[i] = c[2]; if c[1] == cur then idx = i - 1 end end
  swatch(ctx, "##sw" .. key, COLS[idx + 1][3])
  r.ImGui_SetNextItemWidth(ctx, 170)
  local ch, n = r.ImGui_Combo(ctx, label, idx, table.concat(names, "\0") .. "\0")
  if ch then set(key, COLS[n + 1][1]) end
end

-- ---------------------------------------------------------------- targets: assignment and suggestions
local function trackName(t) local _, n = r.GetTrackName(t); return n end
local function guidList()
  local _, list = r.GetProjExtState(0, SEXT, "targets")
  local t = {}
  for g in list:gmatch("[^,]+") do t[#t + 1] = g end
  return t
end
local function setGuids(t)                     -- keeps project order
  local inSet = {}
  for _, g in ipairs(t) do inSet[g] = true end
  local out = {}
  for i = 0, r.CountTracks(0) - 1 do
    local g = r.GetTrackGUID(r.GetTrack(0, i))
    if inSet[g] and #out < 32 then out[#out + 1] = g end
  end
  r.SetProjExtState(0, SEXT, "targets", table.concat(out, ","))
  bump()
end
local function assignSelected(add)
  local t = add and guidList() or {}
  for i = 0, r.CountSelectedTracks(0) - 1 do t[#t + 1] = r.GetTrackGUID(r.GetSelectedTrack(0, i)) end
  setGuids(t)
end

-- FX categories from REAPER's FX browser (reaper-fxtags.ini) and own folders (reaper-fxfolders.ini)
local WANT_CAT = { "reverb", "delay", "room" }
local NAME_HINT = { "reverb", "verb", "hall", "room", "delay", "echo", "dearvr", "plate", "space", "convol" }
local function base(s)
  s = (s or ""):lower():gsub("\\", "/")
  s = s:match("([^/]+)$") or s
  s = s:gsub("^%w+:%s*", "")                    -- "vst3: …", "au: …"
  s = s:gsub("%.vst%.dylib$", ""):gsub("%.vst3$", ""):gsub("%.dll$", ""):gsub("%.dylib$", ""):gsub("%.vst$", "")
    :gsub("%.component$", ""):gsub("%.clap$", ""):gsub("%.so$", ""):gsub("%s*%(.-%)%s*$", "")
  return s
end
local CATS
local function loadCats()
  CATS = {}
  local res = r.GetResourcePath()
  local f = io.open(res .. "/reaper-fxtags.ini", "r")
  if f then
    local sec
    for line in f:lines() do
      local s = line:match("^%[(.-)%]")
      if s then sec = s:lower()
      elseif sec == "category" then
        local k, v = line:match("^(.-)=(.*)$")
        if k then CATS[base(k)] = (CATS[base(k)] or "") .. "|" .. v:lower() end
      end
    end
    f:close()
  end
  f = io.open(res .. "/reaper-fxfolders.ini", "r")
  if f then
    local names, sec, items = {}, nil, {}
    for line in f:lines() do
      local s = line:match("^%[(.-)%]")
      if s then sec = s
      else
        local k, v = line:match("^(.-)=(.*)$")
        if k and sec == "Folders" and k:match("^Name%d+$") then names[tonumber(k:match("%d+"))] = v:lower() end
        if k and sec and sec:match("^Folder%d+$") and k:match("^Item%d+$") then
          local n = tonumber(sec:match("%d+"))
          items[n] = items[n] or {}
          items[n][#items[n] + 1] = v
        end
      end
    end
    f:close()
    for n, list in pairs(items) do
      local fname = names[n] or ""
      for _, it in ipairs(list) do CATS[base(it)] = (CATS[base(it)] or "") .. "|" .. fname end
    end
  end
end
local function fxHit(tr, fx)                   -- returns a reason or nil
  local _, name = r.TrackFX_GetFXName(tr, fx, "")
  local ok, ident = r.TrackFX_GetNamedConfigParm(tr, fx, "fx_ident")
  local cats = (ok and CATS[base(ident)] or "") .. (CATS[base(name)] or "")
  for _, c in ipairs(WANT_CAT) do
    if cats:find(c, 1, true) then return base(name) ~= "" and (name:gsub("^%w+:%s*", "") .. " · " .. c) or c end
  end
  local low = name:lower()
  for _, h in ipairs(NAME_HINT) do if low:find(h, 1, true) then return name:gsub("^%w+:%s*", "") end end
end
local SUG, sugT = {}, -math.huge
local function scan()
  if not CATS then loadCats() end
  SUG = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetTrackNumSends(tr, -1) > 0 then                   -- only tracks that receive something
      for fx = 0, r.TrackFX_GetCount(tr) - 1 do
        local why = fxHit(tr, fx)
        if why then SUG[#SUG + 1] = { tr = tr, g = r.GetTrackGUID(tr), why = why }; break end
      end
    end
  end
end

local function targetsUI()
  local now = r.time_precise()
  if now - sugT > 2 then sugT = now; scan() end
  local on = {}
  for _, g in ipairs(guidList()) do on[g] = true end
  local rows, seen = {}, {}
  for _, s in ipairs(SUG) do rows[#rows + 1] = s; seen[s.g] = true end
  for i = 0, r.CountTracks(0) - 1 do                         -- assigned tracks that are no suggestion
    local tr = r.GetTrack(0, i)
    local g = r.GetTrackGUID(tr)
    if on[g] and not seen[g] then rows[#rows + 1] = { tr = tr, g = g, why = "von Hand" } end
  end
  if #rows == 0 then
    r.ImGui_TextDisabled(ctx, "Keine Vorschläge: keine Spur mit Receives hat ein Reverb/Delay/Room- oder dearVR-Plugin.")
  else
    r.ImGui_TextDisabled(ctx, "Vorschläge (Spuren mit Receives und Reverb/Delay/Room/dearVR) – anklicken = Ziel an/aus:")
    for _, s in ipairs(rows) do
      local num = math.floor(r.GetMediaTrackInfo_Value(s.tr, "IP_TRACKNUMBER"))
      local ch, v = r.ImGui_Checkbox(ctx, string.format("%d %s##%s", num, trackName(s.tr), s.g), on[s.g] == true)
      r.ImGui_SameLine(ctx)
      r.ImGui_TextDisabled(ctx, s.why)
      if ch then
        local t = {}
        for _, g in ipairs(guidList()) do if g ~= s.g then t[#t + 1] = g end end
        if v then t[#t + 1] = s.g end
        setGuids(t)
      end
    end
  end
  if r.ImGui_Button(ctx, "Alle Vorschläge") then
    local t = guidList()
    for _, s in ipairs(SUG) do t[#t + 1] = s.g end
    setGuids(t)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Ausgewählte Spuren = Ziele") then assignSelected(false) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+ Ausgewählte") then assignSelected(true) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Keine") then r.SetProjExtState(0, SEXT, "targets", ""); bump() end
  if #guidList() == 0 then
    r.ImGui_TextDisabled(ctx, "Nichts zugewiesen: dann gilt die alte Reverb-Remote-Zuweisung, sonst das Präfix.")
  end
  r.ImGui_SetNextItemWidth(ctx, 120)
  local chp, pre = r.ImGui_InputText(ctx, "Präfix (fällt in den Namen weg)", get("prefix"))
  if chp then set("prefix", pre) end
end

local function frame()
  pushTheme(ctx)
  r.ImGui_SetNextWindowSize(ctx, 640, 820, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, "seren.a E16 + Twister – Sends / Ziele", true)
  if visible then
    lookPicker(ctx)
    section(ctx, "Ziele (Hallspuren / FX-Returns)")
    radio("Ziele sind:", "targets", { { "assigned", "zugewiesene Spuren" }, { "sends", "die Sends der Spur" } })
    targetsUI()

    section(ctx, "Layout")
    radio("E16 Seite 1:", "layout", { { "split", "1-8 Sends / 9-16 Ziele" }, { "pages", "eigene Seiten für Sends und Ziele" } })
    check("Feste Encoder für Spur und Master (E16: Spur 8 bzw. 15, Master 16 · Twister: 15/16 wie im MultiEQ, 8 = Gruppe)", "dedicated")
    check("Twister: Ebene 6 „Sends“ in Bank 4", "twister")
    check("E16: Unterseite „Spur“ (TCP-Regler / Encoder-Plugin / Spurwerte)", "spur")

    section(ctx, "Push auf einen Send")
    radio("", "push", { { "prepost", "Pre/Post, 2× Ziel" }, { "mute", "Mute, 2× Ziel" }, { "mute_pp", "Mute, 2× Pre/Post" },
      { "pp_mute", "Pre/Post, 2× Mute" } })
    check("Pre-FX mit durchschalten (Post → Pre → PreFX)", "preFx")

    section(ctx, "MultiEQ")
    radio("MultiEQ A/B kommen von:", "eqScope", { { "sel", "nur der gewählten Spur (beide, wenn sie zwei hat)" }, { "all", "allen Spuren (alt: bis zu zwei, auch von verschiedenen Spuren)" } })

    section(ctx, "Pegel und Master")
    check("Sends höchstens 0 dB", "capSend")
    local CAP = { { "0", "0 dB" }, { "6", "+6 dB" }, { "12", "+12 dB" }, { "off", "aus" } }
    radio("Fader-Grenze, normale Spuren (+ Master):", "capTrack", CAP)
    radio("Fader-Grenze, Gruppen-/Ordnerspuren:", "capGroup", CAP)
    radio("Fader-Grenze, Spuren mit Receives:", "capRecv", CAP)
    check("Master-Encoder wie im MultiEQ: drehen = Spur vor/zurück, drücken + drehen = Master-Pegel", "masterNav")

    section(ctx, "Spur-Encoder (E16 15)")
    check("3× Push = Spur 0 dB / -inf", "triple")
    check("2× Push = Master-Send an/aus (Solo kommt dann 0,4 s später)", "dbl")

    section(ctx, "Ringfarben (E16, Twister, Twister View)")
    colour("Send", "cSend"); colour("Send Pre", "cPre"); colour("Send / Spur stumm", "cMute")
    colour("Ziel: Pegelanzeige", "cMeter"); colour("Ziel: Fader beim Drehen", "cFader")
    colour("Master", "cMaster"); colour("Spur", "cTrack")

    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Alles zurücksetzen") then for k, v in pairs(DEF) do set(k, v) end end
    r.ImGui_End(ctx)
  end
  popTheme(ctx)
  if open then r.defer(frame) end
end
r.defer(frame)
