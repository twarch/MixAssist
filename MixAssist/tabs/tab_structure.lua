-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- tabs/tab_structure.lua — ReaOrganizer
-- Structure tab: song markers and regions.
-- ============================================================

local T = {}

-- Section colors (R,G,B) for buttons AND timeline markers
local COLORS = {
  INT = { btn = { 60,  100, 160 }, marker = 0x3C64A0 },  -- Light blue
  PC  = { btn = { 180, 150,  30 }, marker = 0xB4961E },  -- Yellow
  BR  = { btn = { 120,  50, 160 }, marker = 0x7832A0 },  -- Purple
  SLO = { btn = {  30, 160, 160 }, marker = 0x1EA0A0 },  -- Cyan
  OUT = { btn = {  70,  90, 110 }, marker = 0x465A6E },  -- Blue grey
  V   = { btn = {  40, 130,  60 }, marker = 0x28823C },  -- Green
  VA  = { btn = {  30,  90,  45 }, marker = 0x1E5A2D },  -- Dark green
  VB  = { btn = {  30,  90,  45 }, marker = 0x1E5A2D },  -- Dark green
  C   = { btn = { 190,  80,  30 }, marker = 0xBE501E },  -- Orange
  CA  = { btn = { 140,  40,  30 }, marker = 0x8C281E },  -- Dark red
  CB  = { btn = { 140,  40,  30 }, marker = 0x8C281E },  -- Dark red
}

local function to_native(hex)
  local r = (hex >> 16) & 0xFF
  local g = (hex >> 8)  & 0xFF
  local b =  hex        & 0xFF
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function push_color(ctx, H, key)
  local c   = COLORS[key].btn
  local col = H.rgb_to_imgui(c[1], c[2], c[3])
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  H.lighten(col, 35))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   col)
end

local function count_markers(prefix)
  local count = 0
  local i = 0
  repeat
    local retval, isrgn, _, _, name = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and not isrgn then
      if name:match("^" .. prefix .. "%d+$") then count = count + 1 end
    end
    i = i + 1
  until retval == 0
  return count
end

local function count_ab_groups(prefix)
  local max_num = 0
  local i = 0
  repeat
    local retval, isrgn, _, _, name = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and not isrgn then
      local num = name:match("^" .. prefix .. "(%d+)[AB]$")
      if num then
        local n = tonumber(num)
        if n > max_num then max_num = n end
      end
    end
    i = i + 1
  until retval == 0
  return max_num
end

local function ab_a_exists(prefix, group_num)
  local i = 0
  repeat
    local retval, isrgn, _, _, name = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and not isrgn then
      if name == prefix .. group_num .. "A" then return true end
    end
    i = i + 1
  until retval == 0
  return false
end

local function ab_b_exists(prefix, group_num)
  local i = 0
  repeat
    local retval, isrgn, _, _, name = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and not isrgn then
      if name == prefix .. group_num .. "B" then return true end
    end
    i = i + 1
  until retval == 0
  return false
end

local function add_marker(name, color_key)
  reaper.AddProjectMarker2(0, false, reaper.GetCursorPosition(), 0, name, -1,
    to_native(COLORS[color_key].marker))
  reaper.UpdateArrange()
end

function T.render(ctx, state)
  local btn_w   = state.btn_w
  local H       = state.H
  local set_log = state.set_log
  local spacing = 8

  local half_w = math.floor((btn_w - spacing) / 2)

  local function full_btn(label, id, color_key, on_click)
    push_color(ctx, H, color_key)
    if reaper.ImGui_Button(ctx, label .. "##" .. id, btn_w, 24) then on_click() end
    reaper.ImGui_PopStyleColor(ctx, 3)
  end

  local function half_btn(label, id, color_key, on_click)
    push_color(ctx, H, color_key)
    if reaper.ImGui_Button(ctx, label .. "##" .. id, half_w, 22) then on_click() end
    reaper.ImGui_PopStyleColor(ctx, 3)
  end

  reaper.ImGui_Spacing(ctx)

  -- Intro
  full_btn("Intro", "intro", "INT", function()
    add_marker("INT", "INT"); set_log("Marker: INT")
  end)
  reaper.ImGui_Spacing(ctx)

  -- Verse + Verse B
  half_btn("Verse", "vs", "V", function()
    local n = "V" .. (count_markers("V") + 1)
    add_marker(n, "V"); set_log("Marker: " .. n)
  end)
  reaper.ImGui_SameLine(ctx)
  half_btn("Verse B", "vb", "VB", function()
    local g = count_markers("V")
    local n = "V" .. math.max(g, 1) .. "B"
    add_marker(n, "VB"); set_log("Marker: " .. n)
  end)
  reaper.ImGui_Spacing(ctx)

  -- Pre-Chorus
  full_btn("Pre-Chorus", "pc", "PC", function()
    local n = "PC" .. (count_markers("PC") + 1)
    add_marker(n, "PC"); set_log("Marker: " .. n)
  end)
  reaper.ImGui_Spacing(ctx)

  -- Chorus + Chorus B
  half_btn("Chorus", "ch", "C", function()
    local n = "C" .. (count_markers("C") + 1)
    add_marker(n, "C"); set_log("Marker: " .. n)
  end)
  reaper.ImGui_SameLine(ctx)
  half_btn("Chorus B", "cb", "CB", function()
    local g = count_markers("C")
    local n = "C" .. math.max(g, 1) .. "B"
    add_marker(n, "CB"); set_log("Marker: " .. n)
  end)
  reaper.ImGui_Spacing(ctx)

  -- Bridge
  full_btn("Bridge", "br", "BR", function()
    local n = "BR" .. (count_markers("BR") + 1)
    add_marker(n, "BR"); set_log("Marker: " .. n)
  end)
  reaper.ImGui_Spacing(ctx)

  -- Solo
  full_btn("Solo", "slo", "SLO", function()
    local n = "SLO" .. (count_markers("SLO") + 1)
    add_marker(n, "SLO"); set_log("Marker: " .. n)
  end)
  reaper.ImGui_Spacing(ctx)

  -- Outro
  full_btn("Outro", "out", "OUT", function()
    add_marker("OUT", "OUT"); set_log("Marker: OUT")
  end)
  reaper.ImGui_Spacing(ctx)

  -- End (needed for last region)
  full_btn("End", "end", "OUT", function()
    add_marker("END", "OUT"); set_log("Marker: END")
  end)
  reaper.ImGui_Spacing(ctx)

  -- Custom marker
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  local input_w = btn_w - 80 - spacing
  reaper.ImGui_SetNextItemWidth(ctx, input_w)
  local cm, vm = reaper.ImGui_InputText(ctx, "##custommarker",
    state.buf_custom_marker, 32)
  if cm then state.buf_custom_marker = vm end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Add##mkr", 80, 0) then
    local txt = state.buf_custom_marker
    if txt and txt ~= "" then
      reaper.AddProjectMarker2(0, false, reaper.GetCursorPosition(), 0, txt, -1, 0)
      reaper.UpdateArrange()
      set_log("Marker: " .. txt)
    end
  end
  reaper.ImGui_Spacing(ctx)

  if reaper.ImGui_Button(ctx, "Create regions from markers", btn_w, 24) then
    local action = reaper.NamedCommandLookup("_SWSMARKERLIST13")
    if action == 0 then
      set_log("Error: SWS not found")
    else
      -- Get project start/end before creating regions
      local proj_start = 0
      local proj_end   = 0

      -- Find END marker position and project bounds
      local end_marker_idx = -1
      local i = 0
      repeat
        local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers3(0, i)
        if retval > 0 and not isrgn and name == "END" then
          end_marker_idx = idx
          proj_end = pos
        end
        if retval > 0 and not isrgn and name == "INT" then
          proj_start = pos
        end
        i = i + 1
      until retval == 0

      -- Create regions from markers (SWS)
      reaper.Main_OnCommand(action, 0)

      -- Delete END marker
      if end_marker_idx >= 0 then
        reaper.DeleteProjectMarker(0, end_marker_idx, false)
      end

      -- Add Full Song region on lane 1
      if proj_end > proj_start then
        reaper.AddProjectMarker2(0, true, proj_start, proj_end, "Full Song", -1, 0)
        reaper.UpdateArrange()

        -- Find Full Song by enum index (0-based) for MARKER_LANE
        local j = 0
        repeat
          local retval2, isrgn2, _, _, name2, idx2 =
            reaper.EnumProjectMarkers3(0, j)
          if retval2 > 0 and isrgn2 and name2 == "Full Song" then
            -- Try both the marker idx and the enum index
            reaper.GetSetProjectInfo(0, "MARKER_LANE:" .. j, 1, true)
            reaper.GetSetProjectInfo(0, "MARKER_LANE:" .. idx2, 1, true)
            break
          end
          j = j + 1
        until retval2 == 0
      end

      reaper.UpdateArrange()
      set_log("Regions created + Full Song")
    end
  end
end

return T
