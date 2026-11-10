
sent = {}
clock = 0
function getMillis() return clock end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a} end
function Rectangle(x,y,w,h) return {x=x,y=y,w=w,h=h} end
function sendOSC(msg, conns)
  local ci = 0
  for i=1,#conns do if conns[i] then ci = i end end
  local args = {}
  for i=1,#msg[2] do args[#args+1] = msg[2][i].value end
  sent[#sent+1] = {kind='osc', conn=ci, path=msg[1], args=args}
end
function sendMIDI(m, conns)
  sent[#sent+1] = {kind='midi', bytes={m[1],m[2],m[3]}}
end
controls = {}
function makeControl(name, ctype, x,y,w,h, visible)
  local c = {name=name, type=ctype, values={x=0, y=0, text='', touch=false},
             frame={x=x,y=y,w=w,h=h}, color=nil, visible=visible}
  c.notify = function(self, key, value) _G.onReceiveNotify(key, value) end
  controls[name] = c
  return c
end
root = { findByName = function(self, name, rec) return controls[name] end }
root.notify = function(self, key, value) onReceiveNotify(key, value) end
