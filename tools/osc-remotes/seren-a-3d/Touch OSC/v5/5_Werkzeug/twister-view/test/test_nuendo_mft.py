"""serena_MFTView.js (MIDI Remote mock) -> Twister View (TouchOSC mock)."""
import json, os, sys
from view_harness import View
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..')); import mfs_parse
nu = json.load(open(sys.argv[1]))
view = View((os.environ.get('TOSC') or os.path.join(os.path.dirname(__file__), '..', 'dist', 'seren-a_Twister_View.tosc')))
encs = mfs_parse.parse(open('/root/.claude/uploads/1d4028fa-12da-5404-ac70-1ceecfe42680/0f3307c3-midi_fighter_2026_jan_vor_croissant.mfs', 'rb').read())[1]
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
knobs = [b for b in nu['bindings'] if b['label'].startswith('knob')]
check(len(knobs) == 64 and all(k['desc'] == {'type': 'cc', 'ch': e['encoder_midi_channel'] - 1, 'cc': e['encoder_midi_number']}
      for k, e in zip(knobs, encs)), '64 knobs = the CCs from the .mfs (bank 4 on 49-64)')
check(all(k['port'] == ({'in': 'in:Twister'} if 48 <= i < 64 else {'in': 'in:Twister', 'out': 'out:TouchOSC'}) for i, k in enumerate(knobs)),
      'input Twister, value feedback to the phone (bank 4: rings drawn by the script)')
check(all(k.get('relative') == 'binaryOffset' for k in knobs[48:64]) and not any(k.get('relative') for k in knobs[:48]), 'bank 4 relativ, Banks 1-3 absolut')
banks = [b for b in nu['bindings'] if b['label'].startswith('custom:bank')]
check([(b['desc']['ch'], b['desc']['cc']) for b in banks] == [(3, 0), (3, 1), (3, 2), (3, 3)], 'bank messages: channel 4, CC 0-3')
check(nu['detection'][0]['rules'] == ['in~Twister', 'out~TouchOSC Bridge'], 'detection: Twister in, TouchOSC Bridge out')
hosts = {b['surface']: b['host'] for b in nu['valueBindings']}
check('knob48' not in hosts and hosts.get('knob56') == 'trackQC0' and hosts.get('knob63') == 'trackQC7' and hosts.get('knob16') == 'slot0.param0'
      and hosts.get('knob24') == 'slot1.param0' and 'knob32' not in hosts and hosts.get('knob0') == 'eq1.q'
      and hosts.get('knob15') == 'sel.Volume' and hosts.get('push15') == 'sel.Solo' and hosts.get('push0') == 'eq1.on',
      'bank 1 = Isabellas Default-Seite (EQ, Filter, Pan, Volume, Tasten), bank 2 insert slots, bank 3 frei, bank 4 Sends (Skript) + QCs')
push = {b['label']: b['desc'] for b in nu['bindings'] if b['label'].startswith('push')}
check(len(push) == 32 and push.get('push48') == {'type': 'cc', 'ch': 1, 'cc': 49} and push.get('push0') == {'type': 'note', 'ch': 1, 'note': 0} and push.get('push15') == {'type': 'note', 'ch': 1, 'note': 15}
      and push.get('push60') == {'type': 'cc', 'ch': 1, 'cc': 61} and push.get('push63') == {'type': 'cc', 'ch': 1, 'cc': 64},
      f'push: bank 1 notes 0-15 ch 2, bank 4 CC 49-64 ch 2 ({len(push)})')
marks = {}
for item in nu['out']:
    if isinstance(item, dict):
        marks[item['mark']] = True
        view.tick()
        if item['mark'] == 'titles':
            check(view.text('src') == 'NUENDO' and view.text('track') == 'Vox Lead', f"source/track ({view.text('src')}, {view.text('track')})")
            check(view.text('c9_name') == 'Azimuth Angle\nStereoEncoder' and view.text('c9_val') == '45.0°', f"names from Nuendo ({view.text('c9_name')!r} {view.text('c9_val')!r})")
            check(view.text('bankname') == 'Bank 4', 'view starts on bank 4')
            check(view.text('c10_name') == '', 'unbound knob: empty')
        if item['mark'] == 'bank3':
            check(view.text('bankname') == 'frei' and view.text('c1_name').startswith('Pan Left-Right') and view.text('c1_val') == 'L 20',
                  'Twister bank 3 -> MultiPanner mapped via Mapping Assistant')
        if item['mark'] == 'bank2-off':
            check(view.text('bankname') == 'frei', 'bank-off message (value 0) ignored')
        continue
    assert all(0 <= x <= 127 for x in item[1:-1]), item
    view.midi(*item)
same = nu['out'][nu['out'].index({'mark': 'bank2-off'}) + 1: nu['out'].index({'mark': 'same'})]
check(same == [], 'unchanged display value is not re-sent')
idle = nu['out'][nu['out'].index({'mark': 'same'}) + 1: nu['out'].index({'mark': 'idle'})]
check(len(idle) == 4 and idle[0][:4] == [0xF0, 0x7D, 0x4D, 5] and all(m[:4] == [0xF0, 0x7D, 0x4D, 6] for m in idle[1:]), 'mOnIdle keep-alive every 5 s (source + bank names)')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
