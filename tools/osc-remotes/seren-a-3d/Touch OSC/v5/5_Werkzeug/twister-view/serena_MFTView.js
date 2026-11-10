// seren.a · Twister View for Nuendo / Cubase (MIDI Remote API 1.x)
// Install: <Driver Scripts Folder>/Local/serena/MFTView/serena_MFTView.js
// The Midi Fighter Twister is the input, the TouchOSC Bridge the output: Nuendo's values go to
// the phone as CC (same numbers as the Twister), names/display values/bank/track as SysEx.
// NOT TESTED IN NUENDO/CUBASE: API names checked against midiremote_api_v1.d.ts, logic against a mock.
//
// Mapping: 64 knobs = the Twister's 4 banks (CC numbers from your .mfs).
//   Bank 1 = Isabella's "basic channel" bank, taken over from her DJ Tech Tools mapping (page
//            "Default"), selected track: turn CC 0-3 EQ Q 1-4, 4-7 EQ gain 1-4, 8-11 EQ freq 1-4,
//            12 low cut, 13 high cut, 14 pan, 15 volume; push (note, channel 2) 0-3 EQ band on,
//            4 drum editor, 5 pattern editor, 6 instrument, 7 channel settings, 8 read, 9 write,
//            10 monitor, 11 record, 12 low cut on, 13 high cut on, 14 mute, 15 solo.
//   Bank 2 = insert slot 1 + slot 2, 8 parameters each (Remote Control Editor order).
//   Bank 3 = free for the Mapping Assistant.
//   Bank 4 (relative encoders, Twister_Bank4_MultiEQ.mfs) has two modes. HOLD encoder 16 and let go
//            without turning = switch (the Twister View tab says which):
//     Sends/QC: rows 1-2 (encoders 1-8) = sends 1-8, -40..0 dB; push = send on/off;
//            hold push + turn = pre/post. If the track has no 8th send, encoder 8 = track
//            volume and its push = solo. Rows 3-4 (encoders 9-16) = track quick controls 1-8.
//     Plugins (Nuendo/Cubase 13+, DirectAccess): MultiEQ, Omni-/DirectionalCompressor, FDN reverb +
//            mcfx convolver of the selected track - the same layers and gestures as Reaper_MultiEQ.lua
//            (hold encoder 8 and let go = next layer). See the block PLUGCTL below.
//            (Pushes: CC 49-64 on channel 2, as set in your .mfs.)
// Bank 4 also lights the Twister (rings, colours): give the port "Twister" (output) the Midi Fighter
// Twister in the MIDI Remote Manager if Nuendo doesn't do it by itself.
// v6.1: input "View" = TouchOSC Bridge (or the network session the Twister View uses): tapping a bank on
// the Twister View switches the Twister's bank. Colours follow the IEM plugins (Twister, View, E16).

var midiremote_api = require('midiremote_api_v1')

var IN_MATCH = 'Twister'
var OUT_MATCH = 'TouchOSC Bridge'
var SYS_CH = 3                  // Twister system channel, 0-based (3 = channel 4)
var DEFAULT_MAPPING = true
var SLOT_A = 0, SLOT_B = 1

//@@ENC@@
var ENC = [[0, 0]]
//@@END@@

var driver = midiremote_api.makeDeviceDriver('serena', 'MFTView', 'seren.a')
function clog(t) { try { console.log('[seren.a Twister] ' + t) } catch (e) {} }
clog('Twister-Skript v6.1 geladen')
var mftIn = driver.mPorts.makeMidiInput('Twister')
var viewOut = driver.mPorts.makeMidiOutput('TouchOSC')
var mftOut = driver.mPorts.makeMidiOutput('Twister')     // bank 4: rings and colours back to the Twister
var viewIn = driver.mPorts.makeMidiInput('View')          // taps on the Twister View (bank keys)
driver.makeDetectionUnit().detectPortPair(mftIn, viewOut)
  .expectInputNameContains(IN_MATCH)
  .expectOutputNameContains(OUT_MATCH)
function twister(dev, msg) { try { mftOut.sendMidi(dev, msg) } catch (e) {} }

var NB = Math.floor(ENC.length / 16)

// --- text to the view ---------------------------------------------------------------------------
// SysEx carries 7 bits: umlauts, ß and ° travel as codes 1-8, the view turns them back (v6.1)
var MAP = { 'ä': '\x01', 'ö': '\x02', 'ü': '\x03', 'Ä': '\x04', 'Ö': '\x05', 'Ü': '\x06', 'ß': '\x07', '°': '\x08' }
function ascii(s) {
  var out = ''
  s = String(s || '')
  for (var i = 0; i < s.length; i++) {
    var ch = MAP.hasOwnProperty(s.charAt(i)) ? MAP[s.charAt(i)] : s.charAt(i)
    var c = ch.length ? ch.charCodeAt(0) : 0
    if (ch.length && (ch === '\n' || (c >= 1 && c <= 8) || (c >= 32 && c <= 126))) out += ch
  }
  return out.replace(/^\s+|\s+$/g, '').substr(0, 64)
}

var sent = {}
function sysex(dev, head, text, force) {
  var s = text === undefined ? '' : ascii(text)
  var key = head.join(',')
  if (!force && text !== undefined && sent[key] === s) return
  sent[key] = s
  var msg = [0xF0, 0x7D, 0x4D].concat(head)
  for (var i = 0; i < s.length; i++) msg.push(s.charCodeAt(i))
  msg.push(0xF7)
  viewOut.sendMidi(dev, msg)
}

function withUnit(x, u) { x = String(x || ''); return u ? x + (u === '°' ? '' : ' ') + u : x }

function now() { return (typeof Date !== 'undefined') ? Date.now() : 0 }

// --- surface: 64 knobs, absolute CC like the Twister sends them -------------------------------
var knobs = []                  // { mSurfaceValue } for every encoder, push encoders included
var pushes = []                 // push values (bank 1 and bank 4), by encoder index
var SB = 48                     // bank 4, first encoder = send 1
var SW_CH = 1                   // Twister switch channel, 0-based (1 = channel 2)
for (var i = 0; i < ENC.length; i++) {
  var b = Math.floor(i / 16), s = i % 16
  var x = b * 5 + (s % 4), y = Math.floor(s / 4)
  var push = (b === 0) || (b === 3)
  var sv
  if (push) {
    var pe = driver.mSurface.makePushEncoder(x, y, 1, 1)
    sv = pe.mEncoderValue
    pushes[i] = pe.mPushValue
    var pb = pe.mPushValue.mMidiBinding.setInputPort(mftIn)
    if (b === 0) pb.bindToNote(SW_CH, ENC[i][1])          // bank 1: push = note on channel 2
    else pb.bindToControlChange(SW_CH, ENC[i][1])         // bank 4: push = CC on channel 2
  } else {
    sv = driver.mSurface.makeKnob(x, y, 1, 1).mSurfaceValue
  }
  var mb = sv.mMidiBinding.setInputPort(mftIn)
  if (!(i >= SB && i < SB + 16)) mb.setOutputPort(viewOut)  // bank 4: the script draws the rings itself
  var cb = mb.bindToControlChange(ENC[i][0], ENC[i][1])
  if (i >= SB && i < SB + 16) cb.setTypeRelativeBinaryOffset()   // bank 4 is relative (ENC 3FH/41H)
  knobs.push({ mSurfaceValue: sv })
}

function wire(idx) {
  var b = Math.floor(idx / 16), s = idx % 16
  var sv = knobs[idx].mSurfaceValue
  sv.mOnTitleChange = function (dev, objectTitle, valueTitle) {
    sysex(dev, [1, b, s], valueTitle ? valueTitle + (objectTitle ? '\n' + objectTitle : '') : '')
    if (!valueTitle) sysex(dev, [2, b, s], '')
  }
  sv.mOnDisplayValueChange = function (dev, value, units) {
    sysex(dev, [2, b, s], withUnit(value, units))
  }
}
for (var w = 0; w < ENC.length; w++) wire(w)

// the Twister reports bank changes on its system channel: CC <bank> = 127
function wireBank(b) {
  var v = driver.mSurface.makeCustomValueVariable('bank' + (b + 1))
  v.mMidiBinding.setInputPort(mftIn).bindToControlChange(SYS_CH, b)
  v.mOnProcessValueChange = function (dev, value) { if (value > 0.5) sysex(dev, [4, b]) }
}
for (var nb = 0; nb < NB; nb++) wireBank(nb)

// a bank key on the Twister View: switch the Twister's bank (system channel, CC <bank> = 127)
function wireViewBank(b) {
  var v = driver.mSurface.makeCustomValueVariable('view bank' + (b + 1))
  v.mMidiBinding.setInputPort(viewIn).bindToControlChange(SYS_CH, b)
  v.mOnProcessValueChange = function (dev, value) {
    if (value < 0.5) return
    v.setProcessValue(dev, 0)                            // so the next tap fires again
    twister(dev, [0xB0 + SYS_CH, b, 127])
    sysex(dev, [4, b])
  }
}
for (var vb = 0; vb < NB; vb++) wireViewBank(vb)
var BANK_NAMES = ['Kanal/EQ', 'Insert 1+2', 'frei', 'Sends/QC']

var lastAlive = 0
function hello(dev) {
  var name = 'NUENDO'
  if (midiremote_api.mDefaults && midiremote_api.mDefaults.mAppVersion &&
      midiremote_api.mDefaults.mAppVersion.getVersionString) {
    var v = String(midiremote_api.mDefaults.mAppVersion.getVersionString())
    if (/cubase/i.test(v)) name = 'CUBASE'
  }
  sysex(dev, [5], name, true)
  for (var bn = 0; bn < 3 && bn < NB; bn++) sysex(dev, [6, bn], BANK_NAMES[bn], true)
  lastAlive = now()
}
driver.mOnActivate = function (dev) {
  clog('aktiv - Twister rein, TouchOSC Bridge raus')
  sent = {}
  sysex(dev, [7])
  hello(dev)
}
driver.mOnIdle = function (dev) {             // Cubase/Nuendo 13+: keep-alive for the view
  if (now() - lastAlive > 5000) hello(dev)
}

// bank 4: every encoder also has a never-bound counter (steps), every push goes through the script.
// Sends/QC mode: steps 1-8 drive the send strip, QCs 9-16 are bound (relative) on the sub page.
// Plugins mode: everything goes to the plugin control (plug).
var b4mode = 'sends'
var b4Down = []
var MODE_HOLD = 600
function b4Steps(i) {
  var r = driver.mSurface.makeCustomValueVariable('b4 steps ' + (i + 1))
  r.mMidiBinding.setInputPort(mftIn).setIsConsuming(false)
    .bindToControlChange(ENC[SB + i][0], ENC[SB + i][1]).setTypeRelativeBinaryOffset()
  r.mOnProcessValueChange = function (dev, v) {
    if (Math.abs(v - 0.5) < 1e-6) return                 // our own reset
    var steps = Math.round((v - 0.5) * 128)
    if (steps === 0) steps = v > 0.5 ? 1 : -1
    r.setProcessValue(dev, 0.5)                          // only a counter
    if (b4Down[i]) b4Down[i].moved = true
    if (b4mode === 'plug') { if (plug) plug.turn(dev, 'mft', i + 1, steps) }
    else if (i < 8 && strip) strip.turnRel(dev, i, steps)
  }
}
function b4Push(i) {
  pushes[SB + i].mOnProcessValueChange = function (dev, v) {
    var down = v > 0.5
    if (b4mode === 'plug') { if (plug) plug.press(dev, 'mft', i + 1, down); return }
    if (i < 8 && strip) { if (down) strip.press(dev, i); else strip.release(dev, i) }
    if (i === 15) {                                      // hold 16 and let go = Plugins mode
      if (down) { b4Down[i] = { t: now(), moved: false }; return }
      var d = b4Down[i]
      b4Down[i] = null
      if (d && !d.moved && now() - d.t >= MODE_HOLD) setMode(dev, 'plug')
    }
  }
}

//@@SENDSTRIP@@ (shared by serena_MFTView.js and serena_E16DAWLink.js - edit common_mr/sendstrip.js, then sync)
// Send strip: sends 1-8 of the selected track, -40..0 dB, push = send on/off, hold push + turn =
// pre/post. If the track has no 8th send, the 8th encoder is the track volume and its push is solo.
// Everything goes through custom variables that are bound to Nuendo's values. The script only
// ever writes them in reaction to YOUR hands (turn / push), never when a page or bank changes or
// when Nuendo reports a value - so switching pages cannot overwrite anything.
//
// dB <-> Nuendo value: the API has no "set send level in dB", only 0..1. Nuendo's fader curve isn't
// published, so the script learns it: every time Nuendo reports a send/volume (number + dB text,
// e.g. when you select a track) that pair becomes a calibration point. Until then it uses a curve
// with 0 dB at 0.785 (the Cubase/Nuendo fader position for 0 dB). After one or two track changes
// the dB values you dial in are exact.
var SS_LO = -40, SS_HI = 0           // send range in dB
var SS_PREPOST_TICKS = 6             // hold + turn: this many encoder steps = one pre/post change
var SS_CAL = { send: [], vol: [] }   // learned points [norm, dB]

function ssGuess(db) { return db <= -150 ? 0 : 0.785 * Math.pow(Math.pow(10, db / 20), 1 / 2.853) }
function ssParseDb(text) {
  var s = String(text || '')
  if (/inf|∞/i.test(s)) return -200
  var m = /[-+]?[0-9]+(\.[0-9]+)?/.exec(s)
  return m ? parseFloat(m[0]) : null
}
function ssLearn(kind, norm, db) {
  if (db === null || db <= -100 || norm <= 0.001) return
  var t = SS_CAL[kind]
  for (var k = 0; k < t.length; k++) {
    if (Math.abs(t[k][0] - norm) < 0.004) { t[k] = [norm, db]; return }
  }
  t.push([norm, db])
  t.sort(function (a, b) { return a[1] - b[1] })
  if (t.length > 48) t.splice(Math.floor(t.length / 2), 1)
}
// dB -> 0..1: the guessed curve, corrected by the learned points around the target
function ssNorm(kind, db) {
  if (db <= -150) return 0
  var g = ssGuess(db), t = SS_CAL[kind], lo = null, hi = null
  for (var k = 0; k < t.length; k++) {
    if (t[k][1] <= db) lo = t[k]
    if (t[k][1] >= db && hi === null) hi = t[k]
  }
  var r = 1
  if (lo && hi && hi[1] > lo[1]) {
    var rl = lo[0] / ssGuess(lo[1]), rh = hi[0] / ssGuess(hi[1])
    r = rl + (rh - rl) * (db - lo[1]) / (hi[1] - lo[1])
  } else if (lo || hi) {
    var p = lo || hi
    r = p[0] / ssGuess(p[1])
  }
  return Math.max(0, Math.min(1, g * r))
}
function ssFmtDb(db) { return db <= -100 ? '-inf' : (db > 0 ? '+' : '') + db.toFixed(1) }

// ui = { title(dev, i, name, label), value(dev, i, text), ring(dev, i, pos01 or -1 for off) }
function makeSendStrip(page, mc, prefix, ui) {
  var S = { lvl: [], on: [], pre: [], st: [], vol: null, solo: null, volDb: null, volNorm: 0, soloOn: false }
  var sends = mc.mSends
  function cv(name) { return driver.mSurface.makeCustomValueVariable(prefix + name) }

  function fallback() { return !S.st[7].has }
  function show(dev, i) {
    var s = S.st[i]
    if (i === 7 && fallback()) {
      ui.title(dev, i, 'Volume', 'Spur')
      ui.value(dev, i, (S.volDb === null ? '' : ssFmtDb(S.volDb) + ' dB') + (S.soloOn ? '  SOLO' : ''))
      ui.ring(dev, i, S.volNorm)
      return
    }
    if (!s.has) { ui.title(dev, i, '', ''); ui.value(dev, i, ''); ui.ring(dev, i, -1); return }
    ui.title(dev, i, s.title, 'Send ' + (i + 1))
    var txt = s.db === null ? '' : ssFmtDb(s.db) + ' dB'
    if (s.pre) txt += ' pre'
    if (!s.on) txt += ' AUS'
    ui.value(dev, i, txt)
    ui.ring(dev, i, s.db === null ? 0 : Math.max(0, Math.min(1, (s.db - SS_LO) / (SS_HI - SS_LO))))
  }

  function wireSend(i) {
    var slot = sends.getByIndex(i)
    var s = { has: false, title: '', on: true, pre: false, db: null, norm: 0, held: false, turned: 0,
              pickup: false, lastPos: null, pFresh: false, dFresh: false }
    S.st[i] = s
    var lvl = cv('send' + (i + 1) + 'Level'), on = cv('send' + (i + 1) + 'On'), pre = cv('send' + (i + 1) + 'Pre')
    page.makeValueBinding(lvl, slot.mLevel)
    page.makeValueBinding(on, slot.mOn)
    page.makeValueBinding(pre, slot.mPrePost)
    S.lvl[i] = lvl; S.on[i] = on; S.pre[i] = pre
    slot.mOnTitleChange = function (dev, mapping, title) {
      s.has = !!title
      s.title = title || ''
      s.pickup = false
      show(dev, i)
      if (i === 7) show(dev, 7)
    }
    // Nuendo -> script: only remember and display, never write back
    function pair() { if (s.pFresh && s.dFresh) { ssLearn('send', s.norm, s.db); s.pFresh = s.dFresh = false } }
    lvl.mOnProcessValueChange = function (dev, v) { s.norm = v; s.pFresh = true; pair(); show(dev, i) }
    lvl.mOnDisplayValueChange = function (dev, value) { s.db = ssParseDb(value); s.dFresh = true; pair(); show(dev, i) }
    on.mOnProcessValueChange = function (dev, v) { s.on = v > 0.5; show(dev, i) }
    pre.mOnProcessValueChange = function (dev, v) { s.pre = v > 0.5; show(dev, i) }
  }
  for (var i = 0; i < 8; i++) wireSend(i)

  S.vol = cv('Volume'); S.solo = cv('Solo')
  page.makeValueBinding(S.vol, mc.mValue.mVolume)
  page.makeValueBinding(S.solo, mc.mValue.mSolo)
  var vf = { p: false, d: false }
  function vpair() { if (vf.p && vf.d) { ssLearn('vol', S.volNorm, S.volDb); vf.p = vf.d = false } }
  S.vol.mOnProcessValueChange = function (dev, v) { S.volNorm = v; vf.p = true; vpair(); if (fallback()) show(dev, 7) }
  S.vol.mOnDisplayValueChange = function (dev, value) { S.volDb = ssParseDb(value); vf.d = true; vpair(); if (fallback()) show(dev, 7) }
  S.solo.mOnProcessValueChange = function (dev, v) { S.soloOn = v > 0.5; if (fallback()) show(dev, 7) }

  function setDb(dev, i, db) {
    var s = S.st[i]
    db = Math.max(SS_LO, Math.min(SS_HI, db))
    S.lvl[i].setProcessValue(dev, ssNorm('send', db))
    s.db = db
    show(dev, i)
  }
  function prePostStep(dev, i, ticks) {
    var s = S.st[i]
    ticks = Math.abs(ticks)
    if (ticks === 0) return
    var flip = s.turned === 0              // the first step flips at once, then every N steps
    if (!flip) { s.acc += ticks; if (s.acc >= SS_PREPOST_TICKS) { s.acc -= SS_PREPOST_TICKS; flip = true } }
    s.turned += ticks
    if (flip) {
      s.pre = !s.pre
      S.pre[i].setProcessValue(dev, s.pre ? 1 : 0)
      show(dev, i)
    }
  }

  // absolute encoder (Twister): pos 0..1 = -40..0 dB
  S.turnAbs = function (dev, i, pos) {
    var s = S.st[i]
    if (i === 7 && fallback()) { if (s.held) s.turned++; S.vol.setProcessValue(dev, pos); S.volNorm = pos; show(dev, 7); return }
    if (!s.has) return
    var last = s.lastPos
    s.lastPos = pos
    if (s.held) { if (last !== null) prePostStep(dev, i, Math.round(Math.abs(pos - last) * 127)); return }
    if (s.pickup) {            // after hold + turn the knob is off by the turned amount: wait until it
      var cur = s.db === null ? 0 : (s.db - SS_LO) / (SS_HI - SS_LO)     // passes the current level
      if (last === null || (last - cur) * (pos - cur) > 0 && Math.abs(pos - cur) > 0.02) return
      s.pickup = false
    }
    setDb(dev, i, SS_LO + pos * (SS_HI - SS_LO))
  }
  // relative encoder (E16): steps = +-n, 0.5 dB each
  S.turnRel = function (dev, i, steps) {
    var s = S.st[i]
    if (i === 7 && fallback()) {
      if (s.held) s.turned++
      var vdb = S.volDb === null ? -200 : S.volDb
      var nd = (vdb <= -100 ? (steps > 0 ? -60 : -200) : vdb + steps * 0.5)
      if (nd > 6) nd = 6
      if (nd < -60 && steps < 0) nd = -200
      var nv = ssNorm('vol', nd)
      S.vol.setProcessValue(dev, nv); S.volNorm = nv; S.volDb = nd; show(dev, 7)
      return
    }
    if (!s.has) return
    if (s.held) { prePostStep(dev, i, steps); return }
    var db = s.db === null || s.db < SS_LO ? SS_LO : Math.min(SS_HI, s.db)
    setDb(dev, i, db + steps * 0.5)
  }
  S.press = function (dev, i) { var s = S.st[i]; s.held = true; s.turned = 0; s.acc = 0 }
  S.release = function (dev, i) {
    var s = S.st[i]
    if (!s.held) return
    s.held = false
    if (s.turned > 0) { s.pickup = true; return }      // it was hold + turn: no on/off
    if (i === 7 && fallback()) { S.solo.setProcessValue(dev, S.soloOn ? 0 : 1); S.soloOn = !S.soloOn; show(dev, 7); return }
    if (!s.has) return
    s.on = !s.on
    S.on[i].setProcessValue(dev, s.on ? 1 : 0)
    show(dev, i)
  }
  S.trackChanged = function () { for (var k = 0; k < 8; k++) { S.st[k].pickup = false; S.st[k].held = false } }
  S.refresh = function (dev) { for (var k = 0; k < 8; k++) show(dev, k) }
  return S
}
//@@END SENDSTRIP@@

//@@PLUGCTL@@ (shared by serena_MFTView.js and serena_E16DAWLink.js - edit common_mr/plugctl.js, then sync)
// Plugin control through DirectAccess (MIDI Remote API 1.2+, Nuendo / Cubase 13 or newer): the same
// layers and gestures as Reaper_MultiEQ.lua, for the plugins of the SELECTED track (insert plan
// Insert 5-9, any slot works) and the Stereo Out as a stand-in.
//   Layers: 1 MultiEQ (with DirectionalCompressor + MultiEQ + OmniCompressor all there: the top row is
//   the DirectionalCompressor), 2 Omni, 3 Directional, 4 Hall (IEM FDN Reverb + mcfx convolver).
//   On every layer: 8 = OmniCompressor (press = bypass, hold + let go = next layer), 15 press = solo,
//   press + turn = SceneRotator yaw, 16 turn = track, press + turn = Stereo Out volume, press = mute.
// Plugins are found by name (object title), parameters by their titles; nothing else is touched.
// NOT TESTED IN NUENDO: API names checked against midiremote_api_v1.d.ts, logic against a mock.
var PC_HOLD = 450, PC_TAP = 350, PC_SETTLE = 80, PC_SCAN = 1000   // ms
var PC_FINE = 1 / 400                 // share of a knob per slow step (compressors, hall; EQ without API 1.3)
var PC_FINE_OCT = 1 / 96, PC_FINE_DB = 0.1, PC_FINE_Q = 1 / 24
var PC_ACCEL = [[2, 1], [4, 2], [7, 4], [12, 8], [1e9, 16]]
var PC_LAYERS = ['MultiEQ', 'Omni', 'Directional', 'Hall', 'Hall-EQ']   // 5 = the MultiEQ sitting right before the FDN
var PC_MASTER_DB = [-30, 0]
var PC_RING_DB = 18
// IEM colours (measured from the plugins' GUIs): each device maps these keys to its own colour codes
var PC_HEX = { cyan: '#00CAFE', green: '#50FE03', orange: '#FE9F01', red: '#CF021C', white: '#D9D9D9',
  eq1: '#5E9EA0', eq2: '#9370DB', eq3: '#6495ED', eq4: '#ADFF2F', eq5: '#FFFF00', eq6: '#FF4500',
  conv: '#6495ED', solo: '#FFFF00', mute: '#FF4500', master: '#02FFFF' }
var PC_KEYCOL = { thr: 'orange', knee: 'orange', mk: 'green', gain: 'green', ratio: 'red', att: 'cyan', rel: 'cyan',
  look: 'cyan', az: 'cyan', el: 'green', w: 'orange', pre: 'green', en: 'white', drv: 'white', apply: 'white',
  listen: 'white', size: 'green', rt: 'white', fade: 'white', mix: 'orange', lf: 'red', lg: 'red', hf: 'cyan',
  hg: 'cyan', yaw: 'cyan', preset: 'white' }
function pcColKey(kind, key) {
  if (kind === 'conv') return key === 'preset' ? 'white' : 'conv'
  return PC_KEYCOL[key] || 'white'
}

function pcNum(s) {
  var m = /[-+]?[0-9]+([.,][0-9]+)?/.exec(String(s === undefined || s === null ? '' : s))
  return m ? parseFloat(m[0].replace(',', '.')) : null
}
function pcReal(s) {                  // "1.20 kHz" -> 1200
  var v = pcNum(s)
  if (v !== null && /[0-9.,]\s*k(hz)?\b/i.test(String(s))) v *= 1000
  return v
}
function pcDec(s) { var m = /[0-9][.,]([0-9]+)/.exec(String(s || '')); return m ? m[1].length : 0 }
function pcClamp(v, a, b) { return v < a ? a : v > b ? b : v }
function pcWhole(f) { return Math.abs(f - Math.round(f)) < 0.05 }
function pcHz(f) {
  if (f === null || f === undefined) return '-'
  if (f < 1000 && pcWhole(f)) return Math.round(f) + ' Hz'
  if (f >= 1000) return (f / 1000).toFixed(2) + ' kHz'
  return f.toFixed(1) + ' Hz'
}
function pcHz4(f) {
  if (f === null || f === undefined) return '--'
  if (f >= 9950) return Math.round(f / 1000) + 'k'
  if (f >= 1000) return (f / 1000).toFixed(1) + 'k'
  if (f >= 100 || pcWhole(f)) return String(Math.round(f))
  return f.toFixed(1)
}
function pcDb(g) { return g === null || g === undefined ? '-' : (g >= 0 ? '+' : '') + g.toFixed(1) }
function pcQ(v) { return v === null || v === undefined ? '-' : v >= 10 ? v.toFixed(0) : v >= 1 ? v.toFixed(1) : v.toFixed(2) }
function pc4(v, s) {
  if (v === null || v === undefined) return String(s || '').substr(0, 4)
  var a = Math.abs(v)
  if (a >= 999.5) return Math.round(v / 1000) + 'k'
  if (a >= 99.5 || pcWhole(v)) return String(Math.round(v))
  if (a >= 9.95) return v.toFixed(0)
  return v.toFixed(1)
}

// plugin kinds: name pattern + parameter patterns (first matching pattern wins per parameter)
var PC_KINDS = {
  eq: { name: /multi\s*eq/i },
  omni: { name: /omni\s*comp/i, pat: [['look', /look/], ['thr', /thresh/], ['knee', /knee/], ['att', /attack/],
    ['rel', /release/], ['ratio', /ratio/], ['gain', /gain/], ['byp', /^bypass$/]] },
  dir: { name: /directional\s*comp/i, pat: [['en', /enabl/], ['drv', /driv/], ['apply', /apply/], ['thr', /thresh/],
    ['knee', /knee/], ['att', /attack/], ['rel', /release/], ['ratio', /ratio/], ['mk', /make/], ['pre', /pre|input/],
    ['az', /azimuth/], ['el', /elevation/], ['w', /width/], ['listen', /listen/]] },
  fdn: { name: /fdn\s*reverb/i, pat: [['preset', /^(program|preset)/], ['fade', /fade/], ['mix', /dry|wet|mix/], ['hg', /high.*gain/], ['lg', /low.*gain/],
    ['hf', /high.*(freq|cut)/], ['lf', /low.*(freq|cut)/], ['size', /room|size|delay/], ['rt', /reverb|rt60|time/]] },
  conv: { name: /convol/i },
  rot: { name: /scene\s*rotator|ambi\s*decoder/i, pat: [['yaw', /yaw/]] },
}
function pcEqKind(n) {
  if (/freq/.test(n)) return 'f'
  if (/gain/.test(n)) return 'g'
  if (/type/.test(n)) return 't'
  if (/enabl|active|on\/off/.test(n)) return 'e'
  if (/(^|[^a-z])q([^a-z]|$)/.test(n) || /quality/.test(n)) return 'q'
  return null
}

// ui: { devices: ['mft'] or ['e16'], render(dev, devKey, e, o), title(dev, devKey, L, text),
//       layer(dev, devKey, L), flash(dev, devKey, e, full, v4), action(dev, devKey, name) }
function makePlugCtl(ui) {
  var P = { M: null, ok: false, insts: { eq: [], omni: [], dir: [], fdn: [], conv: [], rot: [], feq: [] },
            layer: {}, e16Page: 1, e16Comp: 2, e16Hall: 4, G: {}, queue: [], lastScan: -1e9, dirty: true,
            sel: { mute: 0, solo: 0, name: '' }, master: { norm: -1, text: '' }, pages: [], cur: null, cache: {} }
  for (var d = 0; d < ui.devices.length; d++) { P.layer[ui.devices[d]] = 1; P.G[ui.devices[d]] = {} }
  var locks = {}

  // --- per page: DirectAccess on the selected track and on the Stereo Out, track values ----------
  // prev: the script's own handlers { activate, deactivate, idle, title } - Nuendo throws
  // "DukValue is uninitialized" when a script READS an mOn... callback, so they are passed in, never read.
  P.addPage = function (page, prev) {
    prev = prev || {}
    var hs = page.mHostAccess
    var pg = { page: page, da: null, daOut: null }
    var selCh = hs.mTrackSelection.mMixerChannel
    var outZone = hs.mMixConsole.makeMixerBankZone('pc out').includeOutputChannels()
    var outCh = outZone.makeMixerBankChannel()
    if (hs.makeDirectAccess) {
      pg.da = hs.makeDirectAccess(selCh)
      pg.daOut = hs.makeDirectAccess(outCh)
      P.ok = true
    }
    pg.next = hs.mTrackSelection.mAction.mNextTrack
    pg.prev = hs.mTrackSelection.mAction.mPrevTrack
    function bindVar(name, host, onValue, onText) {
      var v = driver.mSurface.makeCustomValueVariable(name)
      page.makeValueBinding(v, host)
      v.mOnProcessValueChange = function (dev, value) { if (P.cur === pg) { onValue(value); P.dirty = true } }
      if (onText) v.mOnDisplayValueChange = function (dev, value, units) { if (P.cur === pg) { onText(String(value || '')); P.dirty = true } }
      return v
    }
    var tag = P.pages.length
    pg.mute = bindVar('pc mute ' + tag, selCh.mValue.mMute, function (v) { P.sel.mute = v })
    pg.solo = bindVar('pc solo ' + tag, selCh.mValue.mSolo, function (v) { P.sel.solo = v })
    pg.vol = bindVar('pc vol ' + tag, selCh.mValue.mVolume, function (v) { P.sel.vol = v }, function (t) { P.sel.volText = t })
    pg.outVol = bindVar('pc out vol ' + tag, outCh.mValue.mVolume, function (v) { P.master.norm = v },
      function (t) { P.master.text = t })
    var oldAct = prev.activate, oldDeact = prev.deactivate, oldIdle = prev.idle
    page.mOnActivate = function (dev, mapping) {
      if (pg.da) { pg.da.activate(mapping); pg.daOut.activate(mapping) }
      P.cur = pg; P.M = mapping; P.dirty = true; P.lastScan = -1e9; P.cache = {}
      if (oldAct) oldAct(dev, mapping)
    }
    page.mOnDeactivate = function (dev, mapping) {
      if (pg.da) { pg.da.deactivate(mapping); pg.daOut.deactivate(mapping) }
      if (P.cur === pg) P.cur = null
      if (oldDeact) oldDeact(dev, mapping)
    }
    page.mOnIdle = function (dev, mapping) {
      if (P.cur === pg) { P.M = mapping; P.idle(dev) }
      if (oldIdle) oldIdle(dev, mapping)
    }
    selCh.mOnTitleChange = function (dev, mapping, title) {
      if (P.cur === pg) { P.sel.name = String(title || ''); P.lastScan = -1e9; P.dirty = true }
      if (prev.title) prev.title(dev, mapping, title)
    }
    P.pages.push(pg)
    return pg
  }

  // --- finding plugins ---------------------------------------------------------------------------
  function collect(da, isMaster, where, out) {
    var M = P.M
    var root = da.getBaseObjectID(M)
    if (root === undefined || root < 0) return
    var found = []
    function visit(id, depth, chain) {
      var title = String(da.getObjectTitle(M, id) || '')
      var hit = null
      for (var k in PC_KINDS) if (PC_KINDS[k].name.test(title)) { hit = k; break }
      if (hit && da.getNumberOfParameters(M, id) > 0) {
        for (var f = found.length - 1; f >= 0; f--) if (chain.indexOf(found[f].id) >= 0) found.splice(f, 1)   // keep the innermost
        found.push({ kind: hit, id: id, title: title, chain: chain.slice() })
      }
      if (depth >= 6) return
      var n = da.getNumberOfChildObjects(M, id)
      for (var c = 0; c < n; c++) visit(da.getChildObjectID(M, id, c), depth + 1, chain.concat([id]))
    }
    visit(root, 0, [])
    for (var i = 1; i < found.length; i++)      // the MultiEQ in the slot right before an FDN is the reverb's own EQ (Hall-EQ)
      if (found[i].kind === 'fdn' && found[i - 1].kind === 'eq') found[i - 1].kind = 'feq'
    for (var i = 0; i < found.length; i++) {
      var f = found[i]
      out[f.kind].push({ da: da, id: f.id, title: f.title, master: isMaster, where: where, kind: f.kind,
        uid: String((da.getObjectUniqueIDString && da.getObjectUniqueIDString(M, f.id)) || f.id), parent: f.chain[f.chain.length - 1] })
    }
  }
  function mapParams(q) {
    var M = P.M, da = q.da
    q.P = {}
    var n = da.getNumberOfParameters(M, q.id)
    var conv = 0
    for (var i = 0; i < n; i++) {
      var tag = da.getParameterTagByIndex(M, q.id, i)
      var t = String(da.getParameterTitle(M, q.id, tag, 128) || '').toLowerCase().replace(/^\s+|\s+$/g, '')
      var k = null
      if (q.kind === 'eq' || q.kind === 'feq') k = pcEqKind(t)
      else if (q.kind === 'conv') {
        if (/^(program|preset)/.test(t)) k = 'preset'
        else if (!/bypass/.test(t) && conv < 5) { conv++; k = 'c' + conv; q.names = q.names || {}; q.names[k] = t }
      }
      else {
        var pat = PC_KINDS[q.kind].pat
        for (var j = 0; j < pat.length; j++) if (pat[j][1].test(t)) { k = pat[j][0]; break }
      }
      if (/^bypass$/.test(t)) q.byp = tag
      if (k) { (q.P[k] = q.P[k] || []).push(tag) }
    }
    if (q.byp === undefined && q.parent !== undefined) {          // bypass may sit on the slot object
      var np = da.getNumberOfParameters(M, q.parent)
      for (var b = 0; b < np; b++) {
        var tg = da.getParameterTagByIndex(M, q.parent, b)
        if (/bypass/i.test(String(da.getParameterTitle(M, q.parent, tg, 64) || ''))) { q.byp = tg; q.bypOn = q.parent; break }
      }
    }
  }
  P.scan = function () {
    var pg = P.cur
    if (!pg || !pg.da || !P.M) return
    var sel = { eq: [], omni: [], dir: [], fdn: [], conv: [], rot: [], feq: [] }, out = { eq: [], omni: [], dir: [], fdn: [], conv: [], rot: [], feq: [] }
    collect(pg.da, false, P.sel.name || 'Spur', sel)
    collect(pg.daOut, true, 'Out', out)
    var next = {
      eq: out.eq.concat(sel.eq).slice(0, 2),            // like Reaper: the master's first (room correction)
      omni: sel.omni.concat(out.omni).slice(0, 2),
      dir: sel.dir.concat(out.dir).slice(0, 1),
      fdn: sel.fdn.concat(out.fdn).slice(0, 1),
      conv: sel.conv.concat(out.conv).slice(0, 1),
      rot: sel.rot.concat(out.rot).slice(0, 1),
      feq: sel.feq.concat(out.feq).slice(0, 1),
    }
    var changed = false
    for (var k in next) {
      var a = next[k], b = P.insts[k]
      var ka = a.map(function (q) { return q.uid }).join(';'), kb = b.map(function (q) { return q.uid }).join(';')
      if (ka !== kb) { changed = true; for (var i = 0; i < a.length; i++) mapParams(a[i]); P.insts[k] = a }
      else for (var j = 0; j < a.length; j++) { b[j].id = a[j].id; b[j].da = a[j].da; b[j].where = a[j].where }
    }
    if (!P.insts.feq.length) { P.e16Hall = 4; for (var dk in P.layer) if (P.layer[dk] === 5) P.layer[dk] = 1 }
    if (changed) { P.build(); P.cache = {}; P.describe() }
  }
  P.describe = function () {
    var names = { eq: 'MultiEQ', omni: 'OmniComp', dir: 'DirComp', fdn: 'FDN Reverb', conv: 'Convolver', rot: 'Rotation', feq: 'Hall-EQ' }
    for (var k in names) {
      var l = P.insts[k]
      for (var i = 0; i < l.length; i++) {
        var parts = []
        for (var pk in l[i].P) parts.push(pk + ' ' + l[i].P[pk].length)
        pcLog(names[k] + ' ' + String.fromCharCode(65 + i) + ' = ' + l[i].title + ' auf ' + l[i].where + (l[i].master ? ' (Ersatz vom Out)' : '') + ' · ' + parts.sort().join(', '))
      }
    }
  }

  // --- values ------------------------------------------------------------------------------------
  function norm(q, tag) { return q.da.getParameterProcessValue(P.M, q.id, tag) }
  function setNorm(q, tag, v) { q.da.setParameterProcessValue(P.M, q.id, tag, pcClamp(v, 0, 1)) }
  function text(q, tag) {
    var u = q.da.getParameterDisplayUnits ? q.da.getParameterDisplayUnits(P.M, q.id, tag) : ''
    return String(q.da.getParameterDisplayValue(P.M, q.id, tag) || '') + (u ? ' ' + u : '')
  }
  function plainRaw(q, tag, n) {
    if (!q.da.convertParameterProcessValueToPlain) return null
    var v = q.da.convertParameterProcessValueToPlain(P.M, q.id, tag, n)
    return (typeof v === 'number' && isFinite(v)) ? v : null
  }
  // Nuendo hands back the normalized value as "plain" for plugins without units (IEM): then the
  // conversion is useless and the display text is the real value
  function realScale(q, tag) {
    q.rs = q.rs || {}
    if (q.rs[tag] === undefined) {
      var a = plainRaw(q, tag, 0), b = plainRaw(q, tag, 1), c = plainRaw(q, tag, 0.5)
      q.rs[tag] = a !== null && b !== null && !(Math.abs(a) < 1e-9 && Math.abs(b - 1) < 1e-9 && Math.abs(c - 0.5) < 1e-6)
    }
    return q.rs[tag]
  }
  function plain(q, tag, n) { return realScale(q, tag) ? plainRaw(q, tag, n) : null }
  function cur(q, tag) {
    var p = plain(q, tag, norm(q, tag))
    return p !== null ? p : pcReal(text(q, tag))
  }
  // the knob itself: step, read back, step further until the plugin really moved
  function stepNorm(q, tag, d, m) {
    var n0 = norm(q, tag), t0 = text(q, tag), dn = d * m * PC_FINE
    for (var k = 1; k <= 40; k++) {
      var n = pcClamp(n0 + dn * k, 0, 1)
      setNorm(q, tag, n)
      var now1 = norm(q, tag)
      if ((Math.abs(now1 - n0) > 1e-6 && (now1 - n0) * d > 0) || text(q, tag) !== t0) return
      if (n <= 0 || n >= 1) return
    }
  }
  // EQ: in Hz / dB / Q when Nuendo can convert (API 1.3), else the knob itself
  function stepReal(q, tag, kind, d, m) {
    if (!q.da.convertParameterPlainToProcessValue || plain(q, tag, 0) === null) { stepNorm(q, tag, d, m * (kind === 'f' ? 0.5 : 1)); return }   // knob steps, read back
    var v = plain(q, tag, norm(q, tag)), lo = plain(q, tag, 0), hi = plain(q, tag, 1)
    if (lo > hi) { var tmp = lo; lo = hi; hi = tmp }
    var res = Math.pow(10, -pcDec(text(q, tag)))
    var t = kind === 'f' ? v * Math.pow(2, d * m * PC_FINE_OCT) : kind === 'q' ? v * Math.pow(2, d * m * PC_FINE_Q) : v + d * m * PC_FINE_DB
    if (Math.abs(t - v) < res) t = v + (d > 0 ? res : -res)
    setNorm(q, tag, q.da.convertParameterPlainToProcessValue(P.M, q.id, tag, pcClamp(t, lo, hi)))
  }
  // a choice parameter (program / preset list): one turn = the next / previous entry by its text
  // (the step between entries is found by doubling once, then remembered: few program loads per turn)
  function stepChoice(q, tag, dir) {
    var t0 = text(q, tag), n0 = norm(q, tag)
    q.ps = q.ps || {}
    if (q.ps[tag]) { setNorm(q, tag, pcClamp(n0 + dir * q.ps[tag], 0, 1)); return }
    for (var dn = 1 / 1024; dn <= 1; dn *= 2) {
      var n = pcClamp(n0 + dir * dn, 0, 1)
      setNorm(q, tag, n)
      if (text(q, tag) !== t0) { q.ps[tag] = dn; return }
      if (n <= 0 || n >= 1) return
    }
  }
  function toggle(q, tag) { setNorm(q, tag, norm(q, tag) >= 0.5 ? 0 : 1) }
  function cycle(q, tag) {
    var here = text(q, tag), n = norm(q, tag), steps = []
    for (var i = 0; i <= 20; i++) {
      setNorm(q, tag, i / 20)
      var t = text(q, tag)
      if (!steps.length || steps[steps.length - 1].t !== t) steps.push({ t: t, n: i / 20 })
    }
    var nx = null
    for (var j = 0; j < steps.length; j++) if (steps[j].t === here) { nx = steps[(j + 1) % steps.length]; break }
    setNorm(q, tag, nx ? nx.n : (n >= 0.99 ? 0 : n + 0.5))
  }
  function accel(g, ticks, t) {
    g.hist = g.hist || []
    g.hist.push([t, ticks])
    var n = 0
    for (var i = g.hist.length - 1; i >= 0; i--) { if (t - g.hist[i][0] > 120) g.hist.splice(i, 1); else n += g.hist[i][1] }
    for (var a = 0; a < PC_ACCEL.length; a++) if (n <= PC_ACCEL[a][0]) return PC_ACCEL[a][1]
    return 1
  }
  function locked(inst, band, kd) { var q = P.insts[kd || 'eq'][inst - 1]; return !!(q && locks[q.uid + ':' + band]) }

  // --- layouts -----------------------------------------------------------------------------------
  function T(kind, inst, key, n, m) { return { kind: kind, inst: inst, key: key, n: n || 1, m: m || 'n' } }
  var OMNI_ROW = [['thr', 'Thr'], ['ratio', 'Rat'], ['att', 'Att'], ['rel', 'Rel'], ['knee', 'Knee'], ['gain', 'Makeup']]
  var DIR_ROW = [['thr', 'Thr', 'en', 'tog'], ['ratio', 'Rat', 'drv', 'cyc'], ['att', 'Att', 'apply', 'cyc'], ['rel', 'Rel'], ['knee', 'Knee'], ['mk', 'Mkup']]
  var DIR_TOP = [['thr', 'Thr', 'knee', 'Knee'], ['ratio', 'Rat', 'att', 'Att'], ['mk', 'Mkup', 'rel', 'Rel']]
  P.L = {}
  P.build = function () {
    var I = P.insts
    var mixed = I.dir.length > 0 && I.eq.length > 0 && I.omni.length > 0
    for (var L = 1; L <= 5; L++) {
      var t = {}
      for (var e = 1; e <= 16; e++) {
        var s = null, top = e <= 8, k = (e - 1) % 8 + 1
        if (L === 1) {
          if (top && mixed) {
            var c = e <= 4 ? 1 : 2, j = (e - 1) % 4
            var dd = DIR_TOP[j]
            if (dd) {
              s = { turn: [T('dir', 1, dd[0], c)], pturn: [T('dir', 1, dd[2], c)], label: 'C' + c + ' ' + dd[1], plabel: 'C' + c + ' ' + dd[3] }
              if (j === 0) s.tap2 = T('dir', 1, 'en', c, 'tog')
            }
          } else if (top) {
            var band = e <= 3 ? e : (e >= 5 && e <= 7) ? e - 1 : null
            if (band) s = { eq: true, inst: 1, band: band, tap2: 'eqon', tap3: 'eqlock' }
          } else if (k <= 6) s = { eq: true, inst: mixed ? 1 : 2, band: k, tap2: 'eqon', tap3: 'eqlock' }
        } else if (L === 2 && k <= 6 && e !== 16) {
          var inst = top ? 1 : 2
          s = { turn: [T('omni', inst, OMNI_ROW[k - 1][0])], label: String.fromCharCode(64 + inst) + ' ' + OMNI_ROW[k - 1][1] }
        } else if (L === 3 && k <= 6) {
          var cc = top ? 1 : 2, dr = DIR_ROW[k - 1]
          s = { turn: [T('dir', 1, dr[0], cc)], label: 'C' + cc + ' ' + dr[1] }
          if (dr[2]) s.tap2 = T('dir', 1, dr[2], cc, dr[3])
        } else if (L === 5) {
          if (top) { var hb = e <= 3 ? e : (e >= 5 && e <= 7) ? e - 1 : null; if (hb) s = { eq: true, k: 'feq', inst: 1, band: hb, tap2: 'eqon', tap3: 'eqlock' } }
        } else if (L === 4 && top) {
          var FT = [['size', 'Size'], ['rt', 'Time'], ['fade', 'Fade'], ['mix', 'Mix'], ['lf', 'LoF', 'lg', 'LoG'], ['hf', 'HiF', 'hg', 'HiG']]
          var f = FT[k - 1]
          if (f) { s = { turn: [T('fdn', 1, f[0])], label: 'FDN ' + f[1] }; if (f[2]) { s.pturn = [T('fdn', 1, f[2])]; s.plabel = 'FDN ' + f[3] } }
          else if (k === 7) s = { turn: [T('fdn', 1, 'preset', 1, 'pre')], label: 'FDN Preset' }
        } else if (L === 4 && k <= 5) {
          s = { turn: [T('conv', 1, 'c' + k)], label: 'Conv ' + k }
        } else if (L === 4 && k === 6) {
          s = { turn: [T('conv', 1, 'preset', 1, 'pre')], label: 'Conv Preset' }
        }
        t[e] = s
      }
      t[8] = { tap1: 'bypass', long: 'layer', label: 'Omni A' }
      t[15] = { tap1: 'solo', pturn: [T('rot', 1, 'yaw')], label: 'Solo', plabel: 'Yaw' }
      t[16] = { turn: 'nav', pturn: 'master', tap1: 'mute', long: 'mode', label: 'Spur' }
      P.L[L] = t
    }
    var L1 = P.L[1], L2 = P.L[2], L3 = P.L[3]
    L1[4] = { turn: [T('dir', 1, 'w')], pturn: [T('dir', 1, 'thr', 1), T('dir', 1, 'thr', 2)], hturn: [T('dir', 1, 'ratio', 1), T('dir', 1, 'ratio', 2)],
              label: 'Dir Width', plabel: 'Dir Thr 1+2', hlabel: 'Dir Ratio 1+2' }
    if (mixed) { L1[3].hturn = [T('dir', 1, 'az')]; L1[3].hlabel = 'Azim' }
    L1[8].turn = [T('omni', 1, 'thr')]; L1[8].pturn = [T('omni', 1, 'gain')]; L1[8].hturn = [T('omni', 1, 'ratio')]
    L1[8].label = 'Omni Thr'; L1[8].plabel = 'Omni Makeup'; L1[8].hlabel = 'Omni Ratio'
    // Omni layer: 6/14 = makeup (2x = look-ahead), 7 press = A look-ahead, 8 turn = A makeup
    L2[7] = { tap1: T('omni', 1, 'look', 1, 'tog'), show: T('omni', 1, 'look', 1, 'tog'), label: 'A Look' }
    L2[6].tap2 = T('omni', 1, 'look', 1, 'tog'); L2[14].tap2 = T('omni', 2, 'look', 1, 'tog')
    L2[8].turn = [T('omni', 1, 'gain')]; L2[8].label = 'A Makeup'
    L3[7] = { turn: [T('dir', 1, 'az')], pturn: [T('dir', 1, 'w')], tap2: T('dir', 1, 'listen', 1, 'cyc'), label: 'Azim', plabel: 'Width' }
    L3[8].turn = [T('dir', 1, 'pre')]; L3[8].label = 'PreGain'
    L3[15].turn = [T('dir', 1, 'el')]; L3[15].label = 'Elev'
  }
  P.build()
  function resolve(t) {
    var q = P.insts[t.kind][t.inst - 1]
    var P2 = q && q.P[t.key]
    return { q: q, tag: P2 ? P2[t.n - 1] : undefined }
  }
  P.layerOf = function (devKey) {
    if (devKey !== 'e16') return P.layer[devKey]
    if (P.e16Page === 1) return 1
    if (P.e16Page === 3) return P.e16Comp
    if (P.e16Page === 4) return P.e16Hall
    return null
  }
  function slotOf(L, e) { return L ? P.L[L][e] : null }

  // --- what a slot shows ---------------------------------------------------------------------------
  function bandInfo(inst, band, kd) {
    var q = P.insts[kd || 'eq'][inst - 1]
    if (!q) return null
    var at = function (k) { return q.P[k] ? q.P[k][band - 1] : undefined }
    return { f: at('f') !== undefined ? cur(q, at('f')) : null, g: at('g') !== undefined ? cur(q, at('g')) : null,
             q: at('q') !== undefined ? cur(q, at('q')) : null, on: at('e') === undefined || norm(q, at('e')) >= 0.5, lock: locked(inst, band, kd) }
  }
  function eqRing(b, mode) {
    if (mode === 'p') return Math.round(pcClamp(((b.g || 0) + PC_RING_DB) / (2 * PC_RING_DB), 0, 1) * 127)
    if (mode === 'h') return Math.round(pcClamp(Math.log((b.q || 1) / 0.05) / Math.log(8 / 0.05), 0, 1) * 127)
    return Math.round(pcClamp(Math.log((b.f || 20) / 20) / Math.log(1000), 0, 1) * 127)
  }
  function omniOn() {
    var q = P.insts.omni[0]
    if (!q) return 'none'
    if (q.byp === undefined) return 'on'
    var v = q.da.getParameterProcessValue(P.M, q.bypOn || q.id, q.byp)
    return v >= 0.5 ? 'byp' : 'on'
  }
  P.info = function (L, e, mode) {
    var s = slotOf(L, e)
    if (!s) return null
    var o = { ring: 0, name: '', text: '', v4: '', on: true }
    if (s.eq) {
      var b = bandInfo(s.inst, s.band, s.k)
      if (!b) return null
      o.ring = eqRing(b, mode); o.on = b.on; o.lock = b.lock; o.eq = b; o.col = 'eq' + s.band
      o.v4 = pcHz4(b.f)
      o.name = pcHz(b.f) + '\n' + (s.k === 'feq' ? 'H' : String.fromCharCode(64 + s.inst)) + s.band + (b.lock ? ' LOCK' : '') + (b.on ? '' : ' AUS')
      o.text = pcDb(b.g) + ' dB  Q ' + pcQ(b.q)
      return o
    }
    var src = (mode === 'h' && (s.hturn || s.pturn)) || (mode === 'p' && s.pturn) || s.turn || (s.show && [s.show])
    var lab = (mode === 'h' && (s.hlabel || s.plabel)) || (mode === 'p' && s.plabel) || s.label || ''
    o.col = 'white'
    if (src === 'master') {
      o.col = 'master'
      var db = pcNum(P.master.text)
      o.ring = db === null ? Math.round(Math.max(0, P.master.norm) * 127) : Math.round(pcClamp((db - PC_MASTER_DB[0]) / (PC_MASTER_DB[1] - PC_MASTER_DB[0]), 0, 1) * 127)
      o.v4 = pc4(db, P.master.text); o.name = 'Out\n' + P.master.text; o.text = 'drücken + drehen'
    } else if (src === 'nav') {
      o.ring = Math.round(pcClamp(P.sel.vol || 0, 0, 1) * 127)
      o.v4 = String(P.sel.name || '--').substr(0, 4); o.name = P.sel.name || 'keine Spur'; o.text = P.sel.volText || ''
    } else if (src) {
      var r = resolve(src[0])
      if (r.tag === undefined) o.missing = true
      else {
        var tx = text(r.q, r.tag)
        o.ring = Math.round(norm(r.q, r.tag) * 127); o.master = r.q.master; o.where = r.q.where
        o.col = pcColKey(r.q.kind, src[0].key)
        if (src[0].key === 'thr') { o.ring = 127 - o.ring; o.inv = true }   // threshold: the ring comes from the top (0 dB) down
        if (src[0].m === 'tog') { o.on = norm(r.q, r.tag) >= 0.5; tx = o.on ? 'AN' : 'AUS'; o.v4 = tx } else o.v4 = pc4(pcNum(tx), tx)
        if (r.q.kind === 'conv' && r.q.names) lab = 'Conv ' + (r.q.names[src[0].key] || '')
        o.name = tx + '\n' + lab + (r.q.master ? ' (Out)' : ''); o.text = r.q.where
        if (s.tap2 && s.tap2.key === 'en') { var re = resolve(s.tap2); if (re.tag !== undefined) o.on = norm(re.q, re.tag) >= 0.5 }
      }
    } else { o.name = s.label || ''; o.v4 = String(s.label || '').substr(0, 4).toUpperCase() }
    if (e === 8) {
      var st = omniOn()
      if (st !== 'on') o.omni = st
      if (o.omni && !src) o.v4 = st === 'byp' ? 'BYP' : '--'
      if (!src) o.name = 'Omni A ' + (st === 'byp' ? 'AUS' : st === 'none' ? 'fehlt' : 'an') + '\n' + PC_LAYERS[L - 1]
    }
    if (e === 15 || e === 16) {
      var solo = P.sel.solo > 0.5, mute = P.sel.mute > 0.5
      if (e === 15 && solo) o.blink = 'solo'; else if (e === 15 && mute) o.blink = 'mute15'; else if (e === 16 && mute) o.blink = 'mute'
      if (e === 15 && !src) { o.v4 = solo ? 'SOLO' : 'solo'; o.name = 'Solo\n' + (solo ? 'an' : 'aus') }
    }
    return o
  }

  // --- gestures ------------------------------------------------------------------------------------
  function flash(dev, devKey, e, mode, extra) {
    var L = P.layerOf(devKey), o = L ? P.info(L, e, mode) : null
    if (!o || !ui.flash) return
    var full, v4
    if (o.eq) {
      var s = slotOf(L, e), b = o.eq
      full = String.fromCharCode(64 + s.inst) + s.band + ' ' + pcHz4(b.f) + ' ' + pcDb(b.g) + ' Q' + pcQ(b.q)
      v4 = mode === 'p' ? pcDb(b.g) : mode === 'h' ? 'Q' + pcQ(b.q) : extra === 'lock' ? (b.lock ? 'LOCK' : 'FREI') : extra === 'on' ? (b.on ? ' AN' : 'AUS') : null
    } else {
      var parts = o.name.split('\n')
      full = parts.length > 1 ? parts[1].replace(/ \(Out\)$/, '') + ' ' + parts[0] : o.name
      v4 = (mode || extra) ? o.v4 : null
    }
    ui.flash(dev, devKey, e, full, v4)
  }
  function nextLayer(dev, devKey) {
    var hasH = P.insts.feq.length > 0
    if (devKey !== 'e16') { var nl = P.layer[devKey] % 5 + 1; if (nl === 5 && !hasH) nl = 1; P.layer[devKey] = nl; if (ui.layer) ui.layer(dev, devKey, P.layer[devKey]) }
    else if (P.e16Page === 4) P.e16Hall = P.e16Hall === 4 ? (hasH ? 5 : 4) : 4
    else if (P.e16Page === 3) P.e16Comp = P.e16Comp === 2 ? 3 : 2       // E16 page 3: Omni <-> Directional (page 4 = reverb)
    P.cache = {}; P.dirty = true
  }
  function act(dev, devKey, e, a, L) {
    var pg = P.cur
    if (a === 'bypass') {
      var q = P.insts.omni[0]
      if (q && q.byp !== undefined) q.da.setParameterProcessValue(P.M, q.bypOn || q.id, q.byp, omniOn() === 'byp' ? 0 : 1)
      else pcLog('OmniComp: kein Bypass-Parameter gefunden')
    } else if (a === 'solo') { if (pg) pg.solo.setProcessValue(dev, P.sel.solo > 0.5 ? 0 : 1) }
    else if (a === 'mute') { if (pg) pg.mute.setProcessValue(dev, P.sel.mute > 0.5 ? 0 : 1) }
    else if (a === 'layer') nextLayer(dev, devKey)
    else if (a === 'mode') { if (ui.action) ui.action(dev, devKey, 'mode') }
    else if (a === 'eqon' || a === 'eqlock') {
      var s = slotOf(L, e), eq = P.insts[s.k || 'eq'][s.inst - 1]
      if (!eq) return
      if (a === 'eqlock') { var key = eq.uid + ':' + s.band; locks[key] = !locks[key] }
      else { var pe = eq.P.e && eq.P.e[s.band - 1]; if (pe !== undefined) toggle(eq, pe) }
      flash(dev, devKey, e, null, a === 'eqlock' ? 'lock' : 'on')
    } else if (a && a.kind) {
      var r = resolve(a)
      if (r.tag === undefined) return
      if (a.m === 'cyc') cycle(r.q, r.tag); else toggle(r.q, r.tag)
      flash(dev, devKey, e, null, 'x')
    }
    P.dirty = true
  }
  function press(dev, devKey, e, down, t) {
    var L = P.layerOf(devKey)
    if (!L) return
    var s = slotOf(L, e), G = P.G[devKey], g = G[e] || (G[e] = {})
    if (down) { g.down = true; g.t0 = t; g.mode = null; g.moved = false; P.dirty = true; return }
    if (!g.down) return
    g.down = false
    var held = t - g.t0 >= PC_HOLD, moved = g.moved
    g.mode = null; P.dirty = true
    if (moved || !s) { g.taps = 0; return }
    if (held) { g.taps = 0; if (s.long) act(dev, devKey, e, s.long, L); return }
    var most = s.tap3 ? 3 : s.tap2 ? 2 : s.tap1 ? 1 : 0
    if (!most) return
    g.taps = (g.taps || 0) + 1; g.tapT = t
    if (g.taps >= most) {
      var a = g.taps === 3 ? s.tap3 : g.taps === 2 ? s.tap2 : s.tap1
      g.taps = 0
      act(dev, devKey, e, a, L)
    }
  }
  function turn(dev, devKey, e, d, t) {
    var L = P.layerOf(devKey), s = slotOf(L, e)
    if (!s || d === 0) return
    var G = P.G[devKey], g = G[e] || (G[e] = {})
    if (d > 3) d = 3; else if (d < -3) d = -3
    if (g.down && t - g.t0 < PC_SETTLE) return
    var m = accel(g, Math.abs(d), t)
    if (g.down) { g.moved = true; if (!g.mode) g.mode = (t - g.t0 >= PC_HOLD && (s.hturn || s.eq)) ? 'h' : 'p' }
    var mode = g.down ? g.mode : null
    P.dirty = true
    if (s.eq) {
      var q = P.insts[s.k || 'eq'][s.inst - 1]
      if (!q) return
      var what = mode === 'h' ? 'q' : mode === 'p' ? 'g' : 'f'
      if (what === 'f' && locked(s.inst, s.band, s.k)) { flash(dev, devKey, e, null, 'lock'); return }
      var tag = q.P[what] ? q.P[what][s.band - 1] : undefined
      if (tag === undefined) return
      stepReal(q, tag, what === 'g' ? 'db' : what, d, m)
      flash(dev, devKey, e, mode)
      return
    }
    var src = (mode === 'h' && (s.hturn || s.pturn)) || (mode === 'p' && s.pturn) || s.turn
    if (mode && !(mode === 'h' && s.hturn) && !s.pturn) src = s.turn
    if (src === 'nav') { var pg = P.cur; if (pg) (d > 0 ? pg.next : pg.prev).trigger(P.M) }
    else if (src === 'master') {
      var pg2 = P.cur, db = pcNum(P.master.text)
      if (pg2 && !((d > 0 && db !== null && db >= PC_MASTER_DB[1]) || (d < 0 && db !== null && db <= PC_MASTER_DB[0])))
        pg2.outVol.setProcessValue(dev, pcClamp(P.master.norm + d * m * 0.003, 0, 1))
    } else if (src) {
      for (var i = 0; i < src.length; i++) {
        var r = resolve(src[i])
        if (r.tag === undefined) continue
        if (src[i].m === 'tog') setNorm(r.q, r.tag, d > 0 ? 1 : 0)
        else if (src[i].m === 'pre') stepChoice(r.q, r.tag, d > 0 ? 1 : -1)
        else stepNorm(r.q, r.tag, d, m)
      }
    }
    flash(dev, devKey, e, mode, 'turn')
  }
  function timers(dev, t) {
    for (var dk in P.G) {
      var L = P.layerOf(dk)
      for (var e in P.G[dk]) {
        var g = P.G[dk][e], s = slotOf(L, +e)
        if (g.down && !g.mode && !g.moved && s && (s.hturn || s.eq || s.long) && t - g.t0 >= PC_HOLD) { g.mode = 'h'; P.dirty = true }
        if (!g.down && g.taps > 0 && t - g.tapT > PC_TAP) {
          var a = s && (g.taps === 2 ? s.tap2 : g.taps === 1 ? s.tap1 : null)
          g.taps = 0
          if (a) act(dev, dk, +e, a, L)
        }
      }
    }
  }

  // --- input (queued until a mapping is there) and the idle loop ----------------------------------
  P.turn = function (dev, devKey, e, d) { P.queue.push(['t', devKey, e, d, pcNow()]); if (P.M && P.cur) P.flush(dev) }
  P.press = function (dev, devKey, e, down) { P.queue.push(['p', devKey, e, down, pcNow()]); if (P.M && P.cur) P.flush(dev) }
  P.flush = function (dev) {
    var q = P.queue
    P.queue = []
    for (var i = 0; i < q.length; i++) {
      if (q[i][0] === 't') turn(dev, q[i][1], q[i][2], q[i][3], q[i][4])
      else press(dev, q[i][1], q[i][2], q[i][3], q[i][4])
    }
  }
  P.setE16Page = function (pgNo) { if (pgNo !== P.e16Page) { P.e16Page = pgNo; P.cache = {}; P.dirty = true } }
  P.idle = function (dev) {
    if (!P.ok || !P.cur || !P.M) return
    var t = pcNow()
    if (t - P.lastScan > PC_SCAN) { P.lastScan = t; P.scan() }
    P.flush(dev)
    timers(dev, t)
    P.render(dev)
  }
  P.render = function (dev, force) {
    for (var d = 0; d < ui.devices.length; d++) {
      var dk = ui.devices[d], L = P.layerOf(dk)
      if (!L) continue
      for (var e = 1; e <= 16; e++) {
        var g = P.G[dk][e] || {}
        var o = P.info(L, e, g.down ? g.mode : null)
        var key = dk + e
        var sig = JSON.stringify([L, o, g.down ? g.mode : null])
        if (!force && P.cache[key] === sig) continue
        P.cache[key] = sig
        ui.render(dev, dk, e, o, g.down ? g.mode : null, L)
      }
      var tt
      if (L === 1) tt = P.insts.eq.length ? 'A ' + P.insts.eq[0].where.substr(0, 5) + (P.insts.eq[1] ? ' B ' + P.insts.eq[1].where.substr(0, 5) : '') : 'kein MultiEQ'
      else if (L === 2) tt = P.insts.omni.length ? 'OMNI ' + P.insts.omni[0].where.substr(0, 6) + (P.insts.omni[1] ? '/' + P.insts.omni[1].where.substr(0, 6) : '') : 'kein OmniComp'
      else if (L === 3) tt = P.insts.dir.length ? 'DIR ' + P.insts.dir[0].where.substr(0, 10) : 'kein DirComp'
      else if (L === 5) tt = P.insts.feq.length ? 'HALL-EQ ' + P.insts.feq[0].where.substr(0, 8) : 'kein Hall-EQ'
      else tt = (P.insts.fdn.length || P.insts.conv.length) ? 'HALL ' + ((P.insts.fdn[0] || P.insts.conv[0]).where.substr(0, 10)) : 'kein Hall'
      if (force || P.cache[dk + 'title'] !== tt) { P.cache[dk + 'title'] = tt; if (ui.title) ui.title(dev, dk, L, tt) }
    }
  }
  return P
}
function pcNow() { return (typeof Date !== 'undefined') ? Date.now() : 0 }
function pcLog(t) { try { console.log('[seren.a Plugins] ' + t) } catch (e) {} }
//@@END PLUGCTL@@

// --- bank 4, Plugins mode: Twister rings / colours / animation + the Twister View --------------
var MFT_COL = { master: 25, lock: 113, solo: 64, mute15: 69, mute: 81, mastervol: 81 }
// IEM colours on the Twister's classic colour map (hue wheel: 1 blue, 25 cyan, 45 green, 64 yellow,
// 69 orange, 81 red, 100 magenta, 113 violet); white = 127 (the colour set in the Utility)
var TW_KEY = { cyan: 20, green: 51, orange: 68, red: 83, white: 127, eq1: 25, eq2: 118, eq3: 9, eq4: 56, eq5: 64,
  eq6: 75, conv: 9, master: 25 }
function rgb7(hex) { var n = parseInt(String(hex).slice(1), 16); return [(n >> 17) & 127, (n >> 9) & 127, (n >> 1) & 127] }
var LAYER_COL = [127, 45, 100, 13, 92]      // encoder 8: MultiEQ, Omni, Directional, Hall, Hall-EQ
var b4Sent = {}
function b4out(dev, ch, cc, v) {
  var k = ch * 128 + cc
  if (b4Sent[k] === v) return
  b4Sent[k] = v
  twister(dev, [0xB0 + ch, cc, v])
}
function renderTwister(dev, devKey, e, o, mode, L) {
  if (b4mode !== 'plug') return
  var enc = ENC[SB + e - 1], cc = enc[1]
  var ring = 0, col = 127, rgb = 0, ind = 95, name = '', text = ''
  if (o && !o.missing) {
    ring = o.ring; name = o.name; text = o.text
    col = o.lock ? MFT_COL.lock : o.master ? MFT_COL.master : (TW_KEY[o.col] || 127)
    ind = o.on ? 95 : 70
    rgb = mode === 'h' ? 11 : (!o.on ? 19 : 0)
  } else { col = LAYER_COL[L - 1]; rgb = 19 }
  if (e === 8) { col = LAYER_COL[L - 1]; if (o && o.omni && rgb === 0) rgb = 19 }
  if (o && o.blink) { col = MFT_COL[o.blink]; rgb = 3; if (e === 15 && ring === 0) ring = 127 }
  if (e === 16 && mode) { col = MFT_COL.mastervol; rgb = 22 }
  b4out(dev, enc[0], cc, ring)
  b4out(dev, 1, cc, col)
  b4out(dev, 2, cc, rgb)
  b4out(dev, 5, cc, ind)
  sysex(dev, [1, 3, e - 1], name)
  sysex(dev, [2, 3, e - 1], text)
  var hx = o && o.blink ? PC_HEX[o.blink === 'solo' ? 'solo' : 'mute'] : PC_HEX[(o && !o.missing && o.col) || 'white']
  var c3 = rgb7(hx)
  viewColor(dev, e - 1, c3)
  viewOut.sendMidi(dev, [0xB0 + enc[0], cc, ring])
}
var viewCol = {}
function viewColor(dev, slot, c3) {               // SysEx 8: bar colour <bank> <slot> <r> <g> <b> (0-127)
  var k = c3.join(',')
  if (viewCol[slot] === k) return
  viewCol[slot] = k
  viewOut.sendMidi(dev, [0xF0, 0x7D, 0x4D, 8, 3, slot, c3[0], c3[1], c3[2], 0xF7])
}
var plug = makePlugCtl({
  devices: ['mft'],
  render: renderTwister,
  layer: function (dev, devKey, L) { if (b4mode === 'plug') sysex(dev, [6, 3], PC_LAYERS[L - 1]) },
  action: function (dev, devKey, name) { if (name === 'mode') setMode(dev, 'sends') },
})
var spSends = null, spPlug = null
function setMode(dev, m) {
  b4mode = m
  b4Sent = {}
  var sp = m === 'plug' ? spPlug : spSends
  if (plug.M && sp) sp.mAction.mActivate.trigger(plug.M)
  if (m === 'plug') {
    if (!plug.ok) clog('Plugins-Modus braucht Nuendo/Cubase 13 oder neuer (DirectAccess)')
    sysex(dev, [6, 3], PC_LAYERS[plug.layer.mft - 1], true)
    plug.cache = {}
    plug.render(dev, true)
  } else {
    sysex(dev, [6, 3], 'Sends/QC', true)
    viewCol = {}
    viewOut.sendMidi(dev, [0xF0, 0x7D, 0x4D, 8, 3, 127, 0xF7])   // 127 = all slots back to their own colour
    for (var e = 0; e < 16; e++) { var c = ENC[SB + e][1]; twister(dev, [0xB1, c, 127]); twister(dev, [0xB2, c, 0]); twister(dev, [0xB5, c, 95]) }
    if (strip) strip.refresh(dev)
    for (var q = 0; q < 8; q++) qcShow(dev, q)
  }
}
// QC rings + names on the Twister / view in Sends/QC mode (the QC knobs themselves are relative)
var qcState = []
function qcRing(q, host) {
  var v = driver.mSurface.makeCustomValueVariable('qc ring ' + (q + 1))
  page.makeValueBinding(v, host)
  qcState[q] = { pos: 0, name: '', text: '' }
  v.mOnProcessValueChange = function (dev, x) { qcState[q].pos = x; if (b4mode === 'sends') qcShow(dev, q) }
  v.mOnTitleChange = function (dev, objectTitle, valueTitle) { qcState[q].name = valueTitle ? valueTitle + (objectTitle ? '\n' + objectTitle : '') : ''; if (b4mode === 'sends') qcShow(dev, q) }
  v.mOnDisplayValueChange = function (dev, x, units) { qcState[q].text = withUnit(x, units); if (b4mode === 'sends') qcShow(dev, q) }
}
function qcShow(dev, q) {
  var st = qcState[q]
  if (!st) return
  var e = ENC[SB + 8 + q], p = Math.round(st.pos * 127)
  twister(dev, [0xB0 + e[0], e[1], p])
  viewOut.sendMidi(dev, [0xB0 + e[0], e[1], p])
  sysex(dev, [1, 3, 8 + q], st.name)
  sysex(dev, [2, 3, 8 + q], st.text)
}

// --- mapping ------------------------------------------------------------------------------------
var page = driver.mMapping.makePage('Twister')
var sel = page.mHostAccess.mTrackSelection
function onTrackTitle(dev, mapping, title) {
  sysex(dev, [3], title)
  if (strip) strip.trackChanged()
}
var strip = null
plug.addPage(page, { title: onTrackTitle })


if (DEFAULT_MAPPING) {
  var qcs = sel.mMixerChannel.mQuickControls
    // bank 1: Isabella's basic channel strip (from her DJ Tech Tools "Default" mapping page)
  var mc = sel.mMixerChannel, eq = mc.mChannelEQ, pf = mc.mPreFilter, val = mc.mValue
  var bands = [eq.mBand1, eq.mBand2, eq.mBand3, eq.mBand4]
  if (knobs.length >= 16) {
    for (var bq = 0; bq < 4; bq++) {
      page.makeValueBinding(knobs[bq].mSurfaceValue, bands[bq].mQ)
      page.makeValueBinding(knobs[4 + bq].mSurfaceValue, bands[bq].mGain)
      page.makeValueBinding(knobs[8 + bq].mSurfaceValue, bands[bq].mFreq)
      page.makeValueBinding(pushes[bq], bands[bq].mOn).setTypeToggle()
    }
    page.makeValueBinding(knobs[12].mSurfaceValue, pf.mLowCutFreq)
    page.makeValueBinding(knobs[13].mSurfaceValue, pf.mHighCutFreq)
    page.makeValueBinding(knobs[14].mSurfaceValue, val.mPan)
    page.makeValueBinding(knobs[15].mSurfaceValue, val.mVolume)
    page.makeCommandBinding(pushes[4], 'Editors', 'Open Drum Editor in Window')
    page.makeCommandBinding(pushes[5], 'Editors', 'Open Pattern Editor in Window')
    page.makeValueBinding(pushes[6], val.mInstrumentOpen)
    var tHost = [val.mEditorOpen, val.mAutomationRead, val.mAutomationWrite, val.mMonitorEnable,
                 val.mRecordEnable, pf.mLowCutOn, pf.mHighCutOn, val.mMute, val.mSolo]
    for (var tg = 0; tg < tHost.length; tg++) page.makeValueBinding(pushes[7 + tg], tHost[tg]).setTypeToggle()
  }
  // bank 4: rows 1-2 sends (script-driven), rows 3-4 track quick controls - only in Sends/QC mode
  var b4Area = page.makeSubPageArea('Bank 4')
  spSends = b4Area.makeSubPage('Sends/QC'); spPlug = b4Area.makeSubPage('Plugins')
  for (var q = 0; q < 8 && SB + 8 + q < knobs.length; q++) {
    page.makeValueBinding(knobs[SB + 8 + q].mSurfaceValue, qcs.getByIndex(q)).setSubPage(spSends)
    qcRing(q, qcs.getByIndex(q))
  }
  if (knobs.length >= SB + 8) {
    strip = makeSendStrip(page, sel.mMixerChannel, 'tw', {
      title: function (dev, i, name, label) { if (b4mode === 'sends') sysex(dev, [1, 3, i], name ? name + '\n' + label : (label ? label : '')) },
      value: function (dev, i, text) { if (b4mode === 'sends') sysex(dev, [2, 3, i], text) },
      ring: function (dev, i, pos) {
        var e = ENC[SB + i]
        viewOut.sendMidi(dev, [0xB0 + e[0], e[1], pos < 0 ? 0 : Math.round(pos * 127)])
        if (b4mode === 'sends') twister(dev, [0xB0 + e[0], e[1], pos < 0 ? 0 : Math.round(pos * 127)])
      },
    })
    for (var si = 0; si < 16; si++) { b4Steps(si); b4Push(si) }
  }
  if (knobs.length >= 32) {
    var slots = [SLOT_A, SLOT_B]
    for (var v = 0; v < 2; v++) {
      var viewer = sel.mMixerChannel.mInsertAndStripEffects.makeInsertEffectViewer('Slot ' + (v + 1))
      if (viewer.accessSlotAtIndex) viewer = viewer.accessSlotAtIndex(slots[v])
      var zone = viewer.mParameterBankZone
      for (var p = 0; p < 8; p++) {
        page.makeValueBinding(knobs[16 + v * 8 + p].mSurfaceValue, zone.makeParameterValue())
      }
    }
  }
}
