"""v8.14: Gruppen – A–D vom iPad/Monitor + Reaper-Ordner ohne dearVR/Hall; Anzeige nur der gewählten Gruppen."""
import os
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
L.execute("""
EXT["seren_3D/filter"] = "15,0"
for i = 1, 12 do TRACKS[i] = { name = 'T' .. i, guid = '{' .. i .. '}', sel = false, info = {}, peak = 0, fx = {} } end
TRACKS[1].name = 'Drums'; TRACKS[1].folder = true; TRACKS[2].parent = TRACKS[1]; TRACKS[3].parent = TRACKS[1]
TRACKS[5].name = 'Hall'; TRACKS[5].folder = true; TRACKS[5].fx = { { name = 'VST3: FdnReverb (IEM)', params = {} } }; TRACKS[6].parent = TRACKS[5]
TRACKS[8].name = 'Vox'; TRACKS[8].folder = true; TRACKS[9].parent = TRACKS[8]
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
def inject(b):
    L.execute("SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, string.char(" + ",".join(str(x) for x in b) + "), 2})")
def groups(m):
    gl = {x[4]: (x[5], ''.join(chr(c) for c in x[6:-1])) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 18]}
    return [gl[i] for i in sorted(gl)]
def names(m):
    nm = {x[4]: ''.join(chr(c) for c in x[5:-1]) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 1]}
    return [nm.get(i, '') for i in range(6)]
m = pump(3)
gl = groups(m)
check([n for _, n in gl] == ['A', 'B', 'C', 'D', 'Drums', 'Vox'], f'Gruppen: A–D + Ordner ohne Hall ({gl})')
inject([0xF0, 0x7D, 0x4F, 0x0C, 4, 0, 0xF7]); m = pump(3)
check(names(m)[:4] == ['Drums', 'T2', 'T3', ''], f'Gruppe Drums an: nur Drums und Kinder ({names(m)})')
inject([0xF0, 0x7D, 0x4F, 0x0D, 0, 1, 0xF7]); pump(2)            # T2 (obj 1) -> A
check(g.PEXT['seren_3D/grp_A'] == '{2}', f"T2 in Gruppe A gespeichert ({g.PEXT['seren_3D/grp_A']})")
inject([0xF0, 0x7D, 0x4F, 0x0C, 4, 0, 0xF7]); inject([0xF0, 0x7D, 0x4F, 0x0C, 0, 0, 0xF7]); m = pump(3)
check(names(m)[:2] == ['T2', ''], f'nur Gruppe A an: T2 ({names(m)})')
gl = groups(m)
check(gl[0][0] & 1 and gl[0][0] & 4, f'A: an und hat Spuren ({gl[0]})')
# surface
for name, tosc, tap in (('iPad', '../ipad/dist/seren-a_IEM-Space.tosc', 'r1_tap'), ('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc', 'c1_tap')):
    v = View(os.path.join(D, tosc))
    v.midi(*sx(4, text='REAPER')); v.midi(*sx(19, 6))
    for i, (f, n) in enumerate([(2, 'A'), (2, 'B'), (2, 'C'), (2, 'D'), (5, 'Drums'), (4, 'Vox')]): v.midi(*sx(18, i, f, text=n))
    v.midi(*sx(1, 0, text='Kick')); v.midi(*sx(3, 0, 1)); v.tick()
    v.run("onReceiveNotify('btn','cfg_btn')"); v.tick()
    check(v.text('cfg_gr_5_lbl') == 'Drums' and v.text('cfg_gr_1_lbl') == 'A (leer)' and not v.c['cfg_gr_7']['visible'], f"{name}: Gruppen-Tasten mit Namen ({v.text('cfg_gr_5_lbl')!r}, {v.text('cfg_gr_1_lbl')!r})")
    v.sent(); v.run("onReceiveNotify('btn','cfg_gr_6')"); v.tick()
    check([0xF0, 0x7D, 0x4F, 0x0C, 5, 0, 0xF7] in v.sent(), f'{name}: Vox antippen → SysEx 0C 5')
    v.run("onReceiveNotify('btn','cfg_as_2')"); v.tick()
    check(not v.c['cfg_overlay']['visible'], f'{name}: +B schließt die Config, Zuordnen läuft')
    v.sent(); v.run(f"onReceiveNotify('btn','{tap}')"); v.tick()
    check([0xF0, 0x7D, 0x4F, 0x0D, 1, 0, 0xF7] in v.sent(), f'{name}: Spur antippen → in Gruppe B (SysEx 0D 1 0)')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED')
import sys; sys.exit(1 if fails else 0)
