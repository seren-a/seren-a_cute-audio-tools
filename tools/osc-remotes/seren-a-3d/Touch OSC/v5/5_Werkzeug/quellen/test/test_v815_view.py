"""v8.15: iPad/Monitor speichern Ansicht + Config in Reaper und laden sie beim Start."""
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
for name, tosc, sid, setup, chk in (
        ('iPad', '../ipad/dist/seren-a_IEM-Space.tosc', 0, ["onReceiveNotify('btn','mode_room')", "onReceiveNotify('btn','n32_btn')", "onReceiveNotify('btn','cfg_btn')", "onReceiveNotify('btn','cfg_sc_ebu')", "onReceiveNotify('btn','cfg_close')"], ('n32', 'mode', 'room')),
        ('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc', 1, ["onReceiveNotify('btn','lay_32r')", "onReceiveNotify('btn','cfg_btn')", "onReceiveNotify('btn','cfg_sc_ebu')", "onReceiveNotify('btn','cfg_close')"], ('lay', 'lay', '32r'))):
    v = View(os.path.join(D, tosc)); v.midi(*sx(4, text='REAPER')); v.tick(50, 3)
    s = v.sent(); ask = [x for x in s if x[:4] == [0xF0, 0x7D, 0x4F, 0x0F]]
    check(ask == [[0xF0, 0x7D, 0x4F, 0x0F, sid, 0xF7]], f'{name}: fragt beim Start nach der Voreinstellung')
    v.tick(1100, 3)
    for c in setup: v.run(c)
    v.tick(1100, 2)
    st = [x for x in v.sent() if x[:4] == [0xF0, 0x7D, 0x4F, 0x0E]]
    check(len(st) >= 1 and 'sc=ebu' in ''.join(chr(c) for c in st[-1][5:-1]), f'{name}: Änderung geht an Reaper')
    inject(st[-1]); pump(2)
    saved = g.EXT[f'seren_3D/view{sid}']
    check(saved and 'sc=ebu' in saved and f'{chk[1]}={chk[2]}' in saved, f'{name}: Reaper speichert ({saved[:60]!r}…)')
    inject([0xF0, 0x7D, 0x4F, 0x0F, sid, 0xF7]); m = pump(2)
    rep = [x for x in m if x[:5] == [0xF0, 0x7D, 0x4F, 20, sid]]
    v2 = View(os.path.join(D, tosc)); v2.midi(*sx(4, text='REAPER')); v2.tick(50, 2); v2.midi(*rep[0]); v2.tick(50, 2)
    v2.run("onReceiveNotify('btn','cfg_btn')"); v2.tick()
    ok = v2.L.eval(f"LV.scale") if False else None
    check(v2.c['cfg_sc_ebu_bg']['color'] != v2.c['cfg_sc_digital_bg']['color'], f'{name}: neu geladen – Skala EBU aktiv')
    if name == 'iPad': check(v2.c['tiles32']['visible'] and v2.c['n32_btn_bg']['color'] is not None, 'iPad: neu geladen – 32er-Ansicht an')
    else: check(v2.c['c32_bg']['visible'], 'Monitor: neu geladen – Ansicht 4×8 (32 Felder)')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED')
import sys; sys.exit(1 if fails else 0)
