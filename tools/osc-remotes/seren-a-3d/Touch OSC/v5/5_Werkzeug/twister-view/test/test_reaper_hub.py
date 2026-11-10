"""End to end: reaper_mft_hub.lua (Lua 5.4, Reaper mock) -> MIDI -> Twister View (TouchOSC mock)."""
import importlib, os
from view_harness import View
D = os.path.join(os.path.dirname(__file__), '..', 'dist')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
view = View(os.environ.get('TOSC') or os.path.join(D, 'seren-a_Twister_View.tosc'))
lua = importlib.import_module("lupa.lua54"); R = lua.LuaRuntime(); rg = R.globals()
R.execute(open('reaper_mock.lua').read())
R.execute(r'''
local function P(name, v, learn, fmt) return {name = name, v = v, learn = learn, fmt = fmt or function(x) return string.format("%.1f deg", x * 360 - 180) end} end
ENCF = {name = "VST3: StereoEncoder (IEM)", params = {P("Ambisonics Order", 0), P("Azimuth Angle", 0.625, {midi1 = 176, midi2 = 0, flags = 1}),
        P("Elevation Angle", 0.5, {midi1 = 176, midi2 = 1, flags = 1}), P("Stereo Width", 0.5, {midi1 = 176, midi2 = 20})}}
EQF = {name = "VST: ReaEQ (Cockos)", params = {P("Gain-Band 1", 0.5, {midi1 = 176, midi2 = 49}, function(x) return string.format("%.1f dB", x * 48 - 24) end),
       P("Freq-Band 1", 0.2, {midi1 = 177, midi2 = 2}), P("Note learn", 0.1, {midi1 = 144, midi2 = 3})}}
OTHER = {name = "VST3: StereoEncoder (IEM)", params = {P("Ambisonics Order", 0), P("Azimuth Angle", 0.1, {midi1 = 176, midi2 = 0, flags = 1})}}
TRACKS = { {name = "Vox Lead", guid = "{A}", sel = true, fx = {ENCF}},
           {name = "Bus", guid = "{B}", sel = false, fx = {EQF}},
           {name = "Kick", guid = "{C}", sel = false, fx = {OTHER}} }
''')
def flush(dev_view=2):
    out = rg.OUT; msgs = []
    for i in range(1, len(out) + 1):
        m = out[i]; b = [m.bytes[j] for j in range(1, len(m.bytes) + 1)]
        msgs.append((m.dev, b))
        if m.dev == dev_view: view.midi(*b)
    R.execute("OUT = {}")
    view.tick()
    return msgs
def step(dt=0.05):
    R.execute(f"T = T + {dt}; DEFER()")
    return flush()

R.execute(open(os.path.join(D, 'reaper_mft_hub.lua')).read())
m0 = flush()
check(any(b[:4] == [0xF0, 0x7D, 0x4D, 7] for d, b in m0), 'start: clear sent to the view')
m = m0 + step()
check(view.text('bankname') == 'Bank 4', f"start on bank 4 ({view.text('bankname')})")
R.execute("evIn(1, 0xB3, 0, 127)"); m = m + step()
check(view.text('src') == 'REAPER' and view.text('track') == 'Vox Lead', f"source + track ({view.text('src')}, {view.text('track')})")
check(view.text('c1_name') == 'Azimuth Angle\nStereoEncoder' and view.text('c1_val') == '45.0 deg', f"bank 1 enc 1 from learn ({view.text('c1_name')!r}, {view.text('c1_val')})")
check(view.text('c2_name').startswith('Elevation'), 'enc 2 = elevation')
check(abs(view.bar(1) - 79 / 127) < 1e-6, 'bar = parameter value as CC')
check(view.text('c3_name') == '', 'note-learned parameter ignored (CC only)')
check(not any(b[:1] == [0xB1] for d, b in m), 'channel-2 learn is not a Twister encoder (Twister sends channel 1)')
twister = [b for d, b in m if d == 1]
check([0xB0, 0, 79] in twister, 'value also sent back to the Twister ring')
# Kick also listens to CC 0 but only "selected track only" -> Vox wins; select Kick instead
R.execute("TRACKS[1].sel = false; TRACKS[3].sel = true")
step()
check(view.text('c1_val') == '-144.0 deg' and view.text('track') == 'Kick', f"selection change: Kick's azimuth now ({view.text('c1_val')})")
check(view.text('c2_name') == '', "Vox's elevation (selected-track-only) disappears")
R.execute("TRACKS[1].sel = true; TRACKS[3].sel = false"); step()
# Twister bank buttons -> view follows (bank 4 = CC 49 ReaEQ gain)
R.execute("evIn(1, 0xB3, 0, 0); evIn(1, 0xB3, 3, 127)"); step()
check(view.text('bankname') == 'Bank 4' and view.text('c1_name').startswith('Gain-Band 1') and view.text('c1_val') == '0.0 dB',
      f"Twister bank 4 -> ReaEQ gain on CC 49 ({view.text('c1_name')!r} {view.text('c1_val')})")
# parameter moves (turning the Twister or automation) -> value + text update
R.execute("EQF.params[1].v = 0.75"); m = step()
check(view.text('c1_val') == '12.0 dB' and abs(view.bar(1) - 95 / 127) < 1e-6, 'value change shows up')
step(); check(len(flush()) == 0, 'nothing sent while nothing changes')
# bank tab on the phone -> forwarded to the Twister
R.execute("evIn(2, 0xB3, 1, 127)"); m = step()
check(view.text('bankname') == 'Bank 2' and [0xB3, 1, 127] in [b for d, b in m if d == 1], 'phone tab -> view + Twister bank 2')
check(view.text('c5_name').startswith('Stereo Width'), 'bank 2 enc 5 = width (CC 20)')
# periodic resync, exit
R.execute("T = T + 6"); m = step()
check(view.text('c5_name').startswith('Stereo Width') and view.text('src') == 'REAPER', 'resync keeps the view')
# Reaper_MultiEQ.lua running: the hub leaves bank 4 alone, and takes it back when it stops
R.execute("EXTS['seren_MultiEQ/alive'] = tostring(T)"); m = step()
R.execute("EQF.params[1].v = 0.75"); m = step()
check(not any(b[:6] == [0xF0, 0x7D, 0x4D, 2, 3, 0] for d, b in m) and not any(b[:2] == [0xB0, 49] for d, b in m),
      'MultiEQ läuft: Hub sendet nichts für Bank 4')
R.execute("EXTS['seren_MultiEQ/alive'] = ''"); m = step()
check(any(b[:6] == [0xF0, 0x7D, 0x4D, 1, 3, 0] for d, b in m) and any(b[:2] == [0xB0, 49] for d, b in m),
      'MultiEQ beendet: Hub sendet Bank 4 sofort wieder')
R.execute("ATEXIT()"); flush()
check(view.text('src') != 'REAPER', 'script stopped: view leaves REAPER mode')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
