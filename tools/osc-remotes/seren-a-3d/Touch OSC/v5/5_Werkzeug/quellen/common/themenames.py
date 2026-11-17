"""Build step: lists all text controls by colour role so the palettes can recolour every label (light text,
dim text, cyan accent text). Prepended to the root script as the global THEME_NAMES."""
import re

def _cls(c):
    r, g, b = c.r, c.g, c.b
    if r > 0.9 and g > 0.9: return 'txt'
    if 0.6 < r < 0.8 and 0.55 < g < 0.7 and b > 0.8: return 'dim'
    if 0.78 < r < 0.8 and 0.64 < g < 0.67 and b > 0.95: return 'dim'          # panorama titles
    if r < 0.5 and g > 0.9 and b > 0.95: return 'acc'
    return None

def theme_script(doc):
    out = {'txt': [], 'dim': [], 'acc': []}
    for c in doc.walk():
        if c.control_type.value not in ('LABEL', 'TEXT'): continue
        n = c.get('name')
        if not n or re.match(r'^cfg_.*_lbl$', n) or n.endswith('_icon') or n.endswith('_glyph') or re.match(r'^(th_|_l)', n): continue
        k = _cls(c.get('textColor'))
        if k: out[k].append(n)
    q = lambda l: '{' + ','.join("'%s'" % x for x in l) + '}'
    return "THEME_NAMES = { txt = %s, dim = %s, acc = %s }\n" % (q(out['txt']), q(out['dim']), q(out['acc']))
