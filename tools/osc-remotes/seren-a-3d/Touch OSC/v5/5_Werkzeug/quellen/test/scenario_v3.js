// serena_TouchOSC3D.js v3 through the mock, with the parameter names of the real IEM plugins.
const { load } = require('./mrmock')
const m = load(process.argv[2])
const dev = {}, mp = {}
const out = () => { const r = m.log.midi.map(x => x.msg); m.log.midi.length = 0; return r }
const sets = () => { const r = m.log.setValues || []; m.log.setValues = []; return r }
const SE = ['Ambisonics Order', 'Normalization', 'Quaternion W', 'Quaternion X', 'Quaternion Y', 'Quaternion Z',
  'Azimuth Angle', 'Elevation Angle', 'Roll Angle', 'Stereo Width', 'Sample-wise Panning', '']
const SR = ['Ambisonics Order', 'Normalization', 'Yaw Angle', 'Pitch Angle', 'Roll Angle', 'Quaternion W']
const ME = ['Number of input channels ', 'Ambisonics Order', 'Normalization', 'Master azimuth angle',
  'Master elevation angle', 'Master roll angle', 'Lock Directions relative to Master']
for (let i = 1; i <= 64; i++) ME.push('Azimuth angle ' + i, 'Elevation angle ' + i, 'Gain ' + i, 'Mute input ' + i, 'Solo input ' + i)
const v = (label) => m.sv('custom:' + label)
const titles = (prefix, K, plugin, list) => { for (let i = 0; i < K; i++) v(prefix + ' ' + (i + 1)).mOnTitleChange(dev, plugin, list[i] || '') }
const R = {}
m.driver.mOnActivate(dev); out()
const ch = m.log.bankChannels
ch[0].mOnTitleChange(dev, mp, 'Vox'); ch[1].mOnTitleChange(dev, mp, 'Drums OH'); ch[2].mOnTitleChange(dev, mp, 'Bass')
titles('Ov 1 I5', 12, 'StereoEncoder', SE)
titles('Ov 2 I5', 12, 'MultiEncoder', ME)
titles('Ov 3 I5', 12, 'Pro-Q 3', ['Frequency', 'Gain', 'Q', 'Azimuth Angle'])
titles('Ov 1 I6', 6, 'SceneRotator', SR)
R.titlesOut = out()
// values from Nuendo
v('Ov 1 I5 1').mOnProcessValueChange(dev, 0.5, 0)            // Ambisonics order: must not go out
R.orderOut = out()
v('Ov 1 I5 7').mOnProcessValueChange(dev, 0.75, 0)           // Azimuth Angle
v('Ov 1 I5 10').mOnProcessValueChange(dev, 0.5625, 0)        // Stereo Width
v('Ov 2 I5 4').mOnProcessValueChange(dev, 0.25, 0)           // MultiEncoder master azimuth -> object 2 p0
v('Ov 3 I5 4').mOnProcessValueChange(dev, 0.9, 0)            // "Azimuth Angle" of Pro-Q: other plugin
v('Ov 1 I6 3').mOnProcessValueChange(dev, 0.6, 0)            // Yaw
R.valuesOut = out()
// devices move things
v('In Ov Enc 1 az').mOnProcessValueChange(dev, 0.3, 0)
v('In Ov Enc 2 el').mOnProcessValueChange(dev, 0.4, 0)
v('In Ov Enc 3 az').mOnProcessValueChange(dev, 0.1, 0)        // Pro-Q: nothing may happen
v('In Ov Enc 1 wid').mOnProcessValueChange(dev, 0.7, 0)
v('In Ov Rot 1 pitch').mOnProcessValueChange(dev, 0.45, 0)
R.inSets = sets()
// selected track: MultiEncoder with 4 inputs
m.pages[0].mixer.mOnTitleChange(dev, mp, 'Drums OH')
titles('Sel I5', 88, 'MultiEncoder', ME)
titles('Sel I6', 6, 'SceneRotator', SR)
out()
v('Sel I5 1').mOnProcessValueChange(dev, 4 / 64, 0)          // number of inputs
v('Sel I5 18').mOnProcessValueChange(dev, 0.25, 0)           // Azimuth angle 3
v('Sel I5 19').mOnProcessValueChange(dev, 0.5, 0)            // Elevation angle 3
v('Sel I5 20').mOnProcessValueChange(dev, 1.0, 0)            // Gain 3
v('Sel I5 4').mOnProcessValueChange(dev, 0.5, 0)             // master azimuth -> panner CC1
v('Sel I6 3').mOnDisplayValueChange(dev, '12.5', '°')
R.selOut = out()
v('In ME 3a').mOnProcessValueChange(dev, 0.8, 0)
v('In Pan az').mOnProcessValueChange(dev, 0.55, 0)
v('In Pan yaw').mOnProcessValueChange(dev, 0.65, 0)
v('In Pan wid').mOnProcessValueChange(dev, 0.65, 0)           // MultiEncoder has no width: nothing
R.selSets = sets()
// MultiPanner on the Quick Controls, in Isabella's order
const QCN = ['Rotate Signal around Z-Axis', 'Object Size', 'Signal Depth', 'Distance Scale', 'Front-Rear Pan', 'Z-Axis Pan', 'Left-Right Pan', 'Signal Width']
for (let i = 0; i < 8; i++) v('Ov MP 1 QC' + (i + 1)).mOnTitleChange(dev, 'Vox', QCN[i])
for (let i = 0; i < 8; i++) v('Sel MP QC' + (i + 1)).mOnTitleChange(dev, 'Drums OH', QCN[i])
out()
v('Ov MP 1 QC7').mOnProcessValueChange(dev, 0.75, 0)     // Left-Right = X -> ch10 cc0
v('Ov MP 1 QC6').mOnProcessValueChange(dev, 0.25, 0)     // Z-Axis = Z -> ch10 cc2
v('Ov MP 1 QC2').mOnProcessValueChange(dev, 0.5, 0)      // Object Size: not in the overview
v('Sel MP QC7').mOnProcessValueChange(dev, 1.0, 0)       // X -> pitch bend ch 0
v('Sel MP QC1').mOnProcessValueChange(dev, 0.5, 0)       // Rot Z -> pitch bend ch 3
v('Sel MP QC2').mOnProcessValueChange(dev, 0.0, 0)       // Object Size -> pitch bend ch 9
R.mpOut = out()
v('Ov MP 1 QC5').mOnProcessValueChange(dev, 0.2, 0)      // Front-Rear 0.2 in Nuendo -> surfaces 0.8 (up = front)
v('Sel MP QC5').mOnProcessValueChange(dev, 0.2, 0)
R.mpYOut = out()
v('In Ov MP 1 y').mOnProcessValueChange(dev, 0.6, 0)     // Front-Rear -> QC5
v('In Sel MP width').mOnProcessValueChange(dev, 0.3, 0)  // Signal Width -> QC8
v('In Sel MP tiltx').mOnProcessValueChange(dev, 0.3, 0)  // not on any QC: nothing
R.mpSets = sets()
// object 21 (index 20): values out as SysEx 10, in as SysEx 10; types; bank shift by 16
ch[20].mOnTitleChange(dev, mp, 'Reverb A')
titles('Ov 21 I5', 12, 'StereoEncoder', SE)
out()
v('Ov 21 I5 7').mOnProcessValueChange(dev, 0.5, 0)
R.o20Out = out()
m.log.midiIns[0].mOnSysex(dev, [0xF0, 0x7D, 0x4F, 10, 0, 20, 1, 96, 0, 0xF7])
R.o20Sets = sets()
ch[32].mOnTitleChange(dev, mp, 'Reverb A')              // first FX channel = object 21
m.advance(100); m.driver.mOnIdle(dev)
const idle1 = out()
R.typeOut = idle1.filter(x => x[0] === 0xF0 && x[3] === 3)
R.log1 = idle1.filter(x => x[2] === 0x4F && x[3] === 8).map(x => String.fromCharCode(...x.slice(4, -1)))
m.pages[0].mOnActivate(dev, {})
const btns = Object.keys(m.log.surface).filter(k => k.startsWith('button'))
R.btnCount = btns.length
ch[16].mOnTitleChange(dev, mp, 'Spur17'); out()
m.sv('button33').mOnProcessValueChange(dev, 1, 1)
R.bankOut = out().filter(x => x[0] === 0xF0 && x[3] === 5)
R.triggered = (m.log.triggered || []).length
R.nBank = m.log.bankChannels.length
m.advance(100); m.driver.mOnIdle(dev)
R.log = R.log1.concat(out().filter(x => x[2] === 0x4F && x[3] === 8).map(x => String.fromCharCode(...x.slice(4, -1))))
R.inBind = m.log.bindings.filter(b => /^custom:In /.test(b.label)).map(b => ({ label: b.label.slice(7), ch: b.desc.ch, cc: b.desc.cc, type: b.desc.type, out: !!b.port.out }))
R.mpBind = m.log.bindings.filter(b => b.desc.type === 'cc14' && (b.desc.ch === 10 || b.desc.ch === 11)).map(b => ({ ch: b.desc.ch, cc: b.desc.cc, in: !!b.port.in, out: !!b.port.out }))
R.vb = m.log.valueBindings.length
R.nCustom = Object.keys(m.log.surface).filter(k => k.startsWith('custom:')).length
// dearVR PRO: track 4 in Insert 4 (cartesian), track 5 in Insert 5 (polar, preset only)
const DV = ['Input Mode', 'Azimuth', 'Elevation', 'Distance', 'X', 'Y', 'Z', 'Virtual Acoustics', 'Reflections Level', 'Reverb Level']
titles('Ov 4 I5', 16, 'dearVR PRO 2', DV)
titles('Ov 5 I6', 16, 'dearVR PRO 2', DV)
out()
const disp = (lab, i, t, u) => v(lab + ' ' + i).mOnDisplayValueChange(dev, t, u)
disp('Ov 4 I5', 1, 'Cartesian', ''); disp('Ov 4 I5', 5, '2.00', 'm'); disp('Ov 4 I5', 6, '0.50', 'm'); disp('Ov 4 I5', 7, '1.00', 'm')
disp('Ov 4 I5', 8, 'Medium Room', '')
v('Ov 4 I5 2').mOnProcessValueChange(dev, 0.3, 0)            // dearVR Azimuth: must NOT go out as IEM azimuth
disp('Ov 5 I6', 1, 'Polar', ''); disp('Ov 5 I6', 2, '90.0', '°'); disp('Ov 5 I6', 3, '0.0', '°'); disp('Ov 5 I6', 4, '3.00', 'm')
disp('Ov 5 I6', 8, 'Studio Room', '')
R.dvOut = out()
v('In Ov Enc 4 az').mOnProcessValueChange(dev, 0.9, 0)        // surfaces never move dearVR
R.dvSets = sets()
v('Ov 4 I5 Byp').mOnProcessValueChange(dev, 1, 0)             // Insert 5 bypassed -> no room
R.dvByp = out()
m.advance(100); m.driver.mOnIdle(dev)
R.dvLog = out().filter(x => x[2] === 0x4F && x[3] === 8).map(x => String.fromCharCode(...x.slice(4, -1)))
// v5.5: encoder in Insert 6, rotator in Insert 9; first active one counts
titles('Ov 7 I6', 12, 'StereoEncoder', SE)
titles('Ov 7 I9', 6, 'SceneRotator', SR)
out()
v('Ov 7 I6 7').mOnProcessValueChange(dev, 0.2, 0)
v('Ov 7 I9 3').mOnProcessValueChange(dev, 0.7, 0)
R.slotOut = out()
v('In Ov Rot 7 yaw').mOnProcessValueChange(dev, 0.33, 0)
R.slotSets = sets()
titles('Ov 8 I5', 12, 'StereoEncoder', SE)
titles('Ov 8 I6', 12, 'StereoEncoder', SE)
v('Ov 8 I5 7').mOnProcessValueChange(dev, 0.1, 0)
v('Ov 8 I6 7').mOnProcessValueChange(dev, 0.9, 0)
out()
v('Ov 8 I5 Byp').mOnProcessValueChange(dev, 1, 0)             // Insert 5 bypassed -> Insert 6 counts
R.bypOut = out()
v('In Ov Enc 8 az').mOnProcessValueChange(dev, 0.44, 0)
R.bypSets = sets()
console.log(JSON.stringify(R))
