"""v8.20 Oberflächen: Hall-Reiter FDN / mcfx (cmd 24-27, 0x18), Kopfzeile mit 6 Reitern."""
import sys
from view_harness import View
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
TABS6 = ('mode_iem', 'mode_me', 'mode_mp', 'mode_room', 'mode_fdn', 'mode_mcfx')
HD_IPAD = TABS6 + ('log_btn', 'col_btn', 'cfg_btn', 'n32_btn')
HD_MON = TABS6 + ('lay_16', 'lay_32v', 'lay_32h', 'lay_32r', 'lay_64', 'pano_btn', 'col_btn', 'cfg_btn', 'log_btn')
SUITES = (('iPad', '../ipad/dist/seren-a_IEM-Space.tosc', 16, 'r', 'hc', HD_IPAD, 'src'),)
if len(sys.argv) > 1 and sys.argv[1] == 'all':
    SUITES += (('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc', 16, 'c', 'hc', HD_MON, 'src_lbl'),
               ('MonitorHD', '../monitor/dist/seren-a_IEM-Monitor_HD.tosc', 16, 'c', 'hc', HD_MON, 'src_lbl'))
def sel(v, name): v.run(f"onReceiveNotify('btn','{name}')")
for lv in ('lua51', 'lua54'):
    for (nm, tosc, nslot, rowp, hp, hdr, srcn) in SUITES:
        v = View(tosc, lv)
        v.midi(*sx(4, text='REAPER')); v.tick(16, 3); v.sent()
        check(not v.c['hall_g']['visible'], f'{lv}/{nm}: Hall-Anzeige zunächst aus')
        sel(v, 'mode_fdn'); v.tick(16, 3)
        s = v.sent()
        h18 = [x for x in s if x[:4] == [0xF0, 0x7D, 0x4F, 0x18]]
        check(h18 and h18[-1][4:6] == [1, 0], f'{lv}/{nm}: FDN-Reiter meldet Art 1, Instanz 0 an die DAW ({h18[-1] if h18 else None})')
        check(not [x for x in s if x[:4] == [0xF0, 0x7D, 0x4F, 0x0B]], f'{lv}/{nm}: Hall-Reiter ändert den Spurfilter der DAW nicht')
        check(v.c['hall_g']['visible'] and not v.c['det_g']['visible'] if nm == 'iPad' else v.c['hall_g']['visible'], f'{lv}/{nm}: Hall-Anzeige sichtbar')
        # DAW answers: names = source tracks, sends, header, preset, total
        for o, n in enumerate(('Vox', 'Gtr', 'Keys')):
            v.midi(*sx(1, o, text=n)); v.midi(*sx(17, o, 0, o + 1))
        v.midi(*sx(26, 0, 106, 0)); v.midi(*sx(26, 1, 100, 0)); v.midi(*sx(26, 2, 90, 1))
        v.midi(*sx(24, 1, 0, 2, text='FDN Hall')); v.midi(*sx(27, text='Church')); v.midi(*sx(25, 100))
        v.midi(0xBE, 0, 100); v.midi(0xBE, 1, 60); v.midi(0xBE, 2, 0)
        v.tick(16, 30)
        check(v.text('hall_title') == '✧ FDN-Reverb ✧', f'{lv}/{nm}: Titel ({v.text("hall_title")!r})')
        check('FDN Hall' in v.text('hall_sub') and 'Church' in v.text('hall_sub'), f'{lv}/{nm}: Untertitel mit Spurname + Preset ({v.text("hall_sub")!r})')
        check(v.c['hall_i1']['visible'] and v.c['hall_i2']['visible'] and not v.c['hall_i3']['visible'], f'{lv}/{nm}: zwei Instanz-Chips bei 2 Instanzen')
        check(v.text('hall_cnt') == '3 Sends · 1 stumm', f'{lv}/{nm}: Zählzeile ({v.text("hall_cnt")!r})')
        check(v.text('hc1_n') == 'Vox' and v.text('hc3_n') == 'Keys', f'{lv}/{nm}: Spaltennamen')
        check(v.text('hc1_d') == '+0' or v.text('hc1_d') == '-0' or v.text('hc1_d').lstrip('+-') == '0', f'{lv}/{nm}: Send 0 dB ({v.text("hc1_d")!r})')
        check(v.text('hc3_d') == 'stumm', f'{lv}/{nm}: gemuteter Send ({v.text("hc3_d")!r})')
        check(v.c['hc1_l']['frame']['h'] > v.c['hc2_l']['frame']['h'] > 2, f'{lv}/{nm}: Pegelsäulen folgen dem Pegel ({v.c["hc1_l"]["frame"]["h"]:.0f} > {v.c["hc2_l"]["frame"]["h"]:.0f})')
        check(v.c['hc1_s']['frame']['h'] > v.c['hc3_s']['frame']['h'] and v.c['hc4_n']['visible'] is False, f'{lv}/{nm}: Send-Fader-Säule, leere Plätze aus')
        check(v.c['hall_tot']['frame']['w'] > 100 and 'dB' in v.text('hall_db'), f'{lv}/{nm}: Gesamtpegel ({v.text("hall_db")!r}, {v.c["hall_tot"]["frame"]["w"]:.0f})')
        check(v.text(f'{rowp}1_val').startswith('Send') or 'Send' in v.text(f'{rowp}1_val'), f'{lv}/{nm}: Liste zeigt Send-dB ({v.text(rowp + "1_val")!r})')
        check(v.c['d1']['visible'] is False and v.c['top_xy']['visible'] is False, f'{lv}/{nm}: keine Punkte/Zieh-Fläche im Hall-Reiter')
        # second instance
        v.sent(); sel(v, 'hall_i2'); v.tick(16, 3)
        h18 = [x for x in v.sent() if x[:4] == [0xF0, 0x7D, 0x4F, 0x18]]
        check(h18 and h18[-1][4:6] == [1, 1], f'{lv}/{nm}: Instanz 2 gewählt -> 0x18 1 1 ({h18[-1] if h18 else None})')
        # mcfx tab
        sel(v, 'mode_mcfx'); v.tick(16, 3)
        h18 = [x for x in v.sent() if x[:4] == [0xF0, 0x7D, 0x4F, 0x18]]
        check(h18 and h18[-1][4] == 2, f'{lv}/{nm}: mcfx-Reiter = Art 2 ({h18[-1] if h18 else None})')
        check(v.text('hall_title') == '✧ mcfx-Convolver ✧', f'{lv}/{nm}: mcfx-Titel')
        # back to tracks
        sel(v, 'mode_iem'); v.tick(16, 3)
        s = v.sent()
        h18 = [x for x in s if x[:4] == [0xF0, 0x7D, 0x4F, 0x18]]
        check(h18 and h18[-1][4:6] == [0, 0], f'{lv}/{nm}: zurück zu Spuren -> 0x18 0 0 ({h18[-1] if h18 else None})')
        check(not v.c['hall_g']['visible'], f'{lv}/{nm}: Hall-Anzeige wieder aus')
        # header layout: all six tabs + log/col/cfg/32 + DAW label fit before the bank buttons
        xs = [(v.c[n]['frame']['x'], v.c[n]['frame']['w']) for n in hdr]
        ok = all(xs[i][0] + xs[i][1] <= xs[i + 1][0] for i in range(len(xs) - 1))
        sr = v.c[srcn]['frame']
        srok = (sr['x'] >= xs[-1][0] + xs[-1][1] and sr['x'] + sr['w'] <= v.c['bank_prev']['frame']['x']) if nm == 'iPad' else xs[-1][0] + xs[-1][1] <= v.c['bank_prev']['frame']['x']
        check(ok and srok, f'{lv}/{nm}: Kopfzeile ohne Überlappung (src endet bei {sr["x"] + sr["w"]:.0f}, Bank ab {v.c["bank_prev"]["frame"]["x"]:.0f})')
        # hide the FDN tab (config page 2) -> the rest moves left
        x_before = v.c['mode_mcfx']['frame']['x']
        sel(v, 'cfg_btn'); sel(v, 'cfg_page'); sel(v, 'cfg_tab_fdn'); v.tick(16, 3)
        check(not v.c['mode_fdn']['visible'] and v.c['mode_mcfx']['frame']['x'] < x_before, f'{lv}/{nm}: Reiter FDN ausgeblendet, Rest rückt auf')
        # config state keeps the hall tabs
        v.sent(); v.tick(1200, 6)
        vs = [x for x in v.sent() if x[:4] == [0xF0, 0x7D, 0x4F, 0x0E]]
        st = ''.join(chr(c) for c in vs[-1][5:-1]) if vs else ''
        check('tabh=2' in st and 'mode=iem' in st, f'{lv}/{nm}: Ansicht in Reaper merkt Hall-Reiter (tabh=2, mode=iem) ({st!r})')
print('\nALL OK' if not fails else f'\n{fails} FAILED'); sys.exit(1 if fails else 0)
