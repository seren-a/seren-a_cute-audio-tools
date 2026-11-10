"""Every .member / .method( used on API objects in the scripts must exist in midiremote_api_v1.d.ts."""
import re, sys
D = open(sys.argv[1]).read()
api = set(re.findall(r'^\s*(m[A-Z]\w*)\s*:', D, re.M)) | set(re.findall(r'^\s*([a-zA-Z]\w*)\s*\(', D, re.M))
JS_BUILTIN = {'push','charAt','charCodeAt','substr','toLowerCase','test','exec','match','toFixed','abs','round',
              'max','min','floor','now','hasOwnProperty','length','require','replace','concat','join'}
bad = 0
for f in sys.argv[2:]:
    src = re.sub(r'//.*', '', open(f).read())
    used = set(re.findall(r'\.(m[A-Z]\w*)', src)) | set(re.findall(r'\.([a-zA-Z]\w*)\s*\(', src))
    for name in sorted(used):
        if name in JS_BUILTIN: continue
        ok = name in api
        if not ok: bad += 1
        print(('ok   ' if ok else 'MISSING ') + f.split('/')[-1] + ': ' + name)
print('ALL NAMES FOUND' if bad == 0 else f'{bad} MISSING')
