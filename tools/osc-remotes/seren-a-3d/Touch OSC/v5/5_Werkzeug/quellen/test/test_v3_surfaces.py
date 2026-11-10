"""Übersicht (Handy) und IEM space (iPad) v3 gegen beide DAW-Skripte (Mocks)."""
import json, os, subprocess, sys
D = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, D)
from view_harness import View
from lupa import lua54
OV = os.path.join(D, '..', 'overview', 'dist', 'seren-a_Objekt-Uebersicht.tosc')
IP = os.path.join(D, '..', 'ipad', 'dist', 'seren-a_IEM-Space.tosc')
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1

# ================= Reaper-Hub <-> iPad und Handy =================
L = lua54.LuaRuntime(unpack_returned_tuples=True); g = L.globals()
L.execute(open(os.path.join(D, 'reaper_mock.lua')).read())
L.execute("""
local function P(name, v) return { name = name, v = v or 0.5, fmt = function(x) return string.format('%.1f', x * 360 - 180) end } end
local function SE() return { name = 'VST3: StereoEncoder (IEM)', params = {
  P('Ambisonics Order', 0.1), P('Normalization', 1), P('Quaternion W'), P('Quaternion X'), P('Quaternion Y'), P('Quaternion Z'),
  P('Azimuth Angle', 0.75), P('Elevation Angle', 0.5), P('Roll Angle'), P('Stereo Width', 0.5625), P('Sample-wise Panning', 0) } } end
local function SR() return { name = 'VST3: SceneRotator (IEM)', params = {
  P('Ambisonics Order', 0.1), P('Normalization', 1), P('Yaw Angle', 0.6), P('Pitch Angle'), P('Roll Angle') } } end
local function ME(n)
  local p = { P('Number of input channels ', n / 64), P('Ambisonics Order', 0.1), P('Normalization', 1),
    P('Master azimuth angle', 0.25), P('Master elevation angle'), P('Master roll angle'), P('Lock Directions relative to Master', 0) }
  for i = 1, 20 do p[#p+1] = P('Azimuth angle ' .. i, 0.5 + i / 100); p[#p+1] = P('Elevation angle ' .. i); p[#p+1] = P('Gain ' .. i, 6/7);
    p[#p+1] = P('Mute input ' .. i, 0); p[#p+1] = P('Solo input ' .. i, 0) end
  return { name = 'VST3: MultiEncoder (IEM)', params = p }
end
local EQ = { name = 'VST3: Pro-Q 3 (FabFilter)', params = { P('Frequency'), P('Azimuth Angle', 0.3) } }
TRACKS[1] = { name='Vox', guid='{1}', sel=false, info={}, peak=0, fx={ EQ, SE(), SR() } }
TRACKS[2] = { name='Drums OH', guid='{2}', sel=true, info={}, peak=0, fx={ ME(4) } }
TRACKS[3] = { name='Bass', guid='{3}', sel=false, info={}, peak=0, fx={ EQ } }
""")
L.execute(open(os.path.join(D, '..', 'reaper', 'reaper_seren3D.lua')).read())
LV = os.environ.get('LUAV', 'lua54')
ip, ph = View(IP, LV), View(OV, LV)
def pump(n=1):
    for _ in range(n):
        for v in (ip, ph):
            for m in v.sent(): L.execute(f"evIn(2, {m[0]}, {m[1]}, {m[2]})")
        g.T = g.T + 0.05; L.execute("DEFER()")
        o = g.OUT
        for i in range(1, len(o) + 1):
            msg = [o[i].bytes[j] for j in range(1, len(o[i].bytes) + 1)]
            ip.midi(*msg); ph.midi(*msg)
        L.execute("OUT = {}")
        ip.tick(50); ph.tick(50)
P = lambda t, f, p: L.eval(f"TRACKS[{t}].fx[{f}].params[{p}].v")
pump(3)
check(ip.text('src') == 'REAPER ♡' and ip.text('r2_name') == 'Drums OH ✧multi' and ip.c['d2']['visible'] and not ip.c['d3']['visible'],
      f"iPad space: Vox, Drums (Multi), Bass ohne Encoder ({ip.text('r2_name')!r})")
ip.run("onReceiveNotify('btn','sel1')"); pump(2)
check(ip.text('det_name') == 'Vox' and ip.c['yaw_fader']['visible'] and ip.c['fa']['visible'] and L.eval('TRACKS[1].sel'),
      'iPad: Vox gewählt (auch in Reaper), Width- und Rotator-Fader sichtbar')
top = ip.c['top_area']['frame']; R = top['w'] / 2 - 16
ip.run(f"local c = controls.top_xy; c.values.touch = true; c.values.x = {(top['w']/2 - R/2)/top['w']}; c.values.y = 0.5; onReceiveNotify('drag','top_xy')")
ip.run("local c = controls.yaw_fader; c.values.touch = true; c.values.x = 0.25; onReceiveNotify('drag','yaw_fader')")
ip.run("local c = controls.fa; c.values.touch = true; c.values.x = 0.75; onReceiveNotify('drag','fa')")
pump(2)
check(abs(P(1, 2, 7) - 0.75) < 1e-3 and abs(P(1, 3, 3) - 0.25) < 1e-3 and abs(P(1, 2, 10) - (90 + 360) / 720) < 1e-3,
      f'iPad -> Reaper: Vox Azimuth +90, Rotator Yaw -90, Width +90 ({P(1,2,7):.3f} {P(1,3,3):.3f} {P(1,2,10):.3f})')
check(abs(P(1, 1, 2) - 0.3) < 1e-9 and abs(P(1, 2, 1) - 0.1) < 1e-9, 'EQ-"Azimuth" und Ambisonics Order unberührt')
# multi: erst Drums OH in der Liste wählen (wählt auch in Reaper)
ip.run("onReceiveNotify('btn','sel2')"); pump(2)
ip.run("onReceiveNotify('btn','mode_me')"); pump(2)
check(ip.text('bank') == '✧ Drums OH' and ip.c['d4']['visible'] and not ip.c['d5']['visible'] and not ip.c['yaw_fader']['visible'],
      f"iPad multi: 4 Eingänge von Drums OH ({ip.text('bank')!r})")
ip.run("onReceiveNotify('btn','sel2')")
ip.run("local c = controls.pano_xy; c.values.touch = true; c.values.x = 0.75; c.values.y = 0.25; onReceiveNotify('drag','pano_xy')")
ip.run("local c = controls.fa; c.values.touch = true; c.values.x = 0.5; onReceiveNotify('drag','fa')")
pump(2)
az2, el2, g2 = P(2, 1, 8 + 5), P(2, 1, 9 + 5), P(2, 1, 10 + 5)
check(abs(az2 * 360 - 180 + 90) < 0.05 and abs(el2 * 360 - 180 + 45) < 0.05 and abs(g2 - 0.5) < 1e-3,
      f'iPad multi -> Reaper: Eingang 2 Az -90 El -45 Gain -25 dB')
# Pegel
L.execute("TRACKS[1].peak = 1.0"); ip.run("onReceiveNotify('btn','mode_iem')"); pump(2)
check(abs(ip.c['d1_glow']['frame']['w'] - 84) < 0.01, 'Pegel aus Reaper: Vox leuchtet')
# Log
ip.run("onReceiveNotify('btn','log_btn')"); ip.tick(300)
t = ip.text('mon_text')
check(ip.c['mon_overlay']['visible'] and 'Spur 1 Vox - StereoEncoder in FX 2' in t and '→ Eingang 2' in t, f'iPad log: {t[:120]!r}')
# Handy-Übersicht am selben Hub
ph.run("onReceiveNotify('btn','mode_me')"); ph.tick()
check(ph.text('bank') == 'Drums OH' and ph.c['d4']['visible'] and ph.text('r2_val').startswith('Az -90.0°'),
      f"Handy MULTI-ENC: Eingänge sichtbar, Eingang 2 folgt dem iPad ({ph.text('r2_val')!r})")
ph.run("onReceiveNotify('btn','mode_iem')"); ph.midi(0x9E, 0, 127); ph.tick()
check('Rotator: Yaw -90.0°' in ph.text('det_vals'), f"Handy: Rotator im Detail ({ph.text('det_vals')!r})")

# ================= Nuendo-Skript <-> Übersicht/iPad =================
nu = json.loads(subprocess.check_output(['node', os.path.join(D, 'scenario_v3.js'), os.path.join(D, '..', 'nuendo', 'serena_TouchOSC3D.js')]))
LV = os.environ.get('LUAV', 'lua54')
ip, ph = View(IP, LV), View(OV, LV)
for v in (ip, ph):
    for key in ('titlesOut', 'valuesOut', 'selOut'):
        for msg in nu[key]: v.midi(*msg)
    v.tick()
check(ph.text('r2_name') == 'Drums OH (Multi)' and ph.c['d1']['visible'] and not ph.c['d3']['visible'], 'Nuendo -> Handy: Vox, Drums (Multi), Bass ohne Encoder')
ip.run("onReceiveNotify('btn','mode_me')"); ip.tick()
check(ip.c['d4']['visible'] and not ip.c['d5']['visible'], 'Nuendo -> iPad multi: 4 Eingänge')
inb = {(b['ch'], b['cc']): b['label'] for b in nu['inBind'] if 'cc' in b}
mpb = {(b['ch'], b['cc']) for b in nu['mpBind'] if b['in']}
def sentKeys(v):
    return {(m[0] - 0xB0, m[1]) for m in v.sent() if 0xB0 <= m[0] <= 0xBF and m[1] < 32}
ip.sent()
ip.run("onReceiveNotify('btn','sel3'); local c = controls.top_xy; c.values.touch = true; c.values.x = 0.3; c.values.y = 0.6; onReceiveNotify('drag','top_xy')")
k1 = sentKeys(ip)
ip.run("onReceiveNotify('btn','mode_iem'); onReceiveNotify('btn','sel1'); local c = controls.top_xy; c.values.touch = true; c.values.x = 0.3; c.values.y = 0.6; onReceiveNotify('drag','top_xy')")
ip.run("local c = controls.pitch_fader; c.values.touch = true; c.values.x = 0.3; onReceiveNotify('drag','pitch_fader')")
k2 = sentKeys(ip)
check(k1 and {inb.get(k) for k in k1} <= {'In ME 3a', 'In ME 3e'}, f'iPad multi -> Nuendo-Eingänge {sorted(inb.get(k) for k in k1)}')
check({inb.get(k) for k in k2} == {'In Ov Enc 1 az', 'In Ov Rot 1 pitch'}, f'iPad space -> Nuendo-Eingänge (Kreis = nur Azimut) {sorted(str(inb.get(k)) for k in k2)}')
# MultiPanner-Objekt (Mapping Assistant) vom iPad
ip.midi(0xF0, 0x7D, 0x4F, 3, 0, 3, 0xF7)
ip.run("onReceiveNotify('btn','mode_mp')"); ip.tick()
ip.run("onReceiveNotify('btn','sel1'); local c = controls.pano_xy; c.values.touch = true; c.values.x = 0.8; c.values.y = 0.9; onReceiveNotify('drag','pano_xy')")
k3 = sentKeys(ip)
check(k3 and k3 <= mpb and (10, 2) in k3, f'iPad panner (Rückansicht) -> MultiPanner-Regler X/Z {sorted(k3)}')
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")
