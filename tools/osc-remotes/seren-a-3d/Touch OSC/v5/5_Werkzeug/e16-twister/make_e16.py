"""Builds Reaper_E16_Twister.lua = Reaper_MultiEQ.lua (v6.1) + Sends/Ziele module (snd.lua) + hooks."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
base = open(os.path.join(HERE, 'base_multieq.lua'), encoding='utf-8').read()
snd = open(os.path.join(HERE, 'snd.lua'), encoding='utf-8').read()
s = base


def R(a, b, n=1):
    global s
    c = s.count(a)
    assert c == n, (a[:80], c)
    s = s.replace(a, b)


R('-- Reaper_MultiEQ.lua · seren.a 3D v6.1\n',
  '-- Reaper_E16_Twister.lua · seren.a 3D v8.0 (was Reaper_MultiEQ.lua + reaper_to_e16.lua + e16-reverb-remote)\n'
  '-- v8.0: E16 page 1 (DAW Link) in Reaper = Sends / Ziele / Spur / Menü (hold 16 = next sub-page),\n'
  '--   Twister bank 4 layer 6 "Sends" (encoder 8 turn = next group, hold = next layer), settings in\n'
  '--   Reaper_E16_Einstellungen.lua or on the E16 menu page. reaper_to_e16.lua and e16-reverb-remote must not run.\n')
R('local VERSION = "v6.1"', 'local VERSION = "v8.11.1"')
R('local LAYER_COL   = { 127, 45, 100, 13, 92 }   -- encoder 8: MultiEQ, Omni, Directional, Hall, Hall-EQ',
  'local LAYER_COL   = { 127, 45, 100, 13, 92, 1 }   -- encoder 8: MultiEQ, Omni, Directional, Hall, Hall-EQ, Sends (blue)')
R('local LAYER_NAME = { "MultiEQ", "Omni", "Directional", "Hall", "Hall-EQ" }',
  'local LAYER_NAME = { "MultiEQ", "Omni", "Directional", "Hall", "Hall-EQ", "Sends" }')
R('local function db(v) return v > 0 and 20 * log(v, 10) or -150 end\n',
  'local function db(v) return v > 0 and 20 * log(v, 10) or -150 end\nlocal SND = {}                         -- Sends / Ziele module (v8.0), filled further down\n')
# layer 6 in the layouts (defaults for 8 / 15 / 16)
R('  for L = 1, 5 do\n    local t = {}', '  for L = 1, 6 do\n    local t = {}')
# Twister rendering: layer 6 encoders belong to the module
R('''  for e = 1, 16 do
    local gm = G.mft[e] or {}
    local o = info(L, e, gm.mode)''', '''  for e = 1, 16 do
    if L == 6 and SND.owns("mft", e) then SND.renderMft(e, force) else
    local gm = G.mft[e] or {}
    local o = info(L, e, gm.mode)''')
R('''    viewColor(e, hx, force)
  end
end''', '''    viewColor(e, hx, force)
    end
  end
end''')
# layer cycle
R('''    mftLayer = mftLayer % 5 + 1
    if mftLayer == 5 and #FEQ == 0 then mftLayer = 1 end''', '''    mftLayer = mftLayer % 6 + 1
    if mftLayer == 5 and #FEQ == 0 then mftLayer = 6 end
    if mftLayer == 6 and not SND.twisterOn() then mftLayer = 1 end''')
R('''    viewSysex({ 6, MFT_BANK }, LAYER_NAME[mftLayer])
    mftForce = true
  elseif e16Page == E16_PAGE_REV then''', '''    viewSysex({ 6, MFT_BANK }, LAYER_NAME[mftLayer])
    mftForce = true
    G.mft = {}                                      -- gestures of the old layer are over
  elseif e16Page == E16_PAGE_REV then''')
# the module goes in right before the press actions (everything it uses exists by then)
R('local function act(dev, e, a, L)                     -- a press action\n',
  snd + '\nlocal function act(dev, e, a, L)                     -- a press action\n')
# input
R('''      if dev == mftIn then
        local e = d1 - MFT_CC + 1
        if st == 0xB0 + MFT_TURN_CH and e >= 1 and e <= 16 then''', '''      if dev == mftIn and mftLayer == 6 and d1 >= MFT_CC and d1 < MFT_CC + 16 and SND.owns("mft", d1 - MFT_CC + 1)
        and (st == 0xB0 + MFT_TURN_CH or st == 0xB0 + MFT_PUSH_CH) then
        if st == 0xB0 + MFT_TURN_CH then SND.input("mft", d1 - MFT_CC + 1, "turn", d2 - 64, now)
        else SND.input("mft", d1 - MFT_CC + 1, "press", d2 > 0, now) end
      elseif dev == mftIn then
        local e = d1 - MFT_CC + 1
        if st == 0xB0 + MFT_TURN_CH and e >= 1 and e <= 16 then''')
R('''      elseif e16Ins[dev] and (st == 0xB0 + E16_IN_EQ''', '''      elseif e16Ins[dev] and st == 0xBF then             -- page 1 (DAW Link, channel 16): Sends / Ziele / Spur / Menü
        if d1 >= 20 and d1 <= 35 then SND.input("e16", d1 - 19, "turn", d2 - 64, now)
        elseif d1 >= 40 and d1 <= 55 then SND.input("e16", d1 - 39, "press", d2 > 0, now) end
      elseif e16Ins[dev] and (st == 0xB0 + E16_IN_EQ''')
# main loop
R('''  rescan(now)
  readInput(now)
  tick(now)''', '''  rescan(now)
  readInput(now)
  tick(now)
  SND.tick(now)''')
R('''  renderMft(full or mftForce)
  renderE16(full or e16Force)''', '''  SND.frame(now, full)
  renderMft(full or mftForce)
  renderE16(full or e16Force)''')
R('''  learnConflicts()
  r.atexit(function()
    if stopped then return end                            -- the newer instance owns the devices now
    r.SetExtState(EXT, "alive", "", false)''', '''  learnConflicts()
  SND.init()
  r.atexit(function()
    if stopped then return end                            -- the newer instance owns the devices now
    SND.exit()
    r.SetExtState(EXT, "alive", "", false)''')
R('msg("MultiEQ " .. VERSION .. " geladen', 'msg("E16+Twister " .. VERSION .. " geladen')
R('"MultiEQ", 0)\n    return\n  end', '"E16+Twister", 0)\n    return\n  end')
R('\ninit()\n', '\nSEREN_DBG = { SND = SND, layer = function() return mftLayer end }   -- for the tests\ninit()\n')
out = os.path.join(HERE, 'Reaper_E16_Twister.lua')
open(out, 'w', encoding='utf-8').write(s)
print('ok', out, s.count('\n'), 'lines')
