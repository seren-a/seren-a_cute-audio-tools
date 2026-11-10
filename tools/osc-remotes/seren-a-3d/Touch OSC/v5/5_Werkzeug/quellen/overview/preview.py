"""Vorschau der Objekt-Übersicht: Beispieldaten durch die echte Logik (Mock), dann als Bild."""
import asyncio, math, os, sys, re, html
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'test'))
sys.path.insert(0, '/home/claude/mft-view')
from view_harness import View
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from svgfix import fix_svg
import py2tosc
from playwright.async_api import async_playwright
HERE = os.path.dirname(os.path.abspath(__file__))
TOSC = os.path.join(HERE, 'dist', 'seren-a_Objekt-Uebersicht.tosc')
DEMO = [('Vox Lead', (230, 80, 80), 0, 10, 20), ('Backing L', (240, 160, 60), 40, 15, 60),
        ('Backing R', (240, 210, 70), -40, 15, 60), ('Gitarre', (110, 210, 120), 75, -5, 30),
        ('Keys', (70, 200, 230), -80, 0, 40), ('Pad', (150, 120, 240), 150, 35, 90),
        ('FX Swirl', (230, 110, 210), -135, 55, 0), ('Kick', (200, 200, 200), 0, -30, 0)]
MPD = [(0, 60, 0), (-50, 40, 20), (50, 40, 20), (-80, -20, 0), (80, -20, 0), (0, -70, 60)]
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def cc14(v, ch, obj, p, lo, hi):
    n = round((v - lo) / (hi - lo) * 16383); c = 4 * ((obj - 1) % 8) + p
    return [(0xB0 + ch, c, n // 128), (0xB0 + ch, c + 32, n % 128)]
def state(mode):
    v = View(TOSC)
    v.midi(*sx(4, text='NUENDO'))
    for i, (name, rgb, az, el, wid) in enumerate(DEMO):
        v.midi(*sx(1, i, text=name)); v.midi(*sx(3, i, 1 | (2 if i < len(MPD) else 0)))
        v.midi(*sx(2, i, *[c // 2 for c in rgb]))
        for p, (val, rng) in enumerate(((az, (-180, 180)), (el, (-180, 180)), (wid, (-360, 360)))):
            for m in cc14(val, 12, i + 1, p, *rng): v.midi(*m)
    for i, xyz in enumerate(MPD):
        v.midi(*sx(6, i, text=DEMO[i][0]))
        for p, val in enumerate(xyz):
            for m in cc14(val, 10, i + 1, p, -100, 100): v.midi(*m)
    v.midi(*sx(1, 8, text='Atmo Bed')); v.midi(*sx(3, 8, 0))
    v.midi(0x9E, 1, 127)
    if mode == 'mp': v.run("onReceiveNotify('btn','mode_mp')")
    v.tick()
    return v
def apply(doc, v):
    for i, c in enumerate(doc.walk()):
        if not c.get('name') and c.control_type.value in ('LABEL', 'TEXT'):
            c.name = f'_l{i}'
    def hexcol(c): return '#%02x%02x%02x' % tuple(round(c[k] * 255) for k in 'rgb')
    for c in doc.walk():
        n = c.get('name')
        if not n or n not in v.c: continue
        m = v.c[n]
        c.set('visible', bool(m['visible']))
        if c.value('text') is not None and m['values']['text']: c.value('text').default = m['values']['text']
        if m['color']: c.color = hexcol(m['color'])
        if re.match(r'^[de]\d+$', n):
            f = m['frame']; c.frame = (f['x'], f['y'], f['w'], f['h'])
    def strip(c):
        c.children[:] = [k for k in c.children if k.get('visible', True) and not str(k.get('name') or '').endswith('_tap')]
        for k in c.children: strip(k)
    strip(doc.root)
    return doc
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(executable_path="/opt/pw-browsers/chromium")
        pg = await br.new_page(viewport={"width": 1600, "height": 740})
        for mode, out in (('iem', 'Vorschau_Objekt-Uebersicht_IEM.png'), ('mp', 'Vorschau_Objekt-Uebersicht_MultiPanner.png')):
            doc = apply(py2tosc.load(TOSC), state(mode))
            svg = fix_svg(py2tosc.to_svg(doc, clip=True), doc)
            await pg.set_content(f"<html><head><style>.p2t-box .p2t-shape{{fill-opacity:1}} .p2t-group .p2t-group > .p2t-shape{{fill:none}} .p2t-box .p2t-shape.p2t-outlined{{fill:none}}</style></head><body style='margin:0;background:#000'>{svg}</body></html>")
            await pg.screenshot(path=os.path.join(HERE, 'dist', out), clip={"x": 0, "y": 0, "width": 1600, "height": 740})
        await br.close()
asyncio.run(main())
