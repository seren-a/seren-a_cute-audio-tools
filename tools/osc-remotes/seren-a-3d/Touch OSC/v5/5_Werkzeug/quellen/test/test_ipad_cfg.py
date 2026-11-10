"""IEM space (iPad): Kennzeichnung, Farben-Knopf, Config (Spurtypen, Skala), Theme."""
from view_harness import View
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
for lv in ('lua51', 'lua54'):
    v = View('../ipad/dist/seren-a_IEM-Space.tosc', lv)
    v.midi(*sx(4, text='REAPER'))
    for o, fl in enumerate([1, 1 | 16, 1 | 32, 1 | 64]):
        v.midi(*sx(1, o, text=['Vox', 'Verb', 'Bus', 'Keys'][o])); v.midi(*sx(3, o, fl))
    v.midi(*sx(2, 0, 127, 0, 0)); v.tick()
    check(v.c['r2_fx']['visible'] and v.c['r3_grp']['visible'] and v.text('r4_glyph') == '♪', f'{lv}: Kennzeichnung FX / Gruppe / MIDI')
    v.run("onReceiveNotify('btn','col_btn')"); v.tick()
    c = v.c['r1_chip']['color']
    check(c['r'] > 0.99 and c['g'] < 0.01 and v.text('col_btn_lbl') == 'spurfarben', f'{lv}: Knopf farben -> Spurfarben')
    for b in ('cfg_btn', 'cfg_sh_fx', 'cfg_sc_lu', 'cfg_close'): v.run(f"onReceiveNotify('btn','{b}')")
    v.tick()
    check(not v.c['d2']['visible'] and 'LU' in v.text('cfg_info'), f'{lv}: Config: FX aus, Skala LU')
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_th_nuendo')"); v.tick()
    check(abs(v.g.root.color.r - 0.11) < 0.01, f'{lv}: Theme Nuendo dark')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
