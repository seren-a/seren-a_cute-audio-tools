"""v8.21 Monitor: Split-Ansicht (4 Felder: space, multi, panner, room; eine gemeinsame Spurliste)."""
import sys
from view_harness import View
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def sel(v, name): v.run(f"onReceiveNotify('btn','{name}')")
def ctr(v, n):
    f = v.c[n]['frame']; return f['x'] + f['w'] / 2, f['y'] + f['h'] / 2
def inside(v, n, q):
    x, y = ctr(v, n); f = v.c[q]['frame']
    return f['x'] <= x <= f['x'] + f['w'] and f['y'] <= y <= f['y'] + f['h']
def feed(v):
    v.midi(*sx(4, text='REAPER'))
    for o, (nm, fl) in enumerate((('Vox', 1), ('Pan', 2), ('Both', 3), ('Room', 0))):
        v.midi(*sx(1, o, text=nm)); v.midi(*sx(3, o, fl)); v.midi(*sx(17, o, 0, o + 1))
    v.midi(*sx(14, 3, 0, 100, 0, 100, 0, 100, 0, 100, 0, 100, 0, 100, text='Box'))
    for p_ in range(3):
        n = round((1.0 + 32) / 64 * 16383); v.midi(*[0xF0, 0x7D, 0x4F, 10, 3, 3, p_, n // 128, n % 128, 0xF7])
    v.tick(16, 4)
for lv in ('lua51', 'lua54'):
    for nm, tosc in (('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc'), ('MonitorHD', '../monitor/dist/seren-a_IEM-Monitor_HD.tosc')):
        v = View(tosc, lv); feed(v)
        check(v.c['mode_sp']['visible'], f'{lv}/{nm}: Reiter split in der Kopfzeile')
        xs = [(v.c[n]['frame']['x'], v.c[n]['frame']['w']) for n in ('mode_iem', 'mode_me', 'mode_mp', 'mode_room', 'mode_fdn', 'mode_mcfx', 'mode_sp', 'lay_16', 'lay_32v', 'lay_32h', 'lay_32r', 'lay_64', 'pano_btn', 'col_btn', 'cfg_btn', 'log_btn')]
        check(all(xs[i][0] + xs[i][1] <= xs[i + 1][0] for i in range(len(xs) - 1)) and xs[-1][0] + xs[-1][1] <= v.c['bank_prev']['frame']['x'],
              f'{lv}/{nm}: Kopfzeile ohne Überlappung (Ende {xs[-1][0] + xs[-1][1]:.0f}, Bank ab {v.c["bank_prev"]["frame"]["x"]:.0f})')
        sel(v, 'lay_32v'); v.tick(16, 3)
        sel(v, 'mode_sp'); v.tick(16, 5)
        check(all(v.c[f'spq{i}_bg']['visible'] for i in (1, 2, 3, 4)), f'{lv}/{nm}: vier Felder sichtbar')
        check(not v.c['circ1']['visible'] and not v.c['sq1']['visible'] and not v.c['pano1']['visible'] and not v.c['hall_g']['visible'],
              f'{lv}/{nm}: Einzelansichten aus')
        check(v.text('spq1_title').startswith('space') and v.text('spq2_title').startswith('multi') and v.text('spq3_title').startswith('panner') and v.text('spq4_title').startswith('room'),
              f'{lv}/{nm}: Feldtitel')
        check(v.c['c1']['visible'] and v.c['c4']['visible'] and not v.c['c5']['visible'], f'{lv}/{nm}: gemeinsame Liste (4 Spuren)')
        check(v.text('c1_val').startswith('space') and 'panner' in v.text('c2_val') and 'space' in v.text('c3_val') and 'panner' in v.text('c3_val') and 'room' in v.text('c4_val'),
              f'{lv}/{nm}: Liste zeigt, in welchen Feldern die Spur vorkommt ({[v.text(f"c{i}_val") for i in (1, 2, 3, 4)]})')
        check(v.c['d1']['visible'] and inside(v, 'd1', 'spq1_bg'), f'{lv}/{nm}: Vox im Feld space')
        check(not v.c['d2']['visible'] and v.c['d3']['visible'], f'{lv}/{nm}: Pan nicht im Feld space, Both schon')
        check(v.c['d34']['visible'] and inside(v, 'd34', 'spq3_bg') and v.c['d35']['visible'], f'{lv}/{nm}: Pan + Both im Feld panner')
        check(v.c['d52']['visible'] and inside(v, 'd52', 'spq4_bg'), f'{lv}/{nm}: Room-Spur im Feld room')
        check(not v.c['d17']['visible'], f'{lv}/{nm}: multi leer ohne MultiEncoder')
        check(v.c['spq1_c1']['visible'] and v.c['spq3_sqb']['visible'] and not v.c['spq3_c1']['visible'], f'{lv}/{nm}: Kreis für space, Quadrat für panner')
        # Antippen wählt im Feld; Ziehen bewegt nur dort
        f = v.c['top_xy']['frame']
        def grab(px, py):
            v.run(f"local c = controls.top_xy; c.values.touch = true; c.values.x = {(px - f['x']) / f['w']}; c.values.y = {1 - (py - f['y']) / f['h']}; onReceiveNotify('grab','top_xy')")
        v.sent()
        px, py = ctr(v, 'd34'); grab(px, py); s = v.sent()
        check([0x9E, 1, 127] in s, f'{lv}/{nm}: Antippen im Feld panner wählt Spur 2 ({s})')
        v.run(f"local c = controls.top_xy; c.values.x = {(px - f['x']) / f['w'] + 0.02}; c.values.y = {1 - (py - f['y']) / f['h']}; onReceiveNotify('drag','top_xy')")
        out = v.sent()
        check(out and out[0][0] == 0xBA and out[0][1] == 4, f'{lv}/{nm}: Ziehen im Feld panner -> Panner-X von Spur 2 (CC {out[:1]})')
        v.run("onReceiveNotify('release','top_xy')"); v.tick(16, 3)
        check(v.c['c2']['values']['text'] is not None, f'{lv}/{nm}: nach Ziehen weiter intakt')
        px, py = ctr(v, 'd1'); grab(px, py); s = v.sent()
        check([0x9E, 0, 127] in s, f'{lv}/{nm}: Antippen im Feld space wählt Spur 1')
        v.run("onReceiveNotify('release','top_xy')")
        # Layout-Tasten und Horizont wirken im Split nicht
        sel(v, 'lay_64'); sel(v, 'pano_btn'); v.tick(16, 3)
        check(v.c['spq1_bg']['visible'] and not v.c['pano1']['visible'], f'{lv}/{nm}: Layout/Horizont im Split ohne Wirkung')
        # Feld abschalten: nur 3 Felder, Raster 2×2 mit Lücke, Spur-Zuordnung bleibt
        sel(v, 'cfg_btn'); sel(v, 'cfg_page'); sel(v, 'cfg_sp_room'); sel(v, 'cfg_close'); v.tick(16, 4)
        check(not v.c['spq4_bg']['visible'] or v.text('spq4_title') == '' or not v.text('spq4_title').startswith('room'), f'{lv}/{nm}: Feld room abgeschaltet')
        check(not v.c['d52']['visible'] and not v.c['c4']['visible'], f'{lv}/{nm}: Room-Punkt weg, Spur nur im Room-Feld verschwindet aus der Liste')
        # zurück zu space: Layout wie vorher (32v), Punkte wieder normal
        sel(v, 'mode_iem'); v.tick(16, 4)
        check(v.c['circ1']['visible'] and not v.c['spq1_bg']['visible'] and v.c['d1']['visible'], f'{lv}/{nm}: zurück in space (Kreis, Felder aus)')
        check(not v.c['d33']['visible'] and not v.c['d34']['visible'], f'{lv}/{nm}: Split-Punkte aus')
        check(v.c['lay_32v']['visible'], f'{lv}/{nm}: Layout 32v wieder aktiv')
        # Zustand merken
        sel(v, 'mode_sp'); v.sent(); v.tick(1200, 6)
        vs = [x for x in v.sent() if x[:4] == [0xF0, 0x7D, 0x4F, 0x0E]]
        st = ''.join(chr(c) for c in vs[-1][5:-1]) if vs else ''
        check('mode=sp' in st and 'lay=32v' in st and 'spl=23' in st, f'{lv}/{nm}: Ansicht merkt split, alte Ansicht und Felder (v8.22.7: + Energie = 16) ({st!r})')
        # Config: Reiter split ausblenden
        sel(v, 'cfg_btn'); sel(v, 'cfg_page'); sel(v, 'cfg_tab_sp'); sel(v, 'cfg_close'); v.tick(16, 4)
        check(not v.c['mode_sp']['visible'] and v.c['mode_iem']['visible'], f'{lv}/{nm}: Reiter split lässt sich ausblenden')
print('\nALL OK' if not fails else f'\n{fails} FAILED'); sys.exit(1 if fails else 0)
