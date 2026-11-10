"""Builds the Twister View TouchOSC layout (phone, portrait 9:16) from a Midi Fighter .mfs file.

usage: python3 build.py <settings.mfs> [colors.json] [out.tosc]
"""
import json
import re
import sys
from pathlib import Path

import py2tosc as t
from py2tosc import AlignH, AlignV, ButtonType, Font

import mfs_parse

HERE = Path(__file__).parent
W, H = 720, 1280
BG, CELL, TXT, DIM, ACC = "#121418", "#1b1e24", "#e8ebf0", "#8b93a1", "#36d0c4"

BTN_SCRIPT = """function onValueChanged(k)
  if k == 'touch' and self.values.touch then root:notify('btn', self.name) end
end
"""


def F(x, y, w, h):
    return (round(x), round(y), round(w), round(h))


def lbl(name, frame, text="", size=14, color=TXT, align=AlignH.LEFT, valign=AlignV.MIDDLE,
        multi=False, mono=False):
    maker = t.text if multi else t.label
    c = maker(frame=F(*frame), text_size=size, text_color=color, text_align_h=align,
              text_align_v=valign, background=False, outline=False,
              font=Font.MONOSPACED if mono else Font.DEFAULT)
    if name:
        c.name = name
    c.value("text").default = text
    return c


def box(frame, color, name=None, radius=0.0):
    c = t.box(frame=F(*frame), color=color, background=True, outline=False, corner_radius=radius)
    if name:
        c.name = name
    return c


def lua_tables(mfs_path, colors_path):
    glob, encs = mfs_parse.parse(Path(mfs_path).read_bytes())
    cols = {int(k): v for k, v in json.loads(Path(colors_path).read_text()).items()}
    enc = ", ".join(f"{{ {e['encoder_midi_channel'] - 1}, {e['encoder_midi_number']} }}" for e in encs)
    col = ", ".join("{ %.3f, %.3f, %.3f }" % tuple(c / 255 for c in cols.get(e["active_color"], [255, 255, 255]))
                    for e in encs)
    for e in encs:
        assert e["encoder_midi_type"] == 1, f"encoder {e['encoder']} is not absolute CC"
    return glob, encs, (f"local ENC = {{ {enc} }}", f"local COL = {{ {col} }}")


def build(mfs_path, colors_path=HERE / "used_colors.json", orient="portrait"):
    glob, encs, (enc_lua, col_lua) = lua_tables(mfs_path, colors_path)
    script = (HERE / "mft_root.lua").read_text()
    script = re.sub(r"--@@ENC@@\n.*?--@@END@@", lambda m: f"--@@ENC@@\n{enc_lua}\n--@@COL@@\n{col_lua}\n--@@END@@",
                    script, flags=re.S)
    script = script.replace("  sysCh = 3,", f"  sysCh = {glob.get(0, 4) - 1},")

    if orient == "landscape":
        doc = t.Document.new(frame=(0, 0, LW, LH), color=LBG, background=True, outline=False)
        doc.root.name = "seren.a Twister View quer"
        doc.root.script = script
        doc.root.add(*landscape())
        return doc
    doc = t.Document.new(frame=(0, 0, W, H), color=BG, background=True, outline=False)
    root = doc.root
    root.name = "seren.a Twister View"
    root.script = script
    k = [box((0, 0, W, H), BG, "ground")]
    k += header(12, 12, 696, portrait=True)
    tw = (696 - 3 * 8) / 4
    for b in range(4):
        x = 12 + b * (tw + 8)
        k.append(t.button(name=f"tab{b + 1}", frame=F(x, 132, tw, 64), color="#383c44", corner_radius=8,
                          outline=False, button_type=ButtonType.MOMENTARY, script=BTN_SCRIPT))
        k.append(lbl(f"tab{b + 1}_lbl", (x + 4, 132, tw - 8, 64), f"Bank {b + 1}", 20, TXT, AlignH.CENTER))
    cw, ch, gap, top = (696 - 3 * 8) / 4, (1030 - 3 * 8) / 4, 8, 206
    for s in range(16):
        r, c = divmod(s, 4)
        k += cell(f"c{s + 1}", 12 + c * (cw + gap), top + r * (ch + gap), cw, ch, 24, 34, 15)
    k.append(lbl("status", (12, 1244, 696, 30), "", 14, DIM))
    root.add(*k)
    return doc


LW, LH = 1600, 740
LBG, LLINE = "#050506", "#2a2d33"


def header(x0, y0, wtot, portrait=False):
    """Source (tap: profile), bank name, track, look key."""
    k = [t.button(name="src_btn", frame=F(x0, y0, 150, 48), color="#1c1f24", corner_radius=6,
                  outline=False, button_type=ButtonType.MOMENTARY, script=BTN_SCRIPT),
         lbl("src", (x0, y0, 150, 48), "MIDI", 17, ACC, AlignH.CENTER),
         t.button(name="look_btn", frame=F(x0 + wtot - 170, y0, 170, 48), color="#1c1f24", corner_radius=6,
                  outline=False, button_type=ButtonType.MOMENTARY, script=BTN_SCRIPT),
         lbl("look_lbl", (x0 + wtot - 170, y0, 170, 48), "Look: Klar", 17, DIM, AlignH.CENTER)]
    if portrait:
        k.append(lbl("track", (x0 + 162, y0, wtot - 344, 48), "", 22, DIM, AlignH.RIGHT))
        k.append(lbl("bankname", (x0, y0 + 56, wtot, 64), "Bank 1", 40, TXT))
    else:
        k.append(lbl("bankname", (x0 + 166, y0 - 2, 560, 52), "Bank 1", 36, TXT))
        k.append(lbl("track", (x0 + 740, y0, wtot - 740 - 182, 48), "", 24, DIM, AlignH.RIGHT))
    return k


def cell(n, x, y, cw, ch, fs_name, fs_val, fs_sub):
    """All parts of one cell; the root script places them per look (Klar, Spalte, Neon, IEM Neon)."""
    knob = t.radial(frame=F(x + 10, y + 10, 92, 92), color=ACC, outline=False, interactive=False, visible=False)
    knob.name = n + "_knob"
    return [box((x - 2, y - 2, cw + 4, ch + 4), ACC, n + "_edge", radius=10),
            box((x, y, cw, ch), CELL, n + "_bg", radius=8),
            box((x + 12, y + ch - 44, 0, 26), ACC, n + "_glow", radius=8),
            box((x + 12, y + ch - 38, cw - 24, 14), "#0d0f12", n + "_barbg", radius=4),
            box((x + 12, y + ch - 38, 0, 14), ACC, n + "_bar", radius=4),
            knob,
            box((x + 12, y + ch - 56, 150, 46), "#06040F", n + "_pill", radius=23),
            lbl(n + "_name", (x + 12, y + 6, cw - 24, ch * 0.5), "", fs_name, TXT, AlignH.LEFT, AlignV.TOP, multi=True),
            lbl(n + "_sub", (x + 12, y + 40, cw - 24, 22), "", fs_sub, DIM, AlignH.LEFT, AlignV.TOP),
            lbl(n + "_val", (x + 12, y + ch - 96, cw - 24, 48), "", fs_val, TXT, AlignH.RIGHT),
            lbl(n + "_cc", (x + 12, y + ch - 22, cw - 24, 18), "", 13, DIM, AlignH.LEFT)]


def landscape():
    """Phone landscape: 4 x 4 cells, bank keys as a column on the right (with names), look key."""
    k = [box((0, 0, LW, LH), LBG, "ground")]
    gx, gy, gw, gh, gap = 16, 72, 1316, 616, 10
    k += header(16, 10, LW - 32)
    cw, ch = (gw - 3 * gap) / 4, (gh - 3 * gap) / 4
    for s in range(16):
        r, c = divmod(s, 4)
        k += cell(f"c{s + 1}", gx + c * (cw + gap), gy + r * (ch + gap), cw, ch, 26, 38, 16)
    tx, tw = gx + gw + 14, LW - (gx + gw + 14) - 16
    th = (gh - 3 * gap) / 4
    for b in range(4):
        y = gy + b * (th + gap)
        k.append(t.button(name=f"tab{b + 1}", frame=F(tx, y, tw, th), color="#383c44", corner_radius=8,
                          outline=False, button_type=ButtonType.MOMENTARY, script=BTN_SCRIPT))
        k.append(lbl(f"tab{b + 1}_lbl", (tx + 8, y, tw - 16, th), f"Bank {b + 1}", 24, TXT, AlignH.CENTER))
    k.append(lbl("status", (gx, gy + gh + 10, LW - 32, 30), "", 14, DIM))
    return k


def daw_scripts(mfs_path, outdir):
    """Reaper hub and Nuendo script with the same encoder table as the view."""
    glob, encs = mfs_parse.parse(Path(mfs_path).read_bytes())
    sys_ch = glob.get(0, 4) - 1
    lua = "local ENC = { " + ", ".join(f"{{ {e['encoder_midi_channel'] - 1}, {e['encoder_midi_number']} }}" for e in encs) + " }"
    js = "var ENC = [" + ", ".join(f"[{e['encoder_midi_channel'] - 1}, {e['encoder_midi_number']}]" for e in encs) + "]"
    r = (HERE / "reaper_mft_hub.lua").read_text()
    r = re.sub(r"--@@ENC@@\n.*?--@@END@@", lambda m: f"--@@ENC@@\n{lua}\n--@@END@@", r, flags=re.S)
    r = r.replace("local SYS_CH      = 3 ", f"local SYS_CH      = {sys_ch} ")
    j = (HERE / "serena_MFTView.js").read_text()
    j = re.sub(r"//@@ENC@@\n.*?//@@END@@", lambda m: f"//@@ENC@@\n{js}\n//@@END@@", j, flags=re.S)
    j = j.replace("var SYS_CH = 3 ", f"var SYS_CH = {sys_ch} ")
    outdir.mkdir(exist_ok=True)
    (outdir / "reaper_mft_hub.lua").write_text(r)
    (outdir / "serena_MFTView.js").write_text(j)


if __name__ == "__main__":
    mfs = sys.argv[1]
    dist = HERE / "dist"
    dist.mkdir(exist_ok=True)
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else dist / "seren-a_Twister_View.tosc"
    doc = build(mfs, sys.argv[2] if len(sys.argv) > 2 else HERE / "used_colors.json")
    for i in doc.validate():
        print("ISSUE:", i)
    doc.save(out)
    quer = build(mfs, sys.argv[2] if len(sys.argv) > 2 else HERE / "used_colors.json", "landscape")
    for i in quer.validate():
        print("ISSUE quer:", i)
    quer.save(dist / "seren-a_Twister_View_quer.tosc")
    daw_scripts(mfs, dist)
    print("saved", out, sum(1 for _ in doc.walk()), "controls + DAW scripts in", dist)
