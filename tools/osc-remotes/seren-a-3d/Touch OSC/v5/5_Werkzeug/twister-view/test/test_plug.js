// v6.0: bank 4 Plugins mode of serena_MFTView.js (plugctl engine) against a fake DirectAccess tree.
// node test_plug.js ../dist/serena_MFTView.js   (DA12=1 for the Nuendo 14 path without conversions)
'use strict'
const { load } = require('./mrmock')
const m = load(process.argv[2])
const dev = {}, mapping = {}
const page = m.pages[0]
let fails = 0
const check = (ok, what) => { console.log((ok ? 'PASS ' : 'FAIL ') + what); if (!ok) fails++ }
const sv = (l) => m.sv(l)
const step = (n, d) => sv('custom:b4 steps ' + n).mOnProcessValueChange(dev, 0.5 + d / 128, 0)
const push = (n, v) => sv('push' + (47 + n)).mOnProcessValueChange(dev, v, 0)
const idle = () => page.mOnIdle(dev, mapping)
const tap = (n) => { push(n, 1); m.advance(60); push(n, 0); m.advance(400); idle() }
const hold = (n, ms) => { push(n, 1); m.advance(ms); idle(); push(n, 0); idle() }
let d0 = 0, i0 = 0, t0 = 0, s0 = 0
const since = () => { const r = { da: (m.log.daSets || []).slice(d0), midi: m.log.midi.slice(i0), trig: (m.log.triggers || []).slice(t0), sets: m.log.sets.slice(s0) }
  d0 = (m.log.daSets || []).length; i0 = m.log.midi.length; t0 = (m.log.triggers || []).length; s0 = m.log.sets.length; return r }
const sysexTo = (r, a, b) => r.midi.filter(x => x.msg[0] === 0xF0 && x.msg[3] === a && x.msg[4] === b)
  .map(x => a === 6 ? { t: String.fromCharCode(...x.msg.slice(5, -1)) } : { e: x.msg[5], t: String.fromCharCode(...x.msg.slice(6, -1)) })

const param = require('./fakeplugins').install(m)

// --- start: Nuendo activates, reports the track values ---------------------------------------------
m.driver.mOnActivate(dev)
page.mOnActivate(dev, mapping)
page.mixer.mOnTitleChange(dev, mapping, 'Vox')
page.mixer.__slots[0].mOnTitleChange(dev, mapping, 'FX 1-Reverb')
sv('custom:twsend1Level').mOnProcessValueChange(dev, 0.62, 0); sv('custom:twsend1On').mOnProcessValueChange(dev, 1, 0)
sv('custom:pc out vol 0').mOnProcessValueChange(dev, 0.7, 0); sv('custom:pc out vol 0').mOnDisplayValueChange(dev, '-6.0', 'dB')
idle()
let r = since()
check(r.da.length === 0, 'Start: nichts an Plugins geschrieben')
check(r.midi.filter(x => x.port === 'Twister').length === 0 || !r.midi.some(x => x.port === 'Twister' && x.msg[0] === 0xB2), 'Start (Sends/QC): keine Plugin-Animation auf dem Twister')

// --- hold 16 -> Plugins ---------------------------------------------------------------------------
step(1, 1); r = since()
check(r.sets.some(s => s.label === 'custom:twsend1Level'), 'Sends/QC: Encoder 1 = Send 1')
push(16, 1); m.advance(300); push(16, 0); r = since()
check(!r.trig.includes('subpage Bank 4/Plugins'), 'kurz 16 drücken: bleibt Sends/QC')
push(16, 1); m.advance(700); push(16, 0); idle(); r = since()
check(r.trig.includes('subpage Bank 4/Plugins'), '16 halten: Unterseite Plugins aktiviert ' + JSON.stringify(r.trig))
check(sysexTo(r, 6, 3).some(x => x.t === 'MultiEQ'), 'Ansicht: Ebene MultiEQ')
const tw = r.midi.filter(x => x.port === 'Twister').map(x => x.msg)
check(tw.some(x => x[0] === 0xB1), 'Twister bekommt Farben')
const names = sysexTo(r, 1, 3)
const nm = e => (names.filter(x => x.e === e - 1).pop() || {}).t || ''
check(/C1 Thr/.test(nm(1)) && /C2 Thr/.test(nm(5)), 'Dir + EQ + Omni da: obere Reihe = DirectionalCompressor ' + nm(1) + ' | ' + nm(5))
check(/Dir Width/.test(nm(4)), 'Encoder 4 = Dir Width')
check(/A1/.test(nm(9)) && /40 Hz/.test(nm(9)), 'Encoder 9 = MultiEQ A Band 1 (Out zuerst, 40 Hz) ' + JSON.stringify(nm(9)))
check(/Omni Thr/.test(nm(8)), 'Encoder 8 = Omni Threshold')

// --- turns ----------------------------------------------------------------------------------------
step(1, 1); r = since()
check(r.da.length && r.da.every(x => x.title === 'Threshold C1'), 'Encoder 1 drehen: Threshold C1 ' + JSON.stringify(r.da.map(x => x.title)))
check(!r.sets.some(s => /twsend/.test(s.label)), 'Plugins-Modus: kein Send verändert')
const f1 = param('out', 'eqOut', 'Filter Frequency 1').v
step(9, 1); r = since()
check(r.da.length === 1 && r.da[0].key === 'out' && param('out', 'eqOut', 'Filter Frequency 1').v > f1, 'Encoder 9 drehen: Frequenz Band 1 vom Out-MultiEQ hoch')
push(9, 1); m.advance(120); step(9, 2); push(9, 0); r = since()
check(r.da.length === 1 && r.da[0].title === 'Filter Gain 1', 'Encoder 9 drücken + drehen: Gain ' + JSON.stringify(r.da.map(x => x.title)))
const g0 = param('out', 'eqOut', 'Filter Gain 1').v
push(9, 1); m.advance(120); step(9, 1); push(9, 0); r = since()
check(Math.abs(param('out', 'eqOut', 'Filter Gain 1').v - g0) * 75 <= 0.55, 'eine Raste Gain = höchstens 0,5 dB (keine 7,5-dB-Sprünge) ' + ((param('out', 'eqOut', 'Filter Gain 1').v - g0) * 75).toFixed(2))
const fq0 = param('out', 'eqOut', 'Filter Frequency 1').v
for (let k = 0; k < 3; k++) { step(9, 1); m.advance(200) }
r = since()
const fHz = (v) => 20 * Math.pow(1000, v)
check(fHz(param('out', 'eqOut', 'Filter Frequency 1').v) / fHz(fq0) < 1.15, `3 Rasten Frequenz = kleiner Schritt (${fHz(fq0).toFixed(0)} -> ${fHz(param('out', 'eqOut', 'Filter Frequency 1').v).toFixed(0)} Hz)`)
push(9, 1); m.advance(600); idle(); step(9, 1); push(9, 0); r = since()
check(r.da.length === 1 && r.da[0].title === 'Q 1', 'Encoder 9 halten + drehen: Q ' + JSON.stringify(r.da.map(x => x.title)))
const g1 = param('sel', 'eqTrack', 'Filter Gain 1').v
push(4, 1); m.advance(120); step(4, 1); push(4, 0); r = since()
check(r.da.map(x => x.title).join() === 'Threshold C1,Threshold C2', 'Encoder 4 drücken + drehen: Threshold C1 + C2 ' + JSON.stringify(r.da.map(x => x.title)))

// --- 8: tap = Omni bypass (on the slot), hold = next layer ------------------------------------------
tap(8); r = since()
check(r.da.length === 1 && r.da[0].title === 'Bypass' && param('sel', 'slot6omni', 'Bypass').v === 1, 'Encoder 8 tippen: Bypass am Insert-Platz der OmniComp')
tap(8); since()
hold(8, 600); r = since()
check(sysexTo(r, 6, 3).some(x => x.t === 'Omni'), 'Encoder 8 halten: Ebene Omni')
check(m.log.midi.some(x => x.port === 'Twister' && x.msg[0] === 0xB1 && x.msg[2] === 68) && r.midi.some(x => x.port === 'Twister' && x.msg[0] === 0xB1 && x.msg[2] === 20), 'IEM-Farben auf dem Twister: Threshold orange (68), Attack/Release cyan (20)')
check(r.midi.some(x => x.port === 'Twister' && x.msg[0] === 0xB0 && x.msg[2] === 127 - Math.round(0.8 * 127)), 'Threshold-Ring kommt von oben (umgekehrt: 0 dB = leer)')
step(1, 1); r = since()
check(r.da.length && r.da[0].title === 'Threshold' && r.da[0].key === 'sel', 'Omni-Ebene, Encoder 1 = Threshold')
step(8, 1); r = since()
check(r.da.length && r.da.every(x => x.title === 'MakeUp Gain'), 'Omni-Ebene, Encoder 8 drehen = Makeup ' + JSON.stringify(r.da.map(x => x.title)))
const la = param('sel', 'omni', 'LookAhead').v
tap(7); r = since()
check(param('sel', 'omni', 'LookAhead').v !== la, 'Omni-Ebene, 7 drücken = LookAhead an/aus')
step(7, 1); r = since()
check(r.da.length === 0, 'Omni-Ebene, 7 drehen tut nichts mehr')
hold(8, 600); hold(8, 600); r = since()
check(sysexTo(r, 6, 3).some(x => x.t === 'Hall'), 'zweimal weiter: Ebene Hall')
step(1, 1); r = since()
check(r.da.length && r.da[0].title === 'Room Size', 'Hall, Encoder 1 = FDN Room Size ' + JSON.stringify(r.da.map(x => x.title)))
step(6, 1); r = since()
check(r.da.length && r.da[0].title === 'Highs Cutoff Frequency', 'Hall, Encoder 6 = Highs Freq ' + JSON.stringify(r.da.map(x => x.title)))
push(5, 1); m.advance(120); step(5, -1); push(5, 0); r = since()
check(r.da.length && r.da[0].title === 'Lows Gain', 'Hall, Encoder 5 drücken + drehen = Lows Gain')
step(9, 1); r = since()
check(r.da.length && r.da[0].title === 'Wet Gain', 'Hall, Encoder 9 = Convolver Parameter 1 (ohne Bypass) ' + JSON.stringify(r.da.map(x => x.title)))
step(7, 1); r = since()

check(r.da.length && r.da[r.da.length - 1].title === 'Program' && param('sel', 'fdn', 'Program').disp(param('sel', 'fdn', 'Program').v) === 'Saal', 'Hall, Encoder 7 = FDN-Preset weiter (Kirche -> Saal)')
idle(); r = since()

// --- 15 / 16 ------------------------------------------------------------------------------------------
push(15, 1); m.advance(120); step(15, 2); push(15, 0); r = since()
check(r.da.length && r.da.every(x => x.title === 'Yaw Angle' && x.key === 'out'), 'Encoder 15 drücken + drehen: Yaw vom SceneRotator (Out)')
tap(15); r = since()
check(r.sets.some(s => s.label === 'custom:pc solo 0' && s.v === 1), 'Encoder 15 tippen: Solo')
step(16, 1); r = since()
check(r.trig.includes('nextTrack'), 'Encoder 16 drehen: nächste Spur')
push(16, 1); m.advance(120); step(16, -2); push(16, 0); r = since()
check(r.sets.some(s => s.label === 'custom:pc out vol 0' && s.v < 0.7) && !r.sets.some(s => /mute/.test(s.label)), 'Encoder 16 drücken + drehen: Out-Volume runter, kein Mute')
tap(16); r = since()
check(r.sets.some(s => s.label === 'custom:pc mute 0' && s.v === 1), 'Encoder 16 tippen: Mute')
sv('custom:pc mute 0').mOnProcessValueChange(dev, 1, 0); idle(); r = since()
check(r.midi.some(x => x.port === 'Twister' && x.msg[0] === 0xB2 && x.msg[2] === 3), 'Mute: Encoder 16 blinkt')

// --- Twister View: a bank key switches the Twister's bank
sv('custom:view bank2').mOnProcessValueChange(dev, 1, 0); r = since()
check(r.midi.some(x => x.port === 'Twister' && x.msg.join() === [0xB3, 1, 127].join()) && r.midi.some(x => x.port === 'TouchOSC' && x.msg[3] === 4 && x.msg[4] === 1), 'View-Banktaste 2: Twister auf Bank 2, View bekommt Bank 2')
check(r.sets.some(s => s.label === 'custom:view bank2' && s.v === 0), 'View-Banktaste zurückgesetzt (nächster Tipp kommt wieder an)')
// --- hold 16 -> back to Sends/QC ------------------------------------------------------------------------
hold(16, 600); r = since()
check(r.trig.includes('subpage Bank 4/Sends/QC'), '16 halten: zurück zu Sends/QC')
check(sysexTo(r, 6, 3).some(x => x.t === 'Sends/QC'), 'Ansicht: Sends/QC')
step(1, 1); r = since()
check(r.da.length === 0 && r.sets.some(s => s.label === 'custom:twsend1Level'), 'Sends/QC: Encoder 1 wieder Send 1, kein Plugin')
hold(16, 700); r = since()
check(r.trig.includes('subpage Bank 4/Plugins') && sysexTo(r, 6, 3).some(x => x.t === 'Hall'), 'wieder Plugins: die Ebene (Hall) ist gemerkt')

// --- v6.1: Hall-EQ = the MultiEQ right before the FDN, layer 5 --------------------------------------------
const hq = (n) => param('sel', 'eqHall', n).v, tq = (n) => param('sel', 'eqTrack', n).v
hold(8, 600); r = since()
check(sysexTo(r, 6, 3).some(x => x.t === 'Hall-EQ'), 'Hall -> Ebene 5: Ansicht meldet Hall-EQ')
let a1 = hq('Filter Frequency 1'), b1 = tq('Filter Frequency 1')
step(1, 2); r = since()
check(r.da.length && hq('Filter Frequency 1') > a1 && tq('Filter Frequency 1') === b1, 'Ebene 5, Encoder 1 drehen: Frequenz Band 1 des Hall-EQ (nicht des MultiEQ A)')
a1 = hq('Filter Gain 2'); b1 = tq('Filter Gain 2')
push(2, 1); m.advance(120); step(2, 2); push(2, 0); r = since()
check(hq('Filter Gain 2') > a1 && tq('Filter Gain 2') === b1, 'Ebene 5: drücken + drehen = Gain Band 2')
a1 = hq('Q 5')
push(6, 1); m.advance(700); idle(); step(6, 2); push(6, 0); r = since()
check(hq('Q 5') !== a1, 'Ebene 5: halten + drehen = Q (Band 5 auf Encoder 6)')
hold(8, 600); r = since()
check(sysexTo(r, 6, 3).some(x => x.t === 'MultiEQ'), 'Ebene 5 halten: zurück zu MultiEQ')
a1 = hq('Filter Frequency 1'); b1 = param('out', 'eqOut', 'Filter Frequency 1').v
step(9, 2); r = since()
check(param('out', 'eqOut', 'Filter Frequency 1').v > b1 && hq('Filter Frequency 1') === a1, 'MultiEQ-Ebene steuert weiter nur den MultiEQ A (nicht den vor dem FDN)')

console.log(fails ? fails + ' FAILED' : 'ALL OK')
process.exit(fails ? 1 : 0)
