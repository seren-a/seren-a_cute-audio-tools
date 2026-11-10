"""v6.0: Nuendo -> E16 scene "MultiEQ": feeds the MIDI of serena_E16DAWLink.js (scenario_e16_plug.js)
into E16_MultiEQ.lua on the E16 mock and checks what the E16 shows."""
import importlib, json, sys
lua = importlib.import_module("lupa.lua54")
MOCK = "/home/claude/multieq/test/e16mock.lua"
timeline = json.load(open(sys.argv[1]))
L = lua.LuaRuntime()
E = L.eval(f'dofile("{MOCK}")')
E.load(sys.argv[2])
onCC = L.eval('function(ch, n, v) midi.onCC(0, ch, n, v) end')
snaps = {}
for ev in timeline:
    if 'send' in ev:
        st, cc, v = ev['send']
        assert 0xB0 <= st <= 0xBF and 0 <= cc <= 127 and 0 <= v <= 127, ev
        onCC(st - 0xB0, cc, v)
    elif 'page' in ev:
        E.show(ev['page'])
    elif 'run' in ev:
        E.run(ev['run'])
    elif 'snap' in ev:
        E.run(60)
        lab = {i: E.labels[i] for i in range(1, 17)}
        rg = {i: ((E.rings[i].v, E.rings[i].c) if E.rings[i] else None) for i in range(1, 17)}
        if ev['snap'] == 'mute':                       # blinking: look a while
            cols = set()
            for _ in range(40):
                E.run(20)
                cols.add(E.rings[16].c if E.rings[16] else None)
            rg[16] = cols
        snaps[ev['snap']] = (E.title, lab, rg)
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
t, lab, rg = snaps['eq']
check(rg[9] is not None and rg[9][1] == 87 and rg[1] is not None and rg[1][1] == 36, f'IEM-Farben: MultiEQ Band 1 = 87, Threshold = 36 ({rg[9]}, {rg[1]})')
check(t.startswith('A Out B Vox'), f'Titel: MultiEQ A vom Out, B von der Spur ({t!r})')
check(lab[9] == '40' and lab[10] == '80', f'9/10 = Frequenzen von A ({lab[9]}, {lab[10]})')
check(lab[1] == '-2.0' or lab[1] == '-2', f'1 = Threshold C1 ({lab[1]})')
check(rg[9] is not None and rg[16] is not None, 'Ringe gezeichnet')
t, lab, rg = snaps['turn9']
check(lab[9] != '40', f'gedreht: Wert ändert sich ({lab[9]})')
t, lab, rg = snaps['omni']
check(t.startswith('OMNI Vox'), f'Seite 3: OmniComp ({t!r})')
t, lab, rg = snaps['dir']
check(t.startswith('DIR Vox'), f'8 halten: DirComp ({t!r})')
t, lab, rg = snaps['hall']
check(t.startswith('HALL Vox'), f'Seite 4: Hall ({t!r})')
check(lab[1] not in ('', None) and lab[9] not in ('', None), f'Hall: FDN oben, Convolver unten ({lab[1]}, {lab[9]})')
t, lab, rg = snaps['mute']
check(rg[16] == {57, None}, f'Mute: 16 blinkt rot ({rg[16]})')
t, lab, rg = snaps['back']
check(t.startswith('A Out B Bass'), f'Szene wieder da: neu gezeichnet, neue Spur ({t!r})')
print(f'{fails} FAILED' if fails else 'ALL PASSED')
sys.exit(1 if fails else 0)
