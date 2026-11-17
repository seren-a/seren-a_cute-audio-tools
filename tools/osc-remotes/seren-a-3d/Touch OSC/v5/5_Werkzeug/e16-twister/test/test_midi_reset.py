"""v8.18: beim Start einmal MIDI-Ausgaenge aus/an (midi_reinit), nur wenn der E16 da ist; abschaltbar; Konsole bleibt still."""
import importlib, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'Reaper_E16_Twister.lua')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def run(outs, ext=''):
    R = importlib.import_module("lupa.lua54").LuaRuntime()
    R.execute(open(os.path.join(HERE, 'reaper_mock.lua')).read())
    R.execute(open(os.path.join(HERE, 'multieq_fake.lua')).read())
    R.execute('REINIT = 0; reaper.midi_reinit = function() REINIT = REINIT + 1 end')
    R.execute('OUTS = {%s}; INS = {"Midi Fighter Twister", "OXI E16"}\nMASTER = {name="MASTER", guid="{M}", fx={}, rec={}}; TRACKS = { {name="Vox", guid="{V}", sel=true, fx={}} }' % outs)
    R.execute("EXTS['seren_E16/console'] = nil")
    if ext: R.execute(ext)
    R.execute(open(SCRIPT, encoding='utf-8').read())
    return R.eval('REINIT'), R.eval("CONSOLE or ''")
n, c = run('"Midi Fighter Twister", "OXI E16"'); check(n == 1, f'E16 da: einmal zurueckgesetzt ({n})'); check(c == '', f'Konsole leer {c!r}')
n, _ = run('"Midi Fighter Twister"'); check(n == 0, 'E16-Ausgang fehlt: kein Reset')
n, _ = run('"OXI E16"', "EXTS['seren_E16/midireset'] = '0'"); check(n == 0, 'Option aus: kein Reset')
n, _ = run('"OXI E16"', "EXTS['seren_midi/reinit'] = tostring(T)"); check(n == 0, 'gerade erst zurueckgesetzt (anderes Skript): nicht nochmal')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED'); sys.exit(fails > 0)
