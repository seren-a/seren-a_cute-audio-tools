-- run via test_e16_multieq.py (MOCK and SCRIPT are injected globals)
local E = dofile(MOCK)
local check = E.check
E.load(SCRIPT)
local A, B, C = 11, 9, 7                     -- 0-based channels 12, 10, 8
local function cc(ch, n, v) midi.onCC(0, ch, n, v) end
local function text(ch, base, s) for i = 1, #s do cc(ch, base + i - 1, s:byte(i)) end end

E.run(60)
check(E.title == "MULTIEQ", "default title (" .. E.title .. ")")

text(A, 0, "A Maste B Mon  ")
text(A, 16, "41.0"); text(A, 36, "18k "); text(A, 48, "46.0")
E.run(60)
check(E.title == "A Maste B Mon", "title (" .. E.title .. ")")
check(E.labels[1] == "41.0" and E.labels[6] == "18k" and E.labels[9] == "46.0", "slot names = frequencies")

-- DAW Link / reverb remote channels (16, 14) are ignored by this scene
text(15, 16, "Azim"); text(13, 80, "\64")
E.run(600)
check(E.labels[1] == "41.0", "channel 16 (DAW Link) ignored")
-- 1-based numbering understood
text(12, 20, "63.0")
E.run(600)
check(E.labels[2] == "63.0", "names on 1-based channel 12")

-- rings: colour per instance, then per state
cc(B, 80, 64); cc(B, 88, 32)
E.run(40)
check(E.rings[1] and E.rings[1].v == 64 * 129 and E.rings[1].c == 18, "ring 1: A = light blue")
check(E.rings[9] and E.rings[9].c == 50, "ring 9: B = pink")
cc(C, 1, 1); E.run(40)
check(E.rings[1].c == 0, "band off = dark red")
cc(C, 1, 2); E.run(40)
check(E.rings[1].c == 34, "locked = white")
cc(C, 1, 3); E.run(40)
check(E.rings[1].c == 0, "off wins over locked")
cc(C, 1, 8); E.run(40)
check(E.rings[1].c == 12, "gain mode = yellow")
cc(C, 1, 4)
local on, off = 0, 0
for _ = 1, 60 do E.run(20); if E.rings[1] then on = on + 1 else off = off + 1 end end
check(on > 10 and off > 10, "Q mode blinks (" .. on .. " on, " .. off .. " off)")
cc(C, 1, 0); E.run(40)
check(E.rings[1] and E.rings[1].c == 18, "back to normal")
cc(B, 101, 0); E.run(40)
check(E.rings[6] == nil, "ring off")
cc(9, 81, 100); E.run(40)                          -- 0-based 9 = channel 10
check(E.rings[2] and E.rings[2].v == 100 * 129, "ring on channel 10")

-- value flash
text(B, 20, "+3.0"); E.run(40)
check(E.labels[2] == "+3.0", "value flash")
E.run(1400)
check(E.labels[2] == "63.0", "name back after flash")

-- controls -> channel 13
E.sent = {}
E.turn(3, 2); E.turn(11, -1)
E.press(17); E.release(17, 100)
local got = {}
for _, m in ipairs(E.sent) do got[#got + 1] = string.format("%02X %d %d", m.st, m.d1, m.d2) end
local s = table.concat(got, ",")
check(s:find("BC 22 66", 1, true) and s:find("BC 30 63", 1, true), "turns on channel 13, CC 19+id (" .. s .. ")")
check(s:find("BC 40 127", 1, true) and s:find("BC 40 0", 1, true), "push 1 -> CC 40 127 / 0")
for _, m in ipairs(E.sent) do check(m.d1 < 113, "never CC 113-127 out") break end


-- pages: page 3 = compressors on channel 12; announce; other pages silent
E.sent = {}
E.show(3)
local function has(st, d1, d2) for _, m in ipairs(E.sent) do if m.st == st and m.d1 == d1 and (d2 == nil or m.d2 == d2) then return true end end end
check(has(0xBB, 1, 3), "page 3: announces itself on channel 12 (CC 1 = 3)")
check(E.labels[1] == "" or E.labels[1] == nil, "page change clears the display")
text(A, 16, "-10 "); text(A, 44, "OMNI"); E.run(60)
check(E.labels[1] == "-10" and E.labels[8] == "OMNI", "page 3 shows what Reaper sends")
cc(B, 88, 40); cc(C, 9, 16); E.run(40)
check(E.rings[9] and E.rings[9].c == 34, "compressor from the master = white")
E.sent = {}
controller.onEncoderTurn{id = 1, index = 1, page = 3, increment = 1}
controller.onEncoderPress{id = 24, index = 8, page = 3}
controller.onEncoderRelease{id = 24, index = 8, page = 3, held_ms = 80}
check(has(0xBB, 20, 65) and has(0xBB, 47, 127) and has(0xBB, 47, 0), "page 3: turn and push 8 on channel 12")
E.sent = {}
E.run(1100)
check(has(0xBB, 1, 3), "page 3: announced again within a second")
E.sent = {}
E.show(2)
controller.onEncoderTurn{id = 1, index = 1, page = 2, increment = 1}
E.run(1100)
check(#E.sent == 0, "page 2: nothing sent")
check(E.rings[9] == nil and (E.labels[1] == nil or E.labels[1] == ""), "page 2: our display is gone")
cc(A, 16, 65); E.run(60)
check(E.labels[1] == nil, "page 2: nothing drawn")
E.show(1)
check(has(0xBC, 1, 1), "back on page 1: announced on channel 13")

-- v5.3: solo / mute blink in their colours
E.show(1); cc(B, 94, 127); cc(B, 95, 90); cc(C, 15, 64); cc(C, 16, 66)
local seen = {}
for _ = 1, 60 do E.run(20); for _, i in ipairs({15, 16}) do local x = E.rings[i]; if x then seen[i .. ":" .. x.c] = true else seen[i .. ":off"] = true end end end
check(seen["15:53"] and seen["15:off"], "15 solo: blinks yellow")
check(seen["16:60"] and seen["16:off"], "16 mute: blinks red")
cc(C, 15, 65); E.run(600)
local o = false
for _ = 1, 40 do E.run(20); if E.rings[15] and E.rings[15].c == 55 then o = true end end
check(o, "15 muted, not soloed: orange")
cc(C, 15, 0); cc(C, 16, 0); E.run(100)
check(E.rings[16] and E.rings[16].c == 50, "16 back to normal")
cc(C, 16, 67); E.run(100)
local steady = true
for _ = 1, 40 do E.run(20); if not (E.rings[16] and E.rings[16].c == 0) then steady = false end end
check(steady, "16 master volume: dark red, steady")
cc(C, 16, 0); E.run(100)

-- clear
cc(A, 127, 0); E.run(60)
check(E.rings[1] == nil and E.labels[1] == "", "clear")
E.done()
