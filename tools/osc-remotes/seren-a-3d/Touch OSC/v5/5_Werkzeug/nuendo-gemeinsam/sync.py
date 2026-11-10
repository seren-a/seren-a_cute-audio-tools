"""Copies sendstrip.js and plugctl.js into the Nuendo scripts between their //@@...@@ markers."""
import re, sys, os
here = os.path.dirname(os.path.abspath(__file__))
blocks = [('SENDSTRIP', open(os.path.join(here, 'sendstrip.js')).read().strip()),
          ('PLUGCTL', open(os.path.join(here, 'plugctl.js')).read().strip())]
for p in sys.argv[1:] or ['/home/claude/mft-view/serena_MFTView.js', '/home/claude/e16-display/cubase/serena_E16DAWLink.js']:
    s = open(p).read()
    for name, block in blocks:
        n = re.subn(r'//@@' + name + r'@@.*?//@@END ' + name + r'@@', lambda m: block, s, flags=re.S)
        if n[1] != 1: sys.exit('marker ' + name + ' missing in ' + p)
        s = n[0]
    open(p, 'w').write(s); print('synced', p)
