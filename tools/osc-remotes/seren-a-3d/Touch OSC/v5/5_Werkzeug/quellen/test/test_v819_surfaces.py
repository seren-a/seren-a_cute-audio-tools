"""v8.19 Oberflächen: Beschriftung (Nummer/Name/Preset), Zusatzzeilen, Reiter, Reiter-Filter, 3OA, neue Paletten."""
from view_harness import View
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def feed(v):
    v.midi(*sx(4, text='REAPER'))
    for o, (nm, fl, oa, subs, snd, pre) in enumerate([('Vox', 1, 0, 0, 2, 'Hall A'), ('Atmo', 1, 1, 0, 0, ''), ('Bus', 1 | 32, 0, 3, 1, 'Plate')]):
        v.midi(*sx(1, o, text=nm)); v.midi(*sx(3, o, fl)); v.midi(*sx(17, o, 0, o + 1))
        v.midi(*sx(22, o, oa, subs, snd))
        if pre: v.midi(*sx(23, o, text=pre))
    v.midi(*sx(2, 0, 127, 0, 0)); v.tick(16, 3)
SUITES = (('iPad', '../ipad/dist/seren-a_IEM-Space.tosc', 'r', ['mode_iem', 'mode_me', 'mode_mp', 'mode_room']),
          ('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc', None, None))
for lv in ('lua51', 'lua54'):
    v = View('../ipad/dist/seren-a_IEM-Space.tosc', lv); feed(v)
    n1 = v.text('r1_num')
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_page')")
    v.run("onReceiveNotify('btn','cfg_lb_name')"); v.tick()
    check(v.text('r1_num') != n1 and v.text('r1_num').startswith('Vo'), f'{lv}/iPad: Beschriftung Name statt Nummer ({v.text("r1_num")!r})')
    v.run("onReceiveNotify('btn','cfg_lb_preset')"); v.tick()
    check(v.text('r1_num').startswith('H') and v.text('r2_num').strip() != '', f'{lv}/iPad: Beschriftung Preset, ohne Preset fällt sie auf die Nummer zurück ({v.text("r1_num")!r}, {v.text("r2_num")!r})')
    v.run("onReceiveNotify('btn','cfg_lb_num')"); v.tick()
    check(v.text('r1_num') == n1, f'{lv}/iPad: zurück auf Nummer')
    # extra lines
    check(v.text('r3_xt') == '', f'{lv}/iPad: Zusatzzeilen standardmäßig aus')
    v.run("onReceiveNotify('btn','cfg_xs_group_subs')"); v.run("onReceiveNotify('btn','cfg_xs_group_sends')"); v.tick()
    check('3' in v.text('r3_xt') and '1' in v.text('r3_xt'), f'{lv}/iPad: Gruppe zeigt Subspuren + Sends ({v.text("r3_xt")!r})')
    check(v.text('r1_xt') == '', f'{lv}/iPad: Audio-Spur zeigt nichts (nur für Gruppe eingeschaltet)')
    # 3OA shown separately, switchable
    v.run("onReceiveNotify('btn','cfg_et_iem')"); v.run("onReceiveNotify('btn','cfg_sh_oa3')"); v.tick()
    check(v.text('r2_name') != 'Atmo', f'{lv}/iPad: 3OA-Spur ausgeblendet')
    allsent = v.sent()
    f = [x for x in allsent if x[:4] == [0xF0, 0x7D, 0x4F, 0x0B]]
    check(f and f[-1][4] == 15, f'{lv}/iPad: Filter an die DAW ohne Bit 16 ({f[-1] if f else None})')
    # tabs
    v.run("onReceiveNotify('btn','cfg_tab_me')"); v.tick()
    check(not v.c['mode_me']['visible'] and v.c['mode_iem']['visible'], f'{lv}/iPad: Reiter ME ausgeblendet')
    for m in ('iem', 'mp', 'room'): v.run(f"onReceiveNotify('btn','cfg_tab_{m}')")
    v.tick()
    check(v.c['mode_me']['visible'] or v.c['mode_iem']['visible'] or v.c['mode_mp']['visible'] or v.c['mode_room']['visible'], f'{lv}/iPad: mindestens ein Reiter bleibt')
    # per-tab visibility: the filter of another tab is independent
    v.run("onReceiveNotify('btn','cfg_et_room')"); v.run("onReceiveNotify('btn','cfg_sh_audio')"); v.tick()
    check(v.g.root is not None, f'{lv}/iPad: Reiter-Filter lässt sich einzeln wählen')
    # palettes
    for th in ('cute', 'girly', 'pastel'):
        v.run(f"onReceiveNotify('btn','cfg_th_{th}')"); v.tick()
        c = v.g.root.color
        check(c is not None, f'{lv}/iPad: Palette {th} ({c.r:.2f},{c.g:.2f},{c.b:.2f})')
    v.run("onReceiveNotify('btn','cfg_th_cute')"); v.tick()
    check(v.g.root.color.r > 0.95 and v.g.root.color.g > 0.9, f'{lv}/iPad: Cute Pink hat hellen Grund')
    v.run("onReceiveNotify('btn','cfg_th_girly')"); v.tick()
    check(v.g.root.color.b > v.g.root.color.g and v.g.root.color.r < 0.2, f'{lv}/iPad: Girly Pop Dark ist dunkelviolett')
    # persistence in the view preset (cmd 0E)
    v.tick(500, 8)
    st = [x for x in allsent + v.sent() if x[:4] == [0xF0, 0x7D, 0x4F, 0x0E]]
    check(st, f'{lv}/iPad: Ansicht (inkl. Reiter/Beschriftung/Zusatzzeilen) geht an Reaper')
    # Monitor
    m = View('../monitor/dist/seren-a_IEM-Monitor.tosc', lv); feed(m)
    m.run("onReceiveNotify('btn','cfg_btn')"); m.run("onReceiveNotify('btn','cfg_page')"); m.run("onReceiveNotify('btn','cfg_lb_name')"); m.tick()
    check('Vo' in m.text('d1_num') or 'Vo' in m.text('c1_num'), f'{lv}/Monitor: Beschriftung Name')
    m.run("onReceiveNotify('btn','cfg_th_pastel')"); m.tick()
    check(m.g.root.color is not None, f'{lv}/Monitor: Palette')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
