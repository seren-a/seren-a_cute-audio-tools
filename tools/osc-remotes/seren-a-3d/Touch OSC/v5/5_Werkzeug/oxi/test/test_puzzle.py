"""Tests for Reaper_OXI_Puzzle.lua against a fake Reaper + fake OXI One MkII."""
import os, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'Reaper_OXI_Puzzle.lua')
HDR = bytes([0xF0, 0, 0x21, 0x5B, 1, 1])
fails = 0


def check(ok, msg):
    global fails
    print(('PASS ' if ok else 'FAIL ') + msg)
    if not ok:
        fails += 1


class Rig:
    def __init__(self, setup=''):
        self.L = lua54.LuaRuntime(unpack_returned_tuples=True, encoding=None)
        self.L.execute(open(os.path.join(HERE, 'fake_reaper.lua'), 'rb').read())
        self.L.execute(setup.encode())
        self.g = self.L.globals()
        self.L.execute(open(SCRIPT, 'rb').read())
        self.grid = {}
        self.leds = {}
        self.disp = None
        self.consumed = 0

    def run(self, n=1, dt=0.033):
        for _ in range(n):
            self.g.NOW = self.g.NOW + dt
            f = self.g.DEFER
            self.g.DEFER = None
            if f:
                f()
        self.decode()

    def out(self):
        o = self.g.OUT
        return [bytes(o[i][2]) for i in range(1, len(o) + 1)]

    def decode(self):
        msgs = self.out()
        for m in msgs[self.consumed:]:
            if not m.startswith(HDR):
                continue
            cmd = m[6]
            if cmd == 1:
                d = m[7:-1]
                for k in range(0, len(d), 8):
                    y, x = d[k], d[k + 1]
                    rgb = tuple((d[k + 2 + 2 * c] << 4) | d[k + 3 + 2 * c] for c in range(3))
                    self.grid[(7 - y, x)] = rgb          # OXI y 0 = bottom row
            elif cmd == 2:
                self.leds[m[7] * 16 + m[8]] = m[10]
            elif cmd == 3:
                self.disp = m[7:-1]
        self.consumed = len(msgs)

    def screen(self):
        rows = [[' '] * 128 for _ in range(64)]
        d = self.disp
        pos = 0
        for y in range(0, 64, 8):
            for x in range(128):
                n1, n2 = d[pos], d[pos + 1]
                pos += 2
                for bit in range(8):
                    on = (n1 >> (bit - 4)) & 1 if bit > 3 else (n2 >> bit) & 1
                    if on:
                        rows[y + bit][x] = '#'
        return [''.join(r) for r in rows]

    def text_lines(self):
        """OCR the 8 text lines back using the script's own font."""
        font = self.L.eval('FONT_FOR_TEST')
        glyph = {}
        for c in font.keys():
            rows = [font[c][i] for i in range(1, 9)]
            glyph[tuple(rows)] = c
        scr = self.screen()
        lines = []
        for base in (0, 9, 18, 34, 43, 55):
            s = ''
            for k in range(21):
                rows = []
                for rr in range(8):
                    v = 0
                    for col in range(5):
                        x = k * 6 + col + (1 if base in (0, 55) else 0)
                        on = scr[base + rr][x] == '#' if x < 128 and base + rr < 64 else False
                        v = (v << 1) | (1 if on else 0)
                    rows.append(v)
                c = glyph.get(tuple(rows))
                inv = glyph.get(tuple((~v) & 31 for v in rows))
                if base in (0, 55):
                    c = inv if inv is not None else c
                s += chr(c) if c is not None else '?'
            lines.append(s.rstrip())
        return lines

    def pad(self, row, col, wait=0.1):
        self.g.INPUT(bytes([0x90, (7 - row) * 16 + col, 100]))
        self.g.INPUT(bytes([0x80, (7 - row) * 16 + col, 0]))
        self.run(1)
        self.run(max(1, int(wait / 0.033)))

    def btn(self, n, down=True):
        self.g.INPUT(bytes([0x91 if down else 0x81, n, 127 if down else 0]))
        self.run(1)

    def press(self, n):
        self.btn(n, True)
        self.btn(n, False)

    def knob(self, e, d):
        self.g.INPUT(bytes([0xB0, e - 1, d & 127]))
        self.run(1)

    def enc_push(self, e, kind):
        n = [16, 20, 24, 28][e - 1]
        if kind == 'long':
            self.btn(n, True)
            self.run(20)
            self.btn(n, False)
        elif kind == 'double':
            self.press(n)
            self.press(n)
        else:
            self.press(n)
        self.run(12)

    def tr(self, i):
        return self.g.TRACKS[i]


SETUP = r'''
local t1 = MK("Vox", 0x1000000 | 0x0000FF, 4)      -- red
local t2 = MK("Gitarre", 0x1000000 | 0x00FF00, 3)  -- green
local t3 = MK("Leer", 0, 0)
local t4 = MK("Bus", 0x1000000 | 0xFF0000, 1)
t4.vals.I_FOLDERDEPTH = 1
for i = 5, 12 do MK("Spur " .. i, 0, 2) end
local h = MK("Hall", 0x1000000 | 0xFFFF00, 0)
local d = MK("Delay", 0, 0)
for k = 1, 6 do ADDSEND(t2, k <= 3 and h or d, 0.5) end
t1.fx = { "EQ", "Comp" }
MARKERS = { { rgn = false, pos = 0, name = "Intro" }, { rgn = true, pos = 4, rend = 8, name = "Vers" } }
t1.items[2].color = 0x1000000 | 0x00FFFF
reaper.SetExtState('seren_OXI', 'cells', 'items', true)   -- the old tests: one field per item
reaper.SetExtState('seren_OXI', 'markerKind', 'both', true)
'''

rig = Rig(SETUP)
rig.L.execute(b'FONT_FOR_TEST = nil')
# expose the font: re-run the font chunk from the script source
src = open(SCRIPT, encoding='utf-8').read()
start = src.index('local FONT = {')
end = src.index('\n}\n', start) + 3
rig.L.execute(src[start:end].replace('local FONT', 'FONT_FOR_TEST').encode('utf-8'))
rig.run(5)
out = rig.out()
check(out[0] == HDR + bytes([6, 0x55, 0xF7]) and rig.g.ATEXIT is not None, 'Start: OXI in den Remote-Modus geschaltet')

# grid: track colours, items
g = rig.grid
check(g.get((0, 0)) == (9, 0, 0) or g.get((0, 0)) == (15, 0, 0), f'Zeile 1, Spalte 1 = erstes Item in Spurfarbe rot ({g.get((0, 0))})')
check(g.get((0, 1)) == (9, 9, 0), f'Item 2 in eigener Item-Farbe (gelb) ({g.get((0, 1))})')
check(g.get((0, 3)) not in (None, (0, 0, 0)) and g.get((0, 4)) in (None, (0, 0, 0)), 'Vox: 4 Items, Feld 5 dunkel')
check(g.get((2, 0)) not in (None, (0, 0, 0)), f'leere Spur: Spalte 1 zeigt die Spur dennoch ({g.get((2, 0))})')
check(g.get((2, 1)) in (None, (0, 0, 0)), 'leere Spur: sonst dunkel')

# single push = select track + item
rig.pad(1, 2)
t2 = rig.tr(2)
check(t2.sel and t2[b'items'][3].sel and not t2[b'items'][1].sel, 'Push auf Gitarre Item 3: Spur und Item ausgewählt')
check(rig.grid.get((1, 2)) == (0, 255, 0), f'ausgewähltes Item leuchtet voll ({rig.grid.get((1, 2))})')
lines = rig.text_lines()
check(lines[0].startswith('PUZZLE Items') and lines[1] == '2 Gitarre' and lines[2] == 'Gitarre 3', f'Display: Kopf, Spur, Item ({lines[:3]})')
check(lines[3].startswith('Gain F-In F-OutSpur'.replace('F-OutSpur', 'F-Out Spur')[:4]), f'Display: Encoder-Namen ({lines[3]})')

# double push = loop to item
rig.pad(1, 1, wait=0.05)
rig.pad(1, 1)
loop = rig.g.LOOP
check(abs(loop[1] - 2.0) < 1e-6 and abs(loop[2] - 3.5) < 1e-6 and rig.g.CURSOR == 2.0, f'Doppel-Push: Loop/Cycle = Item, Cursor an den Anfang ({loop[1]}, {loop[2]})')

# shift + push = mute
rig.btn(17, True)
rig.pad(1, 0)
rig.btn(17, False)
check(t2[b'items'][1].vals.B_MUTE == 1, 'Shift + Push: Item stumm')
rig.btn(17, True); rig.pad(1, 0); rig.btn(17, False)
check(t2[b'items'][1].vals.B_MUTE == 0, 'Shift + Push nochmal: Item wieder an')

# encoders state 1
rig.pad(1, 2)
rig.knob(1, 2)
check(abs(rig.g.TRACKS[2][b'items'][3].vals.D_VOL - 10 ** (1 / 20)) < 1e-6, 'Encoder 1: Item-Gain +1 dB (2 Rasten)')
rig.knob(2, 3)
check(abs(t2[b'items'][3].vals.D_FADEINLEN - (0.01 + 0.12)) < 1e-6, f'Encoder 2: Fade-in länger (schnell gedreht x4) ({t2[b'items'][3].vals.D_FADEINLEN})')
rig.knob(3, -1)
check(abs(t2[b'items'][3].vals.D_FADEOUTLEN - 0.0) < 1e-6, 'Encoder 3: Fade-out kürzer, nicht unter 0')
rig.run(30)
check('OXI: Item' in [rig.g.UNDO[i].decode() for i in range(1, len(rig.g.UNDO) + 1)], 'Undo-Punkt nach dem Drehen')
rig.knob(4, 1)
lines = rig.text_lines()
check(lines[4].split()[-1] == '2/14', f'Encoder 4: Ansicht eine Spur weiter ({lines[4]})')
check(rig.grid.get((0, 0)) == (0, 15, 0) or rig.grid.get((0, 0)) == (0, 9, 0), f'Zeile 1 zeigt jetzt Gitarre ({rig.grid.get((0, 0))})')
rig.knob(4, -1)

# encoder pushes (state 1)
cmds = lambda: [rig.g.CMDS[i] for i in range(1, len(rig.g.CMDS) + 1)]
rig.enc_push(1, 'single')
check(cmds()[-1] == 53001, 'Encoder 1 Push: _SWS_TAKESCHANMODE0')
rig.enc_push(2, 'single')
check(cmds()[-1] == 53004, 'Encoder 2 Push: _SWS_TAKESCHANMODE3')
rig.enc_push(3, 'single')
check(cmds()[-2:] == [40289, 53100] and all(it.sel for it in t2[b'items'].values()), 'Encoder 3 Push: alle Items der Spur + _BR_NORMALIZE_LOUDNESS_ITEMS23')
c0 = len(cmds())
rig.enc_push(4, 'single')
check(len(cmds()) == c0, 'Encoder 4 Push: Zoom auf Item (keine Reaper-Aktion nötig)')

# copy/paste FX (vox -> spur 5)
rig.pad(0, 0)
rig.enc_push(1, 'double')
check('FX kopiert' in ''.join(rig.text_lines()), 'Encoder 1 Doppel: FX-Kette kopiert')
rig.pad(4, 0)
rig.enc_push(1, 'long')
check(list(rig.tr(5).fx.values()) == [b'EQ', b'Comp'], 'Encoder 1 lang: FX-Kette eingefügt')
rig.enc_push(3, 'long')
check(len(rig.tr(5).fx) == 0, 'Encoder 3 lang: FX-Kette entfernt')

# copy / replace / remove sends
rig.pad(1, 0)
rig.enc_push(2, 'double')
rig.pad(4, 0)
rig.enc_push(2, 'long')
check(len(rig.tr(5).sends) == 6 and rig.tr(5).sends[1].D_VOL == 0.5, 'Encoder 2 Doppel/lang: Sends kopiert und ersetzt')
rig.enc_push(4, 'long')
check(len(rig.tr(5).sends) == 0, 'Encoder 4 lang: Sends entfernt')

# state 2: sends 1-4
rig.pad(1, 0)
rig.press(22)
rig.run(2)
lines = rig.text_lines()
check(lines[0].startswith('PUZZLE Sends 1-4'), f'TRACK: nächster State Sends 1-4 ({lines[0]})')
check(lines[3].startswith('Hall'), f'Display: Send-Ziele als Namen ({lines[3]})')
rig.knob(1, 2)
check(abs(t2.sends[1].D_VOL - 0.5 * 10 ** (1 / 20)) < 1e-6, 'Sends: Encoder 1 = Send 1 +1 dB')
rig.enc_push(1, 'single')
check(t2.sends[1].B_MUTE == 1, 'Sends: Push = Send stumm')
rig.enc_push(1, 'double')
check(t2.sends[1].I_SENDMODE == 3, 'Sends: Doppel = Pre-Fader (Post-FX)')
rig.enc_push(1, 'double')
check(t2.sends[1].I_SENDMODE == 0, 'Sends: Doppel nochmal = Post (Pre-FX nicht dabei)')
rig.press(22); rig.run(2)
v5 = t2.sends[5].D_VOL
rig.knob(1, 1)
check(t2.sends[5].D_VOL > v5, 'Sends 5-8: Encoder 1 = Send 5')
rig.knob(3, 1)
check('kein Send 7' in ''.join(rig.text_lines()), 'Sends 5-8: Send 7 gibt es nicht → Hinweis im Display')

# menu
rig.press(18); rig.run(2)
lines = rig.text_lines()
check(lines[0].startswith('Marker'), f'PAGE: Menü am Gerät ({lines[0]})')
rig.pad(0, 1)          # marker row on
rig.pad(7, 1)          # pre-fx on
rig.pad(5, 0)          # layout 10 + states
check(rig.g.EXTS[b'seren_OXI/markerRow'] == b'1' and rig.g.EXTS[b'seren_OXI/preFx'] == b'1' and rig.g.EXTS[b'seren_OXI/layout'] == b'10s', 'Menü: Marker-Zeile, Pre-FX, 10+States gespeichert')
rig.press(18); rig.run(3)
check(rig.grid.get((0, 0)) not in (None, (0, 0, 0)) and rig.grid.get((0, 1)) not in (None, (0, 0, 0)), 'Marker-Zeile: Marker und Region oben')
rig.pad(0, 1)
check(rig.g.CURSOR == 4, 'Marker-Zeile: Push springt zur Region')
rig.pad(0, 1, wait=0.05); rig.pad(0, 1)
check(rig.g.LOOP[1] == 4 and rig.g.LOOP[2] == 8, 'Marker-Zeile: Doppel = Loop über die Region')
check(rig.grid.get((1, 11)) is not None and rig.grid.get((1, 10)) in (None, (0, 0, 0)), 'Layout 10+States: Spalte 11 leer, 12-16 States')
rig.pad(2, 12)
check(rig.text_lines()[0].startswith('PUZZLE Sends 1-4') and rig.tr(2).sel, 'State-Feld: Spur wählen + State Sends 1-4')
rig.enc_push(1, 'double'); rig.enc_push(1, 'double')
check(t2.sends[1].I_SENDMODE == 1, 'Pre-FX an: Doppel steppt Post → Pre → PreFX')

# receives own page
rig.L.execute(b'reaper.SetExtState("seren_OXI", "receives", "page"); reaper.SetExtState("seren_OXI", "rev", "x2")')
rig.run(10)
names = [rig.L.eval('function(r) return reaper.GetTrackName(r) end')]
rig.press(12); rig.run(10)
check('Spuren mit Receives' in ''.join(rig.text_lines()) or rig.text_lines()[0].endswith('RCV'), 'BACK: Seite Spuren mit Receives')
rig.pad(1, 0)
check(rig.tr(13).sel, f'Receive-Seite: erste Zeile = Hall')

# ================= track buttons (sequencer 1-8) on the puzzle =================
rig.L.execute(b'reaper.SetExtState("seren_OXI", "receives", "show"); reaper.SetExtState("seren_OXI", "markerRow", "0"); reaper.SetExtState("seren_OXI", "rev", "x3")')
rig.run(10)
rig.press(8); rig.run(3)
check(rig.text_lines()[0].startswith('PUZZLE'), 'ARRANGER: keine Send-Seiten mehr im Skript (die sind jetzt in DrivenByMoss)')
rig.press(34)
check(rig.tr(2).sel, 'Spurtaste 2 = zweite Zeile = Gitarre')
rig.btn(17, True); rig.press(34); rig.btn(17, False); rig.run(15)
check(rig.tr(2).vals.B_MAINSEND == 0, 'Shift + Spurtaste: Master-Send aus')
rig.btn(17, True); rig.press(34); rig.btn(17, False)
check(rig.tr(2).vals.B_MAINSEND == 1, 'Shift + Spurtaste nochmal: Master-Send an')
rig.press(34); rig.press(34); rig.press(34)
check(rig.tr(2).vals.D_VOL == 0, '3× Spurtaste: Spur -inf')
rig.run(20)
rig.press(34); rig.press(34); rig.press(34)
check(rig.tr(2).vals.D_VOL == 1, '3× Spurtaste nochmal: 0 dB')
check((rig.tr(2).vals.B_MUTE or 0) == 0, '3× Spurtaste lässt Mute in Ruhe')
rig.run(20); rig.press(34); rig.press(34); rig.run(3)
check(rig.tr(2).vals.B_MUTE == 1, '2× Spurtaste: Mute')
rig.run(20); rig.press(34); rig.press(34); rig.run(20)
check(rig.tr(2).vals.B_MUTE == 0, '2× Spurtaste nochmal: Mute aus')
rig.btn(34, True); rig.run(25); rig.btn(34, False)
check((rig.tr(2).vals.I_SOLO or 0) > 0, 'Spurtaste halten: Solo')
rig.btn(34, True); rig.run(25); rig.btn(34, False); rig.run(20)
check((rig.tr(2).vals.I_SOLO or 0) == 0, 'Spurtaste nochmal halten: Solo aus')
check(all(rig.leds.get(58 + k) == 1 for k in range(8)), 'Spurtasten-LEDs an, wo eine Spur liegt')
rig.press(18); rig.press(14); rig.run(2)
check(rig.text_lines()[0].startswith('Sh+Spur'), f'Menü Seite 2 ({rig.text_lines()[0]})')
rig.pad(0, 0)
rig.press(18); rig.run(3)
check(rig.g.EXTS[b'seren_OXI/mainSend'] == b'0', 'Menü 2: Master-Send-Aktion aus')
rig.btn(17, True); rig.press(34); rig.btn(17, False)
check(rig.tr(2).vals.B_MAINSEND == 1, 'Master-Send-Aktion aus: Shift + Spurtaste ändert nichts')

# ================= v7.2: orientation, value while turning, running text =================
rig4 = Rig(SETUP)
rig4.L.execute(src[start:end].replace('local FONT', 'FONT_FOR_TEST').encode('utf-8'))
rig4.run(5)
rig4.g.INPUT(bytes([0x90, 112, 100])); rig4.g.INPUT(bytes([0x80, 112, 0])); rig4.run(3)
check(rig4.tr(1).sel, 'Ausrichtung: oberste Pad-Reihe (OXI y 7) = erste Spur')
o = rig4.out()
check(any(m.startswith(HDR + bytes([1])) and m[7:9] == bytes([7, 0]) for m in o), 'Ausrichtung: LED der ersten Spur geht an y 7')
rig4.pad(1, 2); rig4.knob(1, 2); rig4.run(2)
lines = rig4.text_lines()
scr = rig4.screen()
big = sum(row.count('#') for row in scr[11:27])
check(lines[0] == 'Gain' and big > 60, f'Drehen: Parametername oben, Wert groß über Zeile 1-3 ({lines[0]!r}, {big} Pixel)')
rig4.run(50)
check(rig4.text_lines()[0].startswith('PUZZLE'), 'nach 1,5 s wieder die normale Anzeige')
rig4.L.execute(b'reaper.SetExtState("seren_OXI", "turnShow", "line"); reaper.SetExtState("seren_OXI", "rev", "t1")')
rig4.run(2); rig4.knob(2, 1); rig4.run(2)
lines = rig4.text_lines()
check(lines[0].startswith('PUZZLE') and lines[5].startswith('Fade-in 20ms'), f'Option unten: Wert in der untersten Zeile ({lines[5]!r})')
rig4.L.execute(b'TRACKS[2].name = "Gitarre mit einem sehr langen Namen"')
rig4.run(2)
seen = set()
for _ in range(40):
    rig4.run(10); seen.add(rig4.text_lines()[1])
check(len(seen) > 3 and any(x.startswith('2 Gitarre mit') for x in seen) and any(x.endswith('Namen') for x in seen), f'Laufschrift: langer Spurname läuft ({len(seen)} Stellungen)')
rig4.L.execute(b'reaper.SetExtState("seren_OXI", "marquee", "0"); reaper.SetExtState("seren_OXI", "rev", "t2")')
seen = set()
for _ in range(20):
    rig4.run(10); seen.add(rig4.text_lines()[1])
check(seen == {'2 Gitarre mit einem s'}, f'Laufschrift aus: Name steht still ({seen})')


# start on the selected track
rig5 = Rig(SETUP + 'TRACKS[9].sel = true')
rig5.L.execute(src[start:end].replace('local FONT', 'FONT_FOR_TEST').encode('utf-8'))
rig5.run(5)
check(rig5.grid.get((0, 0)) == rig5.grid.get((0, 0)) and rig5.text_lines()[4].split()[-1] == '7/14', f'Start: Ansicht beginnt bei der ausgewählten Spur ({rig5.text_lines()[4]})')

# follow Reaper / OXI-only selection
rig5.L.execute(b'reaper.SetOnlyTrackSelected(TRACKS[1])'); rig5.run(3)
check(rig5.text_lines()[4].split()[-1] == '1/14', f'Folgen: Spur in Reaper gewählt → Puzzle springt hin ({rig5.text_lines()[4]})')
rig5.L.execute(b'reaper.SetExtState("seren_OXI", "select", "oxi"); reaper.SetExtState("seren_OXI", "rev", "o1")'); rig5.run(2)
rig5.pad(1, 1)
check(rig5.tr(1).sel and not rig5.tr(2).sel and rig5.text_lines()[1] == '2 Gitarre', 'nur OXI: Push wählt Gitarre auf der OXI, in Reaper bleibt Vox gewählt')
check(not rig5.tr(2)[b'items'][2].sel and rig5.grid.get((1, 1)) == (0, 255, 0), 'nur OXI: Item leuchtet auf der OXI, Reaper-Auswahl unverändert')
v0 = rig5.tr(2)[b'items'][2].vals.D_VOL
rig5.knob(1, 2)
check(rig5.tr(2)[b'items'][2].vals.D_VOL > v0, 'nur OXI: Encoder wirken auf das OXI-Item')
rig5.L.execute(b'reaper.SetExtState("seren_OXI", "select", "full"); reaper.SetExtState("seren_OXI", "follow", "0"); reaper.SetExtState("seren_OXI", "rev", "o2")'); rig5.run(2)
rig5.L.execute(b'reaper.SetOnlyTrackSelected(TRACKS[12])'); rig5.run(3)
check(rig5.text_lines()[4].split()[-1] == '1/14', 'Folgen aus: Ansicht bleibt stehen')

# exit
n0 = len(rig.out())
rig.g.ATEXIT()
tail = rig.out()[n0:]
check(tail[-2] == HDR + bytes([0, 0xF7]) and tail[-1] == HDR + bytes([6, 0x55, 0xF7]), 'Ende: Remote-Modus aus, dann Übergabe an DrivenByMoss')

# newer instance takes over
rig2 = Rig(SETUP)
rig2.run(3)
rig2.L.execute(b'reaper.SetExtState("seren_OXI", "running", "neu")')
rig2.run(2)
n0 = len(rig2.out())
rig2.g.ATEXIT()
check(len(rig2.out()) == n0 and rig2.g.DEFER is None, 'zweite Instanz: alte hört auf, ohne die OXI zu löschen')

# ---- v8.7: regions as fields, grouped items
SETUP_R = '''
local t1 = MK("Vox", 0x1000000 | 0xFF0000, 4)      -- items at 0, 2, 4, 6 (1.5 long)
local t2 = MK("Git", 0x1000000 | 0x00FF00, 1)      -- one item at 0
MARKERS = { { rgn = true, pos = 0, rend = 4, name = "A" }, { rgn = true, pos = 4, rend = 8, name = "B" },
            { rgn = true, pos = 8, rend = 12, name = "C" }, { rgn = false, pos = 1, name = "m" } }
'''
rr = Rig(SETUP_R); rr.run(5)
check(rr.grid.get((0, 0), (0, 0, 0)) != (0, 0, 0) and rr.grid.get((0, 1), (0, 0, 0)) != (0, 0, 0) and rr.grid.get((0, 2), (0, 0, 0)) == (0, 0, 0),
      f'Regionen: Vox hat Felder in A und B, C leer ({rr.grid.get((0, 0))}, {rr.grid.get((0, 2))})')
check(rr.grid.get((1, 0), (0, 0, 0)) != (0, 0, 0) and rr.grid.get((1, 1), (0, 0, 0)) == (0, 0, 0), 'Regionen: Git nur in A, Lücke in B')
rr.btn(17, True); rr.pad(0, 1); rr.btn(17, False); rr.run(3)
its = rr.L.eval(b'TRACKS[1].items')
check(its[3].vals.B_MUTE == 1 and its[4].vals.B_MUTE == 1 and (its[1].vals.B_MUTE or 0) == 0, 'Shift + Feld B: beide Items in Region B stumm, A bleibt')
rr.pad(0, 0); rr.run(3)
check(its[1].sel and its[2].sel and not its[3].sel, 'Push Feld A: beide Items der Region ausgewählt')
rr.pad(0, 1); rr.pad(0, 1); rr.run(3)
check(abs(rr.g.LOOP[1] - 4) < 1e-9 and abs(rr.g.LOOP[2] - 8) < 1e-9, f'2× Feld B: Loop = Region B ({rr.g.LOOP[1]}, {rr.g.LOOP[2]})')
rr.L.execute(b"reaper.SetExtState('seren_OXI', 'markerRow', '1'); reaper.SetExtState('seren_OXI', 'rev', 'mr')"); rr.run(5)
b0, b1 = rr.grid.get((0, 0), (0, 0, 0)), rr.grid.get((0, 1), (0, 0, 0))
check(b0 == (15, 15, 1), f'Marker-Zeile: Regionen in voller Farbe (gelb ohne eigene Farbe) ({b0}, {b1})')
rr.L.execute(b"REPEAT = 1"); seenw = set()
for _ in range(20):
    rr.run(1, 0.05); seenw.add(rr.grid.get((0, 1)))
check(len(seenw) > 1 and (255, 255, 255) not in seenw, f'Cycle an: Loop-Region blinkt in ihrer Farbe ({seenw})')
SETUP_L = '''
local t1 = MK("Vox", 0x1000000 | 0xFF0000, 4)
MARKERS = { { rgn = true, pos = 0, rend = 8, name = "Teil", lane = 0 }, { rgn = true, pos = 0, rend = 4, name = "A", lane = 1 },
            { rgn = true, pos = 4, rend = 8, name = "B", lane = 1 } }
'''
rl = Rig(SETUP_L); rl.run(5)
check(rl.grid.get((0, 0), (0, 0, 0)) != (0, 0, 0) and rl.grid.get((0, 1), (0, 0, 0)) == (0, 0, 0), 'Lane 1: nur die große Region, ein Feld')
rl.L.execute(b'reaper.SetExtState("seren_OXI", "markerLane", "2"); reaper.SetExtState("seren_OXI", "rev", "l2")'); rl.run(5)
check(rl.grid.get((0, 1), (0, 0, 0)) != (0, 0, 0) and rl.grid.get((0, 2), (0, 0, 0)) == (0, 0, 0), 'Lane 2: Regionen A und B, zwei Felder')
rl.L.execute(b'reaper.SetExtState("seren_OXI", "markerLane", "1"); reaper.SetExtState("seren_OXI", "rgnRange", "2-3"); reaper.SetExtState("seren_OXI", "rev", "l3")'); rl.run(5)
check(rl.grid.get((0, 1), (0, 0, 0)) != (0, 0, 0) and rl.grid.get((0, 2), (0, 0, 0)) == (0, 0, 0), 'Nummern 2-3 statt Lane: Regionen A und B')
SETUP_S = '''
local t1 = MK("Vox", 0x1000000 | 0xFF0000, 2); local t2 = MK("Git", 0x1000000 | 0x00FF00, 2); local t3 = MK("Bass", 0, 2)
t2.vals.B_MUTE = 1; t3.vals.I_SOLO = 2; t1.vals.I_RECARM = 1
reaper.SetExtState("seren_OXI", "statusCol", "1", true)
'''
rs = Rig(SETUP_S)
seen = {58: set(), 59: set(), 60: set(), 68: set()}
for _ in range(40):
    rs.run(1, 0.05)
    for k in seen: seen[k].add(rs.leds.get(k))
check(seen[58] == {0, 1}, f'Spurtaste Vox (Rec): 2× kurz anders ({seen[58]})')
check(seen[59] == {0, 1}, 'Spurtaste Git (Mute) blinkt')
check(seen[60] == {1} and seen[68] == {0, 1}, f'Bass (Solo): Taste an, 2. LED blinkt im Mute-Takt ({seen[60]}, {seen[68]})')
check(rs.grid.get((0, 15)) and rs.grid[(0, 15)][0] > rs.grid[(0, 15)][1], f'Statusspalte: Vox rot (Rec) ({rs.grid.get((0, 15))})')
rs.pad(1, 15); rs.run(20)
check(rs.L.eval(b'TRACKS[2].vals.B_MUTE') == 0, 'Statusfeld Push: Mute aus')
SETUP_G = '''
local t1 = MK("Vox", 0x1000000 | 0xFF0000, 4)
t1.items[2].vals.I_GROUPID = 7; t1.items[3].vals.I_GROUPID = 7
'''
rg = Rig(SETUP_G); rg.run(5)
check(rg.grid.get((0, 2), (0, 0, 0)) != (0, 0, 0) and rg.grid.get((0, 3), (0, 0, 0)) == (0, 0, 0), 'gruppierte Items 2+3 = ein Feld, also 3 Felder')
rg.btn(17, True); rg.pad(0, 1); rg.btn(17, False); rg.run(3)
gi = rg.L.eval(b'TRACKS[1].items')
check(gi[2].vals.B_MUTE == 1 and gi[3].vals.B_MUTE == 1, 'Shift + Gruppenfeld: beide stumm')

print('\nALL OK' if fails == 0 else f'\n{fails} FAILED')
sys.exit(1 if fails else 0)
