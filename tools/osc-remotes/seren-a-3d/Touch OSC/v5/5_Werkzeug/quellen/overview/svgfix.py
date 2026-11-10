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
