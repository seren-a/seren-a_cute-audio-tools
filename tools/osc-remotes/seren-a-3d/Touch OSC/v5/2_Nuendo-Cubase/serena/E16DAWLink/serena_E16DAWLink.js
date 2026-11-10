// seren.a · OXI E16 DAW Link for Cubase / Nuendo (MIDI Remote API 1.x)
// Install: <Driver Scripts Folder>/Local/serena/E16DAWLink/serena_E16DAWLink.js
//   Windows: Documents\Steinberg\<Cubase or Nuendo>\MIDI Remote\Driver Scripts
//   macOS:   ~/Documents/Steinberg/<Cubase or Nuendo>/MIDI Remote/Driver Scripts
// Then: MIDI Remote tab > Script Console > Reload Scripts. Needs dawlink.lua (v2) on the E16.
// NOT TESTED IN CUBASE/NUENDO: API names checked against midiremote_api_v1.d.ts, logic against a mock.
//
// Three pages, the same layouts as the Midi Fighter Twister script:
//   1 SENDS (= Twister bank 4): encoders 1-8 = sends 1-8 of the selected track, -40..0 dB,
//     0.5 dB per step; push = send on/off; hold push + turn = pre/post. No 8th send on the track:
//     encoder 8 = track volume, push 8 = solo. Encoders 9-16 = the track's quick controls 1-8.
//   2 EQ (= Twister bank 1): 1-4 EQ Q, 5-8 EQ gain, 9-12 EQ freq, 13 low cut, 14 high cut, 15 pan,
//     16 volume. Push: 1-4 EQ band on, 5 drum editor, 6 pattern editor, 7 instrument,
//     8 channel settings, 9 read, 10 write, 11 monitor, 12 record, 13 low cut on, 14 high cut on,
//     15 mute, 16 solo.
//   3 INSERTS: 1-8 = insert slot SLOT_A, 9-16 = slot SLOT_B (Remote Control Editor order);
//     push 1/9 = bypass A/B, 8/15 = next parameter bank of A/B.
// On every page: HOLD push 16 (0.6 s) = next page, hold 13/14 = previous/next track.
//   On SENDS and INSERTS a short press of 13/14/16 does the same (those pushes are free there).
// Switching pages writes nothing to Nuendo: the encoders are relative (no positions to jump to),
// the pushes act on release, and the script only writes in reaction to a turn or a push.
// Display: title = track name; slots = names; a changed value flashes; rings show the values.
//
// v6.1: ONE scene for everything (seren.a E16, seren-a_E16.oxie16): page 1 = DAW Link (this script's
// three pages Sends/EQ/Inserts), page 2 = MultiEQ, page 3 = compressors, page 4 = reverb (FDN + mcfx).
// v6.0: the E16 scene "MultiEQ" (E16_MultiEQ.lua / MultiEQ.oxie16, the same one Reaper uses) works
// in Nuendo too: it controls the IEM plugins of the selected track (MultiEQ, OmniCompressor,
// DirectionalCompressor, FDN Reverb + mcfx convolver, SceneRotator yaw) with the gestures of
// Reaper_MultiEQ.lua. Scene page 1 = MultiEQ, page 3 = Omni -> Directional -> Hall (hold 8).
// Just switch scenes on the E16: the script hears the scene (it announces its page every second)
// and draws it; the DAW Link scene keeps working as before. Needs Nuendo/Cubase 13+ (DirectAccess).

var midiremote_api = require('midiremote_api_v1')

var SLOT_A = 0          // insert slots, 0 = first slot
var SLOT_B = 1
var PORT_MATCH = 'E16'  // part of the E16's MIDI port names
var LONG_MS = 600       // hold this long = long press

var driver = midiremote_api.makeDeviceDriver('serena', 'E16DAWLink', 'seren.a')
try { console.log('[seren.a E16] Skript v6.1 geladen') } catch (e) {}
var midiIn = driver.mPorts.makeMidiInput('E16')
var midiOut = driver.mPorts.makeMidiOutput('E16')
driver.makeDetectionUnit().detectPortPair(midiIn, midiOut)
  .expectInputNameContains(PORT_MATCH)
  .expectOutputNameContains(PORT_MATCH)

var A = 0xB0 + 15       // bank A, MIDI channel 16: title + names
var B = 0xB0 + 13       // bank B, MIDI channel 14: values, flash title, rings

// --- surface: 16 relative encoders, 16 pushes (input only: Cubase must not echo CCs on channel 16,
//     the E16 would read them as characters) ---------------------------------------------------
// Encoders 1-8 have a second, never-bound listener (rel) for the send strip: it only counts steps.
var knobs = []
var pushes = []
var rel = []
for (var i = 0; i < 16; i++) {
  var x = (i % 4) * 2.5
  var y = Math.floor(i / 4) * 2.5
  var knob = driver.mSurface.makeKnob(x, y, 2, 2)
  var kb = knob.mSurfaceValue.mMidiBinding.setInputPort(midiIn)
  if (i < 8) kb.setIsConsuming(false)
  kb.bindToControlChange(15, 20 + i).setTypeRelativeBinaryOffset()
  var push = driver.mSurface.makeButton(x + 2, y, 0.5, 0.5)
  push.mSurfaceValue.mMidiBinding.setInputPort(midiIn).bindToControlChange(15, 40 + i)
  knobs.push(knob)
  pushes.push(push)
  if (i < 8) {
    var r = driver.mSurface.makeCustomValueVariable('steps' + (i + 1))
    r.mMidiBinding.setInputPort(midiIn).setIsConsuming(false)
      .bindToControlChange(15, 20 + i).setTypeRelativeBinaryOffset()
    rel.push(r)
  }
}

// --- text helpers (same rules as reaper_to_e16.lua) ---------------------------------------------
var MAP = { 'ä': 'a', 'ö': 'o', 'ü': 'u', 'Ä': 'A', 'Ö': 'O', 'Ü': 'U', 'ß': 's' }
function ascii(s) {
  var out = ''
  s = String(s || '')
  for (var k = 0; k < s.length; k++) {
    var ch = MAP[s.charAt(k)] || s.charAt(k)
    var c = ch.charCodeAt(0)
    if (c >= 32 && c <= 126) out += ch
  }
  return out
}

// "Azimuth Angle" -> "Azim", "Stereo Width" -> "StWi", "Band 1 Frequency" -> "Ban1"
function abbr(s) {
  var w = []
  var words = ascii(s).match(/[A-Za-z0-9]+/g) || []
  for (var k = 0; k < words.length; k++) {
    if (words[k].toLowerCase() !== 'angle') w.push(words[k])
  }
  if (w.length === 0) return ''
  if (w.length === 1) return w[0].substr(0, 4)
  if (/^[0-9]/.test(w[1])) return w[0].substr(0, 3) + w[1].substr(0, 1)
  return w[0].substr(0, 2) + w[1].substr(0, 2)
}

function fmt4(f) {
  if (Math.abs(f) < 0.05) return '0'
  var s = f.toFixed(1)
  if (s.length > 4) s = f.toFixed(0)
  if (s.length > 4) s = (f / 1000).toFixed(0) + 'k'
  return s.substr(0, 4)
}

// "45.0" + "°" -> "45.0", "1.20" + "kHz" -> "1200", "-12.3 dB" -> "-12", "Bell" -> "Bell"
function shortVal(value, units) {
  var s = String(value || '')
  var m = /[-+]?[0-9]+\.?[0-9]*/.exec(s)
  if (!m) return abbr(s)
  var f = parseFloat(m[0])
  if (/[0-9]\s*k/i.test(s) || /^k/i.test(String(units || ''))) f *= 1000
  return fmt4(f)
}

function now() { return (typeof Date !== 'undefined') ? Date.now() : 0 }

// --- sending -----------------------------------------------------------------------------------
var sent = {}
var fullNames = []
var lastTrackChange = -1e9
var active = 0          // 0 SENDS, 1 EQ, 2 INSERTS
var curMapping = null   // the active mapping, needed to trigger page/track actions

function put(dev, st, cc, v, force) {
  var key = st * 128 + cc
  if (force || sent[key] !== v) {
    sent[key] = v
    midiOut.sendMidi(dev, [st, cc, v])
  }
}

function putText(dev, st, base, text, n, force) {
  var s = ascii(text)
  for (var k = 0; k < n; k++) put(dev, st, base + k, k < s.length ? s.charCodeAt(k) : 32, force)
}

function flashTitle(dev, text) {
  if (now() - lastTrackChange < 300) return       // a track change shows the track name instead
  putText(dev, B, 0, text, 15)
  midiOut.sendMidi(dev, [B, 15, 1])
}

function ringOff(dev, idx) {
  sent[B * 128 + 80 + idx] = undefined
  midiOut.sendMidi(dev, [B, 96 + idx, 0])
}

function scriptSlot(idx) { return active === 0 && idx < 8 }   // the send strip draws these

// what Nuendo last said about each encoder; drawn unless the send strip owns the slot
var kTitle = [], kVal = [], kUnits = [], kPos = []
function drawName(dev, idx) {
  fullNames[idx] = kTitle[idx] || ''
  putText(dev, A, 16 + idx * 4, abbr(kTitle[idx]), 4)
  if (!kTitle[idx]) ringOff(dev, idx)
  else if (kPos[idx] !== undefined) put(dev, B, 80 + idx, Math.max(0, Math.min(127, Math.round(kPos[idx] * 127))))
}
function wire(idx) {
  var sv = knobs[idx].mSurfaceValue
  sv.mOnTitleChange = function (dev, objectTitle, valueTitle) {
    kTitle[idx] = valueTitle || ''
    if (!scriptSlot(idx)) drawName(dev, idx)
  }
  sv.mOnDisplayValueChange = function (dev, value, units) {
    kVal[idx] = value; kUnits[idx] = units
    if (scriptSlot(idx)) return
    // re-send even if the 4 characters didn't change: writing a value makes it flash
    putText(dev, B, 16 + idx * 4, shortVal(value, units), 4, true)
    flashTitle(dev, fullNames[idx] + ' ' + value + (units ? ' ' + units : ''))
  }
  sv.mOnProcessValueChange = function (dev, value) {
    kPos[idx] = value
    if (scriptSlot(idx)) return
    if (fullNames[idx]) put(dev, B, 80 + idx, Math.max(0, Math.min(127, Math.round(value * 127))))
  }
}
for (var j = 0; j < 16; j++) wire(j)

driver.mOnActivate = function (dev) {
  sent = {}
  midiOut.sendMidi(dev, [A, 127, 0])              // clear the E16 display
}

// --- pages ---------------------------------------------------------------------------------------
var pageSends = driver.mMapping.makePage('Sends + Quick Controls')
var pageEQ = driver.mMapping.makePage('EQ')
var pageIns = driver.mMapping.makePage('Inserts')
var pages = [pageSends, pageEQ, pageIns]
var PAGE_NAMES = ['SENDS + QC', 'EQ', 'INSERTS']
// ring colours per page (OXI App palette, IEM meaning): 83 cyan, 92 green, 57 red, 36 orange, 74 violet, 18 blue
var DL_COL = [[83, 83, 83, 83, 83, 83, 83, 92, 74, 74, 74, 74, 74, 74, 74, 74],
              [57, 57, 57, 57, 92, 92, 92, 92, 83, 83, 83, 83, 36, 36, 83, 92],
              [18, 18, 18, 18, 18, 18, 18, 18, 77, 77, 77, 77, 77, 77, 77, 77]]
var strip = null

var pageHooks = []                    // handed to plug.addPage (Nuendo can't read callbacks back)
function common(page, idx) {
  var sel = page.mHostAccess.mTrackSelection
  var hooks = pageHooks[idx] = {}
  hooks.title = sel.mMixerChannel.mOnTitleChange = function (dev, mapping, title) {
    lastTrackChange = now()
    putText(dev, A, 0, title, 15)
    if (idx === 0 && strip) strip.trackChanged()
  }
  hooks.activate = page.mOnActivate = function (dev, mapping) {
    active = idx
    curMapping = mapping
    putText(dev, B, 0, PAGE_NAMES[idx], 15)
    midiOut.sendMidi(dev, [B, 15, 1])
    for (var ci = 0; ci < 16; ci++) put(dev, A, 80 + ci, DL_COL[idx][ci])   // ring colours of this page
    if (idx === 0 && strip) strip.refresh(dev)
    else for (var k = 0; k < 8; k++) drawName(dev, k)     // slots 1-8 were the send strip's
  }
}
for (var pg = 0; pg < 3; pg++) common(pages[pg], pg)

function nextPage() { if (curMapping) pages[(active + 1) % 3].mAction.mActivate.trigger(curMapping) }
function track(dir) {
  if (!curMapping) return
  var a = pages[active].mHostAccess.mTrackSelection.mAction
  if (dir < 0) a.mPrevTrack.trigger(curMapping)
  else a.mNextTrack.trigger(curMapping)
}

// a toggle that follows Nuendo's state; the script flips it on a push (release)
function toggle(page, name, hostValue) {
  var t = { cv: driver.mSurface.makeCustomValueVariable(name), on: false }
  page.makeValueBinding(t.cv, hostValue)
  t.cv.mOnProcessValueChange = function (dev, v) { t.on = v > 0.5 }
  t.fire = function (dev) { t.on = !t.on; t.cv.setProcessValue(dev, t.on ? 1 : 0) }
  return t
}
// a key command, fired by a push (release)
function command(page, name, cat, cmd) {
  var cv = driver.mSurface.makeCustomValueVariable(name)
  page.makeCommandBinding(cv, cat, cmd)
  return { fire: function (dev) { cv.setProcessValue(dev, 1); cv.setProcessValue(dev, 0) } }
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

// page 1: sends + quick controls
var mcS = pageSends.mHostAccess.mTrackSelection.mMixerChannel
strip = makeSendStrip(pageSends, mcS, 'e16', {
  title: function (dev, i, name, label) {
    if (active !== 0) return
    fullNames[i] = name ? label + ' ' + name : ''
    putText(dev, A, 16 + i * 4, name === 'Volume' ? 'Vol' : abbr(name), 4)
    if (!name) ringOff(dev, i)
  },
  value: function (dev, i, text) {
    if (active !== 0 || !fullNames[i]) return
    var db = ssParseDb(text)
    var v = /AUS/.test(text) ? 'AUS' : (db === null ? '' : (/ pre/.test(text) ? Math.round(db) + 'p' : fmt4(db)))
    if (/SOLO/.test(text)) v = 'SOLO'
    putText(dev, B, 16 + i * 4, v, 4, true)
    flashTitle(dev, fullNames[i] + ' ' + text)
  },
  ring: function (dev, i, pos) {
    if (active !== 0) return
    if (pos < 0) ringOff(dev, i)
    else put(dev, B, 80 + i, Math.round(pos * 127))
  },
})
function wireSteps(i) {
  rel[i].mOnProcessValueChange = function (dev, v) {
    if (Math.abs(v - 0.5) < 1e-6) return                 // our own reset
    var steps = Math.round((v - 0.5) * 128)
    if (steps === 0) steps = v > 0.5 ? 1 : -1
    rel[i].setProcessValue(dev, 0.5)                     // never bound to Nuendo: only a counter
    if (active === 0) strip.turnRel(dev, i, steps)
  }
}
for (var si = 0; si < 8; si++) wireSteps(si)
var qcs = mcS.mQuickControls
for (var q = 0; q < 8; q++) pageSends.makeValueBinding(knobs[8 + q].mSurfaceValue, qcs.getByIndex(q))

// page 2: EQ / channel strip (Twister bank 1)
var mcE = pageEQ.mHostAccess.mTrackSelection.mMixerChannel
var eq = mcE.mChannelEQ, pf = mcE.mPreFilter, val = mcE.mValue
var bands = [eq.mBand1, eq.mBand2, eq.mBand3, eq.mBand4]
for (var bq = 0; bq < 4; bq++) {
  pageEQ.makeValueBinding(knobs[bq].mSurfaceValue, bands[bq].mQ)
  pageEQ.makeValueBinding(knobs[4 + bq].mSurfaceValue, bands[bq].mGain)
  pageEQ.makeValueBinding(knobs[8 + bq].mSurfaceValue, bands[bq].mFreq)
}
pageEQ.makeValueBinding(knobs[12].mSurfaceValue, pf.mLowCutFreq)
pageEQ.makeValueBinding(knobs[13].mSurfaceValue, pf.mHighCutFreq)
pageEQ.makeValueBinding(knobs[14].mSurfaceValue, val.mPan)
pageEQ.makeValueBinding(knobs[15].mSurfaceValue, val.mVolume)
var eqPush = []
for (var bo = 0; bo < 4; bo++) eqPush.push(toggle(pageEQ, 'eqOn' + (bo + 1), bands[bo].mOn))
eqPush.push(command(pageEQ, 'drumEditor', 'Editors', 'Open Drum Editor in Window'))
eqPush.push(command(pageEQ, 'patternEditor', 'Editors', 'Open Pattern Editor in Window'))
var eqHost = [['instrument', val.mInstrumentOpen], ['editor', val.mEditorOpen], ['read', val.mAutomationRead],
              ['write', val.mAutomationWrite], ['monitor', val.mMonitorEnable], ['record', val.mRecordEnable],
              ['lowCutOn', pf.mLowCutOn], ['highCutOn', pf.mHighCutOn], ['mute', val.mMute], ['solo', val.mSolo]]
for (var eh = 0; eh < eqHost.length; eh++) eqPush.push(toggle(pageEQ, eqHost[eh][0], eqHost[eh][1]))

// page 3: inserts, a fixed slot of the selected track; parameters in Remote Control Editor order
function slotViewer(page, name, index) {
  var viewer = page.mHostAccess.mTrackSelection.mMixerChannel.mInsertAndStripEffects
    .makeInsertEffectViewer(name)
  if (viewer.accessSlotAtIndex) viewer = viewer.accessSlotAtIndex(index)
  return viewer
}
var viewers = [slotViewer(pageIns, 'Slot A', SLOT_A), slotViewer(pageIns, 'Slot B', SLOT_B)]
var insPush = {}
for (var v = 0; v < 2; v++) {
  var zone = viewers[v].mParameterBankZone
  zone.setWrapAround(true)
  for (var p = 0; p < 8; p++) {
    pageIns.makeValueBinding(knobs[v * 8 + p].mSurfaceValue, zone.makeParameterValue())
  }
  insPush[v * 8] = toggle(pageIns, 'bypass' + (v ? 'B' : 'A'), viewers[v].mBypass)
  insPush[v === 0 ? 7 : 14] = { zone: zone }
}

// --- pushes: decided on release (short / long), sends on press (hold + turn) -------------------
var downAt = []
function wirePush(i) {
  pushes[i].mSurfaceValue.mOnProcessValueChange = function (dev, v) {
    var pressed = v > 0.5
    if (active === 0 && i < 8) {                     // send strip: on/off, hold + turn = pre/post
      if (pressed) strip.press(dev, i)
      else strip.release(dev, i)
      return
    }
    if (pressed) { downAt[i] = now(); return }
    if (downAt[i] === undefined) return
    var long = now() - downAt[i] >= LONG_MS
    downAt[i] = undefined
    if (i === 15 && (long || active !== 1)) { nextPage(); return }
    if ((i === 12 || i === 13) && (long || active !== 1)) { track(i === 12 ? -1 : 1); return }
    if (active === 1) { eqPush[i].fire(dev); return }
    if (active === 2 && insPush[i]) {
      if (insPush[i].zone) { if (curMapping) insPush[i].zone.mAction.mNextBank.trigger(curMapping) }
      else insPush[i].fire(dev)
    }
  }
}
for (var pp = 0; pp < 16; pp++) wirePush(pp)

// --- v6.0: E16 scene "MultiEQ" = plugin control (common_mr/plugctl.js) ----------------------------
// The scene sends on its own channels (page 1 on 13, page 3 on 12) and is drawn on 12 / 10 / 8,
// so it never collides with the DAW Link scene (16 / 14). Only drawn while the scene is on show.
var ME_IN = [[12, 1], [11, 3], [10, 4]]   // 0-based channel the scene sends on -> its page (EQ, comp, reverb)
// IEM colours on the OXI App palette (10 x 10 picker, index = row * 10 + column)
var E16_KEY = { cyan: 83, green: 92, orange: 36, red: 57, white: 34, eq1: 87, eq2: 74, eq3: 18, eq4: 40, eq5: 44,
  eq6: 56, conv: 77, master: 85 }
var ME_A = 0xB0 + 11, ME_B = 0xB0 + 9, ME_C = 0xB0 + 7
var ME_TIMEOUT = 3000                  // ms without a sign of the scene = it's not on show
var meSeen = -1e9
function meActive() { return now() - meSeen < ME_TIMEOUT }
function meForget() { for (var k in sent) { var st = Math.floor(k / 128); if (st === ME_A || st === ME_B || st === ME_C) delete sent[k] } }
function meHere(dev, pageNo) {
  var was = meActive()
  meSeen = now()
  if (pageNo !== plug.e16Page) meForget()             // the scene clears its display on a page change
  plug.setE16Page(pageNo)
  if (!was) {                          // the scene just came up: clear it and draw everything
    meForget()
    midiOut.sendMidi(dev, [ME_A, 127, 0])
    plug.cache = {}; plug.dirty = true
    if (plug.M && plug.cur) plug.render(dev, true)
  }
}
function meRing(dev, e, ring) {
  if (ring === null) { delete sent[ME_B * 128 + 79 + e]; put(dev, ME_B, 95 + e, 0) }
  else { delete sent[ME_B * 128 + 95 + e]; put(dev, ME_B, 79 + e, ring) }
}
function meRender(dev, devKey, e, o, mode, L) {
  if (!meActive()) return
  var name = '', ring = null, state = 0
  if (o && !o.missing) {
    name = o.v4; ring = o.ring
    state = (o.on ? 0 : 1) + (o.lock ? 2 : 0) + (mode === 'h' ? 4 : mode === 'p' ? 8 : 0) + (o.master ? 16 : 0)
    if (o.blink) { state = o.blink === 'solo' ? 64 : o.blink === 'mute15' ? 65 : 66; if (ring === 0) ring = 127 }
    if (e === 16 && mode) state = 67                       // Stereo Out volume: master colour
    if (e === 8 && o.omni && state < 64) state = 1
  }
  if (e === 8 && name === '') name = L === 2 ? 'OMNI' : '--'
  putText(dev, ME_A, 16 + (e - 1) * 4, name, 4)
  meRing(dev, e, ring)
  put(dev, ME_C, e, state)
  put(dev, ME_C, 16 + e, (o && !o.missing && E16_KEY[o.col] !== undefined) ? E16_KEY[o.col] : 34)   // ring colour
}
var plug = makePlugCtl({
  devices: ['e16'],
  render: meRender,
  title: function (dev, devKey, L, text) { if (meActive()) putText(dev, ME_A, 0, text, 15) },
  flash: function (dev, devKey, e, full, v4) {
    if (!meActive()) return
    putText(dev, ME_B, 0, full, 15, true)
    midiOut.sendMidi(dev, [ME_B, 15, 0])
    if (v4) putText(dev, ME_B, 16 + (e - 1) * 4, v4, 4, true)
  },
})
function meInput(ch, pageNo) {
  var ann = driver.mSurface.makeCustomValueVariable('me page ' + (ch + 1))
  ann.mMidiBinding.setInputPort(midiIn).bindToControlChange(ch, 1)
  ann.mOnProcessValueChange = function (dev, v) {
    var n = Math.round(v * 127)
    if (n === 0) return                                    // our own reset
    ann.setProcessValue(dev, 0)                            // so the next announcement fires again
    meHere(dev, n)
  }
  function wireTurn(e) {
    var t = driver.mSurface.makeCustomValueVariable('me turn ' + (ch + 1) + ' ' + e)
    t.mMidiBinding.setInputPort(midiIn).bindToControlChange(ch, 19 + e).setTypeRelativeBinaryOffset()
    t.mOnProcessValueChange = function (dev, v) {
      if (Math.abs(v - 0.5) < 1e-6) return
      var steps = Math.round((v - 0.5) * 128)
      if (steps === 0) steps = v > 0.5 ? 1 : -1
      t.setProcessValue(dev, 0.5)
      meHere(dev, pageNo)
      plug.turn(dev, 'e16', e, steps)
    }
    var p = driver.mSurface.makeCustomValueVariable('me push ' + (ch + 1) + ' ' + e)
    p.mMidiBinding.setInputPort(midiIn).bindToControlChange(ch, 39 + e)
    p.mOnProcessValueChange = function (dev, v) { meHere(dev, pageNo); plug.press(dev, 'e16', e, v > 0.5) }
  }
  for (var e = 1; e <= 16; e++) wireTurn(e)
}
for (var mi = 0; mi < ME_IN.length; mi++) meInput(ME_IN[mi][0], ME_IN[mi][1])
for (var ap = 0; ap < 3; ap++) plug.addPage(pages[ap], pageHooks[ap])
