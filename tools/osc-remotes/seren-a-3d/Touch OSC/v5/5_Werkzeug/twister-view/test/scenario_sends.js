// Bank 4 send strip of serena_MFTView.js: what gets written to Nuendo, and when.
const { load } = require('./mrmock')
const m = load(process.argv[2])
const dev = {}, mapping = {}
const page = m.pages[0]
const out = []
let s0 = 0, m0 = 0
const mark = (tag) => { out.push({ tag, sets: m.log.sets.slice(s0), midi: m.log.midi.slice(m0).map(x => x.msg) }); s0 = m.log.sets.length; m0 = m.log.midi.length }
const sv = (l) => m.sv(l)
m.driver.mOnActivate(dev); mark('activate')
page.mixer.mOnTitleChange(dev, mapping, 'Vox Lead')
const slots = page.mixer.__slots
const names = ['FX 1-Reverb', 'FX 2-Delay', 'FX 3-Hall', '', '', '', '', '']
names.forEach((n, i) => slots[i].mOnTitleChange(dev, mapping, n))
// Nuendo reports the current values (this is all "Nuendo -> script": nothing may be written)
sv('custom:twsend1Level').mOnProcessValueChange(dev, 0.62, 0); sv('custom:twsend1Level').mOnDisplayValueChange(dev, '-6.00', 'dB')
sv('custom:twsend1On').mOnProcessValueChange(dev, 1, 0)
sv('custom:twsend2Level').mOnProcessValueChange(dev, 0.40, 0); sv('custom:twsend2Level').mOnDisplayValueChange(dev, '-20.0', 'dB')
sv('custom:twsend2On').mOnProcessValueChange(dev, 1, 0)
sv('custom:twVolume').mOnProcessValueChange(dev, 0.785, 0); sv('custom:twVolume').mOnDisplayValueChange(dev, '0.00', 'dB')
mark('feedback')
// bank 4 is relative now: every turn is a step counter (64 +- n), every push a CC 127 / 0
const step = (n, d) => sv('custom:b4 steps ' + n).mOnProcessValueChange(dev, 0.5 + d / 128, 0)
const push = (n, v) => sv('push' + (47 + n)).mOnProcessValueChange(dev, v, 0)
step(1, 2); mark('turn1')                 // -6 dB + 2 steps of 0.5 dB = -5 dB
step(1, -30); mark('turn1b')              // -5 - 15 = -20 dB -> learned point of send 2
push(1, 1); push(1, 0); mark('push1')
push(2, 1)
step(2, 1); step(2, 1); step(2, 1); mark('holdturn')
push(2, 0); mark('holdrelease')
step(4, 3); push(4, 1); push(4, 0); mark('nosend')
step(8, 2); mark('vol')                   // no 8th send: volume +1 dB
push(8, 1); push(8, 0); mark('solo')
slots[7].mOnTitleChange(dev, mapping, 'FX 8-Cue'); mark('send8')
step(8, -4); mark('send8turn')
page.mixer.mOnTitleChange(dev, mapping, 'Bass'); mark('track')
console.log(JSON.stringify({ out, valueBindings: m.log.valueBindings, bindings: m.log.bindings }))
