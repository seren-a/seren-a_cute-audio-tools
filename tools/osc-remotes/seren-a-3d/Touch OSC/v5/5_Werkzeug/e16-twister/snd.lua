-- ================================================================ Sends / Ziele (v8.0)
-- E16 page 1 (scene seren-a_E16, DAW-Link channels: in 16, out A = 16, B = 14) with sub-pages
-- Sends / Ziele / Spur / Menü (hold 16 = next) and Twister bank 4, layer 6 "Sends".
-- Replaces reaper_to_e16.lua (now the "Spur" sub-page) and e16-reverb-remote (Sends/Ziele).
-- Settings: ExtState "seren_E16" (window Reaper_E16_Einstellungen.lua or the E16 menu page),
-- targets: project ExtState "seren_E16/targets" (GUIDs), else the old reverb-remote assignment, else name prefix.
local function sndModule()
local SEXT = "seren_E16"
local SDEF = { capSend = "1", masterNav = "1", layout = "split", dedicated = "1", push = "prepost", preFx = "0", targets = "assigned", prefix = "RVB",
  cSend = "cyan", cPre = "weiss", cMute = "rot", cMeter = "pink", cFader = "hellblau", cMaster = "orange",
  cTrack = "weiss", triple = "1", dbl = "0", twister = "1", spur = "1" }
-- name, E16 slot text, full name, OXI App palette (E16), Twister colour map, RGB for the Twister View
local COLS = {
  { "cyan", "CYAN", "Cyan", 83, 20, "00CAFE" }, { "gruen", "GRUN", "Grün", 92, 51, "50FE03" },
  { "orange", "ORAN", "Pfirsich/Orange", 36, 68, "FE9F01" }, { "rot", "ROT", "Rot", 57, 83, "CF021C" },
  { "weiss", "WEIS", "Weiß", 34, 127, "D9D9D9" }, { "gelb", "GELB", "Gelb", 44, 64, "FFFF00" },
  { "pink", "PINK", "Pink", 50, 100, "FF4FA0" }, { "hellblau", "HBLA", "Hellblau", 18, 9, "6495ED" },
  { "violett", "VIOL", "Violett", 74, 118, "9370DB" }, { "tuerkis", "TURK", "Türkis", 85, 25, "02FFFF" },
}
local COLBY = {}
for i, c in ipairs(COLS) do COLBY[c[1]] = c; COLBY[i] = c end
local COLCH = {}
for _, c in ipairs(COLS) do COLCH[#COLCH + 1] = { c[1], c[2], c[3] } end
local OPTS = {
  { k = "layout", n = "LAYT", t = "Layout", ch = { { "split", "SPLT", "1-8 Sends / 9-16 Ziele" }, { "pages", "SEIT", "Seiten Sends + Ziele" } } },
  { k = "dedicated", n = "FEST", t = "Spur+Master", ch = { { "1", "FEST", "fest: Spur 15 (8), Master 16" }, { "0", "ALLE", "alles Sends" } } },
  { k = "push", n = "PUSH", t = "Push", ch = { { "prepost", "P/P", "Pre/Post, 2x Ziel" }, { "mute", "MUTE", "Mute, 2x Ziel" },
    { "mute_pp", "M+PP", "Mute, 2x Pre/Post" }, { "pp_mute", "PP+M", "Pre/Post, 2x Mute" } } },
  { k = "preFx", n = "PRFX", t = "Pre-FX", ch = { { "0", "AUS", "nicht mitschalten" }, { "1", "MIT", "mitschalten" } } },
  { k = "targets", n = "ZIEL", t = "Ziele", ch = { { "assigned", "ZUGW", "zugewiesen" }, { "sends", "SEND", "Sends der Spur" } } },
  { k = "cSend", n = "cSND", t = "Farbe Send", ch = COLCH, col = true },
  { k = "cPre", n = "cPRE", t = "Farbe Pre", ch = COLCH, col = true },
  { k = "cMute", n = "cMUT", t = "Farbe Mute", ch = COLCH, col = true },
  { k = "cMeter", n = "cMTR", t = "Farbe Meter", ch = COLCH, col = true },
  { k = "cFader", n = "cFDR", t = "Farbe Fader", ch = COLCH, col = true },
  { k = "cMaster", n = "cMAS", t = "Farbe Master", ch = COLCH, col = true },
  { k = "cTrack", n = "cSPU", t = "Farbe Spur", ch = COLCH, col = true },
  { k = "triple", n = "3xSP", t = "3x Spur", ch = { { "0", "AUS", "aus" }, { "1", "0/-i", "0 dB / -inf" } } },
  { k = "dbl", n = "2xSP", t = "2x Spur", ch = { { "0", "AUS", "aus" }, { "1", "MSND", "Master-Send an/aus" } } },
  { k = "twister", n = "TWST", t = "Twister Sends", ch = { { "1", "AN", "Ebene 6 an" }, { "0", "AUS", "Ebene 6 aus" } } },
  { k = "spur", n = "SPUR", t = "Spur-Seite", ch = { { "1", "AN", "an" }, { "0", "AUS", "aus" } } },
}
SND.OPTS, SND.COLS, SND.SDEF = OPTS, COLS, SDEF

local scfg, srev = {}, nil
local function loadCfg()
  for k, v in pairs(SDEF) do
    local s = r.GetExtState(SEXT, k)
    scfg[k] = s ~= "" and s or v
  end
end
local function setCfg(k, v)
  scfg[k] = v
  r.SetExtState(SEXT, k, v, true)
  srev = tostring(r.time_precise())
  r.SetExtState(SEXT, "rev", srev, false)
end
SND.cfg = scfg

local MIN_DB, MAX_DB, STEP_DB = -90, 6, 0.3
local MET_DB, MET_T, SHOW_FADER, BLINK_T = -60, 0.15, 1.2, 0.4
local HOLD_S, TAP_S = 0.45, 0.4
local A1, B1 = 0xBF, 0xBD                      -- E16 page 1: bank A = channel 16, bank B = channel 14
local S = { sub = 1, mftSub = 1, g = { e16 = {}, mft = {} }, turnAt = {}, lastTurn = {}, met = {}, metT = 0,
  lastUserG = nil, subFlash = 0 }

-- ------------------------------------------------------------ helpers
local function toDb(v) if v <= 0 then return MIN_DB end return max(MIN_DB, 20 * log(v, 10)) end
local function toVol(d) if d <= MIN_DB then return 0 end return 10 ^ (min(MAX_DB, d) / 20) end
local function dbRing(v)
  local d = toDb(v)
  if d <= -60 then return v > 0 and 1 or 0 end
  return floor(clamp((d + 60) / (MAX_DB + 60), 0, 1) * 126 + 1.5)
end
local function fmtDB4(v)                         -- max. 4 characters, as the slot wants
  if v <= 0 then return "-inf" end
  local d = toDb(v)
  local s
  if abs(d) < 0.05 then s = "0"
  elseif d > -10 and d < 10 then s = string.format("%.1f", d)
  else s = tostring(floor(d + 0.5)) end
  return s:sub(1, 4)
end
local function fmtDBf(v) if v <= 0 then return "-inf dB" end return string.format("%+.1f dB", toDb(v)) end
local function nm(t)
  if not t then return "" end
  if t == r.GetMasterTrack(0) then return "MASTER" end
  local _, n = r.GetTrackName(t)
  return n
end
local function four(s)
  s = s or ""
  local pre = scfg.prefix or ""
  if pre ~= "" and s:sub(1, #pre):lower() == pre:lower() and #s > #pre then s = s:sub(#pre + 1) end
  s = ascii(s):gsub("^[%s%-_:]+", "")
  return s:sub(1, 4)
end
local function guid(t) return r.GetTrackGUID(t) end
local function byGuid(g)
  if not g or g == "" then return nil end
  for i = 0, r.CountTracks(0) - 1 do local t = r.GetTrack(0, i); if guid(t) == g then return t end end
end
local function colOf(key) return COLBY[scfg[key]] or COLBY[SDEF[key]] end
local function selectOnly(t)
  for i = 0, r.CountTracks(0) - 1 do r.SetTrackSelected(r.GetTrack(0, i), false) end
  r.SetTrackSelected(r.GetMasterTrack(0), false)
  r.SetTrackSelected(t, true)
end

-- ------------------------------------------------------------ targets and the track the sends belong to
local function targets(eff)
  local out = {}
  if scfg.targets == "sends" then
    if eff then for i = 0, r.GetTrackNumSends(eff, 0) - 1 do out[#out + 1] = r.GetTrackSendInfo_Value(eff, 0, i, "P_DESTTRACK") end end
    return out
  end
  local _, list = r.GetProjExtState(0, SEXT, "targets")
  if list == "" then list = r.GetExtState("E16_REVERB_REMOTE", "guids") end
  if list ~= "" then
    local by = {}
    for i = 0, r.CountTracks(0) - 1 do local t = r.GetTrack(0, i); by[guid(t)] = t end
    for g in list:gmatch("[^,]+") do if by[g] and #out < 32 then out[#out + 1] = by[g] end end
    return out
  end
  local pre = (scfg.prefix or ""):lower()
  if pre == "" then return out end
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, n = r.GetTrackName(t)
    if n:sub(1, #pre):lower() == pre and #out < 32 then out[#out + 1] = t end
  end
  return out
end
local function isIn(t, T) for _, x in ipairs(T) do if x == t then return true end end return false end
local ctx = {}                                   -- per frame: eff, T, sel
local function refreshCtx()
  local sel = selTrack()
  local master = r.GetMasterTrack(0)
  local assigned = scfg.targets ~= "sends" and targets(nil) or {}
  local eff = sel
  if not sel or sel == master or isIn(sel, assigned) then
    if not S.lastUserG then local _, g = r.GetProjExtState(0, SEXT, "lastUser"); S.lastUserG = g ~= "" and g or nil end
    eff = byGuid(S.lastUserG)
  elseif guid(sel) ~= S.lastUserG then
    S.lastUserG = guid(sel)
    r.SetProjExtState(0, SEXT, "lastUser", S.lastUserG)
  end
  ctx.sel, ctx.eff, ctx.master = sel, eff, master
  ctx.T = scfg.targets == "sends" and targets(eff) or assigned
end
local function sendTo(src, dest)
  if not src or not dest then return nil end
  for i = 0, r.GetTrackNumSends(src, 0) - 1 do
    if r.GetTrackSendInfo_Value(src, 0, i, "P_DESTTRACK") == dest then return i end
  end
end

-- ------------------------------------------------------------ layouts
local function freeEnc(dev)
  local ded = scfg.dedicated == "1"
  local top, bot = {}, {}
  for e = 1, 16 do
    local skip
    if dev == "mft" then skip = ded and (e == 8 or e == 15 or e == 16)
    elseif ded then skip = scfg.layout == "split" and (e == 8 or e == 16) or (scfg.layout ~= "split" and (e == 15 or e == 16)) end
    if not skip then if e <= 8 then top[#top + 1] = e else bot[#bot + 1] = e end end
  end
  return top, bot
end
local function subs(dev)
  local top, bot = freeEnc(dev)
  local list = {}
  local nT = #ctx.T
  if scfg.layout == "split" then
    local n = min(#top, #bot)
    for g = 0, max(1, math.ceil(nT / n)) - 1 do list[#list + 1] = { kind = "split", g = g, n = n, top = top, bot = bot } end
  else
    local all = {}
    for _, e in ipairs(top) do all[#all + 1] = e end
    for _, e in ipairs(bot) do all[#all + 1] = e end
    for g = 0, max(1, math.ceil(nT / #all)) - 1 do
      list[#list + 1] = { kind = "S", g = g, n = #all, all = all }
      list[#list + 1] = { kind = "Z", g = g, n = #all, all = all }
    end
  end
  if dev == "e16" then
    if scfg.spur == "1" then list[#list + 1] = { kind = "spur" } end
    list[#list + 1] = { kind = "menu" }
  end
  return list
end
local function subName(sb)
  if not sb then return "" end
  if sb.kind == "split" then return string.format("Sends+Ziele %d-%d", sb.g * sb.n + 1, sb.g * sb.n + sb.n) end
  if sb.kind == "S" then return string.format("Sends %d-%d", sb.g * sb.n + 1, sb.g * sb.n + sb.n) end
  if sb.kind == "Z" then return string.format("Ziele %d-%d", sb.g * sb.n + 1, sb.g * sb.n + sb.n) end
  if sb.kind == "spur" then return "Spur" end
  return "Menue"
end
local function subKey(sb) return sb and (sb.kind .. (sb.g or "")) end
S.subKey = {}
local function curSub(dev)                       -- the sub-page stays the same one when the list changes
  local list = subs(dev)
  local k = dev == "e16" and S.sub or S.mftSub
  local want = S.subKey[dev]
  if want and subKey(list[k]) ~= want then
    local hit
    for i, sb in ipairs(list) do if subKey(sb) == want then hit = i end end
    k = hit or 1
  end
  if k > #list then k = 1 end
  if dev == "e16" then S.sub = k else S.mftSub = k end
  S.subKey[dev] = subKey(list[k])
  return list[k], list, k
end
local function slotMap(dev, sb)
  local m = {}
  if not sb then return m end
  if sb.kind == "split" then
    for i, e in ipairs(sb.top) do if i <= sb.n then m[e] = { k = "send", t = sb.g * sb.n + i } end end
    for i, e in ipairs(sb.bot) do if i <= sb.n then m[e] = { k = "tgt", t = sb.g * sb.n + i } end end
  elseif sb.kind == "S" or sb.kind == "Z" then
    for i, e in ipairs(sb.all) do m[e] = { k = sb.kind == "S" and "send" or "tgt", t = sb.g * sb.n + i } end
  elseif sb.kind == "menu" then
    for i = 1, #OPTS do m[i] = { k = "menu", o = i } end
  elseif sb.kind == "spur" then
    for i = 1, 16 do m[i] = { k = "spur", i = i } end
  end
  if scfg.dedicated == "1" and sb.kind ~= "menu" and sb.kind ~= "spur" then
    if dev == "e16" then
      -- v8.5: like the plugin pages – 15 (bzw. 8) = Spur, 16 = Master
      if scfg.layout == "split" then m[8], m[16] = { k = "track" }, { k = "master" }
      else m[15], m[16] = { k = "track" }, { k = "master" } end
    else m[8] = { k = "scroll" } end
  end
  return m
end
function SND.twisterOn() return scfg.twister ~= "0" end
function SND.owns(dev, e)
  if dev ~= "mft" then return true end
  return not (scfg.dedicated == "1" and (e == 15 or e == 16))
end

-- ------------------------------------------------------------ "Spur" sub-page (was reaper_to_e16.lua)
local SPUR_PROFILES = { { fx = "StereoEncoder", params = { "azimuth", "elevation", "roll", "width" } },
  { fx = "SceneRotator", params = { "yaw", "pitch", "roll" } } }
local SKIPW = { angle = true }
local function abbr(s)
  local w = {}
  for word in s:gmatch("%w+") do if not SKIPW[word:lower()] then w[#w + 1] = word end end
  if #w == 0 then return "" end
  if #w == 1 then return w[1]:sub(1, 4) end
  if w[2]:match("^%d") then return w[1]:sub(1, 3) .. w[2]:sub(1, 1) end
  return w[1]:sub(1, 2) .. w[2]:sub(1, 2)
end
local function shortText(s)
  local n = s:match("[-+]?%d+%.?%d*")
  if not n then return abbr(s) end
  local f = tonumber(n)
  if s:find(n .. "%s*[kK]") then f = f * 1000 end
  return fmt4(f, s)
end
local function fxSlot(tr, fx, p)
  local _, name = r.TrackFX_GetParamName(tr, fx, p, "")
  return { label = abbr(name), full = name,
    get = function() return r.TrackFX_GetParamNormalized(tr, fx, p) end, ring = function(v) return v end,
    text = function() local _, s = r.TrackFX_GetFormattedParamValue(tr, fx, p, ""); return s end,
    turn = function(d) r.TrackFX_SetParamNormalized(tr, fx, p, clamp(r.TrackFX_GetParamNormalized(tr, fx, p) + d * 0.005, 0, 1)) end }
end
local function onoff(v) return v > 0.5 and "On" or "Off" end
local SPUR_TRACK = {
  { "Vol", "Volume", "D_VOL", function(v) return fmtDBf(v) end, function(v) return dbRing(v) / 127 end,
    function(v, d) return toVol(toDb(v) + d * 0.5) end },
  { "Pan", "Pan", "D_PAN", function(v) return string.format("%.0f %%", v * 100) end, function(v) return (v + 1) / 2 end,
    function(v, d) return clamp(v + d * 0.01, -1, 1) end },
  { "Mute", "Mute", "B_MUTE", onoff, function(v) return v end },
  { "Solo", "Solo", "I_SOLO", onoff, function(v) return v > 0 and 1 or 0 end },
  { "Rec", "Rec arm", "I_RECARM", onoff, function(v) return v end },
  { "Phs", "Phase", "B_PHASE", onoff, function(v) return v end },
  { "Wdth", "Width", "D_WIDTH", function(v) return string.format("%.0f %%", v * 100) end, function(v) return (v + 1) / 2 end,
    function(v, d) return clamp(v + d * 0.01, -1, 1) end },
}
local function trackSlot(tr, e)
  local key = e[3]
  local function get() return r.GetMediaTrackInfo_Value(tr, key) end
  return { label = e[1], full = e[2], get = get, ring = e[5], text = function() return e[4](get()) end,
    turn = e[6] and function(d) r.SetMediaTrackInfo_Value(tr, key, e[6](get(), d)) end,
    push = (not e[6]) and function() r.SetMediaTrackInfo_Value(tr, key, get() > 0 and 0 or 1) end }
end
local spur = { sig = nil, at = 0, slots = {}, vals = {} }
local function spurBuild(tr)
  local s = {}
  if tr then
    local nTcp = r.CountTCPFXParms and r.CountTCPFXParms(0, tr) or 0
    if nTcp > 0 then
      for i = 0, min(nTcp, 16) - 1 do
        local ok, fx, p = r.GetTCPFXParm(0, tr, i)
        if ok then s[#s + 1] = fxSlot(tr, fx, p) end
      end
    else
      local hit
      for fx = 0, r.TrackFX_GetCount(tr) - 1 do
        local _, name = r.TrackFX_GetFXName(tr, fx, "")
        for _, pr in ipairs(SPUR_PROFILES) do
          if not hit and name:lower():find(pr.fx:lower(), 1, true) then hit = { fx, pr } end
        end
      end
      if hit then
        for _, pat in ipairs(hit[2].params) do
          for p = 0, r.TrackFX_GetNumParams(tr, hit[1]) - 1 do
            local _, pn = r.TrackFX_GetParamName(tr, hit[1], p, "")
            if pn:lower():find(pat, 1, true) then s[#s + 1] = fxSlot(tr, hit[1], p); break end
          end
        end
      else
        for _, e in ipairs(SPUR_TRACK) do s[#s + 1] = trackSlot(tr, e) end
      end
    end
  end
  spur.slots = s
end
local function spurUpdate(now)
  local tr = selTrack()
  local sig = tr and (guid(tr) .. ":" .. r.TrackFX_GetCount(tr) .. ":" .. (r.CountTCPFXParms and r.CountTCPFXParms(0, tr) or 0)) or "none"
  if sig ~= spur.sig or now - spur.at > 2 then
    if sig ~= spur.sig then spur.vals = {} end
    spur.sig, spur.at = sig, now
    spurBuild(tr)
  end
end

-- ------------------------------------------------------------ E16 page-1 output
local function e16a(cc, v, force) out(e16Out, A1, cc, v, force) end
local function e16b(cc, v, force) out(e16Out, B1, cc, v, force) end
local function txt(st, base, len, s, force)
  s = ascii(s or ""):sub(1, len)
  s = s .. string.rep(" ", len - #s)
  for i = 1, len do out(e16Out, st, base + i - 1, s:byte(i), force) end
end
local function flashE16(e, v4, full)
  if not e16Out then return end
  if full then txt(B1, 0, 15, full, true); out(e16Out, B1, 15, 1, true) end
  if v4 and e then txt(B1, 16 + (e - 1) * 4, 4, v4, true) end
end

-- ------------------------------------------------------------ slot state (shared by E16 and Twister)
-- returns name4, value4, full name, ring 0-127 or nil, colour entry, blink, value text
local function slotInfo(dev, e, d, now)
  if not d then return nil end
  local k = d.k
  if k == "send" then
    local dest = ctx.T[d.t]
    if not dest then return "", "", "", nil, colOf("cSend") end
    local name = nm(dest)
    local i = sendTo(ctx.eff, dest)
    if not i then return four(name), "--", name .. ": kein Send", nil, colOf("cSend"), false, "kein Send" end
    local v = r.GetTrackSendInfo_Value(ctx.eff, 0, i, "D_VOL")
    local muted = r.GetTrackSendInfo_Value(ctx.eff, 0, i, "B_MUTE") == 1
    local mode = floor(r.GetTrackSendInfo_Value(ctx.eff, 0, i, "I_SENDMODE"))
    local c = muted and colOf("cMute") or mode ~= 0 and colOf("cPre") or colOf("cSend")
    local mt = mode == 3 and " Pre" or mode == 1 and " PreFX" or ""
    return four(name), muted and "MUTE" or fmtDB4(v), "Send " .. name .. " " .. fmtDBf(v) .. mt .. (muted and " stumm" or ""),
      dbRing(v), c, muted, fmtDBf(v) .. mt .. (muted and " MUTE" or "")
  elseif k == "tgt" then
    local t = ctx.T[d.t]
    if not t then return "", "", "", nil, colOf("cMeter") end
    local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
    local muted = r.GetMediaTrackInfo_Value(t, "B_MUTE") == 1
    local key = dev .. e
    local show = now - (S.turnAt[key] or -1e9) < SHOW_FADER
    local ring, c = S.met[guid(t)] or 0, colOf("cMeter")
    if show then ring, c = dbRing(v), colOf("cFader")
    elseif muted then ring = dbRing(v) end           -- v8.5: muted blinks like on the plugin pages
    return four(nm(t)), muted and "MUTE" or fmtDB4(v), nm(t) .. " " .. fmtDBf(v) .. (muted and " stumm" or ""), ring, c,
      muted, fmtDBf(v) .. (muted and " MUTE" or "")
  elseif k == "master" then
    local m = ctx.master
    local v = r.GetMediaTrackInfo_Value(m, "D_VOL")
    local muted = r.GetMediaTrackInfo_Value(m, "B_MUTE") == 1
    return "MAST", muted and "MUTE" or fmtDB4(v), "Master " .. fmtDBf(v) .. (muted and " stumm" or ""), dbRing(v),
      muted and colOf("cMute") or colOf("cMaster"), muted, fmtDBf(v)
  elseif k == "track" then
    local t = ctx.sel
    if not t then return "----", "", "keine Spur", nil, colOf("cTrack") end
    local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
    local solo = r.GetMediaTrackInfo_Value(t, "I_SOLO") ~= 0
    local muted = r.GetMediaTrackInfo_Value(t, "B_MUTE") == 1
    local ms = r.GetMediaTrackInfo_Value(t, "B_MAINSEND") == 1
    local c = solo and COLBY.gelb or muted and colOf("cMute") or colOf("cTrack")
    return four(nm(t)), solo and "SOLO" or muted and "MUTE" or fmtDB4(v),
      nm(t) .. " " .. fmtDBf(v) .. (ms and "" or " (kein Master-Send)"), dbRing(v), c, muted or solo, fmtDBf(v)
  elseif k == "scroll" then
    local sb, list, idx = curSub("mft")
    return "", "", subName(sb), floor((idx - 1) / max(1, #list - 1) * 127 + 0.5), nil, false, "Ebene halten"
  elseif k == "menu" then
    local o = OPTS[d.o]
    local cur = 1
    for i, c in ipairs(o.ch) do if c[1] == scfg[o.k] then cur = i end end
    local c = o.col and COLBY[o.ch[cur][1]] or COLBY.weiss
    return o.n, o.ch[cur][2], o.t .. ": " .. o.ch[cur][3], floor((cur - 1) / max(1, #o.ch - 1) * 127 + 0.5), c, false, o.ch[cur][3]
  elseif k == "spur" then
    local s = spur.slots[d.i]
    if not s then return "", "", "", nil, COLBY.weiss end
    local v = s.get()
    return s.label, shortText(s.text()), s.full .. " " .. s.text(), floor(clamp(s.ring(v), 0, 1) * 127 + 0.5), COLBY.weiss,
      false, s.text()
  end
end

-- ------------------------------------------------------------ actions
local function accStep(key, delta, now)
  local d = abs(delta)
  local last = S.lastTurn[key]
  S.lastTurn[key] = now
  local m = d <= 1 and 1 or d == 2 and 1.5 or d <= 3 and 2 or d <= 5 and 3 or d <= 8 and 5 or 8
  if last and now - last < 0.04 then m = m * 2 end
  local s = min(m * STEP_DB, 6)
  return delta < 0 and -s or s
end
local function capped(v, nv, on)               -- v8.5: max 0 dB (what is already above stays, turning up never jumps down)
  if on and nv > 1 and nv > v then return math.max(v, 1) end
  return nv
end
local function volStep(t, dbs)
  local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
  r.SetMediaTrackInfo_Value(t, "D_VOL", capVol(t, v, toVol(toDb(v) + dbs)))
end
local function cycleMode(m)
  if scfg.preFx == "1" then return m == 0 and 3 or m == 3 and 1 or 0 end
  return m == 0 and 3 or 0
end
local MODE_TXT = { [0] = "POST", [3] = "PRE", [1] = "PRFX" }
local function undo(s) r.Undo_OnStateChange(s) end
local PUSHES = { prepost = { "pp", "jump" }, mute = { "mute", "jump" }, mute_pp = { "mute", "pp" }, pp_mute = { "pp", "mute" } }

local function tap(dev, e, d, n, now)
  if not d then return end
  local key = dev .. e
  if d.k == "send" then
    local dest = ctx.T[d.t]
    if not dest then return end
    local a = (PUSHES[scfg.push] or PUSHES.prepost)[min(n, 2)]
    if a == "jump" then selectOnly(dest); flashE16(nil, nil, "> " .. nm(dest)); return end
    local i = sendTo(ctx.eff, dest)
    if not i then flashE16(e, "OFF", nm(dest) .. ": kein Send"); return end
    if a == "mute" then
      local m = r.GetTrackSendInfo_Value(ctx.eff, 0, i, "B_MUTE") == 1
      r.SetTrackSendInfo_Value(ctx.eff, 0, i, "B_MUTE", m and 0 or 1)
      undo("E16: Send stumm"); flashE16(e, m and "AN" or "MUTE", "Send " .. nm(dest) .. (m and " an" or " stumm"))
    else
      local nmode = cycleMode(floor(r.GetTrackSendInfo_Value(ctx.eff, 0, i, "I_SENDMODE")))
      r.SetTrackSendInfo_Value(ctx.eff, 0, i, "I_SENDMODE", nmode)
      undo("E16: Send Pre/Post"); flashE16(e, MODE_TXT[nmode], "Send " .. nm(dest) .. " " .. MODE_TXT[nmode])
    end
  elseif d.k == "tgt" then
    local t = ctx.T[d.t]
    if not t then return end
    S.turnAt[key] = now
    if n >= 2 then selectOnly(t); flashE16(nil, nil, "> " .. nm(t)); return end
    local m = r.GetMediaTrackInfo_Value(t, "B_MUTE") == 1
    r.SetMediaTrackInfo_Value(t, "B_MUTE", m and 0 or 1)
    undo("E16: Ziel stumm"); flashE16(e, m and fmtDB4(r.GetMediaTrackInfo_Value(t, "D_VOL")) or "MUTE", nm(t) .. (m and " an" or " stumm"))
  elseif d.k == "master" then
    local m = ctx.master
    if n >= 2 then
      local mu = r.GetMediaTrackInfo_Value(m, "B_MUTE") == 1
      r.SetMediaTrackInfo_Value(m, "B_MUTE", mu and 0 or 1)
      undo("E16: Master stumm"); flashE16(e, mu and "AN" or "MUTE", "Master" .. (mu and " an" or " stumm"))
    else selectOnly(m); flashE16(nil, nil, "> MASTER") end
  elseif d.k == "track" then
    local t = ctx.sel
    if not t then return end
    if n >= 3 and scfg.triple == "1" then
      local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
      r.SetMediaTrackInfo_Value(t, "D_VOL", v > 0 and 0 or 1)
      undo("E16: Spur 0 dB/-inf"); flashE16(e, v > 0 and "-inf" or "0", nm(t) .. (v > 0 and " -inf" or " 0 dB"))
    elseif n == 2 and scfg.dbl == "1" then
      local on = r.GetMediaTrackInfo_Value(t, "B_MAINSEND") == 1
      r.SetMediaTrackInfo_Value(t, "B_MAINSEND", on and 0 or 1)
      undo("E16: Master-Send"); flashE16(e, on and "MS-" or "MS+", nm(t) .. " Master-Send " .. (on and "aus" or "an"))
    else
      local so = r.GetMediaTrackInfo_Value(t, "I_SOLO") ~= 0
      r.SetMediaTrackInfo_Value(t, "I_SOLO", so and 0 or SOLO_MODE)
      undo("E16: Spur solo"); flashE16(e, so and "solo" or "SOLO", nm(t) .. (so and " solo aus" or " SOLO"))
    end
  elseif d.k == "menu" then
    local o = OPTS[d.o]
    local cur = 1
    for i, c in ipairs(o.ch) do if c[1] == scfg[o.k] then cur = i end end
    local c = o.ch[cur % #o.ch + 1]
    setCfg(o.k, c[1]); flashE16(e, c[2], o.t .. ": " .. c[3])
  elseif d.k == "spur" then
    local s = spur.slots[d.i]
    if s and s.push then s.push(); flashE16(e, shortText(s.text()), s.full .. " " .. s.text()) end
  end
end
local function maxTaps(d)
  if not d then return 0 end
  if d.k == "track" then return scfg.triple == "1" and 3 or scfg.dbl == "1" and 2 or 1 end
  if d.k == "send" or d.k == "tgt" or d.k == "master" then return 2 end
  if d.k == "menu" then return 1 end
  if d.k == "spur" then local s = spur.slots[d.i]; return (s and s.push) and 1 or 0 end
  return 0
end
local function nextSub(dev, dir)
  local _, list, k = curSub(dev)
  k = (k - 1 + (dir or 1)) % #list + 1
  S.subKey[dev] = subKey(list[k])
  if dev == "e16" then S.sub = k; S.subFlash = r.time_precise()
    flashE16(nil, nil, subName(list[k]))
  else
    S.mftSub = k
    viewSysex({ 6, MFT_BANK }, "Sends · " .. subName(list[k]))
  end
  mftForce = true
end
SND.nextSub = nextSub

local function turnSlot(dev, e, d, delta, now)
  if not d then return end
  local key = dev .. e
  if d.k == "send" then
    local dest = ctx.T[d.t]
    if not dest or not ctx.eff or ctx.eff == dest then return end
    local i = sendTo(ctx.eff, dest)
    if not i then
      if scfg.targets == "sends" or delta <= 0 then flashE16(e, "--", nm(dest) .. ": kein Send"); return end
      i = r.CreateTrackSend(ctx.eff, dest)      -- missing send: created on the first turn up
      r.SetTrackSendInfo_Value(ctx.eff, 0, i, "D_VOL", 0)
    end
    local v = r.GetTrackSendInfo_Value(ctx.eff, 0, i, "D_VOL")
    local nv = capped(v, toVol(toDb(v) + accStep(key, delta, now)), scfg.capSend == "1")
    r.SetTrackSendInfo_Value(ctx.eff, 0, i, "D_VOL", nv)
    undo("E16: Send-Pegel")
    flashE16(e, fmtDB4(nv), "Send " .. nm(dest) .. " " .. fmtDBf(nv))
  elseif d.k == "tgt" then
    local t = ctx.T[d.t]
    if not t then return end
    S.turnAt[key] = now
    volStep(t, accStep(key, delta, now)); undo("E16: Ziel-Pegel")
    local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
    flashE16(e, fmtDB4(v), nm(t) .. " " .. fmtDBf(v))
  elseif d.k == "master" then
    local g = S.g[dev][e]
    if scfg.masterNav == "1" and not (g and g.down) then navigate(delta > 0 and 1 or -1); return end   -- like the MultiEQ: turn = track, press + turn = master
    volStep(ctx.master, accStep(key, delta, now)); undo("E16: Master-Pegel")
    local v = r.GetMediaTrackInfo_Value(ctx.master, "D_VOL")
    flashE16(e, fmtDB4(v), "Master " .. fmtDBf(v))
  elseif d.k == "track" then
    local g = S.g[dev][e]
    if g and g.down then navigate(delta > 0 and 1 or -1); return end   -- press + turn = select the next track
    local t = ctx.sel
    if not t then return end
    volStep(t, accStep(key, delta, now)); undo("E16: Spur-Pegel")
    local v = r.GetMediaTrackInfo_Value(t, "D_VOL")
    flashE16(e, fmtDB4(v), nm(t) .. " " .. fmtDBf(v))
  elseif d.k == "scroll" then nextSub("mft", delta > 0 and 1 or -1)
  elseif d.k == "menu" then
    local o = OPTS[d.o]
    local cur = 1
    for i, c in ipairs(o.ch) do if c[1] == scfg[o.k] then cur = i end end
    local nx = clamp(cur + (delta > 0 and 1 or -1), 1, #o.ch)
    if nx ~= cur then setCfg(o.k, o.ch[nx][1]) end
    flashE16(e, o.ch[nx][2], o.t .. ": " .. o.ch[nx][3])
  elseif d.k == "spur" then
    local s = spur.slots[d.i]
    if s and s.turn then s.turn(delta); flashE16(e, shortText(s.text()), s.full .. " " .. s.text()) end
  end
end

-- ------------------------------------------------------------ gestures
function SND.input(dev, e, kind, val, now)
  refreshCtx()
  local sb = curSub(dev)
  local map = slotMap(dev, sb)
  local d = map[e]
  local g = S.g[dev][e] or {}
  S.g[dev][e] = g
  if kind == "press" then
    if val then g.down, g.t0, g.moved, g.long = true, now, false, false; return end
    if not g.down then return end
    g.down = false
    if g.moved or g.long then g.taps = 0; return end
    local most = maxTaps(d)
    if most == 0 then return end
    g.taps = (g.taps or 0) + 1
    g.tapT = now
    if g.taps >= most then local n = g.taps; g.taps = 0; tap(dev, e, d, n, now) end
    return
  end
  if val == 0 then return end
  if dev == "mft" then val = clamp(val, -3, 3) end
  if g.down then
    if now - g.t0 < PRESS_SETTLE then return end
    g.moved = true
  end
  if dev == "mft" and e == 8 and g.down then nextSub("mft", val > 0 and 1 or -1); return end   -- press + turn 8 = group
  turnSlot(dev, e, d, val, now)
end
local function longPress(dev, e)
  if dev == "e16" and e == 16 then nextSub("e16", 1)
  elseif dev == "mft" and e == 8 then nextLayer("mft") end
end
function SND.tick(now)
  for _, dev in ipairs({ "e16", "mft" }) do
    for e, g in pairs(S.g[dev]) do
      if g.down and not g.moved and not g.long and now - g.t0 >= HOLD_S then g.long = true; g.taps = 0; longPress(dev, e) end
      if not g.down and (g.taps or 0) > 0 and now - g.tapT > TAP_S then
        local n = g.taps; g.taps = 0
        refreshCtx()
        tap(dev, e, slotMap(dev, curSub(dev))[e], n, now)
      end
    end
  end
end

-- ------------------------------------------------------------ rendering
local function meters(now)
  if now - S.metT < MET_T then return end
  S.metT = now
  for _, t in ipairs(ctx.T) do
    local nch = clamp(floor(r.GetMediaTrackInfo_Value(t, "I_NCHAN")), 1, 64)
    local peak = 0
    for c = 0, nch - 1 do local p = r.Track_GetPeakInfo(t, c); if p > peak then peak = p end end
    local d = peak > 0 and 20 * log(peak, 10) or -150
    S.met[guid(t)] = d <= MET_DB and 0 or d >= 0 and 127 or floor(1 + (d - MET_DB) * 126 / -MET_DB + 0.5)
  end
end
local ringOff = {}
local function renderE16Page1(now, force)
  if not e16Out then return end
  local sb = curSub("e16")
  local map = slotMap("e16", sb)
  if sb and sb.kind == "spur" then spurUpdate(now) end
  local phase = floor(now / BLINK_T) % 2 == 0
  local title
  if sb and sb.kind == "menu" then title = "MENUE E16"
  elseif sb and sb.kind == "spur" then local t = ctx.sel; title = t and (floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER")) .. " " .. nm(t)) or "keine Spur"
  else
    title = ctx.eff and nm(ctx.eff) or "keine Spur"
    if ctx.eff and ctx.sel ~= ctx.eff then title = "<" .. title end
  end
  txt(A1, 0, 15, title, force)
  for e = 1, 16 do
    local name, _, _, ring, c, blink = slotInfo("e16", e, map[e], now)
    txt(A1, 16 + (e - 1) * 4, 4, name or "", force)
    if c then e16a(79 + e, c[4], force) end
    if ring and not (blink and not phase) then e16b(79 + e, ring, force or ringOff[e]); ringOff[e] = false
    else e16b(95 + e, 0, force or not ringOff[e]); ringOff[e] = true end       -- resend: the E16 caches nothing
  end
end
function SND.renderMft(e, force)
  local sb = curSub("mft")
  local map = slotMap("mft", sb)
  local d = map[e]
  local now = r.time_precise()
  local name, v4, full, ring, c, blink, vt = slotInfo("mft", e, d, now)
  local cc = MFT_CC + e - 1
  local col, anim, ind = 0, DIM_OFF, 70
  if d and d.k == "scroll" then col, anim, ind = LAYER_COL[6], 0, 95
  elseif e == 8 then col, anim, ind = LAYER_COL[6], ring and 0 or DIM_OFF, 95   -- 8 keeps the layer colour
  elseif c and ring then col, anim, ind = c[5], 0, 95 end
  if blink then anim = BLINK end
  out(mftOut, 0xB0 + MFT_TURN_CH, cc, ring or 0, force)
  out(mftOut, 0xB0 + MFT_COL_CH, cc, col, force)
  out(mftOut, 0xB0 + MFT_ANIM_CH, cc, anim, force)
  out(mftOut, 0xB0 + MFT_RING_CH, cc, ind, force)
  local label = ""
  if d and d.k == "scroll" then label = subName(sb) .. "\nhalten = Ebene"
  elseif d and (d.k == "send" or d.k == "tgt") then
    local t = ctx.T[d.t]
    label = t and (nm(t) .. "\n" .. (d.k == "send" and "Send" or "Ziel")) or ""
  end
  view(e, label, vt or "", ring or 0, force)
  viewColor(e, c and c[6] or "6495ED", force)
end
function SND.frame(now, full)
  local rev = r.GetExtState(SEXT, "rev")
  if rev ~= srev then srev = rev; loadCfg(); mftForce = true; full = true end
  refreshCtx()
  meters(now)
  renderE16Page1(now, full)
  if mftLayer == 6 and not SND.twisterOn() then mftLayer = 1; mftForce = true end
end
function SND.init()
  loadCfg()
  srev = r.GetExtState(SEXT, "rev")
  refreshCtx()
  if e16Out then out(e16Out, A1, 127, 0, true) end
  local T = ctx.T
  msg(string.format("Sends/Ziele: %d Ziel(e)%s · Layout %s · E16 Seite 1 = Sends/Ziele/Spur/Menü (16 halten)",
    #T, scfg.targets == "sends" and " (Sends der Spur)" or "", scfg.layout))
end
function SND.exit()
  if e16Out then r.SendMIDIMessageToHardware(e16Out, string.char(A1, 127, 0)) end
end
SND.ctx, SND.S, SND.curSub, SND.slotMap, SND.slotInfo, SND.setCfg = ctx, S, curSub, slotMap, slotInfo, setCfg
end
sndModule()
