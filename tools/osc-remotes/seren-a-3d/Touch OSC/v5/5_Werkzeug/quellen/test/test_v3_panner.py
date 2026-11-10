"""Panner v3: MULTI-Seite (OSC 4), MONITOR, Skript-Fassung gegen das Nuendo-v3-Skript (Mock)."""
import importlib, json, os, subprocess, sys
D = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(D, '..', 'panner'))
import build, build_hochkant
HOCH = os.environ.get('HOCHKANT') == '1'
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
MOCK = open(os.path.join(D, '..', 'panner', 'tosc_mock.lua')).read()
nu = json.loads(subprocess.check_output(['node', os.path.join(D, 'scenario_v3.js'), os.path.join(D, '..', 'nuendo', 'serena_TouchOSC3D.js')]))
for luav in ('lua51', 'lua54'):
    lua = importlib.import_module('lupa.' + luav)
    def load(variant, tm=False):
        doc = build_hochkant.build(tm) if (HOCH and variant == 'nuendo') else build.build(variant, tm)
        L = lua.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
        L.execute(MOCK)
        for c in doc.walk():
            n = c.get('name')
            if n:
                f = c.frame; g.makeControl(n, c.control_type.value, f.x, f.y, f.w, f.h, c.get('visible', True))
        L.execute('function init() end function update() end function onReceiveMIDI() end function onReceiveOSC() end function onReceiveNotify() end'); L.execute(open(__import__('os').path.join(__import__('os').path.dirname(__import__('os').path.abspath(__file__)), '..', 'panner', 'tosc_strict.lua')).read()); L.execute(doc.root.get('script')); L.execute('init()')
        return doc, L, g
    def sent(L, g):
        out = []
        for i in range(1, len(g.sent) + 1):
            m = g.sent[i]
            if m.kind == 'osc': out.append(('osc', m.conn, m.path, [m.args[j] for j in range(1, len(m.args) + 1)]))
            else: out.append(('midi', [m.bytes[j] for j in range(1, 4)]))
        L.execute('sent = {}'); return out
    # --- OSC-Fassung: MultiEncoder über OSC 4
    doc, L, g = load('osc')
    names = [c.get('tab_label') for c in doc.find('pager').children]
    check(names == ['MULTIPANNER', 'IEM', 'MP + IEM', 'MULTI (OSC)', 'MONITOR'], f'{luav}: Seiten OSC-Fassung {names}')
    m = [m for m in doc.find('p4_el').messages]
    check(len(m) == 1 and m[0].connections.index('1') + 1 == 4 and ''.join(p.value for p in m[0].path) == '/MultiEncoder/masterElevation',
          f'{luav}: Master-Elevation-Fader sendet selbst an OSC 4')
    L.execute("clock = clock + 2000; update()"); sent(L, g)
    L.execute("local c = controls.p4_encCircle; c.values.touch = true; c.values.x = 0.0; c.values.y = 0.5; onReceiveNotify('ui','p4_encCircle')")
    s = sent(L, g)
    check(s == [('osc', 4, '/MultiEncoder/masterAzimuth', [90.0])], f'{luav}: Kreis MULTI -> OSC 4 masterAzimuth +90 ({s})')
    L.execute("onReceiveOSC({'/MultiEncoder/masterElevation', {{tag='f', value=30}}}, {false,false,false,true})")
    L.execute("clock = clock + 300; update()")
    t = g.controls['mon_text']['values']['text']
    check(g.controls['p4_el_val']['values']['text'] == '+30.0°' and '← OSC 4 /MultiEncoder/masterElevation 30.0' in t and '→ Master Azimuth +90.0°' in t,
          f'{luav}: Monitor zeigt Ein- und Ausgang: {t[:90]!r}')
    # --- Skript-Fassung gegen Nuendo v3
    doc, L, g = load('nuendo')
    names = [c.get('tab_label') for c in doc.find('pager').children]
    check(names == ['MULTIPANNER', 'IEM', 'MP + IEM', 'MONITOR'], f'{luav}: Seiten Skript-Fassung {names}')
    for msg in nu['selOut']:
        L.execute('onReceiveMIDI({' + ','.join(map(str, msg)) + '}, {true})')
    for text in nu['log']:
        L.execute('onReceiveMIDI({' + ','.join(map(str, [0xF0, 0x7D, 0x4F, 8] + [ord(c) for c in text] + [0xF7])) + '}, {true})')
    L.execute("clock = clock + 300; update()")
    c = g.controls
    check(c['p2_encCircle_val']['values']['text'].startswith('+0.0') and c['p2_rotCircle_val']['values']['text'] == '12.5°',
          f"{luav}: Werte aus Nuendo (Master Azimuth 0, Yaw 12.5) {c['p2_encCircle_val']['values']['text']!r} {c['p2_rotCircle_val']['values']['text']!r}")
    if HOCH:   # hochkant: ein Feld (oben = Y +100 = vorn), Z als Fader
        sent(L, g)
        L.execute("local c = controls.p1_pad1; c.values.touch = true; c.values.x = 0.5; c.values.y = 1.0; onReceiveNotify('ui','p1_pad1')")
        L.execute("local c = controls.p1_k_z; c.values.touch = true; c.values.x = 0.75; onReceiveNotify('ui','p1_k_z')")
        s = [m for k, m in sent(L, g) if k == 'midi']
        check([0xE1, 127, 127] in s and [0xE2, 127, 95] in s and 'p1_pad2' not in g.controls,
              f'{luav}: hochkant: Feld oben = Y +100, Z-Fader -> Pitchbend Kanal 3 ({s})')
    t = c['mon_text']['values']['text']
    check('◆ Gewaehlt: Drums OH - Insert 5: MultiEncoder' in t, f'{luav}: Monitor zeigt die Erkennung aus Nuendo')
    sent(L, g)
    L.execute("local c = controls.p2_encCircle; c.values.touch = true; c.values.x = 0.0; c.values.y = 0.5; onReceiveNotify('ui','p2_encCircle')")
    L.execute("local c = controls.p2_rotCircle; c.values.touch = true; c.values.x = 1.0; c.values.y = 0.5; onReceiveNotify('ui','p2_rotCircle')")
    s = [m[1] for m in sent(L, g) if m[0] == 'midi']
    inb = {(b['ch'], b['cc']): b['label'] for b in nu['inBind'] if 'cc' in b}
    used = {(m[0] - 0xB0, m[1]) for m in s if m[1] < 32}
    check(used and all(u in inb for u in used) and {inb[u] for u in used} == {'In Pan az', 'In Pan yaw'},
          f'{luav}: Panner sendet genau auf die Eingänge des Nuendo-Skripts {sorted(used)}')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
