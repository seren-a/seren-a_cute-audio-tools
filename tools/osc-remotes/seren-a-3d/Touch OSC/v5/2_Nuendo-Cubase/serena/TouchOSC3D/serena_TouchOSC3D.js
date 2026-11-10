// seren.a · TouchOSC 3D v3 for Nuendo / Cubase (MIDI Remote API 1.x)
// Install: <Driver Scripts Folder>/Local/serena/TouchOSC3D/serena_TouchOSC3D.js
// One script for all seren.a 3D surfaces over the TouchOSC Bridge: Panner (Skript),
// Objekt-Übersicht (phone) and IEM space (iPad). Protocol: see PROTOKOLL.md.
// NOT TESTED IN NUENDO: API names checked against midiremote_api_v1.d.ts, logic against a mock.
//
// Plugins (MIDI Remote reaches plugins only by slot number), slot plan since v5.5:
//   Insert 5 or 6 = IEM StereoEncoder, IEM MultiEncoder or dearVR PRO,
//   Insert 5-9    = IEM SceneRotator.
//   In each case the first one that is switched on and not bypassed counts (else the first one found).
//   Inserts 5-9 also carry MultiEQ, Directional-/OmniCompressor, mcfx convolver, FDN reverb: ignored here.
//   Only shown (ROOM page), never moved from the surfaces. Its position/room parameters must be within
//   the first 16 parameters of the slot (Remote Control Editor) - the LOG says what was found.
// Parameters are recognised BY NAME ("Azimuth Angle", "Master azimuth angle", "Yaw Angle" ...),
// never by position, and the script only ever touches the parameters it recognised. Anything
// else in those slots (another plugin, Ambisonics order, normalisation ...) is left alone.
// What it recognised is reported to the surfaces' MONITOR page (SysEx 8).
//
// VST MultiPanner: Steinberg gives scripts no direct access. Way round: Track Quick Controls.
//   Put MultiPanner parameters on the track's QC1-8 in any order; they are recognised by name
//   ("Left-Right Pan" = X, "Front-Rear Pan" = Y, "Z-Axis Pan" = Z, "Rotate Signal around Z-Axis",
//   "Object Size", "Signal Depth", "Distance Scale", "Signal Width" ...).

var midiremote_api = require('midiremote_api_v1')

var SLOTS = [4, 5, 6, 7, 8]   // Inserts 5-9 (0 = first slot)
var ENC_SLOTS = 2             // the first two of them (Inserts 5, 6) may carry the encoder / dearVR PRO
var K_SMALL = 6               // parameters read in Inserts 7-9 (SceneRotator needs 6)
var OV_N = 32           // objects sent to the surfaces (16, 32 or 64; 64 = many values, may be sluggish)
var TZ_N = 64           // channels per type zone (only names: FX / group / instrument recognition)
var ME_N = 16           // MultiEncoder inputs shown for the selected track
var K_ENC = 16          // parameters read per slot in the overview (IEM master/stereo + dearVR PRO)
var K_SEL = 7 + 5 * ME_N + 1   // selected track: MultiEncoder header + 16 inputs x 5 parameters
var PORT_MATCH = 'TouchOSC Bridge'

var driver = midiremote_api.makeDeviceDriver('serena', 'TouchOSC3D', 'seren.a')
function clog(t) { try { console.log('[seren.a 3D] ' + t) } catch (e) {} }
clog('Skript v5.5 geladen')
var midiIn = driver.mPorts.makeMidiInput('TouchOSC')
var midiOut = driver.mPorts.makeMidiOutput('TouchOSC')
driver.makeDetectionUnit().detectPortPair(midiIn, midiOut)
  .expectInputNameContains(PORT_MATCH)
  .expectOutputNameContains(PORT_MATCH)

var page = driver.mMapping.makePage('3D')
var sel = page.mHostAccess.mTrackSelection

// --- text and MIDI out --------------------------------------------------------------------------
var MAP = { 'ä': 'a', 'ö': 'o', 'ü': 'u', 'Ä': 'A', 'Ö': 'O', 'Ü': 'U', 'ß': 's', '°': '', '·': '-' }
function ascii(s) {
  var out = ''
  s = String(s === undefined || s === null ? '' : s)
  for (var i = 0; i < s.length; i++) {
    var ch = MAP.hasOwnProperty(s.charAt(i)) ? MAP[s.charAt(i)] : s.charAt(i)
    if (ch.length && ch.charCodeAt(0) >= 32 && ch.charCodeAt(0) <= 126) out += ch
  }
  return out.replace(/^\s+|\s+$/g, '').substr(0, 96)
}

var sentText = {}
function sysex(dev, id, head, text, force) {
  var s = text === undefined ? '' : ascii(text)
  var key = id + ':' + head.join(',')
  if (!force && text !== undefined && sentText[key] === s) return
  sentText[key] = s
  var msg = [0xF0, 0x7D, id].concat(head)
  for (var i = 0; i < s.length; i++) msg.push(s.charCodeAt(i))
  msg.push(0xF7)
  midiOut.sendMidi(dev, msg)
}
function ov(dev, head, text, force) { sysex(dev, 0x4F, head, text, force) }
function pannerText(dev, field, text) { sysex(dev, 0x54, [field], text) }

var sent14 = {}
function send14(dev, ch, cc, norm) {
  var v = Math.round(Math.max(0, Math.min(1, norm)) * 16383)
  var key = ch * 128 + cc
  if (sent14[key] === v) return
  sent14[key] = v
  midiOut.sendMidi(dev, [0xB0 + ch, cc, v >> 7])
  midiOut.sendMidi(dev, [0xB0 + ch, cc + 32, v & 127])
}
function ccOf(obj, p) { return 4 * (obj % 8) + p }
// object values: objects 0-15 as 14-bit CC (base channel 12 encoder, 6 rotator, 10 MultiPanner),
// objects 16+ as SysEx F0 7D 4F 0A <kind 0/1/2> <obj> <part> <msb> <lsb> F7
var KIND_CH = [12, 6, 10]
var sentX = {}
function outObj(dev, kind, o, p, norm) {
  if (o < 16 && KIND_CH[kind] !== undefined) { send14(dev, KIND_CH[kind] + (o >> 3), ccOf(o, p), norm); return }
  var v = Math.round(Math.max(0, Math.min(1, norm)) * 16383)
  var key = kind + ':' + o + ':' + p
  if (sentX[key] === v) return
  sentX[key] = v
  midiOut.sendMidi(dev, [0xF0, 0x7D, 0x4F, 10, kind, o, p, v >> 7, v & 127, 0xF7])
}

function now() { return (typeof Date !== 'undefined') ? Date.now() : 0 }

// --- recognising plugins and parameters by name ---------------------------------------------------
function pluginType(title) {
  var t = String(title || '')
  if (t === '') return ''
  if (/multi\s*encoder/i.test(t)) return 'ME'
  if (/stereo\s*encoder/i.test(t)) return 'SE'
  if (/scene\s*rotator/i.test(t)) return 'SR'
  if (/dearvr\s*pro/i.test(t)) return 'DV'
  return 'other'
}
var PLUGIN_NAME = { SE: 'StereoEncoder', ME: 'MultiEncoder', SR: 'SceneRotator', DV: 'dearVR PRO' }

// role of a parameter title for a plugin type, or null (= never touched)
function roleOf(type, title) {
  var t = String(title || '').replace(/^\s+|\s+$/g, '').toLowerCase()
  var m
  if (type === 'SE') {
    if (t === 'azimuth angle') return 'az'
    if (t === 'elevation angle') return 'el'
    if (t === 'stereo width') return 'wid'
  } else if (type === 'ME') {
    if (t === 'master azimuth angle') return 'az'
    if (t === 'master elevation angle') return 'el'
    if (/^number of input channels/.test(t)) return 'nin'
    if ((m = /^azimuth angle (\d+)$/.exec(t))) return 'ia' + m[1]
    if ((m = /^elevation angle (\d+)$/.exec(t))) return 'ie' + m[1]
    if ((m = /^gain (\d+)$/.exec(t))) return 'ig' + m[1]
  } else if (type === 'SR') {
    if (t === 'yaw angle') return 'yaw'
    if (t === 'pitch angle') return 'pitch'
    if (t === 'roll angle') return 'roll'
  } else if (type === 'DV') {
    // dearVR PRO: matched loosely (same rules as the Reaper hub)
    var side = function () {
      if (/left/.test(t)) return 'L'; if (/right/.test(t)) return 'R'
      if (/front/.test(t)) return 'F'; if (/back|rear/.test(t)) return 'B'
      if (/top|ceiling/.test(t)) return 'T'; if (/bottom|floor|ground/.test(t)) return 'Bo'
      return null
    }
    if (/wall|auraliz|auralis/.test(t)) { var w = side(); if (w) return 'w' + w }
    if (/scale|gain|pass/.test(t)) return null
    if (/azimuth/.test(t)) return 'az'
    if (/elevation/.test(t)) return 'el'
    if (/distance/.test(t)) return 'dist'
    if (/input mode/.test(t) || t === 'mode' || /polar|cartesian/.test(t)) return 'mode'
    if (/preset|virtual acoustic/.test(t)) return 'preset'
    var ax = ['x', 'y', 'z']
    for (var a = 0; a < 3; a++) {
      var c = ax[a]
      if (t === c || new RegExp('^' + c + '[\\s_\\-(]').test(t) || new RegExp('[\\s_\\-]' + c + '$').test(t) ||
          t.indexOf('position ' + c) >= 0) return c
    }
  }
  return null
}
var ROLE_NAME = { az: 'Azimuth', el: 'Elevation', wid: 'Width', yaw: 'Yaw', pitch: 'Pitch', roll: 'Roll' }

// A plugin slot read through K hidden values. Values go out by role (callback), values from the
// surfaces come in by role (set) and are only applied to a parameter whose name was recognised.
function ParamSet(label, zone, K, kind, cb) {
  var s = { label: label, kind: kind, vars: [], title: [], plugin: '', type: '', role: [], idx: {},
            disp: [], val: [], cb: cb, summary: '' }
  function recompute() {
    s.type = pluginType(s.plugin)
    var ok = s.type === 'DV' || (kind === 'any' && s.type !== 'other' && s.type !== '') ||
             ((kind === 'enc') ? (s.type === 'SE' || s.type === 'ME') : (s.type === 'SR'))
    s.idx = {}
    for (var i = 0; i < K; i++) {
      var r = ok ? roleOf(s.type, s.title[i]) : null
      s.role[i] = r
      if (r && s.idx[r] === undefined) s.idx[r] = i
    }
  }
  function wire(i) {
    var v = driver.mSurface.makeCustomValueVariable(label + ' ' + (i + 1))
    page.makeValueBinding(v, zone.makeParameterValue())
    v.mOnTitleChange = function (dev, objectTitle, valueTitle) {
      s.plugin = String(objectTitle || '')
      s.title[i] = String(valueTitle || '')
      recompute()
      if (cb.info) cb.info(dev, s)
    }
    v.mOnProcessValueChange = function (dev, value) {
      s.val[i] = value
      var r = s.role[i]
      if (r && cb.value) cb.value(dev, r, value, s)
    }
    v.mOnDisplayValueChange = function (dev, value, units) {
      s.disp[i] = String(value || '') + (units ? ' ' + units : '')
      var r = s.role[i]
      if (r && cb.display) cb.display(dev, r, s.disp[i], s)
    }
    s.vars.push(v)
  }
  for (var i = 0; i < K; i++) wire(i)
  s.set = function (dev, role, value) {
    if (s.type === 'DV') return false        // dearVR is only shown, never moved from the surfaces
    var i = s.idx[role]
    if (i === undefined) return false
    s.vars[i].setProcessValue(dev, value)
    return true
  }
  s.describe = function () {
    if (s.type === '') return ''
    if (s.type === 'other') return '"' + s.plugin + '" (kein IEM, wird nicht angefasst)'
    if (s.type === 'DV') {
      var f = []
      if (s.idx.x !== undefined) f.push('X/Y/Z')
      if (s.idx.az !== undefined) f.push('Az/El/Dist')
      if (s.idx.wL !== undefined) f.push('Waende')
      if (s.idx.preset !== undefined) f.push('Preset')
      if (!f.length) {
        var names = []
        for (var j = 0; j < s.title.length; j++) if (s.title[j]) names.push(s.title[j])
        return 'dearVR PRO: Position nicht erkannt - Parameter: ' + names.join(' | ').substr(0, 90)
      }
      return 'dearVR PRO (' + f.join(', ') + ')'
    }
    var parts = []
    for (var r in ROLE_NAME) if (s.idx[r] !== undefined) parts.push(ROLE_NAME[r] + ' P' + (s.idx[r] + 1))
    if (s.type === 'ME' && K > K_ENC) {   // selected track only
      var n = 0
      for (var k in s.idx) if (/^ia/.test(k) && parseInt(k.substr(2), 10) <= ME_N) n++
      parts.push(n + ' Eingaenge lesbar')
    }
    return PLUGIN_NAME[s.type] + (parts.length ? ' (' + parts.join(', ') + ')' : ' (keine Parameter erkannt)')
  }
  return s
}

function slotViewer(insertFx, name, index) {
  var v = insertFx.makeInsertEffectViewer(name)
  if (v.accessSlotAtIndex) v = v.accessSlotAtIndex(index)
  return v
}
function viewerSlot(insertFx, name, index) { return slotViewer(insertFx, name, index).mParameterBankZone }

// --- dearVR PRO (overview objects): position = kind 3 in metres, room = cmd 14 ---------------------
var DV_AZ_LEFT = false     // polar mode: true = +90 degrees azimuth is LEFT (IEM-style)
var DV_X_RIGHT = true      // cartesian mode: true = +X is RIGHT
var DV_Z_FRONT = true      // cartesian mode: true = +Z is IN FRONT (dearVR: Z = depth, Y = height)
var DV_RANGE = 32          // metres: -32..+32 in 14 bit
// The manual's presets with their wall distances in metres: left, front, right, top, back, bottom
var DV_ROOMS = {
  'Concert Hall 1': [12.9, 14.0, 10.5, 20.8, 25.1, 1.8], 'Concert Hall 2': [14.1, 16.6, 13.3, 21.5, 28.3, 1.8],
  'Large Recording Hall': [15.7, 12.1, 15.9, 22.2, 19.3, 1.8], 'Small Recording Hall': [7.7, 5.4, 7.9, 12.0, 9.3, 1.8],
  'Kings Hall': [13.7, 10.4, 13.9, 20.3, 7.3, 1.8], 'Cathedral': [27.5, 24.2, 29.0, 30.0, 30.0, 1.8],
  'Church': [13.9, 17.9, 11.5, 25.5, 22.1, 1.8], 'Chapel': [14.7, 12.4, 14.1, 23.0, 16.3, 1.8],
  'Large Room': [7.9, 4.4, 6.9, 10.0, 5.5, 1.8], 'Medium Room': [3.8, 2.1, 4.1, 4.0, 2.8, 1.8],
  'Small Room': [2.7, 1.5, 2.6, 3.6, 2.2, 1.8], 'Office 1': [3.2, 1.9, 3.9, 4.5, 2.8, 1.8],
  'Office 2': [6.7, 2.4, 6.9, 5.3, 3.3, 1.8], 'Small Studio': [2.7, 2.0, 3.4, 4.7, 2.1, 1.8],
  'Medium Conference Hall': [6.7, 3.4, 6.9, 7.0, 3.3, 1.8], 'Cellar': [2.5, 2.8, 3.0, 3.2, 2.1, 1.8],
  'Empty Room': [5.0, 3.2, 3.7, 5.8, 4.3, 1.8], 'Small Livingroom': [2.3, 3.1, 2.7, 2.9, 2.6, 1.8],
  'Staircase': [4.7, 3.5, 4.9, 8.0, 3.3, 1.8], 'Corridor': [2.7, 2.0, 2.6, 8.8, 4.5, 1.8],
  'Bathroom': [2.1, 2.0, 2.3, 2.8, 1.6, 1.8], 'Restroom': [2.7, 1.5, 3.2, 4.2, 2.3, 1.8],
  'Car 1': [0.6, 0.7, 1.7, 1.6, 1.9, 1.3], 'Car 2': [0.5, 0.7, 1.0, 1.3, 1.6, 1.2],
  'Booth': [3.7, 2.1, 3.3, 2.5, 1.3, 1.8], 'Cinema': [8.0, 7.0, 9.0, 14.0, 9.0, 1.3],
  'Warehouse': [12.0, 10.0, 8.0, 20.0, 15.0, 1.8], 'Outdoor Street': [24.9, 0.0, 22.5, 0.0, 0.0, 1.8],
  'Outdoor Alley': [14.2, 0.0, 16.5, 0.0, 3.1, 1.8], 'Studio Room': [6.7, 3.4, 6.9, 8.0, 3.3, 1.8],
  'Live Stage': [11.7, 5.4, 11.9, 16.5, 14.3, 1.8], 'Live Arena': [20.2, 17.0, 21.5, 25.0, 15.7, 1.8],
  'Heavy Ambience': [6.7, 3.1, 6.9, 8.0, 3.3, 1.8], 'Plate Ambience': [6.7, 3.1, 6.9, 8.0, 3.3, 1.8],
  'Medium Ambience': [6.7, 3.1, 6.9, 8.0, 3.3, 1.8], 'Small Ambience': [6.7, 3.1, 6.9, 8.0, 3.3, 1.8],
  'Vocal Hall 1': [20.2, 15.0, 21.5, 25.0, 12.7, 1.8], 'Vocal Hall 2': [20.2, 15.0, 21.5, 25.0, 12.7, 1.8],
  'Vocal Plate': [20.2, 15.0, 21.5, 25.0, 12.7, 1.8], 'Drum Room 1': [6.7, 3.1, 6.9, 8.0, 3.3, 1.8],
  'Drum Room 2': [2.7, 3.1, 2.9, 6.0, 4.3, 1.8], 'Percussion Plate': [6.7, 3.4, 6.9, 8.0, 4.3, 1.8],
  'Percussion Ambience': [6.7, 3.4, 6.9, 8.0, 4.3, 1.8], 'Acoustic Hall': [20.2, 15.0, 21.5, 25.0, 12.7, 1.8],
  'String Hall': [20.2, 15.0, 21.5, 25.0, 12.7, 1.8], 'String Plate': [20.2, 15.0, 21.5, 25.0, 12.7, 1.8],
}
function dvNum(t) {
  var m = /[-+]?\d+(?:[.,]\d+)?/.exec(String(t === undefined ? '' : t))
  return m ? parseFloat(m[0].replace(',', '.')) : null
}
// position relative to the listener from the shown values: [x right, y front, z up] in metres, or null
function dvPosition(s) {
  var d = function (r) { var i = s.idx[r]; return i === undefined ? undefined : s.disp[i] }
  var polar = /polar/i.test(String(d('mode') || ''))
  if (s.idx.x !== undefined && !polar) {
    var x = dvNum(d('x')), y = dvNum(d('y')), z = dvNum(d('z'))
    if (x !== null && y !== null && z !== null) return [DV_X_RIGHT ? x : -x, DV_Z_FRONT ? z : -z, y]
  }
  var az = dvNum(d('az')), el = dvNum(d('el')), dist = dvNum(d('dist'))
  if (az !== null && dist !== null) {
    var a = az * Math.PI / 180, e = (el || 0) * Math.PI / 180
    var side = dist * Math.cos(e) * Math.sin(a)
    return [DV_AZ_LEFT ? -side : side, dist * Math.cos(e) * Math.cos(a), dist * Math.sin(e)]
  }
  return null
}
// walls from the wall parameters if they are visible, else from the preset table
function dvRoom(s) {
  var keys = ['wL', 'wF', 'wR', 'wT', 'wB', 'wBo'], w = []
  for (var i = 0; i < 6; i++) { var j = s.idx[keys[i]]; w.push(j === undefined ? null : dvNum(s.disp[j])) }
  var pi = s.idx.preset
  var preset = String(pi === undefined ? '' : (s.disp[pi] || '')).replace(/^\s+|\s+$/g, '')
  if (w[0] === null || w[1] === null || w[2] === null || w[4] === null) {
    var t = DV_ROOMS[preset]
    if (!t) return { walls: null, preset: preset }
    w = t
  }
  return { walls: w, preset: preset }
}
var dvSent = {}
// slots = [{ set, on, bypass }] for Insert 4 and Insert 5: the first active dearVR PRO counts
function dvSend(dev, o, slots) {
  var s = null
  for (var i = 0; i < slots.length; i++) {
    var sl = slots[i]
    if (sl.set.type === 'DV' && sl.on && !sl.bypass) { s = sl.set; break }
  }
  if (s) {
    var pos = dvPosition(s)
    if (pos) for (var p = 0; p < 3; p++) outObj(dev, 3, o, p, (pos[p] + DV_RANGE) / (2 * DV_RANGE))
    var rm = dvRoom(s)
    var key = rm.walls ? rm.walls.join(',') + '|' + rm.preset : '?|' + rm.preset
    if (dvSent[o] === key) return
    dvSent[o] = key
    if (rm.walls) {
      var b = [14, o]
      for (var k = 0; k < 6; k++) {
        var cm = Math.round(Math.min(163.83, Math.max(0, rm.walls[k])) * 100)
        b.push(cm >> 7, cm & 127)
      }
      ov(dev, b, rm.preset, true)
    } else ov(dev, [14, o], undefined, true)
    return
  }
  if (!dvSent[o]) return                   // never had dearVR: nothing to clear
  dvSent[o] = ''
  ov(dev, [14, o], undefined, true)        // dearVR gone / bypassed: no room
}

// --- Inserts 5-9 of one channel: which slot is the encoder, which the rotator --------------------
// Every slot is read; the encoder is the first of Inserts 5/6 with a StereoEncoder or MultiEncoder,
// the rotator the first of Inserts 5-9 with a SceneRotator (switched on and not bypassed first).
// cb: enc / rot (dev, role, value, set), encDisp / rotDisp (dev, role, text, set),
//     encInfo / rotInfo (dev, set or null), dv (dev) for dearVR PRO.
function SlotGroup(prefix, insertFx, kBig, cb) {
  var g = { slots: [], enc: null, rot: null }
  function active(st) { return st.on && !st.bypass }
  function pick(types, n) {
    var first = null
    for (var i = 0; i < Math.min(n, g.slots.length); i++) {
      var st = g.slots[i]
      if (types.indexOf(st.set.type) < 0) continue
      if (active(st)) return st.set
      if (!first) first = st.set
    }
    return first
  }
  function emit(dev, set, isEnc) {
    if (!set) return
    for (var i = 0; i < set.role.length; i++) {
      var r = set.role[i]
      if (r && set.val[i] !== undefined) (isEnc ? cb.enc : cb.rot)(dev, r, set.val[i], set)
      if (r && set.disp[i] !== undefined) {
        var f = isEnc ? cb.encDisp : cb.rotDisp
        if (f) f(dev, r, set.disp[i], set)
      }
    }
  }
  g.recheck = function (dev) {
    var e = pick(['SE', 'ME'], ENC_SLOTS), r = pick(['SR'], g.slots.length)
    if (e !== g.enc) { g.enc = e; if (cb.encInfo) cb.encInfo(dev, e); emit(dev, e, true) }
    else if (cb.encInfo) cb.encInfo(dev, e)
    if (r !== g.rot) { g.rot = r; if (cb.rotInfo) cb.rotInfo(dev, r); emit(dev, r, false) }
    else if (cb.rotInfo) cb.rotInfo(dev, r)
    if (cb.dv) cb.dv(dev)
  }
  for (var k = 0; k < SLOTS.length; k++) (function (k) {
    var name = prefix + ' I' + (SLOTS[k] + 1)
    var viewer = slotViewer(insertFx, name, SLOTS[k])
    var st = { set: null, on: true, bypass: false, insert: SLOTS[k] + 1 }
    st.set = ParamSet(name, viewer.mParameterBankZone, k < ENC_SLOTS ? kBig : K_SMALL, 'any', {
      value: function (dev, role, v, set) {
        if (set === g.enc && set.type !== 'DV') cb.enc(dev, role, v, set)
        else if (set === g.rot && set.type !== 'DV') cb.rot(dev, role, v, set)
      },
      display: function (dev, role, text, set) {
        if (set.type === 'DV' && cb.dv) cb.dv(dev)
        else if (set === g.enc && cb.encDisp) cb.encDisp(dev, role, text, set)
        else if (set === g.rot && cb.rotDisp) cb.rotDisp(dev, role, text, set)
      },
      info: function (dev) { g.recheck(dev) },
    })
    st.set.insert = SLOTS[k] + 1
    if (viewer.mOn) {
      var vo = driver.mSurface.makeCustomValueVariable(name + ' On')
      page.makeValueBinding(vo, viewer.mOn)
      vo.mOnProcessValueChange = function (dev, value) { st.on = value > 0.5; g.recheck(dev) }
    }
    if (viewer.mBypass) {
      var vb = driver.mSurface.makeCustomValueVariable(name + ' Byp')
      page.makeValueBinding(vb, viewer.mBypass)
      vb.mOnProcessValueChange = function (dev, value) { st.bypass = value > 0.5; g.recheck(dev) }
    }
    g.slots.push(st)
  })(k)
  g.encSet = { label: prefix + ' Enc', set: function (dev, role, v) { return g.enc ? g.enc.set(dev, role, v) : false } }
  g.rotSet = { label: prefix + ' Rot', set: function (dev, role, v) { return g.rot ? g.rot.set(dev, role, v) : false } }
  g.describe = function () {
    var parts = []
    for (var i = 0; i < g.slots.length; i++) {
      var set = g.slots[i].set
      if (set.type === 'other') parts.push('Insert ' + set.insert + ': ' + set.plugin + ' (kein IEM 3D)')
      else if (set.type) parts.push('Insert ' + set.insert + ': ' + set.describe())
    }
    return parts.join(' · ')
  }
  return g
}

// --- log to the MONITOR pages (sent from mOnIdle so half-read titles don't flood it) -------------
var logPending = {}, logSent = {}
function logLater(key, text) { logPending[key] = text }
function flushLog(dev) {
  for (var k in logPending) {
    var t = logPending[k]
    if (logSent[k] !== t) { logSent[k] = t; ov(dev, [8], k + '|' + t, true); if (t) clog(t) }   // key|text, empty text = remove line
  }
  logPending = {}
}

// --- surface: inputs from the devices (14-bit CC, input port only) ------------------------------
function inVar(label, ch, cc) {
  var v = driver.mSurface.makeCustomValueVariable(label)
  v.mMidiBinding.setInputPort(midiIn).bindToControlChange14Bit(ch, cc)
  return v
}
function inButton(ch, note, out) {
  var b = driver.mSurface.makeButton(0, 0, 1, 1)
  var mb = b.mSurfaceValue.mMidiBinding.setInputPort(midiIn)
  if (out) mb.setOutputPort(midiOut)
  mb.bindToNote(ch, note)
  return b
}

// === overview: OV_N MixConsole channels (VCA never: no panner) ===================================
var mixer = page.mHostAccess.mMixConsole.makeMixerBankZone('Overview')
  .includeAudioChannels().includeGroupChannels().includeInstrumentChannels()
  .includeSamplerChannels().includeMIDIChannels().includeFXChannels()
var ovTitle = [], ovFlags = [], ovBank = 0, ovAlive = 0

function setFlag(dev, o, bit, on) {
  var v = on ? (ovFlags[o] | bit) : (ovFlags[o] & ~bit)
  if (v === ovFlags[o]) return
  ovFlags[o] = v
  ov(dev, [3, o, v], undefined, true)
}

var ENC_P = { az: 0, el: 1, wid: 2 }, ROT_P = { yaw: 0, pitch: 1, roll: 2 }

var ovCh = [], ovSets = []
function ovChannel(o) {
  ovTitle.push(''); ovFlags.push(0)
  var ch = mixer.makeMixerBankChannel()
  ovCh.push(ch)
  var trackNo = function () { return ovBank * 16 + o + 1 }
  ch.mOnTitleChange = function (dev, mapping, title) {
    ovTitle[o] = String(title || '')
    ov(dev, [1, o], title)
    typesDirty = true
  }
  ch.mOnColorChange = function (dev, mapping, r, g, b, a, isActive) {
    ov(dev, [2, o, Math.round(r * 127), Math.round(g * 127), Math.round(b * 127)], undefined)
  }
  var grp = SlotGroup('Ov ' + (o + 1), ch.mInsertAndStripEffects, K_ENC, {
    enc: function (dev, role, v) { if (ENC_P[role] !== undefined) outObj(dev, 0, o, ENC_P[role], v) },
    rot: function (dev, role, v) { if (ROT_P[role] !== undefined) outObj(dev, 1, o, ROT_P[role], v) },
    encInfo: function (dev, s) {
      setFlag(dev, o, 1, !!s)
      setFlag(dev, o, 4, !!s && s.type === 'ME')
    },
    rotInfo: function (dev, s) {
      setFlag(dev, o, 8, !!s)
      var d = grp ? grp.describe() : ''
      logLater('e' + o, d ? 'Spur ' + trackNo() + ' ' + ovTitle[o] + ' · ' + d : '')
    },
    dv: function (dev) { if (grp) dvSend(dev, o, grp.slots) },
  })
  var enc = grp.encSet, rot = grp.rotSet
  enc.label = 'Ov Enc ' + (o + 1); rot.label = 'Ov Rot ' + (o + 1)
  // devices move objects: same CCs as the feedback
  var encRoles = ['az', 'el', 'wid'], rotRoles = ['yaw', 'pitch', 'roll']
  function wireIn(set, ch2, roles) {
    for (var p = 0; p < 3; p++) (function (p) {
      var v = inVar('In ' + set.label + ' ' + roles[p], ch2, ccOf(o, p))
      v.mOnProcessValueChange = function (dev, value) { set.set(dev, roles[p], value) }
    })(p)
  }
  if (o < 16) {                      // objects 16+ come in as SysEx (midiIn.mOnSysex below)
    wireIn(enc, 12 + (o >> 3), encRoles)
    wireIn(rot, 6 + (o >> 3), rotRoles)
  }
  ovSets[o] = { enc: enc, rot: rot, encRoles: encRoles, rotRoles: rotRoles }
  // selection
  var sb = inButton(14, o, true)
  page.makeValueBinding(sb.mSurfaceValue, ch.mValue.mSelected).setTypeToggle()
  // level
  var meter = driver.mSurface.makeCustomValueVariable('Level ' + (o + 1))
  var lastLevel = -1
  meter.mOnProcessValueChange = function (dev, value) {
    var lv = Math.max(0, Math.min(127, Math.round(value * 127)))
    if (Math.abs(lv - lastLevel) < 2 && !(lv === 0 && lastLevel !== 0)) return
    lastLevel = lv
    midiOut.sendMidi(dev, [0xBE, o, lv])
  }
  page.makeValueBinding(meter, ch.mValue.mVUMeter)
}
for (var oc = 0; oc < OV_N; oc++) ovChannel(oc)

// === VST MultiPanner via Track Quick Controls ===================================================
// Recognised BY NAME, in any QC slot and any order (Nuendo's MultiPanner parameter names):
var MP_ROLE_IDX = { x: 0, y: 1, z: 2, rotz: 3, tilty: 4, tiltx: 5, dist: 6, div: 7, field: 8, src: 9, width: 10, depth: 11 }
var MP_ROLE_NAME = { x: 'X', y: 'Y', z: 'Z', rotz: 'Rot Z', tilty: 'Tilt Y', tiltx: 'Tilt X', dist: 'Distance',
                     div: 'Divergence', field: 'Field Size', src: 'Size', width: 'Width', depth: 'Depth' }
function mpRole(title) {
  var t = String(title || '').toLowerCase()
  if (/left.?right pan/.test(t)) return 'x'
  if (/front.?rear pan/.test(t)) return 'y'
  if (/z.?axis pan|bottom.?top pan|elevation/.test(t)) return 'z'
  if (/around z|rotat.*z|z.*rotat/.test(t)) return 'rotz'
  if (/around y|tilt.*y|y.*tilt/.test(t)) return 'tilty'
  if (/around x|tilt.*x|x.*tilt/.test(t)) return 'tiltx'
  if (/distance/.test(t)) return 'dist'
  if (/diverg/.test(t)) return 'div'
  if (/field/.test(t)) return 'field'
  if (/object size|source size|signal size/.test(t)) return 'src'
  if (/width/.test(t)) return 'width'
  if (/depth/.test(t)) return 'depth'
  return null
}
// MultiPanner "Front-Rear Pan" runs the other way round than the surfaces draw it (there: up =
// front = Y +100). Flipped here, once, for every surface (panner, overview, iPad, monitor).
var MP_FLIP = { y: true }
function mpFlip(role, v) { return MP_FLIP[role] ? 1 - v : v }
// 8 hidden values on a track's Quick Controls; cb.value(dev, role, v), cb.info(dev, set)
function QcSet(label, qcs, cb) {
  var s = { vars: [], role: [], idx: {}, title: [] }
  function recompute() {
    s.idx = {}
    for (var i = 0; i < 8; i++) { s.role[i] = mpRole(s.title[i]); if (s.role[i] && s.idx[s.role[i]] === undefined) s.idx[s.role[i]] = i }
  }
  for (var i = 0; i < 8; i++) (function (i) {
    var v = driver.mSurface.makeCustomValueVariable(label + ' QC' + (i + 1))
    page.makeValueBinding(v, qcs.getByIndex(i))
    v.mOnTitleChange = function (dev, objectTitle, valueTitle) {
      s.title[i] = String(valueTitle || ''); recompute()
      if (cb.info) cb.info(dev, s)
    }
    v.mOnProcessValueChange = function (dev, value) { var r = s.role[i]; if (r && cb.value) cb.value(dev, r, mpFlip(r, value)) }
    s.vars.push(v)
  })(i)
  s.set = function (dev, role, value) {
    var i = s.idx[role]
    if (i === undefined) return false
    s.vars[i].setProcessValue(dev, mpFlip(role, value)); return true
  }
  s.describe = function () {
    var parts = []
    for (var r in MP_ROLE_IDX) if (s.idx[r] !== undefined) parts.push(MP_ROLE_NAME[r] + '=QC' + (s.idx[r] + 1))
    return parts.length ? 'MultiPanner ' + parts.join(' ') : ''
  }
  return s
}

// overview: X/Y/Z of every object (14-bit CC channels 11/12), out and in
var ovMp = []
for (var mo = 0; mo < OV_N; mo++) (function (o) {
  var XYZ = ['x', 'y', 'z']
  var set = QcSet('Ov MP ' + (o + 1), ovCh[o].mQuickControls, {
    value: function (dev, role, v) {
      var p = XYZ.indexOf(role)
      if (p >= 0) outObj(dev, 2, o, p, v)
    },
    info: function (dev, s) {
      var on = s.idx.x !== undefined || s.idx.y !== undefined || s.idx.z !== undefined
      setFlag(dev, o, 2, on)
      if (on) ov(dev, [6, o], ovTitle[o] || ('Spur ' + (ovBank * 16 + o + 1)))
      logLater('m' + o, on ? 'Spur ' + (ovBank * 16 + o + 1) + ' ' + ovTitle[o] + ' - ' + s.describe() : '')
    },
  })
  if (o < 16) for (var p = 0; p < 3; p++) (function (p) {
    var v = inVar('In Ov MP ' + (o + 1) + ' ' + XYZ[p], 10 + (o >> 3), ccOf(o, p))
    v.mOnProcessValueChange = function (dev, value) { set.set(dev, XYZ[p], value) }
  })(p)
  ovMp.push(set)
})(mo)

var bankPrev = inButton(15, 2, false), bankNext = inButton(15, 3, false)
// bank = 16 channels (the iPad shows 16, the 5:4 monitor up to 64): shift the zone 16 times
var lastMapping = null
page.mOnActivate = function (dev, mapping) { lastMapping = mapping }
function shift(dev, dir) {
  if (!lastMapping) { clog('Bank: noch keine aktive Seite'); return }
  var a = dir > 0 ? mixer.mAction.mShiftRight : mixer.mAction.mShiftLeft
  for (var i = 0; i < 16; i++) a.trigger(lastMapping)
  ovBank += dir
  ov(dev, [5, ovBank], undefined, true)
}
bankPrev.mSurfaceValue.mOnProcessValueChange = function (dev, value) { if (value > 0.5 && ovBank > 0) shift(dev, -1) }
bankNext.mSurfaceValue.mOnProcessValueChange = function (dev, value) { if (value > 0.5 && ovTitle[16] !== '') shift(dev, 1) }

// objects 16+ moved on a surface: SysEx F0 7D 4F 0A <kind> <obj> <part> <msb> <lsb> F7
midiIn.mOnSysex = function (dev, msg) {
  var m = msg
  if (!m || m[1] !== 0x7D || m[2] !== 0x4F || m[3] !== 10 || m.length < 10) return
  var kind = m[4], o = m[5], p = m[6], v = (m[7] * 128 + m[8]) / 16383
  if (o >= OV_N) return
  if (kind === 0 && ovSets[o]) ovSets[o].enc.set(dev, ovSets[o].encRoles[p], v)
  else if (kind === 1 && ovSets[o]) ovSets[o].rot.set(dev, ovSets[o].rotRoles[p], v)
  else if (kind === 2 && ovMp[o]) ovMp[o].set(dev, ['x', 'y', 'z'][p], v)
}

// track types (flags 16 FX, 32 group, 64 MIDI/instrument): extra zones that only read names
var typeTitles = { 16: {}, 32: {}, 64: {} }
function typeZone(name, bit, includeFn) {
  var z = includeFn(page.mHostAccess.mMixConsole.makeMixerBankZone(name))
  for (var i = 0; i < TZ_N; i++) (function (i) {
    var c = z.makeMixerBankChannel()
    var keep = driver.mSurface.makeCustomValueVariable(name + ' ' + (i + 1))
    page.makeValueBinding(keep, c.mValue.mSelected)        // keeps the channel (and its name) alive
    c.mOnTitleChange = function (dev, mapping, title) {
      var old = typeTitles[bit]['#' + i]
      if (old) delete typeTitles[bit][old]
      var t = String(title || '')
      typeTitles[bit]['#' + i] = t
      if (t) typeTitles[bit][t] = true
      typesDirty = true
    }
  })(i)
}
var typesDirty = false
typeZone('Type FX', 16, function (z) { return z.includeFXChannels() })
typeZone('Type Group', 32, function (z) { return z.includeGroupChannels() })
typeZone('Type Instr', 64, function (z) { return z.includeInstrumentChannels().includeSamplerChannels().includeMIDIChannels() })
function applyTypes(dev) {
  typesDirty = false
  for (var o = 0; o < OV_N; o++) {
    var t = ovTitle[o]
    setFlag(dev, o, 16, !!t && !!typeTitles[16][t])
    setFlag(dev, o, 32, !!t && !!typeTitles[32][t])
    setFlag(dev, o, 64, !!t && !!typeTitles[64][t])
  }
}

// === selected track: Panner (channel 16) + MultiEncoder inputs (channels 9/10) ==================
var PAN_CC = { az: 1, el: 2, wid: 4, yaw: 5, pitch: 6, roll: 7 }
var PAN_FIELD = { az: 1, el: 2, wid: 4, yaw: 5, pitch: 6, roll: 7 }
var selName = '', meCount = -1

var selGrp = SlotGroup('Sel', sel.mMixerChannel.mInsertAndStripEffects, K_SEL, {
  enc: function (dev, role, v, s) {
    if (PAN_CC[role]) { send14(dev, 15, PAN_CC[role], v); return }
    var m = /^i([aeg])(\d+)$/.exec(role)
    if (m) {
      var n = parseInt(m[2], 10)
      if (n >= 1 && n <= ME_N) send14(dev, 8 + ((n - 1) >> 3), ccOf(n - 1, { a: 0, e: 1, g: 2 }[m[1]]), v)
    } else if (role === 'nin') {
      var c = Math.round(v * 64)
      if (c !== meCount) { meCount = c; ov(dev, [9, Math.min(c, ME_N)], selName, true) }
    }
  },
  rot: function (dev, role, v) { if (PAN_CC[role]) send14(dev, 15, PAN_CC[role], v) },
  encDisp: function (dev, role, text) { if (PAN_FIELD[role]) pannerText(dev, 10 + PAN_FIELD[role], text) },
  rotDisp: function (dev, role, text) { if (PAN_FIELD[role]) pannerText(dev, 10 + PAN_FIELD[role], text) },
  encInfo: function (dev, s) {
    pannerText(dev, 20, s ? (PLUGIN_NAME[s.type] || s.plugin) : '')
    if (s) for (var r in PAN_FIELD) if (r === 'az' || r === 'el' || r === 'wid') {
      var i = s.idx[r]
      if (i !== undefined) pannerText(dev, PAN_FIELD[r], s.type === 'ME' ? 'Master ' + ROLE_NAME[r] : s.title[i])
    }
    if ((!s || s.type !== 'ME') && meCount !== 0) { meCount = 0; ov(dev, [9, 0], selName, true) }
  },
  rotInfo: function (dev, s) {
    pannerText(dev, 21, s ? (PLUGIN_NAME[s.type] || s.plugin) : '')
    if (s) for (var r in ROT_P) { var i = s.idx[r]; if (i !== undefined) pannerText(dev, PAN_FIELD[r], s.title[i]) }
    var d = selGrp ? selGrp.describe() : ''
    logLater('se', 'Gewaehlt: ' + selName + ' · ' + (d || 'kein Encoder/Rotator in Insert 5-9'))
  },
})
var selEnc = selGrp.encSet, selRot = selGrp.rotSet
sel.mMixerChannel.mOnTitleChange = function (dev, mapping, title) {
  selName = String(title || '')
  pannerText(dev, 0, title)
}

// inputs: panner CCs on channel 16 ...
for (var pr in PAN_CC) (function (role) {
  var v = inVar('In Pan ' + role, 15, PAN_CC[role])
  v.mOnProcessValueChange = function (dev, value) {
    if (ROT_P[role] !== undefined) selRot.set(dev, role, value)
    else selEnc.set(dev, role, value)
  }
})(pr)
// ... MultiEncoder inputs on channels 9/10
for (var mi = 1; mi <= ME_N; mi++) (function (n) {
  var kinds = ['a', 'e', 'g']
  for (var p = 0; p < 3; p++) (function (p) {
    var v = inVar('In ME ' + n + kinds[p], 8 + ((n - 1) >> 3), ccOf(n - 1, p))
    v.mOnProcessValueChange = function (dev, value) { selEnc.set(dev, 'i' + kinds[p] + n, value) }
  })(p)
})(mi)

// MultiPanner of the selected track (panner page): pitch bend, channel = parameter in panner order
// (X, Y, Z, Rot Z, Tilt Y, Tilt X, Distance, Divergence, Field Size, Size, Width, Depth), taken
// from whichever Quick Controls carry those parameters.
var lastPb = {}
var selMp = QcSet('Sel MP', sel.mMixerChannel.mQuickControls, {
  value: function (dev, role, v) {
    var c = MP_ROLE_IDX[role]
    var n = Math.round(Math.max(0, Math.min(1, v)) * 16383)
    if (lastPb[c] === n) return
    lastPb[c] = n
    midiOut.sendMidi(dev, [0xE0 + c, n & 127, n >> 7])
  },
  info: function (dev, s) { logLater('qc', 'Gewaehlt: ' + selName + ' - ' + (s.describe() || 'kein MultiPanner auf den Quick Controls')) },
})
for (var role in MP_ROLE_IDX) (function (role) {
  var v = driver.mSurface.makeCustomValueVariable('In Sel MP ' + role)
  v.mMidiBinding.setInputPort(midiIn).bindToPitchBend(MP_ROLE_IDX[role])
  v.mOnProcessValueChange = function (dev, value) { selMp.set(dev, role, value) }
})(role)
var prevTrack = inButton(15, 0, false), nextTrack = inButton(15, 1, false)
page.makeActionBinding(prevTrack.mSurfaceValue, sel.mAction.mPrevTrack)
page.makeActionBinding(nextTrack.mSurfaceValue, sel.mAction.mNextTrack)

// === life cycle ====================================================================================
function hello(dev) {
  ov(dev, [4], 'NUENDO', true)
  ov(dev, [5, ovBank], undefined, true)
  ov(dev, [12, OV_N], undefined, true)
  ovAlive = now()
}
driver.mOnActivate = function (dev) {
  clog('aktiv - sende an TouchOSC Bridge (Hallo, Spurnamen, Werte)')
  sentText = {}; sent14 = {}; sentX = {}; logSent = {}; lastPb = {}; dvSent = {}
  for (var i = 0; i < OV_N; i++) ovFlags[i] = 0
  ov(dev, [7], undefined, true)
  hello(dev)
  ov(dev, [8], 'hello|3D v5.5 aktiv · Encoder/dearVR PRO in Insert 5 oder 6, Rotator in Insert 5-9', true)
}
driver.mOnDeactivate = function (dev) {   // Nuendo closes / script stops: empty the surfaces
  clog('inaktiv - Oberflaechen geleert')
  ov(dev, [7], undefined, true)
  ov(dev, [4], '', true)
}
var idleSeen = false
driver.mOnIdle = function (dev) {              // Cubase/Nuendo 13+
  if (!idleSeen) { idleSeen = true; clog('mOnIdle laeuft') }
  flushLog(dev)
  if (typesDirty) applyTypes(dev)
  if (now() - ovAlive > 5000) hello(dev)
}
