"""v8.22.8: Standard je Reiter, einmalige Übernahme bei älteren Voreinstellungen, Knopf „Standard je Reiter laden“, Lite-Fassungen."""
import sys
from view_harness import View
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=b''): return [0xF0, 0x7D, 0x4F, cmd, *d, *text, 0xF7]
FULL = [('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc'), ('HD', '../monitor/dist/seren-a_IEM-Monitor_HD.tosc'), ('iPad', '../ipad/dist/seren-a_IEM-Space.tosc')]
LITE = [('Monitor Lite', '../monitor/dist/seren-a_IEM-Monitor_Lite.tosc'), ('HD Lite', '../monitor/dist/seren-a_IEM-Monitor_HD_Lite.tosc'), ('iPad Lite', '../ipad/dist/seren-a_IEM-Space_Lite.tosc')]
def state(v): return v.run("local t = {} for k, x in pairs(LOOK_DEFAULTS.tabs) do t[#t+1] = k .. '=' .. tostring(x) end table.sort(t) return table.concat(t, ',')")
for nm, f in FULL + LITE:
    lite = 'Lite' in nm
    v = View(f, defaults=True)
    v.midi(*sx(4, text=b'REAPER')); v.tick(16, 3)
    vis = lambda n: n in v.c and v.c[n]['visible']
    check(not vis('mode_me') and not vis('mode_mp') and vis('mode_iem') and vis('mode_room'), f'{nm}: Standard: multi/panner aus, space/room an')
    check(('mode_fdn' in v.c) != lite and ('en_g' in v.c) != lite, f'{nm}: Hall/Energie {"fehlen" if lite else "vorhanden"}')
    if lite: check(not vis('mode_fdn') and not vis('mode_en'), f'{nm}: keine Hall-/Energie-Reiter sichtbar')
    sh = v.run("return tostring(lookRef().showBy.iem.fx) .. tostring(lookRef().showBy.iem.group) .. tostring(lookRef().showBy.en.audio)")
    check(sh == 'falsetruefalse', f'{nm}: space ohne FX, mit Ordnern; Energie ohne Audio ({sh})')
    vid = 0 if 'iPad' in nm else 1
    def fresh(txt):
        w = View(f, defaults=True); w.midi(*sx(4, text=b'REAPER')); w.tick(16, 2)
        w.run("lookRef().showBy.iem.fx = true; lookRef().tabs.me = true")
        w.midi(*sx(20, vid, text=txt)); w.tick(16, 3)
        return w.run("return lookRef().theme .. ',' .. tostring(lookRef().showBy.iem.fx) .. ',' .. tostring(lookRef().tabs.me)")
    r = fresh(b'th=cute;tabs=15;sh_iem=31')
    check(r == 'cute,false,false', f'{nm}: alte Voreinstellung: Palette bleibt, Reiter-Standards übernommen ({r})')
    r = fresh(b'dv=2;th=girly;tabs=15;sh_iem=31')
    check(r == 'girly,true,true', f'{nm}: neue Voreinstellung (dv=2) bleibt wie gespeichert ({r})')
    v.run("lookRef().showBy.iem.fx = true; lookRef().tabs.me = true; lookRef().theme = 'girly'")
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_page')"); v.run("onReceiveNotify('btn','cfg_defaults')"); v.run("onReceiveNotify('btn','cfg_close')"); v.tick(16, 3)
    r = v.run("return lookRef().theme .. ',' .. tostring(lookRef().showBy.iem.fx) .. ',' .. tostring(lookRef().tabs.me)")
    check(r == 'girly,false,false', f'{nm}: Knopf „Standard je Reiter“ ({r})')
    check('cfg_defaults' in v.c, f'{nm}: Knopf vorhanden')
    if lite:
        r = v.run("return tostring(lookRef().tabs.fdn) .. tostring(lookRef().tabs.en) .. tostring(lookRef().split.en)")
        check(r == 'falsefalsefalse', f'{nm}: Lite: Hall/Energie bleiben aus ({r})')
        check(not any(k.startswith('cfg_tab_fdn') or k.startswith('cfg_et_en') or k.startswith('cfg_sp_en') for k in v.c), f'{nm}: Lite: keine Hall/Energie-Tasten in der Config')
    if nm.startswith(('Monitor', 'HD')):
        v.sent(); v.run("onReceiveNotify('btn','mode_sp')"); v.tick(16, 4); out = v.sent()
        check(([0xF0, 0x7D, 0x4F, 0x18, 3, 0, 0xF7] in out) != lite, f'{nm}: Split {"ohne" if lite else "mit"} Energiedaten')
        n = sum(1 for i in range(1, 6) if vis(f'spq{i}_bg'))
        check(n == (2 if lite else 3), f'{nm}: Split zeigt space + room (+ Energie) ({n} Felder)')
        check(vis('spe_g') != lite, f'{nm}: Energie-Feld {"fehlt" if lite else "da"}')
print('FAILS', fails); sys.exit(1 if fails else 0)
