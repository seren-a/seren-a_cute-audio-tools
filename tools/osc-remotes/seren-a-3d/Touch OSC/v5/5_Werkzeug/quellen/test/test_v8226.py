"""v8.22.6: Umlaute/ß in Namen, Energie-Quelle Master, Config schließt immer, Skriptversion in der Kopfzeile."""
import os, sys
from lupa import lua54
from view_harness import View
D = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
# Reaper: Name mit Umlauten -> Steuerbytes
L = lua54.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
L.execute(open(os.path.join(D, 'reaper_mock.lua')).read())
L.execute("""EXT["seren_3D/filter2"] = "31,0"
TRACKS[1] = { name = 'Küche Größe Straße', guid = '{1}', sel = false, info = {}, peak = 0, fx = {} }
TRACKS[2] = { name = 'Amb', guid = '{2}', sel = false, info = {}, peak = 0, fx = {} }
MASTER.fx = { { name = 'JS: seren-a/seren-a_3D_Energy.jsfx', params = { { name = 'Slot', v = 1, raw = 1, fmt = function() return '1' end } } } }
TRACKS[2].fx = { { name = 'JS: seren.a 3D Energy', params = { { name = 'Slot', v = 2, raw = 2, fmt = function() return '2' end } } } }
TRACKS[2].sel = true""")
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
def pump(n=1):
    out = []
    for _ in range(n):
        g.T = g.T + 1.1; L.execute("DEFER()")
        o = g.OUT; out += [[o[i].bytes[j] for j in range(1, len(o[i].bytes) + 1)] for i in range(1, len(o) + 1)]; L.execute("OUT = {}")
    return out
def inject(*b): L.execute("SEQ = SEQ + 1; table.insert(HIST, 1, {SEQ, \"" + "".join("\\%03d" % x for x in b) + "\", 2})")
m = pump(3)
nm = [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 1] and x[4] == 0]
check(nm and all(0 < b < 128 for b in nm[-1][5:-1]), 'Name 7-Bit-sauber')
check(nm and nm[-1][5:-1] == [ord(c) if c not in 'üöß' else {'ü': 6, 'ö': 5, 'ß': 7}[c] for c in 'Küche Größe Straße'], f'Umlaute als Steuerbytes ({nm[-1][5:-1] if nm else None})')
check(any(x[:4] == [0xF0, 0x7D, 0x4F, 8] and bytes(x[4:-1]).startswith(b'hello|3D v8.22.6') for x in pump(6)), 'hello kommt auch beim Resync wieder')
inject(0xF0, 0x7D, 0x4F, 0x18, 3, 0, 0xF7); m = pump(2)
h = [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 29]]
check(h and bytes(h[-1][10:-1]) == b'Amb', f'Quelle gewählte Spur -> Amb ({bytes(h[-1][10:-1]) if h else None})')
inject(0xF0, 0x7D, 0x4F, 0x18, 3, 1, 0xF7); m = pump(2)
h = [x for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 29]]
check(h and bytes(h[-1][10:-1]) == b'Master', f'Quelle Master -> Master ({bytes(h[-1][10:-1]) if h else None})')
# Oberflächen
def sx(cmd, *d, text=b''): return [0xF0, 0x7D, 0x4F, cmd, *d, *text, 0xF7]
for nmf, f in (('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc'), ('HD', '../monitor/dist/seren-a_IEM-Monitor_HD.tosc'), ('iPad', '../ipad/dist/seren-a_IEM-Space.tosc')):
    v = View(f)
    v.midi(*sx(4, text=b'REAPER')); v.midi(*sx(8, text=b'hello|3D v8.22.6 aktiv (Reaper)'))
    v.midi(*sx(1, 0, text=bytes([ord('K'), 6, ord('c'), ord('h'), ord('e'), ord(' '), 7]))); v.midi(*sx(3, 0, 1))
    v.run("onReceiveNotify('btn','mode_iem')"); v.tick(16, 4)
    names = v.run("local t={} for k,c in pairs(controls) do if k:match('_name$') then t[#t+1]=c.values.text end end return table.concat(t,'|')")
    check('Küche ß' in names, f'{nmf}: Name mit ü/ß angezeigt')
    cpu = v.c['cpu_lbl']['values']['text'] if 'cpu_lbl' in v.c else ''
    check('3D v8.22.6' in cpu, f'{nmf}: Skriptversion in der Kopfzeile ({cpu})')
    v.run("onReceiveNotify('btn','cfg_btn')"); v.tick(16, 2)
    v.run("controls['cfg_overlay'].visible = false")      # wie nach dem Verlassen von TouchOSC
    v.run("onReceiveNotify('btn','cfg_btn')"); v.tick(16, 2)
    check(v.c['cfg_overlay']['visible'], f'{nmf}: Config geht nach dem Zurückkommen wieder auf')
    v.run("onReceiveNotify('btn','cfg_close')"); v.tick(16, 2)
    check(not v.c['cfg_overlay']['visible'], f'{nmf}: fertig schließt')
    v.sent(); v.run("onReceiveNotify('btn','mode_en')"); v.tick(16, 3)
    v.run("onReceiveNotify('btn','en_src1')"); v.tick(16, 3)
    out = v.sent()
    check([0xF0, 0x7D, 0x4F, 0x18, 3, 1, 0xF7] in out, f'{nmf}: Taste Master schickt 18 3 1')
    check('en_src1' in v.c, f'{nmf}: Taste Master vorhanden')
print('FAILS', fails); sys.exit(1 if fails else 0)
