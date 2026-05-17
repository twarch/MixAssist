-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- tabs/tab_organise.lua — ReaOrganizer
-- Organise tab: AUTO ORGANIZE, folders, MoveToFolder,
-- structure markers, stereo merge.
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

-- Push button color style
local function push_color(ctx, H, key)
  local c = COLORS[key].btn
  local col = H.rgb_to_imgui(c[1], c[2], c[3])
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  H.lighten(col, 35))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   col)
end

-- Count markers matching prefix + digits only (e.g. V1, V2 but not V1A)
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

-- Find max group number for A/B variants
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

-- Check if prefix+num+A marker exists
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

local function add_marker(prefix, name_or_fn, color_key)
  local pos  = reaper.GetCursorPosition()
  local name = type(name_or_fn) == "function" and name_or_fn() or name_or_fn
  reaper.AddProjectMarker2(0, false, pos, 0, name, -1,
    to_native(COLORS[color_key].marker))
  reaper.UpdateArrange()
  return name
end

local _pending_pairs = nil  -- upvalue pour les paires en attente de merge

local function strip_suffix(s)
  s = s:gsub("%s*%-?%s*[Ll][Ee][Ff][Tt]$", "")
  s = s:gsub("%s*%-?%s*[Rr][Ii][Gg][Hh][Tt]$", "")
  s = s:gsub("%s+[LlRrDd][Tt]?$", "")
  s = s:gsub("%s+[12]$", "")
  s = s:gsub("%.?[LlRr]$", "")
  return s:gsub("%s+$", "")
end

-- Merge tr1 + tr2 en une piste stéréo
-- Si autogroup_folder fourni : remonter les items vers ce dossier parent et supprimer le sous-dossier
local function do_merge(tr1, tr2, autogroup_folder)
  if not tr1 or not tr2 then return end
  local _, name1 = reaper.GetTrackName(tr1)
  local _, name2 = reaper.GetTrackName(tr2)

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local base1 = strip_suffix(name1)
  local base2 = strip_suffix(name2)
  local merged_name = (base1 == base2 and base1 ~= "") and base1
                      or (base1 ~= "" and base1 or name1)

  if autogroup_folder then
    local tr2_depth = reaper.GetMediaTrackInfo_Value(tr2, "I_FOLDERDEPTH")
    local bus_depth = reaper.GetMediaTrackInfo_Value(autogroup_folder, "I_FOLDERDEPTH")

    -- 1. Pan items tr1 gauche
    for i = 0, reaper.CountTrackMediaItems(tr1) - 1 do
      local item = reaper.GetTrackMediaItem(tr1, i)
      local take = reaper.GetActiveTake(item)
      if take then reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", -1.0) end
    end

    -- 2. Pan items tr2 droite et déplacer vers autogroup_folder
    local items_tr2 = {}
    for i = 0, reaper.CountTrackMediaItems(tr2) - 1 do
      table.insert(items_tr2, reaper.GetTrackMediaItem(tr2, i))
    end
    for _, item in ipairs(items_tr2) do
      local take = reaper.GetActiveTake(item)
      if take then reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", 1.0) end
      reaper.MoveMediaItemToTrack(item, autogroup_folder)
    end

    -- 3. Déplacer items tr1 vers autogroup_folder
    local items_tr1 = {}
    for i = 0, reaper.CountTrackMediaItems(tr1) - 1 do
      table.insert(items_tr1, reaper.GetTrackMediaItem(tr1, i))
    end
    for _, item in ipairs(items_tr1) do
      reaper.MoveMediaItemToTrack(item, autogroup_folder)
    end

    -- 4. Supprimer tr1 et tr2 directement
    reaper.DeleteTrack(tr2)
    reaper.DeleteTrack(tr1)

    -- 5. Appliquer le nouveau depth APRÈS suppression
    -- tr2_depth + 1 : si tr2=-1 → bus=0 (normal dans DR)
    --                 si tr2=-2 → bus=-1 (ferme DR)
    reaper.SetMediaTrackInfo_Value(autogroup_folder, "I_FOLDERDEPTH", tr2_depth + 1)

  else
    -- Cas manuel : pan + move items, puis gestion du dossier parent
    for i = 0, reaper.CountTrackMediaItems(tr1) - 1 do
      local item = reaper.GetTrackMediaItem(tr1, i)
      local take = reaper.GetActiveTake(item)
      if take then reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", -1.0) end
    end
    local items_to_move = {}
    for i = 0, reaper.CountTrackMediaItems(tr2) - 1 do
      table.insert(items_to_move, reaper.GetTrackMediaItem(tr2, i))
    end
    for _, item in ipairs(items_to_move) do
      local take = reaper.GetActiveTake(item)
      if take then reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", 1.0) end
      reaper.MoveMediaItemToTrack(item, tr1)
    end
    reaper.DeleteTrack(tr2)
    reaper.GetSetMediaTrackInfo_String(tr1, "P_NAME", merged_name, true)
    local parent1 = reaper.GetParentTrack(tr1)
    if parent1 then
      local fi = math.floor(reaper.GetMediaTrackInfo_Value(parent1, "IP_TRACKNUMBER")) - 1
      local folder_children, level = 0, 1
      for i = fi + 1, reaper.CountTracks(0) - 1 do
        local tr  = reaper.GetTrack(0, i)
        local d   = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        if reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 1 then
          folder_children = folder_children + 1
        end
        level = level + d
        if level <= 0 then break end
      end
      if folder_children == 0 then
        local folder_idx = math.floor(reaper.GetMediaTrackInfo_Value(parent1, "IP_TRACKNUMBER")) - 1
        reaper.SetOnlyTrackSelected(tr1)
        reaper.ReorderSelectedTracks(folder_idx, 0)
        local to_del, level2 = {}, 1
        fi = math.floor(reaper.GetMediaTrackInfo_Value(parent1, "IP_TRACKNUMBER")) - 1
        for i = fi + 1, reaper.CountTracks(0) - 1 do
          local tr = reaper.GetTrack(0, i)
          local d  = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
          table.insert(to_del, tr)
          level2 = level2 + d
          if level2 <= 0 then break end
        end
        for k = #to_del, 1, -1 do reaper.DeleteTrack(to_del[k]) end
        reaper.DeleteTrack(parent1)
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Merge to stereo: " .. merged_name, -1)
  return merged_name
end

function T.render(ctx, state)
  local btn_w              = state.btn_w
  local cfg                = state.cfg
  local H                  = state.H
  local set_log            = state.set_log
  local script_path        = state.script_path
  local folders_cache_time_ref = state.folders_cache_time_ref

  -- ImGui item spacing for accurate column width calculation
  local spacing = 8  -- approximate item spacing between columns

  -- ── AUTO ORGANIZE ────────────────────────────────────────
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
    H.rgb_to_imgui(40, 120, 60))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
    H.rgb_to_imgui(55, 150, 75))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
    H.rgb_to_imgui(30, 100, 50))
  if reaper.ImGui_Button(ctx, "▶  AUTO ORGANIZE", btn_w, 36) then
    H.run_script(script_path, "ReaOrganize.lua")
    folders_cache_time_ref[1] = 0
    set_log("ReaOrganize done")
  end
  reaper.ImGui_PopStyleColor(ctx, 3)

  reaper.ImGui_Spacing(ctx)

  -- Case à cocher "Create drum subfolders"
  local create_bus = reaper.GetExtState("MixAssist", "create_drum_bus") ~= "false"
  local cb, vb = reaper.ImGui_Checkbox(ctx, "Create drum subfolders", create_bus)
  if cb then
    reaper.SetExtState("MixAssist", "create_drum_bus", tostring(vb), true)
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Creates BD BUS, SD BUS, TOM BUS, OH BUS, ROOM BUS in [DR]")
    reaper.ImGui_Text(ctx, "Runs automatically after AUTO ORGANIZE")
    reaper.ImGui_EndTooltip(ctx)
  end

  -- Case à cocher "Auto-group stereo & multi-miked"
  local auto_group = reaper.GetExtState("MixAssist", "auto_group") == "true"
  local cg, vg = reaper.ImGui_Checkbox(ctx, "Auto-group stereo & multi-miked", auto_group)
  if cg then
    reaper.SetExtState("MixAssist", "auto_group", tostring(vg), true)
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Groups stereo pairs (L/R) and multi-mic tracks (DI/Amp...)")
    reaper.ImGui_Text(ctx, "into subfolders — all except [DR] which is already handled")
    reaper.ImGui_Text(ctx, "Runs automatically after AUTO ORGANIZE")
    reaper.ImGui_EndTooltip(ctx)
  end

  -- Case à cocher "Add gate on TOM BUS"
  local tom_gate = reaper.GetExtState("MixAssist", "tom_gate") == "true"
  local ctg, vtg = reaper.ImGui_Checkbox(ctx, "Add gate on TOM BUS", tom_gate)
  if ctg then
    reaper.SetExtState("MixAssist", "tom_gate", tostring(vtg), true)
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Adds gate plugin on TOM BUS after DR Bus Setup")
    reaper.ImGui_Text(ctx, "Plugin configurable in Options")
    reaper.ImGui_EndTooltip(ctx)
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- ── Move selection to folder (unified) ───────────────────
  local folders     = state.get_folders_cached()
  local sel_count   = reaper.CountSelectedTracks(0)
  local existing_map = {}
  for _, f in ipairs(folders) do existing_map[f.name] = f end

  local label = sel_count > 0
    and ("Move " .. sel_count .. " track(s) to")
    or  "Folders in project"
  reaper.ImGui_Text(ctx, label)
  reaper.ImGui_Spacing(ctx)

  -- Pré-calculer les sauts de ligne selon les largeurs réelles
  local spacing = 4
  local folders_to_show = {}
  for _, def in ipairs(cfg.FOLDERS) do
    if def.cat ~= "UNK" then
      local txt_w = reaper.ImGui_CalcTextSize(ctx, def.name)
      local w = math.min(btn_w - 8, txt_w + 16)
      table.insert(folders_to_show, { def = def, w = w })
    end
  end

  -- Construire les lignes
  local lines = {}
  local current_line = {}
  local current_w = 0
  for _, item in ipairs(folders_to_show) do
    local needed = (current_w > 0 and (current_w + spacing + item.w) or item.w)
    if needed > btn_w - 16 and #current_line > 0 then
      table.insert(lines, current_line)
      current_line = { item }
      current_w = item.w
    else
      table.insert(current_line, item)
      current_w = needed
    end
  end
  if #current_line > 0 then table.insert(lines, current_line) end

  local cnt = 0
  for _, line in ipairs(lines) do
    -- Calculer la largeur totale de la ligne
    local line_w = 0
    for li, item in ipairs(line) do
      line_w = line_w + item.w
      if li > 1 then line_w = line_w + spacing end
    end
    -- Centrer la ligne
    local offset = math.max(0, math.floor((btn_w - line_w) / 2))
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + offset)

    for li, item in ipairs(line) do
      local def      = item.def
      local existing = existing_map[def.name]
      local c        = def.color
      local col, col_h, col_a

      if existing then
        col   = H.rgb_to_imgui(c[1], c[2], c[3])
        col_h = H.lighten(col, 35)
        col_a = col
      else
        col   = H.rgb_to_imgui(35, 35, 35)
        col_h = H.rgb_to_imgui(50, 50, 50)
        col_a = H.rgb_to_imgui(35, 35, 35)
      end

      if li > 1 then reaper.ImGui_SameLine(ctx) end

      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),       col)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_h)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  col_a)
      if not existing then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),
          H.rgb_to_imgui(c[1], c[2], c[3]))
      end

      local clicked = reaper.ImGui_Button(ctx, def.name .. "##f" .. cnt, item.w, 24)

      if not existing then reaper.ImGui_PopStyleColor(ctx, 1) end
      reaper.ImGui_PopStyleColor(ctx, 3)

      if clicked and sel_count > 0 then
        if existing then
          local native = reaper.ColorToNative(c[1], c[2], c[3]) | 0x1000000
          H.move_selected_to_folder(existing.track, native)
        else
          local folder_tr, native = H.create_folder(cfg, def)
          H.move_selected_to_folder(folder_tr, native)
        end
        folders_cache_time_ref[1] = 0
        H.cleanup_unk_folder(cfg)
        set_log("Moved to " .. def.name)
      end

      cnt = cnt + 1
    end
  end

  -- ── Stereo merge ─────────────────────────────────────────
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Stereo pairs")
  reaper.ImGui_Spacing(ctx)

  -- Détecter les paires AutoGroup (dossiers enfants directs de [XX] avec 2 pistes L/R)
  local function detect_stereo_pairs()
    local pairs = {}
    local function has_lr(name)
      local n = name:lower()
      return n:match("[%s%._%-]l$") or n:match("[%s%._%-]r$")
          or n:match("[%s%._%-]dt$") or n:match("%.l$") or n:match("%.r$")
          or n:match(" left$") or n:match(" right$")
    end
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") >= 1 then
        local parent = reaper.GetParentTrack(tr)
        if parent then
          local children = H.get_direct_children(tr)
          -- Trouver les enfants L/R parmi tous les enfants
          local lr_children = {}
          for _, child in ipairs(children) do
            local _, cname = reaper.GetTrackName(child)
            if has_lr(cname) then
              table.insert(lr_children, child)
            end
          end
          -- Exactement 2 enfants L/R
          if #lr_children == 2 then
            local _, fname = reaper.GetTrackName(tr)
            table.insert(pairs, {
              folder = tr,
              parent = parent,
              tr1    = lr_children[1],
              tr2    = lr_children[2],
              name   = fname,
            })
          end
        end
      end
    end
    return pairs
  end

  -- Cache des paires pour éviter de recalculer entre le bouton et le popup
  local pairs = detect_stereo_pairs()

  local half_w = (btn_w - 4) / 2
  local col_merge = H.rgb_to_imgui(60, 90, 130)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col_merge)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  H.lighten(col_merge, 30))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   col_merge)
  if #pairs == 0 then reaper.ImGui_BeginDisabled(ctx) end
  if reaper.ImGui_Button(ctx, "⇔ Merge All (" .. #pairs .. ")##mergeall", half_w, 28) then
    _pending_pairs = pairs
    reaper.ImGui_OpenPopup(ctx, "Confirm Merge All")
  end
  if #pairs == 0 then reaper.ImGui_EndDisabled(ctx) end
  reaper.ImGui_PopStyleColor(ctx, 3)

  -- Popup confirmation Merge All
  if reaper.ImGui_BeginPopupModal(ctx, "Confirm Merge All", nil,
    reaper.ImGui_WindowFlags_AlwaysAutoResize and reaper.ImGui_WindowFlags_AlwaysAutoResize() or 0) then
    reaper.ImGui_Text(ctx, "Merge these " .. (_pending_pairs and #_pending_pairs or 0) .. " stereo pairs?")
    reaper.ImGui_Spacing(ctx)
    if _pending_pairs then
      for _, p in ipairs(_pending_pairs) do
        reaper.ImGui_TextDisabled(ctx, "  • " .. p.name)
      end
    end
    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_Button(ctx, "Merge##confirm", 120, 0) then
      if _pending_pairs then
        -- Merger en ordre inverse pour préserver les indices
        local sorted = {}
        for _, p in ipairs(_pending_pairs) do table.insert(sorted, p) end
        table.sort(sorted, function(a, b)
          return reaper.GetMediaTrackInfo_Value(a.folder, "IP_TRACKNUMBER") >
                 reaper.GetMediaTrackInfo_Value(b.folder, "IP_TRACKNUMBER")
        end)
        for _, p in ipairs(sorted) do
          if p.tr1 and p.tr2 and p.folder
          and reaper.ValidatePtr(p.tr1, "MediaTrack*")
          and reaper.ValidatePtr(p.tr2, "MediaTrack*")
          and reaper.ValidatePtr(p.folder, "MediaTrack*") then
            do_merge(p.tr1, p.tr2, p.folder)
          end
        end
        set_log("Merged " .. #_pending_pairs .. " stereo pairs")
        folders_cache_time_ref[1] = 0
        _pending_pairs = nil
      end
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel##cancelmerge", 120, 0) then
      _pending_pairs = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  reaper.ImGui_SameLine(ctx)

  -- Bouton Merge Selected
  -- Cas 1 : 2 pistes sélectionnées
  -- Cas 2 : 1 dossier sélectionné avec exactement 2 enfants L/R
  local sel_count = reaper.CountSelectedTracks(0)
  local tr1, tr2 = nil, nil
  local merge_folder = nil

  if sel_count == 2 then
    tr1 = reaper.GetSelectedTrack(0, 0)
    tr2 = reaper.GetSelectedTrack(0, 1)
  elseif sel_count == 1 then
    local sel = reaper.GetSelectedTrack(0, 0)
    if reaper.GetMediaTrackInfo_Value(sel, "I_FOLDERDEPTH") >= 1 then
      local children = H.get_direct_children(sel)
      local lr = {}
      for _, child in ipairs(children) do
        local _, cname = reaper.GetTrackName(child)
        local n = cname:lower()
        if n:match("[%s%._%-]l$") or n:match("[%s%._%-]r$")
        or n:match(" left$") or n:match(" right$")
        or n:match("%.l$") or n:match("%.r$") then
          table.insert(lr, child)
        end
      end
      if #lr == 2 then
        tr1 = lr[1]
        tr2 = lr[2]
        merge_folder = sel
      end
    end
  end

  local can_merge = tr1 ~= nil and tr2 ~= nil
  if not can_merge then reaper.ImGui_BeginDisabled(ctx) end

  if reaper.ImGui_Button(ctx, "⇔  Merge Selected##mergesel", half_w, 28) then
    do_merge(tr1, tr2, merge_folder)
  end

  if not can_merge then
    reaper.ImGui_EndDisabled(ctx)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Select 2 tracks (L first, then R)")
      reaper.ImGui_Text(ctx, "Or select a folder containing exactly 2 L/R tracks")
      reaper.ImGui_EndTooltip(ctx)
    end
  end

end

return T