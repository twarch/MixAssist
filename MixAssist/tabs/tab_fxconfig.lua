-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- tabs/tab_fxconfig.lua — MixAssist
-- Fenêtre flottante FX Config dans le contexte MixAssist
-- ============================================================

local T = {}

local is_open    = false
local WIN_W      = 520
local WIN_H      = 620
local status_msg = ""
local status_t   = 0

-- FX Browser
local browser_open   = false
local browser_query  = ""
local browser_target = nil  -- fonction appelée avec la valeur sélectionnée
local browser_tab    = 0    -- 0=FXChains, 1=Plugins
local all_fxchains   = nil  -- cache
local all_plugins    = nil  -- cache

local function scan_fx_cache()
  if all_fxchains and all_plugins then return end
  -- FXChains
  all_fxchains = {}
  local path = reaper.GetResourcePath() .. "/FXChains/"
  local i = 0
  local f = reaper.EnumerateFiles(path, i)
  while f do
    if f:match("%.RfxChain$") or f:match("%.rfxchain$") then
      table.insert(all_fxchains, f)
    end
    i = i + 1
    f = reaper.EnumerateFiles(path, i)
  end
  table.sort(all_fxchains)
  -- Plugins
  all_plugins = {}
  local j = 0
  local ok, name = reaper.EnumInstalledFX(j)
  while ok do
    if name ~= "Video processor" and name ~= "Container" then
      table.insert(all_plugins, name)
    end
    j = j + 1
    ok, name = reaper.EnumInstalledFX(j)
  end
end

local function open_browser(target_fn, tab)
  scan_fx_cache()
  browser_open   = true
  browser_target = target_fn
  browser_tab    = tab or 0
  browser_query  = ""
end
-- Buffers plats indexés par uid (upvalues directes comme ROConfig)

function T.open() is_open = true end
function T.open_browser(target_fn, tab) open_browser(target_fn, tab) end

local function save_fxconfig(fx_cfg, fx_cfg_path)
  local f = io.open(fx_cfg_path, "w")
  if not f then return false end
  f:write("-- FXConfig.lua — MixAssist\n\nlocal cfg = {}\n\n")
  f:write("cfg.PARALLEL_COLOR = { " .. table.concat(fx_cfg.PARALLEL_COLOR, ", ") .. " }\n\n")
  f:write("cfg.FOLDERS = {\n\n")
  for cat, folder in pairs(fx_cfg.FOLDERS) do
    f:write("  " .. cat .. " = {\n")
    f:write("    fxchain  = " .. string.format("%q", folder.fxchain or "") .. ",\n")
    if folder.sub_buses then
      f:write("    sub_buses = {\n")
      for bus_name, bus_cfg in pairs(folder.sub_buses) do
        f:write("      [" .. string.format("%q", bus_name) .. "] = { fxchain = "
          .. string.format("%q", bus_cfg.fxchain or "") .. " },\n")
      end
      f:write("    },\n")
    end
    f:write("    parallel = {\n")
    for _, par in ipairs(folder.parallel or {}) do
      local vol = (par.volume and par.volume > -150) and tostring(par.volume) or "-math.huge"
      local tvol = (par.track_volume == nil or par.track_volume == 0) and "0" or "-math.huge"
      local grp = par.group and tostring(par.group) or "nil"
      f:write("      { name=" .. string.format("%q", par.name or "")
        .. ", position=" .. string.format("%q", par.position or "internal")
        .. ", prefader=" .. tostring(par.prefader == true)
        .. ", volume=" .. vol
        .. ", track_volume=" .. tvol
        .. ", group=" .. grp
        .. ", fxchain=" .. string.format("%q", par.fxchain or "") .. " },\n")
    end
    f:write("    },\n  },\n\n")
  end
  f:write("}\n\nreturn cfg\n")
  f:close()
  reaper.SetExtState("MixAssist", "fxconfig_dirty", "1", false)
  return true
end

-- selected_cat comme upvalue persistante
local selected_cat = nil

local function render_browser(ctx, H)
  if not browser_open then return end

  reaper.ImGui_SetNextWindowSize(ctx, 420, 500, reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_SetNextWindowPos(ctx, 740, 100, reaper.ImGui_Cond_FirstUseEver())
  local vis, open = reaper.ImGui_Begin(ctx, "FX Browser##fxbrowser", true)
  if not open then browser_open = false end
  if not vis then reaper.ImGui_End(ctx); return end

  local W = 400

  -- Tabs FXChains / Plugins
  if reaper.ImGui_BeginTabBar(ctx, "##browser_tabs") then
    if reaper.ImGui_BeginTabItem(ctx, "FXChains") then
      browser_tab = 0
      reaper.ImGui_EndTabItem(ctx)
    end
    if reaper.ImGui_BeginTabItem(ctx, "Plugins") then
      browser_tab = 1
      reaper.ImGui_EndTabItem(ctx)
    end
    reaper.ImGui_EndTabBar(ctx)
  end

  reaper.ImGui_Spacing(ctx)

  -- Search input
  reaper.ImGui_SetNextItemWidth(ctx, W)
  local cs, vs = reaper.ImGui_InputText(ctx, "##bq", browser_query, 256)
  if cs then browser_query = vs end
  reaper.ImGui_Spacing(ctx)

  -- Liste filtrée
  local query_low = browser_query:lower()
  local list = browser_tab == 0 and all_fxchains or all_plugins
  if list then
    for _, item in ipairs(list) do
      local display = browser_tab == 0 and item:gsub("%.RfxChain$",""):gsub("%.rfxchain$","") or item
      if query_low == "" or display:lower():find(query_low, 1, true) then
        if reaper.ImGui_Selectable(ctx, display .. "##br_" .. item, false) then
          if browser_target then
            local value = browser_tab == 0 and item or item
            browser_target(value)
          end
          browser_open = false
        end
      end
    end
  end

  reaper.ImGui_End(ctx)
end

function T.render_browser(ctx, H) render_browser(ctx, H) end

function T.render(ctx, state)
  if not is_open then return end

  local H           = state.H
  local fx_cfg      = state.fx_cfg
  local script_path = state.script_path
  local cfg         = state.cfg
  local folders_list = cfg.FOLDERS

  -- Initialiser selected_cat
  if not selected_cat and folders_list and folders_list[1] then
    selected_cat = folders_list[1].cat
  end

  local fx_cfg_path = script_path .. "FXConfig.lua"

  reaper.ImGui_SetNextWindowSize(ctx, WIN_W, WIN_H, reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_SetNextWindowPos(ctx, 200, 100, reaper.ImGui_Cond_FirstUseEver())

  local visible, open = reaper.ImGui_Begin(ctx, "MixAssist — FX Config", true,
    reaper.ImGui_WindowFlags_NoScrollbar and reaper.ImGui_WindowFlags_NoScrollbar() or 0)

  if not open then is_open = false end

  if not visible then
    reaper.ImGui_End(ctx)
    return
  end

  local W = WIN_W - 24

  -- ── Sélecteur catégorie ───────────────────────────────────
  local win_w, _ = reaper.ImGui_GetContentRegionAvail(ctx)
  local fx_spacing = 4

  -- Pré-calculer les lignes
  local fx_items = {}
  for _, def in ipairs(folders_list) do
    if def.cat ~= "UNK" then
      local txt_w = reaper.ImGui_CalcTextSize(ctx, def.name)
      table.insert(fx_items, { def = def, w = math.max(52, txt_w + 12) })
    end
  end
  local fx_lines = {}
  local fx_line = {}
  local fx_line_w = 0
  for _, item in ipairs(fx_items) do
    local needed = fx_line_w > 0 and (fx_line_w + fx_spacing + item.w) or item.w
    if needed > win_w - 16 and #fx_line > 0 then
      table.insert(fx_lines, fx_line)
      fx_line = { item }
      fx_line_w = item.w
    else
      table.insert(fx_line, item)
      fx_line_w = needed
    end
  end
  if #fx_line > 0 then table.insert(fx_lines, fx_line) end

  for _, line in ipairs(fx_lines) do
    for li, item in ipairs(line) do
      local def = item.def
      if li > 1 then reaper.ImGui_SameLine(ctx) end
      local c   = def.color
      local col = H.rgb_to_imgui(c[1], c[2], c[3])
      local col_sel = selected_cat == def.cat and col
        or H.rgb_to_imgui(math.floor(c[1]*0.35), math.floor(c[2]*0.35), math.floor(c[3]*0.35))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col_sel)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  H.lighten(col, 20))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   col)
      if reaper.ImGui_Button(ctx, def.name .. "##fxcat_" .. def.cat, item.w, 20) then
        selected_cat = def.cat
      end
      reaper.ImGui_PopStyleColor(ctx, 3)
    end
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- ── Config de la catégorie ────────────────────────────────
  local folder = fx_cfg.FOLDERS[selected_cat]
  if not folder then
    folder = { fxchain = "", parallel = {} }
    fx_cfg.FOLDERS[selected_cat] = folder
  end
  if not folder.parallel then folder.parallel = {} end

  -- FXchain du dossier
  reaper.ImGui_Text(ctx, "Folder FX")
  reaper.ImGui_SetNextItemWidth(ctx, W - 30)
  local cf, vf = reaper.ImGui_InputText(ctx, "##fxcfg_main_"..selected_cat, folder.fxchain or "", 256)
  if cf then folder.fxchain = vf end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "…##br_main") then
    open_browser(function(v) folder.fxchain = v end, 0)
  end

  -- Sub-buses (DR uniquement)
  if folder.sub_buses then
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "Sub-bus FXchains")
    reaper.ImGui_Spacing(ctx)
    local bus_order = { "BD BUS", "SD BUS", "TOM BUS", "OH BUS", "ROOM BUS" }
    for _, bus_name in ipairs(bus_order) do
      local bus_cfg = folder.sub_buses[bus_name]
      if not bus_cfg then bus_cfg = { fxchain="" }; folder.sub_buses[bus_name] = bus_cfg end
      reaper.ImGui_Text(ctx, bus_name)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetCursorPosX(ctx, 90)
      reaper.ImGui_SetNextItemWidth(ctx, W - 120)
      local cb, vb = reaper.ImGui_InputText(ctx, "##fxbus_"..bus_name:gsub(" ","_"), bus_cfg.fxchain or "", 256)
      if cb then bus_cfg.fxchain = vb end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "…##br_bus_"..bus_name:gsub(" ","_")) then
        local bc = bus_cfg
        open_browser(function(v) bc.fxchain = v end, 0)
      end
    end
  end

  -- ── Pistes parallèles ────────────────────────────────────
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Parallel tracks")
  reaper.ImGui_Spacing(ctx)

  local to_delete = nil
  for i, par in ipairs(folder.parallel) do
    local uid = selected_cat .. "_" .. i

    -- Ligne 1 : Nom + FXchain
    reaper.ImGui_Text(ctx, "Name:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 130)
    local cn, vn = reaper.ImGui_InputText(ctx, "##fxpar_name_"..uid, par.name or "", 256)
    if cn then par.name = vn end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "FX:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, W - 245)
    local cfx, vfx = reaper.ImGui_InputText(ctx, "##fxpar_fx_"..uid, par.fxchain or "", 256)
    if cfx then par.fxchain = vfx end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "…##br_pfx_"..uid) then
      local pc = par
      open_browser(function(v) pc.fxchain = v end, 0)
    end

    -- Ligne 2 : Position + Pre/Post + Volume + Supprimer
    reaper.ImGui_SetNextItemWidth(ctx, 100)
    if reaper.ImGui_BeginCombo(ctx, "##fxpar_pos_"..uid, par.position == "external" and "External" or "Internal") then
      if reaper.ImGui_Selectable(ctx, "Internal", par.position ~= "external") then
        par.position = "internal"
      end
      if reaper.ImGui_Selectable(ctx, "External", par.position == "external") then
        par.position = "external"
        par.volume   = -math.huge  -- external toujours à -inf
      end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_SetNextItemWidth(ctx, 55)
    if reaper.ImGui_BeginCombo(ctx, "##fxpar_pf_"..uid, par.prefader and "Pre" or "Post") then
      if reaper.ImGui_Selectable(ctx, "Pre",  par.prefader)     then par.prefader = true  end
      if reaper.ImGui_Selectable(ctx, "Post", not par.prefader) then par.prefader = false end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_SetNextItemWidth(ctx, 58)
    local vol_lbl = (not par.volume or par.volume <= -150) and "-inf" or (par.volume.."dB")
    if reaper.ImGui_BeginCombo(ctx, "##fxpar_vol_"..uid, vol_lbl) then
      if reaper.ImGui_Selectable(ctx, "-inf", not par.volume or par.volume<=-150) then par.volume=-math.huge end
      if reaper.ImGui_Selectable(ctx, "0 dB",  par.volume==0)  then par.volume=0  end
      if reaper.ImGui_Selectable(ctx, "-6 dB", par.volume==-6) then par.volume=-6 end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        H.rgb_to_imgui(120,40,40))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  H.rgb_to_imgui(160,55,55))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   H.rgb_to_imgui(100,30,30))
    if reaper.ImGui_SmallButton(ctx, "✕##fxdel_"..uid) then to_delete = i end
    reaper.ImGui_PopStyleColor(ctx, 3)

    -- Ligne 3 : Group (optionnel) + Track volume
    reaper.ImGui_Text(ctx, "Track vol:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 65)
    local tvol_lbl = (par.track_volume ~= nil and par.track_volume <= -150) and "-inf" or "0 dB"
    if reaper.ImGui_BeginCombo(ctx, "##fxpar_tvol_"..uid, tvol_lbl) then
      if reaper.ImGui_Selectable(ctx, "0 dB", par.track_volume == nil or par.track_volume == 0) then
        par.track_volume = 0
      end
      if reaper.ImGui_Selectable(ctx, "-inf", par.track_volume ~= nil and par.track_volume <= -150) then
        par.track_volume = -math.huge
      end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "Group:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 50)
    local cg, vg = reaper.ImGui_InputText(ctx, "##fxpar_grp_"..uid, tostring(par.group or ""), 8)
    if cg then
      local n = tonumber(vg)
      par.group = (n and n > 0) and math.floor(n) or nil
    end
    if par.group then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_TextDisabled(ctx, "→ sources = master, cette piste = slave")
    end



    reaper.ImGui_Spacing(ctx)
  end

  if to_delete then
    table.remove(folder.parallel, to_delete)
  end

  -- Boutons Add + Save
  local half = (W - 4) / 2
  if reaper.ImGui_Button(ctx, "+ Add", half, 0) then
    table.insert(folder.parallel, { name="", position="internal", prefader=false, volume=1.0, track_volume=0, fxchain="" })
  end
  reaper.ImGui_SameLine(ctx)

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        H.rgb_to_imgui(40,100,40))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  H.rgb_to_imgui(55,130,55))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   H.rgb_to_imgui(30,80,30))
  if reaper.ImGui_Button(ctx, "💾 Save", half, 0) then
    if save_fxconfig(fx_cfg, fx_cfg_path) then
      status_msg = "✓ Saved"
      status_t   = reaper.time_precise()
    end
  end
  reaper.ImGui_PopStyleColor(ctx, 3)

  if status_msg ~= "" and (reaper.time_precise() - status_t) < 3.0 then
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextDisabled(ctx, status_msg)
  end

  reaper.ImGui_End(ctx)
end

return T