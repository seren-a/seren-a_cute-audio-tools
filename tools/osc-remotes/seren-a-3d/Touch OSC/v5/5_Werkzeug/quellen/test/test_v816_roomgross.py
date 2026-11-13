"""v8.16: Room „groß“ (iPad, Monitor 5:4, Monitor HD): Raum füllt den Bildschirm, Liste und Details weg, zurück mit „klein“."""
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
def fr(v, n): f = v.c[n]['frame']; return f['x'], f['y'], f['w'], f['h']
MED = (3.8, 2.1, 4.1, 4.0, 2.8, 1.8)
for name, tosc, W, H in (('iPad', 'ipad/dist/seren-a_IEM-Space.tosc', 1366, 1024), ('Monitor 5:4', 'monitor/dist/seren-a_IEM-Monitor.tosc', 1280, 1024),
                         ('Monitor HD', 'monitor/dist/seren-a_IEM-Monitor_HD.tosc', 1920, 1080)):
    v = View(os.path.join(D, '..', tosc)); ipad = name == 'iPad'
    v.midi(*sx(4, text='REAPER'))
    for o, nm in enumerate(('Vox', 'Gtr', 'Pad')):
        v.midi(*sx(1, o, text=nm)); v.midi(*sx(3, o, 1))
    v.midi(*room(0, MED, 'Medium Room')); v.midi(*room(1, MED, 'Medium Room')); v.midi(*room(2, MED, 'Medium Room'))
    for m in pos(0, 2.0, 1.0, 0.5) + pos(1, -1.0, -2.0, 0.0) + pos(2, 0.0, 2.0, 0.0): v.midi(*m)
    v.run("onReceiveNotify('btn','mode_room')"); v.tick(16, 3)
    w0 = fr(v, 'rt_floor')
    check(v.c['rz_big']['visible'] and v.text('rz_big_lbl') == 'groß', f'{name}: Taste „groß“ da')
    listvis = (v.c['r1_bg']['visible'] if ipad else v.c['c1']['visible'])
    check(listvis, f'{name}: vorher Liste sichtbar')
    v.run("onReceiveNotify('btn','rz_big')"); v.tick(16, 3)
    w1 = fr(v, 'rt_floor')
    check(v.text('rz_big_lbl') == 'klein', f'{name}: Taste heißt jetzt „klein“')
    check(w1[2] * w1[3] > w0[2] * w0[3] * 1.2, f'{name}: Raumfläche größer ({w0[2]:.0f}x{w0[3]:.0f} -> {w1[2]:.0f}x{w1[3]:.0f})')
    check(w1[0] >= 0 and w1[1] >= 0 and w1[0] + w1[2] <= W and w1[1] + w1[3] <= H, f'{name}: im Bild')
    if ipad:
        check(not v.c['r1_bg']['visible'] and not v.c['det_g']['visible'], f'{name}: Liste und Details ausgeblendet')
    else:
        check(not any(v.c[f'c{k}']['visible'] for k in range(1, 4)), f'{name}: Liste ausgeblendet')
        tx = fr(v, 'top_xy')
        check(tx[2] > 0.9 * W, f'{name}: Tipp-Fläche folgt der großen Ansicht (w {tx[2]:.0f})')
    # Quellen liegen weiter im Raum, im Bild
    for d in ('d1', 'd2', 'd3'):
        b = fr(v, d); check(0 <= b[0] and b[0] + b[2] <= W and 0 <= b[1] and b[1] + b[3] <= H, f'{name}: Quelle {d} im Bild')
    lx = fr(v, 'rt_lis'); x1 = fr(v, 'd1')
    # mit Horizont: Seitenansicht unten dazu
    if not ipad: v.run("onReceiveNotify('btn','pano_btn')"); v.tick(16, 3)
    rs = fr(v, 'rs_floor'); rt = fr(v, 'rt_floor')
    check(v.c['rs_floor']['visible'] and rs[1] >= rt[1] + rt[3] - 1, f'{name}: Seitenansicht unter der Draufsicht')
    check(rs[0] + rs[2] <= W and rs[1] + rs[3] <= H, f'{name}: Seitenansicht im Bild')
    v.run("onReceiveNotify('btn','rz_big')"); v.tick(16, 3)
    w2 = fr(v, 'rt_floor')
    check(v.text('rz_big_lbl') == 'groß' and (v.c['r1_bg']['visible'] if ipad else v.c['c1']['visible']), f'{name}: „klein“ bringt Liste zurück')
    if ipad: check(v.c['det_g']['visible'], f'{name}: Details wieder da')
    # Moduswechsel aus Room heraus: Liste bleibt da, auch wenn groß an war
    v.run("onReceiveNotify('btn','rz_big')"); v.tick(16, 2)
    v.run("onReceiveNotify('btn','mode_iem')"); v.tick(16, 3)
    check((v.c['r1_bg']['visible'] if ipad else v.c['c1']['visible']), f'{name}: andere Modi zeigen die Liste trotz „groß“')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED'); sys.exit(1 if fails else 0)
