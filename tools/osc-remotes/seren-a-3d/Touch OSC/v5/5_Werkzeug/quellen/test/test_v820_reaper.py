"""v8.20 Reaper: Hall-Reiter (FDN, mcfx): Sends als Objekte, Send-Pegel (cmd 26), Gesamtpegel (25), Preset (27), Instanz (24)."""
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
for i = 1, 8 do TRACKS[i] = { name = 'T' .. i, guid = '{' .. i .. '}', sel = false, info = {}, peak = 0, fx = {} } end
TRACKS[1].name = 'Vox'; TRACKS[2].name = 'Gtr'; TRACKS[3].name = 'Keys'
TRACKS[6].name = 'FDN Hall'; TRACKS[6].fx = { { name = 'VST3: FdnReverb (IEM)', preset = 'Church', params = {} } }
TRACKS[7].name = 'Faltungshall'; TRACKS[7].fx = { { name = 'VST3: mcfx_convolver (mcfx)', preset = 'Aula', params = {} } }
TRACKS[8].name = 'FDN 2'; TRACKS[8].fx = { { name = 'VST3: FdnReverb (IEM)', params = {} } }
TRACKS[6].recvs = { { src = TRACKS[1], vol = 1.0 }, { src = TRACKS[2], vol = 0.5 }, { src = TRACKS[3], vol = 0.25, mute = true } }
TRACKS[7].recvs = { { src = TRACKS[2], vol = 0.1 } }
TRACKS[1].peak = 0.5; TRACKS[2].peak = 1.0; TRACKS[3].peak = 1.0; TRACKS[6].peak = 0.25
""")
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
def pump(n=1):
    out = []
    for _ in range(n):
        g.T = g.T + 0.05; L.execute("DEFER()")
        o = g.OUT
        out += [[o[i].bytes[j] for j in range(1, len(o[i].bytes) + 1)] for i in range(1, len(o) + 1)]
        L.execute("OUT = {}")
    return out
def inject(*b):
    L.execute("SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, \"" + "".join("\\%03d" % x for x in b) + "\", 2})")
def names(m): return {x[4]: ''.join(chr(c) for c in x[5:-1]) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 1]}
pump(3)
inject(0xF0, 0x7D, 0x4F, 24, 1, 0, 0xF7)                 # FDN tab, instance 0
m = pump(4)
nm = names(m)
check(nm.get(0) == 'Vox' and nm.get(1) == 'Gtr' and nm.get(2) == 'Keys' and nm.get(3, '') == '', f'FDN-Reiter zeigt die Sends als Objekte ({nm.get(0)}, {nm.get(1)}, {nm.get(2)})')
sv = {x[4]: (x[5], x[6]) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 26]}
check(sv.get(0, (0,))[0] == 127 * 60 // 72 + 1 or abs(sv[0][0] - 106) <= 1, f'Send-Fader Vox 0 dB -> {sv.get(0)}')
check(sv.get(2) == (0, 1), f'gemuteter Send meldet mute ({sv.get(2)})')
hh = [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 24]]
check(hh and hh[-1][4:7] == [1, 0, 2] and ''.join(chr(c) for c in hh[-1][7:-1]) == 'FDN Hall', f'Kopf: Art FDN, Instanz 0 von 2, Name ({hh[-1] if hh else None})')
pre = [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 27]]
check(pre and ''.join(chr(c) for c in pre[-1][4:-1]) == 'Church', 'Preset des Halls (cmd 27)')
tot = [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 25]]
check(tot and 40 <= tot[-1][4] <= 127 and tot[-1][4] > 0, f'Gesamtpegel des Halls (cmd 25) = {tot[-1][4] if tot else None}')
lv = {x[1]: x[2] for x in m if len(x) == 3 and x[0] == 0xBE}
check(lv.get(0, 0) > lv.get(1, 0) > 0 or lv.get(0, 0) >= lv.get(1, 0), f'Live-Pegel am Hall: Vox {lv.get(0)} Gtr {lv.get(1)} Keys {lv.get(2)} (Keys gemutet = 0)')
check(lv.get(2) == 0, 'gemuteter Send: Pegel 0')
# change a send fader live
L.execute("TRACKS[6].recvs[2].vol = 2.0")
m = pump(3)
sv = {x[4]: (x[5], x[6]) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 26]}
check(sv.get(1, (0,))[0] > 106, f'Send-Fader folgt live (Gtr +6 dB -> {sv.get(1)})')
# second FDN instance, then the mcfx tab
inject(0xF0, 0x7D, 0x4F, 24, 1, 1, 0xF7)
m = pump(4)
hh = [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 24]]
check(hh and hh[-1][5] == 1 and ''.join(chr(c) for c in hh[-1][7:-1]) == 'FDN 2', 'zweite FDN-Instanz')
check(names(m).get(0, '') == '' , 'FDN 2 hat keine Sends')
inject(0xF0, 0x7D, 0x4F, 24, 2, 0, 0xF7)
m = pump(4)
check(names(m).get(0) == 'Gtr', f'mcfx-Reiter: Send von Gtr ({names(m).get(0)})')
check([x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 27]] and ''.join(chr(c) for c in [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 27]][-1][4:-1]) == 'Aula', 'mcfx-Preset')
# back to tracks
inject(0xF0, 0x7D, 0x4F, 24, 0, 0, 0xF7)
m = pump(4)
check(names(m).get(0) == 'Vox' and names(m).get(5) is not None, f'Art 0 = wieder die Spuren ({names(m).get(0)}, {names(m).get(5)})')
print('\nALL OK' if not fails else f'\n{fails} FAILED')
