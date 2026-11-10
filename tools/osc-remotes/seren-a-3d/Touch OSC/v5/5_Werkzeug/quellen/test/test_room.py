"""ROOM-Ansicht (dearVR PRO) auf Monitor 5:4 und iPad: Wände, Hörer, Quellen, gemeinsamer Raum."""
import os, sys
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
def room(o, walls, name):
    b = [14, o]
    for w in walls: cm = round(w * 100); b += [cm // 128, cm % 128]
    return sx(*b, text=name)
def ctr(v, n): f = v.c[n]['frame']; return f['x'] + f['w'] / 2, f['y'] + f['h'] / 2
MED = (3.8, 2.1, 4.1, 4.0, 2.8, 1.8)
for name, tosc, top in (('Monitor', os.path.join(D, '..', 'monitor', 'dist', 'seren-a_IEM-Monitor.tosc'), None),
                        ('iPad', os.path.join(D, '..', 'ipad', 'dist', 'seren-a_IEM-Space.tosc'), None)):
    v = View(tosc)
    v.midi(*sx(4, text='REAPER'))
    for o, nm in enumerate(('Vox', 'Gtr', 'Pad')):
        v.midi(*sx(1, o, text=nm)); v.midi(*sx(3, o, 1))
    v.midi(*room(0, MED, 'Medium Room')); v.midi(*room(1, MED, 'Medium Room'))
    for m in pos(0, 2.0, 1.0, 0.5) + pos(1, -1.0, -2.0, 0.0) + pos(2, 0.0, 5.0, 0.0): v.midi(*m)
    v.run("onReceiveNotify('btn','mode_room')"); v.tick(16, 3)
    check(v.c['rt_floor']['visible'] and v.c['rt_wl']['visible'] and v.c['d1']['visible'] and v.c['d2']['visible'],
          f'{name}: Raum mit Wänden, Quellen 1+2 sichtbar')
    lx, ly = ctr(v, 'rt_lis')
    wl, wr = v.c['rt_wl']['frame'], v.c['rt_wr']['frame']
    sc = (wr['x'] - wl['x']) / (3.8 + 4.1)
    x1, y1 = ctr(v, 'd1')
    check(abs((x1 - lx) / sc - 2.0) < 0.05 and abs((ly - y1) / sc - 1.0) < 0.05, f'{name}: Quelle 1 2 m rechts, 1 m vorn vom Hörer ({(x1 - lx) / sc:.2f}, {(ly - y1) / sc:.2f})')
    check(abs((lx - (wl['x'] + 2)) / sc - 3.8) < 0.05, f'{name}: linke Wand 3,8 m links vom Hörer')
    check('Medium Room' in v.text('rt_title') and 'anderem Raum' in v.text('rt_title'), f"{name}: Titel {v.text('rt_title')!r}")
    a3 = v.c['d3_dot']['color']['a']
    check(a3 < 0.3, f'{name}: Quelle 3 (ohne Raum) blass ({a3:.2f})')
    # Zoom wie dearVR: + = näher (3 m), − = weiter (6, 12 m), Raum = ganzer Raum
    v.run("onReceiveNotify('btn','rz_plus')"); v.tick()
    lx, ly = ctr(v, 'rt_lis'); x1, _ = ctr(v, 'd1')
    tf = v.c['top_xy']['frame'] if name == 'Monitor' else v.c['top_area']['frame']
    check(v.text('rz_fit_lbl') == '± 3 m' and not v.c['rt_wl']['visible'] and v.c['rz_plus']['visible'],
          f"{name}: Zoom ± 3 m, linke Wand (3,8 m) außerhalb -> unsichtbar ({v.text('rz_fit_lbl')!r})")
    v.run("onReceiveNotify('btn','rz_minus')"); v.run("onReceiveNotify('btn','rz_minus')"); v.tick()
    lx2, _ = ctr(v, 'rt_lis'); x2, _ = ctr(v, 'd1')
    check(v.text('rz_fit_lbl') == '± 12 m' and abs((x2 - lx2) * 4 - (x1 - lx)) < 2, f"{name}: ± 12 m, Quelle 4x näher am Hörer")
    v.run("onReceiveNotify('btn','rz_fit')"); v.tick()
    check(v.text('rz_fit_lbl') == 'Raum' and v.c['rt_wl']['visible'], f'{name}: Raum = ganzer Raum wieder')
    v.midi(*room(2, MED, 'Medium Room')); v.tick()
    check('anderem Raum' not in v.text('rt_title'), f'{name}: alle im selben Raum -> gemeinsamer Raum')
    v.midi(*room(2, (6.7, 3.4, 6.9, 8.0, 3.3, 1.8), 'Studio Room')); v.tick()
    check('1 Quelle in anderem Raum' in v.text('rt_title'), f"{name}: anderer Raum erkannt ({v.text('rt_title')!r})")
    v.sent()
    v.run(f"local c = controls.top_xy; c.values.touch = true; c.values.x = 0.5; c.values.y = 0.5; onReceiveNotify('grab','top_xy')" if name == 'Monitor'
          else "onReceiveNotify('btn','sel1')")
    v.run("local c = controls.top_xy; c.values.touch = true; c.values.x = 0.1; c.values.y = 0.1; onReceiveNotify('drag','top_xy')")
    s = [m for m in v.sent() if m[0] in (0xBC, 0xBD) or (m[0] == 0xF0 and len(m) > 4 and m[3] == 10)]
    check(s == [], f'{name}: im Raum wird nichts verschoben (nur Anzeige) {s[:2]}')
    v.run("onReceiveNotify('btn','mode_iem')"); v.tick()
    check(not v.c['rt_floor']['visible'], f'{name}: zurück auf space: Raum weg')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
