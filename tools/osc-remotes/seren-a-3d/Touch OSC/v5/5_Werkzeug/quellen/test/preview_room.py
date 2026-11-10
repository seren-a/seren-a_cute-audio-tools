"""Vorschau ROOM-Ansicht (dearVR PRO): iPad und Monitor 5:4 mit Demo-Daten durch die echte Logik."""
import asyncio, os, re, sys
D = os.path.dirname(os.path.abspath(__file__)); V3 = os.path.join(D, '..')
sys.path.insert(0, os.path.join(V3, 'overview'))
from view_harness import View
from svgfix import fix_svg
import py2tosc
from playwright.async_api import async_playwright
OUT = os.path.join(V3, 'prev')
CSS = ".p2t-box .p2t-shape{fill-opacity:1} .p2t-group .p2t-group > .p2t-shape{fill:none} .p2t-box .p2t-shape.p2t-outlined{fill:none}"
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def pos(o, x, y, z):
    return [[0xF0, 0x7D, 0x4F, 10, 3, o, p, round((v + 32) / 64 * 16383) // 128, round((v + 32) / 64 * 16383) % 128, 0xF7] for p, v in enumerate((x, y, z))]
def room(o, walls, name):
    b = [14, o]
    for w in walls: cm = round(w * 100); b += [cm // 128, cm % 128]
    return sx(*b, text=name)
SRC = [('Vox Lead', 0.6, 1.4, 0.2), ('Gtr L', -2.2, 0.8, 0.0), ('Gtr R', 2.4, 0.9, 0.0), ('Drums', 0.0, 1.9, -0.3),
       ('Pad', -3.0, -1.8, 1.5), ('FX Rise', 2.8, -2.2, 2.2), ('Choir', -1.0, 1.6, 1.0), ('Atmo', 3.5, 1.5, 0.8)]
MED = (3.8, 2.1, 4.1, 4.0, 2.8, 1.8)
def state(tosc, pano=False):
    v = View(tosc)
    v.midi(*sx(4, text='REAPER'))
    for o, (nm, x, y, z) in enumerate(SRC):
        v.midi(*sx(1, o, text=nm)); v.midi(*sx(3, o, 1))
        v.midi(*room(o, MED if o != 7 else (6.7, 3.4, 6.9, 8.0, 3.3, 1.8), 'Medium Room' if o != 7 else 'Studio Room'))
        for m in pos(o, x, y, z): v.midi(*m)
        v.midi(0xBE, o, 40 + o * 10)
    v.midi(0x9E, 0, 127)
    v.midi(*sx(15, 23, 12, 0))                       # Auslastung (Option an)
    v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_cpu')"); v.run("onReceiveNotify('btn','cfg_close')")
    v.run("onReceiveNotify('btn','mode_room')")
    if pano: v.run("onReceiveNotify('btn','pano_btn')")
    v.tick(16, 10)
    return v
def apply(doc, v, keep=r'^(rt_|rs_|[dpe]\d+(_glow|_dot|_ring|_lo)?$|c\d+|r\d+_lvl|blk|top_xy|pano_xy)'):
    def col(c): return '#%02x%02x%02x%02x' % tuple(round(max(0, min(1, c[k] if c[k] is not None else 1)) * 255) for k in ('r', 'g', 'b', 'a'))
    for i, c in enumerate(doc.walk()):
        n = c.get('name')
        if not n and c.control_type.value in ('LABEL', 'TEXT'): c.name = f'_l{i}'; continue
        if not n or n not in v.c: continue
        m = v.c[n]
        c.set('visible', bool(m['visible']))
        if c.value('text') is not None and m['values']['text']: c.value('text').default = m['values']['text']
        if m['color'] and not n.startswith('th_'): c.color = col(m['color'])
        if m['textColor']: c.set('textColor', col(m['textColor']))
        if re.match(keep, n) or not re.match(r'^(circ|sq|pano|bg_)', n):
            f = m['frame']
            if not re.match(r'^(circ|sq|pano)\d', n) and not n.startswith('bg_'): c.frame = (f['x'], f['y'], f['w'], f['h'])
    def strip(c):
        c.children[:] = [k for k in c.children if k.get('visible', True) and k.control_type.value not in ('XY', 'BUTTON')
                         and not str(k.get('name') or '').endswith('_tap') and k.get('name') not in ('top_area', 'pano_area')]
        for k in c.children: strip(k)
    strip(doc.root)
    return doc
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(executable_path="/opt/pw-browsers/chromium")
        for name, tosc, w, h, pano in (('iPad_5_Room', os.path.join(V3, 'ipad', 'dist', 'seren-a_IEM-Space.tosc'), 1366, 1024, False),
                                       ('Monitor_6_Room', os.path.join(V3, 'monitor', 'dist', 'seren-a_IEM-Monitor.tosc'), 1280, 1024, False),
                                       ('Monitor_7_Room_Seitenansicht', os.path.join(V3, 'monitor', 'dist', 'seren-a_IEM-Monitor.tosc'), 1280, 1024, True)):
            pg = await br.new_page(viewport={"width": w, "height": h})
            v = state(tosc, pano)
            doc = apply(py2tosc.load(tosc), v)
            vf = (20, 68, 200, 16) if 'iPad' in name else (14, 46, 200, 16)   # wie release.py
            lab = py2tosc.label(name="version", frame=vf, text_size=11, text_color="#9a93b0", text_align_h=py2tosc.AlignH.LEFT, background=False, outline=False)
            lab.value("text").default = "v5.0 · 28.10.26"
            doc.root.add(lab)
            svg = fix_svg(py2tosc.to_svg(doc, clip=True), doc)
            await pg.set_content(f"<html><head><style>{CSS}</style></head><body style='margin:0;background:#000'>{svg}</body></html>")
            await pg.screenshot(path=os.path.join(OUT, name + '.png'), clip={"x": 0, "y": 0, "width": w, "height": h})
        await br.close()
asyncio.run(main())
