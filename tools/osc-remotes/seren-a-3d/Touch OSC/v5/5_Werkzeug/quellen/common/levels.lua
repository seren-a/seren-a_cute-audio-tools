--------------------------------------------------------------------------
-- PEGEL (gemeinsam: IEM space iPad + IEM monitor 5:4)
-- Die DAW schickt pro Spur einen Spitzenpegel 0..127 = -60..0 dBFS (Kanal 15, CC = Objekt).
-- Hier wird daraus die Anzeige: Skala, Peak/RMS/Lautheit, Rücklauf, Halten, Glühen.
-- Skalen und Begriffe wie in SuperVision (Steinberg): Digital, DIN, EBU, British, Nordic,
-- K-20/14/12, dazu LUFS/LU. LUFS/LU sind hier eine NÄHERUNG: ohne K-Filter und aus den
-- Meterwerten der DAW gerechnet (ca. 30 Werte/s), nicht aus dem Audiosignal.
--------------------------------------------------------------------------
local LV = {
  scale = 'digital',   -- digital din ebu british nordic k20 k14 k12 lufs lu
  mode = 'peak',       -- peak rms (bei lufs/lu automatisch: Lautheit M = 400 ms bzw. S = 3 s)
  aes17 = false,       -- RMS +3 dB (AES17)
  rmsMs = 300,         -- RMS-Auflösung (Integrationszeit), 50..3000 ms
  loud = 'M',          -- M (400 ms) oder S (3 s)
  fallback = 13.3,     -- Rücklauf dB/s (IEC 60268-10 Typ I: 20 dB in 1,5 s)
  holdMs = 1500,       -- Spitzenwert halten, 0..5000 ms (0 = aus)
  target = -23,        -- LU-Bezug: -23 EBU R128, -24 ATSC A/85, -16, -14 (Streaming)
  attackMs = 10,       -- Glühen: Anstieg (wie SuperVision Ambisonics: Attack)
  releaseMs = 600,     -- Glühen: Abfall (Release)
  threshold = -60,     -- darunter leuchtet nichts
}
-- Anzeige-Bereich je Skala: Bezugspegel in dBFS, unten/oben relativ dazu, Einheit
local SCALES = {
  digital = { name = 'Digital', ref = 0,   lo = -60, hi = 0,  unit = 'dBFS' },
  din     = { name = 'DIN',     ref = -9,  lo = -50, hi = 5,  unit = 'dB' },
  ebu     = { name = 'EBU',     ref = -18, lo = -12, hi = 12, unit = 'dB' },
  british = { name = 'British', ref = -18, lo = -12, hi = 12, unit = 'PPM' },  -- Marke 4 = -18 dBFS, 4 dB/Marke
  nordic  = { name = 'Nordic',  ref = -18, lo = -36, hi = 9,  unit = 'dB' },
  k20     = { name = 'K-20',    ref = -20, lo = -40, hi = 20, unit = 'dB' },
  k14     = { name = 'K-14',    ref = -14, lo = -40, hi = 14, unit = 'dB' },
  k12     = { name = 'K-12',    ref = -12, lo = -40, hi = 12, unit = 'dB' },
  lufs    = { name = 'LUFS≈',   ref = 0,   lo = -60, hi = 0,  unit = 'LUFS' },
  lu      = { name = 'LU≈',     ref = nil, lo = -18, hi = 9,  unit = 'LU' },   -- EBU +9-Skala
}
local SCALE_ORDER = { 'digital', 'din', 'ebu', 'british', 'nordic', 'k20', 'k14', 'k12', 'lufs', 'lu' }
local FALLBACKS = {   -- Rücklauf-Vorgaben (IEC 60268-10 / IEC 60268-17)
  { name = 'Typ I (DIN/Nordic)', v = 13.3 },   -- 20 dB in 1,5 s
  { name = 'Typ IIa (EBU/BBC)', v = 8.6 },     -- 24 dB in 2,8 s
  { name = 'Digital schnell', v = 26 },
  { name = 'VU (300 ms)', v = 0 },              -- 0 = VU-Ballistik statt Rücklauf
}

local LVS = {}        -- je Objekt: env, holdV, holdT, rms, lm, ls, glow
local function lvState(k)
  local s = LVS[k]
  if not s then s = { env = -120, holdV = -120, holdT = 0, rms = 1e-12, lm = 1e-12, ls = 1e-12, vu = -120, glow = 0 }; LVS[k] = s end
  return s
end
local function lvReset() LVS = {} end
local function pow10(x) return 10 ^ (x / 10) end
local LOG10 = math.log10 or function(x) return math.log(x) / math.log(10) end
local function db10(p) return 10 * LOG10(math.max(p, 1e-12)) end
local function avg(a, x, tau, dt) return a + (x - a) * (1 - math.exp(-dt / math.max(tau, 0.001))) end

-- in: 0..1 (= -60..0 dBFS), dt in s, now in ms. Out: Wert in Skaleneinheit, Position 0..1, Glühen 0..1, Halte-Position
local function lvStep(k, in01, dt, now)
  local s = lvState(k)
  local x = (in01 > 0) and (in01 * 60 - 60) or -120
  -- Peak mit Rücklauf / VU
  if LV.fallback > 0 then
    if x >= s.env then s.env = x else s.env = math.max(x, s.env - LV.fallback * dt) end
  else
    s.env = db10(avg(pow10(s.env), pow10(x), 0.3, dt))
  end
  if x >= s.holdV or LV.holdMs <= 0 then s.holdV, s.holdT = x, now
  elseif now - s.holdT > LV.holdMs then s.holdV = math.max(s.env, s.holdV - math.max(LV.fallback, 8.6) * dt) end
  -- Leistungsmittel
  local p = pow10(x)
  s.rms = avg(s.rms, p, LV.rmsMs / 1000, dt)
  s.lm = avg(s.lm, p, 0.4, dt)
  s.ls = avg(s.ls, p, 3.0, dt)
  local sc = SCALES[LV.scale] or SCALES.digital
  local dbfs
  if LV.scale == 'lufs' or LV.scale == 'lu' then
    dbfs = db10(LV.loud == 'S' and s.ls or s.lm)
  elseif LV.mode == 'rms' then
    dbfs = db10(s.rms) + (LV.aes17 and 3.01 or 0)
  else
    dbfs = s.env
  end
  local ref = sc.ref or LV.target
  local v, hv = dbfs - ref, s.holdV - ref
  local pos = math.max(0, math.min(1, (v - sc.lo) / (sc.hi - sc.lo)))
  local hpos = math.max(0, math.min(1, (hv - sc.lo) / (sc.hi - sc.lo)))
  -- Glühen: eigene Attack/Release-Glättung, unter der Schwelle aus
  local g = (dbfs > LV.threshold) and pos or 0
  local tau = (g > s.glow) and LV.attackMs / 1000 or LV.releaseMs / 1000
  s.glow = avg(s.glow, g, tau, dt)
  return v, pos, s.glow, hpos
end

local function lvFormat(v)
  local sc = SCALES[LV.scale] or SCALES.digital
  if v < sc.lo - 0.5 then return '–' end
  if LV.scale == 'british' then return string.format('%.1f', 4 + v / 4) end   -- PPM-Marken
  return string.format('%+.1f %s', v, sc.unit)
end
local function lvDescribe()
  local sc = SCALES[LV.scale] or SCALES.digital
  local m
  if LV.scale == 'lufs' or LV.scale == 'lu' then m = (LV.loud == 'S') and 'Short-term 3 s' or 'Momentary 400 ms'
  elseif LV.mode == 'rms' then m = 'RMS ' .. LV.rmsMs .. ' ms' .. (LV.aes17 and ' +3 dB AES17' or '')
  else m = (LV.fallback > 0) and string.format('Peak, Rücklauf %.1f dB/s', LV.fallback) or 'VU 300 ms' end
  local t = (LV.scale == 'lu') and string.format(', Ziel %d LUFS', LV.target) or ''
  return sc.name .. ' · ' .. m .. t
end
