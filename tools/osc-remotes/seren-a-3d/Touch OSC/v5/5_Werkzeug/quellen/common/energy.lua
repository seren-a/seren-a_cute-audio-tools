--------------------------------------------------------------------------
-- ENERGIE-REITER (v8.22, gemeinsam: iPad + Monitor)
-- Energiekarte der Ambisonics-Spur (Ansicht Azimut x Elevation, links = +180 Grad, oben = +90 Grad), gerechnet vom JSFX
-- „seren.a 3D Energy“ aus den bis zu 16 Kanälen (die Zeichnung des IEM EnergyVisualizer selbst lässt sich nicht auslesen).
-- DAW -> Oberfläche: 28 <zeile 0-11> <24 Werte 0-127 = -80..+10 dB>,
--                    29 <status 0 kein JSFX, 1 läuft, 2 keine Daten> <skala 0 Standard, 1 aus IEM-Plugin> <peak+64 dB> <bereich dB>
--                       <ordnung 0-3> <gesamt 0-127 = -60..0 dB> <spurname>
-- Oberfläche -> DAW: 0x18 3 0 (wie die Hall-Reiter: Reiter „energy“ gewählt, die DAW fängt an zu senden)
--------------------------------------------------------------------------
EN_ROWS, EN_COLS, EN_DB0, EN_DB1 = 12, 24, -80, 10
EN = { srcSel = 0, ver = 0, drawn = nil, st = 0, src = 0, peak = 0, range = 35, ord = 0, tot = 0, name = '', rows = {}, manual = false, mpeak = 0, mrange = 35 }
HALLCAP.en = 'Energie'
function energyReset() EN.st, EN.rows, EN.name = 0, {}, ''; EN.ver = EN.ver + 1 end
function energySysex(m)
  local cmd = m[4]
  if cmd == 28 and m[5] and m[5] < EN_ROWS and m[5 + EN_COLS] then
    local r = {}
    for c = 1, EN_COLS do r[c] = m[5 + c] end
    EN.rows[m[5] + 1] = r; EN.ver = EN.ver + 1
    return true
  elseif cmd == 29 and m[10] then
    EN.st, EN.src, EN.peak, EN.range, EN.ord, EN.tot = m[5], m[6], m[7] - 64, math.max(1, m[8]), m[9], m[10] / 127
    EN.name = hallText(m, 11)
    if EN.st == 0 then EN.rows = {} end
    EN.ver = EN.ver + 1; EN.force = true
    return true
  end
  return false
end
function eclamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function elerp(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
function energyScale()                                    -- Peak-Pegel und Dynamikbereich (wie im IEM EnergyVisualizer)
  if EN.manual then return EN.mpeak, EN.mrange end
  return EN.peak, EN.range
end
function energyColor(p, th)                               -- 0..1 -> dunkel, cyan, pink, gold
  local c0, c1, c2, c3 = th.row, elerp(th.row, th.accent2, 0.75), th.accent, th.meterHot
  if p < 0.34 then return elerp(c0, c1, p / 0.34)
  elseif p < 0.67 then return elerp(c1, c2, (p - 0.34) / 0.33) end
  return elerp(c2, c3, (p - 0.67) / 0.33)
end
function cellDb(v) return EN_DB0 + v / 127 * (EN_DB1 - EN_DB0) end
function energyButton(name)                               -- true, wenn es eine Taste des Energie-Reiters war
  local pk, rg = energyScale()
  local function manual() if not EN.manual then EN.manual, EN.mpeak, EN.mrange = true, pk, rg end end
  if name == 'en_pk_dn' then manual(); EN.mpeak = eclamp(EN.mpeak - 5, -60, 20)
  elseif name == 'en_pk_up' then manual(); EN.mpeak = eclamp(EN.mpeak + 5, -60, 20)
  elseif name == 'en_rg_dn' then manual(); EN.mrange = eclamp(EN.mrange - 5, 10, 80)
  elseif name == 'en_rg_up' then manual(); EN.mrange = eclamp(EN.mrange + 5, 10, 80)
  elseif name == 'en_auto' then EN.manual = false
  elseif name == 'en_src0' or name == 'en_src1' then EN.srcSel = (name == 'en_src1') and 1 or 0   -- v8.22.6: Quelle
  else return false end
  EN.ver = EN.ver + 1; EN.force = true
  return true
end
function energySub()
  if EN.st == 0 then return EN.srcSel == 1 and 'kein „seren.a 3D Energy“ auf dem Master' or 'kein „seren.a 3D Energy“ auf der gewählten Spur oder dem Master' end
  local s = 'Spur ' .. (EN.name ~= '' and EN.name or '?')
  if EN.st == 2 then return s .. '  ·  keine Daten (Wiedergabe oder Eingang?)' end
  return s .. '  ·  ' .. EN.ord .. '. Ordnung'
end
function energyRender(E)
  local C, setText, setVisible, setColor = E.C, E.setText, E.setVisible, E.setColor
  local th = theme()
  local t = E.t or 0                                        -- v8.22.2: nur bei neuen Daten/Palette neu zeichnen, höchstens 10x pro Sekunde
  if EN.drawn == EN.ver and EN.drawnTh == th and t - (EN.drawT or -1e9) < 1000 then return end   -- (TouchOSC: „Too many cycles“)
  if t - (EN.drawT or -1e9) < 100 and not EN.force then return end
  EN.force = false
  EN.drawn, EN.drawnTh, EN.drawT = EN.ver, th, t
  setText('en_title', '✧ Energie ✧')
  setText('en_sub', energySub())
  local pk, rg = energyScale()
  local lo = pk - rg
  local live = EN.st ~= 0
  local best, bi, bj = -1e9, nil, nil
  for r = 1, EN_ROWS do
    local row = EN.rows[r]
    for c = 1, EN_COLS do
      local nm = 'ec' .. (r - 1) .. '_' .. (c - 1)
      local v = live and row and row[c] or nil
      local p = 0
      if v then
        local db = cellDb(v)
        p = eclamp((db - lo) / rg, 0, 1)
        if db > best then best, bi, bj = db, r, c end
      end
      local col = energyColor(p, th)
      setColor(nm, col, v and 1 or 0.5)
    end
  end
  local mp, ml = C('en_map'), C('en_peak')
  if bi and mp and ml then
    local f = mp.frame
    local cw, ch = f.w / EN_COLS, f.h / EN_ROWS
    local sz = ml.frame.w
    ml.frame = Rectangle(f.x + (bj - 0.5) * cw - sz / 2, f.y + (bi - 0.5) * ch - sz / 2, sz, sz)
    setVisible('en_peak', true)
    local az, el = 180 - (bj - 0.5) * 15, 90 - (bi - 0.5) * 15
    setText('en_peaklbl', string.format('Maximum  Az %+.0f°  El %+.0f°   %+.1f dB', az, el, best))
  else
    setVisible('en_peak', false); setText('en_peaklbl', '')
  end
  setText('en_tot', live and EN.st == 1 and string.format('gesamt %.1f dB RMS', EN.tot * 60 - 60) or '')
  for i = 1, 16 do setColor('en_lg' .. i, energyColor((i - 0.5) / 16, th), 1) end
  setText('en_lgmin', string.format('%.0f dB', lo)); setText('en_lgmax', string.format('%.0f dB', pk))
  setText('en_pk_val', string.format('Peak %+.0f dB', pk)); setText('en_rg_val', string.format('Bereich %.0f dB', rg))
  local src = EN.manual and 'manuell' or (EN.src == 1 and 'aus dem IEM EnergyVisualizer' or 'Standard (kein EnergyVisualizer auf der Spur)')
  setText('en_scale', 'Skala: ' .. src)
  setColor('en_auto_bg', EN.manual and th.pill or th.accent, 1)
  for i = 0, 1 do                                         -- v8.22.6: Quelle gewählte Spur / Master
    local on = (EN.srcSel == i)
    setColor('en_src' .. i .. '_bg', on and th.accent or th.pill, 1)
    local lc = C('en_src' .. i .. '_lbl')
    if lc then local tc = on and { 0.14, 0.06, 0.25 } or th.text; lc.textColor = Color(tc[1], tc[2], tc[3], 1) end
  end
  local c = C('en_auto_lbl')
  if c then local tc = EN.manual and th.text or { 0.14, 0.06, 0.25 }; c.textColor = Color(tc[1], tc[2], tc[3], 1) end
end

-- v8.22.7: Energie als Feld der Split-Ansicht (Monitor): grobe Karte 12 x 6 (je 2 x 2 Felder der 24 x 12, das lauteste zählt)
ES = { key = nil, drawn = nil, drawnTh = nil, drawT = -1e9 }
function energySplitRender(E, f, q)
  local setVisible, setColor, setFrame, setText = E.setVisible, E.setColor, E.setFrame, E.setText
  local th = theme()
  setVisible('spe_g', true); setVisible('spe_sub', true)
  local fk = string.format('%.0f,%.0f,%.0f,%.0f', f.x, f.y, f.w, f.h)
  if ES.key ~= fk then                                 -- Rahmen und Felder nur bei neuer Lage setzen; gezeichnet wird im nächsten Frame
    ES.key = fk; ES.drawn = nil; ES.drawT = -1e9
    setFrame('spe_g', f.x, f.y, f.w, f.h)
    local cw, ch = f.w / 12, f.h / 6
    for r = 0, 5 do for c = 0, 11 do setFrame('se' .. r .. '_' .. c, c * cw + 0.5, r * ch + 0.5, cw - 1, ch - 1) end end
    setFrame('spe_frame', 0, 0, f.w, f.h)
    setFrame('spe_sub', q.x + 12, f.y + f.h + 2, q.w - 24, 18)
    return
  end
  local t = E.t or 0
  if ES.drawn == EN.ver and ES.drawnTh == th and t - ES.drawT < 1000 then return end
  if t - ES.drawT < 100 and ES.drawnTh == th then return end
  ES.drawn, ES.drawnTh, ES.drawT = EN.ver, th, t
  setText('spe_sub', energySub())
  setColor('spe_frame', th.accent, 1)
  local pk, rg = energyScale()
  local lo = pk - rg
  local live = EN.st ~= 0
  local E0 = {}
  for r = 0, 5 do
    local ra, rb = live and EN.rows[2 * r + 1] or E0, live and EN.rows[2 * r + 2] or E0
    for c = 0, 11 do                                   -- je 2 x 2 Felder: das lauteste (billiger als Leistungsmittel; TouchOSC „Too many cycles“)
      local j = 2 * c + 1
      local v = ra[j]
      local w = ra[j + 1]; if w and (not v or w > v) then v = w end
      w = rb[j]; if w and (not v or w > v) then v = w end
      w = rb[j + 1]; if w and (not v or w > v) then v = w end
      local p = v and eclamp((cellDb(v) - lo) / rg, 0, 1) or 0
      setColor('se' .. r .. '_' .. c, energyColor(p, th), v and 1 or 0.5)
    end
  end
end
