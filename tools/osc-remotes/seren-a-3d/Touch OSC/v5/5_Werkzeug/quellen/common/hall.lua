--------------------------------------------------------------------------
-- HALL-REITER (v8.20, gemeinsam: iPad + Monitor)
-- Reiter „FDN“ und „mcfx“ zeigen die SENDS, die in einen Hall-Plugin-Instanz laufen:
-- Objektplätze = Quellspuren, Pegel = was am Hall ankommt, dazu Gesamtpegel des Halls.
-- DAW -> Oberfläche: 24 <art> <instanz> <anzahl> <spurname>, 25 <pegel 0-127>, 26 <obj> <send 0-127 = -60..+12 dB> <stumm>, 27 <preset>
-- Oberfläche -> DAW: 0x18 <art 0 = Spuren, 1 FDN, 2 mcfx> <instanz>
--------------------------------------------------------------------------
HL = { kind = 0, inst = 0, n = 0, name = '', preset = '', tot = 0, want = 0, sentKey = nil }
HALLCAP = { fdn = 'FDN-Reverb', mcfx = 'mcfx-Convolver' }
function hallMode(m) return HALL_KIND[m] or 0 end
function hallText(m, from)
  local t = {}
  for i = from, #m - 1 do if m[i] >= 32 and m[i] <= 126 then t[#t + 1] = string.char(m[i]) end end
  return table.concat(t)
end
function sendDb(v) return -60 + (v / 127) * 72 end
function hallSendText(o)
  if not o or o.sv == nil then return '' end
  if o.smute then return 'Send stumm' end
  return string.format('Send %+.1f dB', sendDb(o.sv))
end
-- gibt true zurück, wenn die Nachricht ein Hall-Befehl war
function hallSysex(m, obj, N)
  local cmd = m[4]
  if cmd == 24 and m[7] then
    HL.kind, HL.inst, HL.n, HL.name = m[5], m[6], m[7], hallText(m, 8)
    if HL.kind ~= 0 then HL.want = HL.inst end
    return true
  elseif cmd == 25 and m[5] then HL.tot = m[5] / 127; return true
  elseif cmd == 26 and m[7] then
    local o = obj[m[5] + 1]
    if m[5] < N and o then o.sv, o.smute = m[6], m[7] == 1 end
    return true
  elseif cmd == 27 then HL.preset = hallText(m, 5); return true
  end
  return false
end
-- Auswahl an die DAW (nur bei Änderung, nur Reaper kennt Hall-Reiter)
function hallSelect(m, daw, send)
  if daw ~= 'REAPER' then return end
  local kind = hallMode(m)
  local inst = (kind ~= 0) and HL.want or 0
  local key = kind .. ',' .. inst
  if key == HL.sentKey then return end
  HL.sentKey = key
  send({ 0xF0, 0x7D, 0x4F, 0x18, kind, inst, 0xF7 })
end
function hallSub()
  if HL.n == 0 then return 'kein Hall dieser Art im Projekt' end
  local s = HL.name ~= '' and HL.name or ''
  if HL.preset ~= '' then s = s .. (s ~= '' and '  ·  ' or '') .. 'Preset ' .. HL.preset end
  return s
end

-- Zeichnen (E: C, setText, setVisible, setColor, slotK, present, obj, N, lvPos, lvHold, mode, dt, t aus dem Root-Skript)
local HC_PARTS = { '_sb', '_s', '_z', '_lb', '_l', '_h', '_n', '_d' }
local function hclamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function hallRender(E)
  local C, setText, setVisible, setColor, obj, present = E.C, E.setText, E.setVisible, E.setColor, E.obj, E.present
  local th = theme()
  setText('hall_title', '✧ ' .. HALLCAP[E.mode] .. ' ✧')
  setText('hall_sub', hallSub())
  for n = 1, 6 do
    local on, act = HL.n >= 2 and n <= HL.n, (n - 1 == HL.want)
    for _, sfx in ipairs({ '_bg', '_lbl', '' }) do setVisible('hall_i' .. n .. sfx, on) end
    if on then
      setColor('hall_i' .. n .. '_bg', act and th.accent or th.pill, 1)
      local c = C('hall_i' .. n .. '_lbl')
      if c then local tc = act and { 0.14, 0.06, 0.25 } or th.text; c.textColor = Color(tc[1], tc[2], tc[3], 1) end
    end
  end
  local v, pos, _, hp = lvStep('hall', HL.tot, E.dt, E.t)
  local bg, bar, hb = C('hall_totbg'), C('hall_tot'), C('hall_hold')
  if bg and bar then
    local f = bg.frame
    bar.frame = Rectangle(f.x, f.y, math.max(0, f.w * hclamp(pos, 0, 1)), f.h)
    local mc = meterColor(pos); bar.color = Color(mc[1], mc[2], mc[3], 0.95)
    if hb then
      hb.frame = Rectangle(f.x + f.w * hclamp(hp, 0, 1) - 1, f.y, 2, f.h)
      local hc = th.meterHold; hb.color = Color(hc[1], hc[2], hc[3], 0.9)
    end
  end
  setText('hall_db', lvFormat(v))
  local cnt, mut = 0, 0
  for k = 1, E.N do if present(k) then cnt = cnt + 1; if obj[k].smute then mut = mut + 1 end end end
  setText('hall_cnt', cnt .. (cnt == 1 and ' Send' or ' Sends') .. (mut > 0 and (' · ' .. mut .. ' stumm') or ''))
  for i = 1, 16 do
    local k = E.slotK[i]
    local on = k ~= nil and present(k)
    for _, sfx in ipairs(HC_PARTS) do setVisible('hc' .. i .. sfx, on) end
    local sb, sf, lb, lf, hh = C('hc' .. i .. '_sb'), C('hc' .. i .. '_s'), C('hc' .. i .. '_lb'), C('hc' .. i .. '_l'), C('hc' .. i .. '_h')
    if on and sb and sf and lb and lf then
      local o = obj[k]
      local f, p = sb.frame, hclamp((o.sv or 0) / 127, 0, 1)
      sf.frame = Rectangle(f.x, f.y + f.h * (1 - p), f.w, math.max(1, f.h * p))
      local a2 = th.accent2; sf.color = Color(a2[1], a2[2], a2[3], o.smute and 0.22 or 0.95)
      local g, lp = lb.frame, o.smute and 0 or (E.lvPos[k] or 0)
      lf.frame = Rectangle(g.x, g.y + g.h * (1 - lp), g.w, math.max(1, g.h * lp))
      local mc = meterColor(lp); lf.color = Color(mc[1], mc[2], mc[3], 0.95)
      if hh then
        hh.frame = Rectangle(g.x, g.y + g.h * (1 - hclamp(o.smute and 0 or (E.lvHold[k] or 0), 0, 1)) - 1, g.w, 2)
        local hc = th.meterHold; hh.color = Color(hc[1], hc[2], hc[3], 0.9)
      end
      setText('hc' .. i .. '_n', abbr(o.name, 6))
      setText('hc' .. i .. '_d', o.smute and 'stumm' or string.format('%+.0f', sendDb(o.sv or 0)))
    end
  end
end
