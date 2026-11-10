"""Objekt-Übersicht: Logik gegen den TouchOSC-Mock."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from view_harness import View
TOSC = os.path.join(os.path.dirname(__file__), '..', 'dist', 'seren-a_Objekt-Uebersicht.tosc')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1

def sx(cmd, *data, text=''):
    return [0xF0, 0x7D, 0x4F, cmd, *data, *[ord(c) for c in text], 0xF7]
def cc14(v, ch, obj, p, lo, hi):
    n = round((v - lo) / (hi - lo) * 16383)
    c = 4 * ((obj - 1) % 8) + p
    return [(0xB0 + ch, c, n // 128), (0xB0 + ch, c + 32, n % 128)]
def iem(v, obj, p, rng):
    return cc14(v, 12 + (obj - 1) // 8, obj, p, *rng)
def mp(v, obj, p):
    return cc14(v, 10 + (obj - 1) // 8, obj, p, -100, 100)
def center(v, n):
    f = v.c[n]['frame']; return f['x'] + f['w'] / 2, f['y'] + f['h'] / 2

for luav in ('lua51', 'lua54'):
    v = View(TOSC, luav)
    check(v.text('src') == 'keine DAW' and not any(v.c[f'd{k}']['visible'] for k in range(1, 17)), f'{luav}: Start leer')
    v.midi(*sx(4, text='NUENDO'))
    v.midi(*sx(1, 0, text='Vox')); v.midi(*sx(3, 0, 1)); v.midi(*sx(2, 0, 127, 0, 0))
    v.midi(*sx(1, 1, text='Gtr')); v.midi(*sx(3, 1, 1))
    v.midi(*sx(1, 2, text='Bass')); v.midi(*sx(3, 2, 0))
    for m in iem(90, 1, 0, (-180, 180)) + iem(0, 1, 1, (-180, 180)) + iem(0, 2, 0, (-180, 180)) + iem(90, 2, 1, (-180, 180)):
        v.midi(*m)
    v.tick()
    top = v.c['top_area']['frame']; cx, cy = top['x'] + top['w'] / 2, top['y'] + top['h'] / 2
    R = top['w'] / 2 - 14
    x1, y1 = center(v, 'd1'); x2, y2 = center(v, 'd2')
    check(v.text('src') == 'NUENDO', f'{luav}: Quelle NUENDO')
    check(abs(x1 - (cx - R / 2)) < 1 and abs(y1 - cy) < 1, f'{luav}: Az +90 El 0 = links auf dem Horizont ({x1:.0f},{y1:.0f})')
    check(abs(x2 - cx) < 1 and abs(y2 - cy) < 1, f'{luav}: El +90 = Mitte')
    col = v.c['d1_dot']['color']
    check(abs(col['r'] - 1) < 1e-6 and col['g'] == 0, f'{luav}: Spurfarbe aus Nuendo')
    sec = v.c['sec_area']['frame']; ex, ey = center(v, 'e1')
    check(abs(ex - (sec['x'] + sec['w'] * 0.25)) < 1 and abs(ey - (sec['y'] + sec['h'] / 2)) < 1, f'{luav}: Panorama Az +90 bei einem Viertel')
    rows = lambda: {v.text(f'r{i}_num'): i for i in range(1, 17) if v.c[f'r{i}_bg']['visible']}
    check(v.c['d3']['visible'] is False and rows() == {'1': 1, '2': 2},
          f'{luav}: Spur ohne StereoEncoder: kein Punkt, keine Zeile, Liste rückt auf ({rows()})')
    check(v.text('r1_name') == 'Vox' and v.text('r1_val') == 'Az +90.0°   El +0.0°', f'{luav}: Liste {v.text("r1_val")!r}')
    # Objekt 9 auf Kanal 14
    v.midi(*sx(3, 8, 1))
    for m in iem(-45, 9, 0, (-180, 180)): v.midi(*m)
    v.tick()
    check(v.c['d9']['visible'] and v.text(f"r{rows()['9']}_val").startswith('Az -45.0°'), f'{luav}: Objekt 9 kommt über Kanal 14')
    # Auswahl von Nuendo, Antippen sendet Note
    v.midi(0x9E, 1, 127); v.tick()
    check(v.c['d2_ring']['visible'] and v.text('det_name') == '2  Gtr', f'{luav}: gewählte Spur: Ring + Detail ({v.text("det_name")!r})')
    v.sent()
    v.run("onReceiveNotify('btn','r3_tap')")
    check(v.sent() == [[0x9E, 8, 127], [0x9E, 8, 0]], f'{luav}: Antippen Zeile 3 (= Spur 9, Spuren 3–8 ohne Encoder) = Note 8 auf Kanal 15')
    v.run("onReceiveNotify('btn','bank_next')")
    check(v.sent() == [[0x9F, 3, 127], [0x9F, 3, 0]], f'{luav}: Bank vor = Note 3 Kanal 16')
    v.midi(*sx(5, 1)); v.tick()
    check(v.text('bank') == 'Spuren 17–32' and v.text('r1_num') == '17', f'{luav}: Bank 2 nummeriert 17-32')
    # MultiPanner
    v.run("onReceiveNotify('btn','mode_mp')")
    v.midi(*sx(3, 0, 3)); v.midi(*sx(6, 0, text='Vox MP'))
    for m in mp(100, 1, 0) + mp(0, 1, 1) + mp(-100, 1, 2): v.midi(*m)
    v.tick()
    mx, my = center(v, 'd1'); rx, ry = center(v, 'e1')
    check(abs(mx - (top['x'] + top['w'])) < 1 and abs(my - cy) < 1, f'{luav}: MP X +100 = rechter Rand')
    check(abs(ry - (sec['y'] + sec['h'])) < 1, f'{luav}: MP Z -100 = unten in der Rückansicht')
    check(v.text('r1_name') == 'Vox MP' and v.c['d2']['visible'] is False, f'{luav}: MP zeigt nur zugewiesene Objekte')
    check(v.c['bg_top_mp']['visible'] and not v.c['bg_top_iem']['visible'], f'{luav}: Hintergrund wechselt')
    v.sent(); v.run("onReceiveNotify('btn','r1_tap')")
    check(v.sent() == [], f'{luav}: im MP-Modus wählt Antippen keine Spur')
    v.midi(*sx(7)); v.run("onReceiveNotify('btn','mode_iem')"); v.tick()
    check(not any(v.c[f'd{k}']['visible'] for k in range(1, 17)), f'{luav}: Löschen leert alles')
    # Ignoriert fremde Kanäle (Panner CC auf 16, Twister CC auf 1, Pitchbend)
    v.midi(0xBF, 1, 64); v.midi(0xB0, 0, 64); v.midi(0xE0, 0, 64); v.tick()
    check(not any(v.c[f'd{k}']['visible'] for k in range(1, 17)), f'{luav}: Panner-, Twister- und Pitchbend-Daten ignoriert')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
