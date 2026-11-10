"""Preview PNGs for v2 with a few demo values (preview only)."""
import asyncio, math, sys
import py2tosc, build
from playwright.async_api import async_playwright

DEMO = {"tm_main_val": "-12.5 dB", "tm_ph_val": "-24.0 dB", "mt_main_peak": "-6.2", "mt_ph_peak": "-14.8",
        "p2_encCircle_val": "+45.0°", "p2_rotCircle_val": "-30.0°", "p2_el_val": "+20.0°", "p2_pitch_val": "+0.0°",
        "eq_track": "AN 1/2", "eq_type1": "Low Shelf", "eq_freq1": "120", "eq_gain1": "+3.0 dB", "eq_q1": "0.7",
        "eq_freq2": "1200", "eq_gain2": "-2.5 dB", "eq_q2": "1.5", "eq_type3": "High Shelf", "eq_freq3": "8000",
        "eq_gain3": "+1.5 dB", "eq_q3": "0.7", "eq_lcfreq": "40", "eq_lcgrade": "12 dB/oct", "nu_track": "Vox Lead"}

def demo(doc, page, overlay):
    pager = doc.find("pager"); pager.children[:] = [pager.children[page]]
    for c in doc.walk():
        n = c.get("name")
        if n in DEMO and c.value("text"): c.value("text").default = DEMO[n]
        if n in ("mt_main_L", "mt_main_R", "mt_ph_L", "mt_ph_R"):
            c.value("x").default = {"mt_main_L": .8, "mt_main_R": .76, "mt_ph_L": .6, "mt_ph_R": .55}[n]
        if n and n.endswith("_hold") and n.startswith("mt_"):
            f = doc.find(n[:-5]).frame; v = doc.find(n[:-5]).value("x").default + 0.05
            c.frame = (f.x, f.y + f.h * (1 - v), f.w, 2)
        if n in ("tm_main", "tm_ph"): c.value("x").default = 0.7 if n == "tm_main" else 0.55
        if n == "snap2_led": c.value("x").default = 1.0
    ov = doc.find("eq_overlay"); ov.visible = overlay
    if overlay:
        bg = doc.find("eq_bg").frame
        for i in range(48):
            f = 20 * 1000 ** ((i + .5) / 48)
            db = 3 / (1 + (f / 120) ** 2) - 2.5 * math.exp(-(math.log(f / 1200) ** 2) / .3) + 1.5 / (1 + (8000 / f) ** 2) - 10 * math.log10(1 + (40 / f) ** 4)
            db = max(-20, min(20, db)); hh = abs(db) / 20 * bg.h / 2; mid = bg.y + bg.h / 2
            b = doc.find(f"eq_b{i + 1}"); b.frame = (b.frame.x, mid - hh if db >= 0 else mid, b.frame.w, max(hh, 1))
    def strip(c):
        c.children[:] = [k for k in c.children if k.get("visible", True)]
        for k in c.children: strip(k)
    strip(doc.root)
    return doc

async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(executable_path="/opt/pw-browsers/chromium")
        pg = await br.new_page(viewport={"width": 1600, "height": 740})
        for variant, page, ov, name in (("osc", 1, False, "v2_page2"), ("osc", 0, True, "v2_eq"), ("nuendo", 1, False, "v2_nuendo_page2")):
            svg = py2tosc.to_svg(demo(build.build(variant), page, ov), clip=True)
            await pg.set_content(f"<html><body style='margin:0;background:#000'>{svg}</body></html>")
            await pg.screenshot(path=f"prev/{name}.png", clip={"x": 0, "y": 0, "width": 1600, "height": 740})
        await br.close()
if __name__ == "__main__":
    asyncio.run(main())
