-- Reaper_E16_Twister.lua · seren.a 3D v8.0 (was Reaper_MultiEQ.lua + reaper_to_e16.lua + e16-reverb-remote)
-- v8.0: E16 page 1 (DAW Link) in Reaper = Sends / Ziele / Spur / Menü (hold 16 = next sub-page),
--   Twister bank 4 layer 6 "Sends" (encoder 8 turn = next group, hold = next layer), settings in
--   Reaper_E16_Einstellungen.lua or on the E16 menu page. reaper_to_e16.lua and e16-reverb-remote must not run.
-- IEM MultiEQ, OmniCompressor, DirectionalCompressor, FDN Reverb + mcfx convolver on Midi Fighter Twister bank 4 and on the
-- OXI E16 scene "MultiEQ" (E16_MultiEQ.lua / MultiEQ.oxie16), plus track selection, master, mute, solo.
--
-- Four layers: Twister bank 4 = MultiEQ -> Omni -> Directional -> Hall (hold encoder 8 for 0.45 s and
-- let go without turning). E16: page 1 = MultiEQ, page 3 = Omni -> Directional -> Hall (hold encoder 8).
--
-- On every layer
--   8   press = OmniCompressor A on/off (bypass)            hold + let go = next layer
--   15  press = solo of the selected track (blinks yellow; orange = not soloed but muted)
--       press + turn = SceneRotator yaw (selected track, master, monitoring FX, tracks; else an AmbiDecoder)
--   16  turn = select the next / previous track · press + turn = master volume (-30 .. 0 dB)
--       press = mute the selected track (blinks red); acts on letting go, so press + turn never mutes
-- MultiEQ layer (MultiEQ: the first two found on master, monitoring FX, tracks from the top)
--   two MultiEQ: 1-3 = A band 1-3, 5-7 = A band 4-6, 9-14 = B band 1-6
--   with DirectionalCompressor + MultiEQ + OmniCompressor all there: the top row is the compressor,
--     1-3 = compressor 1, 5-7 = compressor 2: turn threshold / ratio / makeup, press + turn knee /
--     attack / release (3 hold + turn = azimuth, 2x on 1 / 5 = compressor on/off); 9-14 = MultiEQ A band 1-6
--   EQ bands: turn = frequency · press + turn = gain · hold + turn = Q · 2x = band on/off · 3x = lock
--   4   DirectionalCompressor: turn = width · press + turn = both thresholds · hold + turn = both ratios
--   8   OmniCompressor A: turn = threshold · press + turn = makeup (output gain) · hold + turn = ratio
-- Omni layer: 1-7 = A, 9-14 = B: threshold, ratio, attack, release, knee, gain (7 = A look-ahead,
--   2x press or turn; 15 turn = B look-ahead)
-- Directional layer: 1-6 = compressor 1, 9-14 = compressor 2: threshold, ratio, attack, release, knee,
--   makeup (2x press: 1/9 on/off, 2/10 driving signal, 3/11 apply to) · 7 turn = azimuth,
--   press + turn = width, 2x press = listen · 8 turn = pre gain · 15 turn = elevation
-- v6.1: Omni layer 6/14 = makeup (2x = look-ahead), 7 press = A look-ahead, 8 turn = A makeup;
--   Hall 7 = FDN preset, 9-13 = convolver parameters 1-5, 14 = convolver preset (Reaper's preset list);
--   colours of the IEM plugins on Twister, Twister View and E16; threshold rings come from the top;
--   E16: one scene seren-a_E16.oxie16 (page 2 MultiEQ, 3 Omni <-> Directional, 4 Reverb).
-- Hall layer (v6.0): 1-6 = FDN Reverb: room size, reverb time, fade-in, dry/wet, low cut (press + turn:
--   low gain), high cut (press + turn: high gain) · 9-14 = mcfx convolver: its first 6 parameters
--   (the selected track's, else the master's)
-- Compressors: from the selected track. Omni: if the track has only one, B is the master's; none: the
-- master's. Directional: the track's, else the master's. One from the master shows in COL_MASTER (E16: white).
-- Turning a plugin's parameter opens its window (OPEN_WINDOWS); the one opened before closes.
--
-- Twister, bank 4 in the Midi Fighter Utility (all 16 encoders): Encoder MIDI type "ENC 3FH/41H",
-- movement Direct, channel 1, CC 49-64; switch action "CC Hold", channel 2, CC 49-64
-- (Twister_Bank4_MultiEQ.mfs). Reaper > Preferences > MIDI Devices: Twister and E16 in + out enabled.
-- NOT TESTED INSIDE REAPER: API calls checked against the API docs, logic against a mock.

-- ============================ CONFIGURATION ============================
local MFT_MATCH  = "Twister"           -- part of the Twister's MIDI port name
local E16_MATCH  = "E16"               -- part of the E16's MIDI port name
local VIEW_MATCH = "TouchOSC Bridge"   -- Twister View on the phone (optional)
local OPEN_WINDOWS = true              -- turning a plugin's parameter opens its window
local CLOSE_OTHERS = true              -- ... and closes the window the script opened before

local MFT_CC      = 49                 -- bank 4, encoder 1 (Utility: CC 49-64)
local MFT_TURN_CH = 0                  -- 0-based: channel 1 = turns
local MFT_PUSH_CH = 1                  -- channel 2 = pushes (CC Hold 127/0)
local MFT_COL_CH  = 1                  -- channel 2 to the Twister = RGB colour
local MFT_ANIM_CH = 2                  -- channel 3 to the Twister = RGB animation (strobe, pulse, brightness)
local MFT_RING_CH = 5                  -- channel 6 to the Twister = ring animation / brightness (Utility default)
local MFT_SYS_CH  = 3                  -- channel 4 = Twister bank buttons
local MFT_BANK    = 3                  -- 0-based: bank 4
-- Twister colours (classic colour map, Utility setting): 25 cyan, 45 green, 64 yellow, 69 orange, 81 red, 100 magenta,
-- 113 violet, 127 = the colour set in the Utility, 0 = the inactive colour (off)
local COL_MASTER  = 25                 -- compressor taken from the master
local LOCK_COLOR  = 113                -- locked EQ band
local COL_SOLO, COL_MUTE15, COL_MUTE = 64, 69, 81
local COL_MASTERVOL, DIM_MASTERVOL = 81, 22   -- encoder 16 while setting the master: red, dimmed (steady)
local DIM_OFF     = 19                 -- channel-3 value for "off" (band off, compressor off, Omni bypassed): dim
local PRESS_SETTLE = 0.08              -- s: turn ticks right after a press are ignored (the knob wobbles)
local LAYER_COL   = { 127, 45, 100, 13, 92, 1 }   -- encoder 8: MultiEQ, Omni, Directional, Hall, Hall-EQ, Sends (blue)
local BLINK       = 3                  -- channel-3 value: RGB strobe (1-8 = rates)
local Q_PULSE     = 11                 -- channel-3 value while holding (RGB pulse)
local SOLO_MODE   = 2                  -- I_SOLO when soloing: 1 = solo, 2 = solo in place

local E16_PAGE_EQ, E16_PAGE_COMP, E16_PAGE_REV = 1, 3, 4   -- pages as the scene announces them (seren_E16:
                                               -- E16 pages 2, 3, 4; page 1 DAW Link announces 127)
local E16_IN_EQ, E16_IN_COMP, E16_IN_REV = 12, 11, 10   -- 0-based: the scene sends on channel 13 / 12 / 11
-- IEM colours (as in the plugins' GUIs) on each device: Twister classic colour map, OXI App palette,
-- RGB for the Twister View
local IEM_HEX = { cyan = "00CAFE", green = "50FE03", orange = "FE9F01", red = "CF021C", white = "D9D9D9",
  eq1 = "5E9EA0", eq2 = "9370DB", eq3 = "6495ED", eq4 = "ADFF2F", eq5 = "FFFF00", eq6 = "FF4500",
  conv = "6495ED", solo = "FFFF00", mute = "FF4500", master = "02FFFF" }
local TW_KEY = { cyan = 20, green = 51, orange = 68, red = 83, white = 127, eq1 = 25, eq2 = 118, eq3 = 9, eq4 = 56,
  eq5 = 64, eq6 = 75, conv = 9, master = 25 }
local E16_KEY = { cyan = 83, green = 92, orange = 36, red = 57, white = 34, eq1 = 87, eq2 = 74, eq3 = 18, eq4 = 40,
  eq5 = 44, eq6 = 56, conv = 77, master = 85 }
local KEYCOL = { thr = "orange", knee = "orange", mk = "green", gain = "green", ratio = "red", att = "cyan", rel = "cyan",
  look = "cyan", az = "cyan", el = "green", w = "orange", pre = "green", size = "green", mix = "orange", lf = "red",
  lg = "red", hf = "cyan", hg = "cyan", yaw = "cyan" }
local E16_A, E16_B, E16_C = 11, 9, 7           -- display channels 12 (names), 10 (values, rings), 8 (state)

local HOLD      = 0.45                 -- s: held this long without turning = "hold"
local TAP       = 0.35                 -- s: window for the 2nd / 3rd press
local FINE_OCT  = 1 / 96               -- octaves per slow step (a twelfth of a semitone)
local FINE_DB   = 0.1                  -- dB per slow step
local FINE_Q    = 1 / 24               -- Q / ratio / times: octaves per slow step (about 3 %)
local MASTER_DB = { -30, 0 }           -- range of the master volume on encoder 16
local MASTER_STEP = 0.5                -- dB per slow step
local COMP_FINE = 1 / 400              -- compressors: share of the knob's range per slow step
local RING_DB   = 18                   -- EQ ring shows the gain -18 .. +18 dB
local ACCEL     = { { 2, 1 }, { 4, 2 }, { 7, 4 }, { 12, 8 }, { 1e9, 16 } }  -- ticks in 0.12 s -> factor
local DEBUG     = false                -- every MIDI event into the console
-- =====================================================================

local VERSION = "v8.11.1"
local r = reaper
local floor, abs, log, max, min = math.floor, math.abs, math.log, math.max, math.min
local EXT = "seren_MultiEQ"
local LAYER_NAME = { "MultiEQ", "Omni", "Directional", "Hall", "Hall-EQ", "Sends" }

local mftIn, mftOut, e16Out, viewOut
local e16Ins = {}                      -- every input port of the E16 (it has more than one)
local EQ, OMNI, DIR, ROT, FDN, CONV, FEQ = {}, {}, {}, {}, {}, {}, {}   -- FEQ = the MultiEQ in the slot right before the FDN (Hall-EQ)   -- instances: tr, fx, guid, where, master, P (ROT = SceneRotator / AmbiDecoder)
local lastScan, lastState, lastSel, lastAlive, lastResync = -1e9, nil, nil, -1e9, -1e9
local lastSeq
local mftLayer, e16Page, e16Comp, e16Hall = 1, E16_PAGE_EQ, 2, 4
local G = { mft = {}, e16 = {} }       -- gesture state per device and encoder
local sent = {}                        -- last MIDI value per "dev:status:cc"
local lockedCache = {}
local e16Force, mftForce = true, true
local opened                           -- window the script opened: { tr, fx }

-- Console: quiet by default. Warnings (second argument true) always show, the rest only when
-- "Meldungen in der Reaper-Konsole" is on in Reaper_E16_Einstellungen.lua (ExtState seren_E16/console = 1).
local function msg(s, always)
  if always or r.GetExtState("seren_E16", "console") == "1" then r.ShowConsoleMsg("[MultiEQ] " .. s .. "\n") end
end

-- ---------------------------------------------------------------- helpers
local function num(s)
  local m = tostring(s or ""):match("[-+]?%d+[.,]?%d*")
  return m and tonumber((m:gsub(",", "."))) or nil
end
local function decimals(s)
  local d = tostring(s or ""):match("%d[.,](%d+)")
  return d and #d or 0
end
local function clamp(v, a, b) return v < a and a or v > b and b or v end

-- v8.11: fader limit per kind of track (E16 window): 0 / 6 / 12 dB or off, for normal tracks (+ master),
-- group/folder tracks and tracks with receives. Turning up never jumps down when a fader already sits above.
local function capDb(tr)
  local key = "capTrack"
  if tr ~= r.GetMasterTrack(0) then
    if r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 then key = "capGroup"
    elseif r.GetTrackNumSends(tr, -1) > 0 then key = "capRecv" end
  end
  local v = r.GetExtState("seren_E16", key)
  if v == "" then v = "0" end
  return tonumber(v)                                -- nil = off
end
local function capVol(tr, old, new)               -- linear volumes
  local c = capDb(tr)
  if not c then return new end
  local lim = 10 ^ (c / 20)
  if new > lim and new > old then return math.max(old, lim) end
  return new
end
local function db(v) return v > 0 and 20 * log(v, 10) or -150 end
local SND = {}                         -- Sends / Ziele module (v8.0), filled further down

-- ---------------------------------------------------------------- layouts
-- A target: { plug = EQ / OMNI / DIR, inst, key, n, spec }. A slot: turn / pturn / hturn = list of
-- targets or a special ("nav", "master"), tap1 / tap2 / tap3 / long = actions, label, row (1 = top).
local S_DB, S_MUL, S_MS = { m = "db" }, { m = "mul", off = 0 }, { m = "mul", off = 1 }
local S_DEG, S_TOG, S_CYC, S_PRE = { m = "lin" }, { m = "tog" }, { m = "cyc" }, { m = "pre" }
local function T(plug, inst, key, n, spec) return { plug = plug, inst = inst, key = key, n = n or 1, spec = spec } end

local OMNI_ROW = { { "thr", S_DB, "Thr" }, { "ratio", S_MUL, "Rat" }, { "att", S_MS, "Att" }, { "rel", S_MS, "Rel" },
  { "knee", S_DB, "Knee" }, { "gain", S_DB, "Makeup" } }
local DIR_ROW = { { "thr", S_DB, "Thr", "en", S_TOG }, { "ratio", S_MUL, "Rat", "drv", S_CYC },
  { "att", S_MS, "Att", "apply", S_CYC }, { "rel", S_MS, "Rel" }, { "knee", S_DB, "Knee" }, { "mk", S_DB, "Mkup" } }

local FDN_ROW = { { "size", "Size" }, { "rt", "Time" }, { "fade", "Fade" }, { "mix", "Mix" },
  { "lf", "LoF", "lg", "LoG" }, { "hf", "HiF", "hg", "HiG" } }

local LAYOUT = {}
-- encoder 4 on the MultiEQ layer: DirectionalCompressor width; press: both thresholds; hold: both ratios
local function dir4()
  return { turn = { T(DIR, 1, "w", 1, S_DEG) }, pturn = { T(DIR, 1, "thr", 1, S_DB), T(DIR, 1, "thr", 2, S_DB) },
    hturn = { T(DIR, 1, "ratio", 1, S_MUL), T(DIR, 1, "ratio", 2, S_MUL) }, label = "Dir Width",
    plabel = "Dir Thr 1+2", hlabel = "Dir Ratio 1+2" }
end
-- top row of the MultiEQ layer when a DirectionalCompressor is there: turn / press + turn per compressor
local DIR_TOP = { { "thr", S_DB, "Thr", "knee", S_DB, "Knee" }, { "ratio", S_MUL, "Rat", "att", S_MS, "Att" },
  { "mk", S_DB, "Mkup", "rel", S_MS, "Rel" } }
local mixed = false                    -- MultiEQ layer shows the DirectionalCompressor on 1-7

local function build()
  mixed = #DIR > 0 and #EQ > 0 and #OMNI > 0
  for L = 1, 6 do
    local t = {}
    for e = 1, 16 do
      local s
      local top, k = e <= 8, (e - 1) % 8 + 1
      if L == 1 then
        if top and mixed then                       -- 1-3 compressor 1, 5-7 compressor 2
          local c, j = e <= 4 and 1 or 2, (e - 1) % 4 + 1
          local d = DIR_TOP[j]
          if d then
            s = { turn = { T(DIR, 1, d[1], c, d[2]) }, pturn = { T(DIR, 1, d[4], c, d[5]) },
              label = "C" .. c .. " " .. d[3], plabel = "C" .. c .. " " .. d[6] }
            if j == 1 then s.tap2 = T(DIR, 1, "en", c, S_TOG) end
          end
        elseif top then                             -- MultiEQ A: 1-3 = band 1-3, 5-7 = band 4-6
          local band = e <= 3 and e or (e >= 5 and e <= 7) and e - 1 or nil
          if band then s = { eq = true, inst = 1, band = band, tap2 = "eqon", tap3 = "eqlock" } end
        elseif k <= 6 then                          -- 9-14: MultiEQ B (A if the top row is the compressor)
          s = { eq = true, inst = mixed and 1 or 2, band = k, tap2 = "eqon", tap3 = "eqlock" }
        end
      elseif L == 2 and k <= 6 and e ~= 16 then
        local d, inst = OMNI_ROW[k], top and 1 or 2
        s = { turn = { T(OMNI, inst, d[1], 1, d[2]) }, label = string.char(64 + inst) .. " " .. d[3] }
      elseif L == 3 and k <= 6 then
        local d, c = DIR_ROW[k], top and 1 or 2
        s = { turn = { T(DIR, 1, d[1], c, d[2]) }, label = "C" .. c .. " " .. d[3] }
        if d[4] then s.tap2 = T(DIR, 1, d[4], c, d[5]) end
      elseif L == 5 then                            -- Hall-EQ: like MultiEQ A, on the reverb's own EQ
        if top then
          local band = e <= 3 and e or (e >= 5 and e <= 7) and e - 1 or nil
          if band then s = { eq = true, k = "feq", inst = 1, band = band, tap2 = "eqon", tap3 = "eqlock" } end
        end
      elseif L == 4 and top then                    -- Hall: FDN Reverb on top
        local f = FDN_ROW[k]
        if f then
          s = { turn = { T(FDN, 1, f[1], 1, S_DEG) }, label = "FDN " .. f[2] }
          if f[3] then s.pturn, s.plabel = { T(FDN, 1, f[3], 1, S_DEG) }, "FDN " .. f[4] end
        elseif k == 7 then s = { turn = { T(FDN, 1, "preset", 1, S_PRE) }, label = "FDN Preset" }
        end
      elseif L == 4 and k <= 5 then                 -- ... the convolver below
        s = { turn = { T(CONV, 1, "c" .. k, 1, S_DEG) }, label = "Conv " .. k }
      elseif L == 4 and k == 6 then
        s = { turn = { T(CONV, 1, "preset", 1, S_PRE) }, label = "Conv Preset" }
      end
      t[e] = s
    end
    -- the same on every layer
    t[8] = { turn = nil, tap1 = "bypass", long = "layer", label = "Omni A" }
    t[15] = { tap1 = "solo", pturn = { T(ROT, 1, "yaw", 1, S_DEG) }, label = "Solo", plabel = "Yaw" }
    t[16] = { turn = "nav", pturn = "master", tap1 = "mute", label = "Spur" }
    LAYOUT[L] = t
  end
  local L1, L2, L3 = LAYOUT[1], LAYOUT[2], LAYOUT[3]
  L1[4] = dir4()
  if mixed then L1[3].hturn, L1[3].hlabel = { T(DIR, 1, "az", 1, S_DEG) }, "Azim" end
  L1[8].turn, L1[8].pturn, L1[8].hturn = { T(OMNI, 1, "thr", 1, S_DB) }, { T(OMNI, 1, "gain", 1, S_DB) }, { T(OMNI, 1, "ratio", 1, S_MUL) }
  L1[8].label, L1[8].plabel, L1[8].hlabel = "Omni Thr", "Omni Makeup", "Omni Ratio"
  -- Omni layer: 6/14 = makeup (2x = look-ahead), 7 press = A look-ahead, 8 turn = A makeup
  L2[7] = { tap1 = T(OMNI, 1, "look", 1, S_TOG), show = T(OMNI, 1, "look", 1, S_TOG), label = "A Look" }
  L2[6].tap2, L2[14].tap2 = T(OMNI, 1, "look", 1, S_TOG), T(OMNI, 2, "look", 1, S_TOG)
  L2[8].turn, L2[8].label = { T(OMNI, 1, "gain", 1, S_DB) }, "A Makeup"
  L3[7] = { turn = { T(DIR, 1, "az", 1, S_DEG) }, pturn = { T(DIR, 1, "w", 1, S_DEG) }, tap2 = T(DIR, 1, "listen", 1, S_CYC),
    label = "Azim", plabel = "Width" }
  L3[8].turn, L3[8].label = { T(DIR, 1, "pre", 1, S_DB) }, "PreGain"
  L3[15].turn, L3[15].label = { T(DIR, 1, "el", 1, S_DEG) }, "Elev"
end
build()

local function layerOf(dev)
  if dev == "mft" then return mftLayer end
  if e16Page == E16_PAGE_EQ then return 1 end
  if e16Page == E16_PAGE_COMP then return e16Comp end
  if e16Page == E16_PAGE_REV then return e16Hall end
end
local function slotOf(L, e) return L and LAYOUT[L][e] end

-- ---------------------------------------------------------------- finding the plugins
local function fxName(tr, fx)
  local _, n = r.TrackFX_GetFXName(tr, fx, "")
  return n or ""
end

local function eqKind(n)
  if n:find("freq") then return "f" end
  if n:find("gain") then return "g" end
  if n:find("type") then return "t" end
  if n:find("enabl") or n:find("active") or n:find("on/off") then return "e" end
  if n:find("%f[%w]q%f[%W]") or n:find("quality") then return "q" end
end
local OMNI_PAT = { { "look", "look" }, { "thr", "thresh" }, { "knee", "knee" }, { "att", "attack" },
  { "rel", "release" }, { "ratio", "ratio" }, { "gain", "gain" } }
local DIR_PAT = { { "en", "enabl" }, { "drv", "driv" }, { "apply", "apply" }, { "thr", "thresh" }, { "knee", "knee" },
  { "att", "attack" }, { "rel", "release" }, { "ratio", "ratio" }, { "mk", "makeup" }, { "mk", "make" },
  { "pre", "pre" }, { "pre", "input" }, { "az", "azimuth" }, { "el", "elevation" }, { "w", "width" }, { "listen", "listen" } }

local ROT_PAT = { { "yaw", "yaw" } }
local function fdnKind(n)
  if n:find("fade") then return "fade" end
  if n:find("dry") or n:find("wet") or n:find("mix") then return "mix" end
  local hi, lo = n:find("high"), n:find("low")
  if hi and n:find("gain") then return "hg" end
  if lo and n:find("gain") then return "lg" end
  if hi and (n:find("freq") or n:find("cut")) then return "hf" end
  if lo and (n:find("freq") or n:find("cut")) then return "lf" end
  if n:find("room") or n:find("size") or n:find("delay") then return "size" end
  if n:find("reverb") or n:find("rt60") or n:find("time") then return "rt" end
end

local function mapParams(tr, fx, kind)
  local P, names, nc = {}, {}, 0
  local np = r.TrackFX_GetNumParams(tr, fx)
  for p = 0, np - 1 do
    local _, pn = r.TrackFX_GetParamName(tr, fx, p, "")
    local n = (pn or ""):lower()
    local k
    local reaperOwn = p >= np - 3 and (n == "bypass" or n == "wet" or n == "delta")   -- Reaper adds these at the end
    if reaperOwn then k = nil
    elseif kind == "eq" then k = eqKind(n)
    elseif kind == "fdn" then k = fdnKind(n)
    elseif kind == "conv" then                    -- the first 6 parameters of the plugin itself
      if n ~= "bypass" and nc < 5 then nc = nc + 1; k = "c" .. nc; names[k] = pn end
    else
      for _, pat in ipairs(kind == "omni" and OMNI_PAT or kind == "rot" and ROT_PAT or DIR_PAT) do
        if n:find(pat[2], 1, true) then k = pat[1] break end
      end
    end
    if k then P[k] = P[k] or {}; P[k][#P[k] + 1] = p end
  end
  return P, names
end

local function trackLabel(tr)
  local _, n = r.GetTrackName(tr, "")
  return n or "?"
end

-- instances of a plugin in: the given tracks' FX (in order), the master, the monitoring FX
local function collect(match, tracks, withMaster)
  local found = {}
  local function try(tr, fx, where, isMaster)
    if fxName(tr, fx):lower():find(match, 1, true) then
      found[#found + 1] = { tr = tr, fx = fx, where = where, master = isMaster, guid = r.TrackFX_GetFXGUID(tr, fx) or "" }
    end
  end
  local master = r.GetMasterTrack(0)
  local function masterAll()
    for fx = 0, r.TrackFX_GetCount(master) - 1 do try(master, fx, "Master", true) end
    for fx = 0, r.TrackFX_GetRecCount(master) - 1 do try(master, 0x1000000 + fx, "Monitor", true) end
  end
  if withMaster == "first" then masterAll() end
  for _, tr in ipairs(tracks) do
    for fx = 0, r.TrackFX_GetCount(tr) - 1 do try(tr, fx, trackLabel(tr), false) end
  end
  if withMaster == "last" then masterAll() end
  return found
end

local function allTracks()
  local t = {}
  for i = 0, r.CountTracks(0) - 1 do t[#t + 1] = r.GetTrack(0, i) end
  return t
end

local function eqList(kd) return kd == "feq" and FEQ or EQ end
local function locked(inst, band, kd)
  local q = eqList(kd)[inst]
  if not q then return false end
  local key = q.guid .. ":" .. band
  if lockedCache[key] == nil then
    local _, v = r.GetProjExtState(0, EXT, key)
    lockedCache[key] = v == "1"
  end
  return lockedCache[key]
end

local function setLocked(inst, band, on, kd)
  local key = eqList(kd)[inst].guid .. ":" .. band
  lockedCache[key] = on
  r.SetProjExtState(0, EXT, key, on and "1" or "")
end

-- ---------------------------------------------------------------- values
local function textAt(q, p, nv)
  local ok, s = r.TrackFX_FormatParamValueNormalized(q.tr, q.fx, p, nv, "")
  if ok and s and s ~= "" then return s end
end
local function realAt(q, p, nv) return num(textAt(q, p, nv)) end
local function curText(q, p)
  local _, s = r.TrackFX_GetFormattedParamValue(q.tr, q.fx, p, "")
  return s or ""
end
local function cur(q, p) return num(curText(q, p)) end
local function norm(q, p) return r.TrackFX_GetParamNormalized(q.tr, q.fx, p) end
local function setNorm(q, p, v) r.TrackFX_SetParamNormalized(q.tr, q.fx, p, v) end

-- normalized value whose text is closest to target (the text grows with the value, or shrinks)
local function normFor(q, p, target)
  local v0, v1 = realAt(q, p, 0), realAt(q, p, 1)
  if not v0 or not v1 then return nil end
  local up = v1 >= v0
  local lo, hi = 0, 1
  for _ = 1, 24 do
    local mid = (lo + hi) / 2
    local v = realAt(q, p, mid) or v0
    if (v < target) == up then lo = mid else hi = mid end
  end
  local a, b = realAt(q, p, lo) or v0, realAt(q, p, hi) or v1
  return abs(a - target) <= abs(b - target) and lo or hi
end

local function limits(q, p)
  local a, b = realAt(q, p, 0), realAt(q, p, 1)
  if a and b then return min(a, b), max(a, b) end
end

local function accel(g, ticks, now)
  g.hist = g.hist or {}
  local h, n = g.hist, 0
  h[#h + 1] = { now, ticks }
  for i = #h, 1, -1 do
    if now - h[i][1] > 0.12 then table.remove(h, i) else n = n + h[i][2] end
  end
  for _, a in ipairs(ACCEL) do if n <= a[1] then return a[2] end end
  return 1
end

-- one step on parameter p. kind: "f" (octaves), "q"/"mul" (multiplicative, + offset), "db", "lin"
local function step(q, p, kind, d, m, off)
  local s = curText(q, p)
  local v = num(s)
  local lo, hi = limits(q, p)
  if not v or not lo then                          -- plugin gives no value text: step normalized
    setNorm(q, p, clamp(norm(q, p) + d * m * 0.002, 0, 1))
    return
  end
  local res = 10 ^ -decimals(s)                    -- smallest step the plugin shows
  local t
  if kind == "f" then t = v * 2 ^ (d * m * FINE_OCT)
  elseif kind == "q" or kind == "mul" then
    off = off or 0
    t = (v + off) * 2 ^ (d * m * FINE_Q) - off
  elseif kind == "lin" then t = v + d * m
  else t = v + d * m * FINE_DB end
  if abs(t - v) < res then t = v + (d > 0 and res or -res) end
  local n = normFor(q, p, clamp(t, lo, hi))
  if n then setNorm(q, p, n) end
end

-- compressors: move the knob itself; if the plugin's value (its text) doesn't change, a bigger step
-- The plugin may round to its own steps: read back what it took, and step further until it moved.
local function stepNorm(q, p, d, m)
  local n0 = norm(q, p)
  local dn = d * m * COMP_FINE
  for k = 1, 40 do
    local n = clamp(n0 + dn * k, 0, 1)
    setNorm(q, p, n)
    local now = norm(q, p)
    if abs(now - n0) > 1e-6 and (now - n0) * d > 0 then return end
    if n <= 0 or n >= 1 then break end
  end
end

local function toggle(q, p) setNorm(q, p, norm(q, p) >= 0.5 and 0 or 1) end

local function cycle(q, p)                         -- choice parameter: next entry, by its text
  local here, steps = curText(q, p), {}
  for i = 0, 20 do
    local t = textAt(q, p, i / 20)
    if t and t ~= steps[#steps] then steps[#steps + 1] = t; steps[t] = i / 20 end
  end
  for i, t in ipairs(steps) do
    if t == here then setNorm(q, p, steps[steps[i % #steps + 1]]) return end
  end
  setNorm(q, p, norm(q, p) >= 0.99 and 0 or min(1, norm(q, p) + 0.5))
end

local function resolve(t)                          -- target -> instance, parameter index
  local q = t.plug[t.inst]
  if t.key == "preset" then return q, q and -1 end   -- the plugin's preset list (Reaper's own)
  local P = q and q.P[t.key]
  return q, P and P[t.n]
end
local function colKey(t)                           -- IEM colour of a target
  if t.plug == CONV then return t.key == "preset" and "white" or "conv" end
  return KEYCOL[t.key] or "white"
end

-- ---------------------------------------------------------------- plugin windows
local function showWindow(q)
  if not OPEN_WINDOWS or not q then return end
  if opened and opened.tr == q.tr and opened.fx == q.fx then
    if r.TrackFX_GetFloatingWindow(q.tr, q.fx) then return end
  end
  if CLOSE_OTHERS and opened and not (opened.tr == q.tr and opened.fx == q.fx) then
    if r.ValidatePtr(opened.tr, "MediaTrack*") then r.TrackFX_Show(opened.tr, opened.fx, 2) end
  end
  if not r.TrackFX_GetFloatingWindow(q.tr, q.fx) then r.TrackFX_Show(q.tr, q.fx, 3) end
  opened = { tr = q.tr, fx = q.fx }
end

-- ---------------------------------------------------------------- tracks
local function selTrack() return r.GetSelectedTrack(0, 0) end
local function trackState(tr)
  if not tr then return false, false end
  return r.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0, r.GetMediaTrackInfo_Value(tr, "B_MUTE") > 0
end
local function trackNo(tr) return tr and floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) or 0 end
local function vol7(v, lo, hi) return floor(clamp((db(v) - lo) / (hi - lo), 0, 1) * 127 + 0.5) end

local function navigate(d)
  local n = r.CountTracks(0)
  if n == 0 then return end
  local tr = selTrack()
  local i = tr and trackNo(tr) - 1 or (d > 0 and -1 or n)
  i = clamp(i + d, 0, n - 1)
  local nt = r.GetTrack(0, i)
  r.SetOnlyTrackSelected(nt)
  r.Main_OnCommand(40913, 0)                       -- scroll the selected track into view
end

local function masterStep(d, m)
  local ms = r.GetMasterTrack(0)
  local old = r.GetMediaTrackInfo_Value(ms, "D_VOL")
  local top = math.max(capDb(ms) or 24, db(old))       -- v8.11: upper end = fader limit (window), was always 0 dB
  local v = clamp(db(old) + d * m * MASTER_STEP, MASTER_DB[1], top)
  r.SetMediaTrackInfo_Value(ms, "D_VOL", capVol(ms, old, 10 ^ (v / 20)))
end

local function omniBypass()
  local q = OMNI[1]
  if not q then msg("kein OmniCompressor", true) return end
  r.TrackFX_SetEnabled(q.tr, q.fx, not r.TrackFX_GetEnabled(q.tr, q.fx))
end

-- ---------------------------------------------------------------- formats
local function whole(f) return abs(f - floor(f + 0.5)) < 0.05 end
local function fmtHz(f)
  if not f then return "-" end
  if f < 1000 and whole(f) then return string.format("%d Hz", floor(f + 0.5)) end
  if f >= 1000 then return string.format("%.2f kHz", f / 1000) end
  if f >= 100 then return string.format("%d Hz", floor(f + 0.5)) end
  return string.format("%.1f Hz", f)
end
local function fmtHz4(f)                            -- 4 characters for the E16 slot
  if not f then return " -- " end
  if f >= 9950 then return string.format("%dk", floor(f / 1000 + 0.5)) end
  if f >= 1000 then return string.format("%.1fk", f / 1000) end
  if f >= 100 or whole(f) then return string.format("%d", floor(f + 0.5)) end
  return string.format("%.1f", f)
end
local function fmtDb(g) return g and string.format("%+.1f", g) or "-" end
local function fmtQ(v)
  if not v then return "-" end
  return v >= 10 and string.format("%.0f", v) or v >= 1 and string.format("%.1f", v) or string.format("%.2f", v)
end
local function fmt4(v, s)                           -- any value in 4 characters
  if not v then return (s or ""):sub(1, 4) end
  local a = abs(v)
  if a >= 999.5 then return string.format("%dk", floor(v / 1000 + 0.5)) end
  if a >= 99.5 or whole(v) then return string.format("%d", floor(v + 0.5)) end
  if a >= 9.95 then return string.format("%.0f", v) end
  return string.format("%.1f", v)
end

-- ---------------------------------------------------------------- what a slot shows
local function bandInfo(inst, band, kd)
  local q = eqList(kd)[inst]
  if not q then return nil end
  local P = q.P
  local function at(k) return P[k] and P[k][band] end
  return { f = at("f") and cur(q, at("f")), g = at("g") and cur(q, at("g")), q = at("q") and cur(q, at("q")),
    on = not at("e") or norm(q, at("e")) >= 0.5, lock = locked(inst, band, kd) }
end

local function eqRing(b, mode)
  if mode == "p" then return floor(clamp(((b.g or 0) + RING_DB) / (2 * RING_DB), 0, 1) * 127 + 0.5) end
  if mode == "h" then return floor(clamp(log((b.q or 1) / 0.05) / log(8 / 0.05), 0, 1) * 127 + 0.5) end
  return floor(clamp(log((b.f or 20) / 20) / log(1000), 0, 1) * 127 + 0.5)
end

-- -> { ring, name, text, v4, on, master, lock, blink ("solo" / "mute15" / "mute") }
local function info(L, e, mode)
  local s = slotOf(L, e)
  if not s then return nil end
  local o = { ring = 0, name = "", text = "", v4 = "", on = true }
  if s.eq then
    local b = bandInfo(s.inst, s.band, s.k)
    if not b then return nil end
    o.ring, o.on, o.lock, o.eq, o.col = eqRing(b, mode), b.on, b.lock, b, "eq" .. s.band
    o.v4 = fmtHz4(b.f)
    o.name = fmtHz(b.f) .. "\n" .. (s.k == "feq" and "H" or string.char(64 + s.inst)) .. s.band .. (b.lock and " LOCK" or "") .. (b.on and "" or " AUS")
    o.text = fmtDb(b.g) .. " dB  Q " .. fmtQ(b.q)
    return o
  end
  local src = (mode == "p" and s.pturn) or (mode == "h" and (s.hturn or s.pturn)) or s.turn or (s.show and { s.show })
  local sel = selTrack()
  o.col = "white"
  if src == "nav" or src == "master" then
    local ms = r.GetMasterTrack(0)
    if src == "master" then
      local v = r.GetMediaTrackInfo_Value(ms, "D_VOL")
      o.ring, o.v4, o.name, o.text = vol7(v, MASTER_DB[1], MASTER_DB[2]), fmt4(db(v)), "Master\n" .. string.format("%.1f dB", db(v)), "drücken + drehen"
    else
      local v = sel and r.GetMediaTrackInfo_Value(sel, "D_VOL") or 0
      o.ring = sel and vol7(v, -60, 6) or 0
      o.v4 = sel and ("T" .. trackNo(sel)) or "--"
      o.name = sel and (trackNo(sel) .. " " .. trackLabel(sel)) or "keine Spur"
      o.text = sel and string.format("%.1f dB", db(v)) or ""
    end
  elseif type(src) == "table" then
    local q, p = resolve(src[1])
    if not p then
      o.missing = true
    elseif p == -1 then                              -- preset list
      local _, pn = r.TrackFX_GetPreset(q.tr, q.fx, "")
      pn = (pn and pn ~= "") and pn or "-"
      o.v4, o.name, o.text, o.master, o.where, o.col = pn:sub(1, 4), pn .. "\n" .. (s.label or ""), q.where, q.master, q.where, "white"
    else
      local t = curText(q, p)
      o.ring, o.master, o.where = floor(norm(q, p) * 127 + 0.5), q.master, q.where
      o.col = colKey(src[1])
      if src[1].key == "thr" then o.ring, o.inv = 127 - o.ring, true end   -- threshold: the ring comes from the top (0 dB) down
      if src[1].spec.m == "tog" then o.on = norm(q, p) >= 0.5; t = o.on and "AN" or "AUS"; o.v4 = t
      else o.v4 = fmt4(num(t), t) end
      local lab = (mode == "h" and (s.hlabel or s.plabel)) or (mode == "p" and s.plabel) or s.label or ""
      if q.names and q.names[src[1].key] then lab = "Conv " .. q.names[src[1].key] end
      o.name = t .. "\n" .. lab .. (q.master and " (Master)" or "")
      o.text = q.where
      if s.tap2 and s.tap2.key == "en" then
        local qe, pe = resolve(s.tap2)
        if pe then o.on = norm(qe, pe) >= 0.5 end
      end
    end
  else
    o.name, o.v4 = s.label or "", (s.label or ""):sub(1, 4):upper()
  end
  if e == 8 then                                    -- OmniCompressor A on / bypassed / missing
    local q = OMNI[1]
    if not q then o.omni = "none" elseif not r.TrackFX_GetEnabled(q.tr, q.fx) then o.omni = "byp" end
    if o.omni and not src then o.v4 = o.omni == "byp" and "BYP" or "--" end
    if not src then o.name = "Omni A" .. (o.omni == "byp" and " AUS" or o.omni == "none" and " fehlt" or " an") .. "\n" .. LAYER_NAME[L] end
  end
  if e == 15 or e == 16 then
    local solo, mute = trackState(sel)
    if e == 15 and solo then o.blink = "solo" elseif e == 15 and mute then o.blink = "mute15"
    elseif e == 16 and mute then o.blink = "mute" end
    if e == 15 and not src then o.v4 = solo and "SOLO" or "solo"; o.name = "Solo\n" .. (solo and "an" or "aus") end
  end
  return o
end

-- ---------------------------------------------------------------- MIDI out (only changes)
local function out(dev, st, cc, v, force, tag)
  if not dev then return end
  local key = dev .. ":" .. st .. ":" .. cc .. (tag or "")
  if not force and sent[key] == v then return end
  sent[key] = v
  r.SendMIDIMessageToHardware(dev, string.char(st, cc, v))
end

local function ascii(s) return ((s or ""):gsub("[^\32-\126]", "?")) end

local function e16Text(ch, base, len, s, force)       -- one CC per character
  s = ascii(s):sub(1, len)
  s = s .. string.rep(" ", len - #s)
  for i = 1, len do out(e16Out, 0xB0 + ch, base + i - 1, s:byte(i), force) end
end

-- SysEx carries 7 bits: umlauts, ß and ° travel as codes 1-8, the view turns them back (v6.1)
local UML = { ["\195\164"] = "\1", ["\195\182"] = "\2", ["\195\188"] = "\3", ["\195\132"] = "\4",
              ["\195\150"] = "\5", ["\195\156"] = "\6", ["\195\159"] = "\7", ["\194\176"] = "\8" }
local function ascii7(s)
  s = (s or ""):gsub("[\194\195][\128-\191]", function(u) return UML[u] or "" end)
  return (s:gsub("[^\1-\8\10\32-\126]", "")):sub(1, 64)
end
local function viewSysex(head, text)
  if not viewOut then return end
  local t = { "\240\125\77" }
  for _, b in ipairs(head) do t[#t + 1] = string.char(b) end
  if text then t[#t + 1] = ascii7(text) end
  t[#t + 1] = "\247"
  r.SendMIDIMessageToHardware(viewOut, table.concat(t))
end

local viewColSent = {}
local function viewColor(e, hx, force)            -- SysEx 8: bar colour of slot e in the Twister View
  if not viewOut or not hx then return end
  if not force and viewColSent[e] == hx then return end
  viewColSent[e] = hx
  local n = tonumber(hx, 16)
  r.SendMIDIMessageToHardware(viewOut, string.char(0xF0, 0x7D, 0x4D, 8, MFT_BANK, e - 1,
    (n >> 17) & 127, (n >> 9) & 127, (n >> 1) & 127, 0xF7))
end

local viewSent = {}
local function view(e, name, text, v7, force)
  if not viewOut then return end
  local now = name .. "|" .. text .. "|" .. v7
  if not force and viewSent[e] == now then return end
  local on, ot, ov = (viewSent[e] or "||"):match("^(.-)|(.-)|(.-)$")
  viewSent[e] = now
  if force or on ~= name then viewSysex({ 1, MFT_BANK, e - 1 }, name) end
  if force or ot ~= text then viewSysex({ 2, MFT_BANK, e - 1 }, text) end
  if force or ov ~= tostring(v7) then
    r.SendMIDIMessageToHardware(viewOut, string.char(0xB0 + MFT_TURN_CH, MFT_CC + e - 1, v7))
  end
end

-- ---------------------------------------------------------------- feedback
local function short(q) return q and q.where:sub(1, 6) or "--" end

local function renderMft(force)
  local L = mftLayer
  for e = 1, 16 do
    if L == 6 and SND.owns("mft", e) then SND.renderMft(e, force) else
    local gm = G.mft[e] or {}
    local o = info(L, e, gm.mode)
    local cc = MFT_CC + e - 1
    local ring, col, rgb, ind, name, text = 0, 0, 0, 95, "", ""
    if o and not o.missing then
      ring, name, text = o.ring, o.name, o.text
      col = o.lock and LOCK_COLOR or o.master and COL_MASTER or TW_KEY[o.col] or 127
      ind = o.on and 95 or 70
      rgb = gm.mode == "h" and Q_PULSE or not o.on and DIM_OFF or 0
    end
    if e == 8 then
      col = LAYER_COL[L]
      if o and o.omni and rgb == 0 then rgb = DIM_OFF end
    end
    if not o or o.missing then col, rgb = LAYER_COL[L], DIM_OFF end
    if o and o.blink then
      col = o.blink == "solo" and COL_SOLO or o.blink == "mute15" and COL_MUTE15 or COL_MUTE
      rgb = BLINK
      if e == 15 and ring == 0 then ring = 127 end
    end
    if e == 16 and gm.mode then col, rgb = COL_MASTERVOL, DIM_MASTERVOL end   -- master: dim red, steady
    out(mftOut, 0xB0 + MFT_TURN_CH, cc, ring, force)
    out(mftOut, 0xB0 + MFT_COL_CH, cc, col, force)
    out(mftOut, 0xB0 + MFT_ANIM_CH, cc, rgb, force)     -- one value per channel: strobe / pulse / none
    out(mftOut, 0xB0 + MFT_RING_CH, cc, ind, force)     -- ring brightness on the ring channel
    view(e, name, text, ring, force)
    local hx = IEM_HEX[(o and o.blink) and (o.blink == "solo" and "solo" or "mute") or (o and not o.missing and o.col) or "white"]
    viewColor(e, hx, force)
    end
  end
end

local function renderE16(force)
  local L = layerOf("e16")
  if not e16Out or not L then return end
  for e = 1, 16 do
    local ge = G.e16[e] or {}
    local o = info(L, e, ge.mode)
    local name, ring, state = "", nil, 0
    if o and not o.missing then
      name, ring = o.v4, o.ring
      state = (o.on and 0 or 1) + (o.lock and 2 or 0) + (ge.mode == "h" and 4 or ge.mode == "p" and 8 or 0) + (o.master and 16 or 0)
      if o.blink then
        state = o.blink == "solo" and 64 or o.blink == "mute15" and 65 or 66
        if ring == 0 then ring = 127 end
      end
      if e == 16 and ge.mode then state = 67 end              -- master volume: master colour
      if e == 8 and o.omni and state < 64 then state = 1 end
    end
    if e == 8 and name == "" then name = L == 2 and "OMNI" or "--" end
    e16Text(E16_A, 16 + (e - 1) * 4, 4, name, force)
    if ring then out(e16Out, 0xB0 + E16_B, 79 + e, ring, force)
    else out(e16Out, 0xB0 + E16_B, 95 + e, 0, force) end
    out(e16Out, 0xB0 + E16_C, e, state, force)
    out(e16Out, 0xB0 + E16_C, 16 + e, (o and not o.missing and E16_KEY[o.col]) or 34, force)   -- ring colour
  end
  local t
  if L == 1 then t = (#EQ == 0) and "kein MultiEQ" or ("A " .. short(EQ[1]):sub(1, 5) .. " B " .. short(EQ[2]):sub(1, 5))
  elseif L == 2 then t = (#OMNI == 0) and "kein OmniComp" or ("OMNI " .. short(OMNI[1]) .. (OMNI[2] and ("/" .. short(OMNI[2])) or ""))
  elseif L == 3 then t = (#DIR == 0) and "kein DirComp" or ("DIR " .. short(DIR[1]))
  elseif L == 5 then t = (#FEQ == 0) and "kein Hall-EQ" or ("HALL-EQ " .. short(FEQ[1]))
  else local h = FDN[1] or CONV[1]; t = h and ("HALL " .. short(h)) or "kein Hall" end
  e16Text(E16_A, 0, 15, t, force)
end

local function flash(dev, e, mode, extra)            -- E16: title + slot value show the change
  if dev ~= "e16" or not e16Out then return end
  local L = layerOf("e16")
  local o = L and info(L, e, mode)
  if not o then return end
  local full, v4
  if o.eq then
    local b, s = o.eq, slotOf(L, e)
    full = string.format("%s%d %s %s Q%s", s.k == "feq" and "H" or string.char(64 + s.inst), s.band, fmtHz4(b.f), fmtDb(b.g), fmtQ(b.q))
    v4 = mode == "p" and fmtDb(b.g) or mode == "h" and ("Q" .. fmtQ(b.q)) or extra == "lock" and (b.lock and "LOCK" or "FREI")
      or extra == "on" and (b.on and " AN" or "AUS") or nil
  else
    local value, label = o.name:match("^(.-)\n(.*)$")
    full = label and (label:gsub(" %(Master%)", "") .. " " .. value) or o.name
    v4 = (mode or extra) and o.v4 or nil
  end
  e16Text(E16_B, 0, 15, full, true)
  out(e16Out, 0xB0 + E16_B, 15, 0, true)
  if v4 then e16Text(E16_B, 16 + (e - 1) * 4, 4, v4, true) end
end

-- ---------------------------------------------------------------- gestures
local function nextLayer(dev)
  if dev == "mft" then
    mftLayer = mftLayer % 6 + 1
    if mftLayer == 5 and #FEQ == 0 then mftLayer = 6 end
    if mftLayer == 6 and not SND.twisterOn() then mftLayer = 1 end
    msg("Twister Bank 4: " .. LAYER_NAME[mftLayer])
    viewSysex({ 6, MFT_BANK }, LAYER_NAME[mftLayer])
    mftForce = true
    G.mft = {}                                      -- gestures of the old layer are over
  elseif e16Page == E16_PAGE_REV then
    e16Hall = e16Hall == 4 and (#FEQ > 0 and 5 or 4) or 4
    e16Force = true
  elseif e16Page == E16_PAGE_COMP then
    e16Comp = e16Comp == 2 and 3 or 2              -- page 3: Omni <-> Directional (page 4 = reverb)
    e16Force = true
  end
end

-- ================================================================ Sends / Ziele (v8.0)
-- E16 page 1 (scene seren-a_E16, DAW-Link channels: in 16, out A = 16, B = 14) with sub-pages
-- Sends / Ziele / Spur / Menü (hold 16 = next) and Twister bank 4, layer 6 "Sends".
-- Replaces reaper_to_e16.lua (now the "Spur" sub-page) and e16-reverb-remote (Sends/Ziele).
-- Settings: ExtState "seren_E16" (window Reaper_E16_Einstellungen.lua or the E16 menu page),
-- targets: project ExtState "seren_E16/targets" (GUIDs), else the old reverb-remote assignment, else name prefix.
local function sndModule()
local SEXT = "seren_E16"
local SDEF = { capSend = "1", masterNav = "1", layout = "split", dedicated = "1", push = "prepost", preFx = "0", targets = "assigned", prefix = "RVB",
  cSend = "cyan", cPre = "weiss", cMute = "rot", cMeter = "pink", cFader = "hellblau", cMaster = "orange",
  cTrack = "weiss", triple = "1", dbl = "0", twister = "1", spur = "1" }
-- name, E16 slot text, full name, OXI App palette (E16), Twister colour map, RGB for the Twister View
local COLS = {
  { "cyan", "CYAN", "Cyan", 83, 20, "00CAFE" }, { "gruen", "GRUN", "Grün", 92, 51, "50FE03" },
  { "orange", "ORAN", "Pfirsich/Orange", 36, 68, "FE9F01" }, { "rot", "ROT", "Rot", 57, 83, "CF021C" },
  { "weiss", "WEIS", "Weiß", 34, 127, "D9D9D9" }, { "gelb", "GELB", "Gelb", 44, 64, "FFFF00" },
  { "pink", "PINK", "Pink", 50, 100, "FF4FA0" }, { "hellblau", "HBLA", "Hellblau", 18, 9, "6495ED" },
  { "violett", "VIOL", "Violett", 74, 118, "9370DB" }, { "tuerkis", "TURK", "Türkis", 85, 25, "02FFFF" },
}
local COLBY = {}
for i, c in ipairs(COLS) do COLBY[c[1]] = c; COLBY[i] = c end
local COLCH = {}
for _, c in ipairs(COLS) do COLCH[#COLCH + 1] = { c[1], c[2], c[3] } end
local OPTS = {
  { k = "layout", n = "LAYT", t = "Layout", ch = { { "split", "SPLT", "1-8 Sends / 9-16 Ziele" }, { "pages", "SEIT", "Seiten Sends + Ziele" } } },
  { k = "dedicated", n = "FEST", t = "Spur+Master", ch = { { "1", "FEST", "fest: Spur 15 (8), Master 16" }, { "0", "ALLE", "alles Sends" } } },
  { k = "push", n = "PUSH", t = "Push", ch = { { "prepost", "P/P", "Pre/Post, 2x Ziel" }, { "mute", "MUTE", "Mute, 2x Ziel" },
    { "mute_pp", "M+PP", "Mute, 2x Pre/Post" }, { "pp_mute", "PP+M", "Pre/Post, 2x Mute" } } },
  { k = "preFx", n = "PRFX", t = "Pre-FX", ch = { { "0", "AUS", "nicht mitschalten" }, { "1", "MIT", "mitschalten" } } },
  { k = "targets", n = "ZIEL", t = "Ziele", ch = { { "assigned", "ZUGW", "zugewiesen" }, { "sends", "SEND", "Sends der Spur" } } },
  { k = "cSend", n = "cSND", t = "Farbe Send", ch = COLCH, col = true },
  { k = "cPre", n = "cPRE", t = "Farbe Pre", ch = COLCH, col = true },
  { k = "cMute", n = "cMUT", t = "Farbe Mute", ch = COLCH, col = true },
  { k = "cMeter", n = "cMTR", t = "Farbe Meter", ch = COLCH, col = true },
  { k = "cFader", n = "cFDR", t = "Farbe Fader", ch = COLCH, col = true },
  { k = "cMaster", n = "cMAS", t = "Farbe Master", ch = COLCH, col = true },
  { k = "cTrack", n = "cSPU", t = "Farbe Spur", ch = COLCH, col = true },
  { k = "triple", n = "3xSP", t = "3x Spur", ch = { { "0", "AUS", "aus" }, { "1", "0/-i", "0 dB / -inf" } } },
  { k = "dbl", n = "2xSP", t = "2x Spur", ch = { { "0", "AUS", "aus" }, { "1", "MSND", "Master-Send an/aus" } } },
  { k = "twister", n = "TWST", t = "Twister Sends", ch = { { "1", "AN", "Ebene 6 an" }, { "0", "AUS", "Ebene 6 aus" } } },
  { k = "spur", n = "SPUR", t = "Spur-Seite", ch = { { "1", "AN", "an" }, { "0", "AUS", "aus" } } },
}
SND.OPTS, SND.COLS, SND.SDEF = OPTS, COLS, SDEF

local scfg, srev = {}, nil
local function loadCfg()
  for k, v in pairs(SDEF) do
    local s = r.GetExtState(SEXT, k)
    scfg[k] = s ~= "" and s or v
  end
end
local function setCfg(k, v)
  scfg[k] = v
  r.SetExtState(SEXT, k, v, true)
  srev = tostring(r.time_precise())
  r.SetExtState(SEXT, "rev", srev, false)
end
SND.cfg = scfg

local MIN_DB, MAX_DB, STEP_DB = -90, 6, 0.3
local MET_DB, MET_T, SHOW_FADER, BLINK_T = -60, 0.15, 1.2, 0.4
local HOLD_S, TAP_S = 0.45, 0.4
local A1, B1 = 0xBF, 0xBD                      -- E16 page 1: bank A = channel 16, bank B = channel 14
local S = { sub = 1, mftSub = 1, g = { e16 = {}, mft = {} }, turnAt = {}, lastTurn = {}, met = {}, metT = 0,
  lastUserG = nil, subFlash = 0 }

-- ------------------------------------------------------------ helpers
local function toDb(v) if v <= 0 then return MIN_DB end return max(MIN_DB, 20 * log(v, 10)) end
local function toVol(d) if d <= MIN_DB then return 0 end return 10 ^ (min(MAX_DB, d) / 20) end
local function dbRing(v)
  local d = toDb(v)
  if d <= -60 then return v > 0 and 1 or 0 end
  return floor(clamp((d + 60) / (MAX_DB + 60), 0, 1) * 126 + 1.5)
end
local function fmtDB4(v)                         -- max. 4 characters, as the slot wants
  if v <= 0 then return "-inf" end
  local d = toDb(v)
  local s
  if abs(d) < 0.05 then s = "0"
  elseif d > -10 and d < 10 then s = string.format("%.1f", d)
  else s = tostring(floor(d + 0.5)) end
  return s:sub(1, 4)
end
local function fmtDBf(v) if v <= 0 then return "-inf dB" end return string.format("%+.1f dB", toDb(v)) end
local function nm(t)
  if not t then return "" end
  if t == r.GetMasterTrack(0) then return "MASTER" end
  local _, n = r.GetTrackName(t)
  return n
end
local function four(s)
  s = s or ""
  local pre = scfg.prefix or ""
  if pre ~= "" and s:sub(1, #pre):lower() == pre:lower() and #s > #pre then s = s:sub(#pre + 1) end
  s = ascii(s):gsub("^[%s%-_:]+", "")
  return s:sub(1, 4)
end
local function guid(t) return r.GetTrackGUID(t) end
local function byGuid(g)
  if not g or g == "" then return nil end
  for i = 0, r.CountTracks(0) - 1 do local t = r.GetTrack(0, i); if guid(t) == g then return t end end
end
local function colOf(key) return COLBY[scfg[key]] or COLBY[SDEF[key]] end
local function selectOnly(t)
  for i = 0, r.CountTracks(0) - 1 do r.SetTrackSelected(r.GetTrack(0, i), false) end
  r.SetTrackSelected(r.GetMasterTrack(0), false)
  r.SetTrackSelected(t, true)
end

-- ------------------------------------------------------------ targets and the track the sends belong to
local function targets(eff)
  local out = {}
  if scfg.targets == "sends" then
    if eff then for i = 0, r.GetTrackNumSends(eff, 0) - 1 do out[#out + 1] = r.GetTrackSendInfo_Value(eff, 0, i, "P_DESTTRACK") end end
    return out
  end
  local _, list = r.GetProjExtState(0, SEXT, "targets")
  if list == "" then list = r.GetExtState("E16_REVERB_REMOTE", "guids") end
  if list ~= "" then
    local by = {}
    for i = 0, r.CountTracks(0) - 1 do local t = r.GetTrack(0, i); by[guid(t)] = t end
    for g in list:gmatch("[^,]+") do if by[g] and #out < 32 then out[#out + 1] = by[g] end end
    return out
  end
  local pre = (scfg.prefix or ""):lower()
  if pre == "" then return out end
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, n = r.GetTrackName(t)
    if n:sub(1, #pre):lower() == pre and #out < 32 then out[#out + 1] = t end
  end
  return out
end
local function isIn(t, T) for _, x in ipairs(T) do if x == t then return true end end return false end
local ctx = {}                                   -- per frame: eff, T, sel
local function refreshCtx()
  local sel = selTrack()
  local master = r.GetMasterTrack(0)
  local assigned = scfg.targets ~= "sends" and targets(nil) or {}
  local eff = sel
  if not sel or sel == master or isIn(sel, assigned) then
    if not S.lastUserG then local _, g = r.GetProjExtState(0, SEXT, "lastUser"); S.lastUserG = g ~= "" and g or nil end
    eff = byGuid(S.lastUserG)
  elseif guid(sel) ~= S.lastUserG then
    S.lastUserG = guid(sel)
    r.SetProjExtState(0, SEXT, "lastUser", S.lastUserG)
  end
  ctx.sel, ctx.eff, ctx.master = sel, eff, master
  ctx.T = scfg.targets == "sends" and targets(eff) or assigned
end
local function sendTo(src, dest)
  if not src or not dest then return nil end
  for i = 0, r.GetTrackNumSends(src, 0) - 1 do
    if r.GetTrackSendInfo_Value(src, 0, i, "P_DESTTRACK") == dest then return i end
  end
end

-- ------------------------------------------------------------ layouts
local function freeEnc(dev)
  local ded = scfg.dedicated == "1"
  local top, bot = {}, {}
  for e = 1, 16 do
    local skip
    if dev == "mft" then skip = ded and (e == 8 or e == 15 or e == 16)
    elseif ded then skip = scfg.layout == "split" and (e == 8 or e == 16) or (scfg.layout ~= "split" and (e == 15 or e == 16)) end
    if not skip then if e <= 8 then top[#top + 1] = e else bot[#bot + 1] = e end end
  end
  return top, bot
end
local function subs(dev)
  local top, bot = freeEnc(dev)
  local list = {}
  local nT = #ctx.T
  if scfg.layout == "split" then
    local n = min(#top, #bot)
    for g = 0, max(1, math.ceil(nT / n)) - 1 do list[#list + 1] = { kind = "split", g = g, n = n, top = top, bot = bot } end
  else
    local all = {}
    for _, e in ipairs(top) do all[#all + 1] = e end
    for _, e in ipairs(bot) do all[#all + 1] = e end
    for g = 0, max(1, math.ceil(nT / #all)) - 1 do
      list[#list + 1] = { kind = "S", g = g, n = #all, all = all }
      list[#list + 1] = { kind = "Z", g = g, n = #all, all = all }
    end
  end
  if dev == "e16" then
    if scfg.spur == "1" then list[#list + 1] = { kind = "spur" } end
    list[#list + 1] = { kind = "menu" }
  end
  return list
end
local function subName(sb)
  if not sb then return "" end
  if sb.kind == "split" then return string.format("Sends+Ziele %d-%d", sb.g * sb.n + 1, sb.g * sb.n + sb.n) end
  if sb.kind == "S" then return string.format("Sends %d-%d", sb.g * sb.n + 1, sb.g * sb.n + sb.n) end
  if sb.kind == "Z" then return string.format("Ziele %d-%d", sb.g * sb.n + 1, sb.g * sb.n + sb.n) end
  if sb.kind == "spur" then return "Spur" end
  return "Menue"
end
local function subKey(sb) return sb and (sb.kind .. (sb.g or "")) end
S.subKey = {}
local function curSub(dev)                       -- the sub-page stays the same one when the list changes
  local list = subs(dev)
  local k = dev == "e16" and S.sub or S.mftSub
  local want = S.subKey[dev]
  if want and subKey(list[k]) ~= want then
    local hit
    for i, sb in ipairs(list) do if subKey(sb) == want then hit = i end end
    k = hit or 1
  end
  if k > #list then k = 1 end
  if dev == "e16" then S.sub = k else S.mftSub = k end
  S.subKey[dev] = subKey(list[k])
  return list[k], list, k
end
local function slotMap(dev, sb)
  local m = {}
  if not sb then return m end
  if sb.kind == "split" then
    for i, e in ipairs(sb.top) do if i <= sb.n then m[e] = { k = "send", t = sb.g * sb.n + i } end end
    for i, e in ipairs(sb.bot) do if i <= sb.n then m[e] = { k = "tgt", t = sb.g * sb.n + i } end end
  elseif sb.kind == "S" or sb.kind == "Z" then
    for i, e in ipairs(sb.all) do m[e] = { k = sb.kind == "S" and "send" or "tgt", t = sb.g * sb.n + i } end
  elseif sb.kind == "menu" then
    for i = 1, #OPTS do m[i] = { k = "menu", o = i } end
  elseif sb.kind == "spur" then
    for i = 1, 16 do m[i] = { k = "spur", i = i } end
  end
  if scfg.dedicated == "1" and sb.kind ~= "menu" and sb.kind ~= "spur" then
    if dev == "e16" then
      -- v8.5: like the plugin pages – 15 (bzw. 8) = Spur, 16 = Master
      if scfg.layout == "split" then m[8], m[16] = { k = "track" }, { k = "master" }
      else m[15], m[16] = { k = "track" }, { k = "master" } end
    else m[8] = { k = "scroll" } end
  end
  return m
end
function SND.twisterOn() return scfg.twister ~= "0" end
function SND.owns(dev, e)
  if dev ~= "mft" then return true end
  return not (scfg.dedicated == "1" and (e == 15 or e == 16))
end

-- ------------------------------------------------------------ "Spur" sub-page (was reaper_to_e16.lua)
local SPUR_PROFILES = { { fx = "StereoEncoder", params = { "azimuth", "elevation", "roll", "width" } },
  { fx = "SceneRotator", params = { "yaw", "pitch", "roll" } } }
local SKIPW = { angle = true }
local function abbr(s)
  local w = {}
  for word in s:gmatch("%w+") do if not SKIPW[word:lower()] then w[#w + 1] = word end end
  if #w == 0 then return "" end
  if #w == 1 then return w[1]:sub(1, 4) end
  if w[2]:match("^%d") then return w[1]:sub(1, 3) .. w[2]:sub(1, 1) end
  return w[1]:sub(1, 2) .. w[2]:sub(1, 2)
end
local function shortText(s)
  local n = s:match("[-+]?%d+%.?%d*")
  if not n then return abbr(s) end
  local f = tonumber(n)
  if s:find(n .. "%s*[kK]") then f = f * 1000 end
  return fmt4(f, s)
end
local function fxSlot(tr, fx, p)
  local _, name = r.TrackFX_GetParamName(tr, fx, p, "")
  return { label = abbr(name), full = name,
    get = function() return r.TrackFX_GetParamNormalized(tr, fx, p) end, ring = function(v) return v end,
    text = function() local _, s = r.TrackFX_GetFormattedParamValue(tr, fx, p, ""); return s end,
    turn = function(d) r.TrackFX_SetParamNormalized(tr, fx, p, clamp(r.TrackFX_GetParamNormalized(tr, fx, p) + d * 0.005, 0, 1)) end }
end
local function onoff(v) return v > 0.5 and "On" or "Off" end
local SPUR_TRACK = {
  { "Vol", "Volume", "D_VOL", function(v) return fmtDBf(v) end, function(v) return dbRing(v) / 127 end,
    function(v, d) return toVol(toDb(v) + d * 0.5) end },
  { "Pan", "Pan", "D_PAN", function(v) return string.format("%.0f %%", v * 100) end, function(v) return (v + 1) / 2 end,
    function(v, d) return clamp(v + d * 0.01, -1, 1) end },
  { "Mute", "Mute", "B_MUTE", onoff, function(v) return v end },
  { "Solo", "Solo", "I_SOLO", onoff, function(v) return v > 0 and 1 or 0 end },
  { "Rec", "Rec arm", "I_RECARM", onoff, function(v) return v end },
  { "Phs", "Phase", "B_PHASE", onoff, function(v) return v end },
  { "Wdth", "Width", "D_WIDTH", function(v) return string.format("%.0f %%", v * 100) end, function(v) return (v + 1) / 2 end,
    function(v, d) return clamp(v + d * 0.01, -1, 1) end },
}
local function trackSlot(tr, e)
  local key = e[3]
  local function get() return r.GetMediaTrackInfo_Value(tr, key) end
  return { label = e[1], full = e[2], get = get, ring = e[5], text = function() return e[4](get()) end,
    turn = e[6] and function(d) r.SetMediaTrackInfo_Value(tr, key, e[6](get(), d)) end,
    push = (not e[6]) and function() r.SetMediaTrackInfo_Value(tr, key, get() > 0 and 0 or 1) end }
end
local spur = { sig = nil, at = 0, slots = {}, vals = {} }
local function spurBuild(tr)
  local s = {}
  if tr then
    local nTcp = r.CountTCPFXParms and r.CountTCPFXParms(0, tr) or 0
    if nTcp > 0 then
      for i = 0, min(nTcp, 16) - 1 do
        local ok, fx, p = r.GetTCPFXParm(0, tr, i)
        if ok then s[#s + 1] = fxSlot(tr, fx, p) end
      end
    else
      local hit
      for fx = 0, r.TrackFX_GetCount(tr) - 1 do
        local _, name = r.TrackFX_GetFXName(tr, fx, "")
        for _, pr in ipairs(SPUR_PROFILES) do
          if not hit and name:lower():find(pr.fx:lower(), 1, true) then hit = { fx, pr } end
        end
      end
      if hit then
        for _, pat in ipairs(hit[2].params) do
          for p = 0, r.TrackFX_GetNumParams(tr, hit[1]) - 1 do
            local _, pn = r.TrackFX_GetParamName(tr, hit[1], p, "")
            if pn:lower():find(pat, 1, true) then s[#s + 1] = fxSlot(tr, hit[1], p); break end
          end
        end
      else
        for _, e in ipairs(SPUR_TRACK) do s[#s + 1] = trackSlot(tr, e) end
      end
    end
  end
  spur.slots = s
end
local function spurUpdate(now)
  local tr = selTrack()
  local sig = tr and (guid(tr) .. ":" .. r.TrackFX_GetCount(tr) .. ":" .. (r.CountTCPFXParms and r.CountTCPFXParms(0, tr) or 0)) or "none"
  if sig ~= spur.sig or now - spur.at > 2 then
    if sig ~= spur.sig then spur.vals = {} end
    spur.sig, spur.at = sig, now
    spurBuild(tr)
  end
end

-- ------------------------------------------------------------ E16 page-1 output
local function e16a(cc, v, force) out(e16Out, A1, cc, v, force) end
local function e16b(cc, v, force) out(e16Out, B1, cc, v, force) end
local function txt(st, base, len, s, force)
  s = ascii(s or ""):sub(1, len)
  s = s .. string.rep(" ", len - #s)
  for i = 1, len do out(e16Out, st, base + i - 1, s:byte(i), force) end
end
local function flashE16(e, v4, full)
  if not e16Out then return end
  if full then txt(B1, 0, 15, full, true); out(e16Out, B1, 15, 1, true) end
  if v4 and e then txt(B1, 16 + (e - 1) * 4, 4, v4, true) end
end

-- ------------------------------------------------------------ slot state (shared by E16 and Twister)
-- returns name4, value4, full name, ring 0-127 or nil, colour entry, blink, value text
local function slotInfo(dev, e, d, now)
  if not d then return nil end
  local k = d.k
  if k == "send" then
    local dest = ctx.T[d.t]
    if not dest then return "", "", "", nil, colOf("cSend") end
    local name = nm(dest)
    local i = sendTo(ctx.eff, dest)
    if not i then return four(name), "--", name .. ": kein Send", nil, colOf("cSend"), false, "kein Send" end
    local v = r.GetTrackSendInfo_Value(ctx.eff, 0, i, "D_VOL")
    local muted = r.GetTrackSendInfo_Value(ctx.eff, 0, i, "B_MUTE") == 1
    local mode = floor(r.GetTrackSendInfo_Value(ctx.eff, 0, i, "I_SENDMODE"))
    local c = muted and colOf("cMute") or mode ~= 0 and colOf("cPre") or colOf("cSend")
    local mt = mode == 3 and " Pre" or mode == 1 and " PreFX" or ""
    return four(name), muted and "MUTE" or fmtDB4(v), "Send " .. name .. " " .. fmtDBf(v) .. mt .. (muted and " stumm" or ""),
      dbRing(v), c, muted, fmtDBf(v) .. mt .. (muted and " MUTE" or "")
  elseif k == "tgt" then
    local t = ctx.T[d.t]
    if not t then return "", "", "", nil, colOf("cMeter") end
    local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
    local muted = r.GetMediaTrackInfo_Value(t, "B_MUTE") == 1
    local key = dev .. e
    local show = now - (S.turnAt[key] or -1e9) < SHOW_FADER
    local ring, c = S.met[guid(t)] or 0, colOf("cMeter")
    if show then ring, c = dbRing(v), colOf("cFader")
    elseif muted then ring = dbRing(v) end           -- v8.5: muted blinks like on the plugin pages
    return four(nm(t)), muted and "MUTE" or fmtDB4(v), nm(t) .. " " .. fmtDBf(v) .. (muted and " stumm" or ""), ring, c,
      muted, fmtDBf(v) .. (muted and " MUTE" or "")
  elseif k == "master" then
    local m = ctx.master
    local v = r.GetMediaTrackInfo_Value(m, "D_VOL")
    local muted = r.GetMediaTrackInfo_Value(m, "B_MUTE") == 1
    return "MAST", muted and "MUTE" or fmtDB4(v), "Master " .. fmtDBf(v) .. (muted and " stumm" or ""), dbRing(v),
      muted and colOf("cMute") or colOf("cMaster"), muted, fmtDBf(v)
  elseif k == "track" then
    local t = ctx.sel
    if not t then return "----", "", "keine Spur", nil, colOf("cTrack") end
    local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
    local solo = r.GetMediaTrackInfo_Value(t, "I_SOLO") ~= 0
    local muted = r.GetMediaTrackInfo_Value(t, "B_MUTE") == 1
    local ms = r.GetMediaTrackInfo_Value(t, "B_MAINSEND") == 1
    local c = solo and COLBY.gelb or muted and colOf("cMute") or colOf("cTrack")
    return four(nm(t)), solo and "SOLO" or muted and "MUTE" or fmtDB4(v),
      nm(t) .. " " .. fmtDBf(v) .. (ms and "" or " (kein Master-Send)"), dbRing(v), c, muted or solo, fmtDBf(v)
  elseif k == "scroll" then
    local sb, list, idx = curSub("mft")
    return "", "", subName(sb), floor((idx - 1) / max(1, #list - 1) * 127 + 0.5), nil, false, "Ebene halten"
  elseif k == "menu" then
    local o = OPTS[d.o]
    local cur = 1
    for i, c in ipairs(o.ch) do if c[1] == scfg[o.k] then cur = i end end
    local c = o.col and COLBY[o.ch[cur][1]] or COLBY.weiss
    return o.n, o.ch[cur][2], o.t .. ": " .. o.ch[cur][3], floor((cur - 1) / max(1, #o.ch - 1) * 127 + 0.5), c, false, o.ch[cur][3]
  elseif k == "spur" then
    local s = spur.slots[d.i]
    if not s then return "", "", "", nil, COLBY.weiss end
    local v = s.get()
    return s.label, shortText(s.text()), s.full .. " " .. s.text(), floor(clamp(s.ring(v), 0, 1) * 127 + 0.5), COLBY.weiss,
      false, s.text()
  end
end

-- ------------------------------------------------------------ actions
local function accStep(key, delta, now)
  local d = abs(delta)
  local last = S.lastTurn[key]
  S.lastTurn[key] = now
  local m = d <= 1 and 1 or d == 2 and 1.5 or d <= 3 and 2 or d <= 5 and 3 or d <= 8 and 5 or 8
  if last and now - last < 0.04 then m = m * 2 end
  local s = min(m * STEP_DB, 6)
  return delta < 0 and -s or s
end
local function capped(v, nv, on)               -- v8.5: max 0 dB (what is already above stays, turning up never jumps down)
  if on and nv > 1 and nv > v then return math.max(v, 1) end
  return nv
end
local function volStep(t, dbs)
  local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
  r.SetMediaTrackInfo_Value(t, "D_VOL", capVol(t, v, toVol(toDb(v) + dbs)))
end
local function cycleMode(m)
  if scfg.preFx == "1" then return m == 0 and 3 or m == 3 and 1 or 0 end
  return m == 0 and 3 or 0
end
local MODE_TXT = { [0] = "POST", [3] = "PRE", [1] = "PRFX" }
local function undo(s) r.Undo_OnStateChange(s) end
local PUSHES = { prepost = { "pp", "jump" }, mute = { "mute", "jump" }, mute_pp = { "mute", "pp" }, pp_mute = { "pp", "mute" } }

local function tap(dev, e, d, n, now)
  if not d then return end
  local key = dev .. e
  if d.k == "send" then
    local dest = ctx.T[d.t]
    if not dest then return end
    local a = (PUSHES[scfg.push] or PUSHES.prepost)[min(n, 2)]
    if a == "jump" then selectOnly(dest); flashE16(nil, nil, "> " .. nm(dest)); return end
    local i = sendTo(ctx.eff, dest)
    if not i then flashE16(e, "OFF", nm(dest) .. ": kein Send"); return end
    if a == "mute" then
      local m = r.GetTrackSendInfo_Value(ctx.eff, 0, i, "B_MUTE") == 1
      r.SetTrackSendInfo_Value(ctx.eff, 0, i, "B_MUTE", m and 0 or 1)
      undo("E16: Send stumm"); flashE16(e, m and "AN" or "MUTE", "Send " .. nm(dest) .. (m and " an" or " stumm"))
    else
      local nmode = cycleMode(floor(r.GetTrackSendInfo_Value(ctx.eff, 0, i, "I_SENDMODE")))
      r.SetTrackSendInfo_Value(ctx.eff, 0, i, "I_SENDMODE", nmode)
      undo("E16: Send Pre/Post"); flashE16(e, MODE_TXT[nmode], "Send " .. nm(dest) .. " " .. MODE_TXT[nmode])
    end
  elseif d.k == "tgt" then
    local t = ctx.T[d.t]
    if not t then return end
    S.turnAt[key] = now
    if n >= 2 then selectOnly(t); flashE16(nil, nil, "> " .. nm(t)); return end
    local m = r.GetMediaTrackInfo_Value(t, "B_MUTE") == 1
    r.SetMediaTrackInfo_Value(t, "B_MUTE", m and 0 or 1)
    undo("E16: Ziel stumm"); flashE16(e, m and fmtDB4(r.GetMediaTrackInfo_Value(t, "D_VOL")) or "MUTE", nm(t) .. (m and " an" or " stumm"))
  elseif d.k == "master" then
    local m = ctx.master
    if n >= 2 then
      local mu = r.GetMediaTrackInfo_Value(m, "B_MUTE") == 1
      r.SetMediaTrackInfo_Value(m, "B_MUTE", mu and 0 or 1)
      undo("E16: Master stumm"); flashE16(e, mu and "AN" or "MUTE", "Master" .. (mu and " an" or " stumm"))
    else selectOnly(m); flashE16(nil, nil, "> MASTER") end
  elseif d.k == "track" then
    local t = ctx.sel
    if not t then return end
    if n >= 3 and scfg.triple == "1" then
      local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
      r.SetMediaTrackInfo_Value(t, "D_VOL", v > 0 and 0 or 1)
      undo("E16: Spur 0 dB/-inf"); flashE16(e, v > 0 and "-inf" or "0", nm(t) .. (v > 0 and " -inf" or " 0 dB"))
    elseif n == 2 and scfg.dbl == "1" then
      local on = r.GetMediaTrackInfo_Value(t, "B_MAINSEND") == 1
      r.SetMediaTrackInfo_Value(t, "B_MAINSEND", on and 0 or 1)
      undo("E16: Master-Send"); flashE16(e, on and "MS-" or "MS+", nm(t) .. " Master-Send " .. (on and "aus" or "an"))
    else
      local so = r.GetMediaTrackInfo_Value(t, "I_SOLO") ~= 0
      r.SetMediaTrackInfo_Value(t, "I_SOLO", so and 0 or SOLO_MODE)
      undo("E16: Spur solo"); flashE16(e, so and "solo" or "SOLO", nm(t) .. (so and " solo aus" or " SOLO"))
    end
  elseif d.k == "menu" then
    local o = OPTS[d.o]
    local cur = 1
    for i, c in ipairs(o.ch) do if c[1] == scfg[o.k] then cur = i end end
    local c = o.ch[cur % #o.ch + 1]
    setCfg(o.k, c[1]); flashE16(e, c[2], o.t .. ": " .. c[3])
  elseif d.k == "spur" then
    local s = spur.slots[d.i]
    if s and s.push then s.push(); flashE16(e, shortText(s.text()), s.full .. " " .. s.text()) end
  end
end
local function maxTaps(d)
  if not d then return 0 end
  if d.k == "track" then return scfg.triple == "1" and 3 or scfg.dbl == "1" and 2 or 1 end
  if d.k == "send" or d.k == "tgt" or d.k == "master" then return 2 end
  if d.k == "menu" then return 1 end
  if d.k == "spur" then local s = spur.slots[d.i]; return (s and s.push) and 1 or 0 end
  return 0
end
local function nextSub(dev, dir)
  local _, list, k = curSub(dev)
  k = (k - 1 + (dir or 1)) % #list + 1
  S.subKey[dev] = subKey(list[k])
  if dev == "e16" then S.sub = k; S.subFlash = r.time_precise()
    flashE16(nil, nil, subName(list[k]))
  else
    S.mftSub = k
    viewSysex({ 6, MFT_BANK }, "Sends · " .. subName(list[k]))
  end
  mftForce = true
end
SND.nextSub = nextSub

local function turnSlot(dev, e, d, delta, now)
  if not d then return end
  local key = dev .. e
  if d.k == "send" then
    local dest = ctx.T[d.t]
    if not dest or not ctx.eff or ctx.eff == dest then return end
    local i = sendTo(ctx.eff, dest)
    if not i then
      if scfg.targets == "sends" or delta <= 0 then flashE16(e, "--", nm(dest) .. ": kein Send"); return end
      i = r.CreateTrackSend(ctx.eff, dest)      -- missing send: created on the first turn up
      r.SetTrackSendInfo_Value(ctx.eff, 0, i, "D_VOL", 0)
    end
    local v = r.GetTrackSendInfo_Value(ctx.eff, 0, i, "D_VOL")
    local nv = capped(v, toVol(toDb(v) + accStep(key, delta, now)), scfg.capSend == "1")
    r.SetTrackSendInfo_Value(ctx.eff, 0, i, "D_VOL", nv)
    undo("E16: Send-Pegel")
    flashE16(e, fmtDB4(nv), "Send " .. nm(dest) .. " " .. fmtDBf(nv))
  elseif d.k == "tgt" then
    local t = ctx.T[d.t]
    if not t then return end
    S.turnAt[key] = now
    volStep(t, accStep(key, delta, now)); undo("E16: Ziel-Pegel")
    local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
    flashE16(e, fmtDB4(v), nm(t) .. " " .. fmtDBf(v))
  elseif d.k == "master" then
    local g = S.g[dev][e]
    if scfg.masterNav == "1" and not (g and g.down) then navigate(delta > 0 and 1 or -1); return end   -- like the MultiEQ: turn = track, press + turn = master
    volStep(ctx.master, accStep(key, delta, now)); undo("E16: Master-Pegel")
    local v = r.GetMediaTrackInfo_Value(ctx.master, "D_VOL")
    flashE16(e, fmtDB4(v), "Master " .. fmtDBf(v))
  elseif d.k == "track" then
    local g = S.g[dev][e]
    if g and g.down then navigate(delta > 0 and 1 or -1); return end   -- press + turn = select the next track
    local t = ctx.sel
    if not t then return end
    volStep(t, accStep(key, delta, now)); undo("E16: Spur-Pegel")
    local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
    flashE16(e, fmtDB4(v), nm(t) .. " " .. fmtDBf(v))
  elseif d.k == "scroll" then nextSub("mft", delta > 0 and 1 or -1)
  elseif d.k == "menu" then
    local o = OPTS[d.o]
    local cur = 1
    for i, c in ipairs(o.ch) do if c[1] == scfg[o.k] then cur = i end end
    local nx = clamp(cur + (delta > 0 and 1 or -1), 1, #o.ch)
    if nx ~= cur then setCfg(o.k, o.ch[nx][1]) end
    flashE16(e, o.ch[nx][2], o.t .. ": " .. o.ch[nx][3])
  elseif d.k == "spur" then
    local s = spur.slots[d.i]
    if s and s.turn then s.turn(delta); flashE16(e, shortText(s.text()), s.full .. " " .. s.text()) end
  end
end

-- ------------------------------------------------------------ gestures
function SND.input(dev, e, kind, val, now)
  refreshCtx()
  local sb = curSub(dev)
  local map = slotMap(dev, sb)
  local d = map[e]
  local g = S.g[dev][e] or {}
  S.g[dev][e] = g
  if kind == "press" then
    if val then g.down, g.t0, g.moved, g.long = true, now, false, false; return end
    if not g.down then return end
    g.down = false
    if g.moved or g.long then g.taps = 0; return end
    local most = maxTaps(d)
    if most == 0 then return end
    g.taps = (g.taps or 0) + 1
    g.tapT = now
    if g.taps >= most then local n = g.taps; g.taps = 0; tap(dev, e, d, n, now) end
    return
  end
  if val == 0 then return end
  if dev == "mft" then val = clamp(val, -3, 3) end
  if g.down then
    if now - g.t0 < PRESS_SETTLE then return end
    g.moved = true
  end
  if dev == "mft" and e == 8 and g.down then nextSub("mft", val > 0 and 1 or -1); return end   -- press + turn 8 = group
  turnSlot(dev, e, d, val, now)
end
local function longPress(dev, e)
  if dev == "e16" and e == 16 then nextSub("e16", 1)
  elseif dev == "mft" and e == 8 then nextLayer("mft") end
end
function SND.tick(now)
  for _, dev in ipairs({ "e16", "mft" }) do
    for e, g in pairs(S.g[dev]) do
      if g.down and not g.moved and not g.long and now - g.t0 >= HOLD_S then g.long = true; g.taps = 0; longPress(dev, e) end
      if not g.down and (g.taps or 0) > 0 and now - g.tapT > TAP_S then
        local n = g.taps; g.taps = 0
        refreshCtx()
        tap(dev, e, slotMap(dev, curSub(dev))[e], n, now)
      end
    end
  end
end

-- ------------------------------------------------------------ rendering
local function meters(now)
  if now - S.metT < MET_T then return end
  S.metT = now
  for _, t in ipairs(ctx.T) do
    local nch = clamp(floor(r.GetMediaTrackInfo_Value(t, "I_NCHAN")), 1, 64)
    local peak = 0
    for c = 0, nch - 1 do local p = r.Track_GetPeakInfo(t, c); if p > peak then peak = p end end
    local d = peak > 0 and 20 * log(peak, 10) or -150
    S.met[guid(t)] = d <= MET_DB and 0 or d >= 0 and 127 or floor(1 + (d - MET_DB) * 126 / -MET_DB + 0.5)
  end
end
local ringOff = {}
local function renderE16Page1(now, force)
  if not e16Out then return end
  local sb = curSub("e16")
  local map = slotMap("e16", sb)
  if sb and sb.kind == "spur" then spurUpdate(now) end
  local phase = floor(now / BLINK_T) % 2 == 0
  local title
  if sb and sb.kind == "menu" then title = "MENUE E16"
  elseif sb and sb.kind == "spur" then local t = ctx.sel; title = t and (floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER")) .. " " .. nm(t)) or "keine Spur"
  else
    title = ctx.eff and nm(ctx.eff) or "keine Spur"
    if ctx.eff and ctx.sel ~= ctx.eff then title = "<" .. title end
  end
  txt(A1, 0, 15, title, force)
  for e = 1, 16 do
    local name, _, _, ring, c, blink = slotInfo("e16", e, map[e], now)
    txt(A1, 16 + (e - 1) * 4, 4, name or "", force)
    if c then e16a(79 + e, c[4], force) end
    if ring and not (blink and not phase) then e16b(79 + e, ring, force or ringOff[e]); ringOff[e] = false
    else e16b(95 + e, 0, force or not ringOff[e]); ringOff[e] = true end       -- resend: the E16 caches nothing
  end
end
function SND.renderMft(e, force)
  local sb = curSub("mft")
  local map = slotMap("mft", sb)
  local d = map[e]
  local now = r.time_precise()
  local name, v4, full, ring, c, blink, vt = slotInfo("mft", e, d, now)
  local cc = MFT_CC + e - 1
  local col, anim, ind = 0, DIM_OFF, 70
  if d and d.k == "scroll" then col, anim, ind = LAYER_COL[6], 0, 95
  elseif e == 8 then col, anim, ind = LAYER_COL[6], ring and 0 or DIM_OFF, 95   -- 8 keeps the layer colour
  elseif c and ring then col, anim, ind = c[5], 0, 95 end
  if blink then anim = BLINK end
  out(mftOut, 0xB0 + MFT_TURN_CH, cc, ring or 0, force)
  out(mftOut, 0xB0 + MFT_COL_CH, cc, col, force)
  out(mftOut, 0xB0 + MFT_ANIM_CH, cc, anim, force)
  out(mftOut, 0xB0 + MFT_RING_CH, cc, ind, force)
  local label = ""
  if d and d.k == "scroll" then label = subName(sb) .. "\nhalten = Ebene"
  elseif d and (d.k == "send" or d.k == "tgt") then
    local t = ctx.T[d.t]
    label = t and (nm(t) .. "\n" .. (d.k == "send" and "Send" or "Ziel")) or ""
  end
  view(e, label, vt or "", ring or 0, force)
  viewColor(e, c and c[6] or "6495ED", force)
end
function SND.frame(now, full)
  local rev = r.GetExtState(SEXT, "rev")
  if rev ~= srev then srev = rev; loadCfg(); mftForce = true; full = true end
  refreshCtx()
  meters(now)
  renderE16Page1(now, full)
  if mftLayer == 6 and not SND.twisterOn() then mftLayer = 1; mftForce = true end
end
function SND.init()
  loadCfg()
  srev = r.GetExtState(SEXT, "rev")
  refreshCtx()
  if e16Out then out(e16Out, A1, 127, 0, true) end
  local T = ctx.T
  msg(string.format("Sends/Ziele: %d Ziel(e)%s · Layout %s · E16 Seite 1 = Sends/Ziele/Spur/Menü (16 halten)",
    #T, scfg.targets == "sends" and " (Sends der Spur)" or "", scfg.layout))
end
function SND.exit()
  if e16Out then r.SendMIDIMessageToHardware(e16Out, string.char(A1, 127, 0)) end
end
SND.ctx, SND.S, SND.curSub, SND.slotMap, SND.slotInfo, SND.setCfg = ctx, S, curSub, slotMap, slotInfo, setCfg
end
sndModule()

local function act(dev, e, a, L)                     -- a press action
  if a == "bypass" then omniBypass()
  elseif a == "solo" then
    local tr = selTrack()
    if tr then local s = trackState(tr); r.SetMediaTrackInfo_Value(tr, "I_SOLO", s and 0 or SOLO_MODE) end
  elseif a == "mute" then
    local tr = selTrack()
    if tr then local _, m = trackState(tr); r.SetMediaTrackInfo_Value(tr, "B_MUTE", m and 0 or 1) end
  elseif a == "layer" then nextLayer(dev)
  elseif a == "eqon" or a == "eqlock" then
    local s = slotOf(L, e)
    local q = eqList(s.k)[s.inst]
    if not q then return end
    if a == "eqlock" then
      setLocked(s.inst, s.band, not locked(s.inst, s.band, s.k), s.k)
      msg((s.k == "feq" and "H" or string.char(64 + s.inst)) .. s.band .. (locked(s.inst, s.band, s.k) and ": Frequenz gesperrt" or ": Frequenz frei"))
    else
      local pe = q.P.e and q.P.e[s.band]
      if pe then toggle(q, pe) else msg("Band an/aus: kein Parameter gefunden", true) end
    end
    flash(dev, e, nil, a == "eqlock" and "lock" or "on")
    return
  elseif type(a) == "table" then                     -- a target: toggle or cycle it
    local q, p = resolve(a)
    if not p then return end
    if a.spec.m == "cyc" then cycle(q, p) else toggle(q, p) end
    showWindow(q)
  end
  flash(dev, e, nil, "x")
end

local function press(dev, e, down, now)
  local L = layerOf(dev)
  if not L then return end
  local s = slotOf(L, e)
  local g = G[dev][e] or {}
  G[dev][e] = g
  if down then
    g.down, g.t0, g.mode, g.moved = true, now, nil, false
    return
  end
  if not g.down then return end
  g.down = false
  local held = now - g.t0 >= HOLD
  local moved = g.moved
  g.mode = nil
  if moved or not s then g.taps = 0; return end
  if held then                                      -- held and let go without turning
    g.taps = 0
    if s.long then act(dev, e, s.long, L) end
    return
  end
  local most = s.tap3 and 3 or s.tap2 and 2 or s.tap1 and 1 or 0
  if most == 0 then return end
  g.taps = (g.taps or 0) + 1
  g.tapT = now
  if g.taps >= most then                            -- no more presses can follow: act now
    local a = g.taps == 3 and s.tap3 or g.taps == 2 and s.tap2 or s.tap1
    g.taps = 0
    act(dev, e, a, L)
  end
end

local function turn(dev, e, d, now)
  local L = layerOf(dev)
  local s = slotOf(L, e)
  if not s or d == 0 then return end
  local g = G[dev][e] or {}
  G[dev][e] = g
  if d > 3 then d = 3 elseif d < -3 then d = -3 end   -- Twister on "velocity": its own jumps capped
  local m = accel(g, abs(d), now)
  if g.down and now - g.t0 < PRESS_SETTLE then return end   -- wobble while pressing
  if g.down then
    g.moved = true
    if not g.mode then g.mode = (now - g.t0 >= HOLD and (s.hturn or s.eq)) and "h" or "p" end
  end
  local mode = g.down and g.mode or nil
  if s.eq then
    local q = eqList(s.k)[s.inst]
    if not q then return end
    local what = mode == "h" and "q" or mode == "p" and "g" or "f"
    if what == "f" and locked(s.inst, s.band, s.k) then flash(dev, e, nil, "lock") return end
    local p = q.P[what] and q.P[what][s.band]
    if not p then return end
    step(q, p, what == "f" and "f" or what == "q" and "q" or "db", d, m)
    showWindow(q)
    flash(dev, e, mode)
    return
  end
  local src = (mode == "h" and (s.hturn or s.pturn)) or (mode == "p" and s.pturn) or s.turn
  if mode and not (mode == "h" and s.hturn) and not s.pturn then src = s.turn end   -- no press layer: plain turn
  if src == "nav" then navigate(d > 0 and 1 or -1)
  elseif src == "master" then masterStep(d, m)
  elseif type(src) == "table" then
    for _, t in ipairs(src) do
      local q, p = resolve(t)
      if p == -1 then
        r.TrackFX_NavigatePresets(q.tr, q.fx, d > 0 and 1 or -1)
        showWindow(q)
      elseif p then
        if t.spec.m == "tog" then setNorm(q, p, d > 0 and 1 or 0)
        elseif t.spec.m == "cyc" then cycle(q, p)
        else stepNorm(q, p, d, m) end
        showWindow(q)
      end
    end
  end
  flash(dev, e, mode, "turn")
end

local function tick(now)                                -- timers: hold, multiple presses
  for _, dev in ipairs({ "mft", "e16" }) do
    local L = layerOf(dev)
    for e, g in pairs(G[dev]) do
      local s = slotOf(L, e)
      if g.down and not g.mode and not g.moved and s and (s.hturn or s.eq or s.long) and now - g.t0 >= HOLD then g.mode = "h" end
      if not g.down and (g.taps or 0) > 0 and now - g.tapT > TAP then
        local a = s and (g.taps == 2 and s.tap2 or g.taps == 1 and s.tap1)
        g.taps = 0
        if a then act(dev, e, a, L) end
      end
    end
  end
end

-- ---------------------------------------------------------------- input
local function readInput(now)
  local events, idx, newest = {}, 0, nil
  while idx < 256 do
    local seq, buf, _, dev = r.MIDI_GetRecentInputEvent(idx)
    if seq == 0 or (lastSeq and seq <= lastSeq) then break end
    if idx == 0 then newest = seq end
    table.insert(events, 1, { buf, dev & 0xFFFF })
    idx = idx + 1
  end
  if newest then lastSeq = newest end
  for _, ev in ipairs(events) do
    local buf, dev = ev[1], ev[2]
    if #buf == 3 then
      local st, d1, d2 = buf:byte(1, 3)
      if DEBUG then msg(string.format("in dev %d: %02X %d %d", dev, st, d1, d2)) end
      if dev == mftIn and mftLayer == 6 and d1 >= MFT_CC and d1 < MFT_CC + 16 and SND.owns("mft", d1 - MFT_CC + 1)
        and (st == 0xB0 + MFT_TURN_CH or st == 0xB0 + MFT_PUSH_CH) then
        if st == 0xB0 + MFT_TURN_CH then SND.input("mft", d1 - MFT_CC + 1, "turn", d2 - 64, now)
        else SND.input("mft", d1 - MFT_CC + 1, "press", d2 > 0, now) end
      elseif dev == mftIn then
        local e = d1 - MFT_CC + 1
        if st == 0xB0 + MFT_TURN_CH and e >= 1 and e <= 16 then turn("mft", e, d2 - 64, now)
        elseif st == 0xB0 + MFT_PUSH_CH and e >= 1 and e <= 16 then press("mft", e, d2 > 0, now)
        elseif st == 0xB0 + MFT_SYS_CH and d2 == 127 and d1 == MFT_BANK then mftForce = true end
      elseif e16Ins[dev] and st == 0xBF then             -- page 1 (DAW Link, channel 16): Sends / Ziele / Spur / Menü
        if d1 >= 20 and d1 <= 35 then SND.input("e16", d1 - 19, "turn", d2 - 64, now)
        elseif d1 >= 40 and d1 <= 55 then SND.input("e16", d1 - 39, "press", d2 > 0, now) end
      elseif e16Ins[dev] and (st == 0xB0 + E16_IN_EQ or st == 0xB0 + E16_IN_COMP or st == 0xB0 + E16_IN_REV) then
        local page = st == 0xB0 + E16_IN_EQ and E16_PAGE_EQ or st == 0xB0 + E16_IN_COMP and E16_PAGE_COMP or E16_PAGE_REV
        if d1 == 1 then                                    -- the scene says which page is showing
          if d2 ~= e16Page then e16Page = d2; e16Force = true end
        else
          if page ~= e16Page then e16Page = page; e16Force = true end
          if d1 >= 20 and d1 <= 35 then turn("e16", d1 - 19, d2 - 64, now)
          elseif d1 >= 40 and d1 <= 55 then press("e16", d1 - 39, d2 > 0, now) end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- start / main loop
local function describe(list, what)
  if #list == 0 then msg(what .. ": keins gefunden", true) return end
  for i, q in ipairs(list) do
    local parts = {}
    for k, v in pairs(q.P) do parts[#parts + 1] = k .. " " .. #v end
    table.sort(parts)
    msg(string.format("%s %s = %s auf %s%s · %s", what, string.char(64 + i), fxName(q.tr, q.fx), q.where,
      q.master and " (Ersatz vom Master)" or "", table.concat(parts, ", ")))
  end
end

local function keyOf(list)
  local k = ""
  for _, q in ipairs(list) do k = k .. q.guid .. ";" end
  return k
end

local function adopt(old, new, kind, what)
  if keyOf(old) == keyOf(new) then
    for i, q in ipairs(new) do old[i].tr, old[i].fx, old[i].where, old[i].master = q.tr, q.fx, q.where, q.master end
    return old, false
  end
  for _, q in ipairs(new) do q.P, q.names = mapParams(q.tr, q.fx, kind) end
  describe(new, what)
  return new, true
end

-- the tables are swapped, so the layouts (which point at them) are rebuilt after a change
local function rescan(now)
  local st = r.GetProjectStateChangeCount(0)
  local sel = selTrack()
  local selKey = sel and r.GetTrackGUID(sel) or ""
  if st == lastState and selKey == lastSel and now - lastScan < 2 then return end
  if selKey ~= lastSel then mftForce, e16Force = true, true end
  lastState, lastSel, lastScan = st, selKey, now
  local ch, any
  local selT = sel and { sel } or {}
  -- Hall: FDN Reverb and convolver of the selected track, else the master's
  local fd = collect("fdnreverb", selT, "last")
  while #fd > 1 do table.remove(fd) end
  -- the MultiEQ in the slot right before the FDN is the reverb's own EQ (layer 5) and no MultiEQ A/B
  local fe = {}
  if fd[1] and fd[1].fx ~= 0 and fd[1].fx ~= 0x1000000 then
    local pv = fd[1].fx - 1
    if fxName(fd[1].tr, pv):lower():find("multieq", 1, true) then
      fe[1] = { tr = fd[1].tr, fx = pv, where = fd[1].where, master = fd[1].master, guid = r.TrackFX_GetFXGUID(fd[1].tr, pv) or "" }
    end
  end
  -- v8.10/8.11: MultiEQ A/B only from the selected track (both if it has two), no longer from other tracks or the master
  local eq
  if r.GetExtState("seren_E16", "eqScope") == "all" then eq = collect("multieq", allTracks(), "first")
  else
    eq = collect("multieq", selT, "none")        -- v8.11: no master fallback, a clear view
  end
  if fe[1] then for i = #eq, 1, -1 do if eq[i].guid == fe[1].guid then table.remove(eq, i) end end end
  while #eq > 2 do table.remove(eq) end
  EQ, ch = adopt(EQ, eq, "eq", "MultiEQ")
  if ch then lockedCache = {} end
  any = ch
  FEQ, ch = adopt(FEQ, fe, "eq", "Hall-EQ")
  any = any or ch
  if #FEQ == 0 then e16Hall = 4; if mftLayer == 5 then mftLayer = 1 end end
  local om = collect("omnicompressor", selT, "last")
  while #om > 2 do table.remove(om) end
  OMNI, ch = adopt(OMNI, om, "omni", "OmniComp")
  any = any or ch
  local di = collect("directionalcompressor", selT, "last")
  while #di > 1 do table.remove(di) end
  DIR, ch = adopt(DIR, di, "dir", "DirComp")
  any = any or ch
  -- SceneRotator (else AmbiDecoder): selected track, master, monitoring FX, then the tracks from the top
  local ro = collect("scenerotator", selT, "last")
  if #ro == 0 then ro = collect("scenerotator", allTracks(), "none") end
  if #ro == 0 then ro = collect("ambidecoder", selT, "last") end
  if #ro == 0 then ro = collect("ambidecoder", allTracks(), "none") end
  while #ro > 1 do table.remove(ro) end
  ROT, ch = adopt(ROT, ro, "rot", "Rotation")
  any = any or ch
  FDN, ch = adopt(FDN, fd, "fdn", "FDN Reverb")
  any = any or ch
  local cv = collect("convol", selT, "last")
  while #cv > 1 do table.remove(cv) end
  CONV, ch = adopt(CONV, cv, "conv", "Convolver")
  any = any or ch
  if any then build(); mftForce, e16Force = true, true end
end

local token = tostring(r.time_precise()) .. ":" .. math.random(1, 1e9)
local stopped = false

local function frame()
  local now = r.time_precise()
  if r.GetExtState(EXT, "token") ~= token then          -- a newer start took over: stop quietly
    stopped = true
    msg(VERSION .. ": eine neuere Instanz läuft, diese hört auf", true)
    return
  end
  rescan(now)
  readInput(now)
  tick(now)
  SND.tick(now)
  if now - lastAlive > 0.5 then
    lastAlive = now
    r.SetExtState(EXT, "alive", tostring(now), false)     -- Twister View hub leaves bank 4 to us
  end
  local full = now - lastResync > 5
  if full then
    lastResync = now
    viewSysex({ 5 }, "REAPER")                          -- also without the Twister View hub
    viewSysex({ 6, MFT_BANK }, LAYER_NAME[mftLayer])
  end
  if e16Force and e16Out then
    out(e16Out, 0xB0 + E16_A, 127, 0, true)
    for k in pairs(sent) do if k:find("^" .. e16Out .. ":") then sent[k] = nil end end
  end
  SND.frame(now, full)
  renderMft(full or mftForce)
  renderE16(full or e16Force)
  mftForce, e16Force = false, false
end

local function loop()
  frame()
  if not stopped then r.defer(loop) end
end

local function find(count, name, match)
  for i = 0, count() - 1 do
    local ok, n = name(i, "")
    if ok and n:find(match, 1, true) then return i end
  end
end

local function learnConflicts()
  local hit = {}
  for _, tr in ipairs(allTracks()) do
    for fx = 0, r.TrackFX_GetCount(tr) - 1 do
      for p = 0, r.TrackFX_GetNumParams(tr, fx) - 1 do
        local ok, m1 = r.TrackFX_GetNamedConfigParm(tr, fx, "param." .. p .. ".learn.midi1")
        local ok2, m2 = r.TrackFX_GetNamedConfigParm(tr, fx, "param." .. p .. ".learn.midi2")
        m1, m2 = ok and tonumber(m1), ok2 and tonumber(m2)
        if m1 and m2 and m1 == 0xB0 + MFT_TURN_CH and m2 >= MFT_CC and m2 < MFT_CC + 16 then
          local _, pn = r.TrackFX_GetParamName(tr, fx, p, "")
          hit[#hit + 1] = fxName(tr, fx) .. ": " .. pn .. " (CC " .. m2 .. ")"
        end
      end
    end
  end
  if #hit > 0 then
    msg("Achtung: MIDI-Learn auf Bank-4-CCs, das reagiert doppelt:", true)
    for _, h in ipairs(hit) do msg("  " .. h, true) end
  end
end

local function init()
  mftIn = find(r.GetNumMIDIInputs, r.GetMIDIInputName, MFT_MATCH)
  mftOut = find(r.GetNumMIDIOutputs, r.GetMIDIOutputName, MFT_MATCH)
  local e16In
  for i = 0, r.GetNumMIDIInputs() - 1 do
    local ok, n = r.GetMIDIInputName(i, "")
    if ok and n:find(E16_MATCH, 1, true) then e16Ins[i] = true; e16In = e16In or i end
  end
  e16Out = find(r.GetNumMIDIOutputs, r.GetMIDIOutputName, E16_MATCH)
  viewOut = find(r.GetNumMIDIOutputs, r.GetMIDIOutputName, VIEW_MATCH)
  msg("E16+Twister " .. VERSION .. " geladen · Twister " .. (mftIn and "da" or "fehlt") ..
    " · E16 " .. (e16In and "da" or "fehlt") .. " · Twister View " .. (viewOut and "da" or "fehlt"))
  if not mftIn and not e16In then
    r.ShowMessageBox("Weder Twister noch E16 als MIDI-Eingang gefunden.\n" ..
      "Preferences > MIDI Devices: Eingänge aktivieren.", "E16+Twister", 0)
    return
  end
  local alive = tonumber(r.GetExtState(EXT, "alive"))
  if alive and r.time_precise() - alive < 1.5 then
    msg("Achtung: es lief schon ein MultiEQ-Skript. Neuere Fassungen beenden sich jetzt selbst;", true)
    msg("eine alte (v5.1-v5.3.1) läuft weiter und stört (Blinken, Bypass, Ratio). Reaper neu starten oder", true)
    msg("in der Aktionsliste die alte Instanz beenden (Aktion nochmal starten > 'Terminate instances').", true)
    r.ShowMessageBox("Es läuft schon ein MultiEQ-Skript (vielleicht die alte Version).\n" ..
      "Zwei Instanzen stören sich: Blinken, Bypass und Ratio gehen dann nicht richtig.\n\n" ..
      "Bitte Reaper neu starten oder die alte Instanz beenden.", "MultiEQ " .. VERSION, 0)
  end
  r.SetExtState(EXT, "token", token, false)
  lastSeq = r.MIDI_GetRecentInputEvent(0)                 -- ignore what happened before the start
  learnConflicts()
  SND.init()
  r.atexit(function()
    if stopped then return end                            -- the newer instance owns the devices now
    SND.exit()
    r.SetExtState(EXT, "alive", "", false)
    if e16Out then r.SendMIDIMessageToHardware(e16Out, string.char(0xB0 + E16_A, 127, 0)) end
    viewSysex({ 6, MFT_BANK }, "")
    if viewOut then r.SendMIDIMessageToHardware(viewOut, string.char(0xF0, 0x7D, 0x4D, 8, MFT_BANK, 127, 0xF7)) end
    for e = 1, 16 do
      viewSysex({ 1, MFT_BANK, e - 1 }, ""); viewSysex({ 2, MFT_BANK, e - 1 }, "")
      if mftOut then
        r.SendMIDIMessageToHardware(mftOut, string.char(0xB0 + MFT_ANIM_CH, MFT_CC + e - 1, 0))
        r.SendMIDIMessageToHardware(mftOut, string.char(0xB0 + MFT_RING_CH, MFT_CC + e - 1, 0))
      end
    end
  end)
  loop()
end

SEREN_DBG = { SND = SND, layer = function() return mftLayer end }   -- for the tests
init()
