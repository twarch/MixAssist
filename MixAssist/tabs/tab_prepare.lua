-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- tabs/tab_prepare.lua — MixAssist
-- Onglet Prepare : setup scripts + ARA plugins + commit
-- ============================================================

local T   = {}
local _H  = nil
local _TH = nil
local _theme = {}

local function get_script_path()
  return ({reaper.get_action_context()})[2]:match("^(.*[\\/])")
end

-- Wrapper : enfants d'un dossier par son nom
local function get_child_tracks(folder_name)
  -- Chercher le dossier par son nom
  local folder = nil
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    if name == folder_name then folder = tr; break end
  end
  if not folder then return {} end
  -- Retourner les enfants directs
  local idx    = math.floor(reaper.GetMediaTrackInfo_Value(folder, "IP_TRACKNUMBER")) - 1
  local result = {}
  local depth  = 0
  for i = idx + 1, reaper.CountTracks(0) - 1 do
    local tr   = reaper.GetTrack(0, i)
    local d    = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    local show = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")
    if show == 1 then table.insert(result, tr) end
    depth = depth + d
    if depth < 0 then break end
  end
  return result
end

-- Check if any item in folder has a specific plugin
local function folder_has_plugin(folder_name, plugin_name)
  for _, tr in ipairs(get_child_tracks(folder_name)) do
    for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local item = reaper.GetTrackMediaItem(tr, j)
      local take = reaper.GetActiveTake(item)
      if take then
        for k = 0, reaper.TakeFX_GetCount(take) - 1 do
          local _, fname = reaper.TakeFX_GetFXName(take, k, "")
          if fname == plugin_name then return true end
        end
      end
    end
  end
  return false
end

-- Add plugin to all items in folder
local function add_fx_to_folder(folder_name, plugin_name, set_log)
  local tracks = get_child_tracks(folder_name)
  if #tracks == 0 then set_log("Folder not found"); return 0 end
  local count = 0
  reaper.Undo_BeginBlock()
  for _, tr in ipairs(tracks) do
    for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local item = reaper.GetTrackMediaItem(tr, j)
      local take = reaper.GetActiveTake(item)
      if take then
        local already = false
        for k = 0, reaper.TakeFX_GetCount(take) - 1 do
          local _, fname = reaper.TakeFX_GetFXName(take, k, "")
          if fname == plugin_name then already = true; break end
        end
        if not already then
          local idx = reaper.TakeFX_AddByName(take, plugin_name, 1)
          if idx >= 0 then count = count + 1 end
        end
      end
    end
  end
  reaper.Undo_EndBlock("Add " .. plugin_name, -1)
  return count
end

-- Remove all FX from all items in folder
local function remove_fx_from_folder(folder_name, set_log)
  local tracks = get_child_tracks(folder_name)
  if #tracks == 0 then set_log("Folder not found"); return end
  local count = 0
  reaper.Undo_BeginBlock()
  for _, tr in ipairs(tracks) do
    for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local item = reaper.GetTrackMediaItem(tr, j)
      local take = reaper.GetActiveTake(item)
      if take then
        for k = reaper.TakeFX_GetCount(take) - 1, 0, -1 do
          reaper.TakeFX_Delete(take, k)
          count = count + 1
        end
      end
    end
  end
  reaper.Undo_EndBlock("Remove FX from " .. folder_name, -1)
  set_log("Removed " .. count .. " FX")
end

-- Commit: render to new take + optionally crop + rename take
local function commit_folder(folder_name, label, fx_label, keep_takes, set_log)
  local tracks = get_child_tracks(folder_name)
  if #tracks == 0 then set_log("Folder not found"); return end
  reaper.SelectAllMediaItems(0, false)
  local count = 0

  -- Snapshot des takes actives avant render + mémoriser leurs noms
  local takes_before = {}
  local take_names_before = {}  -- mémoriser le nom de la take active avant render
  for _, tr in ipairs(tracks) do
    for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local item = reaper.GetTrackMediaItem(tr, j)
      reaper.SetMediaItemSelected(item, true)
      count = count + 1
      local take = reaper.GetActiveTake(item)
      if take then
        takes_before[tostring(take)] = true
        -- Mémoriser le nom actuel pour le nommage cumulatif
        local _, cur_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        take_names_before[tostring(item)] = cur_name
      end
    end
  end

  if count == 0 then set_log("No items found"); return end

  reaper.Undo_BeginBlock()
  reaper.Main_OnCommand(40601, 0)  -- Render to new take
  if not keep_takes then
    reaper.Main_OnCommand(40131, 0)  -- Crop to active take (delete inactive)
  end

  -- Renommer les fichiers des nouvelles takes (nommage cumulatif)
  if fx_label then
    for _, tr in ipairs(tracks) do
      for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local item = reaper.GetTrackMediaItem(tr, j)
        local take = reaper.GetActiveTake(item)
        if take and not takes_before[tostring(take)] then
          local prev_name = take_names_before[tostring(item)] or ""
          -- Renommer le fichier source
          local src      = reaper.GetMediaItemTake_Source(take)
          local src_file = reaper.GetMediaSourceFileName(src, "")
          local dir      = src_file:match("^(.*[\\/])")
          local base = prev_name ~= ""
            and prev_name:gsub("%.wav$", ""):gsub("%.WAV$", "")
            or src_file:match("([^/\\]+)%s+render%s+%d+%.wav$") or ""
          base = base:gsub("%.wav$", ""):gsub("%.WAV$", "")
          if base ~= "" then
            local new_file = dir .. base .. " [" .. fx_label .. "].wav"
            local ok = os.rename(src_file, new_file)
            if ok then
              local new_src = reaper.PCM_Source_CreateFromFile(new_file)
              if new_src then reaper.SetMediaItemTake_Source(take, new_src) end
              -- Renommer la take avec le même nom (sans extension)
              reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME",
                base .. " [" .. fx_label .. "]", true)
            end
          end
        end
      end
    end
  end

  reaper.Undo_EndBlock("Commit " .. label, -1)
  reaper.UpdateArrange()
  set_log("Committed " .. count .. " items in " .. label)
end

-- ── Button helpers ────────────────────────────────────────────

local function plugin_btn(ctx, H, w, label, tooltip, on_click)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
    _TH and _TH.btn(_theme, "btn_ara") or H.rgb_to_imgui(50, 50, 78))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
    _TH and _TH.btn_hov(_theme, "btn_ara") or H.rgb_to_imgui(70, 70, 105))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
    _TH and _TH.btn_act(_theme, "btn_ara") or H.rgb_to_imgui(40, 40, 65))
  if reaper.ImGui_Button(ctx, label, w, 22) then on_click() end
  reaper.ImGui_PopStyleColor(ctx, 3)
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, tooltip)
    reaper.ImGui_EndTooltip(ctx)
  end
end

local function commit_btn(ctx, H, w, id, folder_name, label, fx_label, keep_takes, set_log)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
    _TH and _TH.btn(_theme, "btn_commit") or H.rgb_to_imgui(80, 55, 20))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
    _TH and _TH.btn_hov(_theme, "btn_commit") or H.rgb_to_imgui(105, 75, 28))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
    _TH and _TH.btn_act(_theme, "btn_commit") or H.rgb_to_imgui(65, 45, 16))
  if reaper.ImGui_Button(ctx, "Commit##" .. id, w, 22) then
    commit_folder(folder_name, label, fx_label, keep_takes, set_log)
  end
  reaper.ImGui_PopStyleColor(ctx, 3)
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Render all items in " .. label .. " to new take")
    if keep_takes then
      reaper.ImGui_Text(ctx, "Inactive takes will be kept")
    else
      reaper.ImGui_Text(ctx, "Inactive takes will be deleted")
    end
    reaper.ImGui_EndTooltip(ctx)
  end
end

local function remove_btn(ctx, H, w, id, folder_name, label, set_log)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
    _TH and _TH.btn(_theme, "btn_danger") or H.rgb_to_imgui(80, 30, 30))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
    _TH and _TH.btn_hov(_theme, "btn_danger") or H.rgb_to_imgui(105, 42, 42))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
    _TH and _TH.btn_act(_theme, "btn_danger") or H.rgb_to_imgui(65, 25, 25))
  if reaper.ImGui_Button(ctx, "Remove FX##" .. id, w, 22) then
    remove_fx_from_folder(folder_name, set_log)
  end
  reaper.ImGui_PopStyleColor(ctx, 3)
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Remove all FX from items in " .. label)
    reaper.ImGui_EndTooltip(ctx)
  end
end

local function setup_btn(ctx, H, btn_w, label, is_done, on_click, tooltip)
  local col   = is_done and (_TH and _TH.btn(_theme, "btn_done")       or H.rgb_to_imgui(35,80,35))
                         or (_TH and _TH.btn(_theme, "btn_default")     or H.rgb_to_imgui(70,70,80))
  local col_h = is_done and (_TH and _TH.btn_hov(_theme, "btn_done")   or H.rgb_to_imgui(45,100,45))
                         or (_TH and _TH.btn_hov(_theme, "btn_default") or H.rgb_to_imgui(90,90,105))
  local col_a = is_done and (_TH and _TH.btn_act(_theme, "btn_done")   or H.rgb_to_imgui(30,70,30))
                         or (_TH and _TH.btn_act(_theme, "btn_default") or H.rgb_to_imgui(60,60,70))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),       col)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_h)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  col_a)
  if reaper.ImGui_Button(ctx, (is_done and "✓ " or "  ") .. label, btn_w, 28) then
    on_click()
  end
  reaper.ImGui_PopStyleColor(ctx, 3)
  if tooltip and reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, tooltip)
    if is_done then reaper.ImGui_TextDisabled(ctx, "✓ Already done") end
    reaper.ImGui_EndTooltip(ctx)
  end
end

-- ── Render ────────────────────────────────────────────────────

local function get_folder(cfg, cat)
  for _, def in ipairs(cfg.FOLDERS) do
    if def.cat == cat then return def.name, def.label end
  end
  return nil, cat
end

function T.render(ctx, state)
  _H = state.H
  if not _TH then
    local sp = get_script_path()
    if sp then _TH = dofile(sp .. "lib/theme.lua") end
  end
  _theme = state.theme or {}
  local theme = _theme
  local btn_w       = state.btn_w
  local H           = state.H
  local set_log     = state.set_log
  local script_path = state.script_path
  local cfg         = state.cfg
  local spacing     = 8
  local half_w      = math.floor((btn_w - spacing) / 2)

  local dr_name, dr_label = get_folder(cfg, "DR")
  local lv_name, lv_label = get_folder(cfg, "LV")
  local bv_name, bv_label = get_folder(cfg, "BV")
  local dv_name, dv_label = get_folder(cfg, "DV")

  local VA  = "VST3: VoiceAssist (NoiseWorks)"
  local AA  = "VST3: Auto-Align 2 (Sound Radix)"
  local MEL = "VST3: Melodyne (Celemony)"
  local REP = "VST3: RePitch (Synchro Arts)"
  local DCL = "VST3: RX 10 De-click (iZotope)"

  -- Delete takes preference (persistent) — décoché par défaut = garder les takes
  local keep_takes_str = reaper.GetExtState("MixAssist", "keep_takes")
  local keep_takes = keep_takes_str == "true"  -- default false
  local delete_takes = not keep_takes

  reaper.ImGui_Spacing(ctx)

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)

  -- Check if a take name in folder contains a tag
  local function folder_has_commit_tag(folder_name, tag)
    for _, tr in ipairs(get_child_tracks(folder_name)) do
      for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local item = reaper.GetTrackMediaItem(tr, j)
        local take = reaper.GetActiveTake(item)
        if take then
          local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
          if name:find(tag, 1, true) then return true end
        end
      end
    end
    return false
  end

  -- Render a vocal section with ARA logic
  local function vocal_section(folder_name, label, id)
    if not folder_name then return end

    local has_va  = folder_has_plugin(folder_name, VA)
    local has_mel = folder_has_plugin(folder_name, MEL)
    local has_rep = folder_has_plugin(folder_name, REP)
    local has_dcl = folder_has_plugin(folder_name, DCL)
    local has_ara = has_va or has_mel or has_rep
    local has_any = has_ara or has_dcl

    -- Build composite commit label from all plugins present on items
    local function build_commit_label()
      local parts = {}
      if has_va  then table.insert(parts, "VoiceAssist") end
      if has_mel then table.insert(parts, "Melodyne") end
      if has_rep then table.insert(parts, "RePitch") end
      if has_dcl then table.insert(parts, "De-click") end
      -- Check for unknown plugins
      local known = { [VA]=true, [MEL]=true, [REP]=true, [DCL]=true }
      local seen_unknown = {}
      for _, tr in ipairs(get_child_tracks(folder_name)) do
        for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
          local item = reaper.GetTrackMediaItem(tr, j)
          local take = reaper.GetActiveTake(item)
          if take then
            for k = 0, reaper.TakeFX_GetCount(take) - 1 do
              local _, fname = reaper.TakeFX_GetFXName(take, k, "")
              if not known[fname] and not seen_unknown[fname] then
                seen_unknown[fname] = true
                local short = fname:match("VST3?:%s*(.-)%s*%(")
                           or fname:match("AU:%s*(.-)%s*%(")
                           or fname
                table.insert(parts, short)
              end
            end
          end
        end
      end
      return #parts > 0 and table.concat(parts, "+") or nil
    end

    local ara_label = build_commit_label()

    local done_va  = folder_has_commit_tag(folder_name, "[VoiceAssist]")
    local done_mel = folder_has_commit_tag(folder_name, "[Melodyne]")
    local done_rep = folder_has_commit_tag(folder_name, "[RePitch]")

    reaper.ImGui_Text(ctx, label)
    reaper.ImGui_Spacing(ctx)

    -- Status indicators
    local status = {}
    if done_va  then table.insert(status, "✓ VoiceAssist") end
    if done_mel then table.insert(status, "✓ Melodyne") end
    if done_rep then table.insert(status, "✓ RePitch") end
    if #status > 0 then
      reaper.ImGui_TextDisabled(ctx, table.concat(status, "  "))
      reaper.ImGui_Spacing(ctx)
    end

    -- Ligne 1 : ARA plugins + De-click (4 boutons)
    local quarter_w = math.floor((btn_w - spacing * 3) / 4)

    if has_mel or has_rep then reaper.ImGui_BeginDisabled(ctx) end
    plugin_btn(ctx, H, quarter_w, "VoiceAssist##" .. id,
      "Add VoiceAssist on items in " .. label ..
      ((has_mel or has_rep) and "\n⚠ Only one ARA plugin at a time" or ""),
      function()
        local n = add_fx_to_folder(folder_name, VA, set_log)
        set_log("VoiceAssist: " .. n .. " items")
      end)
    if has_mel or has_rep then reaper.ImGui_EndDisabled(ctx) end
    reaper.ImGui_SameLine(ctx)

    if has_va or has_rep then reaper.ImGui_BeginDisabled(ctx) end
    plugin_btn(ctx, H, quarter_w, "Melodyne##" .. id,
      "Add Melodyne on items in " .. label ..
      ((has_va or has_rep) and "\n⚠ Only one ARA plugin at a time" or ""),
      function()
        local n = add_fx_to_folder(folder_name, MEL, set_log)
        set_log("Melodyne: " .. n .. " items")
      end)
    if has_va or has_rep then reaper.ImGui_EndDisabled(ctx) end
    reaper.ImGui_SameLine(ctx)

    if has_va or has_mel then reaper.ImGui_BeginDisabled(ctx) end
    plugin_btn(ctx, H, quarter_w, "RePitch##" .. id,
      "Add RePitch on items in " .. label ..
      ((has_va or has_mel) and "\n⚠ Only one ARA plugin at a time" or ""),
      function()
        local n = add_fx_to_folder(folder_name, REP, set_log)
        set_log("RePitch: " .. n .. " items")
      end)
    if has_va or has_mel then reaper.ImGui_EndDisabled(ctx) end
    reaper.ImGui_SameLine(ctx)

    plugin_btn(ctx, H, quarter_w, "De-click##" .. id,
      "Add RX De-click on items in " .. label,
      function()
        local n = add_fx_to_folder(folder_name, DCL, set_log)
        set_log("De-click: " .. n .. " items")
      end)

    reaper.ImGui_Spacing(ctx)

    -- Ligne 2 : Commit + Remove
    if not has_any then reaper.ImGui_BeginDisabled(ctx) end
    commit_btn(ctx, H, half_w, id, folder_name, label, ara_label, keep_takes, set_log)
    if not has_any then reaper.ImGui_EndDisabled(ctx) end
    reaper.ImGui_SameLine(ctx)
    remove_btn(ctx, H, half_w, id, folder_name, label, set_log)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
  end

  reaper.ImGui_Spacing(ctx)

  -- ── Drums ARA ─────────────────────────────────────────────
  local has_ara_section = (dr_name and H.find_track(dr_name))
    or H.find_track(lv_name or "") or H.find_track(bv_name or "") or H.find_track(dv_name or "")

  if has_ara_section then
    reaper.ImGui_SeparatorText(ctx, "ARA Process")
    reaper.ImGui_Spacing(ctx)
    -- Cases à cocher liées au process ARA
    local ck, vk = reaper.ImGui_Checkbox(ctx, "Delete inactive takes after Commit", delete_takes)
    if ck then
      keep_takes = not vk
      reaper.SetExtState("MixAssist", "keep_takes", tostring(keep_takes), true)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Checked: inactive takes are deleted after render")
      reaper.ImGui_Text(ctx, "Unchecked: inactive takes are kept (recoverable via right-click → Take)")
      reaper.ImGui_EndTooltip(ctx)
    end
    local show_takes = reaper.GetToggleCommandState(40435) == 1
    local cst, _ = reaper.ImGui_Checkbox(ctx, "Show inactive takes in lanes", show_takes)
    if cst then reaper.Main_OnCommand(40435, 0) end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Toggle visibility of inactive takes (Cmd+L)")
      reaper.ImGui_EndTooltip(ctx)
    end
    reaper.ImGui_Spacing(ctx)
  end

  if dr_name and H.find_track(dr_name) then
    reaper.ImGui_Text(ctx, dr_label or "Drums")
    reaper.ImGui_Spacing(ctx)

    local dr_has_aa = folder_has_plugin(dr_name, AA)
    local third_w = (btn_w - 8) / 3
    plugin_btn(ctx, H, third_w, "Auto-Align##dr",
      "Add Auto-Align 2 on all items in " .. (dr_label or "Drums"),
      function()
        local n = add_fx_to_folder(dr_name, AA, set_log)
        set_log("Auto-Align 2: " .. n .. " items")
      end)
    reaper.ImGui_SameLine(ctx)
    if not dr_has_aa then reaper.ImGui_BeginDisabled(ctx) end
    commit_btn(ctx, H, third_w, "dr", dr_name, dr_label or "Drums", "Auto-Align", keep_takes, set_log)
    if not dr_has_aa then reaper.ImGui_EndDisabled(ctx) end
    reaper.ImGui_SameLine(ctx)
    remove_btn(ctx, H, third_w, "dr", dr_name, dr_label or "Drums", set_log)

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
  end
  vocal_section(lv_name, lv_label or "Lead Vocals", "lv")
  vocal_section(bv_name, bv_label or "Backing Vocals", "bv")
  vocal_section(dv_name, dv_label or "Double Vocals", "dv")

  -- ── Set FX dynamique (triés par position dans le projet) ──
  local fx_cfg = state.fx_cfg
  local FS     = state.FS
  if fx_cfg and FS and fx_cfg.FOLDERS then
    local fx_buttons = {}
    for cat, folder_cfg in pairs(fx_cfg.FOLDERS) do
      local cfg_def = state.cfg and state.cfg.BY_CAT and state.cfg.BY_CAT[cat]
      local folder_name = cfg_def and cfg_def.name or ("[" .. cat .. "]")
      local folder_tr = H.find_track(folder_name)
      if folder_tr then
        local pos = math.floor(reaper.GetMediaTrackInfo_Value(folder_tr, "IP_TRACKNUMBER"))
        table.insert(fx_buttons, {
          cat = cat, folder_cfg = folder_cfg,
          folder_name = folder_name, folder_tr = folder_tr, pos = pos
        })
      end
    end
    table.sort(fx_buttons, function(a, b) return a.pos < b.pos end)

    if #fx_buttons > 0 then
      reaper.ImGui_SeparatorText(ctx, "Set FX")
      reaper.ImGui_Spacing(ctx)
      for _, btn in ipairs(fx_buttons) do
        local done = false
        if btn.folder_cfg.parallel and #btn.folder_cfg.parallel > 0 then
          local first_par = btn.folder_cfg.parallel[1]
          if first_par.name and first_par.name ~= "" then
            done = H.find_track(first_par.name) ~= nil
          end
        elseif btn.folder_cfg.fxchain and btn.folder_cfg.fxchain ~= "" then
          done = reaper.TrackFX_GetCount(btn.folder_tr) > 0
        end
        local cat = btn.cat
        local folder_tr = btn.folder_tr
        local folder_cfg = btn.folder_cfg
        setup_btn(ctx, H, btn_w,
          "Set " .. btn.folder_name .. " FX##setfx_" .. cat,
          done,
          function()
            FS.apply(cat, folder_tr, folder_cfg, H)
            set_log(cat .. " FX done")
          end,
          "Apply FX config for " .. btn.folder_name)
      end
      reaper.ImGui_Spacing(ctx)

      -- Master avec couleur distincte
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        _TH and _TH.btn(_theme, "btn_master")     or H.rgb_to_imgui(90, 30, 30))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  _TH and _TH.btn_hov(_theme, "btn_master") or H.rgb_to_imgui(115, 40, 40))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   _TH and _TH.btn_act(_theme, "btn_master") or H.rgb_to_imgui(70, 22, 22))
      local master_done = H.master_has_fx()
      if reaper.ImGui_Button(ctx, (master_done and "✓ " or "  ") .. "Set Master FX##master", btn_w, 28) then
        H.run_script(script_path, "MasterSetup.lua")
        set_log("Master done")
      end
      reaper.ImGui_PopStyleColor(ctx, 3)
    end
  end

end

return T
