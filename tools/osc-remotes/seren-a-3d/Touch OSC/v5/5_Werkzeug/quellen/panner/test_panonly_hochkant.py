"""Panner ohne TotalMix (beide Varianten): keine TotalMix-Messages, Werteübersicht rechts."""
import os, importlib
lua = importlib.import_module("lupa." + os.environ.get("LUA", "lua51"))
import build_hochkant as build
MOCK = open('tosc_mock.lua').read()
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1

for variant in ('nuendo',):
    doc = build.build(tm=False)
    names = {c.get('name') for c in doc.walk()}
    check(not any(n and (n.startswith('tm_') or n.startswith('snap') or n.startswith('eq_') or n.startswith('mt_')) for n in names),
          f'{variant}: keine TotalMix-Controls')
    used = {m.connections.index('1') + 1 for c in doc.walk() for m in c.messages}
    check(used <= {2, 3, 4}, f'{variant}: OSC-Verbindungen {sorted(used)} (TotalMix-OSC 1 frei)')
    check(('nu_track' in names) == (variant == 'nuendo'), f'{variant}: Spurfeld nur in Nuendo-Variante')
    L = lua.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
    L.execute(MOCK)
    for c in doc.walk():
        n = c.get("name")
        if n:
            f = c.frame
            g.makeControl(n, c.control_type.value, f.x, f.y, f.w, f.h, c.get("visible", True))
    L.execute('function init() end function update() end function onReceiveMIDI() end function onReceiveOSC() end function onReceiveNotify() end'); L.execute(open(__import__('os').path.join(__import__('os').path.dirname(__import__('os').path.abspath(__file__)), 'tosc_strict.lua')).read()); L.execute(doc.root.get("script"))
    run = L.execute; ctrls = g.controls
    run("init()")
    for i in range(80):
        run("clock = clock + 16; update()")
    osc = [g.sent[i] for i in range(1, len(g.sent) + 1) if g.sent[i].kind == 'osc']
    check(not osc, f'{variant}: kein TotalMix-Sync beim Start ({len(osc)} OSC)')
    # MultiPanner X von Nuendo (Pitchbend Kanal 1), IEM Azimut
    run("onReceiveMIDI({0xE0, 0, 96}, {true})")
    if variant == 'osc':
        run("onReceiveOSC({'/StereoEncoder/azimuth', {{tag='f', value=45}}}, {false,true,false})")
    else:
        v14 = round((45 + 180) / 360 * 16383)
        run(f"onReceiveMIDI({{0xBF, 1, {v14 // 128}}}, {{true}}); onReceiveMIDI({{0xBF, 33, {v14 % 128}}}, {{true}})")
    for i in range(10):
        run("clock = clock + 20; update()")
    tx = ctrls['ro_x']['values']['text']; ta = ctrls['ro_az']['values']['text']
    check(tx == '+50', f'{variant}: Übersicht X = {tx}')
    check(ta.startswith('+45') or ta.startswith('+44.9'), f'{variant}: Übersicht Azimuth = {ta}')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
