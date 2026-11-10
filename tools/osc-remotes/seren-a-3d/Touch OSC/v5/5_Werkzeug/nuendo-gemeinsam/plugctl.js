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
