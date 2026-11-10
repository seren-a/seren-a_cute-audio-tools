"""IEM space (iPad): Logik gegen den TouchOSC-Mock, beide Lua-Versionen."""
import os, sys, math
sys.path.insert(0, os.path.dirname(__file__))
from view_harness import View
TOSC = os.path.join(os.path.dirname(__file__), '..', 'dist', 'seren-a_IEM-Space.tosc')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def iem(v, obj, p, lo, hi):
    n = round((v - lo) / (hi - lo) * 16383); c = 4 * ((obj - 1) % 8) + p; ch = 12 + (obj - 1) // 8
    return [(0xB0 + ch, c, n // 128), (0xB0 + ch, c + 32, n % 128)]
def dec(msgs):
    """14-bit pairs -> {(obj, p): normalized}"""
    out, msb = {}, {}
    for m in msgs:
        st, cc, v = m
        if st in (0xBC, 0xBD):
            if cc < 32: msb[(st, cc)] = v
            else:
                c = cc - 32; obj = (st - 0xBC) * 8 + c // 4 + 1
                out[(obj, c % 4)] = (msb.get((st, c), 0) * 128 + v) / 16383
    return out
def center(v, n):
    f = v.c[n]['frame']; return f['x'] + f['w'] / 2, f['y'] + f['h'] / 2

for luav in ('lua51', 'lua54'):
    v = View(TOSC, luav)
    v.midi(*sx(4, text='REAPER'))
    for i, name in enumerate(['Vox', 'Gtr', 'Pad']):
        v.midi(*sx(1, i, text=name)); v.midi(*sx(3, i, 1))
    for m in iem(0, 1, 0, -180, 180) + iem(0, 1, 1, -180, 180) + iem(-90, 2, 0, -180, 180) + iem(0, 2, 1, -180, 180):
        v.midi(*m)
    v.tick()
    check(v.text('src') == 'REAPER ♡' and v.text('det_name') == 'Vox', f"{luav}: Quelle, erstes Objekt automatisch gewählt ({v.text('det_name')!r})")
    a1, a2 = v.c['d1_dot']['color']['a'], v.c['d2_dot']['color']['a']
    check(v.c['d1_ring']['visible'] and not v.c['d2_ring']['visible'] and a2 < 0.5 * a1 + 0.01, f'{luav}: gewähltes Objekt mit Ring, andere weicher (a {a1:.2f} / {a2:.2f})')
    # Auswahl per Pille: sendet Note an die DAW
    v.sent(); v.run("onReceiveNotify('btn','sel2')"); v.tick()
    check(v.text('det_name') == 'Gtr' and v.sent() == [[0x9E, 1, 127], [0x9E, 1, 0]], f'{luav}: Pille 2 wählt Gtr, auch in der DAW')
    v.run("onReceiveNotify('btn','sel9')"); v.tick()
    check(v.text('det_name') == 'Gtr', f'{luav}: leere Pille wählt nichts')
    # Ziehen in der Draufsicht: links auf dem Horizont = Az +90, El 0
    top = v.c['top_area']['frame']; R = top['w'] / 2 - 16
    tx = (top['w'] / 2 - R / 2) / top['w']; ty = 0.5
    v.sent()
    v.run(f"local c = controls.top_xy; c.values.touch = true; c.values.x = {tx}; c.values.y = {ty}; onReceiveNotify('drag','top_xy')")
    d = dec(v.sent())
    check(abs(d[(2, 0)] - (90 + 180) / 360) < 1e-3 and abs(d.get((2, 1), 0.5) - 0.5) < 1e-3, f'{luav}: Ziehen Draufsicht -> Objekt 2 Az +90 El 0 ({d})')
    v.tick()
    check(v.text('det_v1') == '+90.0°', f"{luav}: Anzeige folgt sofort ({v.text('det_v1')})")
    # Rückmeldung der DAW mit altem Wert während des Ziehens wird ignoriert
    for m in iem(-90, 2, 0, -180, 180): v.midi(*m)
    v.tick()
    check(v.text('det_v1') == '+90.0°', f'{luav}: altes Echo der DAW überschreibt das Ziehen nicht')
    v.tick(500)
    for m in iem(45, 2, 0, -180, 180): v.midi(*m)
    v.tick()
    check(v.text('det_v1') == '+45.0°', f'{luav}: danach gilt wieder die DAW')
    # Panorama: oben Mitte = Az 0 El +90; y=1 ist oben
    v.sent(); v.run("local c = controls.pano_xy; c.values.touch = true; c.values.x = 0.25; c.values.y = 0.75; onReceiveNotify('drag','pano_xy')")
    d = dec(v.sent())
    check(abs(d[(2, 0)] - (90 + 180) / 360) < 1e-3 and abs(d[(2, 1)] - (45 + 180) / 360) < 1e-3, f'{luav}: Panorama x .25 y .75 -> Az +90 El +45')
    # Width
    v.sent(); v.run("local c = controls.fa; c.values.touch = true; c.values.x = 0.75; onReceiveNotify('drag','fa')")
    d = dec(v.sent())
    check(abs(d[(2, 2)] - (90 + 360) / 720) < 1e-3, f'{luav}: Width-Fader 3/4 = +90° (Plugin-Bereich ±360)')
    # Leuchten
    g0 = v.c['d1_glow']['frame']['w']
    v.midi(0xBE, 0, 127); v.tick(16, 6)
    g1 = v.c['d1_glow']['frame']['w']; a = v.c['d1_glow']['color']['a']
    check(g1 > 2.5 * g0 and abs(g1 - 84) < 0.5, f'{luav}: Pegel 127 -> Glühen voll ({g0:.0f} -> {g1:.0f})')
    v.midi(0xBE, 0, 0); v.tick(16, 60)
    g2 = v.c['d1_glow']['frame']['w']
    check(30 < g2 < g1 - 1, f'{luav}: klingt weich ab, Rücklauf 13,3 dB/s ({g2:.0f})')
    v.tick(16, 420)
    check(abs(v.c['d1_glow']['frame']['w'] - 30) < 0.5, f'{luav}: nach ~6 s (60 dB Rücklauf + Abfall) wieder still')
    lv = v.c['r1_lvl']['frame']['w']
    check(lv < 1, f'{luav}: Pegelbalken in der Liste zurück')
    # DAW wählt Spur 3 -> hier mit
    v.midi(0x9E, 2, 127); v.tick()
    check(v.text('det_name') == 'Pad', f'{luav}: Auswahl in der DAW wird übernommen')
    # Bank
    v.sent(); v.run("onReceiveNotify('btn','bank_next')")
    check(v.sent() == [[0x9F, 3, 127], [0x9F, 3, 0]], f'{luav}: Bank vor')
    v.midi(*sx(7)); v.tick()
    check(not any(v.c[f'd{k}']['visible'] for k in range(1, 17)) and v.text('det_name') == 'nichts gewählt', f'{luav}: Löschen')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
