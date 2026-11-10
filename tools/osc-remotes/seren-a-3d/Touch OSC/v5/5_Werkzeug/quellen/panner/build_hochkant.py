"""Builds the portrait (hochkant) Panner Skript layouts: 740 x 1600 phone portrait.

Same root script as the landscape version (build.py); the script only reads positions from the
frames. Top: selected track. Middle: pages (one big top view with Z as a fader, the knobs below).
Bottom: TotalMix, or all values in large type.
"""
import math
from pathlib import Path

import py2tosc as t
from py2tosc import Shape, AlignH, AlignV, ButtonType

import build as B
from build import (F, lbl, box, button, knob_block, pad_block, led_button, nbutton, meter, osc,
                   recv_text, page_select, BTN_SCRIPT, CTRL_SCRIPT, BG, PANEL, PAD_BG, LINE, DIM_TXT,
                   TXT, ACCENT, IEM_C, RME_C, MAIN_STRIP, PH_STRIP, MAIN_CH, PH_CH)

HERE = Path(__file__).parent
W, H = 740, 1600
HDR_H = 104                     # oben: gewählte Spur, immer sichtbar
TAB = 44
PAGER_Y = HDR_H + 4
PANEL_H = 470                   # unten: TotalMix bzw. alle Werte
PANEL_Y = H - PANEL_H
PAGER_H = PANEL_Y - 4 - PAGER_Y
PAGE_H = PAGER_H - TAB


def page_group(name, tab):
    g = t.group(name=name, frame=F(0, TAB, W, PAGE_H), color=BG, background=True, outline=False)
    g.tab_label = tab
    return g


def header():
    g = t.group(name="hdr", frame=F(0, 0, W, HDR_H), color=PANEL, background=True, outline=False)
    k = [lbl(None, (14, 6, 460, 20), "DAW · GEWÄHLTE SPUR", 14, IEM_C, AlignH.LEFT),
         lbl("nu_track", (14, 26, 462, 70), "–", 36, TXT, AlignH.LEFT)]
    k += button("nu_prev", (486, 12, 120, 80), "◂", size=34)
    k += button("nu_next", (612, 12, 120, 80), "▸", size=34)
    g.add(*k)
    return g


def multipanner_page(prefix, tab, knobs):
    """One big top view (80 % of the width) with Z as a fader next to it; the knobs below."""
    page = page_group(prefix, tab)
    kids = [t.button(name=f"{prefix}_mode", frame=F(8, 8, 250, 64), color=ACCENT, corner_radius=6,
                     outline=False, script=BTN_SCRIPT),
            lbl(f"{prefix}_modeLbl", (8, 8, 250, 64), "MODE\nPOSITION", 18, "#0d1013", multi=True),
            lbl(None, (270, 8, 462, 64), "oben = vorn · MODE wechselt, was das Feld steuert", 15, DIM_TXT,
                AlignH.LEFT)]
    s, py = 596, 82
    kids += pad_block(prefix, "pad1", 8, py, s, ACCENT)
    # Z: vertical fader (handled like a knob: <page>_k_z)
    zx, zw = 616, 116
    f = t.fader(name=f"{prefix}_k_z", frame=F(zx, py + 34, zw, s - 72), color=ACCENT, outline=False,
                centered=True, script=CTRL_SCRIPT)
    f.value("x").default = 0.5
    kids += [lbl(f"{prefix}_k_z_title", (zx, py, zw, 30), "Z  Höhe", 18, ACCENT), f,
             lbl(f"{prefix}_k_z_val", (zx - 6, py + s - 34, zw + 12, 34), "–", 24, TXT)]
    ks, cw = 72, 148
    y0 = py + s + 18
    for i, (name, title, color, centered) in enumerate(knobs):
        r, c = divmod(i, 5)
        n_in_row = min(5, len(knobs) - r * 5)
        x = (W - n_in_row * cw) / 2 + c * cw + (cw - ks) / 2
        kids += knob_block(name, x, y0 + r * 136, ks, title, color, centered)
    page.add(*kids)
    return page


def iem_circle(prefix, x, y, s, title, color):
    n = f"p2_{prefix}Circle"
    items = [lbl(f"p2_{prefix}Title", (x, y - 60, s + 120, 30), title, 20, color, AlignH.LEFT),
             box((x, y, s, s), PAD_BG, shape=Shape.CIRCLE)]
    for r in (1.0, 0.66, 0.33):
        d = s * r
        items.append(box((x + (s - d) / 2, y + (s - d) / 2, d, d), LINE, shape=Shape.CIRCLE, bg=False,
                         outline=True))
    items += [box((x + s / 2 - 0.5, y, 1, s), LINE), box((x, y + s / 2 - 0.5, s, 1), LINE)]
    for a in range(0, 360, 30):
        rr = math.radians(a)
        px = x + s / 2 - math.sin(rr) * (s / 2 - 10)
        pyy = y + s / 2 - math.cos(rr) * (s / 2 - 10)
        items.append(box((px - 2.5, pyy - 2.5, 5, 5), "#5b6372", shape=Shape.CIRCLE))
    items += [lbl(None, (x + s / 2 - 60, y - 28, 120, 24), "0° vorn", 16, DIM_TXT),
              lbl(None, (x + s / 2 - 60, y + s + 2, 120, 24), "180°", 16, DIM_TXT),
              lbl(None, (x + 4, y + s / 2 - 36, 70, 24), "+90° L", 16, DIM_TXT, AlignH.LEFT),
              lbl(None, (x + s - 76, y + s / 2 - 36, 72, 24), "−90° R", 16, DIM_TXT, AlignH.RIGHT)]
    xy = t.xy(name=n, frame=F(x, y, s, s), color=color, background=False, outline=False, cursor=False,
              lines=False, grid_x=False, grid_y=False, script=CTRL_SCRIPT)
    xy.value("x").default = 0.5
    xy.value("y").default = 0.5
    items += [xy, lbl(n + "_val", (x + s / 2 - 120, y + s / 2 + 12, 240, 50), "+0.0°", 38, TXT)]
    mk = 36
    items.append(box((x + s / 2 - mk / 2, y + s * 0.04 - mk / 2, mk, mk), color, name=f"p2_{prefix}Mark",
                     shape=Shape.CIRCLE))
    return items


def vfader(name, x, y, h, title, color):
    f = t.fader(name=name, frame=F(x, y, 110, h), color=color, outline=False, centered=True,
                script=CTRL_SCRIPT)
    f.value("x").default = 0.5
    return [lbl(name + "_title", (x - 10, y - 30, 130, 26), title, 18, color), f,
            lbl(name + "_val", (x - 20, y + h + 2, 150, 30), "+0.0°", 24, TXT)]


def iem_page():
    page = page_group("p2", "IEM")
    s = 396
    y1 = 64
    y2 = y1 + s + 88
    kids = iem_circle("enc", 14, y1, s, "IEM StereoEncoder · Azimuth", IEM_C)
    kids += vfader("p2_el", 560, y1, s - 16, "ELEV", IEM_C)
    kids += iem_circle("rot", 14, y2, s, "IEM SceneRotator · Yaw", IEM_C)
    kids += vfader("p2_pitch", 560, y2, s - 16, "PITCH", IEM_C)
    page.add(*kids)
    return page


def monitor_page():
    page = page_group("p5", "MONITOR")
    page.add(lbl(None, (14, 10, W - 28, 28), "◆ erkannt   ← kommt an   → geht raus   (neueste oben)", 16,
                 DIM_TXT, AlignH.LEFT),
             box((10, 44, W - 20, PAGE_H - 54), PAD_BG, radius=6),
             lbl("mon_text", (22, 54, W - 44, PAGE_H - 74), "", 17, TXT, AlignH.LEFT, AlignV.TOP, multi=True))
    return page


def rme_panel():
    g = t.group(name="rme", frame=F(0, PANEL_Y, W, PANEL_H), color=PANEL, background=True, outline=False)
    k = []
    for i in range(4):
        row = 8 - i
        k += led_button(f"snap{i + 1}", (6 + i * 86, 6, 80, 52), f"S{i + 1}", f"/3/snapshots/{row}/1",
                        [osc(f"/3/snapshots/{row}/1", receive=False), osc("/1", None, receive=False, cond="FALL")],
                        size=20)
    k += nbutton("tm_sync", (356, 6, 140, 52), "SYNC TM", page_select(1, 0), size=17)
    k.append(lbl(None, (6, 66, 160, 24), "MAIN", 18, RME_C, AlignH.LEFT))
    k.append(lbl(None, (296, 66, 160, 24), "PHONES", 18, RME_C, AlignH.LEFT))
    k.append(t.radial(name="tm_main", frame=F(6, 94, 170, 170), color=RME_C, outline=False, grid=False,
                      messages=[osc("/1/mastervolume")]))
    k.append(t.label(name="tm_main_val", frame=F(176, 150, 112, 50), text_size=26, text_color=TXT,
                     text_align_h=AlignH.RIGHT, background=False, outline=False,
                     messages=[recv_text("/1/mastervolumeVal")]))
    k += led_button("tm_dim", (6, 276, 96, 52), "DIM", "/1/mainDim", [osc("/1/mainDim", receive=False)], size=18)
    k += nbutton("tm_eqMain", (108, 276, 96, 52), "EQ", page_select(2, MAIN_CH), size=18)
    k.append(t.radial(name="tm_ph", frame=F(296, 94, 170, 170), color=RME_C, outline=False, grid=False,
                      messages=[osc(f"/1/volume{PH_STRIP}")]))
    k.append(t.label(name="tm_ph_val", frame=F(466, 150, 112, 50), text_size=26, text_color=TXT,
                     text_align_h=AlignH.RIGHT, background=False, outline=False,
                     messages=[recv_text(f"/1/volume{PH_STRIP}Val")]))
    k.append(t.button(name="tm_phMute", frame=F(296, 276, 96, 52), color="#ff4a3d",
                      button_type=ButtonType.TOGGLE_RELEASE, corner_radius=4, outline=False,
                      messages=[osc(f"/1/mute/1/{PH_STRIP}")]))
    k.append(lbl(None, (296, 276, 96, 52), "MUTE", 18, TXT))
    k += nbutton("tm_eqPh", (398, 276, 96, 52), "EQ", page_select(2, PH_CH), size=18)
    k.append(lbl(None, (6, 346, 570, 80), "Snapshot hell = aktiv · blinkt = seit Laden geändert\n"
                 "EQ öffnet die Kurve für Main / Phones", 15, DIM_TXT, AlignH.LEFT, AlignV.TOP, multi=True))
    mh = PANEL_H - 104
    for out, x, cap, strip in (("ph", 600, "PH", PH_STRIP), ("main", 670, "MAIN", MAIN_STRIP)):
        k.append(lbl(f"mt_{out}_peak", (x - 6, 6, 68, 24), "-∞", 17, TXT))
        k.append(lbl(None, (x - 6, 28, 68, 16), "peak", 12, DIM_TXT))
        k.append(box((x - 2, 46, 62, mh + 4), "#0d0f12"))
        k += meter(f"mt_{out}_L", x, 48, 27, mh, f"/1/level{strip}Left")
        k += meter(f"mt_{out}_R", x + 31, 48, 27, mh, f"/1/level{strip}Right")
        k.append(lbl(None, (x - 6, 54 + mh, 68, 22), cap, 16, RME_C))
        k.append(lbl(None, (x - 6, 76 + mh, 68, 18), "L    R", 12, DIM_TXT))
    g.add(*k)
    return g


def pan_panel():
    """All values, large: MultiPanner 3 rows, IEM 2 rows."""
    g = t.group(name="pan_panel", frame=F(0, PANEL_Y, W, PANEL_H), color=PANEL, background=True, outline=False)
    cw, ch = 180, 76
    k = []

    def grid(title, color, y0, items):
        out = [lbl(None, (12, y0, 400, 26), title, 17, color, AlignH.LEFT), box((12, y0 + 28, W - 24, 1), LINE)]
        for i, (pid, name) in enumerate(items):
            r, c = divmod(i, 4)
            x, yy = 12 + c * (cw + 2), y0 + 34 + r * ch
            out.append(lbl(None, (x, yy, cw, 22), name, 16, DIM_TXT, AlignH.LEFT))
            out.append(lbl(f"ro_{pid}", (x, yy + 22, cw, 48), "–", 36, TXT, AlignH.LEFT))
        return out

    k += grid("MULTIPANNER", ACCENT, 6, [
        ("x", "X"), ("y", "Y"), ("z", "Z"), ("rotz", "Rot Z"), ("tilty", "Tilt Y"), ("tiltx", "Tilt X"),
        ("dist", "Distance"), ("div", "Divergence"), ("field", "Field Size"), ("src", "Source Size"),
        ("width", "Width"), ("depth", "Depth")])
    k += grid("IEM", IEM_C, 6 + 34 + 3 * ch + 8, [("az", "Azimuth"), ("el", "Elevation"), ("wid", "Width"),
                                                  ("yaw", "Yaw"), ("pitch", "Pitch")])
    g.add(*k)
    return g


def eq_overlay():
    g = t.group(name="eq_overlay", frame=F(0, PAGER_Y, W, PAGER_H), color="#0f1115", background=True,
                outline=False, visible=False)
    k = [lbl("eq_title", (14, 10, 260, 36), "EQ · MAIN", 22, RME_C, AlignH.LEFT),
         t.label(name="eq_track", frame=F(280, 10, 446, 36), text_size=16, text_color=DIM_TXT,
                 text_align_h=AlignH.LEFT, background=False, outline=False, messages=[recv_text("/2/trackname")])]
    k += nbutton("eq_sel_m", (14, 54, 120, 44), "MAIN", page_select(2, MAIN_CH))
    k += nbutton("eq_sel_p", (140, 54, 120, 44), "PHONES", page_select(2, PH_CH))
    k += led_button("eq_on", (430, 54, 120, 44), "EQ", "/2/eqEnable", [osc("/2/eqEnable", receive=False)])
    k += led_button("eq_lc", (556, 54, 170, 44), "LOW CUT", "/2/lowcutEnable", [osc("/2/lowcutEnable", receive=False)])
    bx, by, bw, bh = 14, 112, W - 28, 420
    k.append(box((bx, by, bw, bh), PAD_BG, name="eq_bg"))
    for db in (-12, -6, 6, 12):
        k.append(box((bx, by + bh / 2 - db / 20 * bh / 2, bw, 1), "#262a32"))
        k.append(lbl(None, (bx + 4, by + bh / 2 - db / 20 * bh / 2 - 9, 40, 18), f"{db:+d}", 11, DIM_TXT,
                     AlignH.LEFT))
    for f in (50, 100, 200, 500, 1000, 2000, 5000, 10000):
        xx = bx + bw * math.log(f / 20) / math.log(1000)
        k.append(box((xx, by, 1, bh), "#262a32"))
        k.append(lbl(None, (xx - 30, by + bh + 2, 60, 18), f"{f // 1000}k" if f >= 1000 else str(f), 11, DIM_TXT))
    k.append(box((bx, by + bh / 2, bw, 1), "#4a5160"))
    n = 48
    for i in range(n):
        k.append(box((bx + i * bw / n + 1, by + bh / 2, bw / n - 2, 1), RME_C, name=f"eq_b{i + 1}"))
    cols = (("BAND", 14, 60), ("TYPE", 80, 180), ("FREQ", 270, 150), ("GAIN", 430, 150), ("Q", 590, 136))
    ty = 572
    for title, x, w in cols:
        k.append(lbl(None, (x, ty, w, 24), title, 12, DIM_TXT, AlignH.LEFT))
    for b in (1, 2, 3):
        y = ty + 30 + (b - 1) * 40
        k.append(lbl(None, (14, y, 60, 34), str(b), 18, TXT, AlignH.LEFT))
        if b == 2:
            k.append(lbl(None, (80, y, 180, 34), "Bell", 18, TXT, AlignH.LEFT))
        else:
            k.append(t.label(name=f"eq_type{b}", frame=F(80, y, 180, 34), text_size=18, text_color=TXT,
                             text_align_h=AlignH.LEFT, background=False, outline=False,
                             messages=[recv_text(f"/2/eqType{b}Val")]))
        for key, x, w in (("Freq", 270, 150), ("Gain", 430, 150), ("Q", 590, 136)):
            k.append(t.label(name=f"eq_{key.lower()}{b}", frame=F(x, y, w, 34), text_size=18, text_color=TXT,
                             text_align_h=AlignH.LEFT, background=False, outline=False,
                             messages=[recv_text(f"/2/eq{key}{b}Val")]))
    y = ty + 30 + 3 * 40
    k.append(lbl(None, (14, y, 60, 34), "LC", 18, TXT, AlignH.LEFT))
    k.append(t.label(name="eq_lcfreq", frame=F(270, y, 150, 34), text_size=18, text_color=TXT,
                     text_align_h=AlignH.LEFT, background=False, outline=False,
                     messages=[recv_text("/2/lowcutFreqVal")]))
    k.append(t.label(name="eq_lcgrade", frame=F(430, y, 150, 34), text_size=18, text_color=TXT,
                     text_align_h=AlignH.LEFT, background=False, outline=False,
                     messages=[recv_text("/2/lowcutGradeVal")]))
    k += nbutton("eq_close", (W - 180, PAGER_H - 70, 166, 56), "ZURÜCK", [osc("/1", None, receive=False, cond="RISE")],
                 size=17)
    g.add(*k)
    return g


def build(tm=True):
    doc = t.Document.new(frame=(0, 0, W, H), color=BG, background=True, outline=False)
    root = doc.root
    root.name = "seren.a Panner Skript hochkant" + (" + TotalMix" if tm else "")
    script = (HERE.parent / "common" / "monitor.lua").read_text() + "\n" + (HERE / "root.lua").read_text()
    assert "  iemVia = 'osc'," in script
    script = script.replace("  iemVia = 'osc',", "  iemVia = 'midi',")
    if not tm:
        assert "  withTM = true," in script
        script = script.replace("  withTM = true,", "  withTM = false,")
    root.script = script
    pager = t.pager(name="pager", frame=F(0, PAGER_Y, W, PAGER_H), color="#20242b", tabbar_size=TAB,
                    text_size_on=17, text_size_off=17)
    mp_knobs = [("dist", "Distance"), ("div", "Divergence"), ("field", "Field Size"), ("src", "Source Size"),
                ("width", "Width"), ("depth", "Depth")]
    p1 = multipanner_page("p1", "MULTIPANNER", [(f"p1_k_{i}", n, ACCENT, False) for i, n in mp_knobs] +
                          [("p1_k_rotz", "Rot Z", ACCENT, True), ("p1_k_tilty", "Tilt Y", ACCENT, True),
                           ("p1_k_tiltx", "Tilt X", ACCENT, True)])
    p3 = multipanner_page("p3", "MP + IEM", [(f"p3_k_{i}", n, ACCENT, False) for i, n in mp_knobs] +
                          [("p3_az", "IEM Azimuth", IEM_C, True), ("p3_el", "IEM Elevation", IEM_C, True),
                           ("p3_wid", "IEM Width", IEM_C, True)])
    pager.add(p1, iem_page(), p3, monitor_page())
    root.add(header(), pager)
    if tm:
        root.add(rme_panel(), eq_overlay())
    else:
        root.add(pan_panel())
    for c in doc.walk():
        if c.control_type.value == "RADIAL" and c.get("centered"):
            c.value("x").default = 0.5
    return doc


if __name__ == "__main__":
    for tm, name in ((True, "seren-a_Panner_Skript_hochkant_TotalMix.tosc"), (False, "seren-a_Panner_Skript_hochkant.tosc")):
        doc = build(tm)
        for i in doc.validate():
            print("ISSUE:", i)
        doc.save(HERE / name)
        print("saved", name, sum(1 for _ in doc.walk()), "controls")
