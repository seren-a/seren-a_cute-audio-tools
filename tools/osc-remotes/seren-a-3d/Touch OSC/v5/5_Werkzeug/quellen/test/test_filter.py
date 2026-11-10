"""Liste/Felder zeigen nur Spuren mit dem Plugin des Modus (LOOK.onlyPlug), iPad + Monitor."""
import os
from view_harness import View
D = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def pos(o, x, y, z):
    out = []
    for p, v in enumerate((x, y, z)):
        n = round((v + 32) / 64 * 16383); out.append([0xF0, 0x7D, 0x4F, 10, 3, o, p, n // 128, n % 128, 0xF7])
    return out
for name, tosc, pre in (('Monitor', os.path.join(D, '..', 'monitor', 'dist', 'seren-a_IEM-Monitor.tosc'), 'c'),
                        ('iPad', os.path.join(D, '..', 'ipad', 'dist', 'seren-a_IEM-Space.tosc'), 'r')):
    v = View(tosc)
    def rows():
        out = []
        for i in range(1, 65):
            n = f'{pre}{i}'
            if n + '_bg' not in v.c: break
            vis = v.c[n]['visible'] if pre == 'c' else v.c[n + '_bg']['visible']
            if vis: out.append(v.text(n + '_num'))
        return out
    v.midi(*sx(4, text='REAPER'))
    for o, nm, fl in ((0, 'Vox', 1), (1, 'Bass', 0), (2, 'Gtr', 1), (3, 'Hall', 0)):
        v.midi(*sx(1, o, text=nm)); v.midi(*sx(3, o, fl))
    for m in pos(3, 1.0, 2.0, 0.0): v.midi(*m)
    v.midi(*sx(14, 3, 0, 100, 0, 100, 0, 100, 0, 100, 0, 100, 0, 100, text='Box'))
    v.tick(16, 3)
    check(rows() == ['1', '3'], f'{name}: SPACE nur Spuren mit Encoder {rows()}')
    v.sent()
    v.run(f"onReceiveNotify('btn','{'c2_tap' if pre == 'c' else 'r2_tap'}')"); v.tick()
    s = v.sent()
    check(any(m[0] == 0x9E and m[1] == 2 and m[2] == 127 for m in s), f'{name}: Zeile 2 antippen wählt Spur 3 {s[:2]}')
    v.run("onReceiveNotify('btn','mode_room')"); v.tick()
    check(rows() == ['4'], f'{name}: ROOM nur Spur mit dearVR {rows()}')
    v.run("onReceiveNotify('btn','mode_space')" if pre == 'r' else "onReceiveNotify('btn','mode_iem')")
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_only')"); v.run("onReceiveNotify('btn','cfg_close')"); v.tick()
    check(len(rows()) >= 4 and rows()[:4] == ['1', '2', '3', '4'], f'{name}: Option aus -> alle Spuren {rows()[:6]}')
print('ALL OK' if not fails else f'{fails} FAILED')
