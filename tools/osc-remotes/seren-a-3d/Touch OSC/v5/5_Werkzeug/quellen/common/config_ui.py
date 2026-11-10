"""Config-Seite (Overlay) für IEM space (iPad) und IEM monitor (5:4). Namen cfg_* -> common/config.lua."""
import py2tosc as t
from py2tosc import AlignH, AlignV, ButtonType, Orientation

BTN = """function onValueChanged(k)
  if k == 'touch' and self.values.touch then root:notify('btn', self.name) end
end
"""
FADER = """function onValueChanged(k)
  if k == 'x' and self.values.touch then root:notify('cfgf', self.name) end
end
"""
TXT, DIM, PANEL, PILL = "#fff0fa", "#b9a6d6", "#1d0c38", "#2e1659"


def _lbl(name, frame, text, size, color=TXT, align=AlignH.LEFT):
    c = t.label(frame=tuple(round(v) for v in frame), text_size=size, text_color=color, text_align_h=align,
                text_align_v=AlignV.MIDDLE, background=False, outline=False)
    if name:
        c.name = name
    c.value("text").default = text
    c.set("interactive", False)
    return c


def _btn(name, x, y, w, h, cap, size=14):
    bg = t.box(frame=(x, y, w, h), color=PILL, background=True, outline=False, corner_radius=8)
    bg.name = name + "_bg"
    bg.set("interactive", False)
    b = t.button(name=name, frame=(x, y, w, h), color="#ffffff00", corner_radius=8, outline=False,
                 background=False, button_type=ButtonType.MOMENTARY, script=BTN)
    return [bg, b, _lbl(name + "_lbl", (x, y, w, h), cap, size, TXT, AlignH.CENTER)]


def _fader(name, x, y, w, h, title, default):
    f = t.fader(name=name, frame=(x, y + 20, w, h - 20), color="#ff6fc7", orientation=Orientation.EAST,
                background=True, outline=False, script=FADER)
    f.value("x").default = default
    return [_lbl(name + "_t", (x, y, w * 0.6, 20), title, 12, DIM), _lbl(name + "_val", (x + w * 0.6, y, w * 0.4, 20), "", 12, TXT, AlignH.RIGHT), f]


def build(W, H, with64=False):
    """Returns the overlay group (hidden). Coordinates scale with the page size."""
    g = t.group(name="cfg_overlay", frame=(0, 0, W, H), color="#0a0414", background=True, outline=False)
    g.visible = False
    k = [t.box(frame=(0, 0, W, H), color="#0a0414", background=True, outline=False)]
    k[0].set("interactive", False)
    s = min(W / 1280, H / 1024)
    pad = 24 * s
    col_w = (W - 4 * pad) / 3
    bh, gap = 40 * s, 8 * s
    x1, x2, x3 = pad, 2 * pad + col_w, 3 * pad + 2 * col_w
    y0 = 64 * s
    k.append(_lbl(None, (pad, 12 * s, W * 0.5, 40 * s), "✧ config ✧", 26 * s, "#ff6fc7"))
    k += _btn("cfg_close", W - pad - 140 * s, 12 * s, 140 * s, 40 * s, "fertig ♡", 16 * s)
    k.append(_lbl("cfg_info", (pad, H - 40 * s, W - 2 * pad, 30 * s), "", 13 * s, DIM))

    # Spalte 1: Pegel
    y = y0
    k.append(_lbl(None, (x1, y, col_w, 26 * s), "PEGEL · Skala", 14 * s, "#7af5ff")); y += 30 * s
    scales = [("digital", "Digital"), ("din", "DIN"), ("ebu", "EBU"), ("british", "British"), ("nordic", "Nordic"),
              ("k20", "K-20"), ("k14", "K-14"), ("k12", "K-12"), ("lufs", "LUFS≈"), ("lu", "LU≈")]
    bw = (col_w - 4 * gap) / 5
    for i, (key, cap) in enumerate(scales):
        k += _btn("cfg_sc_" + key, x1 + (i % 5) * (bw + gap), y + (i // 5) * (bh + gap), bw, bh, cap, 13 * s)
    y += 2 * (bh + gap) + 8 * s
    k.append(_lbl(None, (x1, y, col_w, 26 * s), "Anzeige", 14 * s, "#7af5ff")); y += 30 * s
    bw3 = (col_w - 2 * gap) / 3
    for i, (key, cap) in enumerate([("cfg_md_peak", "Peak"), ("cfg_md_rms", "RMS"), ("cfg_aes", "+3 dB AES17")]):
        k += _btn(key, x1 + i * (bw3 + gap), y, bw3, bh, cap, 13 * s)
    y += bh + gap
    for i, (key, cap) in enumerate([("cfg_loud_M", "LUFS M 400 ms"), ("cfg_loud_S", "LUFS S 3 s")]):
        k += _btn(key, x1 + i * (bw3 + gap), y, bw3, bh, cap, 12 * s)
    y += bh + gap + 4 * s
    k.append(_lbl(None, (x1, y, col_w, 22 * s), "LU-Bezug", 12 * s, DIM)); y += 24 * s
    bw4 = (col_w - 3 * gap) / 4
    for i, tg in enumerate([23, 24, 16, 14]):
        k += _btn("cfg_tg_%d" % tg, x1 + i * (bw4 + gap), y, bw4, bh, "-%d" % tg, 13 * s)
    y += bh + gap + 4 * s
    for name, title, d in (("cfg_f_rms", "RMS-Auflösung", 0.09), ("cfg_f_thr", "Schwelle Glühen", 0.0)):
        k += _fader(name, x1, y, col_w, 60 * s, title, d); y += 68 * s

    # Spalte 2: Ballistik
    y = y0
    k.append(_lbl(None, (x2, y, col_w, 26 * s), "BALLISTIK · Rücklauf", 14 * s, "#7af5ff")); y += 30 * s
    bw2 = (col_w - gap) / 2
    for i, cap in enumerate(["Typ I DIN/Nordic", "Typ IIa EBU/BBC", "Digital schnell", "VU 300 ms"]):
        k += _btn("cfg_fb_%d" % (i + 1), x2 + (i % 2) * (bw2 + gap), y + (i // 2) * (bh + gap), bw2, bh, cap, 12 * s)
    y += 2 * (bh + gap) + 6 * s
    for name, title, d in (("cfg_f_fall", "Rücklauf", 0.33), ("cfg_f_hold", "Spitze halten", 0.3),
                           ("cfg_f_att", "Glühen Anstieg", 0.05), ("cfg_f_rel", "Glühen Abfall", 0.19)):
        k += _fader(name, x2, y, col_w, 60 * s, title, d); y += 68 * s
    # v8.14: Gruppen (Reaper)
    y += 6 * s
    k.append(_lbl(None, (x2, y, col_w * 0.5, 26 * s), "GRUPPEN zeigen", 14 * s, "#7af5ff"))
    k.append(_lbl("cfg_gr_info", (x2 + col_w * 0.4, y, col_w * 0.6, 26 * s), "", 11 * s, DIM, AlignH.RIGHT)); y += 30 * s
    gb = (col_w - 2 * gap) / 3
    for i in range(12):
        k += _btn("cfg_gr_%d" % (i + 1), x2 + (i % 3) * (gb + gap), y + (i // 3) * (bh + gap), gb, bh, "", 12 * s)
    y += 4 * (bh + gap) + 4 * s
    k.append(_lbl(None, (x2, y, col_w, 22 * s), "Spuren zuordnen (danach antippen, nochmal = fertig)", 12 * s, DIM)); y += 24 * s
    for i, cap in enumerate(("+A", "+B", "+C", "+D")):
        k += _btn("cfg_as_%d" % (i + 1), x2 + i * (bw4 + gap), y, bw4, bh, cap, 14 * s)

    # Spalte 3: Aussehen, Spuren, Symbole, 64er
    y = y0
    k.append(_lbl(None, (x3, y, col_w, 26 * s), "AUSSEHEN", 14 * s, "#7af5ff")); y += 30 * s
    k += _btn("cfg_col_tosc", x3, y, bw2, bh, "Farben TouchOSC", 12 * s)
    k += _btn("cfg_col_daw", x3 + bw2 + gap, y, bw2, bh, "Spurfarben", 12 * s); y += bh + gap
    k += _btn("cfg_th_synth", x3, y, bw2, bh, "seren.a", 12 * s)
    k += _btn("cfg_th_nuendo", x3 + bw2 + gap, y, bw2, bh, "Nuendo dark", 12 * s); y += bh + gap + 6 * s
    k.append(_lbl(None, (x3, y, col_w, 26 * s), "SPUREN zeigen", 14 * s, "#7af5ff")); y += 30 * s
    for i, (key, cap) in enumerate([("audio", "Audio"), ("fx", "FX"), ("group", "Gruppe/Ordner"), ("instr", "MIDI/Instr")]):
        k += _btn("cfg_sh_" + key, x3 + (i % 2) * (bw2 + gap), y + (i // 2) * (bh + gap), bw2, bh, cap, 12 * s)
    y += 2 * (bh + gap)
    k += _btn("cfg_marks", x3, y, col_w, bh, "Kennzeichnung ─ FX · │ Gruppe · ♪ MIDI", 12 * s); y += bh + gap
    k += _btn("cfg_only", x3, y, bw2, bh, "nur Spuren mit Plugin", 12 * s)
    k += _btn("cfg_cpu", x3 + bw2 + gap, y, bw2, bh, "Auslastung (Reaper)", 12 * s); y += bh + gap + 6 * s
    k.append(_lbl(None, (x3, y, col_w, 26 * s), "SYMBOLE", 14 * s, "#7af5ff")); y += 30 * s
    for i, (key, cap) in enumerate([("off", "aus"), ("dot", "Punkt"), ("list", "Liste"), ("both", "beide")]):
        k += _btn("cfg_ic_" + key, x3 + i * (bw4 + gap), y, bw4, bh, cap, 12 * s)
    y += bh + gap
    k += _fader("cfg_f_isz", x3, y, col_w, 60 * s, "Symbolgröße", 0.33); y += 68 * s
    k += _fader("cfg_f_ia", x3, y, col_w, 60 * s, "Symbol-Deckkraft", 0.87); y += 68 * s
    k.append(_lbl("cfg_bottom", (x3, y, 1, 1), "", 1))   # marks how far column 3 goes (test)
    if with64:
        k.append(_lbl(None, (x3, y, col_w, 26 * s), "64er-ANSICHT · HORIZONT", 14 * s, "#7af5ff")); y += 30 * s
        k += _fader("cfg_f_gsz", x3, y, col_w, 60 * s, "Feldgröße", 0.3); y += 68 * s
        k += _fader("cfg_f_ga", x3, y, col_w, 60 * s, "Feld-Deckkraft", 0.5); y += 68 * s
        k += _fader("cfg_f_pa", x3, y, col_w, 60 * s, "Horizont-Deckkraft", 0.5); y += 68 * s
    g.add(*k)
    return g
