"""v8.18: 'groß' wird in der Voreinstellung gespeichert; SceneRotator zeigt kurz sein FX-Fenster."""
import os, sys
from lupa import lua54
from view_harness import View
D = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
L = lua54.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
L.execute(open(os.path.join(D, 'reaper_mock.lua')).read())
L.execute("for i = 1, 3 do TRACKS[i] = { name = 'T' .. i, guid = '{' .. i .. '}', sel = false, info = {}, peak = 0, fx = {} } end")
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
def pump(n=1):
    out = []
    for _ in range(n):
        g.T = g.T + 0.05; L.execute("DEFER()")
        o = g.OUT
        out += [[o[i].bytes[j] for j in range(1, len(o[i].bytes) + 1)] for i in range(1, len(o) + 1)]
        L.execute("OUT = {}")
    return out
def inject(b):
    L.execute("SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, string.char(" + ",".join(str(x) for x in b) + "), 2})")
for name, tosc, sid in (('iPad', '../ipad/dist/seren-a_IEM-Space.tosc', 0), ('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc', 1),
                        ('Monitor HD', '../monitor/dist/seren-a_IEM-Monitor_HD.tosc', 1)):
    v = View(os.path.join(D, tosc)); v.midi(*sx(4, text='REAPER')); v.tick(50, 3); v.tick(1100, 3)
    v.run("onReceiveNotify('btn','mode_room')"); v.tick(16, 3)
    v.run("onReceiveNotify('btn','rz_big')"); v.tick(1100, 3); v.tick(1100, 2)
    st = [x for x in v.sent() if x[:4] == [0xF0, 0x7D, 0x4F, 0x0E]]
    check(st and 'big=1' in ''.join(chr(c) for c in st[-1][5:-1]), f'{name}: "groß" geht an Reaper')
    inject(st[-1]); pump(2)
    saved = g.EXT[f'seren_3D/view{sid}']
    check(saved and 'big=1' in saved, f'{name}: Reaper speichert ({saved[:50]!r})')
    inject([0xF0, 0x7D, 0x4F, 0x0F, sid, 0xF7]); m = pump(2)
    rep = [x for x in m if x[:5] == [0xF0, 0x7D, 0x4F, 20, sid]]
    v2 = View(os.path.join(D, tosc)); v2.midi(*sx(4, text='REAPER')); v2.tick(50, 2); v2.midi(*rep[0]); v2.tick(50, 2)
    v2.run("onReceiveNotify('btn','mode_room')"); v2.tick(16, 3)
    check(v2.text('rz_big_lbl') == 'klein', f'{name}: nach Neustart ist „groß“ noch an')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED')
sys.exit(1 if fails else 0)
