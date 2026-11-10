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
