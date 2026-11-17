"""v8.20: Hall-Anzeige (Reiter FDN / mcfx): Gesamtpegel + je Send eine Doppelsäule (Send-Fader | Pegel am Hall)."""
from py2tosc import AlignH


def build(t, box, lbl, tap, frame, cols=16, PINK="#ff6ec7", PINK_DD="#4a1d5e", CYAN="#5ef2ff", TXT="#fff0fb",
          DIM="#b79bd6", PANEL="#241046", PANEL2="#2e1458", BG="#170a2b", title=30, chips=6):
    """Gruppe 'hall_g' mit Rahmen frame=(x,y,w,h); Kindnamen: hall_title, hall_sub, hall_i<n>(_bg/_lbl), hall_totbg,
    hall_tot, hall_hold, hall_db, hall_cnt, hc<i>_(sb|s|z|lb|l|h|n|d)."""
    x, y, w, h = frame
    g = t.group(name="hall_g", frame=(x, y, w, h), color=BG, background=False, outline=False, visible=False)
    C, R = AlignH.CENTER, AlignH.RIGHT
    k = [box((0, 0, w, h), PANEL, name="th_panel", radius=18),
         lbl("hall_title", (24, 14, w - 48, 44), "✧ Hall ✧", title, PINK),
         lbl("hall_sub", (24, 58, w - 48, 28), "", 18, DIM)]
    for n in range(chips):
        cx = 24 + n * 104
        k += [box((cx, 98, 96, 40), PANEL2, name=f"hall_i{n + 1}_bg", radius=12),
              lbl(f"hall_i{n + 1}_lbl", (cx, 98, 96, 40), str(n + 1), 17, TXT, C),
              tap(f"hall_i{n + 1}", (cx, 98, 96, 40))]
    k += [lbl(None, (24, 150, 400, 18), "gesamtpegel am hall", 13, DIM),
          lbl("hall_db", (w - 324, 142, 300, 34), "–", 26, TXT, R),
          box((24, 180, w - 48, 34), PINK_DD, name="hall_totbg", radius=10),
          box((24, 180, 0, 34), PINK, name="hall_tot", radius=10),
          box((24, 180, 2, 34), TXT, name="hall_hold"),
          lbl("hall_cnt", (24, 222, w - 48, 22), "", 14, DIM)]
    top, bot = 262, h - 120
    cw = (w - 48) / cols
    for i in range(cols):
        n = i + 1
        cx = 24 + i * cw + 3
        bw, lw = 12, cw - 3 - 12 - 8
        k += [box((cx, top, bw, bot - top), PINK_DD, name=f"hc{n}_sb", radius=5),
              box((cx, bot, bw, 1), CYAN, name=f"hc{n}_s", radius=5),
              box((cx - 2, top + (bot - top) * (1 - 60 / 72), bw + 4, 2), TXT, name=f"hc{n}_z"),
              box((cx + bw + 4, top, lw, bot - top), PINK_DD, name=f"hc{n}_lb", radius=5),
              box((cx + bw + 4, bot, lw, 1), PINK, name=f"hc{n}_l", radius=5),
              box((cx + bw + 4, bot, lw, 2), TXT, name=f"hc{n}_h"),
              lbl(f"hc{n}_n", (cx - 4, bot + 8, cw + 2, 22), "", 12, TXT, C),
              lbl(f"hc{n}_d", (cx - 4, bot + 30, cw + 2, 20), "", 11, DIM, C)]
    k.append(lbl(None, (24, h - 56, w - 48, 22),
                 "links: Send-Fader (Strich = 0 dB)   ·   rechts: Pegel, der am Hall ankommt", 13, DIM))
    k.append(lbl(None, (24, h - 32, w - 48, 22),
                 "Pegel = Quellspur-Peak × Send-Fader (rechnerisch, nicht das Hall-Signal selbst)", 11, DIM))
    g.add(*k)
    return g
