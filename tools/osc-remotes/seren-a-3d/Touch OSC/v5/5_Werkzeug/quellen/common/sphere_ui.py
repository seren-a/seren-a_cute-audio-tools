"""Top view rings shared by IEM space (iPad) and IEM monitor (5:4).

Like IEM's sphere view with linear elevation: centre = straight above (+90°), edge = horizon (0°),
a ring every 15°. Objects below the horizon sit mirrored inside the circle and are drawn hollow.
"""
import py2tosc as t
from py2tosc import AlignH, AlignV, Shape

STEP = 15


def rings(box, lbl, cx, cy, R, line, horizon, dim, label_size=11):
    k = []
    for el in range(STEP, 90, STEP):
        r = R * (90 - el) / 90
        k.append(box((cx - r, cy - r, 2 * r, 2 * r), line, name="th_line" if el % 45 else None,
                     shape=Shape.CIRCLE, bg=False, outline=True))
        if el % 30 == 0:
            k.append(lbl(None, (cx + 5, cy - r + 1, 70, 16), f"±{el}°", label_size, dim))
    k.append(box((cx - R, cy - R, 2 * R, 2 * R), horizon, shape=Shape.CIRCLE, bg=False, outline=True))
    k.append(lbl(None, (cx + 5, cy - R + 1, 120, 16), "0° horizont", label_size, horizon))
    k.append(box((cx - 3, cy - 3, 6, 6), horizon, shape=Shape.CIRCLE))
    return k


LEGEND = "mitte = über dir ♡ · rand = horizont\nhohl = unter dem horizont · höhe: im horizont-feld"
