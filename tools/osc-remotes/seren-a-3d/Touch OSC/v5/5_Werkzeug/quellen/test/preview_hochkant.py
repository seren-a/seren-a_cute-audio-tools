"""Vorschau Panner Skript hochkant: jede Seite statisch (mit und ohne TotalMix-Teil)."""
import asyncio, os, re, sys
D = os.path.dirname(os.path.abspath(__file__)); V3 = os.path.join(D, '..')
sys.path.insert(0, os.path.join(V3, 'overview'))
from svgfix import fix_svg
import py2tosc
from playwright.async_api import async_playwright
OUT = os.path.join(V3, 'prev')
CSS = ".p2t-box .p2t-shape{fill-opacity:1} .p2t-group .p2t-group > .p2t-shape{fill:none} .p2t-box .p2t-shape.p2t-outlined{fill:none}"
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(executable_path="/opt/pw-browsers/chromium")
        pg = await br.new_page(viewport={"width": 740, "height": 1600})
        for fn, tag in (('seren-a_Panner_Skript_hochkant_TotalMix.tosc', 'TM'), ('seren-a_Panner_Skript_hochkant.tosc', '')):
            path = os.path.join(V3, 'panner', fn)
            n = len(py2tosc.load(path).find('pager').children)
            for i in range(n):
                doc = py2tosc.load(path); pager = doc.find('pager')
                tab = getattr(pager.children[i], 'tab_label', str(i))
                pager.children[:] = [pager.children[i]]
                for j, c in enumerate(doc.walk()):
                    if c.get('name') == 'eq_overlay': c.visible = False
                    if not c.get('name') and c.control_type.value in ('LABEL', 'TEXT'): c.name = f'_l{j}'
                    nm = c.get('name') or ''
                    demo = {'nu_track': 'Vox Lead Dbl', 'p1_pad1_val': 'X +24    Y +60', 'p3_pad1_val': 'X +24    Y +60',
                            'p1_pad1_title': 'TOP VIEW  ·  X / Y', 'p3_pad1_title': 'TOP VIEW  ·  X / Y'}
                    if nm in demo: c.value('text').default = demo[nm]
                    elif nm.startswith('ro_'): c.value('text').default = {'x': '+24', 'y': '+60', 'z': '-10', 'az': '+45.0°', 'el': '+12.0°'}.get(nm[3:], '50%')
                    elif nm.endswith('_val') and c.value('text') is not None and c.value('text').default in ('–', ''): c.value('text').default = '+12'
                svg = fix_svg(py2tosc.to_svg(doc, clip=True), doc)
                await pg.set_content(f"<html><head><style>{CSS}</style></head><body style='margin:0;background:#000'>{svg}</body></html>")
                safe = re.sub(r'[^A-Za-z0-9]+', '-', str(tab)).strip('-')
                await pg.screenshot(path=os.path.join(OUT, f"Panner_hochkant{('_' + tag) if tag else ''}_{i + 1}_{safe}.png"),
                                    clip={"x": 0, "y": 0, "width": 740, "height": 1600})
        await br.close()
asyncio.run(main())
