"""Twister bank 4 send strip: writes to Nuendo only on turn/push, never on feedback/track/bank changes."""
import json, os, subprocess, sys
from view_harness import View
here = os.path.dirname(os.path.abspath(__file__))
js = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'dist', 'serena_MFTView.js')
d = json.loads(subprocess.check_output(['node', os.path.join(here, 'scenario_sends.js'), js]))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
host = {b['surface']: b['host'] for b in d['valueBindings']}
check(host.get('custom:twsend1Level') == 'send0.level' and host.get('custom:twsend8Pre') == 'send7.pre'
      and host.get('custom:twVolume') == 'sel.Volume' and host.get('custom:twSolo') == 'sel.Solo', 'Sends 1-8 + Volume/Solo gebunden')
o = {x['tag']: x for x in d['out']}
sets = lambda t: [(s['label'].split(':')[1], s['v']) for s in o[t]['sets'] if not s['label'].split(':')[1].startswith('b4 steps')]
for t in ('activate', 'feedback', 'send8', 'track', 'holdrelease', 'nosend'):
    check(sets(t) == [], f'{t}: nichts an Nuendo geschickt')
check([k for k, v in sets('turn1')] == ['twsend1Level'] and sets('turn1')[0][1] > 0.62, f"2 Raster rechts = lauter als -6 dB {sets('turn1')}")
check(sets('turn1b') == [('twsend1Level', 0.4)], f"30 Raster links = -20 dB = gelernter Wert von Send 2 {sets('turn1b')}")
check(sets('push1') == [('twsend1On', 0)], 'Drücken = Send aus')
check([k for k, v in sets('holdturn')] == ['twsend2Pre'], f"halten + drehen = nur pre/post {sets('holdturn')}")
check([k for k, v in sets('vol')] == ['twVolume'] and sets('solo') == [('twSolo', 1)], 'kein 8. Send: Encoder 8 = Volume, Drücken = Solo')
check([k for k, v in sets('send8turn')] == ['twsend8Level'], f"8. Send da: Encoder 8 = Send 8 {sets('send8turn')}")
view = View(os.environ.get('TOSC') or os.path.join(here, '..', 'dist', 'seren-a_Twister_View.tosc'))
for x in d['out']:
    for msg in x['midi']: view.midi(*msg)
    view.tick()
    if x['tag'] == 'feedback':
        check(view.text('c1_name') == 'FX 1-Reverb\nSend 1' and view.text('c1_val') == '-6.0 dB', f"Ansicht: {view.text('c1_name')!r} {view.text('c1_val')!r}")
        check(view.text('c8_name') == 'Volume\nSpur' and view.text('c4_name') == '', f"Ansicht: Encoder 8 = {view.text('c8_name')!r}")
    if x['tag'] == 'push1':
        check(view.text('c1_val') == '-20.0 dB AUS', 'Ansicht zeigt AUS')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
sys.exit(1 if fails else 0)
