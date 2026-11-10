-- TouchOSC sandbox (manual: script-functions-lua): restricted base library, restricted os,
-- no io/debug/package/coroutine/load*; unknown globals are an error (TouchOSC: nil call errors).
do
  local keep_os = { clock = os.clock, date = os.date, difftime = os.difftime, time = os.time }
  local allowed = { error=1, ipairs=1, next=1, pairs=1, print=1, select=1, tonumber=1, tostring=1, unpack=1, type=1,
    string=1, table=1, math=1, os=1, bit32=1, utf8=1, _G=1, _VERSION=1 }
  local real = {}
  for k, v in pairs(_G) do real[k] = v end
  local smt, rg = setmetatable, rawget
  if not table.unpack then table.unpack = unpack end
  if not unpack then unpack = table.unpack end
  if not math.clamp then math.clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end end
  os = keep_os
  for _, k in ipairs({ 'pcall', 'xpcall', 'setmetatable', 'getmetatable', 'rawget', 'rawset', 'rawequal', 'rawlen',
      'assert', 'collectgarbage', 'load', 'loadstring', 'loadfile', 'dofile', 'require', 'getfenv', 'setfenv',
      'module', 'io', 'debug', 'package', 'coroutine', 'gcinfo', 'newproxy' }) do _G[k] = nil end
  local quiet = { debug = 1, package = 1, coroutine = 1, io = 1, jit = 1, python = 1 }   -- looked up by lupa itself
  smt(_G, { __index = function(_, k) if quiet[k] then return nil end error("TouchOSC: unbekannte globale Variable '" .. tostring(k) .. "'", 2) end })
end
