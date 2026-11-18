"""v8.22.2: SceneRotator-Spur in space, Config folgt der Palette, Nummer kontrastreich, Config schließen."""
import sys
from view_harness import View
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
for nm, f in (('Monitor', '../monitor/dist/seren-a_IEM-Monitor.tosc'), ('HD', '../monitor/dist/seren-a_IEM-Monitor_HD.tosc'), ('iPad', '../ipad/dist/seren-a_IEM-Space.tosc')):
    v = View(f)
    v.midi(*sx(4, text='REAPER'))
    v.midi(*sx(1, 0, text='3OA Bett')); v.midi(*sx(3, 0, 8))
    v.midi(*sx(1, 1, text='Vox')); v.midi(*sx(3, 1, 1))
    v.run("onReceiveNotify('btn','mode_iem')"); v.tick(16, 4)
    rows = v.run("local t={} for k,c in pairs(controls) do if k:match('^c%d+_name$') or k:match('^r%d+_name$') or k:match('^sel%d+_name$') then t[#t+1]=c.values.text end end return table.concat(t,'|')")
    check('3OA Bett' in (rows or '') and '· –' not in (rows or '').split('3OA Bett')[1][:4], f'{nm}: Rotator-Spur steht in space ({rows[:80]})')
    v.run("onReceiveNotify('btn','cfg_btn')"); v.tick(16, 2)
    check(v.c['cfg_overlay']['visible'], f'{nm}: Config offen')
    v.run("onReceiveNotify('btn','cfg_close')"); v.tick(16, 3)
    check(not v.c['cfg_overlay']['visible'], f'{nm}: Config schließt mit „fertig“')
print('FAILS', fails); sys.exit(1 if fails else 0)
