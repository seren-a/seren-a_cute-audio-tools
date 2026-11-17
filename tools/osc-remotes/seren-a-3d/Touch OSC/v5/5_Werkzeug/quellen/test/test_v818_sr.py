"""v8.18: SceneRotator oeffnet sein FX-Fenster kurz, wenn eine Oberflaeche es dreht."""
import os, sys
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
local function SR() return { name = 'VST3: SceneRotator (IEM)', params = { P('Yaw Angle', 0.6), P('Pitch Angle'), P('Roll Angle') } } end
local function SE() return { name = 'VST3: StereoEncoder (IEM)', params = { P('Azimuth Angle', 0.75), P('Elevation Angle'), P('Stereo Width') } } end
TRACKS[1] = { name='Vox', guid='{1}', sel=true, info={}, peak=0, fx={ SE(), SR() } }
""")
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
def pump(n=1):
    for _ in range(n): g.T = g.T + 0.05; L.execute("DEFER()")
def inject(b): L.execute("SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, \"" + "".join("\\%03d" % x for x in b) + "\", 2})")
def shown(): return L.eval("(function() local n = 0; for _, v in pairs(reaper.__shown) do if v then n = n + 1 end end; return n end)()")
pump(3)
check(shown() == 0, 'am Anfang kein Fenster offen')
inject([0xF0, 0x7D, 0x4F, 10, 0, 0, 0, 100, 5, 0xF7]); pump(2)       # Encoder: Azimut -> kein Fenster
check(shown() == 0, 'StereoEncoder drehen: kein Fenster')
inject([0xF0, 0x7D, 0x4F, 10, 1, 0, 0, 100, 5, 0xF7]); pump(2)       # Rotator: Yaw
check(shown() == 1, 'SceneRotator drehen: FX-Fenster offen')
g.T = g.T + 1.0; pump(2); check(shown() == 1, 'nach 1 s noch offen')
inject([0xF0, 0x7D, 0x4F, 10, 1, 0, 0, 101, 5, 0xF7]); pump(1); g.T = g.T + 2.0; pump(2)
check(shown() == 1, 'weiterdrehen haelt es offen')
g.T = g.T + 3.0; pump(2); check(shown() == 0, 'danach schliesst es sich wieder')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED'); sys.exit(1 if fails else 0)
