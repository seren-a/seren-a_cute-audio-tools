"""v8.4: Spurfilter in der DAW (Reaper), echte Spurnummern, leere Bänke überspringen (iPad, Monitor, Handy)."""
import os
from lupa import lua54
from view_harness import View
D = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
def sx(cmd, *d, text=''): return [0xF0, 0x7D, 0x4F, cmd, *d, *[ord(c) for c in text], 0xF7]

# ================= Reaper hub =================
L = lua54.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
L.execute(open(os.path.join(D, 'reaper_mock.lua')).read())
L.execute("""
EXT["seren_3D/filter"] = nil            -- default of the script: all types, only tracks with a 3D plugin
local function P(name, v) return { name = name, v = v or 0.5, fmt = function(x) return string.format('%.1f', x) end } end
local function SE() return { name = 'VST3: StereoEncoder (IEM)', params = { P('Azimuth Angle'), P('Elevation Angle'), P('Stereo Width') } } end
local DV = { name = 'VST3: dearVR PRO 2 (Dear Reality)', params = { P('Input Mode'), P('Azimuth'), P('Elevation'), P('Distance') } }
for i = 1, 60 do TRACKS[i] = { name = 'T' .. i, guid = '{' .. i .. '}', sel = false, info = {}, peak = 0, fx = {} } end
TRACKS[3].fx = { SE() }; TRACKS[10].fx = { SE() }; TRACKS[51].fx = { DV }
TRACKS[20].folder = true; TRACKS[30].recv = 2; TRACKS[40].instr = true
""")
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
def pump(n=1):
    out = []
    for _ in range(n):
        g.T = g.T + 0.05; L.execute("DEFER()")
        o = g.OUT
        out += [[o[i].bytes[j] for j in range(1, len(o[i].bytes) + 1)] for i in range(1, len(o) + 1)]
        L.execute("OUT = {}")
    return out
def objs(m):
    names = {x[4]: ''.join(chr(c) for c in x[5:-1]) for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 1]}
    nums = {x[4]: x[5] * 128 + x[6] for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 17]}
    return [names.get(i, '') for i in range(4)], [nums.get(i, 0) for i in range(4)]
m = pump(2)
nm, no = objs(m)
check(nm[:3] == ['T3', 'T10', 'T51'] and nm[3] == '', f'Standard: nur Spuren mit 3D-Plugin, dearVR auf Spur 51 steht auf Platz 3 ({nm})')
check(no[:3] == [3, 10, 51], f'echte Spurnummern gehen mit (cmd 17) ({no})')
check([0xF0, 0x7D, 0x4F, 16, 15, 1, 0xF7] in m, 'Filterstand an die Oberflächen (cmd 16 = 15,1)')
def filt(types, plug):
    L.execute(f"SEQ = SEQ + 1; table.insert(HIST, 1, {{SEQ, string.char(0xF0, 0x7D, 0x4F, 0x0B, {types}, {plug}, 0xF7), 2}})")
filt(2, 0)
m = pump(3)
nm, no = objs(m)
check(nm[0] == 'T30' and nm[1] == '' and g.EXT['seren_3D/filter'] == '2,0', f'Filter FX (= Spuren mit Receives), alle: nur T30, gespeichert ({nm}, {g.EXT["seren_3D/filter"]})')
check([0xF0, 0x7D, 0x4F, 5, 0, 0xF7] in m and [0xF0, 0x7D, 0x4F, 16, 2, 0, 0xF7] in m, 'Filterwechsel: Bank 1 + neuer Stand an alle')
filt(4, 0); nm, _ = objs(pump(3))
check(nm[0] == 'T20' and nm[1] == '', f'Filter Gruppe/Ordner: T20 ({nm})')
filt(8, 0); m = pump(3); nm, _ = objs(m)
fl = {x[4]: x[5] for x in m if x[:4] == [0xF0, 0x7D, 0x4F, 3]}
check(nm[0] == 'T40' and fl.get(0) == 64, f'Filter Instrument: T40 mit Flag 64 ({nm}, {fl.get(0)})')
filt(15, 0); nm, no = objs(pump(3))
check(nm == ['T1', 'T2', 'T3', 'T4'] and no == [1, 2, 3, 4], f'alle Spuren: wie früher ({nm})')

# ================= surfaces =================
for name, tosc, pre in (('iPad', os.path.join(D, '..', 'ipad', 'dist', 'seren-a_IEM-Space.tosc'), 'r'),
                        ('Monitor', os.path.join(D, '..', 'monitor', 'dist', 'seren-a_IEM-Monitor.tosc'), 'c'),
                        ('Handy', os.path.join(D, '..', 'overview', 'dist', 'seren-a_Objekt-Uebersicht.tosc'), 'r')):
    v = View(tosc)
    v.midi(*sx(4, text='REAPER'))
    v.midi(*sx(1, 0, text='Vox')); v.midi(*sx(3, 0, 1)); v.midi(*sx(17, 0, 0, 51)); v.tick(16, 3)
    num = v.text(f'{pre}1_num')
    check(num == '51', f'{name}: Liste zeigt die echte Spurnummer 51 ({num!r})')
    lab = v.text('range_lbl' if pre == 'c' else 'bank')
    check('51' in lab, f'{name}: Bereich nach echten Nummern ({lab!r})')
    if name != 'Handy':
        v.sent()
        v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_only')"); v.tick()
        s = v.sent()
        check([0xF0, 0x7D, 0x4F, 0x0B, 15, 0, 0xF7] in s, f'{name}: „nur Spuren mit Plugin“ aus → Filter an die DAW')
        v.run("onReceiveNotify('btn','cfg_sh_audio')"); v.tick()
        check([0xF0, 0x7D, 0x4F, 0x0B, 14, 0, 0xF7] in v.sent(), f'{name}: Audio aus → Filter 14,0')
        v.run("onReceiveNotify('btn','cfg_close')")
        v.midi(*sx(16, 2, 1)); v.tick(); v.sent()
        v.run("onReceiveNotify('btn','cfg_btn')"); v.run("onReceiveNotify('btn','cfg_sh_group')"); v.tick()
        s = v.sent()
        check([0xF0, 0x7D, 0x4F, 0x0B, 6, 1, 0xF7] in s, f'{name}: Stand der DAW übernommen (FX, nur Plugin) + Gruppe an = 6,1 ({s})')
        v.run("onReceiveNotify('btn','cfg_close')")
    # skipping empty banks (Nuendo: no filter in the DAW)
    v = View(tosc)
    v.midi(*sx(4, text='Nuendo'))
    v.midi(*sx(1, 0, text='Bass')); v.midi(*sx(3, 0, 0)); v.tick()
    v.sent()
    v.run("onReceiveNotify('btn','bank_next')"); v.tick()
    s = v.sent()
    check(s == [[0x9F, 3, 127], [0x9F, 3, 0]], f'{name}: Bank vor = Note 3')
    v.midi(*sx(5, 1)); v.tick(100, 9)
    s = v.sent()
    check(s == [[0x9F, 3, 127], [0x9F, 3, 0]], f'{name}: Bank 2 ohne Encoder → geht von selbst weiter ({s})')
    v.midi(*sx(5, 2)); v.midi(*sx(3, 0, 1)); v.tick(100, 10)
    check(v.sent() == [], f'{name}: Bank 3 mit Encoder → bleibt stehen')
    v.run("onReceiveNotify('btn','bank_next')"); v.tick(); v.sent()
    v.midi(*sx(5, 3)); v.midi(*sx(3, 0, 0)); v.tick(100, 9); v.sent()
    v.tick(100, 20)
    check(v.sent() == [], f'{name}: am Ende (kein Bankwechsel mehr) hört es auf')

print('\nALL OK' if fails == 0 else f'\n{fails} FAILED')
import sys; sys.exit(1 if fails else 0)
