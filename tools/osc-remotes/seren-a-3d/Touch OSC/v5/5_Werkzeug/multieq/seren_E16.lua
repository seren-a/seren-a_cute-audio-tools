-- seren_E16.lua · seren.a 3D v6.1 · OXI E16, Lua API 1.3 (needs midi.listen / midi.onCC)
-- ONE scene for everything (seren-a_E16.oxie16). Pages (Shift + encoder 1-4):
--   1 DAW Link   Nuendo: serena/E16DAWLink (Sends+QC / EQ / Inserts, hold 16 = next)
--                Reaper: reaper_to_e16.lua
--   2 MultiEQ    \
--   3 Kompressor  > plugin control: Nuendo serena/E16DAWLink, Reaper Reaper_MultiEQ.lua
--   4 Reverb     /  (page 3: hold 8 = Omni <-> Directional; page 4 = FDN Reverb + mcfx convolver)
-- Built from DAW Link v2.4 and E16_MultiEQ (hardware-verified turns, pushes, display, rings).
--
-- out (to the DAW): page 1 on channel 16, page 2 on 13, page 3 on 12, page 4 on 11:
--   turn e -> CC 19+e (20-35), value 64+steps; push e -> CC 39+e (40-55) = 127, release -> 0;
--   pages 2-4: CC 1 = 1 / 3 / 4 on every page change and once a second; page 1: CC 1 = 127 on
--   channel 13 once (= the plugin pages are not on show)
-- in  page 1 (DAW Link): A = channel 16: CC 0-14 title, 16-79 names, 80-95 ring colour, 127 clear
--                         B = channel 14: CC 0-14 flash title, 15 show it, 16-79 values, 80-95 rings,
--                             96-111 ring off
-- in  pages 2-4:          A = channel 12, B = channel 10 (same meanings), C = channel 8:
--                         CC 1-16 state: +1 off, +2 locked, +4 hold (blinks), +8 press, +16 from the
--                         master; 64 solo, 65 muted not soloed, 66 muted (blink), 67 master volume;
--                         CC 17-32 ring colour of slot 1-16
-- Colours = index into the OXI App palette (10 x 10 picker, row * 10 + column).
-- Channels are recognised whether the firmware numbers them 0-15 or 1-16.

--@assign id=1 abbr="E1" name="Encoder 1" l=0 h=127 manual=true g=1
--@assign id=2 abbr="E2" name="Encoder 2" l=0 h=127 manual=true g=2
--@assign id=3 abbr="E3" name="Encoder 3" l=0 h=127 manual=true g=3
--@assign id=4 abbr="E4" name="Encoder 4" l=0 h=127 manual=true g=4
--@assign id=5 abbr="E5" name="Encoder 5" l=0 h=127 manual=true g=5
--@assign id=6 abbr="E6" name="Encoder 6" l=0 h=127 manual=true g=6
--@assign id=7 abbr="E7" name="Encoder 7" l=0 h=127 manual=true g=7
--@assign id=8 abbr="E8" name="Encoder 8" l=0 h=127 manual=true g=8
--@assign id=9 abbr="E9" name="Encoder 9" l=0 h=127 manual=true g=9
--@assign id=10 abbr="E10" name="Encoder 10" l=0 h=127 manual=true g=10
--@assign id=11 abbr="E11" name="Encoder 11" l=0 h=127 manual=true g=11
--@assign id=12 abbr="E12" name="Encoder 12" l=0 h=127 manual=true g=12
--@assign id=13 abbr="E13" name="Encoder 13" l=0 h=127 manual=true g=13
--@assign id=14 abbr="E14" name="Encoder 14" l=0 h=127 manual=true g=14
--@assign id=15 abbr="E15" name="Encoder 15" l=0 h=127 manual=true g=15
--@assign id=16 abbr="E16" name="Encoder 16" l=0 h=127 manual=true g=16
--@assign id=17 abbr="E1" name="Push 1" p=true g=1
--@assign id=18 abbr="E2" name="Push 2" p=true g=2
--@assign id=19 abbr="E3" name="Push 3" p=true g=3
--@assign id=20 abbr="E4" name="Push 4" p=true g=4
--@assign id=21 abbr="E5" name="Push 5" p=true g=5
--@assign id=22 abbr="E6" name="Push 6" p=true g=6
--@assign id=23 abbr="E7" name="Push 7" p=true g=7
--@assign id=24 abbr="E8" name="Push 8" p=true g=8
--@assign id=25 abbr="E9" name="Push 9" p=true g=9
--@assign id=26 abbr="E10" name="Push 10" p=true g=10
--@assign id=27 abbr="E11" name="Push 11" p=true g=11
--@assign id=28 abbr="E12" name="Push 12" p=true g=12
--@assign id=29 abbr="E13" name="Push 13" p=true g=13
--@assign id=30 abbr="E14" name="Push 14" p=true g=14
--@assign id=31 abbr="E15" name="Push 15" p=true g=15
--@assign id=32 abbr="E16" name="Push 16" p=true g=16

local LISTEN = {cc = true}
local OUT = 0                       -- send to all ports
-- page -> model ("d" = DAW Link, "m" = plugin control), out channel (0-based), announcement, title
local PG = {{"d", 15, nil, "DAW LINK"}, {"m", 12, 1, "MULTIEQ"}, {"m", 11, 3, "KOMPRESSOR"}, {"m", 10, 4, "REVERB"}}
local ANN = 12                      -- channel 13: page 1 says "plugin pages not on show" (CC 1 = 127)
local FLASH, QUIET, BLINK = 60, 20, 12   -- update ticks of 20 ms
-- OXI App palette: 34 white, 44 yellow, 57 red, 36 peach (orange), 85 cyan, 24 grey-violet
local CDEF, COFF, CLOCK, CGAIN, CMAST = 18, 24, 34, 44, 34
local CBL = {[64] = 44, [65] = 36, [66] = 57, [67] = 85}   -- solo, muted, mute, master volume
local cur = 1

local function model()
  local m = {T = {}, S = {}, FT = {}, V = {}, RV = {}, ST = {}, CO = {}, dirty = {}, vf = {}, ring = {},
    tdirty = true, tf = 0, quiet = 0}
  for i = 1, 15 do m.T[i] = 32; m.FT[i] = 32 end
  for i = 1, 64 do m.S[i] = 32; m.V[i] = 32 end
  for i = 1, 16 do m.vf[i] = 0; m.ST[i] = 0 end
  return m
end
local D, M = model(), model()
local title, bphase, btick, tAnn = nil, false, 0, 0

local function code(v)
  return v >= 32 and v <= 126 and v or v >= 1 and v <= 26 and v + 127 or 32
end
local function trim(s) return s:match("^%s*(.-)%s*$") end

local function markAll(m)
  m.tdirty = true
  for i = 1, 16 do m.dirty[i] = true; if m.RV[i] then m.ring[i] = m.RV[i] end end
end

local function clear(m)
  for i = 1, 64 do m.S[i] = 32; m.V[i] = 32 end
  for i = 1, 15 do m.T[i] = 32; m.FT[i] = 32 end
  for i = 1, 16 do m.vf[i] = 0; m.RV[i] = nil; m.ring[i] = -1; m.ST[i] = 0 end
  m.tf = 0
end

local function bankA(m, n, v)        -- title, names, ring colours
  m.quiet = QUIET
  if n == 127 then clear(m); markAll(m)
  elseif n < 15 then m.T[n + 1] = code(v); m.tdirty = true
  elseif n >= 16 and n < 80 then m.S[n - 15] = code(v); m.dirty[(n - 16) // 4 + 1] = true
  elseif n >= 80 and n < 96 then m.CO[n - 79] = v; if m.RV[n - 79] then m.ring[n - 79] = m.RV[n - 79] end
  end
end

local function bankB(m, n, v)        -- flashes, rings
  if n < 15 then m.FT[n + 1] = code(v)
  elseif n == 15 then if m.quiet == 0 then m.tf = FLASH; m.tdirty = true end
  elseif n < 80 then
    local i = (n - 16) // 4 + 1
    m.V[n - 15] = code(v)
    if m.quiet == 0 then m.vf[i] = FLASH end
    m.dirty[i] = true
  elseif n < 96 then m.RV[n - 79] = v; m.ring[n - 79] = v
  elseif n < 112 then m.RV[n - 95] = nil; m.ring[n - 95] = -1
  end
end

function midi.onCC(port, ch, n, v)
  if ch == 15 or ch == 16 then bankA(D, n, v)
  elseif ch == 13 or ch == 14 then bankB(D, n, v)
  elseif ch == 11 or ch == 12 then bankA(M, n, v)
  elseif ch == 9 or ch == 10 then bankB(M, n, v)
  elseif ch == 7 or ch == 8 then             -- C: states and colours
    local i = n <= 16 and n or n - 16
    if n >= 1 and n <= 16 then M.ST[n] = v elseif n >= 17 and n <= 32 then M.CO[i] = v end
    if i >= 1 and i <= 16 and M.RV[i] then M.ring[i] = M.RV[i] end
  end
end

local function blinks(m, i)
  local s = m.ST[i]
  return (s >= 64 and s <= 66) or (s < 64 and s & 4 ~= 0)
end

local function color(m, i)
  local s, c = m.ST[i], m.CO[i] or CDEF
  if s >= 64 then return CBL[s] or c end
  if s & 8 ~= 0 then return CGAIN end
  if s & 1 ~= 0 then return COFF end
  if s & 16 ~= 0 then return CMAST end
  if s & 2 ~= 0 then return CLOCK end
  return c
end

local function draw()
  local p = PG[cur]
  if not p then return end
  local m = p[1] == "d" and D or M
  if p[3] then
    tAnn = tAnn + 1
    if tAnn >= 50 then tAnn = 0; midi.sendCC(OUT, p[2], 1, p[3]) end
  end
  if title then page.setTitle(title); title = nil end
  if m.quiet > 0 then m.quiet = m.quiet - 1 end
  if m.tf > 0 then m.tf = m.tf - 1; if m.tf == 0 then m.tdirty = true end end
  for i = 1, 16 do
    if m.vf[i] > 0 then m.vf[i] = m.vf[i] - 1; if m.vf[i] == 0 then m.dirty[i] = true end end
  end
  if m.tdirty then
    m.tdirty = false
    local t = trim(string.char(table.unpack(m.tf > 0 and m.FT or m.T)))
    page.resetTitle()                 -- title freeze workaround: set on the next tick
    title = t == "" and p[4] or t
  end
  btick = btick + 1
  local flip = false
  if btick >= BLINK then btick = 0; bphase = not bphase; flip = true end
  for i = 1, 16 do
    if m.dirty[i] then
      m.dirty[i] = false
      local b, src = i * 4 - 4, m.vf[i] > 0 and m.V or m.S
      slots.update(i, trim(string.char(src[b + 1], src[b + 2], src[b + 3], src[b + 4])))
    end
    local r, bl = m.ring[i], blinks(m, i)
    if flip and bl and m.RV[i] then r = m.RV[i] end
    if r then
      m.ring[i] = nil
      if r < 0 or (bl and not bphase) then leds.reset(i)
      else leds.updateByIndex(i, r * 129, color(m, i)) end
    end
  end
end

-- An error in update would stop updates for good: catch it and print it to the console.
function system.update()
  local ok, e = pcall(draw)
  if not ok then print(e) end
end

function controller.onEncoderTurn(e)
  local id, d, p = e.id, e.increment, PG[e.page]
  -- 0 = not a physical turn (recorder, random, group); 255 = non-script control
  if d == 0 or id < 1 or id > 16 or not p then return end
  controller.set(id, "v", 8192)       -- keep manual encoders off their end stops
  local v = 64 + d
  midi.sendCC(OUT, p[2], 19 + id, v < 1 and 1 or v > 127 and 127 or v)
end

local function push(e, v)
  local p, id = PG[e.page], e.id
  local cc = (id >= 17 and id <= 32) and 23 + id or (id >= 1 and id <= 16) and 39 + id or nil
  if cc and p then midi.sendCC(OUT, p[2], cc, v) end
end
function controller.onEncoderPress(e) push(e, 127) end
function controller.onEncoderRelease(e) push(e, 0) end

local function enter(pg)
  cur = pg
  for i = 1, 16 do slots.reset(i); leds.reset(i) end
  local p = PG[pg]
  if not p then return end
  if p[1] == "m" then
    clear(M); markAll(M); tAnn = 0
    midi.sendCC(OUT, p[2], 1, p[3])   -- tell the DAW which plugin page to draw
  else
    markAll(D)
    midi.sendCC(OUT, ANN, 1, 127)
  end
end

function page.onPageChange(prev, curr) enter(curr) end

function page.onInit()
  for id = 1, 16 do controller.set(id, {manual = true, v = 8192}) end
  system.setUpdateRate(20)
  if midi.listen then
    local ok, e = pcall(midi.listen, LISTEN)
    if not ok then print(e) end
  else
    print("no midi.listen: needs API 1.3")
  end
  enter(controller.getPage and controller.getPage() or 1)
end
