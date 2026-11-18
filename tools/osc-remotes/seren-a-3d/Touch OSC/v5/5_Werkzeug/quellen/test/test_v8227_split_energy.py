"""v8.22.7: Energie als fünftes Feld der Split-Ansicht (Monitor 5:4 / HD)."""
import random, sys
from view_harness import View
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=b''): return [0xF0, 0x7D, 0x4F, cmd, *d, *text, 0xF7]
for nm, f in (('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc'), ('HD', '../monitor/dist/seren-a_IEM-Monitor_HD.tosc')):
    v = View(f)
    v.midi(*sx(4, text=b'REAPER'))
    for k in range(4): v.midi(*sx(1, k, text=b'Obj%d' % k)); v.midi(*sx(3, k, 1))
    v.sent(); v.run("onReceiveNotify('btn','mode_sp')"); v.tick(16, 4)
    out = v.sent()
    check([0xF0, 0x7D, 0x4F, 0x18, 3, 0, 0xF7] in out, f'{nm}: Split holt Energiedaten (18 3 0)')
    check(v.c['spe_g']['visible'], f'{nm}: Energie-Feld sichtbar')
    g = v.c['spe_g']['frame']; bg = [v.c[f'spq{i}_bg'] for i in range(1, 6)]
    check(abs(g['w'] / g['h'] - 2) < 0.02, f"{nm}: Karte 2:1 ({g['w']:.0f}×{g['h']:.0f})")
    others = [b['frame'] for b in bg[:4] if b['visible']]
    check(len(others) == 4 and all(o['y'] + o['h'] <= g['y'] for o in others), f'{nm}: vier Felder oben, Energie unten')
    v.midi(*sx(29, 1, 1, 64, 40, 3, 100, text=b'Master'))
    for r in range(12): v.midi(*sx(28, r, *[127 if (r == 5 and c == 12) else 30 for c in range(24)]))
    v.tick(120, 3)
    hot = v.c['se2_6']['color']; cold = v.c['se0_0']['color']
    check((hot['r'], hot['g'], hot['b']) != (cold['r'], cold['g'], cold['b']), f'{nm}: lautes Feld (2,6) anders gefärbt als ruhiges')
    check('Master' in v.c['spe_sub']['values']['text'], f"{nm}: Untertitel nennt die Quelle ({v.c['spe_sub']['values']['text']})")
    vis = sum(1 for k in range(1, 17) if v.c[f'd{k}']['visible'])
    check(vis >= 1, f'{nm}: Punkte im space-Feld weiter da ({vis})')
    # Energie in der Config aus -> Feld weg, Daten-Anfrage zurück auf Spuren
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_page')"); v.sent()
    v.run("onReceiveNotify('btn','cfg_sp_en')"); v.run("onReceiveNotify('btn','cfg_close')"); v.tick(16, 4)
    check(not v.c['spe_g']['visible'], f'{nm}: Energie aus -> Feld weg')
    check([0xF0, 0x7D, 0x4F, 0x18, 0, 0, 0xF7] in v.sent(), f'{nm}: Energie aus -> 18 0 0')
    # nur Energie
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_sp_en')")
    for m in ('iem', 'me', 'mp', 'room'): v.run(f"onReceiveNotify('btn','cfg_sp_{m}')")
    v.run("onReceiveNotify('btn','cfg_close')"); v.tick(16, 4)
    g = v.c['spe_g']['frame']
    check(v.c['spe_g']['visible'] and g['w'] > 600 and not v.c['spq2_bg']['visible'], f"{nm}: nur Energie -> ein großes Feld ({g['w']:.0f})")
print('FAILS', fails); sys.exit(1 if fails else 0)
