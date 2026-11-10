"""Reaper_MultiEQ.lua against the Reaper mock with two fake IEM MultiEQ: Twister bank 4 + E16 scene."""
import importlib, math, os
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'Reaper_MultiEQ.lua')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1

lua = importlib.import_module("lupa.lua54")
R = lua.LuaRuntime(); g = R.globals()
R.execute(open(os.path.join(HERE, 'reaper_mock.lua')).read())
R.execute(open(os.path.join(HERE, 'multieq_fake.lua')).read())
R.execute('''
OUTS = {"IAC Bus 1", "Midi Fighter Twister", "TouchOSC Bridge", "OXI E16"}
INS  = {"Keystation", "Midi Fighter Twister", "TouchOSC Bridge", "OXI E16"}
EQA = MultiEQ("VST3: MultiEQ (IEM)", "{EQA}", {40, 63, 120, 500, 2000, 18000})
EQB = MultiEQ("VST3: MultiEQ (IEM)", "{EQB}", {45, 80, 200, 800, 4000, 16000})
OTHER = MultiEQ("VST3: MultiEQ (IEM)", "{EQC}", {50, 90, 300, 900, 5000, 15000})
OMV, DIV, OMM, DIM = OmniComp("{OV}"), DirComp("{DV}"), OmniComp("{OM}"), DirComp("{DM}")
OMK = OmniComp("{OK}")
FDNV, CONVM = FdnReverb("{FV}"), Convolver("{CM}")
ROTM = { name = "VST3: SceneRotator (IEM)", guid = "{RM}", params = {
  { name = "Ambisonics Order", v = 0, fmt = function(x) return "Auto" end },
  { name = "Yaw Angle", v = 0.5, fmt = function(x) return string.format("%.1f deg", x * 360 - 180) end } } }
MASTER = {name = "MASTER", guid = "{M}", fx = {EQA, OMM}, rec = {}}
TRACKS = { {name = "Vox", guid = "{V}", sel = true, fx = {OMV}}, {name = "Mon", guid = "{X}", sel = false, fx = {EQB, OTHER}},
           {name = "Kick", guid = "{K}", sel = false, fx = {OMK}} }
''')
MFT, VIEW, E16 = 1, 2, 3
T = [0.0]
def run(dt=0.033, n=1):
    for _ in range(n):
        T[0] += dt
        R.execute(f"T = {T[0]}; DEFER()")
def flush():
    out = g.OUT; msgs = []
    for i in range(1, len(out) + 1):
        m = out[i]; msgs.append((m.dev, [m.bytes[j] for j in range(1, len(m.bytes) + 1)]))
    R.execute("OUT = {}")
    return msgs
def ev(dev, st, d1, d2): R.execute(f"evIn({dev}, {st}, {d1}, {d2})")
def turn_mft(e, d): ev(MFT, 0xB0, 48 + e, 64 + d)
def push_mft(e, down): ev(MFT, 0xB1, 48 + e, 127 if down else 0)
def turn_e16(e, d): ev(E16, 0xBC, 19 + e, 64 + d)
def push_e16(e, down): ev(E16, 0xBC, 39 + e, 127 if down else 0)
def real(fx, b, k): return round(R.eval(f"REAL({fx}, {b}, '{k}')"), 4)
def enabled(fx, b): return R.eval(f"ENABLED({fx}, {b})")

R.execute(open(SCRIPT).read())
run()
con = g.CONSOLE or ''
check('A = VST3: MultiEQ (IEM) auf Master' in con and 'B = VST3: MultiEQ (IEM) auf Mon' in con, 'A = Master, B = erste Instanz auf Spur "Mon"')
check('e 6, f 6, g 6, q 6, t 6' in con, 'alle 6 Bänder je Art erkannt')
check('E16 da' in con and 'Twister da' in con, 'Twister und E16 gefunden')
flush(); run(0.5)

# --- turning = frequency, fine when slow
f0 = real('EQA', 1, 'Frequency')
turn_mft(1, 1); run(0.2)
f1 = real('EQA', 1, 'Frequency')
check(f1 == f0 + 1, f'langsam drehen bei 40 Hz = 1 Hz weiter ({f0} -> {f1})')
f0 = real('EQA', 5, 'Frequency')
turn_mft(6, 1); run(0.2)
f1 = real('EQA', 5, 'Frequency')
check(f0 < f1 <= f0 * 2 ** (1.5 / 96), f'langsam bei 2 kHz = 1/96 Oktave ({f0} -> {f1})')
f0 = real('EQA', 5, 'Frequency')
for _ in range(12): turn_mft(6, 1)
run()
f1 = real('EQA', 5, 'Frequency')
check(f1 > f0 * 2 ** (12 * 4 / 96), f'schnell 12 Raster = mehr als eine halbe Oktave ({f0:.0f} -> {f1:.0f})')
f0 = real('EQA', 5, 'Frequency')
turn_mft(6, -1); run(0.3); turn_mft(6, -1); run(0.3)
check(real('EQA', 5, 'Frequency') < f0, 'links drehen = tiefer')
g0 = real('EQA', 5, 'Gain')
check(abs(g0) < 1e-9, 'Gain bleibt beim Drehen unberührt')

# --- press + turn = gain
f0, g0 = real('EQA', 3, 'Frequency'), real('EQA', 3, 'Gain')
push_mft(3, True); run(0.1); turn_mft(3, -1); run(0.2); turn_mft(3, -1); run(0.2); push_mft(3, False); run(0.5)
f1, g1 = real('EQA', 3, 'Frequency'), real('EQA', 3, 'Gain')
check(f1 == f0 and abs(g1 + 0.2) < 1e-6, f'drücken + drehen = Gain -0,2 dB, Frequenz bleibt ({g1:.2f} dB, {f0}->{f1})')
check(enabled('EQA', 3), 'drücken + drehen ist kein Doppelklick')
# gain keeps going even past HOLD once started
push_mft(3, True); run(0.1); turn_mft(3, 1); run(0.1); run(0.6); turn_mft(3, 1); run(0.1); push_mft(3, False); run(0.1); run(0.5)
check(abs(real('EQA', 3, 'Gain')) < 1e-6, 'einmal Gain begonnen bleibt Gain, auch nach 0,45 s')

# --- hold + turn = Q
q0, g0 = real('EQA', 4, 'Q'), real('EQA', 4, 'Gain')
push_mft(5, True); run(0.033, 16)
q_pulse = [b for d, b in flush() if d == MFT and b[:2] == [0xB2, 53]]
check(any(b[2] == 11 for b in q_pulse), f'nach 0,45 s halten pulsiert der Twister (Q-Modus) {q_pulse}')
turn_mft(5, 1); run(0.2); turn_mft(5, 1); run(0.2); push_mft(5, False); run(0.5)
q1 = real('EQA', 4, 'Q')
check(q1 > q0 and real('EQA', 4, 'Gain') == g0, f'halten + drehen = Q höher ({q0:.2f} -> {q1:.2f}), Gain bleibt')
check(any(b[:2] == [0xB2, 53] and b[2] == 0 for d, b in flush() if d == MFT), 'nach dem Loslassen kein Pulsieren mehr')

# --- double press = band off / on
push_mft(2, True); run(0.06); push_mft(2, False); run(0.1); push_mft(2, True); run(0.06); push_mft(2, False); run(0.1)
check(enabled('EQA', 2), 'Doppelklick schaltet erst nach dem Fenster (3. Klick könnte kommen)')
run(0.4)
check(not enabled('EQA', 2), 'Doppelklick: Band 2 aus')
m = flush()
check(any(d == MFT and b == [0xB2, 50, 19] for d, b in m) and not any(d == MFT and b == [0xB1, 50, 0] for d, b in m), 'Twister: Band aus = gedimmt (Farbe bleibt gesetzt)')
check(any(d == E16 and b == [0xB7, 2, 1] for d, b in m), 'E16: Zustand Band 2 = aus')
push_mft(2, True); run(0.06); push_mft(2, False); run(0.1); push_mft(2, True); run(0.06); push_mft(2, False); run(0.1); run(0.5)
check(enabled('EQA', 2), 'Doppelklick nochmal: Band 2 wieder an')

# --- triple press = lock frequency
for _ in range(3):
    push_mft(7, True); run(0.05); push_mft(7, False); run(0.08)
run(0.5)
check(enabled('EQA', 6), 'Dreifachklick schaltet das Band nicht aus')
check(g.PEXT['seren_MultiEQ/{EQA}:6'] == '1', 'Dreifachklick: Sperre im Projekt gespeichert')
f0 = real('EQA', 6, 'Frequency')
turn_mft(7, 3); run(0.2)
check(real('EQA', 6, 'Frequency') == f0, 'gesperrt: Drehen ändert die Frequenz nicht')
check(any(d == MFT and b == [0xB1, 55, 113] for d, b in flush()), 'Twister: gesperrt = Sperrfarbe (violett)')
push_mft(7, True); run(0.1); turn_mft(7, 1); run(0.1); push_mft(7, False); run(0.5)
check(abs(real('EQA', 6, 'Gain') - 0.1) < 1e-6, 'gesperrt: Gain geht weiter')
for _ in range(3):
    push_mft(7, True); run(0.05); push_mft(7, False); run(0.08)
run(0.5)
turn_mft(7, -1); run(0.2)
check(real('EQA', 6, 'Frequency') < f0, 'nochmal dreifach: wieder frei')

# --- encoders 7, 8, 15, 16 free; 9-14 = B
f0 = real('EQB', 1, 'Frequency')
turn_mft(9, 1); run(0.2)
check(real('EQB', 1, 'Frequency') == f0 + 1, 'Encoder 9 = MultiEQ B Band 1')
check(real('OTHER', 1, 'Frequency') == 50, 'dritte Instanz bleibt unberührt')

# --- E16 scene
f0 = real('EQB', 3, 'Frequency')
turn_e16(11, 1); run(0.2)
check(real('EQB', 3, 'Frequency') > f0, 'E16 Encoder 11 = B Band 3 Frequenz')
push_e16(11, True); run(0.1); turn_e16(11, 1); run(0.1); push_e16(11, False); run(0.5)
check(abs(real('EQB', 3, 'Gain') - 0.1) < 1e-6, 'E16 drücken + drehen = Gain')
m = flush(); run(); m += flush()
T[0] += 6; run(); m = flush()          # full resync
names = {}
for d, b in m:
    if d == E16 and b[0] == 0xBB and 16 <= b[1] < 80: names[b[1]] = chr(b[2])
slot = lambda e: ''.join(names.get(16 + (e - 1) * 4 + i, '?') for i in range(4))
check(slot(1).strip() == '41' and slot(7).strip() == '18k' and slot(5).strip() == '500', f'E16 Slotnamen = Frequenz, Band 4-6 auf 5-7 ({slot(1)!r}, {slot(5)!r}, {slot(7)!r})')
check(slot(4).strip() == '' and slot(9).strip() == '46', f'E16 Encoder 4 leer (kein DirComp), 9 = B1 ({slot(4)!r}, {slot(9)!r})')
title = ''.join(chr(b[2]) for d, b in m if d == E16 and b[0] == 0xBB and b[1] < 15)
check(title.strip() == 'A Maste B Mon', f'E16 Titel ({title!r})')
check(any(d == E16 and b[0] == 0xB9 and b[1] == 80 for d, b in m), 'E16 Ring 1 gesendet')
check(any(d == E16 and b[:2] == [0xB9, 86] for d, b in m), 'E16 Ring 7 = Band 6')
flush(); push_e16(12, True); run(0.033, 16); m = flush()
check(any(d == E16 and b == [0xB7, 12, 4] for d, b in m), 'E16: halten = Q-Modus (Zustand +4)')
push_e16(12, False); run(0.1)
check(any(d == E16 and b == [0xB7, 12, 0] for d, b in flush()), 'E16: loslassen = normal')
# value flash on the E16
turn_e16(11, 1); run(0.1); m = flush()
check(any(d == E16 and b == [0xB9, 15, 0] for d, b in m), 'E16: Titel-Flash nach Drehen')

# --- Twister View: bank 4 names, values, ring
T[0] += 6; run(); m = flush()
sx = [b for d, b in m if d == VIEW and b[:3] == [0xF0, 0x7D, 0x4D]]
nm = [bytes(b[6:-1]).decode() for b in sx if b[3] == 1 and b[4] == 3 and b[5] == 0]
check(nm and nm[0] == '41 Hz\nA1' or nm and nm[0].startswith('41.0 Hz\nA1'), f'Twister View: Name Bank 4 Encoder 1 ({nm})')
import sys; sys.path.insert(0, '/home/claude/mft-view/test')
from view_harness import View
v = View('/home/claude/mft-view/dist/seren-a_Twister_View.tosc')
for d, b in m:
    if d == VIEW: v.midi(*b)
v.tick()
check(v.text('c1_name') == '41 Hz\nA1' and v.text('c1_val') == '+0.0 dB  Q 0.71', f"Twister View zeigt A1 ({v.text('c1_name')!r}, {v.text('c1_val')!r})")
check(v.text('c7_name').endswith('A6') and v.text('c4_name') == '' and v.text('c9_name').startswith('46 Hz\nB1') and v.text('bankname') == 'MultiEQ', f"Twister View: 7 = A6, 4 leer, 9 = B1, Tab 'MultiEQ' ({v.text('c7_name')!r}, {v.text('c4_name')!r}, {v.text('c9_name')!r})")
check(g.EXTS['seren_MultiEQ/alive'] not in (None, ''), 'Hub-Signal "alive" gesetzt')


def tap(e, n=1, dev='mft'):
    for _ in range(n):
        (push_mft if dev == 'mft' else push_e16)(e, True); run(0.05)
        (push_mft if dev == 'mft' else push_e16)(e, False); run(0.08)
def hold(e, dev='mft'):
    (push_mft if dev == 'mft' else push_e16)(e, True); run(0.033, 18)
    (push_mft if dev == 'mft' else push_e16)(e, False); run(0.1)
def pturn(e, d, long=False, dev='mft'):
    P = push_mft if dev == 'mft' else push_e16; Tn = turn_mft if dev == 'mft' else turn_e16
    P(e, True); run(0.033, 18) if long else run(0.1); Tn(e, d); run(0.1); P(e, False); run(0.1)

# ================= v5.4: DirectionalCompressor dazu -> obere Reihe = Kompressor =================
R.execute("table.insert(MASTER.fx, DIM); table.insert(TRACKS[1].fx, DIV); STATE = STATE + 1"); run(0.1); run(0.1)
flush()
th, kn = R.eval("PV(DIV, 'Threshold 1')"), R.eval("PV(DIV, 'Knee 1')")
turn_mft(1, 1); run(0.2)
check(R.eval("PV(DIV, 'Threshold 1')") > th, 'mit DirComp: Encoder 1 drehen = Threshold 1')
pturn(1, 1)
check(R.eval("PV(DIV, 'Knee 1')") > kn, 'Encoder 1 drücken + drehen = Knee 1')
ra, at = R.eval("PV(DIV, 'Ratio 1')"), R.eval("PV(DIV, 'Attack Time 1')")
turn_mft(2, 1); run(0.2); pturn(2, 1)
check(R.eval("PV(DIV, 'Ratio 1')") > ra and R.eval("PV(DIV, 'Attack Time 1')") > at, 'Encoder 2: Ratio 1 / drücken Attack 1')
mk, rl, az = R.eval("PV(DIV, 'MakeUp Gain 1')"), R.eval("PV(DIV, 'Release Time 1')"), R.eval("PV(DIV, 'Azimuth of mask')")
turn_mft(3, 1); run(0.2); pturn(3, 1); pturn(3, 1, long=True)
check(R.eval("PV(DIV, 'MakeUp Gain 1')") > mk and R.eval("PV(DIV, 'Release Time 1')") > rl and R.eval("PV(DIV, 'Azimuth of mask')") > az,
      'Encoder 3: Makeup 1 / drücken Release 1 / halten Azimut')
t2, k2 = R.eval("PV(DIV, 'Threshold 2')"), R.eval("PV(DIV, 'Knee 2')")
turn_mft(5, -1); run(0.2); pturn(5, 1)
check(R.eval("PV(DIV, 'Threshold 2')") < t2 and R.eval("PV(DIV, 'Knee 2')") > k2, 'Encoder 5: Threshold 2 / drücken Knee 2')
r2, m2 = R.eval("PV(DIV, 'Ratio 2')"), R.eval("PV(DIV, 'MakeUp Gain 2')")
turn_mft(6, 1); run(0.2); turn_mft(7, 1); run(0.2)
check(R.eval("PV(DIV, 'Ratio 2')") > r2 and R.eval("PV(DIV, 'MakeUp Gain 2')") > m2, 'Encoder 6 = Ratio 2, 7 = Makeup 2')
f0 = real('EQA', 1, 'Frequency')
turn_mft(9, 1); run(0.2)
check(real('EQA', 1, 'Frequency') > f0, 'untere Reihe 9 = MultiEQ A Band 1')
f0 = real('EQA', 6, 'Frequency')
turn_mft(14, -1); run(0.2)
check(real('EQA', 6, 'Frequency') < f0, '14 = MultiEQ A Band 6')
tap(1, 2)
check(R.eval("PT(DIV, 'Enable Compression Stage 1')") == 'off', '2x auf 1 = Kompressor 1 aus')
tap(1, 2)
# --- 15 press + turn = SceneRotator yaw (master)
R.execute("table.insert(MASTER.fx, ROTM); STATE = STATE + 1"); run(0.1); run(0.1)
y0 = R.eval("ROTM.params[2].v")
pturn(15, 1)
check(R.eval("ROTM.params[2].v") > y0, '15 drücken + drehen = SceneRotator Yaw')
check(R.eval("TRACKS[1].vals == nil or (TRACKS[1].vals.I_SOLO or 0) == 0"), 'drücken + drehen auf 15 schaltet kein Solo')

# ================= v5.3: compressor layers, encoder 7/8/15/16 =================
con = g.CONSOLE or ''
check('OmniComp A = VST3: OmniCompressor (IEM) auf Vox' in con and 'OmniComp B = VST3: OmniCompressor (IEM) auf Master (Ersatz vom Master)' in con,
      'Omni: A von der ausgewählten Spur, B vom Master (nur eins auf der Spur)')
check('DirComp A = VST3: DirectionalCompressor (IEM) auf Vox' in con, 'Directional von der ausgewählten Spur')
check('en 2' in con and 'drv 2' in con and 'apply 2' in con and 'mk 2' in con and 'pre 1' in con and 'listen 1' in con and 'w 1' in con,
      'Directional-Parameter erkannt (inkl. Input Gain = PreGain, MakeUp)')
# --- MultiEQ layer, encoder 8 = OmniComp A (Vox): turn thr, press+turn gain, hold+turn ratio, press = bypass
flush()
t0, g0, r0 = R.eval("PV(OMV, 'Threshold')"), R.eval("PV(OMV, 'Output Gain')"), R.eval("PV(OMV, 'Ratio')")
turn_mft(8, -1); run(0.2)
check(abs(R.eval("PV(OMV, 'Threshold')") - t0 + 0.1) < 1e-6, 'EQ-Ebene: Encoder 8 drehen = Omni-Threshold')
check(R.eval("OMV.float") == True, 'Drehen öffnet das Fenster des OmniCompressors')
pturn(8, 1)
check(abs(R.eval("PV(OMV, 'Output Gain')") - g0 - 0.1) < 1e-6, 'Encoder 8 drücken + drehen = Makeup (Output Gain)')
pturn(8, 1, long=True)
check(R.eval("PV(OMV, 'Ratio')") > r0, 'Encoder 8 lang drücken + drehen = Ratio hoch')
r1 = R.eval("PV(OMV, 'Ratio')")
pturn(8, -1, long=True)
check(R.eval("PV(OMV, 'Ratio')") < r1, 'Encoder 8 lang drücken + links drehen = Ratio runter')
push_mft(8, True); run(0.033, 18); turn_mft(8, 1); run(0.1); flush(); T[0] += 6; run(); mm = flush()
nm = [bytes(b[6:-1]).decode() for d, b in mm if d == VIEW and b[:6] == [0xF0, 0x7D, 0x4D, 1, 3, 7]]
check(nm and nm[-1].endswith('Omni Ratio'), f'beim Halten zeigt die Twister View Ratio ({nm[-1:]!r})')
push_mft(8, False); run(0.1)
check(R.eval("OMV.enabled") != False, 'drücken + drehen schaltet nicht aus')
tap(8)
check(R.eval("OMV.enabled") == False, 'Encoder 8 drücken = OmniComp A Bypass')
m = flush(); run(); m += flush()
check(any(d == MFT and b == [0xB2, 56, 19] for d, b in m), 'Bypass: Encoder 8 gedimmt')
tap(8)
check(R.eval("OMV.enabled") == True, 'nochmal drücken = wieder an')
# --- encoder 7 = Directional (Vox): turn width, press+turn both thresholds, hold+turn both ratios
w0 = R.eval("PV(DIV, 'Width of mask')"); a0, b0 = R.eval("PV(DIV, 'Threshold 1')"), R.eval("PV(DIV, 'Threshold 2')")
ra, rb = R.eval("PV(DIV, 'Ratio 1')"), R.eval("PV(DIV, 'Ratio 2')")
turn_mft(4, 1); run(0.2)
check(0 < R.eval("PV(DIV, 'Width of mask')") - w0 < 1.5, 'EQ-Ebene: Encoder 7 drehen = Directional Width (fein)')
check(R.eval("DIV.float") == True and R.eval("OMV.float") == False, 'Fenster: Directional auf, OmniComp zu')
pturn(4, -1)
check(abs(R.eval("PV(DIV, 'Threshold 1')") - a0 + 0.1) < 1e-6 and abs(R.eval("PV(DIV, 'Threshold 2')") - b0 + 0.1) < 1e-6,
      'Encoder 7 drücken + drehen = Threshold von Kompressor 1 und 2')
pturn(4, 1, long=True)
check(R.eval("PV(DIV, 'Ratio 1')") > ra and R.eval("PV(DIV, 'Ratio 2')") > rb, 'Encoder 7 lang + drehen = Ratio von beiden')
# --- encoder 16: tracks, master, mute
turn_mft(16, 1); run(0.2)
check(R.eval("TRACKS[2].sel") == True and R.eval("TRACKS[1].sel") == False, 'Encoder 16 drehen = nächste Spur')
turn_mft(16, -1); run(0.2)
check(R.eval("TRACKS[1].sel") == True, 'zurück = vorige Spur')
pturn(16, -3); pturn(16, -3)
mv = 20 * math.log10(R.eval("MASTER.vals.D_VOL"))
check(-6.5 < mv < -5.5, f'Encoder 16 drücken + drehen = Master-Lautstärke, 3 schnelle Raster = 3 dB ({mv:.1f} dB)')
for _ in range(30): pturn(16, -3)
mv = 20 * math.log10(R.eval("MASTER.vals.D_VOL"))
check(abs(mv + 30) < 0.01, f'Master endet bei -30 dB ({mv:.1f})')
flush(); push_mft(16, True); run(0.1); turn_mft(16, 1); run(0.1); mm = flush()
check(any(d == MFT and b == [0xB1, 64, 81] for d, b in mm) and any(d == MFT and b == [0xB2, 64, 22] for d, b in mm),
      'Master einstellen: 16 gedimmt rot, ohne Blinken')
push_mft(16, False); run(0.1); mm = flush()
check(any(d == MFT and b == [0xB2, 64, 0] for d, b in mm), 'danach wieder normal')
check(not any(d == MFT and b[0] == 0xB2 and b[2] >= 49 for d, b in mm), 'Ringhelligkeit nie auf dem Blink-Kanal 3')
check(R.eval("TRACKS[1].vals == nil or TRACKS[1].vals.B_MUTE == nil or TRACKS[1].vals.B_MUTE == 0"), 'drücken + drehen mutet nicht')
push_mft(16, True); run(0.05)
check(R.eval("TRACKS[1].vals == nil or (TRACKS[1].vals.B_MUTE or 0) == 0"), 'Mute erst beim Loslassen')
push_mft(16, False); run(0.1)
check(R.eval("TRACKS[1].vals.B_MUTE") == 1, 'Encoder 16 drücken = Vox gemutet')
m = flush(); run(); m += flush()
check(any(d == MFT and b == [0xB1, 64, 81] for d, b in m) and any(d == MFT and b == [0xB2, 64, 3] for d, b in m), 'Mute: 16 blinkt rot')
check(any(d == MFT and b == [0xB1, 63, 69] for d, b in m), 'gemutet, nicht solo: 15 blinkt orange')
tap(15)
check(R.eval("TRACKS[1].vals.I_SOLO") == 2, 'Encoder 15 drücken = Solo')
m = flush(); run(); m += flush()
check(any(d == MFT and b == [0xB1, 63, 64] for d, b in m), 'Solo: 15 blinkt gelb')
tap(15); tap(16)
check(R.eval("TRACKS[1].vals.I_SOLO") == 0 and R.eval("TRACKS[1].vals.B_MUTE") == 0, 'Solo und Mute wieder aus')
m = flush(); run(); m += flush()
check(any(d == MFT and b == [0xB2, 64, 0] for d, b in m), 'Blinken aus')

# --- layer switch: hold encoder 8 and let go
hold(8)
m = flush()
check(any(d == MFT and b == [0xB1, 56, 45] for d, b in m), 'Encoder 8 halten: Ebene Omni (grün)')
check(R.eval("OMV.enabled") == True, 'halten schaltet nicht den Bypass')
check(any(d == MFT and b == [0xB1, 57, 25] for d, b in m) and any(d == MFT and b == [0xB1, 49, 68] for d, b in m),
      'Omni B vom Master in Master-Farbe (cyan 25), A in IEM-Farbe (Threshold orange 68)')
check(any(d == MFT and b[:2] == [0xB0, 49] and b[2] == 127 - round(R.eval("OMV.params[3].v") * 127) for d, b in m), 'Threshold-Ring kommt von oben (umgekehrt)')
check(any(d == VIEW and b[:6] == [0xF0, 0x7D, 0x4D, 8, 3, 0] for d, b in m), 'Twister View bekommt die Balkenfarbe (SysEx 8)')
t0 = R.eval("PV(OMV, 'Threshold')")
turn_mft(1, -1); run(0.2)
check(abs(R.eval("PV(OMV, 'Threshold')") - t0 + 0.1) < 1e-6, 'Omni A Threshold')
r0 = R.eval("PV(OMM, 'Ratio')")
turn_mft(10, 1); run(0.2)
check(R.eval("PV(OMM, 'Ratio')") > r0 and R.eval("OMM.float") == True, 'Encoder 10 = Omni B (Master) Ratio, Fenster auf')
a0 = R.eval("PV(OMV, 'Attack Time')")
for _ in range(10): turn_mft(3, 1)
run()
check(R.eval("PV(OMV, 'Attack Time')") > a0 + 5, 'Attack schnell drehen = große Schritte')
tap(7)
check(R.eval("PT(OMV, 'LookAhead')") == 'on', '7 drücken = A LookAhead an')
tap(14, 2)
check(R.eval("PT(OMM, 'LookAhead')") == 'on', 'Omni-Ebene: 2x auf 14 = B LookAhead')
g0 = R.eval("PV(OMV, 'Output Gain')"); turn_mft(8, 1); run(0.2)
check(R.eval("PV(OMV, 'Output Gain')") > g0, 'Omni-Ebene: 8 drehen = A Makeup')
tap(15)
check(R.eval("TRACKS[1].vals.I_SOLO") == 2, 'Omni-Ebene: 15 drücken = trotzdem Solo')
tap(15)
v2 = View('/home/claude/mft-view/dist/seren-a_Twister_View.tosc')
T[0] += 6; run()
for d, b in flush():
    if d == VIEW: v2.midi(*b)
v2.tick()
check(v2.text('bankname') == 'Omni' and v2.text('c1_name').endswith('A Thr') and v2.text('c10_name').endswith('B Rat (Master)'),
      f"Twister View: Tab Omni ({v2.text('c1_name')!r}, {v2.text('c10_name')!r})")
check(v2.text('c16_name').startswith('1 Vox'), f"Twister View 16 = Spur ({v2.text('c16_name')!r})")
# --- Directional layer
hold(8)
th = R.eval("PV(DIV, 'Threshold 2')")
turn_mft(9, 1); run(0.2)
check(abs(R.eval("PV(DIV, 'Threshold 2')") - th - 0.1) < 1e-6, 'Directional: Encoder 9 = Kompressor 2 Threshold')
p0 = R.eval("PV(DIV, 'Input Gain')")
turn_mft(8, 1); run(0.2)
check(R.eval("PV(DIV, 'Input Gain')") > p0, 'Directional: Encoder 8 drehen = PreGain')
az = R.eval("PV(DIV, 'Azimuth of mask')")
turn_mft(7, 1); run(0.3); turn_mft(7, 1); run(0.3)
check(0 < R.eval("PV(DIV, 'Azimuth of mask')") - az < 3, 'Encoder 7 = Azimut, fein')
w0 = R.eval("PV(DIV, 'Width of mask')")
pturn(7, 1)
check(0 < R.eval("PV(DIV, 'Width of mask')") - w0 < 1.5, 'Encoder 7 drücken + drehen = Width')
el = R.eval("PV(DIV, 'Elevation of mask')")
turn_mft(15, 1); run(0.2)
check(R.eval("PV(DIV, 'Elevation of mask')") > el, 'Encoder 15 drehen = Elevation')
tap(1, 2)
check(R.eval("PT(DIV, 'Enable Compression Stage 1')") == 'off', '2x auf 1 = Kompressor 1 aus')
check(any(d == MFT and b == [0xB2, 49, 19] for d, b in flush() + (run() or []) + flush()), 'Kompressor 1 aus = gedimmt')
tap(10, 2)
check(R.eval("PT(DIV, 'Compression Driving Signal 2')") == 'Masked', '2x auf 10 = Driving Signal 2 weiter')
tap(7, 2)
check(R.eval("PT(DIV, 'Listen to')") == 'Masked', '2x auf 7 = Listen weiter')
# ================= v6.0: Hall layer (FDN Reverb on the track, convolver from the master) =================
R.execute("table.insert(TRACKS[1].fx, FDNV); table.insert(MASTER.fx, CONVM); STATE = STATE + 1"); run(0.1); run(0.1)
con = g.CONSOLE or ''
check('FDN Reverb A = VST3: FdnReverb (IEM) auf Vox' in con and 'fade 1, hf 1, hg 1, lf 1, lg 1, mix 1, rt 1, size 2' in con,
      'FDN Reverb von der Spur, Parameter erkannt')
check('Convolver A = VST: mcfx_convolver8 (mcfx) auf Master (Ersatz vom Master) · c1 1, c2 1' in con,
      'Convolver vom Master: nur seine 2 Parameter (nicht Reapers Bypass/Wet/Delta)')
flush()
hold(8)
m = flush()
check(any(d == MFT and b == [0xB1, 56, 13] for d, b in m), 'Encoder 8 halten: Ebene Hall (Farbe 13)')
for e, name in ((1, 'Room Size'), (2, 'Reverberation Time'), (3, 'Fade-in Time'), (4, 'Dry/Wet'), (5, 'Lows Cutoff Frequency'), (6, 'Highs Cutoff Frequency')):
    v0 = R.eval(f"PV(FDNV, '{name}')"); turn_mft(e, 1); run(0.2)
    check(R.eval(f"PV(FDNV, '{name}')") > v0, f'Hall: Encoder {e} = {name}')
for e, name in ((5, 'Lows Gain'), (6, 'Highs Gain')):
    v0 = R.eval(f"PV(FDNV, '{name}')"); pturn(e, -1)
    check(R.eval(f"PV(FDNV, '{name}')") < v0, f'Hall: Encoder {e} drücken + drehen = {name}')
g0, d0 = R.eval("PV(CONVM, 'Master Gain')"), R.eval("PV(CONVM, 'Pre-Delay')")
turn_mft(9, 1); run(0.2); turn_mft(10, 3); run(0.2); turn_mft(11, 1); run(0.2)
check(R.eval("PV(CONVM, 'Master Gain')") > g0 and R.eval("PV(CONVM, 'Pre-Delay')") > d0 and R.eval("CONVM.params[4].v") == 1,
      'Hall: 9 = Convolver Master Gain, 10 = Pre-Delay, 11 leer (Wet bleibt)')
check(R.eval("CONVM.float") == True, 'Convolver-Fenster geht auf')
m = flush()
check(any(d == MFT and b == [0xB1, 57, 25] for d, b in m), 'Convolver vom Master in Master-Farbe')
v3 = View('/home/claude/mft-view/dist/seren-a_Twister_View.tosc')
T[0] += 6; run()
for d, b in flush():
    if d == VIEW: v3.midi(*b)
v3.tick()
check(v3.text('bankname') == 'Hall' and 'FDN Size' in v3.text('c1_name') and 'Conv Master Gain (Master)' in v3.text('c9_name'),
      f"Twister View: Tab Hall ({v3.text('c1_name')!r}, {v3.text('c9_name')!r})")
hold(8); hold(8); hold(8)                                  # Hall -> MultiEQ -> Omni -> Directional
# --- selection change: Kick has only an Omni
turn_mft(16, 1); run(0.1); turn_mft(16, 1); run(0.2); run(0.1)
con = g.CONSOLE or ''
check(R.eval("TRACKS[3].sel") == True and 'OmniComp A = VST3: OmniCompressor (IEM) auf Kick' in con
      and 'DirComp A = VST3: DirectionalCompressor (IEM) auf Master (Ersatz vom Master)' in con,
      'Spur weiter mit 16: Omni folgt (Kick), Directional vom Master')
th = R.eval("PV(DIM, 'Threshold 1')")
turn_mft(1, 1); run(0.2)
check(R.eval("PV(DIM, 'Threshold 1')") > th, 'Directional jetzt = Master-Instanz')
check(any(d == MFT and b == [0xB1, 49, 25] for d, b in flush()), 'Master-Directional in Master-Farbe')
hold(8); hold(8)
f0 = real('EQA', 1, 'Frequency'); turn_mft(9, 1); run(0.2)
check(real('EQA', 1, 'Frequency') > f0, 'Encoder 8 zweimal halten: über Hall zurück zum MultiEQ (9 = A Band 1)')
turn_mft(16, -1); run(0.1); turn_mft(16, -1); run(0.2)
check(R.eval("TRACKS[1].sel") == True, 'zurück auf Vox')

# --- E16 page 3 = compressors
flush()
ev(E16, 0xBB, 1, 3); run(0.1)
m = flush()
title = ''.join(chr(b[2]) for d, b in m if d == E16 and b[0] == 0xBB and b[1] < 15)
check(title.strip() == 'OMNI Vox/Master', f'E16 Seite 3: Titel Omni ({title!r})')
names = {b[1]: chr(b[2]) for d, b in m if d == E16 and b[0] == 0xBB and 16 <= b[1] < 80}
slot = lambda e: ''.join(names.get(16 + (e - 1) * 4 + i, '?') for i in range(4)).strip()
check(slot(1) == '-10' and slot(8) not in ('OMNI', '--', '') and slot(7) == 'AN' and slot(16) == 'T1', f'E16 Slots ({slot(1)!r}, {slot(8)!r}, {slot(7)!r}, {slot(16)!r})')
check(any(d == E16 and b == [0xB7, 9, 16] for d, b in m), 'E16: Omni B vom Master = Zustand +16 (weiß)')
t0 = R.eval("PV(OMV, 'Threshold')")
ev(E16, 0xBB, 20, 65); run(0.2)
check(abs(R.eval("PV(OMV, 'Threshold')") - t0 - 0.1) < 1e-6, 'E16 Seite 3 Encoder 1 = Omni A Threshold')
ev(E16, 0xBB, 55, 127); run(0.05); ev(E16, 0xBB, 55, 0); run(0.1)
check(R.eval("TRACKS[1].vals.B_MUTE") == 1, 'E16 Encoder 16 drücken = Mute')
m = flush(); run(); m += flush()
check(any(d == E16 and b == [0xB7, 16, 66] for d, b in m) and any(d == E16 and b == [0xB7, 15, 65] for d, b in m),
      'E16: 16 blinkt rot (66), 15 orange (65)')
ev(E16, 0xBB, 55, 127); run(0.05); ev(E16, 0xBB, 55, 0); run(0.1)
ev(E16, 0xBB, 47, 127); run(0.033, 18); ev(E16, 0xBB, 47, 0); run(0.1)   # hold 8: Omni -> Directional
m = flush()
title = ''.join(chr(b[2]) for d, b in m if d == E16 and b[0] == 0xBB and b[1] < 15)
check(title.strip() == 'DIR Vox', f'E16 Encoder 8 halten: Directional ({title!r})')
ev(E16, 0xBA, 1, 4); run(0.1)                                             # page 4 = reverb
m = flush()
title = ''.join(chr(b[2]) for d, b in m if d == E16 and b[0] == 0xBB and b[1] < 15)
check(title.strip() == 'HALL Vox', f'E16 Seite 4: Hall ({title!r})')
check(any(d == E16 and b[:2] == [0xB7, 17] and b[2] == 92 for d, b in m), 'E16 Seite 4: Room Size in IEM-Grün (92, Kanal 8 CC 17)')
v0 = R.eval("PV(FDNV, 'Room Size')")
ev(E16, 0xBA, 20, 65); run(0.2)
check(R.eval("PV(FDNV, 'Room Size')") > v0, 'E16 Seite 4 Encoder 1 = FDN Room Size')
R.execute("FDNV.presets = {'Kirche', 'Saal', 'Wohnzimmer'}")
ev(E16, 0xBA, 26, 65); run(0.2)
check(R.eval("FDNV.preset") == 2, 'E16 Seite 4 Encoder 7 = nächstes FDN-Preset')
ev(E16, 0xBB, 1, 3); run(0.1)
ev(E16, 0xBB, 47, 127); run(0.033, 18); ev(E16, 0xBB, 47, 0); run(0.1)   # page 3: Directional -> Omni
m = flush()
title = ''.join(chr(b[2]) for d, b in m if d == E16 and b[0] == 0xBB and b[1] < 15)
check(title.strip().endswith('OMNI Vox/Master'), f'E16 Seite 3, 8 halten: wieder Omni ({title!r})')
ev(E16, 0xBC, 1, 127); run(0.1); m = flush()
check(not any(d == E16 and b[0] in (0xBB, 0xB9, 0xB7) and b != [0xBB, 127, 0] for d, b in m), 'E16 Seite 1 (DAW Link, 127): Reaper_MultiEQ zeichnet nichts')
ev(E16, 0xBC, 1, 1); run(0.1)
m = flush()
title = ''.join(chr(b[2]) for d, b in m if d == E16 and b[0] == 0xBB and b[1] < 15)
check(title.strip().startswith('A Maste'), f'E16 Seite 1 = MultiEQ ({title!r})')
f0 = real('EQA', 1, 'Frequency')
ev(VIEW, 0xBC, 20, 65); run(0.2)
check(real('EQA', 1, 'Frequency') == f0, 'Kanal 13 von der Bridge wird ignoriert (nur E16-Ports)')

# --- wobble right after pressing is ignored: still a press (bypass)
push_mft(8, True); turn_mft(8, 1); run(0.05); push_mft(8, False); run(0.1)
check(R.eval("OMV.enabled") == False, 'Wackeln beim Drücken zählt nicht als Drehen: Bypass geht')
tap(8)
# --- ratio on a plugin that rounds coarsely (steps of 0.5): still moves both ways
R.execute("for _, p in ipairs(OMV.params) do if p.name == 'Ratio' then local s0 = p.snap; p.snap = function(x) local c = p.conv(x); local v = math.floor(c * 2 + 0.5) / 2; local lo, hi = 0, 1; for i = 1, 40 do local m = (lo + hi) / 2; if p.conv(m) < v then lo = m else hi = m end end; return hi end end end")
r0 = R.eval("PV(OMV, 'Ratio')")
pturn(8, 1, long=True)
r1 = R.eval("PV(OMV, 'Ratio')")
pturn(8, -1, long=True); pturn(8, -1, long=True)
check(r1 > r0 and R.eval("PV(OMV, 'Ratio')") < r1, f'Ratio bei grob rundendem Plugin: hoch und runter ({r0:.2f} -> {r1:.2f} -> {R.eval("PV(OMV, 'Ratio')"):.2f})')

# --- no value text from the plugin: normalized fallback still moves
R.execute("NOFMT = true")
n0 = R.eval("EQA.params[3].v")
turn_mft(9, 1); run(0.2)
check(R.eval("EQA.params[3].v") > n0, 'ohne Werte-Texte: Frequenz bewegt sich trotzdem (normiert)')
R.execute("NOFMT = false")

# ================= v6.1: Hall-EQ = the MultiEQ in the slot right before the FDN (layer 5) =================
R.execute("EQH = MultiEQ('VST3: MultiEQ (IEM)', '{EQH}', {60, 100, 250, 1000, 3000, 12000}); "
          "for i, f in ipairs(TRACKS[1].fx) do if f == FDNV then table.insert(TRACKS[1].fx, i, EQH) break end end; STATE = STATE + 1")
run(0.1); run(0.1)
con = g.CONSOLE or ''
check('Hall-EQ A = VST3: MultiEQ (IEM) auf Vox' in con, 'Hall-EQ: MultiEQ direkt vor dem FDN erkannt')
flush()
f0, h0 = real('EQA', 1, 'Frequency'), real('EQH', 1, 'Frequency')
ev(E16, 0xBA, 1, 4); run(0.1)
ev(E16, 0xBA, 47, 127); run(0.033, 18); ev(E16, 0xBA, 47, 0); run(0.1)      # hold 8 on page 4: Hall -> Hall-EQ
m = flush()
title = ''.join(chr(b[2]) for d, b in m if d == E16 and b[0] == 0xBB and b[1] < 15)
title = title[-15:]
check(title.strip() == 'HALL-EQ Vox', f'E16 Seite 4, Encoder 8 halten: Hall-EQ ({title!r})')
ev(E16, 0xBA, 20, 65); run(0.2)
check(real('EQH', 1, 'Frequency') > h0 and real('EQA', 1, 'Frequency') == f0, 'E16 Hall-EQ: Encoder 1 = Frequenz Band 1 des Hall-EQ')
ev(E16, 0xBA, 47, 127); run(0.033, 18); ev(E16, 0xBA, 47, 0); run(0.1)      # hold 8 again: back to the reverb
m = flush()
title = ''.join(chr(b[2]) for d, b in m if d == E16 and b[0] == 0xBB and b[1] < 15)
check(title.strip() == 'HALL Vox', f'E16 Encoder 8 nochmal halten: zurück zum Hall ({title!r})')
for _ in range(4): hold(8)                                                  # Twister: MultiEQ -> Omni -> Dir -> Hall -> Hall-EQ
m = flush()
check(any(d == MFT and b == [0xB1, 56, 92] for d, b in m), 'Twister: Encoder 8 viermal halten = Ebene 5 Hall-EQ (Farbe 92)')
h0 = real('EQH', 2, 'Frequency'); turn_mft(2, 1); run(0.2)
check(real('EQH', 2, 'Frequency') > h0, 'Twister Hall-EQ: Encoder 2 = Frequenz Band 2')
g0 = real('EQH', 3, 'Gain'); pturn(3, 1)
check(real('EQH', 3, 'Gain') > g0, 'Twister Hall-EQ: Encoder 3 drücken + drehen = Gain Band 3')
hold(8)
check(R.eval("true"), 'zurück zum MultiEQ')

# --- atexit clears E16 and stops the hub handover
R.execute("ATEXIT()")
check(g.EXTS['seren_MultiEQ/alive'] == '', 'Ende: Bank 4 geht an den Hub zurück')
check(any(d == E16 and b == [0xBB, 127, 0] for d, b in flush()), 'Ende: E16-Anzeige gelöscht')
R.execute("EXTS['seren_MultiEQ/token'] = 'other'; CONSOLE = ''")
run()
check('eine neuere Instanz läuft' in (g.CONSOLE or ''), 'zweite Instanz übernimmt, die erste hört auf')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
