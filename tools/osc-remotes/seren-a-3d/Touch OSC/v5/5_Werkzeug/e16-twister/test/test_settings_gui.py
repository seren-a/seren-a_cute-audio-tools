"""Smoke test of both settings windows with a stand-in ImGui; checks the reverb suggestions from FX categories."""
import os, sys, tempfile
from lupa import lua54
HERE = os.path.dirname(os.path.abspath(__file__))
E16_GUI = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'Reaper_E16_Einstellungen.lua')
OXI_GUI = sys.argv[2] if len(sys.argv) > 2 else None
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1

RES = tempfile.mkdtemp()
open(os.path.join(RES, 'reaper-fxtags.ini'), 'w').write('[developer]\nFdnReverb.vst3=IEM\n[category]\nFdnReverb.vst3=Reverb\nValhallaDelay.vst3=Delay|Modulation\nTAL-Chorus.vst3=Modulation\n')
open(os.path.join(RES, 'reaper-fxfolders.ini'), 'w').write('[Folders]\nNbFolders=1\nName0=Room Sims\n[Folder0]\nNb=1\nItem0=/Library/Audio/Plug-Ins/VST3/MyRoom.vst3\nType0=3\n')

def run(path, extra=''):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(open(os.path.join(HERE, 'reaper_mock.lua')).read())
    L.execute('''
MASTER = {name="MASTER", guid="{M}", fx={}}
function mkfx(name, ident) return {name = name, ident = ident} end
A = {name="A1 Tisch Fenster", guid="{A}", fx={}, vals={}}; B = {name="E1", guid="{B}", fx={}, vals={}}
C = {name="Vox", guid="{C}", sel=true, fx={}, vals={}}; D = {name="Delay Bus", guid="{D}", fx={}, vals={}}
F = {name="Chorus Bus", guid="{F}", fx={}, vals={}}; G = {name="Ohne Receives", guid="{G}", fx={}, vals={}}
H = {name="Raum", guid="{H}", fx={}, vals={}}
A.fxl = { mkfx("VST3: dearVR PRO (Dear Reality)", "/Library/Audio/Plug-Ins/VST3/dearVR PRO.vst3") }
B.fxl = { mkfx("VST3: FdnReverb (IEM)", "/Library/Audio/Plug-Ins/VST3/FdnReverb.vst3") }
D.fxl = { mkfx("VST3: ValhallaDelay (Valhalla DSP)", "/x/ValhallaDelay.vst3") }
F.fxl = { mkfx("VST3: TAL-Chorus", "/x/TAL-Chorus.vst3") }
G.fxl = { mkfx("VST3: FdnReverb (IEM)", "/x/FdnReverb.vst3") }
H.fxl = { mkfx("VST3: MyRoom", "/Library/Audio/Plug-Ins/VST3/MyRoom.vst3") }
TRACKS = {C, A, B, D, F, G, H}
C.sends = { {dest=A}, {dest=B}, {dest=D}, {dest=F}, {dest=H} }
reaper.TrackFX_GetCount = function(t) return #(t.fxl or {}) end
reaper.TrackFX_GetFXName = function(t, i) return true, t.fxl[i+1].name end
reaper.TrackFX_GetNamedConfigParm = function(t, i, k) if k == "fx_ident" then return true, t.fxl[i+1].ident end return false, "" end
reaper.GetResourcePath = function() return [[''' + RES + ''']] end
reaper.GetSelectedTrack = function(_, i) local n = 0; for _, t in ipairs(TRACKS) do if t.sel then if n == i then return t end n = n + 1 end end end
reaper.CountSelectedTracks = function() local n = 0; for _, t in ipairs(TRACKS) do if t.sel then n = n + 1 end end return n end
CALLS = {}; PUSH = 0; POP = 0
setmetatable(reaper, { __index = function(t, k)
  if k:match("^ImGui_Col_") or k:match("^ImGui_StyleVar_") or k:match("^ImGui_ColorEditFlags") or k:match("^ImGui_Cond") then return function() return 1 end end
  if k:match("^ImGui_") then return function(ctx, a, b) CALLS[#CALLS+1] = k .. ":" .. tostring(a)
    if k == "ImGui_PushStyleColor" then PUSH = PUSH + 1 elseif k == "ImGui_PopStyleColor" then POP = POP + (a or 1) end
    if k == "ImGui_Begin" then return true, true end
    if k == "ImGui_Checkbox" then if CLICK and a:find(CLICK, 1, true) then return true, not b end return false, b end
    if k == "ImGui_Combo" then return false, b end
    if k == "ImGui_InputText" then return false, b end
    if k == "ImGui_RadioButton" or k == "ImGui_Button" then return false end
    if k == "ImGui_CreateContext" then return {} end
    return nil end end end })
''' + extra)
    L.execute(open(path, encoding='utf-8').read())
    g = L.globals(); g.DEFER()
    return L, g

L, g = run(E16_GUI)
calls = [g.CALLS[i] for i in range(1, len(g.CALLS) + 1)]
boxes = [c.split(':', 1)[1].split('##')[0] for c in calls if c.startswith('ImGui_Checkbox:') and '##{' in c]
why = [c.split(':', 1)[1] for c in calls if c.startswith('ImGui_TextDisabled:')]
check(boxes == ['2 A1 Tisch Fenster', '3 E1', '4 Delay Bus', '7 Raum'], f'Vorschläge: dearVR, Kategorie Reverb, Delay, Ordner Room; ohne Chorus und ohne Spur ohne Receives ({boxes})')
check(any('FdnReverb' in w and 'reverb' in w for w in why) and any('dearVR PRO' in w for w in why), f'Grund steht dabei ({why[1:5]})')
check(g.PUSH == g.POP and g.PUSH > 20, f'Farben der TouchOSC-Looks gesetzt und sauber zurückgenommen ({g.PUSH}/{g.POP})')
L, g = run(E16_GUI, 'CLICK = "3 E1##"')
check(g.PEXT['seren_E16/targets'] == '{B}', 'Haken bei E1: E1 ist Ziel')
L, g = run(E16_GUI, 'PEXT["seren_E16/targets"] = "{A},{B}"; CLICK = "2 A1 Tisch Fenster##"')
check(g.PEXT['seren_E16/targets'] == '{B}', 'Haken weg bei A1: nur noch E1')
if OXI_GUI:
    L, g = run(OXI_GUI)
    check(g.PUSH == g.POP and g.PUSH > 20 and any(c.startswith('ImGui_ColorButton') for c in [g.CALLS[i] for i in range(1, len(g.CALLS) + 1)]),
          'OXI-Fenster: Looks + Farbfelder der States')
print('\nALL OK' if fails == 0 else f'\n{fails} FAILED')
sys.exit(1 if fails else 0)
