// Drives serena_MFTView.js through the MIDI Remote mock; prints structure + MIDI timeline.
const { load } = require('./mrmock')
const m = load(process.argv[2])
const dev = {}, mapping = {}
const page = m.pages[0]
const out = []
let sent = 0
const flush = (tag) => { for (; sent < m.log.midi.length; sent++) out.push(m.log.midi[sent].msg); out.push({ mark: tag }) }
m.driver.mOnActivate(dev); flush('activate')
page.mixer.mOnTitleChange(dev, mapping, 'Vox Lead')
const sv = (i) => m.sv('knob' + i)
// Nuendo calls these for whatever is bound (factory page or Mapping Assistant)
sv(0).mOnTitleChange(dev, 'StereoEncoder', 'Azimuth Angle'); sv(0).mOnDisplayValueChange(dev, '45.0', '°')
sv(16).mOnTitleChange(dev, 'StereoEncoder', 'Azimuth Angle'); sv(16).mOnDisplayValueChange(dev, '45.0', '°')
sv(32).mOnTitleChange(dev, 'VST MultiPanner', 'Pan Left-Right'); sv(32).mOnDisplayValueChange(dev, 'L 20', '')
sv(56).mOnTitleChange(dev, 'StereoEncoder', 'Azimuth Angle'); sv(56).mOnDisplayValueChange(dev, '45.0', '°')
sv(57).mOnTitleChange(dev, '', '')
flush('titles')
m.sv('custom:bank3').mOnProcessValueChange(dev, 1, 1); flush('bank3')
m.sv('custom:bank2').mOnProcessValueChange(dev, 0, -1); flush('bank2-off')
sv(32).mOnDisplayValueChange(dev, 'L 20', ''); flush('same')
m.advance(6000); m.driver.mOnIdle(dev); flush('idle')
const L = m.log
console.log(JSON.stringify({ detection: L.detection, bindings: L.bindings, valueBindings: L.valueBindings, out }))
