-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- lib/theme.lua — ReaOrganizer
-- Theme management: colors stored via ExtState.
-- ============================================================

local TH = {}

local EXT_KEY = "SessionPrepare_Theme"

-- Default theme
local DEFAULTS = {
  bg          = { 0.12, 0.12, 0.14, 1.0 },
  bg_child    = { 0.10, 0.10, 0.12, 1.0 },
  accent      = { 0.20, 0.45, 0.75, 1.0 },
  accent_hov  = { 0.25, 0.55, 0.90, 1.0 },
  tab_active  = { 0.20, 0.45, 0.75, 1.0 },
  text        = { 0.90, 0.90, 0.90, 1.0 },
  text_dim    = { 0.55, 0.55, 0.55, 1.0 },
  separator   = { 0.28, 0.28, 0.32, 1.0 },
  frame_bg    = { 0.18, 0.18, 0.22, 1.0 },
  header      = { 0.20, 0.20, 0.25, 1.0 },
  -- Boutons
  btn_primary = { 0.16, 0.31, 0.55, 1.0 },  -- QB, principal
  btn_done    = { 0.14, 0.31, 0.14, 1.0 },  -- déjà fait (vert)
  btn_default = { 0.27, 0.27, 0.31, 1.0 },  -- Set FX non fait
  btn_danger  = { 0.31, 0.12, 0.12, 1.0 },  -- Remove, destructif
  btn_ara     = { 0.28, 0.22, 0.08, 1.0 },  -- ARA plugins
  btn_commit  = { 0.31, 0.20, 0.06, 1.0 },  -- Commit
  btn_master  = { 0.35, 0.12, 0.12, 1.0 },  -- Master FX
  btn_progress= { 0.29, 0.61, 0.35, 1.0 },  -- barre QB
}

local function pack(t)
  return string.format("%.3f,%.3f,%.3f,%.3f", t[1], t[2], t[3], t[4])
end

local function unpack_color(s)
  local r, g, b, a = s:match("([^,]+),([^,]+),([^,]+),([^,]+)")
  return { tonumber(r), tonumber(g), tonumber(b), tonumber(a) }
end

function TH.load()
  local theme = {}
  for k, default in pairs(DEFAULTS) do
    local stored = reaper.GetExtState(EXT_KEY, k)
    if stored and stored ~= "" then
      theme[k] = unpack_color(stored)
    else
      theme[k] = { table.unpack(default) }
    end
  end
  return theme
end

function TH.save(theme)
  for k, v in pairs(theme) do
    reaper.SetExtState(EXT_KEY, k, pack(v), true)
  end
end

function TH.reset(theme)
  for k, default in pairs(DEFAULTS) do
    theme[k] = { table.unpack(default) }
  end
  TH.save(theme)
end

-- Convert {r,g,b,a} 0-1 to ImGui color int
function TH.to_imgui(c)
  local r = math.floor(c[1] * 255 + 0.5)
  local g = math.floor(c[2] * 255 + 0.5)
  local b = math.floor(c[3] * 255 + 0.5)
  local a = math.floor(c[4] * 255 + 0.5)
  return ((r & 0xFF) << 24) | ((g & 0xFF) << 16) | ((b & 0xFF) << 8) | (a & 0xFF)
end

-- Apply theme to ImGui context (call before Begin)
function TH.push(ctx, theme)
  local cols = {}

  local function try(fn, color)
    if fn then
      table.insert(cols, { fn(), color })
    end
  end

  try(reaper.ImGui_Col_WindowBg,          theme.bg)
  try(reaper.ImGui_Col_ChildBg,           theme.bg_child)
  try(reaper.ImGui_Col_Text,              theme.text)
  try(reaper.ImGui_Col_TextDisabled,      theme.text_dim)
  try(reaper.ImGui_Col_Separator,         theme.separator)
  try(reaper.ImGui_Col_SeparatorHovered,  theme.separator)
  try(reaper.ImGui_Col_FrameBg,           theme.frame_bg)
  try(reaper.ImGui_Col_FrameBgHovered,    theme.frame_bg)
  try(reaper.ImGui_Col_Header,            theme.header)
  try(reaper.ImGui_Col_HeaderHovered,     theme.accent)
  try(reaper.ImGui_Col_Tab,               theme.bg_child)
  try(reaper.ImGui_Col_TabHovered,        theme.accent_hov)
  try(reaper.ImGui_Col_TabActive,         theme.tab_active)
  try(reaper.ImGui_Col_TitleBg,           theme.bg)
  try(reaper.ImGui_Col_TitleBgActive,     theme.bg)
  try(reaper.ImGui_Col_ResizeGrip,        theme.accent)
  try(reaper.ImGui_Col_ResizeGripHovered, theme.accent_hov)
  try(reaper.ImGui_Col_ScrollbarBg,       theme.bg)
  try(reaper.ImGui_Col_ScrollbarGrab,     theme.separator)

  for _, pair in ipairs(cols) do
    reaper.ImGui_PushStyleColor(ctx, pair[1], TH.to_imgui(pair[2]))
  end
  return #cols
end

function TH.pop(ctx, count)
  if count > 0 then
    reaper.ImGui_PopStyleColor(ctx, count)
  end
end

-- Get button color as ImGui int (for PushStyleColor)
function TH.btn(theme, key)
  local c = theme[key] or DEFAULTS[key] or {0.3,0.3,0.3,1.0}
  return TH.to_imgui(c)
end

-- Get hover variant (slightly lighter)
function TH.btn_hov(theme, key)
  local c = theme[key] or DEFAULTS[key] or {0.3,0.3,0.3,1.0}
  return TH.to_imgui({
    math.min(1, c[1]+0.06),
    math.min(1, c[2]+0.06),
    math.min(1, c[3]+0.06),
    c[4]
  })
end

-- Get active variant (slightly darker)
function TH.btn_act(theme, key)
  local c = theme[key] or DEFAULTS[key] or {0.3,0.3,0.3,1.0}
  return TH.to_imgui({
    math.max(0, c[1]-0.05),
    math.max(0, c[2]-0.05),
    math.max(0, c[3]-0.05),
    c[4]
  })
end

return TH
