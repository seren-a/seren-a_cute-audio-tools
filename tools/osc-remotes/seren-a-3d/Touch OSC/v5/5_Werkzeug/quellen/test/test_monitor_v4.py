"""IEM monitor: 64er-Felder (Nummer, Werte, Info am Block), IEM-Draufsicht, Breite, Horizont verkleinert."""
import math, os
from view_harness import View
D = os.path.dirname(os.path.abspath(__file__))
TOSC = os.path.join(D, '..', 'monitor', 'dist', 'seren-a_IEM-Monitor.tosc')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def enc(v, o, p, rng=360):
    n = round((v + rng / 2) / rng * 16383)
    if o < 16:
        ch, cc = 12 + o // 8, 4 * (o % 8) + p
        return [[0xB0 + ch, cc, n // 128], [0xB0 + ch, cc + 32, n % 128]]
    return [[0xF0, 0x7D, 0x4F, 10, 0, o, p, n // 128, n % 128, 0xF7]]
def ctr(c): f = c['frame']; return f['x'] + f['w'] / 2, f['y'] + f['h'] / 2
for luav in ('lua51', 'lua54'):
    v = View(TOSC, luav)
    v.midi(*sx(4, text='REAPER')); v.midi(*sx(12, 64))
    for o in range(40):
        v.midi(*sx(1, o, text=f'Track {o + 1}')); v.midi(*sx(3, o, 1))
        for m in enc(30, o, 0) + enc(0, o, 1): v.midi(*m)
    for m in enc(-30, 19, 1) + enc(60, 19, 2, 720): v.midi(*m)        # Spur 20: unter dem Horizont, Breite 60
    v.run("onReceiveNotify('btn','lay_64')"); v.tick(16, 3)
    check(v.text('c20_num') == '20' and v.text('c20_numb') == '20' and v.c['c20_numb']['frame']['w'] > 0,
          f'{luav}: 64: Nummer im Kreis, fett (2. Lage)')
    check(v.text('c20_val') == '30   -30   60', f"{luav}: 64: zweite Zeile Werte ohne Einheit ({v.text('c20_val')!r})")
    check(v.text('c20_name') == 'Track 20', f"{luav}: 64: Name ohne Nummer davor ({v.text('c20_name')!r})")
    check(not v.c['blk2_info']['visible'], f'{luav}: erster Abgleich zeigt keine Info')
    # Draufsicht: el 0 liegt am Rand, -30° gespiegelt und hohl
    f = (160, 62, 960, 960); cx, cy, R = 160 + 480, 62 + 480, 480 - 14
    x1, y1 = ctr(v.c['d1']); x20, y20 = ctr(v.c['d20'])
    check(abs(math.hypot(x1 - cx, y1 - cy) - R) < 1.5, f'{luav}: el 0° = Rand ({math.hypot(x1 - cx, y1 - cy):.1f} vs {R})')
    check(abs(math.hypot(x20 - cx, y20 - cy) - R * 60 / 90) < 1.5 and v.c['d20_lo']['visible'] and not v.c['d1_lo']['visible'],
          f'{luav}: el -30° gespiegelt, hohl')
    check(v.c['wl20']['visible'] and v.c['wr20']['visible'] and not v.c['wl1']['visible'], f'{luav}: Breite 60° = zwei Ringe')
    xl, yl = ctr(v.c['wl20'])
    azl = math.degrees(math.atan2(-(xl - cx), -(yl - cy)))
    check(abs(azl - 60) < 1.5, f'{luav}: linker Rand bei Azimut + Breite/2 ({azl:.1f})')
    # Bewegung aus der DAW -> Info unter dem Block
    v.tick(1000, 3)
    for m in enc(45, 19, 0): v.midi(*m)
    v.tick()
    info, bf = v.c['blk2_info'], v.c['c17']['frame']
    check(info['visible'] and 'Azimut +45°' in v.text('blk2_info') and 'Breite +60°' in v.text('blk2_info')
          and info['frame']['y'] > bf['y'] + 100, f"{luav}: bewegt -> alle Werte unter dem Block ({v.text('blk2_info')!r})")
    v.tick(1000, 4)
    check(not v.c['blk2_info']['visible'], f'{luav}: Info verschwindet nach 3 s')
    for m in enc(10, 35, 0): v.midi(*m)
    v.tick()
    check(v.c['blk3_info']['visible'] and v.c['blk3_info']['frame']['y'] < v.c['c33']['frame']['y'], f'{luav}: unterer Block: Info darüber')
    # Ziehen im Kreis: nur Azimut, Elevation bleibt; Info zeigt sich auch beim eigenen Ziehen
    v.sent()
    px, py = x1, y1
    v.run(f"local c = controls.top_xy; c.values.touch = true; c.values.x = {(px - f[0]) / f[2]}; c.values.y = {1 - (py - f[1]) / f[3]}; onReceiveNotify('grab','top_xy')")
    v.run("local c = controls.top_xy; c.values.x = 0.2; c.values.y = 0.5; onReceiveNotify('drag','top_xy')")
    out = v.sent()
    check(any(m[:4] == [0xB0 + 12, 0, *m[2:3]] for m in out) and not any(m[0] == 0xBC and m[1] in (1, 33) for m in out),
          f'{luav}: Ziehen im Kreis sendet nur Azimut ({out[:4]})')
    v.run("onReceiveNotify('release','top_xy')"); v.tick()
    check(v.c['blk1_info']['visible'], f'{luav}: eigenes Ziehen zeigt die Info auch')
    # Horizont: Kreis wird kleiner und sitzt darüber
    v.run("onReceiveNotify('btn','pano_btn')"); v.tick()
    t = v.c['top_xy']['frame']
    check(v.c['circ3s']['visible'] and not v.c['circ3']['visible'] and t['h'] < 700 and t['y'] + t['h'] <= 62 + 960 * 0.66 + 1,
          f"{luav}: Horizont an: kleiner Kreis darüber ({t['y']}, {t['h']})")
    # Pegelfarbe aus der Palette (nicht Spurfarbe)
    v.midi(0xBE, 0, 100); v.tick(16, 5)
    col = v.c['c1_lvl']['color']
    check(abs(col['r'] - 0.48) < 0.02 and abs(col['g'] - 0.94) < 0.02, f"{luav}: Pegelbalken Mint ({col['r']:.2f},{col['g']:.2f})")
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
