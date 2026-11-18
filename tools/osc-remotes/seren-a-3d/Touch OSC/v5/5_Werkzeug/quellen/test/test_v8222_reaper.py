"""v8.22.2 Reaper: EnergyVisualizer auf dem Master ohne JSFX -> JSFX wird nach REAPER/Effects kopiert und auf dem Master eingefügt."""
import os, shutil, tempfile
from lupa import lua54
D = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
res = tempfile.mkdtemp()
L = lua54.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
L.execute(f'RESPATH = "{res}"')
L.execute(open(os.path.join(D, 'reaper_mock.lua')).read())
L.execute("""
EXT["seren_3D/filter2"] = "31,0"
for i = 1, 3 do TRACKS[i] = { name = 'T' .. i, guid = '{' .. i .. '}', sel = false, info = {}, peak = 0, fx = {} } end
MASTER.fx = { { name = 'VST3: EnergyVisualizer (IEM)', params = {} } }
""")
src = os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')
L.execute(open(src).read().replace('debug.getinfo(1, "S").source', '"@' + os.path.join(D, '..', 'jsfx') + '/"'))
def pump(n=1):
    out = []
    for _ in range(n):
        g.T = g.T + 0.6; L.execute("DEFER()")
        o = g.OUT; out += [[o[i].bytes[j] for j in range(1, len(o[i].bytes) + 1)] for i in range(1, len(o) + 1)]; L.execute("OUT = {}")
    return out
def inject(*b): L.execute("SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, \"" + "".join("\\%03d" % x for x in b) + "\", 2})")
pump(2)
check(L.eval("#MASTER.fx") == 1, 'ohne Energie-Reiter wird nichts eingefügt')
inject(0xF0, 0x7D, 0x4F, 0x18, 3, 0, 0xF7)
m = pump(4)
check(L.eval("#MASTER.fx") == 2, f'JSFX auf dem Master eingefügt ({L.eval("#MASTER.fx")})')
check(os.path.exists(os.path.join(res, 'Effects', 'seren-a', 'seren-a_3D_Energy.jsfx')), 'JSFX nach REAPER/Effects/seren-a kopiert')
logs = [''.join(chr(c) for c in x[5:-1]) for x in m if x[:5] == [0xF0, 0x7D, 0x4F, 8, *[]][:4] + [] or (x[:4] == [0xF0, 0x7D, 0x4F, 8])]
check(any('eingefuegt' in s for s in logs), 'LOG meldet das Einfügen')
h = [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 29]]
check(h and h[-1][4] != 0, f'Kopf: JSFX gefunden (Status {h[-1][4] if h else None})')
m = pump(6)
check(L.eval("#MASTER.fx") == 2, 'nur einmal eingefügt')
shutil.rmtree(res, ignore_errors=True)
print('FAILS', fails)
