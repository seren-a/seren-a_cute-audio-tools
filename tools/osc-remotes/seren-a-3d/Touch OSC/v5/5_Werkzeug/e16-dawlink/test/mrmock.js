// Minimal functional mock of the MIDI Remote API (only what the two scripts use), strict:
// reading a member the mock doesn't define throws, so typos and wrong chains fail loudly.
'use strict'
const fs = require('fs')
const vm = require('vm')

function strict(obj, name, optional) {
  return new Proxy(obj, {
    get(t, k) {
      if (typeof k === 'symbol' || k in t) return t[k]
      if (optional && optional.includes(k)) return undefined   // feature test of a newer API
      if (/^mOn[A-Z]/.test(k)) throw new Error('DukValue is uninitialized: ' + name + '.' + k + ' read before it was set (Nuendo throws here)')
      throw new Error('mock: ' + name + ' has no member ' + String(k))
    },
  })
}

function load(scriptPath) {
  const log = { sets: [], triggers: [], surface: {}, midi: [], bindings: [], valueBindings: [], actionBindings: [], detection: [], pages: [] }
  let clock = 1e6
  const action = (name) => strict({ __action: name, trigger(mp) { (log.triggers = log.triggers || []).push(name) } }, 'action ' + name)

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
    sv.mMidiBinding = strict({
      setInputPort(p) { binding.port.in = p.__name; return this },
      setIsConsuming(c) { binding.consuming = c; return this },
      setOutputPort(p) { binding.port.out = p.__name; return this },
      bindToControlChange(ch, cc) { return chain({ type: 'cc', ch, cc }) },
      bindToControlChange14Bit(ch, cc) { return chain({ type: 'cc14', ch, cc }) },
      bindToPitchBend(ch) { return chain({ type: 'pb', ch }) },
      bindToNote(ch, note) { return chain({ type: 'note', ch, note }) },
    }, 'mMidiBinding')
    sv.__v = 0
    sv.setProcessValue = (dev, v) => { sv.__v = v; log.sets.push({ label, v: Math.round(v * 10000) / 10000 }) }
    sv.getProcessValue = () => sv.__v
    const proxy = strict(sv, 'surfaceValue ' + label)
    log.surface[label] = proxy
    return proxy
  }

  // DirectAccess: trees[key] = { title, params: [{ title, v, disp(v), units, lo, hi, conv }], children: [] }
  const trees = {}
  function makeDA(key) {
    const ids = new Map(), nodes = []
    function index() {
      ids.clear(); nodes.length = 0
      const walk = (n) => { ids.set(n, nodes.length); nodes.push(n); (n.children || []).forEach(walk) }
      if (trees[key]) walk(trees[key])
    }
    const node = (id) => { index(); const n = nodes[id]; if (!n) throw new Error('DA: no object ' + id); return n }
    const par = (id, tag) => { const n = node(id); const p = (n.params || [])[tag]; if (!p) throw new Error('DA: no tag ' + tag); return p }
    const da = {
      active: false,
      activate() { da.active = true }, deactivate() { da.active = false },
      getBaseObjectID() { index(); return nodes.length ? 0 : -1 },
      getNumberOfChildObjects(m, id) { return (node(id).children || []).length },
      getChildObjectID(m, id, i) { const c = node(id).children[i]; return ids.get(c) },
      getObjectTitle(m, id) { return node(id).title },
      getObjectUniqueIDString(m, id) { return key + ':' + (node(id).uid || node(id).title) },
      getNumberOfParameters(m, id) { return (node(id).params || []).length },
      getParameterTagByIndex(m, id, i) { return i },
      getParameterTitle(m, id, tag) { return par(id, tag).title },
      getParameterProcessValue(m, id, tag) { return par(id, tag).v },
      setParameterProcessValue(m, id, tag, v) { const p = par(id, tag); p.v = p.snap ? p.snap(v) : v; (log.daSets = log.daSets || []).push({ key, title: p.title, v: p.v }) },
      getParameterDisplayValue(m, id, tag) { const p = par(id, tag); return p.disp ? p.disp(p.v) : String(p.v) },
      getParameterDisplayUnits(m, id, tag) { return par(id, tag).units || '' },
    }
    if (!process.env.DA12) {
      da.convertParameterProcessValueToPlain = (m, id, tag, n) => { const p = par(id, tag); return p.conv ? p.conv(n) : n }
      da.convertParameterPlainToProcessValue = (m, id, tag, x) => { const p = par(id, tag); return p.inv ? p.inv(x) : x }
    }
    return strict(da, 'directAccess', ['convertParameterProcessValueToPlain', 'convertParameterPlainToProcessValue'])
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
    raw.mParameterBankZone = zone('slot' + slot)
    raw.mBypass = hostValue('slot' + slot + '.bypass')
    return strict(raw, 'viewer')
  }

  function page(name) {
    const qcs = strict({ getByIndex(i) { return hostValue('trackQC' + i) } }, 'mQuickControls')
    const fqcs = strict({ getByIndex(i) { return hostValue('focusQC' + i) } }, 'mFocusedQuickControls')
    const band = (i) => strict({ mGain: hostValue('eq' + i + '.gain'), mFreq: hostValue('eq' + i + '.freq'), mQ: hostValue('eq' + i + '.q'), mOn: hostValue('eq' + i + '.on') }, 'band')
    const vals = {}
    for (const k of ['Pan', 'Volume', 'Mute', 'Solo', 'MonitorEnable', 'RecordEnable', 'EditorOpen', 'InstrumentOpen', 'AutomationRead', 'AutomationWrite']) vals['m' + k] = hostValue('sel.' + k)
    const slots = []
    for (let i = 0; i < 8; i++) slots.push(strict({ mLevel: hostValue('send' + i + '.level'), mOn: hostValue('send' + i + '.on'), mPrePost: hostValue('send' + i + '.pre') }, 'sendslot'))
    const mixer = { mQuickControls: qcs, __slots: slots, __da: 'sel',
      mSends: strict({ getByIndex(i) { return slots[i] }, getSize() { return 8 } }, 'mSends'),
      mChannelEQ: strict({ mBand1: band(1), mBand2: band(2), mBand3: band(3), mBand4: band(4) }, 'eq'),
      mPreFilter: strict({ mLowCutFreq: hostValue('lc.freq'), mHighCutFreq: hostValue('hc.freq'), mLowCutOn: hostValue('lc.on'), mHighCutOn: hostValue('hc.on') }, 'prefilter'),
      mValue: strict(vals, 'values'),
      mInsertAndStripEffects: strict({ makeInsertEffectViewer(n) { return makeViewer(n, 'none') } }, 'inserts') }
    const p = {
      __name: name,
      mHostAccess: strict({
        mTrackSelection: strict({
          mMixerChannel: strict(mixer, 'mMixerChannel'),
          mAction: strict({ mPrevTrack: action('prevTrack'), mNextTrack: action('nextTrack') }, 'trackActions'),
        }, 'mTrackSelection'),
        mFocusedQuickControls: fqcs,
        mMixConsole: strict({ makeMixerBankZone(zn) {
          const z = { __name: zn }
          z.includeOutputChannels = () => strict(z, 'zone ' + zn)
          z.makeMixerBankChannel = () => strict({ __da: 'out', mValue: strict({ mVolume: hostValue('out.Volume') }, 'outvals') }, 'outchannel')
          return strict(z, 'zone ' + zn)
        } }, 'mMixConsole'),
        makeDirectAccess(ho) { return makeDA(ho.__da || 'sel') },
      }, 'mHostAccess'),
      mAction: strict({ mActivate: action('activate ' + name) }, 'pageActions'),
      makeSubPageArea(an) {
        return strict({ __name: an, makeSubPage(sn) { const sp = { __name: an + '/' + sn }; sp.mAction = strict({ mActivate: action('subpage ' + an + '/' + sn) }, 'subpageActions'); return strict(sp, 'subpage ' + sn) },
          mAction: strict({ mPrev: action(an + ' prev'), mNext: action(an + ' next'), mReset: action(an + ' reset') }, 'spa actions') }, 'subPageArea')
      },
      makeValueBinding(sv, hv) {
        const b = { page: name, surface: sv.__label, host: hv.__host, toggle: false }
        log.valueBindings.push(b)
        return strict({ setTypeToggle() { b.toggle = true; return this }, setSubPage(sp) { b.subPage = sp.__name; return this } }, 'valueBinding')
      },
      makeActionBinding(sv, a) { log.actionBindings.push({ page: name, surface: sv.__label, action: a.__action }); return {} },
      makeCommandBinding(sv, cat, cmd) { (log.commandBindings = log.commandBindings || []).push({ surface: sv.__label, cmd: cat + ':' + cmd }); return {} },
      mixer,
    }
    const sp = strict(p, 'page ' + name)
    log.pages.push(p)
    return sp
  }

  const driver = {
    mPorts: strict({
      makeMidiInput(n) { return { __name: 'in:' + n } },
      makeMidiOutput(n) { return strict({ __name: 'out:' + n, sendMidi(dev, msg) { log.midi.push({ t: clock, port: n, msg: msg.slice() }) } }, 'out') },
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
      makePushEncoder() { const k = nKnob++; return strict({ mEncoderValue: surfaceValue('knob' + k), mPushValue: surfaceValue('push' + k) }, 'pushEncoder') },
      makeButton() { return strict({ mSurfaceValue: surfaceValue('button' + (nButton++)) }, 'button') },
      makeCustomValueVariable(n) { return surfaceValue('custom:' + n) },
    }, 'mSurface'),
    mMapping: strict({ makePage: page }, 'mMapping'),
  }
  const sDriver = strict(driver, 'driver')
  const api = strict({ makeDeviceDriver() { return sDriver },
    mDefaults: { mAppVersion: { getVersionString: () => 'Nuendo 14.0.30' } } }, 'api')

  const ctx = {
    require(n) { if (n !== 'midiremote_api_v1') throw new Error('require ' + n); return api },
    console: { log: () => {}, error: () => {} },
    Date: { now: () => clock },
  }
  vm.createContext(ctx)
  vm.runInContext(fs.readFileSync(scriptPath, 'utf8'), ctx, { filename: scriptPath })
  return {
    log, driver, pages: log.pages, trees,
    advance(ms) { clock += ms },
    sv(label) { return log.surface[label] },
  }
}

module.exports = { load }
