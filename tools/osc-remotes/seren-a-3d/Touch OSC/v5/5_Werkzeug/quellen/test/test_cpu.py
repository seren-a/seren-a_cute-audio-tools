"""Auslastung (cmd 15): Reaper-Hub misst (macOS: ps), Oberflächen zeigen sie dezent (Option)."""
import os
from lupa import lua54
from view_harness import View
D = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
L = lua54.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
L.execute(open(os.path.join(D, 'reaper_mock.lua')).read())
L.execute("TRACKS[1] = { name='Vox', guid='{1}', sel=true, info={}, peak=0, fx={} }")
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
def pump(n=1, dt=0.05):
    out = []
    for _ in range(n):
        g.T = g.T + dt; L.execute("DEFER()")
        o = g.OUT
        out += [[o[i].bytes[j] for j in range(1, len(o[i].bytes) + 1)] for i in range(1, len(o) + 1)]
        L.execute("OUT = {}")
    return out
c15 = lambda out: [m for m in out if m[:4] == [0xF0, 0x7D, 0x4F, 15]]
o = c15(pump(80))      # 4 s
check(o and o[0] == [0xF0, 0x7D, 0x4F, 15, 4, 2, 0, 0xF7], f'Hub: System 32 %/8 Kerne = 4 %, REAPER 12 %/8 = 2 %, keine Aussetzer {o[:1]}')
n_exec = g.EXEC
pump(20)
check(g.EXEC - n_exec <= 1, f'Hub: ps höchstens alle 3 s ({g.EXEC - n_exec} Aufrufe in 1 s)')
g.XRUN = 12345
o = c15(pump(80))
check(o and o[-1][6] == 1, f'Hub: Aussetzer gemeldet {o[-1:]}')
g.OS = 'Win64'
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
o = c15(pump(80))
check(o and o[-1][4:6] == [127, 127], f'Hub Windows: keine CPU-Zahlen (127), nur Aussetzer {o[-1:]}')

def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
for name, tosc in (('Monitor', os.path.join(D, '..', 'monitor', 'dist', 'seren-a_IEM-Monitor.tosc')),
                   ('iPad', os.path.join(D, '..', 'ipad', 'dist', 'seren-a_IEM-Space.tosc'))):
    v = View(tosc)
    v.midi(*sx(4, text='REAPER')); v.midi(*sx(15, 23, 12, 0)); v.tick(16, 3)
    check(not v.c['cpu_lbl']['visible'], f'{name}: Option aus -> nichts zu sehen')
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_cpu')"); v.run("onReceiveNotify('btn','cfg_close')")
    v.tick(16, 70)
    check(v.c['cpu_lbl']['visible'] and v.text('cpu_lbl') == 'CPU 23 %  ·  REAPER 12 %', f"{name}: {v.text('cpu_lbl')!r}")
    a = v.c['cpu_lbl']['textColor']['a'] if 'textColor' in v.c['cpu_lbl'] else None
    v.midi(*sx(15, 91, 60, 1)); v.tick(16, 70)
    check('Aussetzer' in v.text('cpu_lbl'), f"{name}: hohe Last + Aussetzer {v.text('cpu_lbl')!r}")
print('ALL OK' if not fails else f'{fails} FAILED')
