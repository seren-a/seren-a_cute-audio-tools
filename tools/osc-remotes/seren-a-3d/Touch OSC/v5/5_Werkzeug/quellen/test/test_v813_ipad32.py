"""v8.13: iPad – Taste „32“: Spuren 17–32 als Kacheln unten (2 Reihen à 8), Objekte 17+ per SysEx 10."""
import os
from view_harness import View
D = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
v = View(os.path.join(D, '..', 'ipad', 'dist', 'seren-a_IEM-Space.tosc'))
v.midi(*sx(4, text='REAPER')); v.midi(*sx(12, 64))
for o in range(32):
    v.midi(*sx(1, o, text=f'T{o + 1}')); v.midi(*sx(3, o, 1)); v.midi(*sx(17, o, 0, o + 1))
v.midi(*[0xF0, 0x7D, 0x4F, 10, 0, 19, 0, 96, 0, 0xF7])          # T20 az
v.tick(16, 5)
vis = lambda n: v.c[n]['visible']
check(not vis('tiles32') and not vis('d20'), '16er-Ansicht: keine Kacheln, Punkt 20 aus')
v.run("onReceiveNotify('btn','n32_btn')"); v.tick(16, 3)
check(vis('tiles32') and vis('d20') and not vis('pano_xy'), 'Taste 32: Kacheln an, Punkt 20 da, Panorama-Ziehfläche aus')
check(v.text('r20_name') == 'T20' and v.text('r20_num') == '20', f"Kachel 20: Name und Nummer ({v.text('r20_name')!r}, {v.text('r20_num')!r})")
check('Az' in v.text('r20_val'), f"Kachel 20: Werte aus SysEx 10 ({v.text('r20_val')!r})")
check(v.text('bank') == 'Spuren 1–32', f"Bereich 1–32 ({v.text('bank')!r})")
v.sent(); v.run("onReceiveNotify('btn','bank_next')"); v.tick()
check(v.sent() == [[0x9F, 3, 127], [0x9F, 3, 0], [0x9F, 3, 127], [0x9F, 3, 0]], '32: Bank vor = zwei DAW-Bänke')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED')
import sys; sys.exit(1 if fails else 0)
