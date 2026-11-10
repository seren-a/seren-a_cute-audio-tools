"""Preview PNGs of both Twister View layouts with demo values (preview only)."""
import asyncio, json, sys
import py2tosc, build, mfs_parse
from playwright.async_api import async_playwright
MFS = sys.argv[1]
encs = mfs_parse.parse(open(MFS, 'rb').read())[1]
cols = json.load(open('used_colors.json'))
NAMES = ["Azimuth\nStereoEncoder", "Elevation\nStereoEncoder", "Width\nStereoEncoder", "Roll\nStereoEncoder",
         "Yaw\nSceneRotator", "Pitch\nSceneRotator", "Roll\nSceneRotator", "",
         "Distance\nMultiPanner", "Divergence\nMultiPanner", "Field Size\nMultiPanner", "",
         "Send A\nReverb", "Pre-Delay\nReverb", "Decay\nReverb", "Mix\nReverb"]
VALS = ["+45.0°", "+20.0°", "90.0°", "0.0°", "-30.0°", "+5.0°", "0.0°", "", "3.2 m", "40 %", "1.0", "",
        "-12.0 dB", "18 ms", "2.4 s", "35 %"]
X = [.62, .61, .62, .5, .42, .53, .5, 0, .3, .4, .25, 0, .7, .2, .45, .35]
def demo(doc):
    f = lambda n: doc.find(n)
    f("src").value("text").default = "NUENDO"; f("track").value("text").default = "Vox Lead"
    f("bankname").value("text").default = "IEM 3D"; f("tab1_lbl").value("text").default = "IEM 3D"
    f("tab1").color = "#36d0c4"; f("status").value("text").default = "Bank 1 · 13 belegt"
    for s in range(16):
        n = f"c{s+1}"
        f(n + "_name").value("text").default = NAMES[s]; f(n + "_val").value("text").default = VALS[s]
        f(n + "_cc").value("text").default = f"CC {encs[s]['encoder_midi_number']}"
        bg, bar = f(n + "_barbg").frame, f(n + "_bar")
        bar.frame = (bg.x, bg.y, bg.w * X[s], bg.h)
        r, g, b = cols[str(encs[s]['active_color'])]; bar.color = "#%02x%02x%02x" % (r, g, b)
        if not NAMES[s]: f(n + "_bg").color = "#121418"
    return doc
import re, html
def fix_svg(svg, doc):
    """The py2tosc SVG preview ignores label alignment/background and line breaks: redraw those texts."""
    def sub(m):
        name, ink = m.group(2), m.group(3)
        c = doc.find(name)
        if c is None or c.get('background') is not False: return m.group(0)
        f = c.frame; size = c.get('textSize') or 14
        txt = c.value('text').default or ''
        ah, av = c.get('textAlignH') or 2, c.get('textAlignV') or 2
        x, anchor = {1: (0, 'start'), 2: (f.w / 2, 'middle'), 3: (f.w, 'end')}[ah]
        lines = txt.split('\n')
        lh = size * 1.2
        y0 = size if av == 1 else (f.h - lh * len(lines)) / 2 + size * 0.95
        sp = ''.join(f'<tspan x="{x}" y="{y0 + i * lh:.1f}"{" fill-opacity=\"0.55\"" if i else ""}>{html.escape(l)}</tspan>'
                     for i, l in enumerate(lines))
        return (f'<g class="p2t-control" transform="{m.group(1)}"><text style="fill:{ink};font-family:sans-serif" '
                f'text-anchor="{anchor}" font-size="{size}">{sp}</text></g>')
    return re.sub(r'<g class="p2t-control p2t-(?:text|label)" transform="([^"]*)" data-name="([^"]*)" '
                  r'style="--ink: ([^"]*)">.*?</g>', sub, svg, flags=re.S)
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(executable_path="/opt/pw-browsers/chromium")
        for orient, w, h, out in (("landscape", 1600, 740, "Vorschau_Twister_View_quer.png"),
                                  ("portrait", 720, 1280, "Vorschau_Twister_View.png")):
            pg = await br.new_page(viewport={"width": w, "height": h})
            doc = demo(build.build(MFS, orient=orient))
            svg = fix_svg(py2tosc.to_svg(doc, clip=True), doc)
            await pg.set_content(f"<html><body style='margin:0;background:#000'>{svg}</body></html>")
            await pg.screenshot(path=f"dist/{out}", clip={"x": 0, "y": 0, "width": w, "height": h})
        await br.close()
asyncio.run(main())
