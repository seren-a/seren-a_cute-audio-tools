"""v8.22: Energie-Reiter: Karte Azimut x Elevation (24 x 12 Felder), Skala, Maximum, Gesamtpegel, Peak-/Bereich-Tasten."""
from py2tosc import AlignH, Shape


def build(t, box, lbl, tap, frame, PINK="#ff6ec7", PINK_DD="#4a1d5e", CYAN="#5ef2ff", TXT="#fff0fb",
          DIM="#b79bd6", PANEL="#241046", PANEL2="#2e1458", BG="#170a2b", title=30):
    """Gruppe 'en_g' mit Rahmen frame=(x,y,w,h). Kindnamen: en_title, en_sub, en_map, ec<r>_<c> (r 0-11, c 0-23), en_peak,
    en_peaklbl, en_tot, en_lg1..16, en_lgmin, en_lgmax, en_pk_dn/_up (+ en_pk_val), en_rg_dn/_up (+ en_rg_val), en_auto, en_scale."""
    x, y, w, h = frame
    g = t.group(name="en_g", frame=(x, y, w, h), color=BG, background=False, outline=False, visible=False)
    C, R = AlignH.CENTER, AlignH.RIGHT
    k = [box((0, 0, w, h), PANEL, name="th_panel", radius=18),
         lbl("en_title", (24, 14, w - 48, 44), "✧ Energie ✧", title, PINK),
         lbl("en_sub", (24, 58, w - 48, 28), "", 16, DIM)]
    my = 100
    gut = 26                                           # Rand links für die Elevationsbeschriftung (+90 / −90)
    mw = min(w - 48 - gut, 2 * (h - my - 250))         # 2:1 (360 x 180 Grad), quadratische Felder; bei wenig Höhe schmaler
    mx = 24 + gut + (w - 48 - gut - mw) / 2
    cw = ch = mw / 24
    mh = ch * 12
    k.append(box((mx, my, mw, mh), PINK_DD, name="en_map", radius=4))
    for r in range(12):
        for c in range(24):
            k.append(box((mx + c * cw + 0.5, my + r * ch + 0.5, cw - 1, ch - 1), PANEL2, name=f"ec{r}_{c}"))
    for q in (0.25, 0.5, 0.75):                         # Azimut 90 / 0 / -90 Grad, Horizont
        k.append(box((mx + mw * q - 0.5, my, 1, mh), DIM, name="th_line"))
    k.append(box((mx, my + mh / 2 - 0.5, mw, 1), DIM, name="th_line"))
    k.append(box((mx, my, mw, mh), PINK, name="en_frame", bg=False, outline=True, radius=4))
    k.append(box((mx, my, 22, 22), TXT, name="en_peak", shape=Shape.CIRCLE, bg=False, outline=True))
    ay = my + mh + 2
    for q, txt, al in ((0, "+180°", AlignH.LEFT), (0.25, "+90° links", C), (0.5, "0° vorn", C), (0.75, "−90° rechts", C), (1, "−180°", R)):
        wl = 130
        k.append(lbl(None, (mx + mw * q - (0 if al == AlignH.LEFT else (wl if al == R else wl / 2)), ay, wl, 18), txt, 12, DIM, al))
    k.append(lbl(None, (mx - 28, my + 2, 26, 16), "+90°", 10, DIM, R))
    k.append(lbl(None, (mx - 28, my + mh - 18, 26, 16), "−90°", 10, DIM, R))
    y1 = ay + 28
    k.append(lbl("en_peaklbl", (24, y1, w - 48, 24), "", 16, TXT))
    k.append(lbl("en_tot", (w - 324, y1, 300, 24), "", 16, CYAN, R))
    y2 = y1 + 34
    lw = (w - 48 - 160) / 16
    k.append(lbl("en_lgmin", (24, y2 - 2, 70, 18), "", 12, DIM))
    for i in range(16):
        k.append(box((24 + 74 + i * lw, y2, lw + 0.5, 14), PANEL2, name=f"en_lg{i + 1}"))
    k.append(lbl("en_lgmax", (24 + 74 + 16 * lw + 4, y2 - 2, 70, 18), "", 12, DIM))
    y3 = y2 + 30
    bw, bh = 52, 44
    xs = 24
    k.append(box((xs, y3, bw, bh), PANEL2, name="en_pk_dn_bg", radius=12)); k.append(lbl("en_pk_dn_lbl", (xs, y3, bw, bh), "−", 22, TXT, C)); k.append(tap("en_pk_dn", (xs, y3, bw, bh)))
    k.append(lbl("en_pk_val", (xs + bw + 4, y3, 120, bh), "", 14, TXT, C))
    xu = xs + bw + 4 + 120 + 4
    k.append(box((xu, y3, bw, bh), PANEL2, name="en_pk_up_bg", radius=12)); k.append(lbl("en_pk_up_lbl", (xu, y3, bw, bh), "+", 22, TXT, C)); k.append(tap("en_pk_up", (xu, y3, bw, bh)))
    xr = xu + bw + 24
    k.append(box((xr, y3, bw, bh), PANEL2, name="en_rg_dn_bg", radius=12)); k.append(lbl("en_rg_dn_lbl", (xr, y3, bw, bh), "−", 22, TXT, C)); k.append(tap("en_rg_dn", (xr, y3, bw, bh)))
    k.append(lbl("en_rg_val", (xr + bw + 4, y3, 140, bh), "", 14, TXT, C))
    xv = xr + bw + 4 + 140 + 4
    k.append(box((xv, y3, bw, bh), PANEL2, name="en_rg_up_bg", radius=12)); k.append(lbl("en_rg_up_lbl", (xv, y3, bw, bh), "+", 22, TXT, C)); k.append(tap("en_rg_up", (xv, y3, bw, bh)))
    xa = xv + bw + 24
    k.append(box((xa, y3, 90, bh), PANEL2, name="en_auto_bg", radius=12)); k.append(lbl("en_auto_lbl", (xa, y3, 90, bh), "auto", 15, TXT, C)); k.append(tap("en_auto", (xa, y3, 90, bh)))
    k.append(lbl("en_scale", (24, y3 + bh + 6, w - 48, 20), "", 13, DIM))
    k.append(lbl(None, (24, h - 52, w - 48, 20),
                 "Karte = Energie je Richtung (Azimut × Elevation), vom JSFX „seren.a 3D Energy“ aus den Kanälen der Spur gerechnet.", 12, DIM))
    k.append(lbl(None, (24, h - 30, w - 48, 20),
                 "Das Bild des IEM EnergyVisualizer selbst lässt sich nicht auslesen; Peak/Bereich werden aus dessen Parametern übernommen.", 12, DIM))
    g.add(*k)
    return g
