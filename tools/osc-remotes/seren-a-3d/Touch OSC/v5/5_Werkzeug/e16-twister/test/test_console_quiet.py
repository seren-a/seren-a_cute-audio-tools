"""Console: quiet by default (no start message), on with ExtState seren_E16/console = 1."""
import importlib, os
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'Reaper_E16_Twister.lua')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def run(console):
    R = importlib.import_module("lupa.lua54").LuaRuntime()
    R.execute(open(os.path.join(HERE, 'reaper_mock.lua')).read())
    R.execute(open(os.path.join(HERE, 'multieq_fake.lua')).read())
    R.execute('''OUTS = {"Midi Fighter Twister", "OXI E16"}; INS = {"Midi Fighter Twister", "OXI E16"}
MASTER = {name="MASTER", guid="{M}", fx={}, rec={}}; TRACKS = { {name="Vox", guid="{V}", sel=true, fx={}} }''')
    R.execute("EXTS['seren_E16/console'] = " + ("'1'" if console else "nil"))
    R.execute(open(SCRIPT, encoding='utf-8').read())
    return R.eval("CONSOLE or ''")
q = run(False); l = run(True)
check('geladen' not in q and 'Sends/Ziele' not in q, f'Standard: keine Startmeldungen ({q!r})')
check('geladen' in l, 'Option an: Startmeldung da')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED'); import sys; sys.exit(fails > 0)
