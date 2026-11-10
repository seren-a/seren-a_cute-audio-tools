// Fake DirectAccess trees with IEM plugins for mrmock.js (used by test_plug.js and the E16 test).
'use strict'
function install(m) {
const lin = (lo, hi, u, dec = 1) => ({ conv: n => lo + n * (hi - lo), inv: x => (x - lo) / (hi - lo), disp: v => (lo + v * (hi - lo)).toFixed(dec), units: u })
const P = (title, v, f = {}) => ({ title, v, ...f })
const hz = { conv: n => 20 * Math.pow(1000, n), inv: x => Math.log(x / 20) / Math.log(1000), disp: v => (20 * Math.pow(1000, v)).toFixed(0), units: 'Hz' }
function multiEQ(uid, f0) {
  const ps = []
  for (let b = 1; b <= 6; b++) {
    ps.push(P('Filter Enablement ' + b, 1, { disp: v => v >= 0.5 ? 'On' : 'Off' }))
    ps.push(P('Filter Type ' + b, 0.5))
    ps.push(P('Filter Frequency ' + b, Math.log((f0 * b) / 20) / Math.log(1000), hz))
    ps.push(P('Q ' + b, 0.3, lin(0.05, 8, '', 2)))
    ps.push(P('Filter Gain ' + b, 0.5, lin(-60, 15, 'dB')))
  }
  return { title: 'MultiEQ', uid, params: ps }
}
const slot = (n, plugin) => ({ title: 'Insert ' + n, uid: 'slot' + n + plugin.uid, params: [P('Bypass', 0, { disp: v => v >= 0.5 ? 'On' : 'Off' })], children: [plugin] })
const dir = { title: 'DirectionalCompressor', uid: 'dir', params: [P('Input Gain', 0.5, lin(-10, 10, 'dB')), P('Azimuth of mask', 0.5, lin(-180, 180, '°')), P('Elevation of mask', 0.5, lin(-90, 90, '°')), P('Width of mask', 0.3, lin(10, 180, '°')), P('Listen to', 0)]
  .concat(...[1, 2].map(c => [P('Enable C' + c, 1), P('Compression Driving Signal C' + c, 0), P('Apply compression to C' + c, 0, { disp: v => ['Mask', 'Outside', 'Full'][Math.min(2, Math.floor(v * 3))] }),
    P('Threshold C' + c, 0.8, lin(-50, 10, 'dB')), P('Knee C' + c, 0, lin(0, 30, 'dB')), P('Attack Time C' + c, 0.1, lin(0, 100, 'ms')), P('Release Time C' + c, 0.2, lin(0, 500, 'ms')),
    P('Ratio C' + c, 0.1, lin(1, 16, ':1')), P('MakeUp Gain C' + c, 0.5, lin(-10, 20, 'dB'))])) }
const omni = { title: 'OmniCompressor', uid: 'omni', params: [P('Threshold', 0.8, lin(-50, 10, 'dB')), P('Knee', 0, lin(0, 30, 'dB')), P('Attack Time', 0.1, lin(0, 100, 'ms')), P('Release Time', 0.2, lin(0, 500, 'ms')),
  P('Ratio', 0.1, lin(1, 16, ':1')), P('MakeUp Gain', 0.5, lin(-10, 20, 'dB')), P('LookAhead', 0)] }
const fdn = { title: 'FdnReverb', uid: 'fdn', params: [P('Room Size', 0.3, lin(1, 30, 'm')), P('Reverberation Time', 0.2, lin(0.1, 9, 's')), P('Lows Cutoff Frequency', 0.2, hz), P('Lows Q Factor', 0.3),
  P('Lows Gain', 0.5, lin(-80, 6, 'dB')), P('Highs Cutoff Frequency', 0.8, hz), P('Highs Q Factor', 0.3), P('Highs Gain', 0.5, lin(-80, 4, 'dB')), P('Dry/Wet', 0.5, lin(0, 100, '%', 0)),
  P('Fade-in Time', 0, lin(0, 0.5, 's', 2)), P('Feedback Network Size', 0.5), P('Program', 0, { disp: v => ['Kirche', 'Saal', 'Wohnzimmer', 'Studio'][Math.min(3, Math.floor(v * 4))] })] }
const conv = { title: 'mcfx_convolver8', uid: 'conv', params: [P('Bypass', 0), P('Wet Gain', 0.7, lin(-60, 12, 'dB')), P('Dry Gain', 0, lin(-60, 12, 'dB')), P('Predelay', 0, lin(0, 500, 'ms', 0))] }
const rot = { title: 'SceneRotator', uid: 'rot', params: [P('Yaw Angle', 0.5, lin(-180, 180, '°')), P('Pitch Angle', 0.5), P('Roll Angle', 0.5)] }
m.trees.sel = { title: 'Vox', uid: 'track', children: [slot(5, dir), slot(6, omni), slot(7, multiEQ('eqTrack', 120)), slot(8, multiEQ('eqHall', 300)), slot(9, fdn), slot(10, conv)] }
m.trees.out = { title: 'Stereo Out', uid: 'outch', children: [slot(5, multiEQ('eqOut', 40)), slot(9, rot)] }
const param = (tree, plug, name) => { let hit = null; const w = n => { if (n.uid === plug) hit = n.params.find(p => p.title === name); (n.children || []).forEach(w) }; w(m.trees[tree]); return hit }
  if (process.env.NOCONV) {                 // Nuendo with IEM plugins: "plain" = the normalized value
    const strip = (n) => { (n.params || []).forEach(p => { delete p.conv; delete p.inv }); (n.children || []).forEach(strip) }
    strip(m.trees.sel); strip(m.trees.out)
  }
  return param
}
module.exports = { install }
