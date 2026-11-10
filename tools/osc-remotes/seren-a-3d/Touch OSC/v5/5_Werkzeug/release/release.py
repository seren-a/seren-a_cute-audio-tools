"""Release: copies the built surfaces under their short names, stamps the version into each one.

    python3 release.py <out_dir>

Version rule (since v5.0, 28.10.26):  vX.Y.Z
  X = big addition or new generation, or surfaces and DAW scripts only fit together again (protocol),
      or the set-up has to be done anew
  Y = new functions
  Z = fixes (shown only when > 0: v5.0, v5.0.1, v5.1 ...)
Backup folders: YYMMDD-vX.Y[.Z](most important change)
"""
import sys
from pathlib import Path

import py2tosc as t
from py2tosc import AlignH, AlignV

VERSION = "v6.1"
DATE = "04.11.26"
STAMP = f"{VERSION} · {DATE}"

V3 = Path("/home/claude/v3")
MFT = Path("/home/claude/mft-view/dist")
DIM = "#9a93b0"

# source -> (target, name shown inside TouchOSC, version label frame, size, align)
SURFACES = [
    (V3 / "panner/seren-a_Panner_Skript.tosc", "1_Oberflaechen/Handy_Pan/Pan_Skript.tosc", "Pan Skript", (1480, 14, 110, 24), 13, AlignH.RIGHT),
    (V3 / "panner/seren-a_Panner_Skript_TotalMix.tosc", "1_Oberflaechen/Handy_Pan/Pan_Skript_TotalMix.tosc", "Pan Skript TotalMix", (1316, 702, 140, 26), 13, AlignH.RIGHT),
    (V3 / "panner/seren-a_Panner_OSC.tosc", "1_Oberflaechen/Handy_Pan/Pan_OSC.tosc", "Pan OSC", (1480, 14, 110, 24), 13, AlignH.RIGHT),
    (V3 / "panner/seren-a_Panner_OSC_TotalMix.tosc", "1_Oberflaechen/Handy_Pan/Pan_OSC_TotalMix.tosc", "Pan OSC TotalMix", (1316, 702, 140, 26), 13, AlignH.RIGHT),
    (V3 / "panner/seren-a_Panner_Skript_hochkant.tosc", "1_Oberflaechen/Handy_Pan/Pan_Skript_hochkant.tosc", "Pan Skript hochkant", (330, 6, 146, 20), 13, AlignH.RIGHT),
    (V3 / "panner/seren-a_Panner_Skript_hochkant_TotalMix.tosc", "1_Oberflaechen/Handy_Pan/Pan_Skript_hochkant_TotalMix.tosc", "Pan Skript hochkant TotalMix", (330, 6, 146, 20), 13, AlignH.RIGHT),
    (V3 / "overview/dist/seren-a_Objekt-Uebersicht.tosc", "1_Oberflaechen/Handy_Objekt-Uebersicht/Objekt-Uebersicht.tosc", "Objekt-Übersicht", (1460, 720, 128, 18), 11, AlignH.RIGHT),
    (V3 / "ipad/dist/seren-a_IEM-Space.tosc", "1_Oberflaechen/iPad_IEM-Space/IEM-Space.tosc", "IEM Space", (20, 68, 200, 16), 11, AlignH.LEFT),
    (V3 / "monitor/dist/seren-a_IEM-Monitor.tosc", "1_Oberflaechen/Monitor_5zu4/IEM-Monitor.tosc", "IEM Monitor", (14, 46, 200, 16), 11, AlignH.LEFT),
    (MFT / "seren-a_Twister_View.tosc", "1_Oberflaechen/Handy_Twister-View/Twister_View.tosc", "Twister View", (580, 1250, 128, 20), 11, AlignH.RIGHT),
    (MFT / "seren-a_Twister_View_quer.tosc", "1_Oberflaechen/Handy_Twister-View/Twister_View_quer.tosc", "Twister View quer", (1460, 712, 124, 22), 11, AlignH.RIGHT),
    (V3 / "diag/seren-a_Bridge-Test.tosc", "0_Fehlersuche/Bridge-Test.tosc", "Bridge-Test", (20, 58, 300, 20), 13, AlignH.LEFT),
]


def stamp(src, dst, name, frame, size, align):
    doc = t.load(src)
    doc.root.name = name
    lab = t.label(name="version", frame=frame, text_size=size, text_color=DIM, text_align_h=align,
                  text_align_v=AlignV.MIDDLE, background=False, outline=False)
    lab.value("text").default = STAMP
    lab.set("interactive", False)
    doc.root.add(lab)
    dst.parent.mkdir(parents=True, exist_ok=True)
    doc.save(dst)
    return dst


if __name__ == "__main__":
    out = Path(sys.argv[1])
    for src, rel, name, frame, size, align in SURFACES:
        print("→", stamp(src, out / rel, name, frame, size, align))
