"""v8.22 Oberflächen: Energie-Reiter (cmd 28/29, 0x18 Art 3), manuelle Skala, Kopfzeile, Konfig-Reiter."""
import sys
from view_harness import View
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
TABS = ('mode_iem', 'mode_me', 'mode_mp', 'mode_room', 'mode_fdn', 'mode_mcfx', 'mode_en')
SUITES = (('iPad', '../ipad/dist/seren-a_IEM-Space.tosc', TABS + ('log_btn', 'col_btn', 'cfg_btn', 'n32_btn'), 'bank_prev', 'r'),
          ('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc', TABS + ('mode_sp', 'lay_16', 'lay_32v', 'lay_32h', 'lay_32r', 'lay_64', 'pano_btn', 'col_btn', 'cfg_btn', 'log_btn'), 'bank_prev', 'c'),
          ('MonitorHD', '../monitor/dist/seren-a_IEM-Monitor_HD.tosc', TABS + ('mode_sp', 'lay_16', 'lay_32v', 'lay_32h', 'lay_32r', 'lay_64', 'pano_btn', 'col_btn', 'cfg_btn', 'log_btn'), 'bank_prev', 'c'))
def sel(v, name): v.run(f"onReceiveNotify('btn','{name}')")
def col(v, n):
    c = v.c[n]['color']; return None if c is None else (round(c['r'], 3), round(c['g'], 3), round(c['b'], 3), round(c['a'], 2))
def ctr(v, n):
    f = v.c[n]['frame']; return f['x'] + f['w'] / 2, f['y'] + f['h'] / 2
def send_map(v, peak_rc=(3, 5), st=1, src=1, pk=-6, rg=30, ordr=3, name='Amb'):
    v.midi(*sx(29, st, src, pk + 64, rg, ordr, 100, text=name))
    for r in range(12):
        vals = [10] * 24
        if r == peak_rc[0]: vals[peak_rc[1]] = 127
        if r == 7: vals[0] = 80
        v.midi(*sx(28, r, *vals))
for lv in ('lua51', 'lua54'):
    for nm, tosc, hdr, bank, rp in SUITES:
        v = View(tosc, lv)
        v.midi(*sx(4, text='REAPER'))
        for o, n_ in enumerate(('Vox', 'Amb 3OA')):
            v.midi(*sx(1, o, text=n_)); v.midi(*sx(17, o, 0, o + 1))
        v.tick(16, 3); v.sent()
        check(v.c['mode_en']['visible'], f'{lv}/{nm}: Reiter energy in der Kopfzeile')
        xs = [(v.c[n]['frame']['x'], v.c[n]['frame']['w']) for n in hdr if v.c[n]['visible']]
        check(all(xs[i][0] + xs[i][1] <= xs[i + 1][0] + 0.5 for i in range(len(xs) - 1)) and xs[-1][0] + xs[-1][1] <= v.c[bank]['frame']['x'],
              f'{lv}/{nm}: Kopfzeile ohne Überlappung (Ende {xs[-1][0] + xs[-1][1]:.0f}, Bank ab {v.c[bank]["frame"]["x"]:.0f})')
        check(not v.c['en_g']['visible'], f'{lv}/{nm}: Energie-Anzeige zunächst aus')
        sel(v, 'mode_en'); v.tick(16, 4)
        s = v.sent()
        h18 = [x for x in s if x[:4] == [0xF0, 0x7D, 0x4F, 0x18]]
        check(h18 and h18[-1][4:6] == [3, 0], f'{lv}/{nm}: Reiter meldet Art 3 an die DAW ({h18[-1] if h18 else None})')
        check(v.c['en_g']['visible'] and not v.c['hall_g']['visible'], f'{lv}/{nm}: en_g sichtbar, Hall-Anzeige aus')
        check(v.c[rp+'1_name']['visible'] and v.text(rp+'1_name') == 'Vox' and v.text(rp+'2_name') == 'Amb 3OA', f'{lv}/{nm}: Spurliste bleibt ({v.text(rp+"1_name")}, {v.text(rp+"2_name")})')
        check('seren.a 3D Energy' in v.text('en_sub'), f'{lv}/{nm}: ohne Daten: Hinweis auf das JSFX ({v.text("en_sub")})')
        check(v.text('en_peaklbl') == '' and not v.c['en_peak']['visible'], f'{lv}/{nm}: ohne Daten kein Maximum')
        send_map(v); v.tick(16, 4)
        check('Amb' in v.text('en_sub') and '3. Ordnung' in v.text('en_sub'), f'{lv}/{nm}: Kopfzeile Spur/Ordnung ({v.text("en_sub")})')
        hot, cold = col(v, 'ec3_5'), col(v, 'ec3_6')
        check(hot and cold and hot != cold and hot[3] == 1, f'{lv}/{nm}: Spitzenzelle anders gefärbt als die Nachbarn ({hot} / {cold})')
        pl = v.text('en_peaklbl')
        check('Az +98°' in pl, f'{lv}/{nm}: Maximum-Text ({pl})')
        check('El +38°' in pl, f'{lv}/{nm}: Maximum Elevation ({pl})')
        check('+10.0 dB' in pl, f'{lv}/{nm}: Maximum-Pegel 127 = +10 dB ({pl})')
        check(v.c['en_peak']['visible'], f'{lv}/{nm}: Maximum-Ring sichtbar')
        mp, pk = v.c['en_map']['frame'], v.c['en_peak']['frame']
        px, py = pk['x'] + pk['w'] / 2, pk['y'] + pk['h'] / 2
        check(abs(px - (mp['x'] + 5.5 * mp['w'] / 24)) < 1 and abs(py - (mp['y'] + 3.5 * mp['h'] / 12)) < 1, f'{lv}/{nm}: Ring liegt auf Zelle (Zeile 3, Spalte 5)')
        check('Peak -6 dB' in v.text('en_pk_val') and 'Bereich 30 dB' in v.text('en_rg_val'), f'{lv}/{nm}: Skala aus dem Plugin ({v.text("en_pk_val")}, {v.text("en_rg_val")})')
        check('EnergyVisualizer' in v.text('en_scale'), f'{lv}/{nm}: Skalenquelle: Plugin ({v.text("en_scale")})')
        check('gesamt -' in v.text('en_tot') and 'dB RMS' in v.text('en_tot'), f'{lv}/{nm}: Gesamtpegel ({v.text("en_tot")})')
        # manuelle Skala
        before = col(v, 'ec7_0')
        sel(v, 'en_pk_up'); v.tick(16, 3)
        check('Peak -1 dB' in v.text('en_pk_val') and 'manuell' in v.text('en_scale'), f'{lv}/{nm}: Peak +5 -> manuell ({v.text("en_pk_val")}, {v.text("en_scale")})')
        sel(v, 'en_rg_dn'); v.tick(16, 3)
        check('Bereich 25 dB' in v.text('en_rg_val'), f'{lv}/{nm}: Bereich -5 ({v.text("en_rg_val")})')
        check(col(v, 'ec7_0') != before, f'{lv}/{nm}: Zellfarbe folgt der Skala')
        for _ in range(30): sel(v, 'en_rg_dn'); sel(v, 'en_pk_dn')
        v.tick(16, 3)
        check('Bereich 10 dB' in v.text('en_rg_val') and 'Peak -60 dB' in v.text('en_pk_val'), f'{lv}/{nm}: Grenzen 10 dB / -60 dB ({v.text("en_rg_val")}, {v.text("en_pk_val")})')
        sel(v, 'en_auto'); v.tick(16, 3)
        check('Peak -6 dB' in v.text('en_pk_val') and 'EnergyVisualizer' in v.text('en_scale'), f'{lv}/{nm}: Auto -> zurück zur Plugin-Skala')
        # Status 2 / 0
        send_map(v, st=2); v.tick(16, 3)
        check('keine Daten' in v.text('en_sub'), f'{lv}/{nm}: Status 2 ({v.text("en_sub")})')
        v.midi(*sx(29, 0, 0, 64, 35, 0, 0)); v.tick(16, 3)
        check('seren.a 3D Energy' in v.text('en_sub') and v.text('en_peaklbl') == '' and not v.c['en_peak']['visible'], f'{lv}/{nm}: Status 0 leert die Karte')
        # Standardskala ohne Plugin
        send_map(v, src=0, pk=0, rg=35); v.tick(16, 3)
        check('Standard' in v.text('en_scale') and 'Peak +0 dB' in v.text('en_pk_val'), f'{lv}/{nm}: Standardskala 0 dB / 35 dB ({v.text("en_scale")})')
        # Wechsel zurück
        sel(v, 'mode_iem'); v.tick(16, 4)
        s = v.sent(); h18 = [x for x in s if x[:4] == [0xF0, 0x7D, 0x4F, 0x18]]
        check(not v.c['en_g']['visible'] and h18 and h18[-1][4:6] == [0, 0], f'{lv}/{nm}: zurück zu space -> Art 0, en_g aus ({h18[-1] if h18 else None})')
        sel(v, 'mode_fdn'); v.tick(16, 3)
        check(v.c['hall_g']['visible'] and not v.c['en_g']['visible'], f'{lv}/{nm}: FDN-Reiter zeigt wieder Hall-Anzeige')
        # Konfiguration: Reiter-Schalter
        sel(v, 'cfg_btn'); sel(v, 'cfg_page'); v.tick(16, 2)
        check('cfg_tab_en' in v.c and v.c['cfg_tab_en']['visible'], f'{lv}/{nm}: Konfig-Schalter für den Reiter energy')
        v.run("onReceiveNotify('btn','cfg_tab_en')"); v.run("onReceiveNotify('btn','cfg_close')"); v.tick(16, 4)
        check(not v.c['mode_en']['visible'], f'{lv}/{nm}: Reiter energy abschaltbar')
print('\nALL OK' if not fails else f'\n{fails} FAILED')
