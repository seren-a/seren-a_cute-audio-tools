"""IEM space (iPad): IEM-Draufsicht (Rand = Horizont, unten hohl), Ziehen nur Azimut, Breite, Pegelfarbe."""
import os, sys, math
sys.path.insert(0, os.path.dirname(__file__))
from view_harness import View
from test_space import sx, iem, dec, center
TOSC = os.path.join(os.path.dirname(__file__), '..', 'dist', 'seren-a_IEM-Space.tosc')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
TOP = (16, 168, 600, 600); cx, cy, R = 16 + 300, 168 + 300, 300 - 16
for luav in ('lua51', 'lua54'):
    v = View(TOSC, luav)
    v.midi(*sx(4, text='REAPER'))
    for o in (1, 2):
        v.midi(*sx(1, o - 1, text=f'T{o}')); v.midi(*sx(3, o - 1, 1))
    for m in iem(90, 1, 0, -180, 180) + iem(0, 1, 1, -180, 180) + iem(40, 1, 2, -360, 360): v.midi(*m)
    for m in iem(-90, 2, 0, -180, 180) + iem(-45, 2, 1, -180, 180): v.midi(*m)
    v.tick(16, 3)
    x1, y1 = center(v, 'd1'); x2, y2 = center(v, 'd2')
    check(abs(math.hypot(x1 - cx, y1 - cy) - R) < 1.5 and x1 < cx, f'{luav}: el 0° am Rand, +90° links')
    check(abs(math.hypot(x2 - cx, y2 - cy) - R / 2) < 1.5 and v.c['d2_lo']['visible'] and not v.c['d1_lo']['visible'], f'{luav}: el -45° gespiegelt auf halbem Radius, hohl')
    check(v.c['wl1']['visible'] and v.c['wr1']['visible'] and not v.c['wl2']['visible'], f'{luav}: Breite 40° = zwei Punkte')
    xl, yl = center(v, 'wl1'); azl = math.degrees(math.atan2(-(xl - cx), -(yl - cy)))
    check(abs(azl - 110) < 1.5, f'{luav}: linker Punkt bei Az + Breite/2 ({azl:.1f})')
    v.run("onReceiveNotify('btn','sel1')"); v.tick(); v.sent()
    v.run("local c = controls.top_xy; c.values.touch = true; c.values.x = 0.5; c.values.y = 0.95; onReceiveNotify('drag','top_xy')")
    out = dec(v.sent())
    check((1, 0) in out and (1, 1) not in out and abs(out[(1, 0)] - 0.5) < 0.01, f'{luav}: Ziehen im Kreis nach vorn = nur Azimut 0° {out}')
    v.midi(0xBE, 0, 120); v.tick(16, 5)
    col = v.c['r1_lvl']['color']
    check(abs(col['r'] - 1.0) < 0.02 and abs(col['g'] - 0.83) < 0.02, f"{luav}: Pegel oben = Gold aus der Palette ({col['r']:.2f},{col['g']:.2f})")
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
