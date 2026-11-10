"""Nuendo variant: root.lua (iemVia='midi') against the TouchOSC mock, plus the MIDI produced by
serena_TouchOSC3D.js in the MIDI Remote mock (end to end, both directions)."""
import os, importlib, json, sys
lua51 = importlib.import_module("lupa." + os.environ.get("LUA", "lua51"))
import build
MOCK = open('tosc_mock.lua').read()
doc = build.build('nuendo')
L = lua51.LuaRuntime(unpack_returned_tuples=True)
g = L.globals()
L.execute(MOCK)
L.execute("""function sendMIDI(m, conns) local b = {} for i = 1, #m do b[i] = m[i] end
  sent[#sent+1] = {kind='midi', bytes=b} end""")
for c in doc.walk():
    n = c.get("name")
    if n:
        f = c.frame
        g.makeControl(n, c.control_type.value, f.x, f.y, f.w, f.h, c.get("visible", True))
L.execute(doc.root.get("script"))
ctrls = g.controls
run = L.execute
def sent():
    out = [list(g.sent[i].bytes.values()) for i in range(1, len(g.sent) + 1) if g.sent[i].kind == 'midi']
    run("sent = {}"); return out
def text(n): return ctrls[n]["values"]["text"]
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def midi_in(*b):
    run("onReceiveMIDI({" + ",".join(str(x) for x in b) + "}, {true})")

nu = json.load(open(sys.argv[1]))
run("init()")
check("iemVia = 'midi'" in doc.root.get("script"), "variant script uses the MIDI path")
check('nu_track' in ctrls and 'nu_prev' in ctrls and 'nu_next' in ctrls, "track box in the layout")

# --- what the Nuendo script expects (from its bindings) ---
b14 = {b['desc']['cc']: b for b in nu['bindings'] if b['desc']['type'] == 'cc14' and b['desc']['ch'] == 15}
check(sorted(b14) == [1, 2, 3, 4, 5, 6, 7] and all(b['desc']['ch'] == 15 and b['port'].get('out') for b in b14.values()),
      "Nuendo: 14-bit CC 1-7 on channel 16, with feedback")
hosts = {b['surface']: b['host'] for b in nu['valueBindings']}
check(hosts['knob0'] == 'slot0.param0' and hosts['knob3'] == 'slot0.param3' and hosts['knob4'] == 'slot1.param0'
      and hosts['knob6'] == 'slot1.param2', "Nuendo: knobs -> insert slot 1 params 1-4, slot 2 params 1-3")
pb = [b['desc']['ch'] for b in nu['bindings'] if b['desc']['type'] == 'pb']
check(pb == list(range(12)), "Nuendo: 12 pitch-bend knobs left for the MultiPanner")
notes = {b['desc']['note']: b['label'] for b in nu['bindings'] if b['desc']['type'] == 'note' and b['desc']['ch'] == 15}
acts = {a['surface']: a['action'] for a in nu['actionBindings']}
check(acts[notes[0]] == 'prevTrack' and acts[notes[1]] == 'nextTrack', "Nuendo: notes 0/1 = prev/next track")
check(nu['detection'][0]['rules'] == ['in~TouchOSC Bridge', 'out~TouchOSC Bridge'], "detection on TouchOSC Bridge")

# --- TouchOSC -> Nuendo ---
run("""local c = controls.p2_encCircle; c.values.touch = true; c.values.x = 0.0; c.values.y = 0.5
       onReceiveNotify('ui','p2_encCircle'); c.values.touch = false""")
s = sent()
v14 = s[0][2] * 128 + s[1][2]
check(s[0][:2] == [0xBF, 1] and s[1][:2] == [0xBF, 33] and abs(v14 / 16383 - 0.75) < 1e-3, f"azimuth +90 -> CC1/33 = 0.75 of +-180 ({s})")
check(all(m[1] - (32 if m[1] > 32 else 0) in b14 for m in s), "only CCs the Nuendo script binds")
run("""local c = controls.p2_el; c.values.touch = true; c.values.x = 1.0; onReceiveNotify('ui','p2_el'); c.values.touch = false""")
s = sent()
v14 = s[0][2] * 128 + s[1][2]
check(s[0][1] == 2 and s[1][1] == 34 and abs(v14 / 16383 - 0.75) < 1e-3, f"elevation +90 -> 0.75 of the plugin's +-180 ({s})")
run("""local c = controls.p3_wid; c.values.touch = true; c.values.x = 1.0; onReceiveNotify('ui','p3_wid'); c.values.touch = false""")
s = sent(); v14 = s[0][2] * 128 + s[1][2]
check(s[0][1] == 4 and abs(v14 / 16383 - 0.75) < 1e-3, "width +180 -> 0.75 of +-360")
check(len([1 for m in s if m[0] & 0xF0 == 0xB0 and m[0] != 0xBF]) == 0, "nothing on other channels")
run("onReceiveNotify('btn','nu_next')")
check(sent() == [[0x9F, 1, 127], [0x9F, 1, 0]], "next track -> note 1 on ch 16")
run("onReceiveNotify('btn','nu_prev')")
check(sent()[0] == [0x9F, 0, 127], "prev track -> note 0")

# --- Nuendo -> TouchOSC: 14-bit feedback (track change) ---
v = round((-30 + 180) / 360 * 16383)                   # azimuth -30
midi_in(0xBF, 1, v // 128); midi_in(0xBF, 33, v % 128)
check(abs(ctrls['p3_az']['values']['x'] - (-30 + 180) / 360) < 1e-3, "azimuth feedback moves the page-3 knob")
mk = ctrls['p2_encMark']['frame']; cf = ctrls['p2_encCircle']['frame']
check(mk['x'] + mk['w'] / 2 > cf['x'] + cf['w'] / 2, "marker moved right of centre for -30")
check(text('p2_encCircle_val') == '-30.0°', "local value text until Nuendo's arrives: " + text('p2_encCircle_val'))
check(len(sent()) == 0, "feedback is not echoed back")

# --- Nuendo -> TouchOSC: SysEx text from the real script ---
for msg in nu['midi']:
    assert msg[0] == 0xF0 and msg[-1] == 0xF7 and all(0 <= x <= 127 for x in msg[1:-1]), msg
    run("onReceiveMIDI({" + ",".join(map(str, msg)) + "}, {true})")
check(sum(1 for m in nu['midi'] if m[3] == 0) == 1, "unchanged track name sent once")
check(text('nu_track') == 'Vox Lead', "track name: " + text('nu_track'))
check(text('p2_encTitle') == 'StereoEncoder · Azimuth Angle' and text('p2_rotTitle') == 'SceneRotator · Yaw Angle',
      "headers: " + text('p2_encTitle') + " | " + text('p2_rotTitle'))
check(text('p2_el_title') == 'Elevation Angle' and text('p3_wid_title') == 'Stereo Width', "parameter names from Nuendo")
check(text('p2_encCircle_val') == '45.0 °' or text('p2_encCircle_val') == '45.0°', "Nuendo's value text: " + text('p2_encCircle_val'))
check(text('p2_el_val') == '-12.5 °' or text('p2_el_val') == '-12.5°', "elevation text: " + text('p2_el_val'))
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
