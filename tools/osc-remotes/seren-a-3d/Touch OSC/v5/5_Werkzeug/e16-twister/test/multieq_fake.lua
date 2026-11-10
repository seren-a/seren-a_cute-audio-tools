-- A fake IEM MultiEQ for the Reaper mock: 6 bands x (enable, type, frequency, Q, gain) + Reaper's
-- Bypass/Wet/Delta. Scaling like JUCE: value = lo + (hi-lo) * n^(1/skew), snapped to an interval.
local function range(lo, hi, skew, iv, fmt)
  local function conv(n) return lo + (hi - lo) * (n <= 0 and 0 or math.exp(math.log(n) / skew)) end
  local function inv(v) local x = (v - lo) / (hi - lo); return x <= 0 and 0 or math.exp(skew * math.log(x)) end
  local function snap(n)
    local v = math.floor(conv(n) / iv + 0.5) * iv
    if v < lo then v = lo elseif v > hi then v = hi end
    local r = inv(v)
    return r < 0 and 0 or r > 1 and 1 or r
  end
  return conv, inv, snap, function(n) return fmt(conv(n)) end
end

function MultiEQ(name, guid, freqs)
  local params = {}
  local types = { "HP", "Peak", "Peak", "Peak", "Peak", "LP" }
  for b = 1, 6 do
    local fc, fi, fs, ff = range(20, 20000, 0.2, 1, function(v) return string.format("%d Hz", math.floor(v + 0.5)) end)
    local qc, qi, qs, qf = range(0.05, 8, 0.3, 0.01, function(v) return string.format("%.2f", v) end)
    local gc, gi, gs, gf = range(-60, 15, 1, 0.1, function(v) return string.format("%.1f dB", v) end)
    params[#params + 1] = { name = "Enable Filter " .. b, v = 1, fmt = function(n) return n >= 0.5 and "on" or "off" end,
      snap = function(n) return n >= 0.5 and 1 or 0 end }
    params[#params + 1] = { name = "Filter Type " .. b, v = 0.34, fmt = function() return types[b] end }
    params[#params + 1] = { name = "Filter Frequency " .. b, v = fi(freqs[b]), fmt = ff, snap = fs, conv = fc }
    params[#params + 1] = { name = "Filter Q " .. b, v = qi(0.71), fmt = qf, snap = qs, conv = qc }
    params[#params + 1] = { name = "Filter Gain " .. b, v = gi(0), fmt = gf, snap = gs, conv = gc }
  end
  for _, n in ipairs({ "Bypass", "Wet", "Delta" }) do
    params[#params + 1] = { name = n, v = 0, fmt = function(x) return string.format("%.2f", x) end }
  end
  return { name = name, guid = guid, params = params }
end

-- real value of band b's kind ("Frequency", "Q", "Gain") in an instance
function REAL(fx, b, kind)
  for _, p in ipairs(fx.params) do
    if p.name == "Filter " .. kind .. " " .. b then return p.conv(p.v) end
  end
end
function ENABLED(fx, b) return fx.params[(b - 1) * 5 + 1].v >= 0.5 end

local function cont(name, lo, hi, skew, iv, unit, v)
  local c, i, sn, f = (function()
    local function conv(n) return lo + (hi - lo) * (n <= 0 and 0 or math.exp(math.log(n) / skew)) end
    local function inv(x) local y = (x - lo) / (hi - lo); return y <= 0 and 0 or math.exp(skew * math.log(y)) end
    local function snap(n) local x = math.floor(conv(n) / iv + 0.5) * iv; x = math.max(lo, math.min(hi, x)); return math.max(0, math.min(1, inv(x))) end
    return conv, inv, snap, function(n) return string.format(iv >= 1 and "%d%s" or "%.1f%s", iv >= 1 and math.floor(conv(n) + 0.5) or conv(n), unit) end
  end)()
  return { name = name, v = i(v), fmt = f, snap = sn, conv = c }
end
local function choice(name, opts, k)
  local n = #opts
  return { name = name, v = (k - 1) / (n - 1), fmt = function(x) return opts[math.floor(x * (n - 1) + 0.5) + 1] end,
    snap = function(x) return math.floor(x * (n - 1) + 0.5) / (n - 1) end }
end
local function bool(name, on) return { name = name, v = on and 1 or 0, fmt = function(x) return x >= 0.5 and "on" or "off" end,
  snap = function(x) return x >= 0.5 and 1 or 0 end } end

function OmniComp(guid)
  return { name = "VST3: OmniCompressor (IEM)", guid = guid, params = {
    choice("Ambisonics Order", { "Auto", "0th", "1st", "2nd" }, 1), choice("Normalization", { "N3D", "SN3D" }, 2),
    cont("Threshold", -50, 10, 1, 0.1, " dB", -10), cont("Knee", 0, 30, 1, 0.1, " dB", 0),
    cont("Attack Time", 0, 100, 1, 0.1, " ms", 30), cont("Release Time", 0, 500, 1, 0.1, " ms", 150),
    cont("Ratio", 1, 16, 0.5, 0.1, " : 1", 4), cont("Output Gain", -10, 20, 1, 0.1, " dB", 0),
    bool("LookAhead", false), bool("Report Latency", false), { name = "Bypass", v = 0, fmt = function(x) return "" .. x end } } }
end

function DirComp(guid)
  local ps = { choice("Ambisonics Order", { "Auto", "0th", "1st" }, 1), choice("Normalization", { "N3D", "SN3D" }, 2),
    cont("Input Gain", -10, 10, 1, 0.1, " dB", 0) }
  for c = 1, 2 do
    local add = { bool("Enable Compression Stage " .. c, true),
      choice("Compression Driving Signal " .. c, { "Full", "Masked", "Unmasked" }, 1),
      choice("Apply compression to " .. c, { "Full", "Masked", "Unmasked" }, 1),
      cont("Threshold " .. c, -50, 10, 1, 0.1, " dB", -10), cont("Knee " .. c, 0, 10, 1, 0.1, " dB", 0),
      cont("Attack Time " .. c, 0, 100, 1, 0.1, " ms", 30), cont("Release Time " .. c, 0, 500, 1, 0.1, " ms", 150),
      cont("Ratio " .. c, 1, 16, 0.5, 0.1, " : 1", 4), cont("MakeUp Gain " .. c, -10, 20, 1, 0.1, " dB", 0) }
    for _, x in ipairs(add) do ps[#ps + 1] = x end
  end
  for _, x in ipairs({ cont("Azimuth of mask", -180, 180, 1, 0.1, " deg", 0), cont("Elevation of mask", -180, 180, 1, 0.1, " deg", 0),
    cont("Width of mask", 10, 180, 1, 0.1, " deg", 60), choice("Listen to", { "Full", "Masked", "Unmasked" }, 1) }) do ps[#ps + 1] = x end
  return { name = "VST3: DirectionalCompressor (IEM)", guid = guid, params = ps }
end

function PV(fx, name) for _, p in ipairs(fx.params) do if p.name == name then return p.conv and p.conv(p.v) or p.v end end end
function PT(fx, name) for _, p in ipairs(fx.params) do if p.name == name then return p.fmt(p.v) end end end

-- v6.0 Hall: IEM FdnReverb and an mcfx convolver (2 own parameters + Reaper's Bypass/Wet/Delta)
function FdnReverb(guid)
  return { name = "VST3: FdnReverb (IEM)", guid = guid, params = {
    cont("Room Size", 1, 30, 1, 0.1, " m", 10), cont("Reverberation Time", 0.1, 9, 0.5, 0.01, " s", 2),
    cont("Lows Cutoff Frequency", 20, 20000, 0.2, 1, " Hz", 100), cont("Lows Q Factor", 0.01, 0.9, 1, 0.01, "", 0.5),
    cont("Lows Gain", -80, 6, 1, 0.1, " dB", 0), cont("Highs Cutoff Frequency", 20, 20000, 0.2, 1, " Hz", 2000),
    cont("Highs Q Factor", 0.01, 0.9, 1, 0.01, "", 0.5), cont("Highs Gain", -80, 4, 1, 0.1, " dB", 0),
    cont("Dry/Wet", 0, 1, 1, 0.01, "", 0.5), cont("Fade-in Time", 0, 0.5, 1, 0.01, " s", 0),
    choice("Feedback Network Size", { "16", "32", "64" }, 2),
    { name = "Bypass", v = 0, fmt = function(x) return "" .. x end }, { name = "Wet", v = 1, fmt = function(x) return "" .. x end },
    { name = "Delta", v = 0, fmt = function(x) return "" .. x end } } }
end
function Convolver(guid)
  return { name = "VST: mcfx_convolver8 (mcfx)", guid = guid, params = {
    cont("Master Gain", -60, 12, 1, 0.1, " dB", 0), cont("Pre-Delay", 0, 500, 1, 1, " ms", 0),
    { name = "Bypass", v = 0, fmt = function(x) return "" .. x end }, { name = "Wet", v = 1, fmt = function(x) return "" .. x end },
    { name = "Delta", v = 0, fmt = function(x) return "" .. x end } } }
end
