"""Builds seren-a_IEM-Space.tosc (iPad landscape, 1366 x 1024), synthwave x kawaii.

Top view + panorama on the left (drag the selected object in either), selected object in the
middle, track list on the right, object pills on top. Dots glow with the track level.
"""
import math
from pathlib import Path

import sys
import py2tosc as t
from py2tosc import AlignH, AlignV, ButtonType, Orientation, Shape

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "common"))
import config_ui  # noqa: E402
import room_ui  # noqa: E402
import sphere_ui  # noqa: E402
W, H = 1366, 1024
N = 16
N32 = 32           # v8.13: option "32" – tracks 17–32 as tiles in rows of 8 below (instead of the panorama)
BG, PANEL, PANEL2 = "#170a2b", "#241046", "#2e1458"
PINK, PINK_D, PINK_DD = "#ff6ec7", "#7a2f86", "#4a1d5e"
CYAN, CYAN_D = "#5ef2ff", "#2b6f86"
LAV, TXT, DIM = "#c9a7ff", "#fff0fb", "#b79bd6"
YEL, ORA = "#ffd36e", "#ff9e7a"

TOP = (16, 168, 600, 600)
PANO = (16, 784, 914, 224)
DET = (632, 168, 298, 600)
LIST_X, LIST_W, ROW = 946, 404, 52

BTN_SCRIPT = """function onValueChanged(k)
  if k == 'touch' and self.values.touch then root:notify('btn', self.name) end
end
"""
DRAG_SCRIPT = """function onValueChanged(k)
  if (k == 'x' or k == 'y') and self.values.touch then root:notify('drag', self.name) end
end
"""


def F(x, y, w, h):
    return (round(x), round(y), round(w), round(h))


def lbl(name, frame, text="", size=14, color=TXT, align=AlignH.LEFT, valign=AlignV.MIDDLE,
        multi=False):
    c = (t.text if multi else t.label)(frame=F(*frame), text_size=size, text_color=color,
                                       text_align_h=align, text_align_v=valign,
                                       background=False, outline=False)
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


def tap(name, frame, script=BTN_SCRIPT):
    """Invisible touch area (shows a soft flash while pressed)."""
    return t.button(name=name, frame=F(*frame), color="#ffffff28", background=False,
                    outline=False, button_type=ButtonType.MOMENTARY, script=script)


def pill_button(name, frame, caption, size=22):
    return [box(frame, PANEL2, radius=14), lbl(None, frame, caption, size, PINK, AlignH.CENTER),
            tap(name, frame)]


def mode_pill(name, frame, caption, size=18):
    return [box(frame, PANEL2, name=name + "_bg", radius=14),
            lbl(name + "_lbl", frame, caption, size, TXT, AlignH.CENTER), tap(name, frame)]


def header():
    k = [lbl(None, (16, 12, 300, 60), "✧ seren.a ♡ IEM space", 24, PINK)]
    k += mode_pill("mode_iem", (318, 16, 78, 52), "space", 17)
    k += mode_pill("mode_me", (400, 16, 70, 52), "multi", 17)
    k += mode_pill("mode_mp", (474, 16, 84, 52), "panner", 17)
    k += mode_pill("mode_room", (562, 16, 70, 52), "room", 17)
    k += mode_pill("log_btn", (636, 16, 48, 52), "log", 15)
    k += mode_pill("col_btn", (688, 16, 96, 52), "tosc farben", 13)
    k += mode_pill("cfg_btn", (788, 16, 44, 52), "⚙", 22)
    k += mode_pill("n32_btn", (836, 16, 46, 52), "32", 15)
    k.append(lbl("src", (884, 16, 60, 52), "keine DAW", 11, CYAN, AlignH.CENTER))
    k += pill_button("bank_prev", (LIST_X, 16, 64, 52), "◂")
    k.append(lbl("bank", (LIST_X + 72, 16, LIST_W - 144, 52), "Spuren 1–16", 18, TXT,
                 AlignH.CENTER))
    k += pill_button("bank_next", (LIST_X + LIST_W - 64, 16, 64, 52), "▸")
    # object pills
    for i in range(N):
        x, y, w, h = 16 + i * 83.4, 88, 76, 66
        n = f"sel{i + 1}"
        k += [box((x - 3, y - 3, w + 6, h + 6), TXT, name=n + "_ring", bg=False, outline=True,
                  radius=18),
              box((x, y, w, h), PINK, name=n + "_bg", radius=16),
              lbl(n + "_num", (x, y + 4, w, 30), str(i + 1), 22, "#24103f", AlignH.CENTER),
              lbl(n + "_name", (x + 2, y + 36, w - 4, 24), "", 12, "#24103f", AlignH.CENTER),
              tap(n, (x, y, w, h))]
    return k


def top_view():
    x, y, w, h = TOP
    g = t.group(name="bg_top", frame=F(x, y, w, h), color=BG, background=False, outline=False)
    cx, cy, R = w / 2, h / 2, w / 2 - 16
    k = [box((cx - R - 6, cy - R - 6, 2 * R + 12, 2 * R + 12), PINK_DD, shape=Shape.CIRCLE),
         box((cx - R, cy - R, 2 * R, 2 * R), PANEL, name="th_panel", shape=Shape.CIRCLE),
         ]
    k += sphere_ui.rings(box, lbl, cx, cy, R, PINK_D, CYAN, DIM)
    k.append(box((cx - 0.5, cy - R, 1, 2 * R), PINK_D))
    k.append(box((cx - R, cy - 0.5, 2 * R, 1), PINK_D))
    # Sternchen an den Achsenenden
    k += [lbl(None, (cx - 70, -2, 140, 20), "✧ vorn 0° ✧", 14, PINK, AlignH.CENTER),
          lbl(None, (cx - 70, h - 18, 140, 20), "hinten 180°", 13, DIM, AlignH.CENTER),
          lbl(None, (0, cy - 30, 70, 20), "+90° L", 13, DIM),
          lbl(None, (w - 70, cy - 30, 70, 20), "−90° R", 13, DIM, AlignH.RIGHT),
          lbl(None, (0, h - 46, 230, 44), sphere_ui.LEGEND.replace(" · rand", "\nrand").replace(" · höhe", "\nhöhe"), 10, DIM,
              multi=True, valign=AlignV.BOTTOM)]
    g.add(*k)
    return g


def pano_view():
    x, y, w, h = PANO
    g = t.group(name="bg_pano", frame=F(x, y, w, h), color=BG, background=False, outline=False)
    k = [box((0, 0, w, h), PANEL, name="th_panel", radius=16)]
    hy = h / 2
    # Synthwave-Sonne über dem Horizont (Streifen, nach oben gelb, nach unten pink)
    R = 78
    cols = [YEL, "#ffdf6e", "#ffc86e", "#ffb070", ORA, "#ff8f8a", "#ff7fa6", "#ff74b8", PINK]
    n = len(cols)
    for i, c in enumerate(cols):
        y0 = hy - R + i * (R / n)
        gap = 0 if i < 3 else (i - 2) * 1.2           # Streifen werden nach unten schmaler
        y1 = y0 + R / n - gap
        ym = (y0 + y1) / 2
        half = math.sqrt(max(0, R * R - (hy - ym) ** 2))
        k.append(box((w / 2 - half, y0, 2 * half, max(1.5, y1 - y0)), c, radius=1))
    # Boden: Linien unter dem Horizont, nach unten weiter auseinander
    for i, f in enumerate((0.08, 0.2, 0.38, 0.62, 0.95)):
        k.append(box((0, hy + f * (h / 2 - 4), w, 1), PINK_D))
    for i in range(1, 8):
        k.append(box((w * i / 8 - 0.5, 0, 1, h), PINK_DD if i != 4 else PINK_D))
    k.append(box((0, hy - 1, w, 2), CYAN))
    for i, az in enumerate((180, 90, 0, -90, -180)):
        px = w * i / 4
        k.append(lbl(None, (min(max(px - 30, 4), w - 64), h - 20, 60, 18),
                     f"{az:+d}°" if az else "0°", 11, DIM, AlignH.CENTER))
    k.append(lbl(None, (10, 6, 260, 20), "panorama · azimut × elevation", 12, LAV))
    k.append(lbl(None, (10, hy - 20, 80, 18), "0°", 11, CYAN))
    g.add(*k)
    return g


def hfader(name, frame, color):
    f = t.fader(name=name, frame=F(*frame), color=color, orientation=Orientation.EAST,
                centered=True, outline=False, grid=False, script=DRAG_SCRIPT)
    f.value("x").default = 0.5
    return f


def detail():
    _, _, w, h = DET           # v8.16: eigene Gruppe „det_g“, damit Room „groß“ das Feld ausblenden kann
    x = y = 0
    k = [box((x, y, w, h), PANEL, name="th_panel", radius=18),
         lbl(None, (x, y + 10, w, 26), "✧ ausgewählt ✧", 16, LAV, AlignH.CENTER),
         box((x + w / 2 - 44, y + 46, 88, 88), PINK, name="det_chip", shape=Shape.CIRCLE),
         lbl("det_num", (x + w / 2 - 44, y + 46, 88, 88), "", 36, "#24103f", AlignH.CENTER),
         lbl("det_name", (x + 12, y + 140, w - 24, 58), "nichts gewählt", 22, TXT,
             AlignH.CENTER, multi=True, valign=AlignV.TOP)]
    for i in range(3):
        yy = y + 202 + i * 54
        k += [lbl(f"det_l{i + 1}", (x + 18, yy, w - 36, 18), "", 13, DIM),
              lbl(f"det_v{i + 1}", (x + 18, yy + 17, w - 36, 34), "–", 25, TXT)]
    k += [lbl(None, (x + 18, y + 366, 200, 18), "pegel", 13, DIM),
          box((x + 18, y + 386, w - 36, 14), PINK_DD, name="det_lvlbg", radius=7),
          box((x + 18, y + 386, 0, 14), PINK, name="det_lvl", radius=7),
          lbl("fa_lbl", (x + 18, y + 410, w - 36, 18), "width", 13, DIM),
          hfader("fa", (x + 18, y + 430, w - 36, 38), LAV),
          lbl("yaw_lbl", (x + 18, y + 476, w - 36, 18), "rotator yaw", 13, CYAN),
          hfader("yaw_fader", (x + 18, y + 496, w - 36, 32), CYAN),
          lbl("pitch_lbl", (x + 18, y + 534, w - 36, 18), "rotator pitch", 13, CYAN),
          hfader("pitch_fader", (x + 18, y + 554, w - 36, 32), CYAN)]
    g = t.group(name="det_g", frame=F(*DET), color=BG, background=False, outline=False)
    g.add(*k)
    return [g]


def square_bg(name, frame, labels):
    x, y, w, h = frame
    g = t.group(name=name, frame=F(x, y, w, h), color=BG, background=False, outline=False,
                visible=False)
    k = [box((0, 0, w, h), PANEL, radius=16)]
    for i in range(1, 8):
        k.append(box((w * i / 8 - 0.5, 0, 1, h), PINK_D if i == 4 else PINK_DD))
    for i in range(1, 4):
        k.append(box((0, h * i / 4 - 0.5, w, 1), CYAN if i == 2 else PINK_DD))
    top, bottom, left, right = labels
    k += [lbl(None, (w / 2 - 120, 4, 240, 20), top, 13, PINK, AlignH.CENTER),
          lbl(None, (w / 2 - 120, h - 22, 240, 20), bottom, 12, DIM, AlignH.CENTER),
          lbl(None, (8, h / 2 - 22, 120, 18), left, 12, DIM),
          lbl(None, (w - 128, h / 2 - 22, 120, 18), right, 12, DIM, AlignH.RIGHT)]
    g.add(*k)
    return g


def track_list():
    k = []
    for i in range(N):
        y = 168 + i * ROW
        n = f"r{i + 1}"
        h = ROW - 4
        k += [box((LIST_X, y, LIST_W, h), PANEL, name=n + "_bg", radius=12),
              box((LIST_X + 8, y + 7, 34, 34), PINK, name=n + "_chip", shape=Shape.CIRCLE),
              lbl(n + "_num", (LIST_X + 8, y + 7, 34, 34), str(i + 1), 13, "#24103f",
                  AlignH.CENTER),
              lbl(n + "_name", (LIST_X + 52, y + 2, 190, h - 10), "", 16, TXT),
              lbl(n + "_val", (LIST_X + 240, y + 2, LIST_W - 252, h - 10), "", 12, DIM,
                  AlignH.RIGHT),
              box((LIST_X + 52, y + h - 8, LIST_W - 64, 4), PINK_DD, name=n + "_lvlbg", radius=2),
              box((LIST_X + 52, y + h - 8, 0, 4), PINK, name=n + "_lvl", radius=2),
              box((LIST_X + 52, y + h - 8, 2, 4), TXT, name=n + "_hold"),
              box((LIST_X, y + 6, 4, h - 12), PINK, name=n + "_grp", radius=2),
              box((LIST_X + 8, y + h - 2, LIST_W - 16, 2), CYAN, name=n + "_fx", radius=1),
              lbl(n + "_glyph", (LIST_X + LIST_W - 160, y + 2, 26, h - 14), "", 16, TXT, AlignH.CENTER),
              tap(n + "_tap", (LIST_X, y, LIST_W, h))]
    return k


def tiles32():
    """Tracks 17-32 in 2 rows of 8 where the panorama is; same sub-controls as the list rows (r17_name ...)."""
    x0, y0, w0, h0 = PANO
    g = t.group(name="tiles32", frame=F(x0, y0, w0, h0), color=BG, background=False, outline=False, visible=False)
    k = [box((0, 0, w0, h0), BG, name="tiles32_cover")]
    tw, th = (w0 - 7 * 6) / 8, (h0 - 6) / 2
    for i in range(16):
        n = f"r{N + i + 1}"
        x, y = (i % 8) * (tw + 6), (i // 8) * (th + 6)
        k += [box((x, y, tw, th), PANEL, name=n + "_bg", radius=12),
              box((x + 6, y + 6, 30, 30), PINK, name=n + "_chip", shape=Shape.CIRCLE),
              lbl(n + "_num", (x + 6, y + 6, 30, 30), str(N + i + 1), 12, "#24103f", AlignH.CENTER),
              lbl(n + "_name", (x + 40, y + 4, tw - 44, 34), "", 14, TXT),
              lbl(n + "_val", (x + 6, y + 40, tw - 12, 40), "", 11, DIM, multi=True, valign=AlignV.TOP),
              box((x + 6, y + th - 10, tw - 12, 4), PINK_DD, name=n + "_lvlbg", radius=2),
              box((x + 6, y + th - 10, 0, 4), PINK, name=n + "_lvl", radius=2),
              box((x + 6, y + th - 10, 2, 4), TXT, name=n + "_hold"),
              box((x, y + 6, 4, th - 12), PINK, name=n + "_grp", radius=2),
              box((x + 8, y + th - 3, tw - 16, 2), CYAN, name=n + "_fx", radius=1),
              lbl(n + "_glyph", (x + tw - 28, y + 2, 26, 24), "", 14, TXT, AlignH.CENTER),
              tap(n + "_tap", (x, y, tw, th))]
    g.add(*k)
    return g


def dot(name, size, glow, number):
    g = t.group(name=name, frame=F(-200, -200, glow, glow), color=BG, background=False,
                outline=False, visible=False)
    o = (glow - size) / 2
    g.add(box((o, o, size, size), PINK, name=name + "_glow", shape=Shape.CIRCLE),
          box((o - 6, o - 6, size + 12, size + 12), TXT, name=name + "_ring", shape=Shape.CIRCLE,
              bg=False, outline=True),
          box((o, o, size, size), PINK, name=name + "_dot", shape=Shape.CIRCLE),
          box((o, o, size, size), PINK, name=name + "_lo", shape=Shape.CIRCLE, bg=False, outline=True),
          lbl(None, (o, o, size, size), str(number), 14 if size > 24 else 11, "#24103f",
              AlignH.CENTER),
          lbl(name + "_icon", (o + size * 0.6, o + size * 0.6, size, size), "", 16, TXT, AlignH.CENTER))
    return g


def build():
    doc = t.Document.new(frame=(0, 0, W, H), color=BG, background=True, outline=False)
    root = doc.root
    root.name = "seren.a IEM space"
    common = HERE.parent / "common"
    root.script = "\n".join((common / f).read_text() for f in ("monitor.lua", "levels.lua", "look.lua", "config.lua", "room.lua", "cpu.lua", "bank.lua")) + \
        "\n" + (HERE / "space_root.lua").read_text()
    k = header()
    k += [top_view(), pano_view(),
          square_bg("bg_top_mp", TOP, ("✧ vorn · Y +100 ✧", "hinten · Y −100", "X −100", "X +100")),
          square_bg("bg_pano_mp", PANO, ("rückansicht · Z +100 oben", "Z −100", "X −100", "X +100"))]
    k += room_ui.controls(box, lbl)        # ROOM view (dearVR PRO): top view in TOP, side view in PANO
    k.append(box(TOP, BG, name="top_area", bg=False))
    k.append(box(PANO, BG, name="pano_area", bg=False))
    k += detail()
    k += track_list()
    k.append(tiles32())
    for i in range(N32):                   # width: left/right edge of a StereoEncoder
        for side in ("wl", "wr"):
            k.append(box((-100, -100, 13, 13), PINK, name=f"{side}{i + 1}", shape=Shape.CIRCLE))
    for i in range(N32):
        k.append(dot(f"d{i + 1}", 30, 84, i + 1))
    for i in range(N32):
        k.append(dot(f"e{i + 1}", 20, 56, i + 1))
    # Zieh-Flächen ganz oben, unsichtbar
    for name, fr in (("top_xy", TOP), ("pano_xy", PANO)):
        xy = t.xy(name=name, frame=F(*fr), color=PINK, background=False, outline=False,
                  cursor=False, lines=False, grid_x=False, grid_y=False, script=DRAG_SCRIPT)
        xy.value("x").default = 0.5
        xy.value("y").default = 0.5
        k.append(xy)
    k += room_ui.zoom(box, lbl)            # above the drag areas
    cpu = lbl("cpu_lbl", (118, 68, 300, 16), "", 11, DIM)   # Auslastung (Option), neben der Versionsnummer
    cpu.set("visible", False)
    k.append(cpu)
    mon = t.group(name="mon_overlay", frame=F(16, 168, 914, 840), color=BG, background=True,
                  outline=False, visible=False)
    mon.add(box((0, 0, 914, 840), PANEL, radius=16),
            lbl(None, (16, 10, 880, 24), "✧ log ✧   ◆ vom DAW-Skript erkannt   ← kommt an   → geht raus",
                14, LAV),
            lbl("mon_text", (16, 42, 882, 786), "", 15, TXT, multi=True, valign=AlignV.TOP))
    k.append(mon)
    k.append(config_ui.build(W, H, with64=False))
    root.add(*k)
    return doc


if __name__ == "__main__":
    out = HERE / "dist"
    out.mkdir(exist_ok=True)
    doc = build()
    for issue in doc.validate():
        print("ISSUE:", issue)
    doc.save(out / "seren-a_IEM-Space.tosc")
    print("saved", sum(1 for _ in doc.walk()), "controls")
