// v6.0: the E16 scene "MultiEQ" in Nuendo (serena_E16DAWLink.js + plugctl) against fake IEM plugins.
// Prints a timeline for e2e_e16_plug.py (which feeds it into E16_MultiEQ.lua on the E16 mock) and
// checks what was written to the plugins / Nuendo.
'use strict'
const { load } = require('./mrmock')
const m = load(process.argv[2])
const param = require('/home/claude/mft-view/test/fakeplugins').install(m)
const dev = {}, mapping = {}
const page = m.pages[0]
let fails = 0
const check = (ok, what) => { console.error((ok ? 'PASS ' : 'FAIL ') + what); if (!ok) fails++ }
const out = []
let sent = 0, d0 = 0, s0 = 0, t0 = 0
const flush = () => { for (; sent < m.log.midi.length; sent++) out.push({ send: m.log.midi[sent].msg }) }
const run = (ms) => { flush(); out.push({ run: ms }); m.advance(ms) }
const snap = (n) => { flush(); out.push({ snap: n }) }
const since = () => { const r = { da: (m.log.daSets || []).slice(d0), sets: m.log.sets.slice(s0).filter(x => !/me |steps/.test(x.label)), trig: m.log.triggers.slice(t0) }
  d0 = (m.log.daSets || []).length; s0 = m.log.sets.length; t0 = m.log.triggers.length; return r }
const sv = (l) => m.sv(l)
const CH = { 1: 13, 3: 12, 4: 11 }                        // 1-based channel the scene sends on, per (logical) page
let pg = 1
const PHYS = { 1: 2, 3: 3, 4: 4 }                         // seren_E16: MultiEQ on page 2, comp 3, reverb 4
const announce = (p) => { flush(); out.push({ page: PHYS[p] }); pg = p; sv('custom:me page ' + CH[p]).mOnProcessValueChange(dev, p / 127, 0) }
const turn = (e, n) => sv('custom:me turn ' + CH[pg] + ' ' + e).mOnProcessValueChange(dev, 0.5 + n / 128, 0)
const push = (e, v) => sv('custom:me push ' + CH[pg] + ' ' + e).mOnProcessValueChange(dev, v, 0)
const idle = () => page.mOnIdle(dev, mapping)
const meMsgs = (from) => m.log.midi.slice(from).filter(x => [0xBB, 0xB9, 0xB7].includes(x.msg[0]))

m.driver.mOnActivate(dev)
page.mOnActivate(dev, mapping)
page.mixer.mOnTitleChange(dev, mapping, 'Vox')
sv('custom:pc out vol 0').mOnProcessValueChange(dev, 0.7, 0); sv('custom:pc out vol 0').mOnDisplayValueChange(dev, '-6.0', 'dB')
let i0 = m.log.midi.length
idle(); run(200); idle()
check(meMsgs(i0).length === 0, 'DAW-Link-Szene: nichts auf den MultiEQ-Kanälen 12/10/8')
// the scene comes up on page 1
announce(1); idle(); run(40); snap('eq')
since()
check(m.log.sets.filter(x => x.label === 'custom:me page 13').pop().v === 0, 'Seitenmeldung zurückgesetzt (die nächste kommt wieder an)')
turn(9, 1); idle(); run(40); snap('turn9')
let r = since()
check(r.da.length === 1 && r.da[0].title === 'Filter Frequency 1' && r.da[0].key === 'out', 'E16 Encoder 9: Frequenz Band 1 vom Out-MultiEQ')
push(9, 1); run(120); turn(9, 2); push(9, 0); idle(); r = since()
check(r.da.length === 1 && r.da[0].title === 'Filter Gain 1', 'E16 Encoder 9 drücken + drehen: Gain')
turn(4, 1); r = since()
check(r.da.length === 1 && r.da[0].title === 'Width of mask', 'E16 Encoder 4: Dir Width')
run(1000); announce(1); idle(); run(40)
// page 3: compressors; hold 8 = Omni -> Directional -> Hall
announce(3); idle(); run(40); snap('omni')
turn(1, 1); r = since()
check(r.da.length && r.da[0].title === 'Threshold', 'Seite 3: Omni Threshold')
push(8, 1); run(600); idle(); push(8, 0); idle(); run(40); snap('dir')
turn(1, 1); r = since()
check(r.da.length && r.da[0].title === 'Threshold C1', 'Seite 3, 8 halten: Directional')
push(8, 1); run(600); idle(); push(8, 0); idle(); run(40)
turn(1, 1); r = since()
check(r.da.length && r.da[0].title === 'Threshold', 'Seite 3, 8 nochmal halten: wieder Omni')
// page 4 = reverb
announce(4); idle(); run(40); snap('hall')
turn(1, 1); r = since()
check(r.da.length && r.da[0].title === 'Room Size', 'Seite 4: Hall (FDN Room Size)')
turn(9, -1); r = since()
check(r.da.length && r.da[0].title === 'Wet Gain', 'Seite 4, Encoder 9: Convolver')
turn(7, 1); r = since()
check(r.da.length && r.da[r.da.length - 1].title === 'Program', 'Seite 4, Encoder 7: FDN-Preset weiter')
announce(3); idle(); run(40)
// mute / solo / track
push(16, 1); run(60); push(16, 0); idle(); r = since()
check(r.sets.some(s => s.label === 'custom:pc mute 0' && s.v === 1), 'E16 16 tippen: Mute')
sv('custom:pc mute 0').mOnProcessValueChange(dev, 1, 0); idle(); run(40); snap('mute')
turn(16, 1); r = since()
check(r.trig.includes('nextTrack'), 'E16 16 drehen: nächste Spur')
// the DAW Link page encoders still work as before on their own channel
// scene gone (back to DAW Link): nothing more on 12/10/8
run(3500); i0 = m.log.midi.length
page.mixer.mOnTitleChange(dev, mapping, 'Bass'); sv('custom:pc mute 0').mOnProcessValueChange(dev, 0, 0); idle(); run(1100); idle()
check(meMsgs(i0).length === 0, 'Szene weg: nichts mehr auf 12/10/8')
announce(1); idle(); run(40); snap('back')
console.error(fails ? fails + ' FAILED' : 'ALL OK (Nuendo-Seite)')
flush()
console.log(JSON.stringify(out))
process.exit(fails ? 1 : 0)
