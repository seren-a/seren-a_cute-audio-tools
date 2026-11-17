"""v8.22 Reaper: Energie-Reiter (0x18 3 0): cmd 29 Kopf, cmd 28 Zeilen, Skalierung aus EnergyVisualizer, Watchdog."""
import os
from lupa import lua54
D = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
L = lua54.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
L.execute(open(os.path.join(D, 'reaper_mock.lua')).read())
L.execute("""
EXT["seren_3D/filter2"] = "31,0"
for i = 1, 4 do TRACKS[i] = { name = 'T' .. i, guid = '{' .. i .. '}', sel = false, info = {}, peak = 0, fx = {} } end
TRACKS[1].name = 'Vox'; TRACKS[2].name = 'Amb 3OA'
local function P(name, txt, raw) return { name = name, v = 0.5, raw = raw, fmt = function() return txt end } end
TRACKS[2].fx = { { name = 'JS: seren.a 3D Energy (seren-a)', params = { P('Slot', '2', 2) } },
                 { name = 'VST3: EnergyVisualizer (IEM)', params = { P('Peak Level', '-6.0 dB'), P('Dynamic Range', '30.0 dB'), P('Resolution', '4') } } }
TRACKS[2].sel = true
for i = 0, 11 do for c = 0, 23 do GMEM[2 * 512 + 8 + i * 24 + c] = -80 + (i * 24 + c) % 91 end end
GMEM[2 * 512] = 1; GMEM[2 * 512 + 1] = 3; GMEM[2 * 512 + 2] = -20
""")
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
def pump(n=1, step=0.05, beat=True):
    out = []
    for _ in range(n):
        g.T = g.T + step
        if beat: L.execute("GMEM[2*512] = GMEM[2*512] + 1")
        L.execute("DEFER()")
        o = g.OUT
        out += [[o[i].bytes[j] for j in range(1, len(o[i].bytes) + 1)] for i in range(1, len(o) + 1)]
        L.execute("OUT = {}")
    return out
def inject(*b):
    L.execute("SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, \"" + "".join("\\%03d" % x for x in b) + "\", 2})")
def cmd(m, c): return [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, c]]
pump(3)
inject(0xF0, 0x7D, 0x4F, 0x18, 3, 0, 0xF7)
m = pump(6)
h = cmd(m, 29)
check(h, 'Kopf (cmd 29) gesendet')
if h:
    x = h[-1]
    check(x[4] == 1, f'Status live ({x[4]})')
    check(x[5] == 1, f'Quelle: aus EnergyVisualizer ({x[5]})')
    check(x[6] - 64 == -6 and x[7] == 30, f'Spitze -6 dB / Bereich 30 dB ({x[6]-64}, {x[7]})')
    check(x[8] == 3, f'Ordnung 3 ({x[8]})')
    check(abs(x[9] - round((-20 + 60) / 60 * 127)) <= 1, f'Gesamtpegel ({x[9]})')
    check(''.join(chr(c) for c in x[10:-1]) == 'Amb 3OA', f'Spurname ({"".join(chr(c) for c in x[10:-1])})')
rows = {x[4]: x[5:-1] for x in cmd(m, 28)}
check(sorted(rows) == list(range(12)), f'12 Zeilen ({sorted(rows)})')
check(all(len(v) == 24 for v in rows.values()), '24 Werte je Zeile')
def b(db): return round(max(0, min(1, (db + 80) / 90)) * 127)
exp = [b(-80 + (5 * 24 + c) % 91) for c in range(24)]
check(rows.get(5) and all(abs(a - e) <= 1 for a, e in zip(rows[5], exp)), 'Zeile 5 entspricht gmem (dB -> 0..127)')
check(all(0 <= v <= 127 for r in rows.values() for v in r), 'alle Werte 0..127')
# Spuren bleiben normal
nm = {x[4]: ''.join(chr(c) for c in x[5:-1]) for x in cmd(m, 1)}
check(nm.get(0) == 'Vox' and nm.get(1) == 'Amb 3OA', f'Spurliste bleibt ({nm.get(0)}, {nm.get(1)})')
# Aenderung nur bei neuen Werten
m = pump(5)
check(not cmd(m, 28) and not cmd(m, 29), 'unveraenderte Daten werden nicht erneut gesendet')
L.execute("for c = 0, 23 do GMEM[2*512+8+3*24+c] = -10 end")
m = pump(4)
r3 = {x[4]: x[5:-1] for x in cmd(m, 28)}
check(list(r3) == [3] and all(v == b(-10) for v in r3[3]), f'nur geaenderte Zeile 3 ({list(r3)})')
# Watchdog: Beat steht still
m = pump(40, 0.05, beat=False)
h = cmd(m, 29)
check(h and h[-1][4] == 2, f'Status 2 (keine Daten) bei stehendem Zaehler ({h[-1][4] if h else None})')
m = pump(5)
h = cmd(m, 29)
check(h and h[-1][4] == 1, 'wieder live, sobald der Zaehler laeuft')
# Ohne EnergyVisualizer: Standardwerte
L.execute("TRACKS[2].fx = { TRACKS[2].fx[1] }")
m = pump(30)
h = cmd(m, 29)
check(h and h[-1][5] == 0 and h[-1][6] - 64 == 0 and h[-1][7] == 35, f'ohne Plugin: 0 dB / 35 dB, Quelle 0 ({h[-1][5:8] if h else None})')
# Ohne JSFX: Status 0
L.execute("TRACKS[2].fx = {}")
m = pump(30)
h = cmd(m, 29)
check(h and h[-1][4] == 0, f'ohne JSFX Status 0 ({h[-1][4] if h else None})')
# JSFX auf dem Master
L.execute("MASTER.fx = { { name = 'JS: seren.a 3D Energy', params = { { name = 'Slot', v = 0, raw = 1, fmt = function() return '1' end } } } }")
L.execute("GMEM[1*512] = 0; GMEM[1*512+1] = 1")
m = pump(30)
h = cmd(m, 29)
check(h and h[-1][4] == 1 and ''.join(chr(c) for c in h[-1][10:-1]) == 'Master', 'JSFX auf dem Master wird gefunden')
# zurueck zu Spuren
inject(0xF0, 0x7D, 0x4F, 0x18, 0, 0, 0xF7)
m = pump(5)
check(not cmd(m, 28), 'Art 0: keine Energiedaten mehr')
print('\nALL OK' if not fails else f'\n{fails} FAILED')
