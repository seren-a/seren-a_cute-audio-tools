--------------------------------------------------------------------------
-- BANK vor/zurück, leere Bänke überspringen (v8.4, gemeinsam)
-- Nach dem Wechsel kurz warten, bis die Spuren da sind. Steht auf der Bank nichts, was die Ansicht zeigt,
-- geht es automatisch weiter (höchstens 16 Bänke). Kommt kein Wechsel mehr, ist das Ende erreicht.
--------------------------------------------------------------------------
local BK = { skip = nil }
function BK.press(dir) local t = getMillis(); BK.skip = { dir = dir, t = t, sent = t, hops = 0, moved = false } end
function BK.onBank() if BK.skip then BK.skip.t = getMillis(); BK.skip.moved = true end end
function BK.cancel() BK.skip = nil end
function BK.step(count, send)                   -- count = Objekte, die die Ansicht auf dieser Bank zeigt
  local s = BK.skip
  if not s then return end
  local now = getMillis()
  if not s.moved then
    if now - s.sent > 1500 then BK.skip = nil end
    return
  end
  if now - s.t < 700 then return end
  if count > 0 or s.hops >= 16 then BK.skip = nil; return end
  s.hops = s.hops + 1; s.moved = false; s.sent = now
  send(s.dir)
end
