--[[ seren.a · Bridge-Test (TouchOSC 2)
  Zeigt JEDE MIDI-Nachricht, die ankommt (mit Verbindungsnummer), und schickt auf Knopfdruck
  Test-Nachrichten an alle MIDI-Verbindungen. Keine Abhängigkeiten, absichtlich simpel.
  Einstellung wie alle seren.a-Oberflächen: Bridge 1 = Mac, MIDI 1 Send + Receive = Bridge 1. ]]

local lines, total, last, dirty = {}, 0, nil, true
local counts = {}
local pings = 0

local function hex(m)
  local t = {}
  for i = 1, math.min(#m, 12) do t[#t + 1] = string.format('%02X', m[i]) end
  if #m > 12 then t[#t + 1] = '…(' .. #m .. ' Bytes)' end
  return table.concat(t, ' ')
end

local function text(m, from)
  local t = {}
  for i = from, #m - 1 do
    local c = m[i]
    if c >= 32 and c <= 126 then t[#t + 1] = string.char(c) end
  end
  return table.concat(t)
end

local KIND = { [0x8] = 'Note aus', [0x9] = 'Note', [0xA] = 'AT', [0xB] = 'CC', [0xC] = 'PC', [0xD] = 'ChAT', [0xE] = 'Pitchbend' }

local function describe(m)
  local st = m[1] or 0
  if st == 0xF0 then
    local who = ({ [0x4F] = 'seren.a 3D', [0x54] = 'seren.a Panner', [0x4D] = 'Twister View', [0x7E] = 'Test' })[m[3] or 0] or 'SysEx'
    return who .. ' ' .. string.format('cmd %d', m[4] or -1) .. ' "' .. text(m, 5) .. '"'
  end
  local k, ch = math.floor(st / 16), st % 16 + 1
  return (KIND[k] or '?') .. ' Kanal ' .. ch .. ' #' .. tostring(m[2]) .. ' = ' .. tostring(m[3])
end

local function add(s)
  table.insert(lines, 1, s)
  while #lines > 26 do table.remove(lines) end
  dirty = true
end

local function connList(connections)
  local t = {}
  if type(connections) == 'table' then
    for i = 1, 10 do if connections[i] then t[#t + 1] = tostring(i) end end
  end
  return #t > 0 and ('MIDI ' .. table.concat(t, '+')) or 'MIDI ?'
end

function onReceiveMIDI(m, connections)
  total = total + 1
  last = getMillis()
  local key = (m[1] == 0xF0) and ('sx' .. tostring(m[3])) or tostring(math.floor((m[1] or 0) / 16))
  counts[key] = (counts[key] or 0) + 1
  add(connList(connections) .. '  ←  ' .. describe(m) .. '   [' .. hex(m) .. ']')
  return false
end

local function sendTest()
  pings = pings + 1
  local all = { true, true, true, true, true, true, true, true, true, true }
  local s = { 0xF0, 0x7D, 0x7E, 1 }
  for c in ('PING ' .. pings):gmatch('.') do s[#s + 1] = c:byte() end
  s[#s + 1] = 0xF7
  sendMIDI(s, all)
  sendMIDI({ 0xBF, 119, pings % 128 }, all)
  sendMIDI({ 0x9F, 119, 127 }, all); sendMIDI({ 0x9F, 119, 0 }, all)
  add('→ an alle MIDI-Verbindungen gesendet: PING ' .. pings .. ' (SysEx, CC 119 Kanal 16, Note 119 Kanal 16)')
end

function onReceiveNotify(k, v)
  if k == 'btn' and v == 'ping' then sendTest()
  elseif k == 'btn' and v == 'clear' then lines = {}; total = 0; counts = {}; dirty = true end
end

function update()
  local now = getMillis()
  local st = root:findByName('status', true)
  if st then
    local age = last and math.floor((now - last) / 1000) or nil
    local s = 'empfangen: ' .. total .. ' Nachrichten'
    if age then s = s .. '  ·  letzte vor ' .. age .. ' s' else s = s .. '  ·  noch NICHTS angekommen' end
    s = s .. '\nSysEx 3D: ' .. (counts.sx79 or 0) .. '  ·  Panner-Text: ' .. (counts.sx84 or 0) ..
      '  ·  Twister: ' .. (counts.sx77 or 0) .. '  ·  CC: ' .. (counts['11'] or 0) ..
      '  ·  Noten: ' .. ((counts['9'] or 0) + (counts['8'] or 0)) .. '  ·  Pitchbend: ' .. (counts['14'] or 0)
    st.values.text = s
  end
  if dirty then
    dirty = false
    local c = root:findByName('log', true)
    if c then
      c.values.text = #lines > 0 and table.concat(lines, '\n') or '(noch nichts empfangen)'
    end
  end
end

function init() dirty = true end
