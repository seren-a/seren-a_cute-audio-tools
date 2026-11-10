"""IEM monitor (5:4): Logik gegen den strengen TouchOSC-Mock, Lua 5.1 und 5.4."""
import os, sys
from view_harness import View
D = os.path.dirname(os.path.abspath(__file__))
TOSC = os.path.join(D, '..', 'monitor', 'dist', 'seren-a_IEM-Monitor.tosc')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def enc(v, o, p):  # value to object o (0-based): CC below 16, SysEx 10 above
    n = round((v + 180) / 360 * 16383)
    if o < 16:
        ch, cc = 12 + o // 8, 4 * (o % 8) + p
        return [[0xB0 + ch, cc, n // 128], [0xB0 + ch, cc + 32, n % 128]]
    return [[0xF0, 0x7D, 0x4F, 10, 0, o, p, n // 128, n % 128, 0xF7]]
for luav in ('lua51', 'lua54'):
    v = View(TOSC, luav)
    v.midi(*sx(4, text='REAPER')); v.midi(*sx(12, 64))
    for o in range(40):
        v.midi(*sx(1, o, text=f'Track {o + 1}'))
        fl = 1 | (16 if o == 2 else 0) | (32 if o == 3 else 0) | (64 if o == 4 else 0)
        v.midi(*sx(3, o, fl))
        for m in enc(o * 9 - 180, o, 0) + enc(0, o, 1): v.midi(*m)
    v.midi(*sx(11, 5, text='kick drum'))
    v.tick()
    check(v.c['c1']['visible'] and not v.c['c17']['visible'] and v.text('c1_name') == 'Track 1', f'{luav}: 16er: Zellen 1-16')
    check(v.c['d30']['visible'] is False and v.c['d16']['visible'], f'{luav}: 16er: Punkte 1-16')
    check(v.c['c3_fx']['visible'] and v.c['c4_grp']['visible'] and v.text('c5_glyph') == '♪', f'{luav}: Kennzeichnung FX/Gruppe/MIDI')
    v.run("onReceiveNotify('btn','lay_32v')"); v.tick()
    f17 = v.c['c17']['frame']
    check(v.c['c32']['visible'] and abs(f17['x'] - 1110) < 0.1 and abs(f17['y'] - 64) < 0.1, f'{luav}: 32v: zweite Spalte ab Spur 17 ({f17})')
    check(v.c['d20']['visible'], f'{luav}: 32v: Punkt 20 (Wert per SysEx 10)')
    v.run("onReceiveNotify('btn','lay_32h')"); v.tick()
    f1, f17 = v.c['c1']['frame'], v.c['c17']['frame']
    check(f1['y'] == 60 and f17['y'] == 914 and abs(f17['x'] - 1) < 0.1, f'{luav}: 32h: Reihe oben 1-16, unten 17-32')
    v.run("onReceiveNotify('btn','lay_64')"); v.tick()
    f33, f49 = v.c['c33']['frame'], v.c['c49']['frame']
    check(v.c['c40']['visible'] and not v.c['c41']['visible'] and f33['y'] > 700 and f49['x'] > 1000,
          f'{luav}: 64: Ecken (33 unten links, 49 unten rechts), nur vorhandene Spuren')
    # drag: grab nearest dot at the position of object 20, move
    ca = (160, 62, 960, 960)
    v.run(f"local c = controls.top_xy; c.frame = {{x={ca[0]},y={ca[1]},w={ca[2]},h={ca[3]}}}")
    import math
    az = 19 * 9 - 180; R = ca[2] / 2 - 14; r = R   # el 0 = horizon = edge (IEM, linear)
    px = ca[0] + ca[2] / 2 - r * math.sin(math.radians(az)); py = ca[1] + ca[3] / 2 - r * math.cos(math.radians(az))
    v.sent()
    v.run(f"local c = controls.top_xy; c.values.touch = true; c.values.x = {(px - ca[0]) / ca[2]}; c.values.y = {1 - (py - ca[1]) / ca[3]}; onReceiveNotify('grab','top_xy')")
    sel = v.sent()
    check(sel == [[0x9E, 19, 127], [0x9E, 19, 0]], f'{luav}: Anfassen wählt den nächsten Punkt (Spur 20) {sel}')
    v.run(f"local c = controls.top_xy; c.values.x = 0.5; c.values.y = 1.0; onReceiveNotify('drag','top_xy')")
    out = v.sent()
    check(out and out[0][:7] == [0xF0, 0x7D, 0x4F, 10, 0, 19, 0], f'{luav}: Ziehen Spur 20 -> SysEx 10 ({out[:1]})')
    check(all(m[6] == 0 for m in out if m[0] == 0xF0), f'{luav}: im Kreis nur Azimut, keine Elevation ({[m[6] for m in out]})')
    v.run("onReceiveNotify('release','top_xy')")
    # pegel + skala
    v.midi(0xBE, 0, 127); v.tick(16, 5)
    check(v.c['c1_lvl']['frame']['w'] > 0, f'{luav}: Pegelbalken')
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_sc_ebu')"); v.tick()
    check(v.c['cfg_overlay']['visible'] and 'EBU' in v.text('cfg_info'), f"{luav}: config: Skala EBU ({v.text('cfg_info')[:40]})")
    v.run("onReceiveNotify('btn','cfg_sh_fx')"); v.run("onReceiveNotify('btn','cfg_close')"); v.tick()
    cells3 = [i for i in range(1, 65) if v.c[f'c{i}']['visible'] and v.text(f'c{i}_num') == '3']
    check(not cells3 and not v.c['d3']['visible'], f'{luav}: FX-Spuren ausgeblendet (Liste rückt auf)')
    v.run("onReceiveNotify('btn','col_btn')"); v.midi(*sx(2, 0, 127, 0, 0)); v.tick()
    col = v.c['c1_num']['color']
    check(col['r'] > 0.99 and col['g'] < 0.01, f'{luav}: Knopf farben -> Spurfarbe rot ({col})')
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_th_nuendo')"); v.tick()
    check(abs(v.g.root.color.r - 0.11) < 0.01, f'{luav}: Theme Nuendo dark')
    v.run("onReceiveNotify('btn','cfg_ic_both')"); v.run("onReceiveNotify('btn','cfg_close')"); v.run("onReceiveNotify('btn','lay_16')"); v.tick()
    c6 = [i for i in range(1, 65) if v.c[f'c{i}']['visible'] and v.text(f'c{i}_num') == '6']
    check(c6 and v.text(f'c{c6[0]}_glyph') == '◉' and v.text('d6_icon') == '◉', f"{luav}: Symbol 'kick' an Liste und Punkt")
    v.run("onReceiveNotify('btn','pano_btn')"); v.tick()
    check(v.c['pano1']['visible'] and v.c['p1']['visible'], f'{luav}: Horizont-Overlay')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
