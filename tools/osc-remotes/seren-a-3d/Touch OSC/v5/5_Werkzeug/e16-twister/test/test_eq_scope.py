"""Reaper_MultiEQ.lua against the Reaper mock with two fake IEM MultiEQ: Twister bank 4 + E16 scene."""
import importlib, math, os
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'Reaper_E16_Twister.lua')
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

UMLB = {1: 'ä', 2: 'ö', 3: 'ü', 4: 'Ä', 5: 'Ö', 6: 'Ü', 7: 'ß', 8: '°'}
class View:            # minimal stand-in for the TouchOSC harness: decodes the view SysEx for bank 4
    def __init__(self, *a): self.t = {}; self.bank = None
    def midi(self, *b):
        b = list(b)
        if b[:3] != [0xF0, 0x7D, 0x4D]: return
        cmd = b[3]
        dec = lambda xs: ''.join(UMLB.get(x, chr(x)) for x in xs)
        if cmd in (1, 2) and b[4] == 3: self.t[f"c{b[5] + 1}_{'name' if cmd == 1 else 'val'}"] = dec(b[6:-1])
        if cmd == 6 and b[4] == 3: self.t['bankname'] = dec(b[5:-1])
    def tick(self): pass
    def text(self, k): return self.t.get(k, '')
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

R.execute("EXTS['seren_E16/twister'] = '0'")
R.execute("TRACKS[1].sel = false; TRACKS[2].sel = true")
R.execute(open(SCRIPT).read())
run()
con = g.CONSOLE or ''
check('MultiEQ (IEM) auf Mon' in con and 'MultiEQ (IEM) auf Master' not in con, f'Spur Mon gewählt: nur deren MultiEQ ({con[-200:]!r})')
R.execute("TRACKS[2].sel = false; TRACKS[3].sel = true"); R.execute("CONSOLE = ''")
for _ in range(80): run()
con = g.CONSOLE or ''
check('MultiEQ (IEM) auf' not in con.split('Kick')[-1] if False else ('MultiEQ (IEM) auf Master' not in con and 'MultiEQ (IEM) auf Mon' not in con), f'Spur ohne MultiEQ: kein MultiEQ, auch nicht vom Master ({con[-200:]!r})')
# fader limits: master (normal track) +6 dB
R.execute("EXTS['seren_E16/capTrack'] = '6'; MASTER.vals = MASTER.vals or {}; MASTER.vals.D_VOL = 1")
def pturn(e, d):
    push_mft(e, True); run(0.1); turn_mft(e, d); run(0.1); push_mft(e, False); run(0.1)
for _ in range(40): pturn(16, 3)
mv = R.eval("MASTER.vals.D_VOL")
check(1.99 < mv < 2.0 + 1e-6, f'Fader-Grenze +6 dB: Master bleibt bei +6 dB ({mv})')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED')
