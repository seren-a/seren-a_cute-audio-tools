"""Builds seren-a_Bridge-Test.tosc: zeigt jede ankommende MIDI-Nachricht, sendet Test-Nachrichten."""
from pathlib import Path
import py2tosc as t
from py2tosc import AlignH, AlignV, ButtonType
HERE = Path(__file__).parent
W, H = 1600, 740
BTN = """function onValueChanged(k)
  if k == 'touch' and self.values.touch then root:notify('btn', self.name) end
end
"""
def lbl(name, frame, text, size, color, multi=False, valign=AlignV.MIDDLE, align=AlignH.LEFT):
    c = (t.text if multi else t.label)(frame=frame, text_size=size, text_color=color, text_align_h=align,
                                       text_align_v=valign, background=False, outline=False)
    if name: c.name = name
    c.value("text").default = text
    c.set("interactive", False)
    return c
doc = t.Document.new(frame=(0, 0, W, H), color="#120a1e", background=True, outline=False)
root = doc.root
root.name = "seren.a Bridge-Test"
root.script = (HERE / "diag_root.lua").read_text()
root.add(
    lbl(None, (20, 12, 900, 44), "seren.a · Bridge-Test", 30, "#ff7ad9"),
    lbl(None, (20, 56, 1100, 24), "Einstellung: Bridge 1 = Mac · MIDI 1 Send + Receive = Bridge 1. Dann DAW-Skript bzw. Diagnose starten.", 15, "#c9b8e8"),
    lbl("status", (20, 86, 1180, 60), "empfangen: 0", 18, "#7af5ff", multi=True, valign=AlignV.TOP),
    t.box(frame=(20, 150, 1560, 570), color="#1d1230", background=True, outline=False, corner_radius=10),
    lbl("log", (34, 160, 1530, 550), "(noch nichts empfangen)", 15, "#f3e9ff", multi=True, valign=AlignV.TOP),
)
for name, x, cap, col in (("ping", 1220, "TEST SENDEN", "#ff4fb8"), ("clear", 1420, "LEEREN", "#3a2a55")):
    root.add(t.button(name=name, frame=(x, 20, 180 if name == "ping" else 160, 110), color=col, corner_radius=12,
                      outline=False, button_type=ButtonType.MOMENTARY, script=BTN),
             lbl(None, (x, 20, 180 if name == "ping" else 160, 110), cap, 20, "#ffffff", align=AlignH.CENTER))
doc.save(HERE / "seren-a_Bridge-Test.tosc")
print("ok")
