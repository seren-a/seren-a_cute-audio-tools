"""Feeds the Cubase script's MIDI (from scenario_e16.js) into dawlink.lua on the E16 mock."""
import importlib, json, sys
lua = importlib.import_module("lupa.lua54")
MOCK = "/tmp/claude-0/-home-claude/1d4028fa-12da-5404-ac70-1ceecfe42680/scratchpad/e16repo/repo/test/e16mock.lua"
timeline = json.load(open(sys.argv[1]))
L = lua.LuaRuntime()
E = L.eval(f'dofile("{MOCK}")')
E.load(sys.argv[2])
onCC = L.eval('function(ch, n, v) midi.onCC(0, ch, n, v) end')
snaps = {}
for ev in timeline:
    if 'send' in ev:
        st, cc, v = ev['send']
        assert 0xB0 <= st <= 0xBF and 0 <= cc <= 127 and 0 <= v <= 127, ev
        onCC(st - 0xB0, cc, v)
    elif 'run' in ev:
        E.run(ev['run'])
    elif 'snap' in ev:
        labels = {i: E.labels[i] for i in range(1, 17)}
        rings = {i: (E.rings[i].v if E.rings[i] else None) for i in range(1, 17)}
        snaps[ev['snap']] = (E.title, labels, rings, ev)
fails = 0
def check(c, m):
    global fails
    print(('ok   ' if c else 'FAIL: ') + m); fails += 0 if c else 1
def S(n): return snaps[n]
t, lab, rg, ev = S('sends')
check(t == 'Kick drum Ambis', f'title = track name, 15 chars ({t!r})')
check(lab[1] == 'FX1' and lab[2] == 'FX2' and lab[3] in ('', None) and lab[8] == 'Vol' and lab[9] == 'Azim',
      f'SENDS: send names, no 3rd send, 8 = Volume, 9 = QC 1 ({lab[1]},{lab[2]},{lab[3]},{lab[8]},{lab[9]})')
check(rg[1] == round(0.85 * 127) * 129 and rg[3] is None, f'send ring -6 dB on a -40..0 scale ({rg[1]})')
check(ev['sets'] == [], 'Nuendo reports values: nothing written back')
t, lab, rg, ev = S('turned')
check(ev['sets'] == [['e16send1Level', 0.6455]] and lab[1] == '-5.0' and t.startswith('Send 1 FX 1-Re'), f'turn send 1 by 2 steps = -5 dB ({ev["sets"]}, {lab[1]!r}, {t!r})')
check(S('sendOff')[1][1] == 'AUS' and S('sendOff')[3]['sets'] == [['e16send1On', 0]], 'push = send off, shows AUS')
t, lab, rg, ev = S('prepost')
check(ev['sets'] == [['e16send2Pre', 1]] and lab[2] == '-20p', f'hold + turn = pre, no on/off ({ev["sets"]}, {lab[2]!r})')
check(S('vol')[3]['sets'] == [['e16Volume', 0.801]] and S('solo')[3]['sets'] == [['e16Solo', 1]] and S('solo')[1][8] == 'SOLO',
      'no 8th send: encoder 8 = volume (+0.5 dB), push 8 = solo')
check(S('nextTrackShort')[3]['triggers'] == ['nextTrack'], 'SENDS: short push 14 = next track')
check(S('pageKey')[3]['triggers'] == ['activate EQ'] and S('pageKey')[3]['sets'] == [], 'hold push 16 = EQ page, nothing written')
t, lab, rg, ev = S('eqPage')
check(ev['sets'] == [] and lab[1] == 'Q1' and lab[5] == 'Gai1' and lab[16] == 'Volu', f'EQ page: names like Twister bank 1, nothing written ({lab[1]},{lab[5]},{lab[16]})')
check(S('eqSteps')[3]['sets'] == [], 'EQ page: the send strip stays silent')
check(S('eqSolo')[3]['sets'] == [['solo', 1]] and S('eqBand1')[3]['sets'] == [['eqOn1', 0]] and S('eqLowCut')[3]['sets'] == [['lowCutOn', 1]],
      'EQ page short pushes: 16 solo, 1 band on/off, 13 low cut on')
check(S('eqPrevTrack')[3]['triggers'] == ['prevTrack'] and S('eqPrevTrack')[3]['sets'] == [], 'EQ page: hold 13 = previous track (no low cut toggle)')
check(S('eqDrum')[3]['sets'] == [['drumEditor', 1], ['drumEditor', 0]], 'push 5 = drum editor command')
check(S('eqPage2')[3]['triggers'] == ['activate Inserts'] and S('eqPage2')[3]['sets'] == [], 'EQ page: hold 16 = next page, no solo')
check(S('insKeys')[3]['triggers'] == ['slot0.nextBank'] and S('insKeys')[3]['sets'] == [['bypassA', 1]], 'INSERTS: push 8 next bank, push 1 bypass')
check(S('insPage2')[3]['triggers'] == ['activate Sends + Quick Controls'], 'INSERTS: short 16 = next page (back to sends)')
t, lab, rg, ev = S('backToSends')
check(ev['sets'] == [] and lab[1] == 'FX1' and lab[8] == 'Vol', f'back on SENDS: send names redrawn, nothing written ({lab[1]},{lab[8]})')
print('ALL PASSED' if fails == 0 and E.fails == 0 else f'{fails} FAILED')
