"""Builds seren.a 3D-Panner + TotalMix TouchOSC layout (phone, landscape), v2.

v2: every OSC message that TouchOSC can do on its own sits on the control itself
(TotalMix like RME's TestTMOsc template, IEM faders/knobs); the root script only does
what needs code: circle maths, MultiPanner modes/MIDI, meter peak hold, EQ curve,
snapshot blinking, the Nuendo MIDI path.
"""
import math
import sys
from pathlib import Path

import py2tosc as t
from py2tosc import Shape, AlignH, AlignV, Font, ButtonType

HERE = Path(__file__).parent
W, H = 1600, 740
PAGER_W = 1180
TAB = 40
PAGE_H = H - TAB

BG = "#121418"
PANEL = "#1b1e24"
PAD_BG = "#181b21"
LINE = "#3a404b"
DIM_TXT = "#8b93a1"
TXT = "#e8ebf0"
ACCENT = "#36d0c4"      # MultiPanner
IEM_C = "#b28dff"       # IEM
RME_C = "#f2a33a"       # RME

CTRL_SCRIPT = """function onValueChanged(k)
  if k == 'x' or k == 'y' then
    if self.values.touch then root:notify('ui', self.name) else root:notify('fb', self.name) end
  end
  if k == 'touch' and not self.values.touch then root:notify('release', self.name) end
end
"""

# --- connections / native OSC ---------------------------------------------------------------
OSC_TM, OSC_ENC, OSC_ROT, OSC_MENC = 1, 2, 3, 4   # TouchOSC OSC connections: IEM encoder, IEM rotator, TotalMix
MAIN_STRIP, PH_STRIP = 1, 4          # TotalMix output strips (UCX: AN 1/2 = 1, PH 7/8 = 4)
MAIN_CH, PH_CH = 0, 6                # same outputs as channel numbers for /setBankStart


def conn(i):
    return "".join("1" if k == i else "0" for k in range(1, 11))


def osc(path, arg="x", send=True, receive=True, c=OSC_TM, lo=0.0, hi=1.0, conv="FLOAT",
        cond="ANY", const=None):
    """One OSC message as TouchOSC stores it: fixed path, one argument (or none)."""
    if const is not None:
        args = [t.Partial("CONSTANT", "FLOAT", str(const))]
    elif arg is None:
        args = []
    else:
        args = [t.Partial("VALUE", conv, arg, lo, hi)]
    return t.OscMessage(send=send, receive=receive, connections=conn(c),
                        triggers=[t.Trigger("x", cond)] if send else [],
                        path=[t.Partial("CONSTANT", "STRING", path)], arguments=args)


def recv_text(path, c=OSC_TM):
    return osc(path, "text", send=False, conv="STRING", c=c)


def page_select(page, channel=None):
    """TotalMix: /<page> selects the page (it then re-sends it), for page 2 also bus + channel."""
    m = [osc(f"/{page}", None, receive=False, cond="RISE")]
    if page in (1, 2):
        m.append(osc(f"/{page}/busOutput", receive=False, cond="RISE", const=1))
    if channel is not None:
        m.append(osc("/setBankStart", receive=False, cond="RISE", const=channel))
    return m


# IEM controls with their own OSC message (osc variant only): name -> connection, path, range
NATIVE_IEM = {
    "p2_el":    (OSC_ENC, "/StereoEncoder/elevation", -90, 90),
    "p2_pitch": (OSC_ROT, "/SceneRotator/pitch", -90, 90),
    "p3_az":    (OSC_ENC, "/StereoEncoder/azimuth", -180, 180),
    "p3_el":    (OSC_ENC, "/StereoEncoder/elevation", -90, 90),
    "p3_wid":   (OSC_ENC, "/StereoEncoder/width", -180, 180),
    "p4_el":    (OSC_MENC, "/MultiEncoder/masterElevation", -90, 90),
}
BTN_SCRIPT = """function onValueChanged(k)
  if k == 'touch' and self.values.touch then root:notify('btn', self.name) end
end
"""


def F(x, y, w, h):
    return (round(x), round(y), round(w), round(h))


def lbl(name, frame, text="", size=14, color=TXT, align=AlignH.CENTER,
        valign=AlignV.MIDDLE, mono=False, multi=False):
    maker = t.text if multi else t.label
    c = maker(frame=F(*frame), text_size=size, text_color=color,
              text_align_h=align, text_align_v=valign, background=False,
              outline=False, font=Font.MONOSPACED if mono else Font.DEFAULT)
    if name:
        c.name = name
    c.value("text").default = text
    return c


def box(frame, color, name=None, shape=Shape.RECTANGLE, bg=True, outline=False,
        radius=0.0):
    c = t.box(frame=F(*frame), color=color, shape=shape, background=bg,
              outline=outline, corner_radius=radius)
    if name:
        c.name = name
    return c


def button(name, frame, caption, color="#383c44", size=15):
    b = t.button(name=name, frame=F(*frame), color=color,
                 button_type=ButtonType.MOMENTARY, corner_radius=4,
                 outline=False, script=BTN_SCRIPT)
    cap = lbl(None, frame, caption, size=size, color=TXT)
    return [b, cap]


def radial(name, frame, color, centered=False):
    return t.radial(name=name, frame=F(*frame), color=color, centered=centered,
                    outline=False, grid=False, script=CTRL_SCRIPT)


def knob_block(name, x, y, size, title, color, centered=False):
    """Poti + Name + Zahl."""
    return [
        radial(name, (x, y, size, size), color, centered),
        lbl(name + "_title", (x - 30, y + size + 2, size + 60, 20), title, 15, DIM_TXT),
        lbl(name + "_val", (x - 30, y + size + 21, size + 60, 28), "–", 23, TXT),
    ]


def pad_block(prefix, pad, x, y, s, color):
    name = f"{prefix}_{pad}"
    items = [box((x, y, s, s), PAD_BG, radius=6)]
    # Raster: Ringe + Achsen (eigene Zeichnung, kein Steinberg-Screenshot)
    for r in (0.92, 0.62, 0.32):
        d = s * r
        items.append(box((x + (s - d) / 2, y + (s - d) / 2, d, d), LINE,
                         shape=Shape.CIRCLE, bg=False, outline=True))
    items.append(box((x + s / 2 - 0.5, y + 8, 1, s - 16), LINE))
    items.append(box((x + 8, y + s / 2 - 0.5, s - 16, 1), LINE))
    xy = t.xy(name=name, frame=F(x, y, s, s), color=color, background=False,
              outline=True, grid_x=False, grid_y=False, script=CTRL_SCRIPT)
    xy.value("x").default = 0.5
    xy.value("y").default = 0.5
    items.append(xy)
    items.append(lbl(name + "_title", (x + 10, y + 6, s - 20, 26), "", 17, color,
                     AlignH.LEFT))
    items.append(lbl(name + "_val", (x + 10, y + s - 36, s - 20, 30), "", 21, TXT,
                     AlignH.LEFT))
    return items


def multipanner_page(prefix, tab, right_column):
    page = t.group(name=prefix, frame=F(0, TAB, PAGER_W, PAGE_H), color=BG,
                   background=True, outline=False)
    page.tab_label = tab
    kids = []
    # MODE-Button (umschaltbare Pad-Belegung)
    kids += [t.button(name=f"{prefix}_mode", frame=F(8, 10, 108, 118), color=ACCENT,
                      corner_radius=6, outline=False, script=BTN_SCRIPT),
             lbl(f"{prefix}_modeLbl", (8, 10, 108, 118), "MODE\nPOSITION", 16, "#0d1013",
                 multi=True)]
    # Potis oben
    params = [("dist", "Distance"), ("div", "Divergence"), ("field", "Field Size"),
              ("src", "Source Size"), ("width", "Width"), ("depth", "Depth")]
    x0, step, ks = 160, 170, 74
    for i, (pid, title) in enumerate(params):
        kids += knob_block(f"{prefix}_k_{pid}", x0 + i * step, 8, ks, title, ACCENT)
    # Pads
    s, py = 520, 148
    kids += pad_block(prefix, "pad1", 6, py, s, ACCENT)
    kids += pad_block(prefix, "pad2", 6 + s + 10, py, s, ACCENT)
    # rechte Spalte
    cx, cs = 1062 + 14, 86
    for j, (name, title, color, centered) in enumerate(right_column):
        kids += knob_block(name, cx, py + 2 + j * 176, cs - 8, title, color, centered)
    page.add(*kids)
    return page


def iem_page():
    page = t.group(name="p2", frame=F(0, TAB, PAGER_W, PAGE_H), color=BG,
                   background=True, outline=False)
    page.tab_label = "IEM"
    kids = []
    s, y = 486, 96

    def circle(prefix, x, title, color):
        n = f"p2_{prefix}Circle"
        items = [lbl(f"p2_{prefix}Title", (x, 14, s, 30), title, 20, color, AlignH.LEFT),
                 box((x, y, s, s), PAD_BG, shape=Shape.CIRCLE)]
        for r in (1.0, 0.66, 0.33):
            d = s * r
            items.append(box((x + (s - d) / 2, y + (s - d) / 2, d, d), LINE,
                             shape=Shape.CIRCLE, bg=False, outline=True))
        items.append(box((x + s / 2 - 0.5, y, 1, s), LINE))
        items.append(box((x, y + s / 2 - 0.5, s, 1), LINE))
        # Gradmarken alle 30°
        for a in range(0, 360, 30):
            r = math.radians(a)
            px = x + s / 2 - math.sin(r) * (s / 2 - 10)
            pyy = y + s / 2 - math.cos(r) * (s / 2 - 10)
            items.append(box((px - 2.5, pyy - 2.5, 5, 5), "#5b6372", shape=Shape.CIRCLE))
        items += [lbl(None, (x + s / 2 - 50, y - 26, 100, 22), "0° vorn", 16, DIM_TXT),
                  lbl(None, (x + s / 2 - 50, y + s + 2, 100, 22), "180°", 16, DIM_TXT),
                  lbl(None, (x + 4, y + s / 2 - 36, 80, 24), "+90° L", 16, DIM_TXT,
                      AlignH.LEFT),
                  lbl(None, (x + s - 84, y + s / 2 - 36, 80, 24), "−90° R", 16, DIM_TXT,
                      AlignH.RIGHT)]
        xy = t.xy(name=n, frame=F(x, y, s, s), color=color, background=False,
                  outline=False, cursor=False, lines=False, grid_x=False, grid_y=False,
                  script=CTRL_SCRIPT)
        xy.value("x").default = 0.5
        xy.value("y").default = 0.5
        items.append(xy)
        items.append(lbl(n + "_val", (x + s / 2 - 110, y + s / 2 + 12, 220, 46),
                         "+0.0°", 34, TXT))
        mk = 34
        items.append(box((x + s / 2 - mk / 2, y + s * 0.04 - mk / 2 + 0, mk, mk), color,
                         name=f"p2_{prefix}Mark", shape=Shape.CIRCLE))
        return items

    def vfader(name, x, title, color):
        f = t.fader(name=name, frame=F(x, y, 66, s), color=color, outline=False,
                    centered=True, script=CTRL_SCRIPT)
        f.value("x").default = 0.5
        return [lbl(name + "_title", (x - 20, 46, 106, 26), title, 17, color),
                f,
                lbl(name + "_val", (x - 34, y + s + 4, 134, 30), "+0.0°", 22, TXT)]

    kids += circle("enc", 10, "IEM StereoEncoder · Azimuth", IEM_C)
    kids += vfader("p2_el", 508, "ELEV", IEM_C)
    kids += circle("rot", 596, "IEM SceneRotator · Yaw", IEM_C)
    kids += vfader("p2_pitch", 1096, "PITCH", IEM_C)
    page.add(*kids)
    return page


def led_button(name, frame, caption, recv_path, send_msgs, color=RME_C, size=15):
    """RME pattern: a receive-only LED button under a transparent momentary send button."""
    led = t.button(name=name + "_led", frame=F(*frame), color=color, corner_radius=4,
                   outline=False, interactive=False, messages=[osc(recv_path, send=False)])
    hit = t.button(name=name, frame=F(*frame), color="#00000000", background=False,
                   outline=True, corner_radius=4, button_type=ButtonType.MOMENTARY,
                   messages=send_msgs, script=BTN_SCRIPT)
    return [led, lbl(None, frame, caption, size=size, color=TXT), hit]


def nbutton(name, frame, caption, msgs, size=15, color="#383c44"):
    b = t.button(name=name, frame=F(*frame), color=color, button_type=ButtonType.MOMENTARY,
                 corner_radius=4, outline=False, messages=msgs, script=BTN_SCRIPT)
    return [b, lbl(None, frame, caption, size=size, color=TXT)]


def meter(name, x, y, w, h, path):
    f = t.fader(name=name, frame=F(x, y, w, h), color="#3fd977", interactive=False,
                outline=False, grid=False, cursor=False, messages=[osc(path, send=False)])
    return [f, box((x, y + h - 2, w, 2), "#ffffff", name=name + "_hold")]


def multi_page():
    """OSC variant only: IEM MultiEncoder master direction over OSC 4 (Listen 8003, Sender 9103)."""
    page = t.group(name="p4", frame=F(0, TAB, PAGER_W, PAGE_H), color=BG, background=True,
                   outline=False)
    page.tab_label = "MULTI (OSC)"
    s, x, y = 486, 10, 96
    n = "p4_encCircle"
    k = [lbl("p4_encTitle", (x, 18, s, 26), "IEM MultiEncoder · Master Azimuth (OSC 4)", 17, IEM_C,
             AlignH.LEFT),
         box((x, y, s, s), PAD_BG, shape=Shape.CIRCLE)]
    for r in (1.0, 0.66, 0.33):
        d = s * r
        k.append(box((x + (s - d) / 2, y + (s - d) / 2, d, d), LINE, shape=Shape.CIRCLE, bg=False,
                     outline=True))
    k += [box((x + s / 2 - 0.5, y, 1, s), LINE), box((x, y + s / 2 - 0.5, s, 1), LINE),
          lbl(None, (x + s / 2 - 50, y - 26, 100, 22), "0° vorn", 16, DIM_TXT),
          lbl(None, (x + 4, y + s / 2 - 36, 80, 24), "+90° L", 16, DIM_TXT, AlignH.LEFT),
          lbl(None, (x + s - 84, y + s / 2 - 36, 80, 24), "−90° R", 16, DIM_TXT, AlignH.RIGHT)]
    xy = t.xy(name=n, frame=F(x, y, s, s), color=IEM_C, background=False, outline=False,
              cursor=False, lines=False, grid_x=False, grid_y=False, script=CTRL_SCRIPT)
    xy.value("x").default = 0.5
    xy.value("y").default = 0.5
    k += [xy, lbl(n + "_val", (x + s / 2 - 110, y + s / 2 + 12, 220, 46), "+0.0°", 34, TXT),
          box((x + s / 2 - 17, y + s * 0.04 - 17, 34, 34), IEM_C, name="p4_encMark", shape=Shape.CIRCLE)]
    f = t.fader(name="p4_el", frame=F(508, y, 66, s), color=IEM_C, outline=False, centered=True,
                script=CTRL_SCRIPT)
    f.value("x").default = 0.5
    k += [lbl("p4_el_title", (488, 50, 106, 22), "M-ELEV", 14, IEM_C), f,
          lbl("p4_el_val", (478, y + s + 4, 126, 26), "+0.0°", 18, TXT),
          lbl(None, (610, 96, 540, 300),
              "Für den IEM MultiEncoder per OSC:\n\n"
              "Im Plugin unten links auf OSC:\n"
              "  Listen to port 8003 → OPEN\n"
              "  Sender: IP vom Handy, Port 9103 → CONNECT\n\n"
              "TouchOSC › Verbindungen › OSC 4:\n"
              "  Host = IP vom Mac, Send 8003, Receive 9103\n\n"
              "Die einzelnen Eingänge siehst du in der\nObjekt-Übersicht bzw. im IEM space (Seite MULTI).",
              15, DIM_TXT, AlignH.LEFT, AlignV.TOP, multi=True)]
    page.add(*k)
    return page


def monitor_page():
    page = t.group(name="p5", frame=F(0, TAB, PAGER_W, PAGE_H), color=BG, background=True,
                   outline=False)
    page.tab_label = "MONITOR"
    page.add(lbl(None, (14, 10, 1150, 28),
                 "◆ vom DAW-Skript erkannt   ← kommt an   → geht raus   (neueste oben)", 15, DIM_TXT,
                 AlignH.LEFT),
             box((10, 44, 1160, PAGE_H - 54), PAD_BG, radius=6),
             lbl("mon_text", (22, 54, 1136, PAGE_H - 74), "", 17, TXT, AlignH.LEFT, AlignV.TOP,
                 multi=True))
    return page


def rme_panel(variant="osc"):
    g = t.group(name="rme", frame=F(PAGER_W + 4, 0, W - PAGER_W - 4, H), color=PANEL,
                background=True, outline=False)
    k = []
    # Snapshots: press loads (page 3), release returns TotalMix to page 1 (meters, volumes)
    for i in range(4):
        row = 8 - i                                  # snapshot 1 = /3/snapshots/8/1
        k += led_button(f"snap{i + 1}", (6 + i * 68, 6, 64, 44), f"S{i + 1}",
                        f"/3/snapshots/{row}/1",
                        [osc(f"/3/snapshots/{row}/1", receive=False),
                         osc("/1", None, receive=False, cond="FALL")], size=17)
    # MAIN
    k.append(lbl(None, (6, 58, 150, 22), "MAIN", 15, RME_C, AlignH.LEFT))
    k.append(t.radial(name="tm_main", frame=F(6, 82, 148, 148), color=RME_C, outline=False,
                      grid=False, messages=[osc("/1/mastervolume")]))
    k.append(t.label(name="tm_main_val", frame=F(156, 120, 120, 50), text_size=26,
                     text_color=TXT, text_align_h=AlignH.RIGHT, background=False, outline=False,
                     messages=[recv_text("/1/mastervolumeVal")]))
    k += led_button("tm_dim", (6, 240, 84, 40), "DIM", "/1/mainDim",
                    [osc("/1/mainDim", receive=False)])
    k += nbutton("tm_eqMain", (96, 240, 84, 40), "EQ", page_select(2, MAIN_CH))
    # PHONES
    k.append(lbl(None, (6, 298, 150, 22), "PHONES", 15, RME_C, AlignH.LEFT))
    k.append(t.radial(name="tm_ph", frame=F(6, 322, 148, 148), color=RME_C, outline=False,
                      grid=False, messages=[osc(f"/1/volume{PH_STRIP}")]))
    k.append(t.label(name="tm_ph_val", frame=F(156, 360, 120, 50), text_size=26,
                     text_color=TXT, text_align_h=AlignH.RIGHT, background=False, outline=False,
                     messages=[recv_text(f"/1/volume{PH_STRIP}Val")]))
    k.append(t.button(name="tm_phMute", frame=F(6, 480, 84, 40), color="#ff4a3d",
                      button_type=ButtonType.TOGGLE_RELEASE, corner_radius=4, outline=False,
                      messages=[osc(f"/1/mute/1/{PH_STRIP}")]))
    k.append(lbl(None, (6, 480, 84, 40), "MUTE", 15, TXT))
    k += nbutton("tm_eqPh", (96, 480, 84, 40), "EQ", page_select(2, PH_CH))
    if variant == "nuendo":
        k.append(lbl(None, (6, 534, 270, 18), "DAW · GEWÄHLTE SPUR", 13, IEM_C, AlignH.LEFT))
        k.append(lbl("nu_track", (6, 552, 270, 46), "–", 28, TXT, AlignH.LEFT))
        k += button("nu_prev", (6, 604, 130, 50), "◂  SPUR", size=16)
        k += button("nu_next", (146, 604, 130, 50), "SPUR  ▸", size=16)
    else:
        k.append(lbl(None, (6, 540, 270, 120),
                     "Snapshot hell = aktiv\nblinkt = seit Laden geändert\n"
                     "EQ öffnet die Kurve für Main/Phones",
                     12, DIM_TXT, AlignH.LEFT, AlignV.TOP, multi=True))
    k += nbutton("tm_sync", (6, 688, 120, 44), "SYNC TM", page_select(1, 0))
    # Meter: PH | MAIN, straight from TotalMix (/1/levelNLeft|Right), peak hold by script
    for out, x, cap, strip in (("ph", 284, "PH", PH_STRIP), ("main", 348, "MAIN", MAIN_STRIP)):
        k.append(lbl(f"mt_{out}_peak", (x - 4, 6, 64, 22), "-∞", 15, TXT))
        k.append(lbl(None, (x - 4, 28, 64, 16), "peak", 11, DIM_TXT))
        k.append(box((x - 2, 46, 62, 640), "#0d0f12"))
        k += meter(f"mt_{out}_L", x, 48, 27, 636, f"/1/level{strip}Left")
        k += meter(f"mt_{out}_R", x + 31, 48, 27, 636, f"/1/level{strip}Right")
        k.append(lbl(None, (x - 4, 690, 64, 22), cap, 15, RME_C))
        k.append(lbl(None, (x - 4, 712, 64, 18), "L    R", 11, DIM_TXT))
    g.add(*k)
    return g


def pan_panel(variant="osc"):
    """Rechte Spalte des Panners ohne TotalMix: Spur (Nuendo) + alle Werte auf einen Blick."""
    g = t.group(name="pan_panel", frame=F(PAGER_W + 4, 0, W - PAGER_W - 4, H), color=PANEL,
                background=True, outline=False)
    k = [lbl(None, (12, 8, 390, 32), "seren.a · 3D PAN", 20, TXT, AlignH.LEFT)]
    y = 48
    if variant == "nuendo":
        k.append(lbl(None, (12, y - 4, 390, 18), "DAW · GEWÄHLTE SPUR", 14, IEM_C, AlignH.LEFT))
        k.append(lbl("nu_track", (12, y + 14, 400, 48), "–", 32, TXT, AlignH.LEFT))
        k += button("nu_prev", (12, y + 66, 194, 56), "◂  SPUR", size=19)
        k += button("nu_next", (212, y + 66, 194, 56), "SPUR  ▸", size=19)
    else:
        k.append(lbl(None, (12, y, 390, 110),
                     "IEM direkt per OSC: OSC 2 Encoder, OSC 3 Rotator,\nOSC 4 MultiEncoder\n"
                     "MultiPanner per MIDI 1 über die TouchOSC Bridge",
                     13, DIM_TXT, AlignH.LEFT, AlignV.TOP, multi=True))
    cw, ch = 128, 66

    def grid(title, color, y0, items):
        out = [lbl(None, (12, y0, 390, 24), title, 16, color, AlignH.LEFT),
               box((12, y0 + 26, 392, 1), LINE)]
        for i, (pid, name) in enumerate(items):
            r, c = divmod(i, 3)
            x, yy = 12 + c * (cw + 4), y0 + 32 + r * ch
            out.append(lbl(None, (x, yy, cw, 20), name, 14, DIM_TXT, AlignH.LEFT))
            out.append(lbl(f"ro_{pid}", (x, yy + 20, cw, 40), "–", 30, TXT, AlignH.LEFT))
        return out

    k += grid("MULTIPANNER", ACCENT, 186, [
        ("x", "X"), ("y", "Y"), ("z", "Z"), ("rotz", "Rot Z"), ("tilty", "Tilt Y"),
        ("tiltx", "Tilt X"), ("dist", "Distance"), ("div", "Divergence"),
        ("field", "Field Size"), ("src", "Source Size"), ("width", "Width"),
        ("depth", "Depth")])
        # 4 Reihen bis y ~ 446
    k += grid("IEM", IEM_C, 484, [("az", "Azimuth"), ("el", "Elevation"), ("wid", "Width"),
                                  ("yaw", "Yaw"), ("pitch", "Pitch")])
    k.append(lbl(None, (12, 684, 400, 52),
                 "MODE (Seite 1 und 3): was die Pads steuern –\n"
                 "Position · Größe · Spread", 13, DIM_TXT, AlignH.LEFT, AlignV.TOP, multi=True))
    g.add(*k)
    return g


def eq_overlay():
    """One EQ view (TotalMix page 2 shows one channel at a time): Main or Phones."""
    g = t.group(name="eq_overlay", frame=F(0, 0, PAGER_W, H), color="#0f1115",
                background=True, outline=False, visible=False)
    k = []
    k.append(lbl("eq_title", (14, 12, 300, 36), "EQ · MAIN", 22, RME_C, AlignH.LEFT))
    k.append(t.label(name="eq_track", frame=F(320, 12, 260, 36), text_size=16, text_color=DIM_TXT,
                     text_align_h=AlignH.LEFT, background=False, outline=False,
                     messages=[recv_text("/2/trackname")]))
    k += nbutton("eq_sel_m", (600, 10, 120, 40), "MAIN", page_select(2, MAIN_CH))
    k += nbutton("eq_sel_p", (726, 10, 120, 40), "PHONES", page_select(2, PH_CH))
    k += led_button("eq_on", (900, 10, 120, 40), "EQ", "/2/eqEnable",
                    [osc("/2/eqEnable", receive=False)])
    k += led_button("eq_lc", (1026, 10, 140, 40), "LOW CUT", "/2/lowcutEnable",
                    [osc("/2/lowcutEnable", receive=False)])
    bx, by, bw, bh = 14, 64, 1152, 380
    k.append(box((bx, by, bw, bh), PAD_BG, name="eq_bg"))
    for db in (-12, -6, 6, 12):
        k.append(box((bx, by + bh / 2 - db / 20 * bh / 2, bw, 1), "#262a32"))
        k.append(lbl(None, (bx + 4, by + bh / 2 - db / 20 * bh / 2 - 9, 40, 18), f"{db:+d}", 11,
                     DIM_TXT, AlignH.LEFT))
    for f in (50, 100, 200, 500, 1000, 2000, 5000, 10000):
        xx = bx + bw * math.log(f / 20) / math.log(1000)
        k.append(box((xx, by, 1, bh), "#262a32"))
        k.append(lbl(None, (xx - 30, by + bh + 2, 60, 18), f"{f // 1000}k" if f >= 1000 else str(f),
                     11, DIM_TXT))
    k.append(box((bx, by + bh / 2, bw, 1), "#4a5160"))
    n = 48
    for i in range(n):
        k.append(box((bx + i * bw / n + 1, by + bh / 2, bw / n - 2, 1), RME_C, name=f"eq_b{i + 1}"))
    # value table, every cell straight from TotalMix
    cols = (("BAND", 14, 90), ("TYPE", 110, 200), ("FREQ", 320, 160), ("GAIN", 490, 160), ("Q", 660, 120))
    ty = 476
    for title, x, w in cols:
        k.append(lbl(None, (x, ty, w, 24), title, 12, DIM_TXT, AlignH.LEFT))
    for b in (1, 2, 3):
        y = ty + 28 + (b - 1) * 34
        k.append(lbl(None, (14, y, 90, 30), str(b), 18, TXT, AlignH.LEFT))
        if b == 2:
            k.append(lbl(None, (110, y, 200, 30), "Bell", 18, TXT, AlignH.LEFT))
        else:
            k.append(t.label(name=f"eq_type{b}", frame=F(110, y, 200, 30), text_size=18, text_color=TXT,
                             text_align_h=AlignH.LEFT, background=False, outline=False,
                             messages=[recv_text(f"/2/eqType{b}Val")]))
        for key, x, w in (("Freq", 320, 160), ("Gain", 490, 160), ("Q", 660, 120)):
            k.append(t.label(name=f"eq_{key.lower()}{b}", frame=F(x, y, w, 30), text_size=18,
                             text_color=TXT, text_align_h=AlignH.LEFT, background=False, outline=False,
                             messages=[recv_text(f"/2/eq{key}{b}Val")]))
    y = ty + 28 + 3 * 34
    k.append(lbl(None, (14, y, 90, 30), "LC", 18, TXT, AlignH.LEFT))
    k.append(t.label(name="eq_lcfreq", frame=F(320, y, 160, 30), text_size=18, text_color=TXT,
                     text_align_h=AlignH.LEFT, background=False, outline=False,
                     messages=[recv_text("/2/lowcutFreqVal")]))
    k.append(t.label(name="eq_lcgrade", frame=F(490, y, 160, 30), text_size=18, text_color=TXT,
                     text_align_h=AlignH.LEFT, background=False, outline=False,
                     messages=[recv_text("/2/lowcutGradeVal")]))
    k += nbutton("eq_close", (PAGER_W - 160, 670, 146, 50), "ZURÜCK", [osc("/1", None, receive=False, cond="RISE")], size=16)
    g.add(*k)
    return g


def build(variant="osc", tm=True):
    doc = t.Document.new(frame=(0, 0, W, H), color=BG, background=True, outline=False)
    root = doc.root
    root.name = "seren.a Panner " + ("OSC" if variant == "osc" else "Skript") + (" + TotalMix" if tm else "")
    script = (HERE.parent / "common" / "monitor.lua").read_text() + "\n" + (HERE / "root.lua").read_text()
    if variant == "nuendo":
        assert "  iemVia = 'osc'," in script
        script = script.replace("  iemVia = 'osc',", "  iemVia = 'midi',")
    if not tm:
        assert "  withTM = true," in script
        script = script.replace("  withTM = true,", "  withTM = false,")
    root.script = script

    pager = t.pager(name="pager", frame=F(0, 0, PAGER_W, H), color="#20242b",
                    tabbar_size=TAB, text_size_on=15, text_size_off=15)
    p1 = multipanner_page("p1", "MULTIPANNER", [
        ("p1_k_rotz", "Rot Z", ACCENT, True),
        ("p1_k_tilty", "Tilt Y", ACCENT, True),
        ("p1_k_tiltx", "Tilt X", ACCENT, True),
    ])
    p3 = multipanner_page("p3", "MP + IEM", [
        ("p3_az", "IEM Azimuth", IEM_C, True),
        ("p3_el", "IEM Elevation", IEM_C, True),
        ("p3_wid", "IEM Width", IEM_C, True),
    ])
    pager.add(p1, iem_page(), p3)
    if variant == "osc":
        pager.add(multi_page())
    pager.add(monitor_page())
    if tm:
        root.add(pager, rme_panel(variant), eq_overlay())
    else:
        root.add(pager, pan_panel(variant))

    # IEM knobs/faders: their own OSC messages in the osc variant (Nuendo variant: MIDI by script)
    if variant == "osc":
        for name, (c, path, lo, hi) in NATIVE_IEM.items():
            ctl = doc.find(name)
            ctl.messages.append(osc(path, c=c, lo=lo, hi=hi))

    # Startwerte der bipolaren Potis in die Mitte
    for c in doc.walk():
        if c.control_type.value == "RADIAL" and c.get("centered"):
            c.value("x").default = 0.5
    return doc


if __name__ == "__main__":
    for variant, tm, name in (("osc", True, "seren-a_Panner_OSC_TotalMix.tosc"),
                              ("nuendo", True, "seren-a_Panner_Skript_TotalMix.tosc"),
                              ("osc", False, "seren-a_Panner_OSC.tosc"),
                              ("nuendo", False, "seren-a_Panner_Skript.tosc")):
        out = HERE / name
        doc = build(variant, tm)
        for i in doc.validate():
            print("ISSUE:", i)
        doc.save(out)
        print("saved", out, sum(1 for _ in doc.walk()), "controls")
