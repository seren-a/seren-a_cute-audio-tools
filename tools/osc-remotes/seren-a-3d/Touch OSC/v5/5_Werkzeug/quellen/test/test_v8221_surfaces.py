"""v8.22.1: Monitor ohne doppelte Ansicht nach Layoutwechsel (4x8), Hall-Liste erst nach Antwort der DAW, Zusatzzeile einzeilig."""
import random
from view_harness import View
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def sel(v, n): v.run(f"onReceiveNotify('btn','{n}')")
def feed(v):
    v.midi(*sx(4, text='REAPER'))
    for o, (n, f) in enumerate((('Vox', 1), ('Pan', 2), ('Both', 3), ('Room', 0))):
        v.midi(*sx(1, o, text=n)); v.midi(*sx(3, o, f)); v.midi(*sx(17, o, 0, o + 1))
    v.tick(16, 4)
names = [f'{p}{i}{s}' for p in ('circ', 'sq') for i in (1, 2, 3, 4) for s in ('', 's')]
modes = ['iem', 'me', 'mp', 'room', 'fdn', 'mcfx', 'en', 'sp']
acts = ['mode_' + m for m in modes] + ['pano_btn', 'lay_16', 'lay_32v', 'lay_32h', 'lay_32r', 'lay_64']
for lv in ('lua51', 'lua54'):
    for tosc in ('../monitor/dist/seren-a_IEM-Monitor.tosc', '../monitor/dist/seren-a_IEM-Monitor_HD.tosc'):
        v = View(tosc, lv); feed(v)
        random.seed(11); bad = []
        for it in range(25):
            seq = []
            for k in range(random.randint(3, 8)):
                a = random.choice(acts); seq.append(a); sel(v, a); v.tick(16, 3)
                x = [n for n in names if v.c[n]['visible']]
                if len([n for n in x if n.startswith('circ')]) > 1 or len([n for n in x if n.startswith('sq')]) > 1: bad.append((x, seq[:]))
        check(not bad, f'{lv}: nie zwei Kreise/Quadrate gleichzeitig ({bad[:1]})')
        sel(v, 'lay_32r'); sel(v, 'mode_iem'); v.tick(16, 3); sel(v, 'lay_16'); v.tick(16, 3)
        check((v.c['circ1']['visible'] or v.c['circ1s']['visible']) and not v.c['circ4']['visible'] and not v.c['circ4s']['visible'], f'{lv}: 4x8 -> 16: kein circ4')
    # Hall-Liste
    for tosc, n1, n2 in (('../ipad/dist/seren-a_IEM-Space.tosc', 'r1_name', 'r2_name'), ('../monitor/dist/seren-a_IEM-Monitor.tosc', 'c1', 'c2')):
        v = View(tosc, lv); feed(v)
        sel(v, 'mode_fdn'); v.tick(16, 4)
        check(not v.c[n1]['visible'], f'{lv}: FDN gewählt, DAW noch stumm: keine alte Liste')
        v.midi(*sx(24, 1, 0, 1, text='FDN')); v.midi(*sx(1, 0, text='Vox')); v.midi(*sx(1, 1, text='')); v.midi(*sx(1, 2, text='')); v.midi(*sx(1, 3, text='')); v.tick(16, 4)
        check(v.c[n1]['visible'] and not v.c[n2]['visible'], f'{lv}: nach Antwort der DAW nur der Send')
        sel(v, 'mode_iem'); v.tick(16, 3); sel(v, 'mode_fdn'); v.tick(16, 4)
        check(not v.c[n1]['visible'], f'{lv}: erneut gewählt: wieder erst nach Antwort')
    # Zusatzzeile
    v = View('../ipad/dist/seren-a_IEM-Space.tosc', lv); v.midi(*sx(4, text='REAPER'))
    v.midi(*sx(1, 0, text='Bus')); v.midi(*sx(3, 0, 33)); v.midi(*sx(17, 0, 0, 1)); v.midi(*sx(22, 0, 0, 3, 1)); v.tick(16, 3); sel(v, 'cfg_btn'); sel(v, 'cfg_page'); sel(v, 'cfg_xs_group_subs'); sel(v, 'cfg_xs_group_sends'); v.tick(16, 4)
    t = v.text('r1_xt'); check('\n' not in t and '3' in t and '1' in t, f'{lv}: Zusatzzeile einzeilig ({t!r})')
print('\nALL OK' if not fails else f'\n{fails} FAILED')
