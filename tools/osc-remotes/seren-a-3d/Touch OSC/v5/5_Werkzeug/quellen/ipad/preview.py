"""Vorschau IEM space: Beispieldaten durch die echte Logik (Mock), dann als Bild."""
import asyncio, os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test'))
sys.path.insert(0, '/home/claude/objekt-view')
from view_harness import View
from svgfix import fix_svg
import py2tosc
from playwright.async_api import async_playwright
HERE = os.path.dirname(os.path.abspath(__file__))
TOSC = os.path.join(HERE, 'dist', 'seren-a_IEM-Space.tosc')
DEMO = [('Vox Lead', 0, 10, 20, 118), ('Backing L', 40, 15, 60, 70), ('Backing R', -40, 15, 60, 64),
        ('Gitarre', 75, -5, 30, 92), ('Keys', -80, 0, 40, 40), ('Pad', 150, 35, 90, 85),
        ('FX Swirl', -135, 55, 0, 105), ('Kick', 0, -30, 0, 127), ('Atmo L', 110, 60, 0, 20),
        ('Atmo R', -110, 60, 0, 25)]
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def cc14(v, obj, p, lo, hi):
    n = round((v - lo) / (hi - lo) * 16383); c = 4 * ((obj - 1) % 8) + p; ch = 12 + (obj - 1) // 8
    return [(0xB0 + ch, c, n // 128), (0xB0 + ch, c + 32, n % 128)]
v = View(TOSC)
v.midi(*sx(4, text='NUENDO'))
for i, (name, az, el, wid, lvl) in enumerate(DEMO):
    v.midi(*sx(1, i, text=name)); v.midi(*sx(3, i, 1))
    for p, (val, lo, hi) in enumerate(((az, -180, 180), (el, -180, 180), (wid, -360, 360))):
        for m in cc14(val, i + 1, p, lo, hi): v.midi(*m)
    v.midi(0xBE, i, lvl)
v.midi(0x9E, 3, 127)
v.tick()
def apply(doc):
    def col(c): return '#%02x%02x%02x%02x' % tuple(round(max(0, min(1, c[k])) * 255) for k in ('r', 'g', 'b', 'a'))
    for i, c in enumerate(doc.walk()):
        n = c.get('name')
        if not n and c.control_type.value in ('LABEL', 'TEXT'): c.name = f'_l{i}'; continue
        if not n or n not in v.c: continue
        m = v.c[n]
        c.set('visible', bool(m['visible']))
        if c.value('text') is not None and m['values']['text']: c.value('text').default = m['values']['text']
        if m['color']: c.color = col(m['color'])
        if m['textColor']: c.set('textColor', col(m['textColor']))
        if re.match(r'^([de]\d+(_glow)?|r\d+_lvl|det_lvl)$', n):
            f = m['frame']; c.frame = (f['x'], f['y'], f['w'], f['h'])
    def strip(c):
        c.children[:] = [k for k in c.children if k.get('visible', True) and k.control_type.value not in ('BUTTON', 'XY') and k.get('name') not in ('top_area', 'pano_area')]
        for k in c.children: strip(k)
    strip(doc.root)
    return doc
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(executable_path="/opt/pw-browsers/chromium")
        pg = await br.new_page(viewport={"width": 1366, "height": 1024})
        doc = apply(py2tosc.load(TOSC))
        svg = fix_svg(py2tosc.to_svg(doc, clip=True), doc)
        await pg.set_content(f"<html><head><style>.p2t-box .p2t-shape{{fill-opacity:1}} .p2t-group .p2t-group > .p2t-shape{{fill:none}} .p2t-box .p2t-shape.p2t-outlined{{fill:none}}</style></head><body style='margin:0;background:#000'>{svg}</body></html>")
        await pg.screenshot(path=os.path.join(HERE, 'dist', 'Vorschau_IEM-Space.png'), clip={"x": 0, "y": 0, "width": 1366, "height": 1024})
        await br.close()
asyncio.run(main())
