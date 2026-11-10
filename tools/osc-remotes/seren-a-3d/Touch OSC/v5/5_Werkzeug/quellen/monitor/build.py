"""Builds seren-a_IEM-Monitor.tosc (1280 x 1024, 5:4 monitor on an old phone), synthwave x kawaii.

Top view (circle) + track list; layouts 16 / 32v / 32h / 64, optional semi-transparent horizon
(panorama / rear view), config page (levels, ballistics, look, track types, symbols).
"""
import math
import sys
from pathlib import Path

import py2tosc as t
from py2tosc import AlignH, AlignV, ButtonType, Shape

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "common"))
import config_ui  # noqa: E402
import sphere_ui  # noqa: E402
import room_ui  # noqa: E402

W, H = 1280, 1024
MAXO = 64
BG, PANEL, PANEL2 = "#0a0414", "#241046", "#2e1458"
PINK, PINK_D, PINK_DD = "#ff6ec7", "#7a2f86", "#4a1d5e"
CYAN = "#5ef2ff"
LAV, TXT, DIM = "#c9a7ff", "#fff0fb", "#b79bd6"
CA = {1: (8, 64, 924, 924), 2: (240, 142, 800, 800), 3: (160, 62, 960, 960), 4: (330, 62, 620, 620)}
PH = 0.34          # horizon band: this part of the area, at the bottom (must match monitor_root.lua)


def po(i):
    """Horizon band; in the 64 view it stays between the corner fields."""
    x, y, w, h = CA[i]
    ph = h * PH
    return (240, y + h - ph, 800, ph) if i == 3 else (x, y + h - ph, w, ph)


def area(i, small=False):
    """Circle/square area of layout group i; small = horizon shown, the circle sits above it."""
    x, y, w, h = CA[i]
    if not small:
        return x, y, w, h
    s = h * (1 - PH) - 6
    return x + (w - s) / 2, y, s, s

BTN = """function onValueChanged(k)
  if k == 'touch' and self.values.touch then root:notify('btn', self.name) end
end
"""
XY = """function onValueChanged(k)
  if k == 'touch' then
    if self.values.touch then root:notify('grab', self.name) else root:notify('release', self.name) end
  elseif (k == 'x' or k == 'y') and self.values.touch then root:notify('drag', self.name) end
end
"""


def F(x, y, w, h):
    return (round(x, 1), round(y, 1), round(w, 1), round(h, 1))


def lbl(name, frame, text="", size=14, color=TXT, align=AlignH.LEFT, valign=AlignV.MIDDLE, multi=False, bg=False, bgcol=None, radius=0):
    c = (t.text if multi else t.label)(frame=F(*frame), text_size=size, text_color=color, text_align_h=align,
                                       text_align_v=valign, background=bg, outline=False)
    if bg and bgcol:
        c.color = bgcol
    if radius:
        c.set("cornerRadius", float(radius))
    if name:
        c.name = name
    c.value("text").default = text
    c.set("interactive", False)
    return c


def box(frame, color, name=None, shape=Shape.RECTANGLE, bg=True, outline=False, radius=0.0):
    c = t.box(frame=F(*frame), color=color, shape=shape, background=bg, outline=outline, corner_radius=radius)
    if name:
        c.name = name
    c.set("interactive", False)
    return c


def tap(name, frame):
    return t.button(name=name, frame=F(*frame), color="#ffffff22", background=False, outline=False,
                    button_type=ButtonType.MOMENTARY, script=BTN)


def pill(name, frame, caption, size=16):
    return [box(frame, PANEL2, name=name + "_bg", radius=12), lbl(name + "_lbl", frame, caption, size, TXT, AlignH.CENTER),
            tap(name, frame)]


def header():
    k = [lbl(None, (10, 8, 300, 46), "✧ seren.a ♡ IEM monitor", 22, PINK)]
    for i, (n, cap) in enumerate((("iem", "space"), ("me", "multi"), ("mp", "panner"), ("room", "room"))):
        k += pill("mode_" + n, (300 + i * 63, 10, 60, 42), cap, 14)
    for i, (n, cap) in enumerate((("16", "16"), ("32v", "32v"), ("32h", "32h"), ("32r", "4×8"), ("64", "64"))):
        k += pill("lay_" + n, (556 + i * 47, 10, 44, 42), cap, 14)
    k += pill("pano_btn", (794, 10, 92, 42), "horizont", 14)
    k += pill("col_btn", (890, 10, 112, 42), "tosc farben", 14)
    k += pill("cfg_btn", (1006, 10, 46, 42), "⚙", 20)
    k += pill("log_btn", (1056, 10, 50, 42), "log", 14)
    k.append(lbl("src_lbl", (1112, 4, 164, 22), "keine DAW", 13, CYAN, AlignH.CENTER))
    k.append(lbl("range_lbl", (1146, 30, 96, 26), "1–16", 13, TXT, AlignH.CENTER))
    k += [tap("bank_prev", (1110, 28, 40, 30)), lbl(None, (1110, 28, 40, 30), "◀", 16, PINK, AlignH.CENTER),
          tap("bank_next", (1236, 28, 40, 30)), lbl(None, (1236, 28, 40, 30), "▶", 16, PINK, AlignH.CENTER)]
    return k


def circle(i, small=False):
    x, y, w, h = area(i, small)
    g = t.group(name=f"circ{i}" + ("s" if small else ""), frame=F(x, y, w, h), color=BG, background=False, outline=False,
                visible=(i == 1 and not small))
    cx, cy, R = w / 2, h / 2, w / 2 - 14
    k = [box((cx - R - 6, cy - R - 6, 2 * R + 12, 2 * R + 12), PINK_DD, name="th_line", shape=Shape.CIRCLE),
         box((cx - R, cy - R, 2 * R, 2 * R), PANEL, name="th_panel", shape=Shape.CIRCLE)]
    k += sphere_ui.rings(box, lbl, cx, cy, R, PINK_D, CYAN, DIM, 11 if not small else 10)
    k += [box((cx - 0.5, cy - R, 1, 2 * R), PINK_D, name="th_line"), box((cx - R, cy - 0.5, 2 * R, 1), PINK_D, name="th_line"),
          lbl(None, (cx - 70, -2, 140, 20), "✧ vorn 0° ✧", 14, PINK, AlignH.CENTER),
          lbl(None, (cx - 70, h - 18, 140, 20), "hinten 180°", 13, DIM, AlignH.CENTER),
          lbl(None, (0, cy - 28, 70, 20), "+90° L", 13, DIM),
          lbl(None, (w - 70, cy - 28, 70, 20), "−90° R", 13, DIM, AlignH.RIGHT)]
    if not small and i == 1:
        k.append(lbl(None, (0, h - 40, 260, 40), sphere_ui.LEGEND, 10, DIM, multi=True, valign=AlignV.BOTTOM))
    g.add(*k)
    return g


def square(i, small=False):
    x, y, w, h = area(i, small)
    g = t.group(name=f"sq{i}" + ("s" if small else ""), frame=F(x, y, w, h), color=BG, background=False, outline=False, visible=False)
    k = [box((0, 0, w, h), PANEL, name="th_panel", radius=16)]
    for j in range(1, 8):
        k.append(box((w * j / 8 - 0.5, 0, 1, h), PINK_D if j == 4 else PINK_DD, name="th_line"))
        k.append(box((0, h * j / 8 - 0.5, w, 1), CYAN if j == 4 else PINK_DD, name="th_line"))
    k += [lbl(None, (w / 2 - 120, 4, 240, 20), "✧ vorn · Y +100 ✧", 13, PINK, AlignH.CENTER),
          lbl(None, (w / 2 - 120, h - 22, 240, 20), "hinten · Y −100", 12, DIM, AlignH.CENTER),
          lbl(None, (8, h / 2 - 22, 120, 18), "X −100", 12, DIM),
          lbl(None, (w - 128, h / 2 - 22, 120, 18), "X +100", 12, DIM, AlignH.RIGHT)]
    g.add(*k)
    return g


def pano(i):
    x, y, w, ph = po(i)
    g = t.group(name=f"pano{i}", frame=F(x, y, w, ph), color=BG, background=False, outline=False, visible=False)
    k = [box((0, 0, w, ph), PANEL, name=f"pano{i}_fill", radius=14)]
    for j in range(1, 8):
        k.append(box((w * j / 8 - 0.5, 0, 1, ph), PINK_D if j == 4 else PINK_DD))
    k.append(box((0, ph / 2 - 1, w, 2), CYAN))
    k.append(lbl(f"pano{i}_title", (10, 4, 300, 18), "horizont · azimut × elevation", 12, LAV))
    for j, az in enumerate((180, 90, 0, -90, -180)):
        px = w * j / 4
        k.append(lbl(None, (min(max(px - 30, 4), w - 64), ph - 18, 60, 16), f"{az:+d}°" if az else "0°", 10, DIM, AlignH.CENTER))
    g.add(*k)
    return g


def cell(k):
    # frames are set by the script for each layout; here the 16-layout row
    x, y, w, h = 944, 64 + (k - 1) * 60, 328, 56
    n = f"c{k}"
    g = t.group(name=n, frame=F(x, y, w, h), color=BG, background=False, outline=False, visible=False)
    g.add(box((0, 0, w, h), PANEL, name=n + "_bg", radius=10),
          box((0, 6, 4, h - 12), PINK, name=n + "_grp", radius=2),
          box((6, h - 2, w - 12, 2), CYAN, name=n + "_fx", radius=1),
          lbl(n + "_num", (8, 10, 36, 36), str(k), 14, "#24103f", AlignH.CENTER, bg=True, bgcol=PINK, radius=18),
          lbl(n + "_numb", (8.8, 10, 36, 36), str(k), 14, "#24103f", AlignH.CENTER),   # 2nd pass = bold
          lbl(n + "_name", (52, 2, w - 82, 30), "", 17, TXT),
          lbl(n + "_val", (52, 29, w - 58, 17), "", 12, DIM),
          lbl(n + "_glyph", (w - 30, 2, 28, 30), "", 16, TXT, AlignH.CENTER),
          box((52, h - 8, 0, 4), PINK, name=n + "_lvl", radius=2),
          box((52, h - 8, 2, 4), TXT, name=n + "_hold"),
          tap(n + "_tap", (0, 0, w, h)))
    return g


def dot(k, size=30):
    glow = size * 2.6
    n = f"d{k}"
    g = t.group(name=n, frame=F(-300, -300, glow, glow), color=BG, background=False, outline=False, visible=False)
    o = (glow - size) / 2
    g.add(box((o, o, size, size), PINK, name=n + "_glow", shape=Shape.CIRCLE),
          box((o - 5, o - 5, size + 10, size + 10), TXT, name=n + "_ring", shape=Shape.CIRCLE, bg=False, outline=True),
          box((o, o, size, size), PINK, name=n + "_dot", shape=Shape.CIRCLE),
          box((o, o, size, size), PINK, name=n + "_lo", shape=Shape.CIRCLE, bg=False, outline=True),
          lbl(n + "_num", (o, o, size, size), str(k), 13, "#24103f", AlignH.CENTER),
          lbl(n + "_icon", (o + size * 0.6, o + size * 0.6, size, size), "", 18, TXT, AlignH.CENTER))
    return g


def build():
    doc = t.Document.new(frame=(0, 0, W, H), color=BG, background=True, outline=False)
    root = doc.root
    root.name = "seren.a IEM monitor"
    common = HERE.parent / "common"
    root.script = "\n".join((common / f).read_text() for f in ("monitor.lua", "levels.lua", "look.lua", "config.lua", "room.lua", "cpu.lua", "bank.lua")) + \
        "\n" + (HERE / "monitor_root.lua").read_text()
    k = header()
    for i in (1, 2, 3, 4):
        k += [circle(i), circle(i, True)]
    for i in (1, 2, 3, 4):
        k += [square(i), square(i, True)]
    k += room_ui.controls(box, lbl)        # ROOM view (dearVR PRO), under the dots
    for i in range(1, MAXO + 1):          # width: left/right edge of a StereoEncoder
        for side in ("wl", "wr"):
            k.append(box((-100, -100, 12, 12), PINK, name=f"{side}{i}", shape=Shape.CIRCLE))
    for i in range(1, MAXO + 1):
        k.append(dot(i))
    for i in (1, 2, 3, 4):
        k.append(pano(i))
    for i in range(1, MAXO + 1):
        k.append(box((-100, -100, 14, 14), PINK, name=f"p{i}", shape=Shape.CIRCLE))
    for name, fr in (("top_xy", CA[1]), ("pano_xy", (CA[1][0], CA[1][1] + CA[1][3] * (1 - PH), CA[1][2], CA[1][3] * PH))):
        xy = t.xy(name=name, frame=F(*fr), color=PINK, background=False, outline=False, cursor=False, lines=False,
                  grid_x=False, grid_y=False, script=XY)
        xy.value("x").default = 0.5
        xy.value("y").default = 0.5
        k.append(xy)
    k += room_ui.zoom(box, lbl)            # above the drag areas
    cpu = lbl("cpu_lbl", (112, 46, 320, 16), "", 11, DIM)   # Auslastung (Option), neben der Versionsnummer
    cpu.set("visible", False)
    k.append(cpu)
    for i in range(1, MAXO + 1):
        k.append(cell(i))
    for b in range(1, 5):                  # 64 view: all values of the object that just moved, per block
        k.append(lbl(f"blk{b}_info", (-400, -400, 230, 46), "", 11, TXT, multi=True, valign=AlignV.TOP,
                     bg=True, bgcol=PANEL2, radius=8))
    mon = t.group(name="mon_overlay", frame=F(8, 64, W - 16, H - 72), color=BG, background=True, outline=False, visible=False)
    mon.add(box((0, 0, W - 16, H - 72), PANEL, radius=16),
            lbl(None, (16, 10, W - 48, 24), "✧ log ✧   ◆ vom DAW-Skript erkannt   ← kommt an   → geht raus", 14, LAV),
            lbl("mon_text", (16, 42, W - 48, H - 130), "", 15, TXT, multi=True, valign=AlignV.TOP))
    k.append(mon)
    cfg = config_ui.build(W, H, with64=True)
    k.append(cfg)
    root.add(*k)
    return doc


if __name__ == "__main__":
    out = HERE / "dist"
    out.mkdir(exist_ok=True)
    doc = build()
    for issue in doc.validate():
        print("ISSUE:", issue)
    doc.save(out / "seren-a_IEM-Monitor.tosc")
    print("saved", sum(1 for _ in doc.walk()), "controls")
