"""Builds seren-a_Objekt-Uebersicht.tosc (phone landscape, 1600 x 740).

All objects at once: top view left, second view in the middle (IEM: panorama azimuth x
elevation, MultiPanner: rear view X/Z), selected object below it, track list on the right.
"""
import math
from pathlib import Path

import py2tosc as t
from py2tosc import AlignH, AlignV, ButtonType, Font, Shape

HERE = Path(__file__).parent
W, H = 1600, 740
N = 16
BG, PANEL, CELL = "#0e1014", "#16191f", "#1c1f25"
LINE, LINE_HI = "#2c313a", "#4a5262"
TXT, DIM = "#e8ebf0", "#8b93a1"
ACC, IEM_C = "#36d0c4", "#b28dff"

BTN_SCRIPT = """function onValueChanged(k)
  if k == 'touch' and self.values.touch then root:notify('btn', self.name) end
end
"""

TOP = (12, 64, 664, 664)          # x, y, w, h  (square)
SEC = (690, 96, 444, 300)         # second view
LIST_X, LIST_W, ROW_H = 1148, 440, 41


def F(x, y, w, h):
    return (round(x), round(y), round(w), round(h))


def lbl(name, frame, text="", size=14, color=TXT, align=AlignH.LEFT, valign=AlignV.MIDDLE,
        multi=False, bold=False):
    maker = t.text if multi else t.label
    c = maker(frame=F(*frame), text_size=size, text_color=color, text_align_h=align,
              text_align_v=valign, background=False, outline=False)
    if name:
        c.name = name
    c.value("text").default = text
    c.set("interactive", False)
    return c


def box(frame, color, name=None, shape=Shape.RECTANGLE, bg=True, outline=False, radius=0.0):
    c = t.box(frame=F(*frame), color=color, shape=shape, background=bg, outline=outline,
              corner_radius=radius)
    if name:
        c.name = name
    c.set("interactive", False)
    return c


def button(name, frame, caption, size=16, color="#262a31"):
    return [t.button(name=name, frame=F(*frame), color=color, corner_radius=6, outline=False,
                     button_type=ButtonType.MOMENTARY, script=BTN_SCRIPT),
            lbl(name + "_lbl", frame, caption, size, TXT, AlignH.CENTER)]


def top_iem_bg():
    x, y, w, h = TOP
    g = t.group(name="bg_top_iem", frame=F(x, y, w, h), color=BG, background=False, outline=False)
    k = []
    cx, cy, R = w / 2, h / 2, w / 2 - 14
    k.append(box((cx - R, cy - R, 2 * R, 2 * R), PANEL, shape=Shape.CIRCLE))
    for el in (60, 30, 0, -30, -60):
        r = R * (90 - el) / 180
        k.append(box((cx - r, cy - r, 2 * r, 2 * r), LINE_HI if el == 0 else LINE,
                     shape=Shape.CIRCLE, bg=False, outline=True))
        k.append(lbl(None, (cx + 4, cy - r - 2, 70, 18), f"{el:+d}°" if el else "0° Horizont",
                     11, DIM if el else TXT))
    k.append(box((cx - 0.5, cy - R, 1, 2 * R), LINE))
    k.append(box((cx - R, cy - 0.5, 2 * R, 1), LINE))
    k.append(lbl(None, (cx - 60, 0, 120, 18), "vorn  0°", 12, TXT, AlignH.CENTER))
    k.append(lbl(None, (0, cy - 9, 60, 18), "+90° L", 12, DIM))
    k.append(lbl(None, (w - 60, cy - 9, 60, 18), "−90° R", 12, DIM, AlignH.RIGHT))
    k.append(lbl(None, (cx - 60, h - 18, 120, 18), "hinten 180°", 12, DIM, AlignH.CENTER))
    k.append(lbl(None, (6, h - 40, 220, 34), "Mitte = oben (+90°)\nRand = unten (−90°)",
                 11, DIM, multi=True, valign=AlignV.BOTTOM))
    g.add(*k)
    return g


def top_mp_bg():
    x, y, w, h = TOP
    g = t.group(name="bg_top_mp", frame=F(x, y, w, h), color=BG, background=False, outline=False,
                visible=False)
    k = [box((0, 0, w, h), PANEL, radius=6)]
    for i in range(1, 8):
        k.append(box((w * i / 8 - 0.5, 0, 1, h), LINE_HI if i == 4 else LINE))
        k.append(box((0, h * i / 8 - 0.5, w, 1), LINE_HI if i == 4 else LINE))
    k.append(lbl(None, (w / 2 - 60, 2, 120, 18), "vorn  Y +100", 12, TXT, AlignH.CENTER))
    k.append(lbl(None, (4, h / 2 - 20, 80, 18), "X −100", 12, DIM))
    k.append(lbl(None, (w - 84, h / 2 - 20, 80, 18), "X +100", 12, DIM, AlignH.RIGHT))
    k.append(lbl(None, (w / 2 - 60, h - 20, 120, 18), "hinten  Y −100", 12, DIM, AlignH.CENTER))
    g.add(*k)
    return g


def sec_iem_bg():
    x, y, w, h = SEC
    g = t.group(name="bg_sec_iem", frame=F(x, y, w, h), color=BG, background=False, outline=False)
    k = [box((0, 0, w, h), PANEL, radius=6)]
    for i, az in enumerate((180, 90, 0, -90, -180)):
        px = w * i / 4
        k.append(box((px - 0.5, 0, 1, h), LINE_HI if az == 0 else LINE))
        k.append(lbl(None, (px - 30, h + 2, 60, 16), f"{az:+d}°" if az else "0°", 11, DIM,
                     AlignH.CENTER))
    for el in (45, 0, -45):
        py = h * (0.5 - el / 180)
        k.append(box((0, py - 0.5, w, 1), LINE_HI if el == 0 else LINE))
        k.append(lbl(None, (4, py - 17, 60, 16), f"{el:+d}°" if el else "0°", 11, DIM))
    g.add(*k)
    return g


def sec_mp_bg():
    x, y, w, h = SEC
    g = t.group(name="bg_sec_mp", frame=F(x, y, w, h), color=BG, background=False, outline=False,
                visible=False)
    k = [box((0, 0, w, h), PANEL, radius=6)]
    for i in range(1, 4):
        k.append(box((w * i / 4 - 0.5, 0, 1, h), LINE_HI if i == 2 else LINE))
        k.append(box((0, h * i / 4 - 0.5, w, 1), LINE_HI if i == 2 else LINE))
    k.append(lbl(None, (4, 2, 120, 16), "Z +100 oben", 11, DIM))
    k.append(lbl(None, (4, h - 18, 120, 16), "Z −100", 11, DIM))
    g.add(*k)
    return g


def dot(name, size, number):
    """Group a bit larger than the dot, so the selection ring stays inside it."""
    gs = size + 12
    g = t.group(name=name, frame=F(-100, -100, gs, gs), color=BG, background=False,
                outline=False, visible=False)
    g.add(box((1, 1, gs - 2, gs - 2), TXT, name=name + "_ring", shape=Shape.CIRCLE, bg=False,
              outline=True),
          box((6, 6, size, size), ACC, name=name + "_dot", shape=Shape.CIRCLE),
          lbl(name + "_n", (6, 6, size, size), str(number), 15 if size > 30 else 12, "#0d0f12",
              AlignH.CENTER))
    return g


def build():
    doc = t.Document.new(frame=(0, 0, W, H), color=BG, background=True, outline=False)
    root = doc.root
    root.name = "seren.a Objekt-Übersicht"
    root.script = (HERE.parent / "common" / "monitor.lua").read_text() + "\n" + (HERE.parent / "common" / "bank.lua").read_text() + "\n" + (HERE / "ov_root.lua").read_text()
    k = []
    # header
    k += button("mode_iem", (12, 10, 96, 42), "IEM", 16)
    k += button("mode_mp", (114, 10, 160, 42), "MULTIPANNER", 16)
    k += button("mode_me", (280, 10, 150, 42), "MULTI-ENC", 16)
    k.append(lbl("src", (440, 10, 150, 42), "keine DAW", 15, ACC))
    k += button("log_btn", (600, 10, 80, 42), "LOG", 16)
    # views
    k += [top_iem_bg(), top_mp_bg(), sec_iem_bg(), sec_mp_bg()]
    k.append(box(TOP, BG, name="top_area", bg=False))
    k.append(box(SEC, BG, name="sec_area", bg=False))
    k.append(lbl("sec_title", (690, 64, 444, 26), "Panorama · Azimut × Elevation", 14, IEM_C))
    # detail
    dx, dy = 690, 430
    k.append(box((dx, dy, 444, 296), PANEL, radius=6))
    k.append(lbl(None, (dx + 14, dy + 10, 300, 20), "GEWÄHLT", 12, DIM))
    k.append(lbl("det_name", (dx + 14, dy + 32, 420, 40), "keine Spur gewählt", 26, TXT))
    k.append(lbl("det_vals", (dx + 14, dy + 82, 420, 150), "", 24, TXT, multi=True,
                 valign=AlignV.TOP))
    k.append(lbl("status", (dx + 14, dy + 256, 420, 28), "", 12, DIM))
    # list
    k += button("bank_prev", (LIST_X, 10, 60, 42), "◂", 20)
    k.append(lbl("bank", (LIST_X + 66, 10, LIST_W - 132, 42), "Spuren 1–16", 17, TXT,
                 AlignH.CENTER))
    k += button("bank_next", (LIST_X + LIST_W - 60, 10, 60, 42), "▸", 20)
    for i in range(N):
        y = 64 + i * ROW_H
        n = f"r{i + 1}"
        k.append(box((LIST_X, y, LIST_W, ROW_H - 3), CELL, name=n + "_bg", radius=4))
        k.append(box((LIST_X + 6, y + 4, 30, 30), ACC, name=n + "_chip", shape=Shape.CIRCLE))
        k.append(lbl(n + "_num", (LIST_X + 6, y + 4, 30, 30), str(i + 1), 12, "#0d0f12",
                     AlignH.CENTER))
        k.append(lbl(n + "_name", (LIST_X + 44, y, 200, ROW_H - 3), "", 15, TXT))
        k.append(lbl(n + "_val", (LIST_X + 244, y, LIST_W - 252, ROW_H - 3), "", 13, DIM,
                     AlignH.RIGHT))
        # unsichtbare Taste über der ganzen Zeile (Antippen = Spur wählen)
        k.append(t.button(name=n + "_tap", frame=F(LIST_X, y, LIST_W, ROW_H - 3),
                          color="#ffffff30", background=False, outline=False,
                          button_type=ButtonType.MOMENTARY, script=BTN_SCRIPT))
    # LOG-Fenster über den Ansichten
    mon = t.group(name="mon_overlay", frame=F(12, 64, 1122, 664), color=BG, background=True,
                  outline=False, visible=False)
    mon.add(box((0, 0, 1122, 664), PANEL, radius=6),
            lbl(None, (14, 8, 1090, 24), "LOG   ◆ vom DAW-Skript erkannt   ← kommt an   → geht raus   (neueste oben)",
                14, DIM),
            lbl("mon_text", (14, 40, 1094, 612), "", 15, TXT, multi=True, valign=AlignV.TOP))
    # dots on top of everything
    for i in range(N):
        k.append(dot(f"d{i + 1}", 34, i + 1))
    for i in range(N):
        k.append(dot(f"e{i + 1}", 24, i + 1))
    k.append(mon)
    root.add(*k)
    return doc


if __name__ == "__main__":
    out = HERE / "dist"
    out.mkdir(exist_ok=True)
    doc = build()
    for issue in doc.validate():
        print("ISSUE:", issue)
    doc.save(out / "seren-a_Objekt-Uebersicht.tosc")
    print("saved", sum(1 for _ in doc.walk()), "controls")
