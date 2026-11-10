import os, sys
from view_harness import View
TOSC = os.environ.get('TOSC') or os.path.join(os.path.dirname(__file__), '..', 'dist', 'seren-a_Twister_View.tosc')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
v = View(TOSC)
check(v.text('bankname') == 'Bank 4' and v.text('src') == 'LIVE', f"start: {v.text('src')} / {v.text('bankname')}")
check(v.text('c1_cc') == 'CC 49' and v.text('c16_cc') == 'CC 64', 'start bank 4 = CC 49-64')

# Live/Traktor style: only value feedback (channel 1). Turning encoder 5 of bank 2 (CC 20)
for x in (10, 20, 30):
    v.midi(0xB0, 20, x); v.tick(30)
v.tick()
check(v.text('bankname') == 'Bank 2', 'view follows the bank whose values arrive')
check(v.text('c5_val') == '24 %' and abs(v.bar(5) - 30 / 127) < 1e-6, f"cell 5: {v.text('c5_val')}, bar {v.bar(5):.3f}")
col = v.c['c5_bar']['color']
import json
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..')); import mfs_parse
encs = mfs_parse.parse(open('/root/.claude/uploads/1d4028fa-12da-5404-ac70-1ceecfe42680/0f3307c3-midi_fighter_2026_jan_vor_croissant.mfs','rb').read())[1]
rgb = json.load(open(os.path.join(os.path.dirname(__file__), '..', 'used_colors.json')))[str(encs[20]['active_color'])]
check(all(abs(col[k] - rgb[i] / 255) < 0.002 for i, k in enumerate('rgb')), f'bar colour = encoder 21 colour from the .mfs (#{encs[20]["active_color"]})')
# project load: values for two banks at once -> stay
v.tick(1000)
for cc in (0, 1, 2, 32, 33, 34):
    v.midi(0xB0, cc, 64)
v.tick()
check(v.text('bankname') == 'Bank 2', 'values for several banks at once: no jump')
# single stray value: stay
v.tick(1000); v.midi(0xB0, 40, 1); v.tick()
check(v.text('bankname') == 'Bank 2', 'one stray value: no jump')
# bank 4 lives on CC 49-64 in this file
v.tick(1000)
for x in (1, 2, 3): v.midi(0xB0, 49, x); v.tick(20)
v.tick()
check(v.text('bankname') == 'Bank 4' and v.text('c1_cc') == 'CC 49' and v.text('c1_val') == '2 %', f"bank 4 starts at CC 49 ({v.text('c1_cc')}, {v.text('c1_val')})")
v.midi(0xB0, 48, 100); v.tick()
check(all(v.text(f'c{s}_val') != '79 %' for s in range(1, 17)), 'CC 48 is not on any encoder: ignored')

# Twister bank message (system channel 4): CC 2 = 127 -> bank 3; from then on no auto switching
v.midi(0xB3, 1, 0); v.midi(0xB3, 2, 127); v.tick()
check(v.text('bankname') == 'Bank 3', 'Twister bank message selects bank 3')
for x in (5, 6, 7, 8): v.midi(0xB0, 20, x); v.tick(20)
v.tick()
check(v.text('bankname') == 'Bank 3', 'after a real bank message the values no longer move the view')
v.midi(0xB3, 9, 127); v.tick()
check(v.text('bankname') == 'Bank 3', 'side-button CCs (8+) on channel 4 are not banks')

# bank tabs on the phone: select + tell the Twister
v.sent(); v.run("onReceiveNotify('btn','tab2')"); v.tick()
check(v.text('bankname') == 'Bank 2' and v.sent() == [[0xB3, 1, 127]], 'tab 2: view + CC 1=127 on channel 4')

# profile names (Live/Traktor): editable table; src button cycles
v.run("onReceiveNotify('btn','src_btn')"); v.tick()
check(v.text('src') == 'TRAKTOR', 'source button cycles profiles')

# DAW script (hub): names, display values, bank, track via SysEx
def hub(cmd, *data, text=''):
    v.midi(0xF0, 0x7D, 0x4D, cmd, *data, *[ord(ch) for ch in text], 0xF7)
hub(7); hub(5, text='REAPER'); hub(3, text='Vox Lead'); hub(6, 0, text='IEM')
hub(1, 0, 0, text='Azimuth Angle\nStereoEncoder'); hub(2, 0, 0, text='45.0 deg')
hub(4, 0); v.midi(0xB0, 0, 96); v.tick()
check(v.text('src') == 'REAPER' and v.text('track') == 'Vox Lead' and v.text('bankname') == 'IEM', 'hub: source, track, bank name')
check(v.raw('c1_name') == 'Azimuth Angle' and v.raw('c1_sub') == 'StereoEncoder' and v.text('c1_val') == '45.0 deg',
      'hub: name, plugin line (own field) and display value')
v.midi(0xF0, 0x7D, 0x4D, 1, 0, 1, *b'Lautst\x01rke', 0xF7); v.midi(0xF0, 0x7D, 0x4D, 2, 0, 1, *b'45\x08', 0xF7); v.tick(30)
check(v.text('c2_name') == 'Lautstärke' and v.text('c2_val') == '45°', 'umlauts and ° arrive as codes 1-8 and show as such')
v.midi(0xF0, 0x7D, 0x4D, 1, 0, 1, 0xF7); v.midi(0xF0, 0x7D, 0x4D, 2, 0, 1, 0xF7); v.tick(30)
check(v.text('c2_name') == '' and v.text('c2_val') == '' and v.bar(2) == 0, 'hub mode: unmapped encoder stays empty even with an old value')
check(abs(v.bar(1) - 96 / 127) < 1e-6, 'bar from the CC the hub sends')
check(v.text('tab1_lbl') == 'IEM', 'tab shows the bank name')
v.run("onReceiveNotify('btn','src_btn')"); v.tick()
check(v.text('src') == 'REAPER', 'profiles locked while a DAW script talks')
v.tick(16000); v.tick()
check(v.text('src') == 'TRAKTOR', 'hub silent for 15 s: back to the profile')
hub(5, text=''); v.tick()
check(v.text('src') != '', 'empty source = DAW script stopped')

# v6.1: looks, colours from the DAW script, bank keys
v = View(TOSC)
sx = lambda *b: v.midi(0xF0, 0x7D, 0x4D, *b, 0xF7)
sx(5, *b'NUENDO'); sx(1, 3, 0, *b'Threshold\nOmniCompressor'); sx(2, 3, 0, *b'-18.0 dB'); sx(8, 3, 0, 127, 79, 0)
v.midi(0xB0 + encs[48]['encoder_midi_channel'] - 1, encs[48]['encoder_midi_number'], 64); v.tick(30, 2)
v.bar_frac1 = v.bar(1)
check(abs(v.bar_frac1 - 64 / 127) < 1e-6, 'bar follows the CC')
c = v.c['c1_bar']['color']
check(abs(c['r'] - 1) < 1e-3 and abs(c['g'] - 79 / 127) < 1e-3 and c['b'] == 0, 'bar colour from SysEx 8 (IEM orange)')
check(v.text('look_lbl') == 'Look: Klar' and v.c['c1_knob']['visible'] is False and v.c['c1_bar']['visible'], 'start look: Klar, bar, no knob')
names = []
for want in ('Spalte', 'Neon', 'IEM Neon', 'Kawaii Nacht', 'Klar'):
    v.run("onReceiveNotify('btn','look_btn')"); v.tick(30)
    names.append(v.text('look_lbl'))
    if want == 'Spalte':
        bb = v.c['c1_barbg']['frame']; check(bb['h'] > bb['w'], 'Spalte: the bar stands as a column')
    if want == 'Neon':
        check(v.c['c1_edge']['visible'] and v.c['c1_glow']['visible'], 'Neon: outline + glow')
        tc = v.c['c1_val']['textColor']; check(abs(tc['g'] - 79 / 127) < 1e-3, 'Neon: value in the bar colour')
    if want == 'IEM Neon':
        check(v.c['c1_knob']['visible'] and not v.c['c1_bar']['visible'] and v.c['c1_pill']['visible'], 'IEM Neon: knob + value pill')
        check(abs(v.c['c1_knob']['values']['x'] - v.bar_frac1) < 0.02, 'IEM Neon: knob follows the value')
    if want == 'Kawaii Nacht':
        g = v.c['ground']['color']; check(abs(g['r'] - 0x23 / 255) < 1e-3 and abs(g['b'] - 0x28 / 255) < 1e-3 and v.c['c1_bar']['visible'], 'Kawaii Nacht: night-pink colours, bar')
check(names == ['Look: Spalte', 'Look: Neon', 'Look: IEM Neon', 'Look: Kawaii Nacht', 'Look: Klar'], f'look key cycles: {names}')
sx(8, 3, 127); v.tick(30)
c = v.c['c1_bar']['color']; check(not (abs(c['r'] - 1) < 1e-3 and abs(c['g'] - 79 / 127) < 1e-3), 'SysEx 8 slot 127: colours back to the .mfs')
sx(6, 0, *b'Kanal/EQ'); v.tick(30)
check(v.text('tab1_lbl') == 'Kanal/EQ', 'bank key shows the bank name')
v.sent(); v.run("onReceiveNotify('btn','tab2')"); v.tick(30)
out = v.sent()
check(any(m[0] & 0xF0 == 0xB0 and m[1] == 1 and m[2] == 127 for m in out) and v.text('bankname') != '', f'tap on bank 2 tells the Twister (via the DAW script): {out}')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
