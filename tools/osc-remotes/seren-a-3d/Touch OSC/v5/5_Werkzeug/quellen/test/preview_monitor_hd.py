"""Vorschau IEM monitor (5:4): Demo-Daten durch die echte Logik, alle Ansichten als PNG."""
import asyncio, os, re, sys, math
D = os.path.dirname(os.path.abspath(__file__)); V3 = os.path.join(D, '..')
sys.path.insert(0, D); sys.path.insert(0, os.path.join(V3, 'overview'))
from view_harness import View
from svgfix import fix_svg
import py2tosc
from playwright.async_api import async_playwright
TOSC = os.path.join(V3, 'monitor', 'dist', 'seren-a_IEM-Monitor_HD.tosc')
OUT = os.path.join(V3, 'prev_hd'); os.makedirs(OUT, exist_ok=True)
CSS = ".p2t-box .p2t-shape{fill-opacity:1} .p2t-group .p2t-group > .p2t-shape{fill:none} .p2t-box .p2t-shape.p2t-outlined{fill:none}"
NAMES = ['Vox Lead', 'Backing L', 'Backing R', 'Kick', 'Snare', 'OH L', 'OH R', 'Bass DI', 'Gitarre', 'Keys', 'Pad', 'Synth Lead',
         'Strings', 'Choir', 'Atmo L', 'Atmo R', 'FX Rise', 'Reverb', 'Delay', 'Room', 'Perc', 'Hats', 'Toms', 'Brass',
         'Sax', 'Piano', 'Organ', 'Vox Dbl', 'Harmony', 'Sub', 'Click', 'Noise']
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]
def enc(v, o, p):
    n = round((v + 180) / 360 * 16383)
    if o < 16:
        ch, cc = 12 + o // 8, 4 * (o % 8) + p
        return [[0xB0 + ch, cc, n // 128], [0xB0 + ch, cc + 32, n % 128]]
    return [[0xF0, 0x7D, 0x4F, 10, 0, o, p, n // 128, n % 128, 0xF7]]
def encw(w, o):
    n = round((w + 360) / 720 * 16383)
    if o < 16: ch, cc = 12 + o // 8, 4 * (o % 8) + 2; return [[0xB0 + ch, cc, n // 128], [0xB0 + ch, cc + 32, n % 128]]
    return [[0xF0, 0x7D, 0x4F, 10, 0, o, 2, n // 128, n % 128, 0xF7]]
def state(layout, pano=False, cfg=False, colors=False, move=False):
    v = View(TOSC)
    v.midi(*sx(4, text='REAPER')); v.midi(*sx(12, 64))
    for o in range(64):
        nm = NAMES[o % 32] + ('' if o < 32 else ' 2')
        v.midi(*sx(1, o, text=nm))
        fl = 1 | (16 if nm.startswith(('Reverb', 'Delay', 'FX')) else 0) | (32 if nm.startswith('OH') else 0) | (64 if nm.startswith(('Synth', 'Keys', 'Piano')) else 0)
        v.midi(*sx(3, o, fl))
        v.midi(*sx(2, o, 40 + (o * 37) % 87, 40 + (o * 53) % 87, 40 + (o * 71) % 87))
        az = ((o * 47) % 360) - 180; el = ((o * 23) % 100) - 30
        for m in enc(az, o, 0) + enc(el, o, 1): v.midi(*m)
        if o % 5 == 1:
            for m in encw(40 + (o * 13) % 80, o): v.midi(*m)
        v.midi(0xBE, o, (o * 29) % 128)
    v.midi(*sx(11, 3, text='kick')); v.midi(0x9E, 0, 127)
    v.run(f"onReceiveNotify('btn','lay_{layout}')")
    if pano: v.run("onReceiveNotify('btn','pano_btn')")
    if colors: v.run("onReceiveNotify('btn','col_btn')")
    if cfg: v.run("onReceiveNotify('btn','cfg_btn')")
    v.tick(16, 20)
    if move:
        v.tick(1000, 3)
        for o, az in ((6, 75), (21, -120), (40, 15), (57, 160)):
            for m in enc(az, o, 0): v.midi(*m)
        v.tick(16, 2)
    return v
def apply(doc, v):
    def col(c): return '#%02x%02x%02x%02x' % tuple(round(max(0, min(1, c[k] if c[k] is not None else 1)) * 255) for k in ('r', 'g', 'b', 'a'))
    for i, c in enumerate(doc.walk()):
        n = c.get('name')
        if not n and c.control_type.value in ('LABEL', 'TEXT'): c.name = f'_l{i}'; continue
        if not n or n not in v.c: continue
        m = v.c[n]
        c.set('visible', bool(m['visible']))
        if c.value('text') is not None and m['values']['text']: c.value('text').default = m['values']['text']
        if n.startswith('th_'): continue
        if m['color']: c.color = col(m['color'])
        if m['textColor']: c.set('textColor', col(m['textColor']))
        if m['textSize']: c.set('textSize', int(m['textSize']))
        if m['cornerRadius']: c.set('cornerRadius', float(m['cornerRadius']))
        f = m['frame']
        if not re.match(r'^(circ|sq|pano)\ds?$', n): c.frame = (f['x'], f['y'], f['w'], f['h'])
    def strip(c):
        c.children[:] = [k for k in c.children if k.get('visible', True) and k.control_type.value not in ('XY', 'BUTTON')]
        for k in c.children: strip(k)
    strip(doc.root)
    return doc
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(executable_path="/opt/pw-browsers/chromium")
        pg = await br.new_page(viewport={"width": 1920, "height": 1080})
        for name, kw in (('MonitorHD_1_16', dict(layout='16')), ('MonitorHD_2_32v', dict(layout='32v', colors=True)),
                         ('MonitorHD_3_32h', dict(layout='32h', pano=True)), ('MonitorHD_4_64', dict(layout='64', move=True)), ('MonitorHD_4b_64_Horizont', dict(layout='64', pano=True)),
                         ('MonitorHD_5_Config', dict(layout='16', cfg=True)), ('MonitorHD_6_32r', dict(layout='32r')), ('MonitorHD_6b_32r_Horizont', dict(layout='32r', pano=True))):
            v = state(**kw)
            doc = apply(py2tosc.load(TOSC), v)
            svg = fix_svg(py2tosc.to_svg(doc, clip=True), doc)
            await pg.set_content(f"<html><head><style>{CSS}</style></head><body style='margin:0;background:#000'>{svg}</body></html>")
            await pg.screenshot(path=os.path.join(OUT, name + '.png'), clip={"x": 0, "y": 0, "width": 1920, "height": 1080})
        await br.close()
asyncio.run(main())
