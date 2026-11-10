--------------------------------------------------------------------------
-- CONFIG-Seite (gemeinsam). Braucht levels.lua + look.lua davor.
-- cfgButton(name) / cfgFader(name) liefern true, wenn sie zuständig waren.
-- Einstellungen gelten bis TouchOSC neu lädt; Startwerte stehen in LV / LOOK / CFG64.
--------------------------------------------------------------------------
local CFG64 = { gridSize = 0.18, gridAlpha = 0.5, panoAlpha = 0.6 }
local cfgChanged = nil      -- function(), vom Root-Skript gesetzt: neu zeichnen

-- Fader: Name -> { Tabelle, Feld, min, max, Format, log? }
local CFG_FADERS = {
  cfg_f_rms  = { LV, 'rmsMs', 50, 3000, '%.0f ms' },
  cfg_f_thr  = { LV, 'threshold', -60, -20, '%.0f dBFS' },
  cfg_f_fall = { LV, 'fallback', 0, 40, '%.1f dB/s' },
  cfg_f_hold = { LV, 'holdMs', 0, 5000, '%.0f ms' },
  cfg_f_att  = { LV, 'attackMs', 0, 200, '%.0f ms' },
  cfg_f_rel  = { LV, 'releaseMs', 50, 3000, '%.0f ms' },
  cfg_f_isz  = { LOOK, 'iconSize', 0.5, 2, '%.2f×' },
  cfg_f_ia   = { LOOK, 'iconAlpha', 0.2, 1, '%.0f%%', 100 },
  cfg_f_gsz  = { CFG64, 'gridSize', 0.15, 0.25, '%.0f%%', 100 },
  cfg_f_ga   = { CFG64, 'gridAlpha', 0.2, 0.8, '%.0f%%', 100 },
  cfg_f_pa   = { CFG64, 'panoAlpha', 0.3, 0.9, '%.0f%%', 100 },
}

local function cfgCtl(name) return root:findByName(name, true) end

-- Gruppen (v8.14, Reaper): A–D von hier + Ordner aus Reaper ohne dearVR/Hall. Die DAW schickt die Liste (cmd 19 Anzahl,
-- cmd 18 idx flags name; flags 1 = an, 2 = A–D, 4 = hat Spuren). Antippen = zeigen an/aus (SysEx 0C),
-- „+A“…„+D“ = Zuordnen: danach Spuren antippen (SysEx 0D <Buchstabe> <Objekt>), nochmal tippen = fertig.
local GR = { n = 0, list = {}, assign = nil }
local grSend = nil                                -- root setzt: function(bytes) sendMIDI(bytes, MIDI_OUT) end
local function grSysex(m)
  if m[4] == 19 and m[5] then
    GR.n = math.min(m[5], 12)
    for i = GR.n + 1, 12 do GR.list[i] = nil end
    return true
  end
  if m[4] == 18 and m[6] and m[5] < 12 then
    local t = {}
    for i = 7, #m - 1 do if m[i] >= 32 and m[i] <= 126 then t[#t + 1] = string.char(m[i]) end end
    GR.list[m[5] + 1] = { flags = m[6], name = table.concat(t) }
    return true
  end
  return false
end
-- Ansicht merken (v8.15, Reaper): Pegel-/Aussehen-Einstellungen + Modus/Layout gehen als Text an Reaper_3D.lua
-- (SysEx 0E <id> <text>), Reaper speichert sie und schickt sie beim Verbinden zurück (cmd 20 <id> <text>).
local VS = { id = 0, extra = nil, applyExtra = nil, got = false, last = nil, t = 0 }
local VS_KEYS = { { LV, 'scale', 's' }, { LV, 'mode', 's' }, { LV, 'aes17', 'b' }, { LV, 'rmsMs', 'n' }, { LV, 'loud', 's' },
  { LV, 'fallback', 'n' }, { LV, 'holdMs', 'n' }, { LV, 'target', 'n' }, { LV, 'attackMs', 'n' }, { LV, 'releaseMs', 'n' },
  { LV, 'threshold', 'n' }, { LOOK, 'colors', 's' }, { LOOK, 'theme', 's' }, { LOOK, 'marks', 'b' }, { LOOK, 'cpu', 'b' },
  { LOOK, 'icons', 's' }, { LOOK, 'iconSize', 'n' }, { LOOK, 'iconAlpha', 'n' }, { CFG64, 'gridSize', 'n' },
  { CFG64, 'gridAlpha', 'n' }, { CFG64, 'panoAlpha', 'n' } }
local function vsText()
  local t = {}
  for i, k in ipairs(VS_KEYS) do
    local v = k[1][k[2]]
    if k[3] == 'n' then v = string.format('%.3f', v) end
    t[#t + 1] = i .. '=' .. tostring(v)
  end
  if VS.extra then for key, v in pairs(VS.extra()) do t[#t + 1] = key .. '=' .. tostring(v) end end
  table.sort(t)
  return table.concat(t, ';')
end
local function vsApply(str)
  for key, v in str:gmatch('([%w_]+)=([^;]*)') do
    local k = VS_KEYS[tonumber(key) or 0]
    if k then
      if k[3] == 'n' then k[1][k[2]] = tonumber(v) or k[1][k[2]]
      elseif k[3] == 'b' then k[1][k[2]] = (v == 'true')
      else k[1][k[2]] = v end
    elseif VS.applyExtra then VS.applyExtra(key, v) end
  end
end
local function vsSysex(m)                         -- cmd 20 <id> <text>; true = handled
  if m[4] ~= 20 or m[5] ~= VS.id then return false end
  if not VS.got then
    local t = {}
    for i = 6, #m - 1 do t[#t + 1] = string.char(m[i]) end
    local str = table.concat(t)
    if str ~= '' then vsApply(str) end
    VS.got = true; VS.last = vsText()
    if lvReset then lvReset() end
    if cfgChanged then cfgChanged() end
  end
  return true
end
local function vsTick(now, send)                  -- im update(): Änderungen höchstens jede Sekunde an Reaper
  if not VS.got or now - VS.t < 1000 then return end
  VS.t = now
  local txt = vsText()
  if txt ~= VS.last and #txt < 400 then
    VS.last = txt
    local b = { 0xF0, 0x7D, 0x4F, 0x0E, VS.id }
    for i = 1, #txt do b[#b + 1] = txt:byte(i) % 128 end
    b[#b + 1] = 0xF7
    send(b)
  end
end

local function grText()                           -- Hinweis, solange zugeordnet wird
  if not GR.assign then return nil end
  return ({ 'A', 'B', 'C', 'D' })[GR.assign] .. ' zuordnen: Spuren antippen'
end

local function cfgPaint()
  local th = theme()
  local function pill(name, on)
    local c = cfgCtl(name .. '_bg')
    if c then
      local a = on and th.accent or th.pill
      c.color = Color(a[1], a[2], a[3], 1)
    end
  end
  for _, key in ipairs(SCALE_ORDER) do pill('cfg_sc_' .. key, LV.scale == key) end
  pill('cfg_md_peak', LV.mode == 'peak'); pill('cfg_md_rms', LV.mode == 'rms'); pill('cfg_aes', LV.aes17)
  pill('cfg_loud_M', LV.loud == 'M'); pill('cfg_loud_S', LV.loud == 'S')
  for _, tg in ipairs({ 23, 24, 16, 14 }) do pill('cfg_tg_' .. tg, LV.target == -tg) end
  for i, f in ipairs(FALLBACKS) do pill('cfg_fb_' .. i, math.abs(LV.fallback - f.v) < 0.05) end
  pill('cfg_col_tosc', LOOK.colors == 'tosc'); pill('cfg_col_daw', LOOK.colors == 'daw')
  pill('cfg_th_synth', LOOK.theme == 'synth'); pill('cfg_th_nuendo', LOOK.theme == 'nuendo')
  for _, key in ipairs({ 'audio', 'fx', 'group', 'instr' }) do pill('cfg_sh_' .. key, LOOK.show[key] ~= false) end
  pill('cfg_marks', LOOK.marks)
  pill('cfg_only', LOOK.onlyPlug); pill('cfg_cpu', LOOK.cpu)
  for _, key in ipairs({ 'off', 'dot', 'list', 'both' }) do pill('cfg_ic_' .. key, LOOK.icons == key) end
  for i = 1, 12 do
    local g = GR.list[i]
    local vis = g ~= nil
    for _, sfx in ipairs({ '', '_bg', '_lbl' }) do local c = cfgCtl('cfg_gr_' .. i .. sfx); if c then c.visible = vis end end
    if g then
      pill('cfg_gr_' .. i, g.flags % 2 == 1)
      local lab = cfgCtl('cfg_gr_' .. i .. '_lbl')
      local empty = math.floor(g.flags / 4) % 2 == 0
      if lab then lab.values.text = g.name .. (empty and ' (leer)' or '') end
    end
  end
  for i = 1, 4 do pill('cfg_as_' .. i, GR.assign == i) end
  local gi = cfgCtl('cfg_gr_info')
  if gi then gi.values.text = GR.n == 0 and 'Gruppen gibt es nur mit Reaper' or 'nichts an = alle Spuren' end
  for name, f in pairs(CFG_FADERS) do
    local c = cfgCtl(name)
    if c then
      local v = f[1][f[2]]
      if not c.values.touch then c.values.x = (v - f[3]) / (f[4] - f[3]) end
      local lab = cfgCtl(name .. '_val')
      if lab then
        local txt = string.format(f[5], v * (f[6] or 1))
        if name == 'cfg_f_fall' and v < 0.05 then txt = 'VU 300 ms' end
        if name == 'cfg_f_hold' and v < 1 then txt = 'aus' end
        lab.values.text = txt
      end
    end
  end
  local info = cfgCtl('cfg_info')
  if info then info.values.text = 'Anzeige: ' .. lvDescribe() .. '   ·   LUFS/LU sind Näherungen (ohne K-Filter, aus den DAW-Metern)' end
end

-- Voreinstellung in Reaper (v8.15): Ansicht + Config als Text "k=v;..." (SysEx 0E an die DAW, zurück als cmd 20)
local function cfgState(extra)
  local t = {}
  local function add(k, v) t[#t + 1] = k .. '=' .. tostring(v) end
  add('sc', LV.scale); add('md', LV.mode); add('aes', LV.aes17 and 1 or 0); add('loud', LV.loud); add('tg', LV.target)
  add('col', LOOK.colors); add('th', LOOK.theme); add('mk', LOOK.marks and 1 or 0); add('cpu', LOOK.cpu and 1 or 0); add('ic', LOOK.icons)
  local names = {}
  for name in pairs(CFG_FADERS) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do local f = CFG_FADERS[name]; add(name:sub(5), string.format('%.4g', f[1][f[2]])) end
  for k, v in pairs(extra or {}) do add(k, v) end
  table.sort(t)
  return table.concat(t, ';')
end
local function cfgApplyState(str)                -- gibt die Tabelle zurück (für die eigenen Schlüssel des Root-Skripts)
  local kv = {}
  for k, v in str:gmatch('([%w_]+)=([^;]*)') do kv[k] = v end
  local function num(k) return tonumber(kv[k]) end
  if kv.sc then LV.scale = kv.sc end
  if kv.md then LV.mode = kv.md end
  if kv.aes then LV.aes17 = kv.aes == '1' end
  if kv.loud then LV.loud = kv.loud end
  if num('tg') then LV.target = num('tg') end
  if kv.col then LOOK.colors = kv.col end
  if kv.th then LOOK.theme = kv.th end
  if kv.mk then LOOK.marks = kv.mk == '1' end
  if kv.cpu then LOOK.cpu = kv.cpu == '1' end
  if kv.ic then LOOK.icons = kv.ic end
  for name, f in pairs(CFG_FADERS) do local v = num(name:sub(5)); if v then f[1][f[2]] = v end end
  lvReset(); cfgPaint()
  return kv
end

local function cfgButton(name)
  local key
  key = name:match('^cfg_sc_(%w+)$'); if key then LV.scale = key; lvReset()
  elseif name == 'cfg_md_peak' then LV.mode = 'peak'
  elseif name == 'cfg_md_rms' then LV.mode = 'rms'
  elseif name == 'cfg_aes' then LV.aes17 = not LV.aes17
  elseif name == 'cfg_loud_M' or name == 'cfg_loud_S' then LV.loud = name:sub(-1)
  elseif name:match('^cfg_tg_%d+$') then LV.target = -tonumber(name:match('%d+$'))
  elseif name:match('^cfg_fb_%d$') then local f = FALLBACKS[tonumber(name:sub(-1))]; if f then LV.fallback = f.v end
  elseif name == 'cfg_col_tosc' then LOOK.colors = 'tosc'
  elseif name == 'cfg_col_daw' then LOOK.colors = 'daw'
  elseif name == 'cfg_th_synth' then LOOK.theme = 'synth'
  elseif name == 'cfg_th_nuendo' then LOOK.theme = 'nuendo'
  elseif name:match('^cfg_sh_%w+$') then local s = name:sub(8); LOOK.show[s] = (LOOK.show[s] == false)
  elseif name == 'cfg_marks' then LOOK.marks = not LOOK.marks
  elseif name == 'cfg_only' then LOOK.onlyPlug = not LOOK.onlyPlug
  elseif name == 'cfg_cpu' then LOOK.cpu = not LOOK.cpu
  elseif name:match('^cfg_ic_%w+$') then LOOK.icons = name:sub(8)
  elseif name:match('^cfg_gr_%d+$') then
    local i = tonumber(name:match('%d+$'))
    if GR.list[i] and grSend then grSend({ 0xF0, 0x7D, 0x4F, 0x0C, i - 1, 0, 0xF7 }) end
  elseif name:match('^cfg_as_%d$') then
    local i = tonumber(name:sub(-1)); GR.assign = (GR.assign ~= i) and i or nil
  else return false end
  cfgPaint()
  if cfgChanged then cfgChanged() end
  return true
end

local function cfgFader(name)
  local f = CFG_FADERS[name]
  local c = cfgCtl(name)
  if not f or not c then return false end
  local v = f[3] + c.values.x * (f[4] - f[3])
  if name == 'cfg_f_rms' or name == 'cfg_f_hold' or name == 'cfg_f_att' or name == 'cfg_f_rel' then v = math.floor(v / 10 + 0.5) * 10 end
  f[1][f[2]] = v
  cfgPaint()
  if cfgChanged then cfgChanged() end
  return true
end
