--------------------------------------------------------------------------
-- RAUM (gemeinsam: IEM space iPad + IEM monitor 5:4) – Ansicht wie in dearVR PRO
-- Der Hörer sitzt im Ursprung; jede dearVR-Instanz kennt die Abstände zu den sechs Wänden
-- (links, vorn, rechts, Decke, hinten, Boden, Meter). Haben alle Quellen denselben Raum, stehen
-- sie gemeinsam darin (wie die Encoder in der IEM-Ansicht). Sonst gilt der Raum der gewählten
-- Quelle; Quellen aus anderen Räumen erscheinen blass.
-- Koordinaten: x rechts, y vorn, z oben (Meter, relativ zum Hörer).
-- Steuerelemente: rt_* (Draufsicht) und rs_* (Seitenansicht), Positionen setzt dieses Skript.
--------------------------------------------------------------------------
local RM = { GRID = 16 }
-- Zoom wie in dearVR PRO 2: sichtbarer Bereich ± so viele Meter um den Hörer; 0 = ganzer Raum
RM.ZOOMS = { 3, 6, 12, 18, 24, 30 }
RM.zoom = 0
RM.big = false           -- v8.16: Taste „groß“: Raum füllt den Bildschirm (Liste/Details weg)
RM.fitRange = 6
function RM.zoomStep(dir)          -- dir +1 = näher heran (kleinerer Bereich), -1 = weiter weg
  local cur = (RM.zoom > 0) and RM.zoom or RM.fitRange
  if dir > 0 then
    local best = nil
    for _, z in ipairs(RM.ZOOMS) do if z < cur - 0.01 then best = z end end
    RM.zoom = best or RM.ZOOMS[1]
  else
    local best = nil
    for i = #RM.ZOOMS, 1, -1 do if RM.ZOOMS[i] > cur + 0.01 then best = RM.ZOOMS[i] end end
    RM.zoom = best or RM.ZOOMS[#RM.ZOOMS]
  end
end
function RM.zoomFit() RM.zoom = 0 end

local function rmSame(a, b)
  if not a or not b then return false end
  for i = 1, 6 do if math.abs(a[i] - b[i]) > 0.05 then return false end end
  return true
end

-- objs: list of { k, room, x, y, z }, cur: chosen k. Returns ref room, its name, shared?, others
function RM.pick(objs, cur)
  local ref, refName
  for _, o in ipairs(objs) do if o.k == cur and o.room then ref, refName = o.room, o.name end end
  if not ref then for _, o in ipairs(objs) do if o.room then ref, refName = o.room, o.name; break end end end
  local others = 0
  for _, o in ipairs(objs) do
    o.inRoom = (ref == nil and o.room == nil) or rmSame(o.room, ref)
    if not o.inRoom then others = others + 1 end
  end
  return ref, refName, others == 0, others
end

-- equal-scale mapping of a metre box into an area (with margin)
local function fit(area, x0, x1, y0, y1)
  local m = 0.07
  local w, h = math.max(x1 - x0, 1), math.max(y1 - y0, 1)
  local s = math.min(area.w * (1 - 2 * m) / w, area.h * (1 - 2 * m) / h)
  local ox = area.x + (area.w - w * s) / 2 - x0 * s
  local oy = area.y + (area.h - h * s) / 2 + y1 * s
  -- map: metres -> screen; points outside the area stick to its edge (other rooms, far sources)
  return { s = s, x0 = x0, x1 = x1, y0 = y0, y1 = y1,
           map = function(x, y)
             local px, py = ox + x * s, oy - y * s
             return math.max(area.x + 6, math.min(area.x + area.w - 6, px)), math.max(area.y + 6, math.min(area.y + area.h - 6, py))
           end }
end

local function extent(objs, f, lo, hi)
  for _, o in ipairs(objs) do if o.inRoom then local v = f(o); lo, hi = math.min(lo, v), math.max(hi, v) end end
  return lo, hi
end

-- walls 0 m = open side: then the sources decide (at least 3 m)
function RM.topMap(area, room, objs)
  if RM.zoom > 0 then local z = RM.zoom; return fit(area, -z, z, -z, z) end
  local L, F, R, B = 3, 3, 3, 3
  if room then L, F, R, B = room[1], room[2], room[3], room[5] end
  local x0, x1 = (L > 0) and -L or -3, (R > 0) and R or 3
  local y0, y1 = (B > 0) and -B or -3, (F > 0) and F or 3
  x0, x1 = extent(objs, function(o) return o.x end, x0, x1)
  y0, y1 = extent(objs, function(o) return o.y end, y0, y1)
  RM.fitRange = math.max(-x0, x1, -y0, y1)
  return fit(area, x0, x1, y0, y1)
end
-- side view: horizontal = front (right) / back (left), vertical = height
function RM.sideMap(area, room, objs)
  if RM.zoom > 0 then local z = RM.zoom; return fit(area, -z, z, -z * 0.5, z * 0.5) end
  local F, T, B, Bo = 3, 3, 3, 1.8
  if room then F, T, B, Bo = room[2], room[4], room[5], room[6] end
  local x0, x1 = (B > 0) and -B or -3, (F > 0) and F or 3
  local y0, y1 = (Bo > 0) and -Bo or -2, (T > 0) and T or 3
  x0, x1 = extent(objs, function(o) return o.y end, x0, x1)
  y0, y1 = extent(objs, function(o) return o.z end, y0, y1)
  return fit(area, x0, x1, y0, y1)
end

local function gridStep(s)
  for _, st in ipairs({ 0.5, 1, 2, 5, 10 }) do if st * s >= 26 then return st end end
  return 20
end

-- ui = { frame(name, x, y, w, h), vis(name, bool), col(name, rgb, a), text(name, s) }
-- view: 'rt' (top) or 'rs' (side); lims = wall coordinates in this view {left, right, bottom, top}
local function drawView(ui, pre, area, mp, walls, th, labels)
  local x0, y0 = mp.map(mp.x0, mp.y0)
  local x1, y1 = mp.map(mp.x1, mp.y1)
  ui.frame(pre .. '_floor', x0, y1, x1 - x0, y0 - y1)
  ui.col(pre .. '_floor', th.panel, 1)
  -- grid in metres, through the listener
  local st = gridStep(mp.s)
  local n = 0
  for gx = math.ceil(mp.x0 / st) * st, mp.x1, st do
    n = n + 1
    if n <= RM.GRID then
      local px = mp.map(gx, 0)
      ui.frame(pre .. '_gx' .. n, px - 0.5, y1, 1, y0 - y1); ui.vis(pre .. '_gx' .. n, true)
      ui.col(pre .. '_gx' .. n, th.line, math.abs(gx) < 1e-6 and 0.9 or 0.45)
    end
  end
  for i = n + 1, RM.GRID do ui.vis(pre .. '_gx' .. i, false) end
  n = 0
  for gy = math.ceil(mp.y0 / st) * st, mp.y1, st do
    n = n + 1
    if n <= RM.GRID then
      local _, py = mp.map(0, gy)
      ui.frame(pre .. '_gy' .. n, x0, py - 0.5, x1 - x0, 1); ui.vis(pre .. '_gy' .. n, true)
      ui.col(pre .. '_gy' .. n, th.line, math.abs(gy) < 1e-6 and 0.9 or 0.45)
    end
  end
  for i = n + 1, RM.GRID do ui.vis(pre .. '_gy' .. i, false) end
  -- walls: {name, value or nil, vertical?}; value 0 = open
  for _, w in ipairs(walls) do
    local name, v, vert = w[1], w[2], w[3]
    local on = v ~= nil and v ~= 0
    if on then   -- outside the zoomed view: not drawn
      if vert then on = v >= mp.x0 and v <= mp.x1 else on = v >= mp.y0 and v <= mp.y1 end
    end
    ui.vis(pre .. '_' .. name, on and true or false)
    if on then
      if vert then
        local px = mp.map(v, 0)
        ui.frame(pre .. '_' .. name, px - 2, y1, 4, y0 - y1)
      else
        local _, py = mp.map(0, v)
        ui.frame(pre .. '_' .. name, x0, py - 2, x1 - x0, 4)
      end
      ui.col(pre .. '_' .. name, th.accent2, 0.95)
    end
  end
  -- listener
  local lx, ly = mp.map(0, 0)
  ui.frame(pre .. '_lis', lx - 12, ly - 12, 24, 24); ui.col(pre .. '_lis', th.text, 0.95)
  ui.frame(pre .. '_nose', lx - 4 + (labels.noseX or 0), ly - 4 + (labels.noseY or 0), 8, 8); ui.col(pre .. '_nose', th.accent, 1)
  ui.text(pre .. '_scale', string.format('Raster %s m', (st < 1) and '0,5' or tostring(math.floor(st))))
  ui.frame(pre .. '_scale', area.x + 8, area.y + area.h - 22, 200, 18)
  ui.frame(pre .. '_title', area.x + 8, area.y + 4, area.w - (pre == 'rt' and 300 or 16), 22)
  return st
end

-- draws both views; returns the two mappings (for the sources)
function RM.draw(ui, topArea, sideArea, room, name, shared, others, objs, th)
  local tm = RM.topMap(topArea, room, objs)
  local wl = room and { { 'wl', -room[1], true }, { 'wr', room[3], true }, { 'wf', room[2], false }, { 'wb', -room[5], false } }
             or { { 'wl', nil }, { 'wr', nil }, { 'wf', nil }, { 'wb', nil } }
  for _, w in ipairs(wl) do if w[2] and math.abs(w[2]) < 1e-6 then w[2] = nil end end
  -- dearVR measures open sides as 0 m: keep those walls hidden
  if room then
    if room[1] <= 0 then wl[1][2] = nil end
    if room[3] <= 0 then wl[2][2] = nil end
    if room[2] <= 0 then wl[3][2] = nil end
    if room[5] <= 0 then wl[4][2] = nil end
  end
  drawView(ui, 'rt', topArea, tm, wl, th, { noseY = -14 })
  -- zoom: − [Raum / 6 m] +, oben rechts in der Draufsicht
  local zx, zy = topArea.x + topArea.w - 180, topArea.y + 4
  for _, c in ipairs({ { 'rz_big', zx - 96, 88 }, { 'rz_minus', zx, 44 }, { 'rz_fit', zx + 48, 84 }, { 'rz_plus', zx + 136, 44 } }) do
    ui.frame(c[1], c[2], zy, c[3], 34); ui.frame(c[1] .. '_bg', c[2], zy, c[3], 34); ui.frame(c[1] .. '_lbl', c[2], zy, c[3], 34)
    ui.col(c[1] .. '_bg', (c[1] == 'rz_fit' and RM.zoom == 0) and th.accent or th.pill, 1)
  end
  ui.text('rz_big_lbl', RM.big and 'klein' or 'groß')
  ui.text('rz_fit_lbl', RM.zoom > 0 and (string.format('± %d m', RM.zoom)) or 'Raum')
  local title
  if room then
    title = string.format('%s · %.1f × %.1f × %.1f m', (name ~= '' and name or 'Raum'),
      room[1] + room[3], room[2] + room[5], room[4] + room[6])
  else
    title = 'Raum unbekannt (Preset ohne Wände)'
  end
  if not shared then title = title .. string.format('  ·  %d Quelle%s in anderem Raum (blass)', others, others == 1 and '' or 'n') end
  ui.text('rt_title', (title:gsub('%.', ',')))
  local sm = nil
  if sideArea then
    sm = RM.sideMap(sideArea, room, objs)
    local ws = room and { { 'wf', room[2], true }, { 'wb', -room[5], true }, { 'wt', room[4], false }, { 'wbo', -room[6], false } }
               or { { 'wf', nil }, { 'wb', nil }, { 'wt', nil }, { 'wbo', nil } }
    if room then
      if room[2] <= 0 then ws[1][2] = nil end
      if room[5] <= 0 then ws[2][2] = nil end
      if room[4] <= 0 then ws[3][2] = nil end
      if room[6] <= 0 then ws[4][2] = nil end
    end
    drawView(ui, 'rs', sideArea, sm, ws, th, { noseX = 14 })
    ui.text('rs_title', 'Seitenansicht · vorn ist rechts · Höhe nach oben')
  end
  return tm, sm
end

-- names of all room controls (to show/hide them as a set)
function RM.names(withSide)
  local out = {}
  for _, pre in ipairs(withSide and { 'rt', 'rs' } or { 'rt' }) do
    for _, n in ipairs({ '_floor', '_lis', '_nose', '_scale', '_wl', '_wr', '_wf', '_wb', '_wt', '_wbo', '_title', '_bg' }) do
      out[#out + 1] = pre .. n
    end
  end
  return out
end
RM.ZOOM_CTL = { 'rz_big', 'rz_big_bg', 'rz_big_lbl', 'rz_minus', 'rz_minus_bg', 'rz_minus_lbl', 'rz_fit', 'rz_fit_bg', 'rz_fit_lbl', 'rz_plus', 'rz_plus_bg', 'rz_plus_lbl' }
function RM.button(name)          -- true if it was a zoom button
  if name == 'rz_minus' then RM.zoomStep(-1) elseif name == 'rz_plus' then RM.zoomStep(1)
  elseif name == 'rz_fit' then RM.zoomFit()
  elseif name == 'rz_big' then RM.big = not RM.big else return false end
  return true
end
function RM.gridNames(pre)
  local out = {}
  for i = 1, RM.GRID do out[#out + 1] = pre .. '_gx' .. i; out[#out + 1] = pre .. '_gy' .. i end
  return out
end
function RM.fmtPos(o) return (string.format('X %+.1f  Y %+.1f  Z %+.1f m', o.rx or 0, o.ry or 0, o.rz or 0):gsub('%.', ',')) end
