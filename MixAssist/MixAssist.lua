-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- MixAssist.lua  v2  — ReaOrganizer
-- Hub central de préparation de session.
-- Onglets : Organise / Setup / Export / Infos / Options
-- Nécessite : ReaImGui + Config.lua dans le même dossier
-- ============================================================

local script_path = ({ reaper.get_action_context() })[2]:match("(.+[\\/])")

-- ============================================================
-- Vérification ReaImGui
-- ============================================================

if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox(
    "Ce script nécessite ReaImGui.\nInstallez-la via ReaPack.",
    "MixAssist", 0)
  return
end

-- ============================================================
-- Chargement des modules
-- ============================================================

local H            = dofile(script_path .. "lib/helpers.lua")
local M            = dofile(script_path .. "lib/metadata.lua")
local TH           = dofile(script_path .. "lib/theme.lua")
local FS           = dofile(script_path .. "lib/fx_setup.lua")

-- Charger FXConfig
local fx_cfg_ok, fx_cfg = pcall(dofile, script_path .. "FXConfig.lua")
if not fx_cfg_ok then fx_cfg = { FOLDERS = {}, PARALLEL_COLOR = {144, 107, 250} } end
local TAB_ORGANISE     = dofile(script_path .. "tabs/tab_organise.lua")
local TAB_QUICKBALANCE = dofile(script_path .. "tabs/tab_quickbalance.lua")
local TAB_STRUCTURE    = dofile(script_path .. "tabs/tab_structure.lua")
local TAB_FXCONFIG     = dofile(script_path .. "tabs/tab_fxconfig.lua")
local TAB_PREPARE    = dofile(script_path .. "tabs/tab_prepare.lua")
local TAB_EXPORT     = dofile(script_path .. "tabs/tab_export.lua")
local TAB_INFOS      = dofile(script_path .. "tabs/tab_infos.lua")
local TAB_OPTIONS    = dofile(script_path .. "tabs/tab_options.lua")

-- ============================================================
-- Configuration
-- ============================================================

local function load_config()
  local user_path = script_path .. "UserConfig.lua"
  local f = io.open(user_path, "r")
  if f then f:close(); return dofile(user_path) end
  return dofile(script_path .. "Config.lua")
end

local cfg             = load_config()
local last_config_mtime = 0

local function reload_cfg_if_needed()
  local user_path = script_path .. "UserConfig.lua"
  local f = io.open(user_path, "r")
  if f then
    f:close()
    local flag = reaper.GetExtState("MixAssist", "config_dirty")
    if flag == "1" then
      cfg = load_config()
      reaper.SetExtState("MixAssist", "config_dirty", "0", false)
    end
  end
  -- Recharger FXConfig si modifié par FXConfig_UI
  local fx_flag = reaper.GetExtState("MixAssist", "fxconfig_dirty")
  if fx_flag == "1" then
    local ok, new_fx = pcall(dofile, script_path .. "FXConfig.lua")
    if ok then fx_cfg = new_fx end
    reaper.SetExtState("MixAssist", "fxconfig_dirty", "0", false)
  end
end

-- ============================================================
-- État global
-- ============================================================

local ctx_flags = 0
if reaper.ImGui_ConfigFlags_DockingEnable then
  ctx_flags = ctx_flags | reaper.ImGui_ConfigFlags_DockingEnable()
end

local ctx = reaper.ImGui_CreateContext("MixAssist", ctx_flags)

local WIN_X = tonumber(reaper.GetExtState("MixAssist", "win_x")) or 100
local WIN_Y = tonumber(reaper.GetExtState("MixAssist", "win_y")) or 100
local WIN_W = 340
local WIN_H = 580

local log_msg   = ""
local log_timer = 0
local done      = false

-- Table pour passer folders_cache_time par référence aux onglets
local folders_cache_time = { 0 }
local folders_cache      = {}

local function set_log(msg)
  log_msg   = msg
  log_timer = 200
end

local function get_folders_cached()
  local now = reaper.time_precise()
  if now - folders_cache_time[1] > 1.0 then
    folders_cache         = H.get_project_folders()
    folders_cache_time[1] = now
  end
  return folders_cache
end

-- Theme
local theme = TH.load()

-- Métadonnées
local meta_bufs     = M.load()
meta_bufs.version   = meta_bufs.version or ""
meta_bufs.genre     = meta_bufs.genre   or ""
meta_bufs.album     = meta_bufs.album   or ""
meta_bufs.ts_num    = meta_bufs.ts_num  or 4
meta_bufs.ts_den    = meta_bufs.ts_den  or 4

-- Détection changement de projet
local last_project_path = select(2, reaper.EnumProjects(-1, ""))


-- Export alt state (persistent across frames)
local export_alt = {
  buf_suffix      = "",
  alt_instru      = false,
  alt_acapella    = false,
  alt_live        = false,
  alt_custom      = false,
  buf_custom_label = "",
  is_previewing   = false,
  preview_muted   = {},
  pending_delete  = nil,
}

-- Tap BPM state
local tap_bpm = {
  taps      = {},
  last_bpm  = nil,
}

-- Buffer marqueur personnalisé
local buf_custom_marker = ""

-- ============================================================
-- Boucle principale
-- ============================================================

local WINDOW_FLAGS = reaper.ImGui_WindowFlags_NoScrollbar()
  | (reaper.ImGui_WindowFlags_NoBringToDisplayOnFocus and
     reaper.ImGui_WindowFlags_NoBringToDisplayOnFocus() or 0)
  | (reaper.ImGui_WindowFlags_NoNav and
     reaper.ImGui_WindowFlags_NoNav() or 0)

local last_state = nil  -- état persistant pour les fenêtres flottantes

local function loop()
  reload_cfg_if_needed()
  if done then return end

  reaper.ImGui_SetNextWindowPos(ctx, WIN_X, WIN_Y,
    reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_SetNextWindowSize(ctx, WIN_W, WIN_H,
    reaper.ImGui_Cond_FirstUseEver())

  -- Apply theme
  local theme_count = TH.push(ctx, theme)

  local visible, open = reaper.ImGui_Begin(ctx,
    "MixAssist", true, WINDOW_FLAGS)

  if not open then
    done = true
    TH.pop(ctx, theme_count)
    reaper.ImGui_End(ctx)
    return
  end

  -- Mémoriser position
  local x, y = reaper.ImGui_GetWindowPos(ctx)
  reaper.SetExtState("MixAssist", "win_x",
    tostring(math.floor(x)), true)
  reaper.SetExtState("MixAssist", "win_y",
    tostring(math.floor(y)), true)

  -- Détecter changement de projet et recharger les métadonnées
  local current_project_path = select(2, reaper.EnumProjects(-1, ""))
  if current_project_path ~= last_project_path then
    local new_meta    = M.load()
    meta_bufs.artist  = new_meta.artist
    meta_bufs.title   = new_meta.title
    meta_bufs.bpm     = new_meta.bpm
    meta_bufs.key     = new_meta.key
    meta_bufs.version = new_meta.version or ""
    meta_bufs.genre   = new_meta.genre   or ""
    meta_bufs.album   = new_meta.album   or ""
    meta_bufs.ts_num  = new_meta.ts_num  or 4
    meta_bufs.ts_den  = new_meta.ts_den  or 4
    folders_cache_time[1] = 0
    last_project_path = current_project_path
  end

  if visible then
    local avail = reaper.ImGui_GetContentRegionAvail(ctx)
    local btn_w = math.max(100, avail - 8)  -- marge de 8px pour éviter le débordement

    -- État partagé passé à chaque onglet
    local state = {
      ctx                    = ctx,
      btn_w                  = btn_w,
      cfg                    = cfg,
      H                      = H,
      M                      = M,
      TH                     = TH,
      FS                     = FS,
      fx_cfg                 = fx_cfg,
      open_fxconfig          = function() TAB_FXCONFIG.open() end,
      open_fx_browser        = function(target_fn, tab) TAB_FXCONFIG.open_browser(target_fn, tab) end,
      theme                  = theme,
      set_log                = set_log,
      script_path            = script_path,
      get_folders_cached     = get_folders_cached,
      folders_cache_time_ref = folders_cache_time,
      meta_bufs              = meta_bufs,
      buf_custom_marker      = buf_custom_marker,
      export_alt             = export_alt,
      tap_bpm                = tap_bpm,
    }
    last_state = state

    if reaper.ImGui_BeginTabBar(ctx, "main_tabs") then

      if reaper.ImGui_BeginTabItem(ctx, "Infos") then
        TAB_INFOS.render(ctx, state)
        reaper.ImGui_EndTabItem(ctx)
      end

      if reaper.ImGui_BeginTabItem(ctx, "Organise") then
        reaper.ImGui_Spacing(ctx)
        TAB_ORGANISE.render(ctx, state)
        buf_custom_marker = state.buf_custom_marker
        reaper.ImGui_EndTabItem(ctx)
      end

      if reaper.ImGui_BeginTabItem(ctx, "Balance") then
        TAB_QUICKBALANCE.render(ctx, state)
        reaper.ImGui_EndTabItem(ctx)
      end

      if reaper.ImGui_BeginTabItem(ctx, "Structure") then
        TAB_STRUCTURE.render(ctx, state)
        buf_custom_marker = state.buf_custom_marker
        reaper.ImGui_EndTabItem(ctx)
      end

      if reaper.ImGui_BeginTabItem(ctx, "Prepare") then
        TAB_PREPARE.render(ctx, state)
        reaper.ImGui_EndTabItem(ctx)
      end

      if reaper.ImGui_BeginTabItem(ctx, "Export") then
        TAB_EXPORT.render(ctx, state)
        reaper.ImGui_EndTabItem(ctx)
      end

      if reaper.ImGui_BeginTabItem(ctx, "Options") then
        TAB_OPTIONS.render(ctx, state)
        reaper.ImGui_EndTabItem(ctx)
      end

      reaper.ImGui_EndTabBar(ctx)
    end

    -- Log discret
    if log_timer > 0 then
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_TextDisabled(ctx, "▸ " .. log_msg)
      log_timer = log_timer - 1
    end
  end

  TH.pop(ctx, theme_count)
  reaper.ImGui_End(ctx)

  -- Fenêtres flottantes (même contexte)
  if last_state then
    TAB_FXCONFIG.render(ctx, last_state)
    TAB_FXCONFIG.render_browser(ctx, last_state.H)
  end

  if not done then reaper.defer(loop) end
end

reaper.defer(loop)
