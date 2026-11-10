-- seren_E16.lua (one scene: DAW Link + MultiEQ + compressors + reverb) on the E16 mock.
-- run via test_seren_e16.py (MOCK and SCRIPT are injected globals)
local E = dofile(MOCK)
local check = E.check
E.load(SCRIPT)
local A, B, C = 11, 9, 7              -- plugin pages: 0-based channels 12, 10, 8
local DA, DB = 15, 13                 -- DAW Link: 16, 14
local function cc(ch, n, v) midi.onCC(0, ch, n, v) end
local function text(ch, base, s) for i = 1, #s do cc(ch, base + i - 1, s:byte(i)) end end
local function has(st, d1, d2) for _, m in ipairs(E.sent) do if m.st == st and m.d1 == d1 and (d2 == nil or m.d2 == d2) then return true end end end
local function turn(pg, id, inc) controller.onEncoderTurn{id = id, index = id, page = pg, increment = inc} end
local function push(pg, id) controller.onEncoderPress{id = id, index = id - 16, page = pg}; controller.onEncoderRelease{id = id, index = id - 16, page = pg, held_ms = 80} end

-- page 1 = DAW Link
E.run(60)
check(E.title == "DAW LINK", "page 1: DAW Link (" .. E.title .. ")")
check(has(0xBC, 1, 127), "page 1: tells the plugin control it is not on show (ch 13, CC 1 = 127)")
text(DA, 0, "Vox Lead       "); text(DA, 16, "FX1 "); text(DA, 20, "FX2 ")
cc(DA, 80, 83); cc(DB, 80, 64); cc(DB, 81, 20); E.run(60)
check(E.title == "Vox Lead" and E.labels[1] == "FX1", "DAW Link: title and names")
check(E.rings[1] and E.rings[1].c == 83 and E.rings[1].v == 64 * 129, "DAW Link: ring in the colour the DAW sends (83 cyan)")
check(E.rings[2] and E.rings[2].c == 18, "DAW Link: no colour sent = light blue (18)")
E.sent = {}
turn(1, 1, 1); push(1, 17)
check(has(0xBF, 20, 65) and has(0xBF, 40, 127) and has(0xBF, 40, 0), "DAW Link: turn / push on channel 16")
-- plugin data meanwhile (Nuendo / Reaper may send it any time): kept off the screen on page 1
text(A, 16, "41.0"); cc(B, 80, 100); E.run(60)
check(E.labels[1] == "FX1" and E.rings[1].c == 83, "page 1: plugin channels do not draw over DAW Link")

-- page 2 = MultiEQ
E.sent = {}
E.show(2); E.run(60)
check(has(0xBC, 1, 1), "page 2: announces itself on channel 13 (CC 1 = 1)")
check(E.labels[1] == "" or E.labels[1] == nil, "page 2: clean display on entry")
text(A, 0, "A Out B Vox    "); text(A, 16, "40  "); cc(B, 80, 30); cc(C, 17, 87); E.run(60)
check(E.title == "A Out B Vox" and E.labels[1] == "40", "page 2: what the DAW sends")
check(E.rings[1] and E.rings[1].c == 87, "page 2: ring colour from channel 8 CC 17 (IEM band 1 = 87)")
E.sent = {}
turn(2, 3, -1); push(2, 24)
check(has(0xBC, 22, 63) and has(0xBC, 47, 127), "page 2: turn / push on channel 13")
E.sent = {}; E.run(1100)
check(has(0xBC, 1, 1), "page 2: announced again within a second")
-- states
cc(B, 81, 50); cc(C, 18, 74); cc(C, 2, 1); E.run(60)
check(E.rings[2] and E.rings[2].c == 24, "band off = grey violet (24)")
cc(C, 2, 2); E.run(60)
check(E.rings[2].c == 34, "locked = white")
cc(C, 2, 8); E.run(60)
check(E.rings[2].c == 44, "press + turn = yellow")
cc(C, 2, 0); E.run(60)
check(E.rings[2].c == 74, "back to its own colour")
cc(B, 94, 127); cc(B, 95, 90); cc(C, 15, 64); cc(C, 16, 66)
local seen = {}
for _ = 1, 60 do E.run(20); for _, i in ipairs({15, 16}) do local x = E.rings[i]; seen[i .. ":" .. (x and x.c or "off")] = true end end
check(seen["15:44"] and seen["15:off"], "solo: blinks yellow (44)")
check(seen["16:57"] and seen["16:off"], "mute: blinks red (57)")
cc(C, 15, 65); local o = false
for _ = 1, 40 do E.run(20); if E.rings[15] and E.rings[15].c == 36 then o = true end end
check(o, "muted, not soloed: orange-ish (36)")
cc(C, 16, 67); local steady = true
for _ = 1, 40 do E.run(20); if not (E.rings[16] and E.rings[16].c == 85) then steady = false end end
check(steady, "master volume: cyan, steady")

-- page 3 = compressors, page 4 = reverb
E.sent = {}
E.show(3); E.run(60)
check(has(0xBB, 1, 3) and E.title == "KOMPRESSOR", "page 3: channel 12, CC 1 = 3")
E.sent = {}
turn(3, 1, 1)
check(has(0xBB, 20, 65), "page 3: turn on channel 12")
E.sent = {}
E.show(4); E.run(60)
check(has(0xBA, 1, 4) and E.title == "REVERB", "page 4: channel 11, CC 1 = 4")
E.sent = {}
turn(4, 7, 1); push(4, 30)
check(has(0xBA, 26, 65) and has(0xBA, 53, 127), "page 4: turn / push on channel 11")

-- back to DAW Link: its display comes back from memory
E.sent = {}
E.show(1); E.run(60)
check(E.title == "Vox Lead" and E.labels[1] == "FX1" and E.rings[1] and E.rings[1].c == 83, "back on page 1: DAW Link redrawn from memory")
check(has(0xBC, 1, 127), "page 1 again: plugin control told to stop drawing")
E.sent = {}; E.run(1100)
check(not has(0xBC, 1) and not has(0xBB, 1) and not has(0xBA, 1), "page 1: no announcements every second")

-- 1-based channel numbers understood
text(16, 16, "QC1 "); E.run(60)
check(E.labels[1] == "QC1", "1-based channel 16 = DAW Link")
cc(DA, 127, 0); E.run(60)
check(E.rings[1] == nil and E.labels[1] == "", "DAW Link clear")
E.done()
