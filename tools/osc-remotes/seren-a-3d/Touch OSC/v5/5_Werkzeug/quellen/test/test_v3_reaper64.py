"""Reaper-Hub v3.1: sichtbare Spuren, VCA weg, Typen, Icons, Objekte ab 17 per SysEx 10."""
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
local function P(name, v) return { name = name, v = v or 0.5, fmt = function(x) return string.format('%.1f', x * 360 - 180) end } end
local function SE(az) return { name = 'VST3: StereoEncoder (IEM)', params = { P('Ambisonics Order', 0.1), P('Normalization', 1), P('Quaternion W'), P('Quaternion X'), P('Quaternion Y'), P('Quaternion Z'), P('Azimuth Angle', az), P('Elevation Angle', 0.5), P('Roll Angle'), P('Stereo Width', 0.5) } } end
for i = 1, 22 do TRACKS[i] = { name = 'T' .. i, guid = '{' .. i .. '}', sel = false, info = {}, peak = 0, fx = { SE(0.5) } } end
TRACKS[3].hidden = true
TRACKS[4].vca = true
TRACKS[5].folder = true
TRACKS[6].instr = true
TRACKS[7].icon = '/Users/isa/icons/kick drum.png'
TRACKS[20].fx = { SE(0.75) }
""")
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
def pump():
    g.T = g.T + 0.05; L.execute("DEFER()")
    o = g.OUT; msgs = [[o[i].bytes[j] for j in range(1, len(o[i].bytes) + 1)] for i in range(1, len(o) + 1)]
    L.execute("OUT = {}"); return msgs
m = pump() + pump()
names = {x[4]: ''.join(chr(c) for c in x[5:-1]) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 1]}
check(names.get(2) == 'T5' and names.get(3) == 'T6' and 'T3' not in names.values() and 'T4' not in names.values(),
      f'versteckte Spur und VCA fehlen, Objekt 3 = T5 ({[names.get(i) for i in range(6)]})')
flags = {x[4]: x[5] for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 3]}
check(flags.get(2) == 1 | 32 and flags.get(3) == 1 | 64, f'Ordner = 32, Instrument-Spur = 64 (seit v8.4) ({flags.get(2)}, {flags.get(3)})')
icons = {x[4]: ''.join(chr(c) for c in x[5:-1]) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 11]}
check(icons.get(4) == 'kick drum', f'Icon-Name ohne Pfad und Endung ({icons.get(4)!r})')
# T20 = object index 17 (T3, T4 missing) -> SysEx 10, az 0.75
o17 = [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 10] and x[5] == 17 and x[4] == 0 and x[6] == 0]
check(o17 and o17[-1][7] * 128 + o17[-1][8] == round(0.75 * 16383), f'Objekt 18 (T20) Azimuth per SysEx 10 ({o17[-1] if o17 else None})')
check(any(x[:4] == [0xF0, 0x7D, 0x4F, 12] and x[4] == 64 for x in m), 'Fenstergroesse 64 gemeldet')
# device moves object 18 elevation via SysEx 10
L.execute("SEQ = SEQ + 1; table.insert(HIST, 1, { SEQ, string.char(0xF0,0x7D,0x4F,10,0,17,1,96,0,0xF7), 2 })")
pump()
v = L.eval("TRACKS[20].fx[1].params[8].v")
check(abs(v - 96 * 128 / 16383) < 1e-6, f'SysEx 10 vom Geraet setzt Elevation von T20 ({v:.3f})')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
