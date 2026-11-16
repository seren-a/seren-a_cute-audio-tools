-- reaper_collect.lua -- Ambisonic Loudness Meter: REAPER-Projekt analysieren.
--
-- Was es tut:
--   1. Findet alle "Ambisonic Loudness Meter"-FX-Instanzen im Projekt und liest
--      deren read-only Output-Parameter (alle Metriken) aus.
--   2. Listet alle Media-Items des Projekts mit Dateipfad (items.csv).
--   3. Schreibt alles in eine zentrale CSV (alle Analysen fliessen zusammen).
--
-- Nutzung: Actions > ReaScript > Load... diese Datei auswaehlen und starten.
-- Optional: POLL_SECONDS > 0 -> startet Playback und pollt N Sekunden lang.
--
-- Zentrale CSV: Umgebungsvariable AMBISONIC_ANALYSIS_CSV oder
--   <REAPER-ResourcePath>/ambisonic-analysis/results.csv
-- (macOS default: ~/Library/Application Support/REAPER/ambisonic-analysis/results.csv)

local PLUGIN_NAME   = "Ambisonic Loudness Meter"
local POLL_SECONDS  = 0   -- z. B. 30: Play startet automatisch, 30 s lang wird gepollt

local CENTRAL_CSV = os.getenv("AMBISONIC_ANALYSIS_CSV")
    or (reaper.GetResourcePath() .. "/ambisonic-analysis/results.csv")

-- Spalten der zentralen CSV (gleich wie scripts/batch_analyze.py)
local COLS = {
  "timestamp","source","project","track","fx","file",
  "integrated_lufs","max_shortterm_lufs","max_momentary_lufs","lra_lu",
  "true_peak_dbtp","w_only_lufs","l_aeq_db","l_c_minus_l_a_db",
  "l_a10_minus_l_a90_db","n10_sone","n50_sone","n90_sone","n10_minus_n90_sone",
  "sharpness_acum","roughness_asper","fluctuation_strength_vacil",
}

local function csv_escape(v)
  v = tostring(v == nil and "" or v)
  if v:find('[",\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
  return v
end

local function csv_row(t, cols)
  local parts = {}
  for _, c in ipairs(cols or COLS) do parts[#parts+1] = csv_escape(t[c]) end
  return table.concat(parts, ",")
end

local function ensure_dir(path)
  reaper.RecursiveCreateDirectory(path, 0)
end

local function append_csv(path, row)
  ensure_dir(path:match("(.*)/[^/]+$") or ".")
  local f = io.open(path, "a")
  if not f then return false end
  local need_header = f:seek("end") == 0
  f:close()
  f = io.open(path, "a")
  if need_header then f:write(csv_row({}, COLS) .. "\n") end
  f:write(csv_row(row) .. "\n")
  f:close()
  return true
end

local function project_info()
  local _, pname = reaper.GetProjectName(0, "")
  local _, pdir  = reaper.GetProjectPathEx(0, "")
  if not pdir or #pdir == 0 then _, pdir = reaper.GetProjectPath("") end
  return (pname or "project"), (pdir or reaper.GetResourcePath())
end

-- Alle Meter-Instanzen im Projekt: {track_idx, track_name, fx_idx, params={name=value}}
local function collect_fx()
  local out = {}
  local ntracks = reaper.CountTracks(0)
  for ti = 0, ntracks - 1 do
    local track = reaper.GetTrack(0, ti)
    local _, tname = reaper.GetTrackName(track, "")
    local nfx = reaper.TrackFX_GetCount(track)
    for fi = 0, nfx - 1 do
      local _, fxname = reaper.TrackFX_GetFXName(track, fi, "")
      if fxname and fxname:find(PLUGIN_NAME, 1, true) then
        local params = {}
        local np = reaper.TrackFX_GetNumParams(track, fi)
        for pi = 0, np - 1 do
          local _, pname = reaper.TrackFX_GetParamName(track, fi, pi, "")
          local norm, mn, mx = reaper.TrackFX_GetParam(track, fi, pi)
          local val = mn + norm * (mx - mn)
          params[pname] = val
        end
        out[#out+1] = { track_idx = ti, track_name = tname or "", fx_idx = fi, params = params }
      end
    end
  end
  return out
end

-- Alle Media-Items mit Quelldatei
local function collect_items()
  local out = {}
  local n = reaper.CountMediaItems(0)
  for i = 0, n - 1 do
    local item  = reaper.GetMediaItem(0, i)
    local pos   = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local track = reaper.GetMediaItemTrack(item)
    local _, tname = reaper.GetTrackName(track, "")
    local take  = reaper.GetActiveTake(item)
    local fname, tname_take = "", ""
    if take then
      local _, tk = reaper.GetTakeName(take, "")
      tname_take = tk or ""
      local src = reaper.GetTakeSource(take)
      if src then
        local ok, f = reaper.GetMediaSourceFileName(src)
        if not ok then ok, f = pcall(reaper.GetMediaSourceFileName, src) end
        if ok and f then fname = f end
      end
    end
    out[#out+1] = { item_idx = i, track_name = tname or "", position = pos,
                    length = len, file = fname, take = tname_take }
  end
  return out
end

local function now() return os.date("!%Y-%m-%dT%H:%M:%SZ") end

-- ---------------------------------------------------------------------------

local pname, pdir = project_info()
local adir = pdir .. "/analysis"
ensure_dir(adir)
local items_csv = adir .. "/items.csv"
local fx_csv    = adir .. "/fx_snapshot.csv"

-- items.csv (Uebergabe an batch_analyze.py)
do
  local f = io.open(items_csv, "w")
  f:write("timestamp,project,item_idx,track_name,position,length,file,take\n")
  local items = collect_items()
  for _, it in ipairs(items) do
    f:write(table.concat({
      now(), csv_escape(pname), it.item_idx, csv_escape(it.track_name),
      string.format("%.3f", it.position), string.format("%.3f", it.length),
      csv_escape(it.file), csv_escape(it.take)}, ",") .. "\n")
  end
  f:close()
end

-- optional: Playback starten und N s pollen, damit Integrated/LRA sich fuellen
if POLL_SECONDS and POLL_SECONDS > 0 then
  reaper.Main_OnCommand(1007, 0)  -- Transport: Play
  local steps = POLL_SECONDS * 10
  for _ = 1, steps do reaper.Sleep(100) end
  reaper.Main_OnCommand(1016, 0)  -- Transport: Stop
end

local fxlist = collect_fx()

-- fx_snapshot.csv (long format: eine Zeile pro Param)
do
  local f = io.open(fx_csv, "w")
  f:write("timestamp,project,track_idx,track_name,fx_idx,param,value\n")
  for _, fx in ipairs(fxlist) do
    for pname2, val in pairs(fx.params) do
      f:write(table.concat({ now(), csv_escape(pname), fx.track_idx,
        csv_escape(fx.track_name), fx.fx_idx, csv_escape(pname2),
        string.format("%.4f", val) }, ",") .. "\n")
    end
  end
  f:close()
end

-- zentrale CSV: eine breite Zeile pro FX-Instanz
local n_written = 0
for _, fx in ipairs(fxlist) do
  local row = {
    timestamp = now(), source = "reaper-fx", project = pname,
    track = fx.track_name, fx = fx.fx_idx, file = "",
  }
  for _, c in ipairs(COLS) do
    if fx.params[c] ~= nil then row[c] = string.format("%.4f", fx.params[c]) end
  end
  if append_csv(CENTRAL_CSV, row) then n_written = n_written + 1 end
end

reaper.ShowMessageBox(
  string.format("%d Meter-Instanz(en) gefunden, %d Zeile(n) nach\n%s\ngeschrieben.\n\nItems: %s\nFX-Snapshot: %s\n\nItems jetzt offline analysieren:\n  python3 scripts/batch_analyze.py --items-csv \"%s\"",
    #fxlist, n_written, CENTRAL_CSV, items_csv, fx_csv, items_csv),
  "Ambisonic Loudness Meter – Analyse", 0)
