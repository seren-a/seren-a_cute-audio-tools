"""Reaper v3 Hub (Mock): Plugins in beliebigem Slot, Parameter nach Namen, alle Wege."""
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
local function SE() return { name = 'VST3: StereoEncoder (IEM)', params = {
  P('Ambisonics Order', 0.1), P('Normalization', 1), P('Quaternion W'), P('Quaternion X'), P('Quaternion Y'), P('Quaternion Z'),
  P('Azimuth Angle', 0.75), P('Elevation Angle', 0.5), P('Roll Angle'), P('Stereo Width', 0.5625), P('Sample-wise Panning', 0) } } end
local function SR() return { name = 'VST3: SceneRotator (IEM)', params = {
  P('Ambisonics Order', 0.1), P('Normalization', 1), P('Yaw Angle', 0.6), P('Pitch Angle'), P('Roll Angle') } } end
local function ME(n)
  local p = { P('Number of input channels ', n / 64), P('Ambisonics Order', 0.1), P('Normalization', 1),
    P('Master azimuth angle', 0.25), P('Master elevation angle'), P('Master roll angle'), P('Lock Directions relative to Master', 0) }
  for i = 1, 20 do p[#p+1] = P('Azimuth angle ' .. i, 0.5 + i / 100); p[#p+1] = P('Elevation angle ' .. i); p[#p+1] = P('Gain ' .. i, 0.8);
    p[#p+1] = P('Mute input ' .. i, 0); p[#p+1] = P('Solo input ' .. i, 0) end
  return { name = 'VST3: MultiEncoder (IEM)', params = p }
end
local EQ = { name = 'VST3: Pro-Q 3 (FabFilter)', params = { P('Frequency'), P('Azimuth Angle', 0.3) } }
TRACKS[1] = { name='Vox', guid='{1}', sel=false, info={}, peak=0, fx={ EQ, SE(), SR() } }
TRACKS[2] = { name='Drums OH', guid='{2}', sel=true, info={}, peak=0, fx={ ME(4) } }
TRACKS[3] = { name='Bass', guid='{3}', sel=false, info={}, peak=0, fx={ EQ } }
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
def v14(msgs, st, cc):
    m = [x[2] for x in msgs if x[0] == st and x[1] == cc]; l = [x[2] for x in msgs if x[0] == st and x[1] == cc + 32]
    return (m[-1] * 128 + l[-1]) / 16383 if m and l else None
o = pump(2)
flags = {x[4]: x[5] for x in o if x[:4] == [0xF0, 0x7D, 0x4F, 3] and x[4] < 3}
check(flags == {0: 9, 1: 5, 2: 0}, f'Flags: Vox Encoder+Rotator, Drums MultiEncoder, Bass nichts ({flags})')
check(abs(v14(o, 0xBC, 0) - 0.75) < 1e-3 and abs(v14(o, 0xBC, 2) - 0.5625) < 1e-3, 'Vox: StereoEncoder in FX 2 gefunden (nicht das EQ-"Azimuth")')
check(abs(v14(o, 0xBC, 4) - 0.25) < 1e-3, 'Drums: MultiEncoder Master Azimuth als Objekt 2')
check(abs(v14(o, 0xB6, 0) - 0.6) < 1e-3, 'Vox: Yaw auf Kanal 7')
me = [x for x in o if x[:4] == [0xF0, 0x7D, 0x4F, 9]]
check(me and me[-1][4] == 4, 'gewählte Spur Drums: MultiEncoder mit 4 Eingängen')
check(abs(v14(o, 0xB8, 4) - 0.52) < 1e-3 and abs(v14(o, 0xB8, 6) - 0.8) < 1e-3, 'Eingang 2 Azimuth/Gain auf Kanal 9')
check(abs(v14(o, 0xBF, 1) - 0.25) < 1e-3, 'Panner CC 1 = Master Azimuth')
logs = [bytes(x[4:-1]).decode() for x in o if x[:4] == [0xF0, 0x7D, 0x4F, 8]]
check(any('Spur 1 Vox - StereoEncoder in FX 2 (Azimuth P7, Elevation P8, Width P10)' == l.split('|', 1)[-1] for l in logs), f'Log: {logs[1:3]}')
# Bewegen
def cc14(ch, cc, n):
    v = round(n * 16383)
    L.execute(f"evIn(2, {0xB0 + ch}, {cc}, {v // 128}); evIn(2, {0xB0 + ch}, {cc + 32}, {v % 128})")
cc14(12, 0, 0.1); cc14(12, 1, 0.9); cc14(6, 1, 0.3); cc14(12, 8, 0.2)
cc14(8, 8, 0.33); cc14(15, 2, 0.44); cc14(15, 4, 0.66)
pump(2)
P = lambda t, f, p: L.eval(f"TRACKS[{t}].fx[{f}].params[{p}].v")
check(abs(P(1, 2, 7) - 0.1) < 1e-3 and abs(P(1, 2, 8) - 0.9) < 1e-3, 'Gerät setzt Vox Azimuth/Elevation')
check(abs(P(1, 3, 4) - 0.3) < 1e-3, 'Gerät setzt Vox Pitch (Rotator)')
check(abs(P(1, 1, 2) - 0.3) < 1e-9 and abs(P(1, 2, 1) - 0.1) < 1e-9, 'EQ und Ambisonics Order unberührt')
check(abs(P(3, 1, 2) - 0.3) < 1e-9, 'Bass (kein Encoder): nichts gesetzt')
check(abs(P(2, 1, 8 + 5 * 2) - 0.33) < 1e-3, 'MultiEncoder Eingang 3 Azimuth gesetzt')
check(abs(P(2, 1, 5) - 0.44) < 1e-3, 'Panner Elevation -> Master Elevation')
check(abs(P(2, 1, 4) - 0.25) < 1e-9, 'Panner Width beim MultiEncoder: nichts (kein Width)')
L.execute("evIn(2, 0x9F, 0, 127)"); pump(2)
check(L.eval("TRACKS[1].sel and not TRACKS[2].sel"), 'Note 0 Kanal 16: Spur zurück')
L.execute("evIn(2, 0x9E, 2, 127)"); pump(2)
check(L.eval("TRACKS[3].sel"), 'Note 2 Kanal 15: Spur 3 wählen')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
