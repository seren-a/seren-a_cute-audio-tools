"""Renders what the root script really draws (all 4 looks, both orientations) from the TouchOSC mock to PNG.
usage: python3 look_preview.py <outdir>"""
import asyncio, html, json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from view_harness import View
from playwright.async_api import async_playwright

D = os.path.join(os.path.dirname(__file__), '..', 'dist')
OUT = sys.argv[1] if len(sys.argv) > 1 else D
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
MFS = '/root/.claude/uploads/1d4028fa-12da-5404-ac70-1ceecfe42680/0f3307c3-midi_fighter_2026_jan_vor_croissant.mfs'
IEM = {'cyan': '#00CAFE', 'green': '#50FE03', 'orange': '#FE9F01', 'red': '#CF021C', 'white': '#FFFFFF'}
CELLS = [("Azimuth\nStereoEncoder", "+45.0°", 80, 'cyan'), ("Elevation\nStereoEncoder", "+20.0°", 75, 'green'),
         ("Roll\nStereoEncoder", "0.0°", 64, 'orange'), ("Width\nStereoEncoder", "90.0°", 70, 'red'),
         ("Threshold\nOmniCompressor", "-18.0 dB", 40, 'orange'), ("Ratio\nOmniCompressor", "4.0 : 1", 30, 'red'),
         ("Attack\nOmniCompressor", "12 ms", 20, 'cyan'), ("Makeup\nOmniCompressor", "+3.5 dB", 70, 'green'),
         ("Room Size\nFdnReverb", "48 m", 60, 'green'), ("Reverb Time\nFdnReverb", "2.40 s", 50, 'cyan'),
         ("Dry/Wet\nFdnReverb", "35 %", 45, 'orange'), ("", "", None, None),
         ("Send A · Hall 3D\nFX 1", "-12.0 dB", 90, 'cyan'), ("Send B · Delay lang\nFX 2", "-inf", 0, 'cyan'),
         ("Preset\nFdnReverb", "Kirche", 64, 'white'), ("Lautstärke\nVox Lead", "0.00", 100, 'red')]


def sx(*b): return [0xF0, 0x7D, 0x4D, *b, 0xF7]
CODE = {c: i + 1 for i, c in enumerate('äöüÄÖÜß°')}
def txt(s): return [CODE.get(c, ord(c)) for c in s]


def feed(v):
    bank = 3   # 0-based: bank 4 = plugins
    v.midi(*sx(5, *txt('NUENDO'))); v.midi(*sx(3, *txt('17 Vox Lead')))
    for b, n in enumerate(['Kanal/EQ', 'Insert 1+2', 'frei', 'Plugins']): v.midi(*sx(6, b, *txt(n)))
    import mfs_parse
    enc = mfs_parse.parse(open(MFS, 'rb').read())[1]
    for s, (name, val, x, c) in enumerate(CELLS):
        if not name: continue
        v.midi(*sx(1, bank, s, *txt(name))); v.midi(*sx(2, bank, s, *txt(val)))
        h = IEM[c].lstrip('#'); r, g, bl = (int(h[i:i + 2], 16) * 127 // 255 for i in (0, 2, 4))
        v.midi(*sx(8, bank, s, r, g, bl))
        e = enc[bank * 16 + s]; ch, cc = e['encoder_midi_channel'] - 1, e['encoder_midi_number']
        v.midi(0xB0 + ch, cc, round(x * 127 / 100))
    v.midi(*sx(4, bank)); v.tick(30, 3)


def dump(v, doc):
    out = []
    for c in doc.walk():
        n = c.get('name')
        if not n or n not in v.c: continue
        m = v.c[n]
        f = m['frame']; col = m['color']; tc = m['textColor']
        out.append(dict(n=n, t=c.control_type.name, x=f['x'], y=f['y'], w=f['w'], h=f['h'], vis=bool(m['visible']) if m['visible'] is not None else True,
                        col=[col['r'], col['g'], col['b'], col['a']] if col else None,
                        tc=[tc['r'], tc['g'], tc['b'], tc['a'] or 1] if tc else None,
                        text=m['values']['text'] or '', x01=m['values']['x'],
                        size=m['textSize'] or c.get('textSize') or 14, ah=m['textAlignH'], dah=c.get('textAlignH') or 2,
                        av=c.get('textAlignV') or 2, rad=c.get('cornerRadius') or 0, docc=str(c.get('color') or '')))
    return out


def rgba(c, a=None):
    if not c: return 'transparent'
    return f"rgba({c[0]*255:.0f},{c[1]*255:.0f},{c[2]*255:.0f},{c[3] if a is None else a})"


def page(items, w, h):
    el = []
    for i in items:
        if not i['vis']: continue
        st = f"left:{i['x']}px;top:{i['y']}px;width:{i['w']}px;height:{i['h']}px"
        if i['t'] in ('BOX', 'BUTTON'):
            if not i['col'] and i['docc'].startswith('Color('):
                i['col'] = [float(x.split('=')[1]) for x in i['docc'][6:-1].split(', ')]
            el.append(f"<div class='e' style='{st};background:{rgba(i['col'])};border-radius:{i['rad']}px'></div>")
        elif i['t'] == 'RADIAL':
            r = min(i['w'], i['h']) / 2 - 6; cx, cy = i['w'] / 2, i['h'] / 2
            import math
            a0, sweep = math.radians(135), math.radians(270)
            def pt(a): return cx + r * math.cos(a), cy + r * math.sin(a)
            def arc(fr, colr, wid):
                a1 = a0 + sweep * fr; x0, y0 = pt(a0); x1, y1 = pt(a1)
                big = 1 if sweep * fr > math.pi else 0
                return f"<path d='M{x0:.1f},{y0:.1f} A{r},{r} 0 {big} 1 {x1:.1f},{y1:.1f}' stroke='{colr}' stroke-width='{wid}' fill='none' stroke-linecap='round'/>"
            el.append(f"<svg class='e' style='{st}' viewBox='0 0 {i['w']} {i['h']}'>{arc(1, '#2B2350', 9)}{arc(max(i['x01'], .001), rgba(i['col']), 9)}</svg>")
        else:
            ah = {0: 'left', 1: 'center', 2: 'right'}[i['ah']] if i['ah'] is not None else {1: 'left', 2: 'center', 3: 'right'}[i['dah']]
            jv = {1: 'flex-start', 2: 'center', 3: 'flex-end'}[i['av']]
            lines = html.escape(i['text']).split('\n')
            body = lines[0] + ''.join(f"<br><span style='opacity:.55;font-size:.62em'>{l}</span>" for l in lines[1:])
            el.append(f"<div class='e' style='{st};display:flex;flex-direction:column;justify-content:{jv};text-align:{ah};"
                      f"font-size:{i['size']}px;line-height:1.12;color:{rgba(i['tc']) if i['tc'] else '#ddd'};overflow:hidden'><div>{body}</div></div>")
    return (f"<html><head><meta charset='UTF-8'><style>body{{margin:0;background:#000}}.e{{position:absolute;box-sizing:border-box}}"
            f"*{{font-family:-apple-system,'Helvetica Neue',Roboto,Arial,sans-serif}}</style></head>"
            f"<body><div style='position:relative;width:{w}px;height:{h}px;overflow:hidden'>{''.join(el)}</div></body></html>")


async def main():
    shots = []
    async with async_playwright() as p:
        br = await p.chromium.launch()
        for tag, fn in (('hoch', 'seren-a_Twister_View.tosc'), ('quer', 'seren-a_Twister_View_quer.tosc')):
            v = View(os.path.join(D, fn))
            feed(v)
            rf = v.doc.root.frame
            for look in range(5):
                v.tick(30, 2)
                name = v.text('look_lbl').replace('Look: ', '').replace(' ', '_')
                pg = await br.new_page(viewport={'width': rf.w, 'height': rf.h})
                await pg.set_content(page(dump(v, v.doc), rf.w, rf.h))
                out = os.path.join(OUT, f'look{look + 1}_{name}_{tag}.png')
                await pg.screenshot(path=out); shots.append(out)
                v.run("onReceiveNotify('btn', 'look_btn')")
        await br.close()
    print('\n'.join(shots))

asyncio.run(main())
