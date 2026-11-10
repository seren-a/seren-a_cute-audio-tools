"""Vorschau v3: Demo-Daten laufen durch die echte Oberflächen-Logik (Mock), dann als PNG."""
import asyncio, os, re, sys
D = os.path.dirname(os.path.abspath(__file__))
V3 = os.path.join(D, '..')
sys.path.insert(0, D); sys.path.insert(0, os.path.join(V3, 'overview')); sys.path.insert(0, os.path.join(V3, 'panner'))
from view_harness import View
from svgfix import fix_svg
import py2tosc
from playwright.async_api import async_playwright
OUT = os.path.join(V3, 'prev'); os.makedirs(OUT, exist_ok=True)
OV = os.path.join(V3, 'overview', 'dist', 'seren-a_Objekt-Uebersicht.tosc')
IP = os.path.join(V3, 'ipad', 'dist', 'seren-a_IEM-Space.tosc')
CSS = ".p2t-box .p2t-shape{fill-opacity:1} .p2t-group .p2t-group > .p2t-shape{fill:none} .p2t-box .p2t-shape.p2t-outlined{fill:none}"
# name, rgb, az, el, width, yaw (None = kein Rotator), level, flags (1 enc, 4 multi)
DEMO = [('Vox Lead', (230, 80, 80), 0, 10, 20, -30, 118, 1), ('Drums OH', (240, 160, 60), 40, 15, 0, None, 70, 1 | 4),
        ('Backing', (240, 210, 70), -40, 15, 60, None, 64, 1), ('Gitarre', (110, 210, 120), 75, -5, 30, 15, 92, 1),
        ('Keys', (70, 200, 230), -80, 0, 40, None, 40, 1), ('Pad', (150, 120, 240), 150, 35, 90, None, 85, 1),
        ('FX Swirl', (230, 110, 210), -135, 55, 0, 90, 105, 1), ('Atmo', (200, 200, 200), 0, 0, 0, None, 30, 0)]
ME_IN = [(-60, 20, -3), (60, 20, -3), (-120, 0, -6), (120, 0, -6), (0, 60, 0), (180, -10, -12)]
MPD = [(0, 60, 0), (-50, 40, 20), (50, 40, 20), (-80, -20, 0), (80, -20, 0), (0, -70, 60)]
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def cc14(v, ch, obj, p, lo, hi):
    n = round((v - lo) / (hi - lo) * 16383); c = 4 * ((obj - 1) % 8) + p; ch += (obj - 1) // 8
    return [(0xB0 + ch, c, n // 128), (0xB0 + ch, c + 32, n % 128)]

def feed(v, sel=1):
    v.midi(*sx(7)); v.midi(*sx(4, text='NUENDO'))
    for i, (name, rgb, az, el, wid, yaw, lvl, fl) in enumerate(DEMO):
        o = i + 1
        v.midi(*sx(1, i, text=name)); v.midi(*sx(2, i, *[c // 2 for c in rgb]))
        v.midi(*sx(3, i, fl | (8 if yaw is not None else 0) | (2 if i < len(MPD) else 0)))
        if fl & 1:
            for p, (val, lo, hi) in enumerate(((az, -180, 180), (el, -180, 180), (wid, -360, 360))):
                for m in cc14(val, 12, o, p, lo, hi): v.midi(*m)
        if yaw is not None:
            for p, val in enumerate((yaw, 0, 0)):
                for m in cc14(val, 6, o, p, -180, 180): v.midi(*m)
        v.midi(0xBE, i, lvl)
    for i, xyz in enumerate(MPD):
        v.midi(*sx(6, i, text=DEMO[i][0]))
        for p, val in enumerate(xyz):
            for m in cc14(val, 10, i + 1, p, -100, 100): v.midi(*m)
    v.midi(*sx(9, len(ME_IN), text='Drums OH'))
    for i, (az, el, g) in enumerate(ME_IN):
        for p, (val, lo, hi) in enumerate(((az, -180, 180), (el, -180, 180), (g, -60, 10))):
            for m in cc14(val, 8, i + 1, p, lo, hi): v.midi(*m)
    for t in ('hello|seren.a 3D v3 aktiv · Encoder in Insert 4, Rotator in Insert 5',
              'e0|Spur 1 Vox Lead · Insert 4: StereoEncoder (Azimuth, Elevation, Width)',
              'r0|Spur 1 Vox Lead · Insert 5: SceneRotator (Yaw, Pitch, Roll)',
              'e1|Spur 2 Drums OH · Insert 4: MultiEncoder, 6 Eingaenge (Master Az/El)'):
        v.midi(*sx(8, text=t))
    v.midi(0x9E, sel - 1, 127)
    v.tick()

def apply(doc, v, keep_frames=r'^([de]\d+(_glow|_dot|_ring)?|r\d+_lvl|det_lvl)$', drop=('XY',)):
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
        if re.match(keep_frames, n):
            f = m['frame']; c.frame = (f['x'], f['y'], f['w'], f['h'])
    def strip(c):
        c.children[:] = [k for k in c.children if k.get('visible', True) and k.control_type.value not in drop
                         and not str(k.get('name') or '').endswith('_tap') and k.get('name') not in ('top_area', 'pano_area')]
        for k in c.children: strip(k)
    strip(doc.root)
    return doc

async def shot(pg, doc, path, w, h):
    svg = fix_svg(py2tosc.to_svg(doc, clip=True), doc)
    await pg.set_content(f"<html><head><style>{CSS}</style></head><body style='margin:0;background:#000'>{svg}</body></html>")
    await pg.screenshot(path=path, clip={"x": 0, "y": 0, "width": w, "height": h})

async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(executable_path="/opt/pw-browsers/chromium")
        pg = await br.new_page(viewport={"width": 1366, "height": 1024})
        for mode, sel, name in (('iem', 1, 'iPad_1_IEM'), ('me', 2, 'iPad_2_MultiEncoder'), ('mp', 2, 'iPad_3_MultiPanner'), ('log', 1, 'iPad_4_Log')):
            v = View(IP); feed(v, sel)
            if mode in ('me', 'mp'): v.run(f"onReceiveNotify('btn','mode_{mode}')")
            if mode == 'me': v.run("onReceiveNotify('btn','sel2')")
            if mode == 'log': v.run("onReceiveNotify('btn','log_btn')")
            v.tick(300)
            await shot(pg, apply(py2tosc.load(IP), v, drop=('XY', 'BUTTON')), os.path.join(OUT, f'{name}.png'), 1366, 1024)
        pg = await br.new_page(viewport={"width": 1600, "height": 740})
        for mode, sel, name in (('iem', 1, 'Handy_1_IEM'), ('me', 2, 'Handy_2_MultiEncoder'), ('mp', 1, 'Handy_3_MultiPanner'), ('log', 1, 'Handy_4_Log')):
            v = View(OV); feed(v, sel)
            if mode in ('me', 'mp'): v.run(f"onReceiveNotify('btn','mode_{mode}')")
            if mode == 'log': v.run("onReceiveNotify('btn','log_btn')")
            v.tick(300)
            await shot(pg, apply(py2tosc.load(OV), v, r'^[de]\d+$'), os.path.join(OUT, f'{name}.png'), 1600, 740)
        # Panner: jede Seite statisch
        for fn in ('seren-a_Panner_OSC.tosc', 'seren-a_Panner_Skript.tosc'):
            base = py2tosc.load(os.path.join(V3, 'panner', fn))
            n = len(base.find('pager').children)
            for i in range(n):
                doc = py2tosc.load(os.path.join(V3, 'panner', fn)); pager = doc.find('pager')
                tab = pager.children[i].tab_label if hasattr(pager.children[i], 'tab_label') else str(i)
                pager.children[:] = [pager.children[i]]
                for j, c in enumerate(doc.walk()):
                    if c.get('name') == 'eq_overlay': c.visible = False
                    if not c.get('name') and c.control_type.value in ('LABEL', 'TEXT'): c.name = f'_l{j}'
                safe = re.sub(r'[^A-Za-z0-9]+', '-', str(tab)).strip('-')
                await shot(pg, doc, os.path.join(OUT, f"Panner_{fn.split('_')[2].split('.')[0]}_{i + 1}_{safe}.png"), 1600, 740)
        await br.close()
asyncio.run(main())
