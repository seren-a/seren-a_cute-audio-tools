// Minimal functional mock of the MIDI Remote API (only what the two scripts use), strict:
// reading a member the mock doesn't define throws, so typos and wrong chains fail loudly.
'use strict'
const fs = require('fs')
const vm = require('vm')
const CONSOLE = []

function strict(obj, name) {
  return new Proxy(obj, {
    get(t, k) {
      if (typeof k === 'symbol' || k in t) return t[k]
      if (/^mOn[A-Z]/.test(k)) return undefined            // callbacks: unset until assigned
      throw new Error('mock: ' + name + ' has no member ' + String(k))
    },
  })
}

function load(scriptPath) {
  const log = { surface: {}, midi: [], bindings: [], valueBindings: [], actionBindings: [], detection: [], pages: [] }
  let clock = 1e6
  const action = (name) => strict({ __action: name, trigger(m) { (log.triggered = log.triggered || []).push(name) } }, 'action ' + name)

  function surfaceValue(label) {
    const sv = { __label: label }
    const binding = { port: {} }
    const chain = (desc) => {
      binding.desc = desc
      log.bindings.push({ label, ...binding })
      return strict({
        setTypeRelativeBinaryOffset() { binding.relative = 'binaryOffset'; log.bindings[log.bindings.length - 1].relative = 'binaryOffset'; return this },
        setTypeAbsolute() { return this },
      }, 'midibinding')
    }
    sv.setProcessValue = function (dev, v) { (log.setValues = log.setValues || []).push({ label, v }); sv.__v = v }
    sv.getProcessValue = function () { return sv.__v || 0 }
    sv.mMidiBinding = strict({
      setInputPort(p) { binding.port.in = p.__name; return this },
      setOutputPort(p) { binding.port.out = p.__name; return this },
      bindToControlChange(ch, cc) { return chain({ type: 'cc', ch, cc }) },
      bindToControlChange14Bit(ch, cc) { return chain({ type: 'cc14', ch, cc }) },
      bindToPitchBend(ch) { return chain({ type: 'pb', ch }) },
      bindToNote(ch, note) { return chain({ type: 'note', ch, note }) },
    }, 'mMidiBinding')
    const proxy = strict(sv, 'surfaceValue ' + label)
    log.surface[label] = proxy
    return proxy
  }

  let nKnob = 0, nButton = 0
  function hostValue(desc) { return strict({ __host: desc }, 'host ' + desc) }
  function zone(desc) {
    let n = 0
    return strict({
      __desc: desc, wrap: false,
      setWrapAround(w) { this.wrap = w; return this },
      makeParameterValue() { return hostValue(desc + '.param' + (n++)) },
      mAction: strict({ mPrevBank: action(desc + '.prevBank'), mNextBank: action(desc + '.nextBank'), mResetBank: action(desc + '.resetBank') }, 'zone actions'),
    }, 'zone')
  }
  function makeViewer(name, slot) {
    const raw = { __name: name, __slot: slot }
    raw.accessSlotAtIndex = (i) => makeViewer(name, i)
    raw.followPluginWindowInFocus = () => makeViewer(name, 'focus')
    raw.mParameterBankZone = zone((String(name).startsWith('bank') ? String(name).split(':')[0] + '.' : '') + 'slot' + slot)
    raw.mBypass = hostValue('slot' + slot + '.bypass')
    raw.mOn = hostValue('slot' + slot + '.on')
    return strict(raw, 'viewer')
  }

  log.bankChannels = []
  function bankZone(zn) {
    const z = { __name: zn, includes: [] }
    for (const kind of ['Audio', 'Group', 'Instrument', 'FX', 'MIDI', 'VCA', 'Input', 'Output', 'Sampler']) {
      z['include' + kind + 'Channels'] = function () { z.includes.push(kind); return sz }
    }
    z.mAction = strict({ mPrevBank: action(zn + '.prevBank'), mNextBank: action(zn + '.nextBank'),
      mResetBank: action(zn + '.resetBank'), mShiftLeft: action(zn + '.shiftLeft'), mShiftRight: action(zn + '.shiftRight') }, 'bank actions')
    z.makeMixerBankChannel = function () {
      const i = log.bankChannels.length
      const ch = { __index: i,
        mValue: strict({ mSelected: hostValue('bank' + i + '.selected'), mPan: hostValue('bank' + i + '.pan'),
                         mVolume: hostValue('bank' + i + '.volume'), mVUMeter: hostValue('bank' + i + '.meter') }, 'channel values'),
        mInsertAndStripEffects: strict({ makeInsertEffectViewer(n) { return makeViewer('bank' + i + ':' + n, 'none') } }, 'inserts'),
        mQuickControls: strict({ getByIndex(q) { return hostValue('bank' + i + '.QC' + q) } }, 'bank QCs') }
      log.bankChannels.push(ch)
      return strict(ch, 'bank channel ' + i)
    }
    log.bankZone = z
    const sz = strict(z, 'bank zone')
    return sz
  }

  function page(name) {
    const qcs = strict({ getByIndex(i) { return hostValue('trackQC' + i) } }, 'mQuickControls')
    const fqcs = strict({ getByIndex(i) { return hostValue('focusQC' + i) } }, 'mFocusedQuickControls')
    const mixer = { mQuickControls: qcs,
      mInsertAndStripEffects: strict({ makeInsertEffectViewer(n) { return makeViewer(n, 'none') } }, 'inserts') }
    const p = {
      __name: name,
      mHostAccess: strict({
        mTrackSelection: strict({
          mMixerChannel: strict(mixer, 'mMixerChannel'),
          mAction: strict({ mPrevTrack: action('prevTrack'), mNextTrack: action('nextTrack') }, 'trackActions'),
        }, 'mTrackSelection'),
        mFocusedQuickControls: fqcs,
        mMixConsole: strict({ makeMixerBankZone(zn) { return bankZone(zn) } }, 'mMixConsole'),
      }, 'mHostAccess'),
      mAction: strict({ mActivate: action('activate ' + name) }, 'pageActions'),
      makeValueBinding(sv, hv) {
        const b = { page: name, surface: sv.__label, host: hv.__host, toggle: false }
        log.valueBindings.push(b)
        return strict({ setTypeToggle() { b.toggle = true; return this } }, 'valueBinding')
      },
      makeActionBinding(sv, a) { log.actionBindings.push({ page: name, surface: sv.__label, action: a.__action }); return {} },
      mixer,
    }
    const sp = strict(p, 'page ' + name)
    log.pages.push(p)
    return sp
  }

  const driver = {
    mPorts: strict({
      makeMidiInput(n) { const i = { __name: 'in:' + n }; (log.midiIns = log.midiIns || []).push(i); return i },
      makeMidiOutput(n) { return strict({ __name: 'out:' + n, sendMidi(dev, msg) { log.midi.push({ t: clock, msg: msg.slice() }) } }, 'out') },
    }, 'mPorts'),
    makeDetectionUnit() {
      return strict({ detectPortPair(i, o) {
        const d = { in: i.__name, out: o.__name, rules: [] }
        log.detection.push(d)
        const pp = strict({
          expectInputNameContains(s) { d.rules.push('in~' + s); return pp },
          expectOutputNameContains(s) { d.rules.push('out~' + s); return pp },
        }, 'portpair')
        return pp
      } }, 'detectionUnit')
    },
    mSurface: strict({
      makeKnob() { return strict({ mSurfaceValue: surfaceValue('knob' + (nKnob++)) }, 'knob') },
      makeButton() { return strict({ mSurfaceValue: surfaceValue('button' + (nButton++)) }, 'button') },
      makeCustomValueVariable(n) { return surfaceValue('custom:' + n) },
    }, 'mSurface'),
    mMapping: strict({ makePage: page }, 'mMapping'),
  }
  const sDriver = strict(driver, 'driver')
  const api = strict({ makeDeviceDriver() { return sDriver } }, 'api')

  const ctx = {
    require(n) { if (n !== 'midiremote_api_v1') throw new Error('require ' + n); return api },
    console: { log: (m) => { CONSOLE.push(String(m)) }, error: (m) => { CONSOLE.push('ERR ' + m) } },
    Date: { now: () => clock },
  }
  vm.createContext(ctx)
  vm.runInContext(fs.readFileSync(scriptPath, 'utf8'), ctx, { filename: scriptPath })
  return {
    log, driver, pages: log.pages,
    advance(ms) { clock += ms },
    sv(label) { return log.surface[label] },
  }
}

module.exports = { load, CONSOLE }
