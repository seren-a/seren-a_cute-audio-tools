// Drives serena_E16DAWLink.js through the mock: a timeline for the E16 Lua mock, plus what was
// written to Nuendo (sets) and which actions fired (triggers) between marks.
const { load } = require('./mrmock')
const m = load(process.argv[2])
const out = []
let sent = 0, s0 = 0, t0 = 0
const flush = () => { for (; sent < m.log.midi.length; sent++) out.push({ send: m.log.midi[sent].msg }) }
const run = (ms) => { flush(); out.push({ run: ms }); m.advance(ms) }
const snap = (n) => {
  flush()
  out.push({ snap: n, sets: m.log.sets.slice(s0).map(x => [x.label.replace('custom:', ''), x.v]).filter(x => !/^steps/.test(x[0])),
             resets: m.log.sets.slice(s0).filter(x => /steps/.test(x.label)).length, triggers: m.log.triggers.slice(t0) })
  s0 = m.log.sets.length; t0 = m.log.triggers.length
}
const dev = {}, mapping = {}
const [pS, pEQ, pIns] = m.pages
const L = m.log
out.push({ structure: { detection: L.detection, bindings: L.bindings, valueBindings: L.valueBindings,
  actionBindings: L.actionBindings, commandBindings: L.commandBindings, pages: L.pages.map(p => p.__name) } })
const sv = (l) => m.sv(l)
const push = (i, ms) => { sv('button' + i).mOnProcessValueChange(dev, 1, 0); m.advance(ms || 80); sv('button' + i).mOnProcessValueChange(dev, 0, 0) }
const steps = (i, n) => { const r = sv('custom:steps' + (i + 1)); const v = 0.5 + n / 128; r.mOnProcessValueChange(dev, v, 0); if (r.__v !== 0.5) throw new Error('no reset'); r.mOnProcessValueChange(dev, 0.5, 0) }

m.driver.mOnActivate(dev)
pS.mOnActivate(dev, mapping)
pS.mixer.mOnTitleChange(dev, mapping, 'Kick drum Ambisonics')
const slots = pS.mixer.__slots
;['FX 1-Reverb', 'FX 2-Delay', '', '', '', '', '', ''].forEach((n, i) => slots[i].mOnTitleChange(dev, mapping, n))
sv('custom:e16send1Level').mOnProcessValueChange(dev, 0.62, 0); sv('custom:e16send1Level').mOnDisplayValueChange(dev, '-6.00', 'dB')
sv('custom:e16send1On').mOnProcessValueChange(dev, 1, 0)
sv('custom:e16send2Level').mOnProcessValueChange(dev, 0.4, 0); sv('custom:e16send2Level').mOnDisplayValueChange(dev, '-20.0', 'dB')
sv('custom:e16send2On').mOnProcessValueChange(dev, 1, 0)
sv('custom:e16Volume').mOnProcessValueChange(dev, 0.785, 0); sv('custom:e16Volume').mOnDisplayValueChange(dev, '0.00', 'dB')
for (let i = 0; i < 16; i++) {                       // Nuendo also reports the plain knobs
  const k = sv('knob' + i)
  if (i === 8) { k.mOnTitleChange(dev, 'StereoEncoder', 'Azimuth Angle'); k.mOnDisplayValueChange(dev, '45.0', '°'); k.mOnProcessValueChange(dev, 0.625, 0) }
  else { k.mOnTitleChange(dev, '', ''); k.mOnDisplayValueChange(dev, '', '') }
}
run(700); snap('sends')
m.advance(1000)
steps(0, 2); run(60); snap('turned')
run(1500); snap('settled')
push(0); run(60); snap('sendOff')
sv('button1').mOnProcessValueChange(dev, 1, 0); steps(1, 1); steps(1, 1); sv('button1').mOnProcessValueChange(dev, 0, 0); run(60); snap('prepost')
steps(7, 1); run(60); snap('vol')
push(7); run(60); snap('solo')
push(13); snap('nextTrackShort')
run(1500)
// long press 16 -> EQ page. Nuendo then activates it and reports the EQ values.
push(15, 700); snap('pageKey')
pEQ.mOnActivate(dev, mapping)
const eqNames = ['Q 1', 'Q 2', 'Q 3', 'Q 4', 'Gain 1', 'Gain 2', 'Gain 3', 'Gain 4', 'Freq 1', 'Freq 2', 'Freq 3', 'Freq 4', 'Low Cut', 'High Cut', 'Pan', 'Volume']
eqNames.forEach((n, i) => { const k = sv('knob' + i); k.mOnTitleChange(dev, 'EQ', n); k.mOnProcessValueChange(dev, 0.5, 0); k.mOnDisplayValueChange(dev, '1.0', '') })
sv('custom:solo').mOnProcessValueChange(dev, 0, 0)
sv('custom:eqOn1').mOnProcessValueChange(dev, 1, 0)
run(700); snap('eqPage')
steps(0, 3); snap('eqSteps')                         // the send strip must stay silent on the EQ page
push(15); snap('eqSolo')
push(0); snap('eqBand1')
push(12); snap('eqLowCut')
push(12, 700); snap('eqPrevTrack')
push(4); snap('eqDrum')
push(15, 700); snap('eqPage2')
pIns.mOnActivate(dev, mapping)
run(700); snap('insPage')
push(7); push(0); snap('insKeys')
push(15); snap('insPage2')
pS.mOnActivate(dev, mapping)
run(700); snap('backToSends')
console.log(JSON.stringify(out))
