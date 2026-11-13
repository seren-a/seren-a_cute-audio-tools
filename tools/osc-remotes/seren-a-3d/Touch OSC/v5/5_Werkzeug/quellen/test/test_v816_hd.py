"""v8.16: Monitor HD (1920 x 1080): jede Ansicht liegt im Bild, Felder überlappen sich nicht, Kreis und Liste kommen sich nicht in die Quere."""
import os, sys
from view_harness import View
D = os.path.dirname(os.path.abspath(__file__))
TOSC = os.path.join(D, '..', 'monitor', 'dist', 'seren-a_IEM-Monitor_HD.tosc')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def box(v, n):
    f = v.c[n]['frame']; return f['x'], f['y'], f['w'], f['h']
def inside(b, W=1920, H=1080): return b[0] >= 0 and b[1] >= 0 and b[0] + b[2] <= W + 0.5 and b[1] + b[3] <= H + 0.5
def overlap(a, b): return a[0] < b[0] + b[2] - 0.5 and b[0] < a[0] + a[2] - 0.5 and a[1] < b[1] + b[3] - 0.5 and b[1] < a[1] + a[3] - 0.5
v0 = View(TOSC)
check(v0.doc.root.frame.w == 1920 and v0.doc.root.frame.h == 1080, 'Seite 1920 x 1080')
check(v0.doc.root.get('name') == 'seren.a IEM monitor HD', 'Name im TouchOSC: HD')
for lay, n in (('16', 16), ('32v', 32), ('32h', 32), ('32r', 32), ('64', 64)):
    for pano in (False, True):
        v = View(TOSC); v.midi(*sx(4, text='REAPER')); v.midi(*sx(12, 64))
        for o in range(64):
            v.midi(*sx(1, o, text=f'T{o + 1}')); v.midi(*sx(3, o, 1))
        v.run(f"onReceiveNotify('btn','lay_{lay}')")
        if pano: v.run("onReceiveNotify('btn','pano_btn')")
        v.tick(16, 20)
        cells = [box(v, f'c{k}') for k in range(1, n + 1)]
        tag = f'{lay}{" + Horizont" if pano else ""}'
        check(all(inside(c) for c in cells), f'{tag}: alle {n} Felder im Bild')
        ov = [(i + 1, j + 1) for i in range(n) for j in range(i + 1, n) if overlap(cells[i], cells[j])]
        check(not ov, f'{tag}: Felder überlappen sich nicht {ov[:3]}')
        circ = [n2 for n2 in ('circ1', 'circ2', 'circ3', 'circ4', 'circ1s', 'circ2s', 'circ3s', 'circ4s') if n2 in v.c and v.c[n2]['visible']]
        for cn in circ:
            b = box(v, cn)
            check(inside(b), f'{tag}: {cn} im Bild')
            check(not any(overlap(b, c) for c in cells), f'{tag}: {cn} berührt kein Feld')
        if pano:
            pn = [n2 for n2 in ('pano1', 'pano2', 'pano3', 'pano4') if v.c[n2]['visible']]
            for p in pn:
                b = box(v, p); check(inside(b) and not any(overlap(b, c) for c in cells), f'{tag}: {p} im Bild, frei von Feldern')
# Kopfzeile: Bank-Gruppe rechts am Rand
v = View(TOSC)
check(box(v, 'bank_next')[0] + box(v, 'bank_next')[2] <= 1920, 'Kopfzeile: Bank-Pfeile im Bild')
check(box(v, 'bank_next')[0] > 1800, 'Kopfzeile: Bank-Gruppe sitzt rechts')
v.midi(*sx(4, text='REAPER')); v.run("onReceiveNotify('btn','cfg_btn')"); v.tick(16, 5)
check(box(v, 'cfg_overlay') == (0, 0, 1920, 1080), 'Config-Seite füllt das Bild')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED'); sys.exit(1 if fails else 0)
