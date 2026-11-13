"""Room view controls (common to iPad and monitor). Positions are set by common/room.lua."""
import py2tosc as t
from py2tosc import AlignH, AlignV, Shape

GRID = 16


def controls(box, lbl, prefixes=("rt", "rs"), line="#7a2f86", wall="#5ef2ff", txt="#fff0fb", dim="#b79bd6", accent="#ff6ec7"):
    """Below the dots: floor, grid, walls, listener, labels; all hidden until the ROOM mode shows them."""
    k = []
    off = (-50, -50, 1, 1)
    for pre in prefixes:
        k.append(box(off, "#241046", name=pre + "_floor", radius=6))
        for i in range(1, GRID + 1):
            k.append(box(off, line, name=f"{pre}_gx{i}"))
            k.append(box(off, line, name=f"{pre}_gy{i}"))
        for w in ("wl", "wr", "wf", "wb", "wt", "wbo"):
            k.append(box(off, wall, name=f"{pre}_{w}", radius=2))
        k.append(box(off, txt, name=pre + "_lis", shape=Shape.CIRCLE))
        k.append(box(off, accent, name=pre + "_nose", shape=Shape.CIRCLE))
        k.append(lbl(pre + "_title", off, "", 14, txt))
        k.append(lbl(pre + "_scale", off, "", 11, dim))
    for c in k:
        c.visible = False
    return k


BTN = """function onValueChanged(k)
  if k == 'touch' and self.values.touch then root:notify('btn', self.name) end
end
"""


def zoom(box, lbl, pill="#2e1659", txt="#fff0fb"):
    """Zoom buttons for the top view; must sit ABOVE the XY drag area (add after it)."""
    k = []
    off = (-80, -80, 10, 10)
    for name, cap in (("rz_big", "groß"), ("rz_minus", "−"), ("rz_fit", "Raum"), ("rz_plus", "+")):
        b = box(off, pill, name=name + "_bg", radius=10)
        l = lbl(name + "_lbl", off, cap, 18 if cap in ("−", "+") else 14, txt, t.AlignH.CENTER)
        btn = t.button(name=name, frame=off, color="#ffffff00", background=False, outline=False,
                       button_type=t.ButtonType.MOMENTARY, script=BTN)
        for c in (b, l, btn):
            c.visible = False
        k += [b, l, btn]
    return k
