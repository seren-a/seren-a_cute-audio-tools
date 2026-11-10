"""v2 (osc variant): native OSC messages on the controls + the remaining script logic."""
import os, importlib
lua = importlib.import_module("lupa." + os.environ.get("LUA", "lua51"))
import build
MOCK = open('tosc_mock.lua').read()
doc = build.build('osc')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1

# ---------- structure: the messages TouchOSC sends/receives by itself ----------
def msgs(name):
    c = doc.find(name)
    out = []
    for m in c.messages:
        path = ''.join(p.value for p in m.path)
        args = [(a.type, a.value, a.scale_min, a.scale_max) for a in m.arguments]
        out.append((path, m.send, m.receive, m.connections.index('1') + 1, args,
                    [(tr.var, str(tr.condition)) for tr in m.triggers]))
    return out
def has(name, path, send, recv, conn=1, arg=None):
    for m in msgs(name):
        if m[0] == path and m[1] == send and m[2] == recv and m[3] == conn and (arg is None or m[4] == arg):
            return True
    return False
check(has('tm_main', '/1/mastervolume', True, True, arg=[('VALUE', 'x', 0, 1)]), 'Main: /1/mastervolume send+receive on OSC 3')
check(has('tm_main_val', '/1/mastervolumeVal', False, True, arg=[('VALUE', 'text', 0, 1)]), 'Main dB label receives /1/mastervolumeVal as text')
check(has('tm_ph', '/1/volume4', True, True) and has('tm_ph_val', '/1/volume4Val', False, True), 'Phones: /1/volume4 + Val')
check(has('tm_phMute', '/1/mute/1/4', True, True), 'Phones mute toggle /1/mute/1/4')
check(has('tm_dim', '/1/mainDim', True, False) and has('tm_dim_led', '/1/mainDim', False, True), 'DIM: send button over LED (RME pattern)')
for i in range(1, 5):
    row = 9 - i
    ok = has(f'snap{i}', f'/3/snapshots/{row}/1', True, False) and has(f'snap{i}_led', f'/3/snapshots/{row}/1', False, True)
    back = [m for m in msgs(f'snap{i}') if m[0] == '/1']
    check(ok and back and back[0][5] == [('x', 'FALL')], f'Snapshot {i}: /3/snapshots/{row}/1, back to /1 on release')
for n, p in (('mt_main_L', '/1/level1Left'), ('mt_main_R', '/1/level1Right'), ('mt_ph_L', '/1/level4Left'), ('mt_ph_R', '/1/level4Right')):
    check(has(n, p, False, True) and doc.find(n).get('interactive') is False, f'meter {n} <- {p}')
sync = [m[0] for m in msgs('tm_sync')]
check(sync == ['/1', '/1/busOutput', '/setBankStart'], f'SYNC: {sync}')
eqm = msgs('tm_eqMain'); eqp = msgs('tm_eqPh')
check([m[0] for m in eqm] == ['/2', '/2/busOutput', '/setBankStart'] and eqm[2][4] == [('CONSTANT', '0', 0, 1)]
      and eqp[2][4] == [('CONSTANT', '6', 0, 1)], 'EQ buttons select page 2, output bus, channel 0 / 6')
for b in (1, 3):
    check(has(f'eq_type{b}', f'/2/eqType{b}Val', False, True), f'EQ band {b} type label')
for b in (1, 2, 3):
    check(has(f'eq_freq{b}', f'/2/eqFreq{b}Val', False, True) and has(f'eq_gain{b}', f'/2/eqGain{b}Val', False, True)
          and has(f'eq_q{b}', f'/2/eqQ{b}Val', False, True), f'EQ band {b} freq/gain/Q labels')
check(has('eq_close', '/1', True, False), 'EQ close returns TotalMix to page 1')
check(has('p2_el', '/StereoEncoder/elevation', True, True, conn=2, arg=[('VALUE', 'x', -90, 90)]), 'IEM elevation fader: own message, -90..90, OSC 2')
check(has('p2_pitch', '/SceneRotator/pitch', True, True, conn=3), 'IEM pitch fader: OSC 3')
check(has('p3_wid', '/StereoEncoder/width', True, True, conn=2, arg=[('VALUE', 'x', -180, 180)]), 'IEM width knob')
check(not doc.find('p2_encCircle').messages, 'circles stay script-only (maths)')
used = {m[3] for c in doc.walk() for m in msgs(c.get('name')) } if False else set()
for c in doc.walk():
    for m in c.messages:
        used.add(m.connections.index('1') + 1)
check(used == {1, 2, 3, 4}, f'OSC 1 TotalMix, 2 Encoder, 3 Rotator, 4 MultiEncoder ({sorted(used)})')
bad = [c.get('name') for c in doc.walk() for m in c.messages if m.send and m.receive and c.get('interactive') is False]
check(not bad, 'no non-interactive control sends')

# ---------- script logic against the mock ----------
L = lua.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
L.execute(MOCK)
for c in doc.walk():
    n = c.get("name")
    if n:
        f = c.frame
        g.makeControl(n, c.control_type.value, f.x, f.y, f.w, f.h, c.get("visible", True))
L.execute('function init() end function update() end function onReceiveMIDI() end function onReceiveOSC() end function onReceiveNotify() end'); L.execute(open(__import__('os').path.join(__import__('os').path.dirname(__import__('os').path.abspath(__file__)), 'tosc_strict.lua')).read()); L.execute(doc.root.get("script"))
ctrls = g.controls; run = L.execute
def sent():
    out = []
    for i in range(1, len(g.sent) + 1):
        m = g.sent[i]
        if m.kind == 'osc': out.append(('osc', m.conn, m.path, [m.args[j] for j in range(1, len(m.args) + 1)]))
        else: out.append(('midi', [m.bytes[j] for j in range(1, 4)]))
    run("sent = {}"); return out
def text(n): return ctrls[n]['values']['text']
def tick(ms=16, n=1):
    for _ in range(n): run(f"clock = clock + {ms}; update()")
def tm(path, v, tag='f'):
    vv = f"'{v}'" if tag == 's' else str(v)
    run(f"onReceiveOSC({{'{path}', {{{{tag='{tag}', value={vv}}}}}}}, {{true,false,false}})")

run("init()")
tick(600, 2)
check(sent() == [('osc', 1, '/1', []), ('osc', 1, '/1/busOutput', [1]), ('osc', 1, '/setBankStart', [0])], 'start sync on OSC 1')

# IEM fader with its own message: script must not send, only update text
run("local c = controls.p2_el; c.values.touch = true; c.values.x = 1.0; onReceiveNotify('ui','p2_el'); c.values.touch = false")
check(sent() == [] and text('p2_el_val') == '+90.0°', 'native fader: no script send, text updated')
run("controls.p3_az.values.x = 0.25; onReceiveNotify('fb','p3_az')")
check(text('p3_az_val') == '-90.0°' and text('p2_encCircle_val') == '-90.0°', 'value from plugin (fb) updates both texts')
mk = ctrls['p2_encMark']['frame']; cf = ctrls['p2_encCircle']['frame']
check(mk['x'] + mk['w'] / 2 > cf['x'] + cf['w'] * 0.9, 'and moves the circle marker (right = -90)')
# circle: script sends, does not set native knob x (no double send)
x_before = ctrls['p3_az']['values']['x']
run("local c = controls.p2_encCircle; c.values.touch = true; c.values.x = 0.0; c.values.y = 0.5; onReceiveNotify('ui','p2_encCircle'); c.values.touch = false")
s = sent()
check(s == [('osc', 2, '/StereoEncoder/azimuth', [90])] and ctrls['p3_az']['values']['x'] == x_before, f'circle sends azimuth once ({s})')
# MultiPanner unchanged
run("local c = controls.p1_pad1; c.values.touch = true; c.values.x = 0.25; c.values.y = 0.75; onReceiveNotify('ui','p1_pad1'); c.values.touch = false")
s = sent()
check(len(s) == 2 and s[0][1][0] == 0xE0 and s[1][1][0] == 0xE1, 'MultiPanner pad -> pitch bend ch 1/2')
run("onReceiveNotify('fb','p1_pad1')")
check(sent() == [], 'pad feedback does not re-send')

# meters: native fader values -> peak hold + dB text
run("controls.mt_main_L.values.x = 0.5; controls.mt_main_R.values.x = 1.0; controls.mt_ph_L.values.x = 0.1")
tick(16, 3)
check(text('mt_main_peak') == '0.0' and abs(float(text('mt_ph_peak')) + 20) < 0.1, f"peak text {text('mt_main_peak')} / {text('mt_ph_peak')}")
h = ctrls['mt_main_R_hold']['frame']; f = ctrls['mt_main_R']['frame']
check(abs(h['y'] - (f['y'] - 1)) < 1, 'hold line at the top for 0 dBFS')
run("controls.mt_main_R.values.x = 0.2"); tick(16, 10)
check(abs(ctrls['mt_main_R_hold']['frame']['y'] - (f['y'] - 1)) < 1, 'hold stays (1.5 s)')
tick(100, 30)
check(ctrls['mt_main_R_hold']['frame']['y'] > f['y'] + 10, 'hold falls back after hold time')

# snapshots: LED feedback from TotalMix, blink after a change
tm('/3/snapshots/7/1', 1.0)
check(ctrls['snap2_led']['color']['g'] > 0.6, 'snapshot 2 LED bright')
tick(500, 7)
tm('/1/volume4', 0.5); tm('/1/volume4', 0.6)
greens = set()
for _ in range(6):
    tick(200); greens.add(round(ctrls['snap2_led']['color']['g'], 2))
check(len(greens) == 2, f'blinks after a change ({greens})')
tm('/3/snapshots/6/1', 1.0); tick(500)
check(ctrls['snap2_led']['color']['g'] > 0.6, 'blink reset when another snapshot loads')

# EQ overlay + curve
run("onReceiveNotify('btn','tm_eqPh')")
check(ctrls['eq_overlay']['visible'] is True and text('eq_title') == 'EQ · PHONES', 'EQ opens on PHONES')
for p, v, tg in (('/2/eqEnable', 1.0, 'f'), ('/2/eqType1Val', 'Low Shelf', 's'), ('/2/eqFreq1Val', '120', 's'),
                 ('/2/eqGain1Val', '+6.0', 's'), ('/2/eqQ1Val', '0.7', 's'), ('/2/lowcutEnable', 1.0, 'f'),
                 ('/2/lowcutFreqVal', '40', 's'), ('/2/lowcutGradeVal', '12', 's')):
    tm(p, v, tg)
tick()
mid = ctrls['eq_bg']['frame']['y'] + ctrls['eq_bg']['frame']['h'] / 2
b1 = ctrls['eq_b1']['frame']; b8 = ctrls['eq_b8']['frame']
check(b1['y'] >= mid - 0.5 and b1['h'] > 20, 'low cut pulls the lowest bar down')
check(b8['y'] < mid - 20, 'low shelf boost visible')
run("onReceiveNotify('btn','eq_close')")
check(ctrls['eq_overlay']['visible'] is False, 'EQ closes')
check(not [m for m in sent() if m[0] == 'osc' and m[1] != 2], 'no extra OSC from the script for TotalMix controls')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
