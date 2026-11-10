-- ---------------------------------------------------------------- seren.a look (colours of the TouchOSC surfaces)
local LOOKS = {
  { name = "IEM Neon", ground = 0x0E0B1F, cell = 0x17122F, track = 0x2B2350, txt = 0xF4F0FF, dim = 0xA99FD0, acc = 0x29E7FF },
  { name = "Neon", ground = 0x0E0B1F, cell = 0x17122F, track = 0x2B2350, txt = 0xF4F0FF, dim = 0xA99FD0, acc = 0xFF3D9A },
  { name = "Kawaii Nacht", ground = 0x231628, cell = 0x2E1D35, track = 0x4A2C55, txt = 0xFFE8F4, dim = 0xD7A6C6, acc = 0xFF8FC0 },
  { name = "Klar", ground = 0x0B0C0F, cell = 0x17191E, track = 0x22252B, txt = 0xF2F4F7, dim = 0x8B93A1, acc = 0x36D0C4 },
}
local IEM = { cyan = 0x00CAFE, green = 0x50FE03, orange = 0xFE9F01, red = 0xCF021C, white = 0xFFFFFF, pink = 0xFF4FA0 }
local SECTION = { IEM.cyan, IEM.green, IEM.orange, IEM.pink, IEM.red }
local function rgba(c, a) return (c << 8) | (a or 0xFF) end
local function mix(a, b, t)
  local function ch(x, s) return (x >> s) & 0xFF end
  local function m(s) return math.floor(ch(a, s) + (ch(b, s) - ch(a, s)) * t + 0.5) end
  return (m(16) << 16) | (m(8) << 8) | m(0)
end
local function curLook()
  local n = reaper.GetExtState("seren_look", "imgui")
  for _, L in ipairs(LOOKS) do if L.name == n then return L end end
  return LOOKS[1]
end
local themeN, sectionN = 0, 0
local function pushTheme(ctx)
  local L, r = curLook(), reaper
  local cols = {
    { r.ImGui_Col_WindowBg(), L.ground }, { r.ImGui_Col_ChildBg(), L.ground }, { r.ImGui_Col_PopupBg(), L.cell },
    { r.ImGui_Col_TitleBg(), L.ground }, { r.ImGui_Col_TitleBgActive(), L.track }, { r.ImGui_Col_TitleBgCollapsed(), L.ground },
    { r.ImGui_Col_FrameBg(), L.cell }, { r.ImGui_Col_FrameBgHovered(), L.track }, { r.ImGui_Col_FrameBgActive(), mix(L.track, L.acc, 0.3) },
    { r.ImGui_Col_Button(), L.track }, { r.ImGui_Col_ButtonHovered(), mix(L.track, L.acc, 0.45) }, { r.ImGui_Col_ButtonActive(), L.acc },
    { r.ImGui_Col_Header(), L.track }, { r.ImGui_Col_HeaderHovered(), mix(L.track, L.acc, 0.45) }, { r.ImGui_Col_HeaderActive(), L.acc },
    { r.ImGui_Col_CheckMark(), L.acc }, { r.ImGui_Col_SliderGrab(), L.acc }, { r.ImGui_Col_SliderGrabActive(), L.txt },
    { r.ImGui_Col_Separator(), L.track }, { r.ImGui_Col_Border(), L.track }, { r.ImGui_Col_Text(), L.txt },
    { r.ImGui_Col_TextDisabled(), L.dim },
  }
  for _, c in ipairs(cols) do r.ImGui_PushStyleColor(ctx, c[1], rgba(c[2])) end
  themeN = #cols
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 6)
  sectionN = 0
end
local function popTheme(ctx)
  reaper.ImGui_PopStyleVar(ctx, 3)
  reaper.ImGui_PopStyleColor(ctx, themeN)
end
local function section(ctx, label)                -- section heading in the next IEM colour
  sectionN = sectionN % #SECTION + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), rgba(SECTION[sectionN]))
  reaper.ImGui_SeparatorText(ctx, label)
  reaper.ImGui_PopStyleColor(ctx, 1)
end
local function lookPicker(ctx)
  local L = curLook()
  local names, idx = {}, 0
  for i, x in ipairs(LOOKS) do names[i] = x.name; if x == L then idx = i - 1 end end
  reaper.ImGui_SetNextItemWidth(ctx, 150)
  local ch, n = reaper.ImGui_Combo(ctx, "Look", idx, table.concat(names, "\0") .. "\0")
  if ch then reaper.SetExtState("seren_look", "imgui", LOOKS[n + 1].name, true) end
end
local function swatch(ctx, id, hex)             -- small colour field
  reaper.ImGui_ColorButton(ctx, id, rgba(hex), reaper.ImGui_ColorEditFlags_NoTooltip(), 14, 14)
  reaper.ImGui_SameLine(ctx)
end
