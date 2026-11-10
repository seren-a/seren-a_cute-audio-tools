-- E16_MultiEQ.lua · seren.a 3D v5.4 · OXI E16, Lua API 1.3 (needs midi.listen / midi.onCC)
-- Scene for Reaper_MultiEQ.lua. Page 1 = MultiEQ (1-3, 5-7 = A band 1-6, 4 = Directional, 9-14 = B;
-- with Directional + MultiEQ + Omni: 1-7 = DirectionalCompressor, 9-14 = MultiEQ A),
-- page 3 = compressors (encoder 8 press: OmniCompressor <-> DirectionalCompressor).
-- Pages are switched with Shift + knob 1 / 3. Use the scene file MultiEQ.oxie16: in it, the
-- encoders on pages 1 and 3 are wired to this script (a scene made by hand has to be wired too).
-- pages: MultiEQ,-,Comp
-- Built on DAW Link v2.4 (hardware-verified: relative turns, pushes, display, rings); only
-- the MIDI channels and the ring colours per band state are new.
--
-- Separate channels from DAW Link / the reverb remote, so both can stay set up in Reaper:
--   out (to Reaper): page 1 on channel 13, page 3 on channel 12:
--        turn e -> CC 19+e (20-35), value 64+steps; push e -> CC 39+e (40-55) = 127, release -> 0;
--        CC 1 = page number, on every page change and once a second (so Reaper draws that page)
--   in  A = channel 12: CC 0-14 title, CC 16-79 slot names (4 characters each), CC 127 clear
--   in  B = channel 10: CC 0-14 flash title, CC 15 show it, CC 16-79 slot values (flash),
--                       CC 80-95 ring 1-16 (0-127), CC 96-111 ring off
--   in  C = channel 8:  CC 1-16 state: +1 off, +2 frequency locked, +4 Q mode, +8 gain mode,
--                       +16 compressor taken from the master (white);
--                       64 = solo (yellow, blinks), 65 = muted, not soloed (orange, blinks), 66 = muted (red, blinks),
--                       67 = master volume being set (dark red like the master ring of the send scene, steady)
-- Reaper only sends what the page on show needs; the display is cleared on every page change.
-- (Channels are recognised whether the firmware numbers them 0-15 or 1-16.)
-- Never sends or uses CC 113-127 except A CC 127 (clear): channel-mode territory.

--@assign id=1 abbr="A1" name="A Band 1" l=0 h=127 manual=true g=1
--@assign id=2 abbr="A2" name="A Band 2" l=0 h=127 manual=true g=2
--@assign id=3 abbr="A3" name="A Band 3" l=0 h=127 manual=true g=3
--@assign id=4 abbr="Dir" name="Directional" l=0 h=127 manual=true g=4
--@assign id=5 abbr="A4" name="A Band 4" l=0 h=127 manual=true g=5
--@assign id=6 abbr="A5" name="A Band 5" l=0 h=127 manual=true g=6
--@assign id=7 abbr="A6" name="A Band 6" l=0 h=127 manual=true g=7
--@assign id=8 abbr="Omni" name="OmniComp" l=0 h=127 manual=true g=8
--@assign id=9 abbr="B1" name="B Band 1" l=0 h=127 manual=true g=9
--@assign id=10 abbr="B2" name="B Band 2" l=0 h=127 manual=true g=10
--@assign id=11 abbr="B3" name="B Band 3" l=0 h=127 manual=true g=11
--@assign id=12 abbr="B4" name="B Band 4" l=0 h=127 manual=true g=12
--@assign id=13 abbr="B5" name="B Band 5" l=0 h=127 manual=true g=13
--@assign id=14 abbr="B6" name="B Band 6" l=0 h=127 manual=true g=14
--@assign id=15 abbr="Solo" name="Solo" l=0 h=127 manual=true g=15
--@assign id=16 abbr="Spur" name="Spur/Master/Mute" l=0 h=127 manual=true g=16
--@assign id=17 abbr="A1" name="Push A Band 1" p=true g=1
--@assign id=18 abbr="A2" name="Push A Band 2" p=true g=2
--@assign id=19 abbr="A3" name="Push A Band 3" p=true g=3
--@assign id=20 abbr="Dir" name="Push Directional" p=true g=4
--@assign id=21 abbr="A4" name="Push A Band 4" p=true g=5
--@assign id=22 abbr="A5" name="Push A Band 5" p=true g=6
--@assign id=23 abbr="A6" name="Push A Band 6" p=true g=7
--@assign id=24 abbr="Omni" name="Push OmniComp" p=true g=8
--@assign id=25 abbr="B1" name="Push B1" p=true g=9
--@assign id=26 abbr="B2" name="Push B2" p=true g=10
--@assign id=27 abbr="B3" name="Push B3" p=true g=11
--@assign id=28 abbr="B4" name="Push B4" p=true g=12
--@assign id=29 abbr="B5" name="Push B5" p=true g=13
--@assign id=30 abbr="B6" name="Push B6" p=true g=14
--@assign id=31 abbr="Solo" name="Push Solo" p=true g=15
--@assign id=32 abbr="Spur" name="Push Spur/Master/Mute" p=true g=16

local LISTEN = {cc = true}

local OUT = 0                       -- send to all ports
local PEQ, PCOMP = 1, 3             -- our pages
local CHP = {[1] = 12, [3] = 11}    -- page -> out channel (0-based): 13, 12
local cur = 1                       -- page on show
local FLASH, QUIET = 60, 20         -- in update ticks of 20 ms: 1.2 s, 0.4 s
local DEBUG = false                 -- print push events to the OXI app console
-- Ring colours (OXI App palette, index = row*10+column). Verified: 50 pink, 34 white.
-- From the reverb remote: 18 light blue, 12 yellow, 10 red, 0 dark red.
local CA, CB = 18, 50               -- MultiEQ A light blue, MultiEQ B pink
local COFF  = 0                     -- band off: dark red
local CLOCK = 34                    -- frequency locked: white
local CGAIN = 12                    -- press + turn (gain): yellow
local CQ    = 12                    -- hold + turn (Q): yellow, blinking
local CMAST = 34                    -- compressor from the master: white
local CBL = {[64] = 53, [65] = 55, [66] = 60, [67] = 0}   -- solo yellow, muted orange, mute red, master dark red
local BLINK = 12                    -- blink half-period in ticks (0.24 s)

local T, S, FT, V, RV, ST = {}, {}, {}, {}, {}, {}  -- title, names, flash title, values, rings, states
local dirty, vf, ring = {}, {}, {}
local bphase, btick = false, 0
local tdirty, tf, quiet, title = true, 0, 0, nil
for i = 1, 15 do T[i] = 32; FT[i] = 32 end
for i = 1, 64 do S[i] = 32; V[i] = 32 end
for i = 1, 16 do vf[i] = 0; ST[i] = 0 end

local function code(v)
  return v >= 32 and v <= 126 and v or v >= 1 and v <= 26 and v + 127 or 32
end

local function trim(s) return s:match("^%s*(.-)%s*$") end

local function markAll()
  tdirty = true
  for i = 1, 16 do dirty[i] = true; if RV[i] then ring[i] = RV[i] end end
end

local function blinks(s) return (s >= 64 and s <= 66) or (s < 64 and s & 4 ~= 0) end

local function color(i)
  local s = ST[i]
  if s >= 64 then return CBL[s] or 10 end
  if s & 4 ~= 0 then return CQ end
  if s & 8 ~= 0 then return CGAIN end
  if s & 1 ~= 0 then return COFF end
  if s & 16 ~= 0 then return CMAST end
  if s & 2 ~= 0 then return CLOCK end
  return i <= 8 and CA or CB
end

local function clear()
  for i = 1, 64 do S[i] = 32; V[i] = 32 end
  for i = 1, 15 do T[i] = 32; FT[i] = 32 end
  for i = 1, 16 do vf[i] = 0; RV[i] = nil; ring[i] = -1; ST[i] = 0 end
  tf = 0
end

function midi.onCC(port, ch, n, v)
  if ch == 11 or ch == 12 then                 -- A: names, title
    quiet = QUIET
    if n == 127 then
      clear()
      markAll()
    elseif n < 15 then
      T[n + 1] = code(v); tdirty = true
    elseif n >= 16 and n < 80 then
      S[n - 15] = code(v); dirty[(n - 16) // 4 + 1] = true
    end
  elseif ch == 9 or ch == 10 then              -- B: flashes, rings
    if n < 15 then
      FT[n + 1] = code(v)
    elseif n == 15 then
      if quiet == 0 then tf = FLASH; tdirty = true end
    elseif n < 80 then
      local i = (n - 16) // 4 + 1
      V[n - 15] = code(v)
      if quiet == 0 then vf[i] = FLASH end
      dirty[i] = true
    elseif n < 96 then
      RV[n - 79] = v; ring[n - 79] = v
    elseif n < 112 then
      RV[n - 95] = nil; ring[n - 95] = -1
    end
  elseif ch == 7 or ch == 8 then               -- C: band states
    if n >= 1 and n <= 16 then
      ST[n] = v
      if RV[n] then ring[n] = RV[n] end        -- redraw in the new colour
    end
  end
end

local tAnn = 0
local function draw()
  local ch = CHP[cur]
  if not ch then return end
  tAnn = tAnn + 1
  if tAnn >= 50 then tAnn = 0; midi.sendCC(OUT, ch, 1, cur) end
  if title then page.setTitle(title); title = nil end
  if quiet > 0 then quiet = quiet - 1 end
  if tf > 0 then tf = tf - 1; if tf == 0 then tdirty = true end end
  for i = 1, 16 do
    if vf[i] > 0 then vf[i] = vf[i] - 1; if vf[i] == 0 then dirty[i] = true end end
  end
  if tdirty then
    tdirty = false
    local t = trim(string.char(table.unpack(tf > 0 and FT or T)))
    page.resetTitle()                 -- title freeze workaround: set on the next tick
    title = t == "" and "MULTIEQ" or t
  end
  btick = btick + 1
  local flip = false
  if btick >= BLINK then btick = 0; bphase = not bphase; flip = true end
  for i = 1, 16 do
    if dirty[i] then
      dirty[i] = false
      local b, src = i * 4 - 4, vf[i] > 0 and V or S
      slots.update(i, trim(string.char(src[b + 1], src[b + 2], src[b + 3], src[b + 4])))
    end
    local r = ring[i]
    if flip and blinks(ST[i]) and RV[i] then r = RV[i] end   -- Q mode, solo, mute: blink
    if r then
      ring[i] = nil
      if r < 0 then
        leds.reset(i)
      elseif blinks(ST[i]) and not bphase then
        leds.reset(i)
      else
        leds.updateByIndex(i, r * 129, color(i))
      end
    end
  end
end

-- An error in update would stop updates for good: catch it and print it to the console.
function system.update()
  local ok, e = pcall(draw)
  if not ok then print(e) end
end

function controller.onEncoderTurn(e)
  local id, d = e.id, e.increment
  -- 0 = not a physical turn (recorder, random, group); 255 = non-script control
  local ch = CHP[e.page]
  if d == 0 or id < 1 or id > 16 or not ch then return end
  controller.set(id, "v", 8192)       -- keep manual encoders off their end stops
  local v = 64 + d
  midi.sendCC(OUT, ch, 19 + id, v < 1 and 1 or v > 127 and 127 or v)
end

local function pushCC(id)           -- push ID -> CC 40-55 (both ID worlds)
  if id >= 17 and id <= 32 then return 23 + id end   -- dedicated push IDs
  if id >= 1 and id <= 16 then return 39 + id end     -- encoder IDs as fallback
  return nil
end

function controller.onEncoderPress(e)
  local ch = CHP[e.page]
  local cc = pushCC(e.id)
  if cc and ch then
    midi.sendCC(OUT, ch, cc, 127)
    if DEBUG then print("press id " .. e.id .. " -> CC " .. cc) end
  end
end

function controller.onEncoderRelease(e)
  local ch = CHP[e.page]
  local cc = pushCC(e.id)
  if cc and ch then
    midi.sendCC(OUT, ch, cc, 0)
    if DEBUG then print("release id " .. e.id .. " -> CC " .. cc) end
  end
end

function page.onPageChange(prev, curr)
  cur = curr
  if CHP[prev] then
    for i = 1, 16 do slots.reset(i); leds.reset(i) end
  end
  if CHP[curr] then
    clear(); markAll()
    tAnn = 0
    midi.sendCC(OUT, CHP[curr], 1, curr)   -- tell Reaper which page to draw
  end
end

function page.onInit()
  cur = controller.getPage and controller.getPage() or 1
  for id = 1, 16 do controller.set(id, {manual = true, v = 8192}) end
  system.setUpdateRate(20)
  if midi.listen then
    local ok, e = pcall(midi.listen, LISTEN)
    if not ok then print(e) end
  else
    print("no midi.listen: needs API 1.3")
  end
  markAll()
end
