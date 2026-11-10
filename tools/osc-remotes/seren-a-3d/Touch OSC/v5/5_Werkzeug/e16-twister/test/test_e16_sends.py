"""v8.0 end to end: Reaper_E16_Twister.lua (Reaper mock) <-> seren_E16.lua (scene on the E16 mock) and the Twister.
E16 page 1 = Sends / Ziele / Spur / Menü, Twister bank 4 layer 6 = Sends."""
import importlib, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'Reaper_E16_Twister.lua')
SCENE = os.path.join(HERE, '..', 'seren_E16.lua')
lua = importlib.import_module("lupa.lua54")
fails = 0


def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m)
    fails += 0 if c else 1


MFT, VIEW, E16 = 1, 2, 3
SETUP = '''
OUTS = {"IAC Bus 1", "Midi Fighter Twister", "TouchOSC Bridge", "OXI E16"}
INS  = {"Keystation", "Midi Fighter Twister", "TouchOSC Bridge", "OXI E16"}
MASTER = {name = "MASTER", guid = "{M}", fx = {}, rec = {}, vals = {D_VOL = 1}}
K = {name = "RVB Kirche", guid = "{K}", fx = {}, peak = 0.5, vals = {I_NCHAN = 16}}
RA = {name = "RVB Raum", guid = "{R}", fx = {}, peak = 0, vals = {I_NCHAN = 16}}
P = {name = "RVB Platte", guid = "{P}", fx = {}, peak = 0, vals = {I_NCHAN = 2}}
V = {name = "Vox", guid = "{V}", sel = true, fx = {}, vals = {B_MAINSEND = 1}}
D = {name = "Drums", guid = "{D}", fx = {}, vals = {B_MAINSEND = 1}}
TRACKS = { V, D, K, RA, P }
V.sends = { {dest = K, D_VOL = 0.5, B_MUTE = 0, I_SENDMODE = 0}, {dest = RA, D_VOL = 0.25, B_MUTE = 0, I_SENDMODE = 0} }
'''


class Rig:
    def __init__(self, pre=''):
        self.R = lua.LuaRuntime()
        self.g = self.R.globals()
        self.R.execute(open(os.path.join(HERE, 'reaper_mock.lua')).read())
        self.R.execute(SETUP + pre)
        self.R.execute(open(SCRIPT, encoding='utf-8').read())
        self.E = lua.LuaRuntime()
        self.eg = self.E.globals()
        self.E.execute(f'E = dofile([[{os.path.join(HERE, "e16mock.lua")}]]); E.load([[{SCENE}]])')
        self.t = 0.0
        self.mft = {}
        self.run(0.2)

    def run(self, sec=0.033, n=1):
        for _ in range(n):
            self.t += sec
            self.R.execute(f'T = {self.t}; DEFER()')
            self.pipe()
            self.E.execute(f'E.run({int(sec * 1000)})')
            self.back()

    def pipe(self):
        out = self.g.OUT
        for i in range(1, len(out) + 1):
            m = out[i]
            b = [m.bytes[j] for j in range(1, len(m.bytes) + 1)]
            if m.dev == E16 and len(b) == 3 and 0xB0 <= b[0] <= 0xBF:
                self.E.execute(f'midi.onCC(0, {b[0] - 0xB0}, {b[1]}, {b[2]})')
            if m.dev == MFT and len(b) == 3:
                self.mft[(b[0], b[1])] = b[2]
        self.R.execute('OUT = {}')

    def back(self):
        sent = self.eg.E.sent
        for i in range(1, len(sent) + 1):
            m = sent[i]
            self.R.execute(f'evIn({E16}, {m.st}, {m.d1}, {m.d2})')
        self.E.execute('E.sent = {}')

    def turn(self, e, inc=1):
        self.E.execute(f'controller.onEncoderTurn{{id = {e}, index = {e}, page = E.page, increment = {inc}}}')
        self.back(); self.run(0.05)

    def press(self, e):
        self.E.execute(f'controller.onEncoderPress{{id = {e + 16}, index = {e}, page = E.page}}')
        self.back(); self.run(0.05, 2)

    def release(self, e):
        self.E.execute(f'controller.onEncoderRelease{{id = {e + 16}, index = {e}, page = E.page, held_ms = 80}}')
        self.back(); self.run(0.05)

    def tap(self, e, n=1, settle=True):
        for _ in range(n):
            self.press(e); self.release(e)
        if settle:
            self.run(0.1, 6)

    def hold(self, e):
        self.press(e); self.run(0.1, 6); self.release(e); self.run(0.1, 14)

    def label(self, i): return self.eg.E.labels[i] or ''
    def ring(self, i):
        r = self.eg.E.rings[i]
        return (r.v // 129, r.c) if r else None
    def ringAny(self, i):                       # blinking ring (v8.5): the lit phase
        for _ in range(10):
            r = self.ring(i)
            if r: return r
            self.run(0.1)
    def title(self): return self.eg.E.title
    def val(self, tr, k): return self.R.eval(f'{tr}.vals.{k} or 0')
    def snd(self, tr, i, k): return self.R.eval(f'{tr}.sends[{i}].{k}')
    def nsends(self, tr): return self.R.eval(f'#{tr}.sends')
    # Twister
    def mturn(self, e, d): self.R.execute(f'evIn({MFT}, 0xB0, {48 + e}, {64 + d})'); self.run(0.05)
    def mpress(self, e, down): self.R.execute(f'evIn({MFT}, 0xB1, {48 + e}, {127 if down else 0})'); self.run(0.05)
    def mhold(self, e): self.mpress(e, True); self.run(0.1, 6); self.mpress(e, False); self.run(0.1, 2)


rig = Rig()
con = rig.g.CONSOLE or ''
check('3 Ziel(e)' in con and 'E16+Twister v8.11.1 geladen' in con, f'Start: 3 Hallspuren über Präfix RVB gefunden')
rig.run(0.1, 5)
check(rig.title() == 'Vox', f'Seite 1 Titel = ausgewählte Spur ({rig.title()})')
check([rig.label(i) for i in (1, 2, 3)] == ['Kirc', 'Raum', 'Plat'], f'Sends 1-3 = Hallspuren ohne Präfix ({[rig.label(i) for i in (1, 2, 3)]})')
check([rig.label(i) for i in (9, 10, 11)] == ['Kirc', 'Raum', 'Plat'], 'Ziele 9-11 = dieselben Hallspuren (Layout 1-8 / 9-16)')
check(rig.label(16) == 'MAST' and rig.label(8) == 'Vox', f'8 = Spur, 16 = Master (seit v8.5) ({rig.label(16)}, {rig.label(8)})')
check(rig.ring(1) and rig.ring(1)[1] == 83, f'Send-Ring Cyan 83 statt Blau ({rig.ring(1)})')
check(rig.ring(3) is None, 'Platte: kein Send → Ring aus')
check(rig.ring(16) and rig.ring(16)[1] == 36 and rig.ring(8)[1] == 34, f'Master Pfirsich 36, Spur Weiß 34 ({rig.ring(16)}, {rig.ring(8)})')
check(rig.ring(9) and rig.ring(9)[1] == 50 and rig.ring(9)[0] > 100, f'Ziel Kirche: Metering pink 50 ({rig.ring(9)})')

v0 = rig.snd('V', 1, 'D_VOL')
rig.turn(1, 1)
check(rig.snd('V', 1, 'D_VOL') > v0 and abs(20 * __import__('math').log10(rig.snd('V', 1, 'D_VOL') / v0) - 0.3) < 0.01, 'Encoder 1: Send Kirche +0,3 dB')
rig.tap(1)
check(rig.snd('V', 1, 'I_SENDMODE') == 3, 'Push 1 (Pre/Post): Pre-Fader (Post-FX)')
check(rig.ring(1)[1] == 34, f'Pre-Send: Ring weiß ({rig.ring(1)})')
rig.tap(1, 2)
rig.run(0.1, 12)
check(rig.snd('V', 1, 'I_SENDMODE') == 3 and rig.R.eval('K.sel') and not rig.R.eval('V.sel'), '2× Push 1: Sprung zur Hallspur, Pre/Post unverändert')
rig.run(0.1, 3)
check(rig.title() == '<Vox', f'Hallspur gewählt: Sends gehören weiter zu Vox ({rig.title()})')
v0 = rig.snd('V', 2, 'D_VOL')
rig.turn(2, 2)
check(rig.snd('V', 2, 'D_VOL') > v0, 'von der Hallspur aus: Encoder 2 = Send Vox → Raum')
rig.turn(3, 1)
check(rig.nsends('V') == 3 and rig.R.eval('V.sends[3].dest == P'), 'fehlender Send: beim ersten Drehen nach oben angelegt')

k0 = rig.val('K', 'D_VOL') or 1
rig.turn(9, -3)
check(rig.R.eval('K.vals.D_VOL') < 1, 'Encoder 9: Fader Kirche runter')
check(rig.ring(9)[1] == 18, f'nach dem Drehen: Fader-Wert hellblau ({rig.ring(9)})')
rig.run(0.1, 15)
check(rig.ring(9)[1] == 50, 'nach 1,2 s wieder Metering pink')
rig.tap(9)
check(rig.R.eval('K.vals.B_MUTE') == 1, 'Push 9: Hallspur stumm')
rig.tap(9)

rig.R.execute('reaper.SetOnlyTrackSelected(V)'); rig.run(0.1, 3)
rig.turn(16, 1); rig.run(0.1, 3)
check(rig.R.eval('MASTER.vals.D_VOL') == 1 and not rig.R.eval('V.sel'), 'Encoder 16 drehen: nächste Spur, Master bleibt (wie MultiEQ)')
rig.R.execute('reaper.SetOnlyTrackSelected(V)'); rig.run(0.1, 3)
rig.press(16); rig.turn(16, -2); rig.release(16); rig.run(0.1, 3)
check(rig.R.eval('MASTER.vals.D_VOL') < 1, 'Encoder 16 drücken + drehen: Master-Volume')
rig.press(16); rig.turn(16, 30); rig.release(16); rig.run(0.1, 3)
check(abs(rig.R.eval('MASTER.vals.D_VOL') - 1) < 1e-9, f'Master höchstens 0 dB ({rig.R.eval("MASTER.vals.D_VOL")})')
for _ in range(12): rig.turn(1, 60)
check(0.99 < rig.snd('V', 1, 'D_VOL') <= 1.0000001, f'Send höchstens 0 dB ({rig.snd("V", 1, "D_VOL")})')
rig.tap(16, 2)
check(rig.R.eval('MASTER.vals.B_MUTE') == 1, '2× Push 16: Master stumm')
rig.tap(16, 2)
rig.turn(8, -2)
check(rig.R.eval('V.vals.D_VOL') < 1, 'Encoder 8: Spur-Volume')
rig.tap(8)
check(rig.R.eval('V.vals.I_SOLO') > 0, 'Push 8: Solo')
check(rig.ringAny(8)[1] == 44, f'Solo: Ring gelb, blinkt ({rig.ring(8)})')
rig.tap(8)
rig.tap(8, 3)
check(rig.R.eval('V.vals.D_VOL') == 0, '3× Push 8: Spur -inf')
rig.tap(8, 3)
check(rig.R.eval('V.vals.D_VOL') == 1, '3× Push 8 nochmal: 0 dB')
rig.press(8); rig.turn(8, 1); rig.release(8); rig.run(0.1, 5)
check(rig.R.eval('D.sel'), 'Drücken + Drehen 8: nächste Spur')
rig.R.execute('reaper.SetOnlyTrackSelected(V)'); rig.run(0.1, 3)

# sub-pages: hold 16
rig.hold(16)
check(rig.title() == '1 Vox' and rig.label(1) == 'Vol' and rig.label(2) == 'Pan', f'16 halten: Unterseite Spur ({rig.title()}, {rig.label(1)})')
rig.hold(16)
check(rig.title() == 'MENUE E16' and rig.label(1) == 'LAYT' and rig.label(16) == 'SPUR', f'16 halten: Menü ({rig.title()}, {rig.label(1)})')
rig.turn(1, 1)
check(rig.g.EXTS['seren_E16/layout'] == 'pages', 'Menü Encoder 1: Layout = Seiten')
rig.turn(3, 1)
check(rig.g.EXTS['seren_E16/push'] == 'mute', 'Menü Encoder 3: Push = Mute')
rig.turn(6, 1)
check(rig.g.EXTS['seren_E16/cSend'] == 'gruen' and rig.ring(6)[1] == 92, f'Menü: Send-Farbe Grün, Ring zeigt die Farbe ({rig.ring(6)})')
rig.turn(6, -1)
rig.hold(16); rig.run(0.1, 3)
check(rig.title() == 'Vox' and rig.label(1) == 'Kirc' and rig.label(3) == 'Plat' and rig.label(9) == '' and rig.label(15) == 'Vox' and rig.label(16) == 'MAST',
      f'Layout Seiten: Sends 1-14, 15 = Spur, 16 = Master ({rig.label(1)}, {rig.label(9)!r}, {rig.label(15)})')
rig.tap(2)
check(rig.snd('V', 2, 'B_MUTE') == 1, 'Push = Mute: Send Raum stumm')
check(rig.ringAny(2)[1] == 57, f'stummer Send: Ring rot und blinkt ({rig.ring(2)})')
rig.tap(2)
rig.hold(16)
check(rig.label(1) == 'Kirc' and rig.label(16) == 'MAST' and rig.ring(1) and rig.ring(1)[1] in (50, 18), 'nächste Unterseite: Ziele 1-14')
rig.turn(1, -1)
check(rig.R.eval('K.vals.D_VOL') < k0, 'Ziele-Seite: Encoder 1 = Fader Kirche')

# targets = the track's own sends
rig.R.execute('EXTS["seren_E16/targets"] = "sends"; EXTS["seren_E16/layout"] = "split"; EXTS["seren_E16/rev"] = "x1"')
rig.run(0.1, 4)
rig.R.execute('reaper.SetOnlyTrackSelected(D)'); rig.run(0.1, 15)
check(rig.label(1) == '' and rig.title() == 'Drums', f'Ziele = Sends der Spur: Drums hat keine Sends ({rig.label(1)!r}, {rig.title()!r})')
rig.R.execute('reaper.SetOnlyTrackSelected(V)'); rig.run(0.1, 4)
check([rig.label(i) for i in (1, 2, 3, 4)] == ['Kirc', 'Raum', 'Plat', ''], f'Vox: Ziele = ihre 3 Sends ({[rig.label(i) for i in (1, 2, 3, 4)]})')

# assigned targets (project), old reverb-remote assignment as fallback
rig2 = Rig('EXTS["E16_REVERB_REMOTE/guids"] = "{P},{K}"')
rig2.run(0.1, 4)
check([rig2.label(i) for i in (1, 2, 3)] == ['Plat', 'Kirc', ''], f'alte Reverb-Remote-Zuweisung übernommen ({[rig2.label(i) for i in (1, 2, 3)]})')
rig3 = Rig('PEXT["seren_E16/targets"] = "{RA}"; RA.guid = "{RA}"')
rig3.run(0.1, 4)
check(rig3.label(1) == 'Raum' and rig3.label(2) == '', 'Projekt-Zuweisung gewinnt')

# Twister layer 6
rig.R.execute('EXTS["seren_E16/targets"] = "assigned"; EXTS["seren_E16/push"] = "prepost"; EXTS["seren_E16/rev"] = "x2"')
rig.run(0.1, 3)
for _ in range(4):
    rig.mhold(8)
rig.run(0.1, 3)
check(rig.R.eval('SEREN_DBG.layer()') == 6, f"Twister: Ebene {rig.R.eval('SEREN_DBG.layer()')}")
check(rig.R.eval('true') and rig.mft.get((0xB1, 56)) == 1, f'Twister: 8 viermal halten → Ebene 6 Sends, Encoder 8 blau ({rig.mft.get((0xB1, 56))})')
check(rig.mft.get((0xB1, 50)) == 20 and rig.mft.get((0xB1, 49)) == 127, f'Twister: Send Raum Cyan 20, Send Kirche (Pre) Weiß 127 ({rig.mft.get((0xB1, 50))}, {rig.mft.get((0xB1, 49))})')
v0 = rig.snd('V', 1, 'D_VOL')
rig.mturn(1, -1)
check(rig.snd('V', 1, 'D_VOL') < v0, 'Twister Encoder 1 dreht den Send (runter, oben ist 0 dB)')
rig.mturn(9, -1)
check(rig.R.eval('K.vals.D_VOL') < k0 - 0.001, 'Twister Encoder 9 = Fader Kirche')
rig.mpress(15, True); rig.mpress(15, False); rig.run(0.1, 6)
check(rig.R.eval('V.vals.I_SOLO') > 0, 'Twister 15/16 bleiben wie im MultiEQ (Push 15 = Solo)')
rig.mpress(15, True); rig.mpress(15, False); rig.run(0.1, 6)
rig.mhold(8)
check(rig.mft.get((0xB1, 56)) == 127, 'Twister: 8 halten → zurück zum MultiEQ')

# more options
rig.R.execute('reaper.SetOnlyTrackSelected(V); EXTS["seren_E16/dbl"] = "1"; EXTS["seren_E16/push"] = "mute_pp"; EXTS["seren_E16/preFx"] = "1"; EXTS["seren_E16/rev"] = "x3"')
rig.run(0.1, 5)
rig.tap(8, 2)
check(rig.R.eval('V.vals.B_MAINSEND') == 0, '2x Spur (Option an): Master-Send aus')
rig.tap(8, 2)
check(rig.R.eval('V.vals.B_MAINSEND') == 1, '2x Spur nochmal: Master-Send an')
rig.tap(2, 2)
check(rig.snd('V', 2, 'I_SENDMODE') == 3, 'Push Mute + 2x Pre/Post: 2x = Pre')
rig.tap(2, 2)
check(rig.snd('V', 2, 'I_SENDMODE') == 1, 'Pre-FX an: 2x weiter = Pre-FX')
rig.tap(2, 2)
check(rig.snd('V', 2, 'I_SENDMODE') == 0, '2x weiter = Post')
rig.tap(2)
check(rig.snd('V', 2, 'B_MUTE') == 1, 'Push = Mute')
rig.tap(2)
# Twister without dedicated encoders: 15 / 16 become targets
rig.R.execute('EXTS["seren_E16/dedicated"] = "0"; EXTS["seren_E16/rev"] = "x4"')
rig.run(0.1, 3)
for _ in range(5):
    if rig.R.eval('SEREN_DBG.layer()') == 6: break
    rig.mhold(8)
solo0 = rig.R.eval('V.vals.I_SOLO')
rig.mpress(15, True); rig.mpress(15, False); rig.run(0.1, 6)
check(rig.R.eval('V.vals.I_SOLO') == solo0, 'Twister ohne feste Encoder: 15 ist kein Solo mehr')
rig.mturn(9, 1)
check(rig.R.eval('SEREN_DBG.layer()') == 6, 'Twister ohne feste Encoder: Encoder 9 = Ziel')
rig.mhold(8)
check(rig.R.eval('SEREN_DBG.layer()') == 1, 'Twister: 8 halten wechselt weiter die Ebene')
rig.R.execute('EXTS["seren_E16/dedicated"] = "1"; EXTS["seren_E16/rev"] = "x5"'); rig.run(0.1, 3)

# exit clears page 1
rig.g.OUT = rig.R.table()
rig.R.execute('ATEXIT()')
out = rig.g.OUT
msgs = [[out[i].bytes[j] for j in range(1, len(out[i].bytes) + 1)] for i in range(1, len(out) + 1)]
check([0xBF, 127, 0] in msgs, 'Ende: E16 Seite 1 gelöscht')

print('\nALL OK' if fails == 0 else f'\n{fails} FAILED')
sys.exit(1 if fails else 0)
