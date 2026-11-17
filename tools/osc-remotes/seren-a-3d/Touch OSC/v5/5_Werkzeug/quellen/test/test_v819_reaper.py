"""v8.19 Reaper: 3OA-Erkennung (Kanäle/Name), Untespuren/Sends, Preset, Filterbit 16."""
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
TRACKS[1].nch = 16                                   -- 16 channels -> 3OA
TRACKS[2].name = 'Atmo ambiX'                        -- name says so
TRACKS[3].folder = true; TRACKS[3].depth = 1         -- folder with 3 children
TRACKS[4].parent = TRACKS[3]; TRACKS[5].parent = TRACKS[3]; TRACKS[6].depth = -1
TRACKS[7].recv = 4                                   -- receives = sends into this plugin track
TRACKS[7].fx = { { name = 'VST3: StereoEncoder (IEM)', preset = 'Hall A', params = {} } }
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
m = pump(3)
fl = {x[4]: x[5] for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 3]}
ex = {x[4]: x[5:-1] for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 22]}
pre = {x[4]: ''.join(chr(c) for c in x[5:-1]) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 23]}
check(ex.get(0) is not None and ex[0][0] == 1, f'16 Kanäle → 3OA ({ex.get(0)})')
check(ex.get(1) is not None and ex[1][0] == 1, f'Name „ambiX“ → 3OA ({ex.get(1)})')
check(ex.get(2) is not None and ex[2][0] == 0 and ex[2][1] == 3, f'Ordner zählt Unterspuren ({ex.get(2)})')
check(ex.get(6) is not None and ex[6][2] == 4, f'Sends in diese Spur gezählt ({ex.get(6)})')
check(pre.get(6) == 'Hall A', f'Preset des Encoders geht an die Oberfläche ({pre})')
# filter: only 3OA tracks (surface -> DAW, cmd 0B with bit 16)
L.execute("SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, string.char(0xF0, 0x7D, 0x4F, 0x0B, 16, 0, 0xF7), 2})")
m = pump(3)
names = {x[4]: ''.join(chr(c) for c in x[5:-1]) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 1]}
check(names.get(0) == 'T1' and names.get(1) == 'Atmo ambiX' and names.get(2, '') == '', f'Filter nur 3OA: T1 + ambiX ({names.get(0)}, {names.get(1)}, {names.get(2)})')
check(g.EXT['seren_3D/filter2'] == '16,0', 'Filter gespeichert (16,0)')
print('\nALL OK' if not fails else f'\n{fails} FAILED')
