"""Reaper Hub v4.4: nur aktive Plugins zählen (Bypass/Offline), mehrere auf einer Spur, dearVR PRO -> Raum."""
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
local function P(name, v, f) return { name = name, v = v or 0.5, fmt = f or function(x) return string.format('%.1f', x * 360 - 180) end } end
local function T(s) return function() return s end end
local function SE(off) return { name = 'VST3: StereoEncoder (IEM)', off = off, params = { P('Azimuth Angle', 0.75), P('Elevation Angle', 0.5), P('Stereo Width', 0.5) } } end
local function SR(off) return { name = 'VST3: SceneRotator (IEM)', off = off, params = { P('Yaw Angle', 0.6), P('Pitch Angle'), P('Roll Angle') } } end
local function ME(off) return { name = 'VST3: MultiEncoder (IEM)', off = off, params = { P('Number of input channels ', 4 / 64),
  P('Master azimuth angle', 0.25), P('Master elevation angle'), P('Azimuth angle 1', 0.3), P('Elevation angle 1'), P('Gain 1', 0.8) } } end
local DVC = { name = 'VST3: dearVR PRO 2 (Dear Reality)', params = {
  P('Input Mode', 0, T('Cartesian')), P('X', 0.5, T('2.0 m')), P('Y', 0.5, T('1.0 m')), P('Z', 0.5, T('3.0 m')),
  P('Azimuth', 0.5, T('33.7')), P('Elevation', 0.5, T('15.5')), P('Distance', 0.5, T('3.7 m')), P('Distance Scale', 0.5, T('1.00')),
  P('Direct Gain', 0.5, T('0.0 dB')), P('Preset', 0.3, T('Medium Room')) } }
local DVP = { name = 'VST3: dearVR PRO 2 (Dear Reality)', params = {
  P('Input Mode', 1, T('Polar')), P('Azimuth', 0.75, T('90.0')), P('Elevation', 0.5, T('0.0')), P('Distance', 0.5, T('2.0 m')),
  P('Wall Left', 0.1, T('1.5 m')), P('Wall Front', 0.1, T('2.0 m')), P('Wall Right', 0.1, T('2.5 m')), P('Wall Top', 0.1, T('3.0 m')),
  P('Wall Back', 0.1, T('4.0 m')), P('Wall Bottom', 0.1, T('1.8 m')), P('Reflections Gain', 0.5, T('0.0 dB')) } }
TRACKS[1] = { name='Vox', guid='{1}', sel=true, info={}, peak=0, fx={ SE(true), ME(false), SR(false) } }
TRACKS[2] = { name='Gtr', guid='{2}', sel=false, info={}, peak=0, fx={ SE(false), ME(false) } }
TRACKS[3] = { name='Pad', guid='{3}', sel=false, info={}, peak=0, fx={ SR(true) } }
TRACKS[4] = { name='Room A', guid='{4}', sel=false, info={}, peak=0, fx={ DVC } }
TRACKS[5] = { name='Room B', guid='{5}', sel=false, info={}, peak=0, fx={ DVP } }
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
o = pump(2)
flags = {x[4]: x[5] for x in o if x[:4] == [0xF0, 0x7D, 0x4F, 3] and x[4] < 5}
check(flags.get(0) == 1 | 4 | 8, f'Vox: StereoEncoder umgangen -> MultiEncoder + Rotator ({flags.get(0)})')
check(flags.get(1) == 1, f'Gtr: zwei aktive Encoder -> der erste (StereoEncoder) ({flags.get(1)})')
check(flags.get(2) == 0, f'Pad: Rotator umgangen -> nichts ({flags.get(2)})')
logs = [bytes(x[4:-1]).decode() for x in o if x[:4] == [0xF0, 0x7D, 0x4F, 8]]
u1 = [l for l in logs if l.startswith('u1|')]
check(u1 and 'StereoEncoder FX1 (aus)' in u1[0] and 'MultiEncoder FX2 *' in u1[0] and 'SceneRotator FX3 *' in u1[0], f'Log Spur 1: {u1}')
u2 = [l for l in logs if l.startswith('u2|')]
check(u2 and 'MultiEncoder FX2 (ignoriert)' in u2[0], f'Log Spur 2: {u2}')
me = [x for x in o if x[:4] == [0xF0, 0x7D, 0x4F, 9]]
check(me and me[-1][4] == 4, 'gewählte Spur Vox: MultiEncoder-Seite mit 4 Eingängen (der aktive Encoder)')
def dv(obj):
    v = {x[6]: (x[7] * 128 + x[8]) / 16383 * 64 - 32 for x in o if x[:6] == [0xF0, 0x7D, 0x4F, 10, 3, obj]}
    return [round(v.get(p, 99), 2) for p in range(3)]
check(dv(3) == [2.0, 3.0, 1.0], f'dearVR kartesisch: X 2 -> rechts 2, Z 3 -> vorn 3, Y 1 -> oben 1 ({dv(3)})')
check(dv(4) == [2.0, 0.0, 0.0], f'dearVR polar: Azimut 90, 2 m -> rechts 2 m ({dv(4)})')
rooms = {x[4]: x for x in o if x[:4] == [0xF0, 0x7D, 0x4F, 14]}
def walls(x): return [(x[5 + 2 * i] * 128 + x[6 + 2 * i]) / 100 for i in range(6)], bytes(x[17:-1]).decode()
check(walls(rooms[3]) == ([3.8, 2.1, 4.1, 4.0, 2.8, 1.8], 'Medium Room'), f'Raum aus Preset-Tabelle ({walls(rooms[3])})')
check(walls(rooms[4])[0] == [1.5, 2.0, 2.5, 3.0, 4.0, 1.8], f'Raum aus Wand-Parametern ({walls(rooms[4])})')
check(rooms[0][4:] == [0, 0xF7], 'Spur ohne dearVR: Raum leer')
# Bypass umschalten: MultiEncoder auf Vox aus -> kein Encoder mehr
L.execute("TRACKS[1].fx[2].off = true; STATE = STATE + 1")
o = pump(2)
flags = {x[4]: x[5] for x in o if x[:4] == [0xF0, 0x7D, 0x4F, 3] and x[4] == 0}
check(flags.get(0) == 8, f'Vox: MultiEncoder jetzt auch umgangen -> nur noch Rotator ({flags.get(0)})')
L.execute("TRACKS[1].fx[1].off = false; STATE = STATE + 1")
o = pump(2)
flags = {x[4]: x[5] for x in o if x[:4] == [0xF0, 0x7D, 0x4F, 3] and x[4] == 0}
check(flags.get(0) == 1 | 8, f'Vox: StereoEncoder wieder an -> übernimmt ({flags.get(0)})')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
# Ende-zu-Ende: Reaper-Hub -> iPad ROOM
from view_harness import View
g.T = g.T + 6
o = pump(3)
ip = View(os.path.join(D, '..', 'ipad', 'dist', 'seren-a_IEM-Space.tosc'))
for x in o: ip.midi(*x)
ip.run("onReceiveNotify('btn','mode_room')"); ip.tick(16, 3)
t = ip.text('rt_title')
check(ip.c['d4']['visible'] and ip.c['d5']['visible'] and not ip.c['d1']['visible'] and 'Medium Room' in t and 'anderem Raum' in t,
      f'Reaper -> iPad ROOM: dearVR-Spuren 4+5 sichtbar, Räume verschieden ({t!r})')
print("\nALL OK (e2e)" if fails == 0 else f"\n{fails} FAILED")
