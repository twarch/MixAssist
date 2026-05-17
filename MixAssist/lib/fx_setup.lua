-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- lib/fx_setup.lua — MixAssist
-- Applique les FXchains et crée les pistes parallèles
-- pour un dossier donné selon FXConfig.lua
-- ============================================================

local FS = {}

-- ── Chargement d'un FX ou FXchain ────────────────────────────
local function apply_fxchain(tr, fxchain_name)
  if not fxchain_name or fxchain_name == "" then return end

  -- Plugin direct (VST3:, AU:, JS:, VST:, etc.)
  if fxchain_name:match("^%a%w*:") then
    local fx_idx = reaper.TrackFX_AddByName(tr, fxchain_name, false, 1)
    if fx_idx < 0 then
      reaper.ShowConsoleMsg("FXConfig: Plugin introuvable: " .. fxchain_name .. "\n")
      return false
    end
    return true
  end

  -- FXchain (.RfxChain) — juste le nom du fichier, Reaper cherche dans FXChains/
  local resource = reaper.GetResourcePath()
  local path = resource .. "/FXChains/" .. fxchain_name
  local f = io.open(path, "r")
  if not f then
    reaper.ShowConsoleMsg("FXConfig: FXchain introuvable: " .. path .. "\n")
    return false
  end
  f:close()
  local fx_idx = reaper.TrackFX_AddByName(tr, fxchain_name, false, -1)
  if fx_idx < 0 then
    reaper.ShowConsoleMsg("FXConfig: Impossible de charger: " .. fxchain_name .. "\n")
    return false
  end
  return true
end

-- ── Créer un send pre/post fader ─────────────────────────────
local function create_send(src_tr, dst_tr, prefader, volume_db)
  local idx = reaper.CreateTrackSend(src_tr, dst_tr)
  if idx < 0 then return end
  -- Pre ou post fader
  local send_mode = prefader and 3 or 0
  reaper.SetTrackSendInfo_Value(src_tr, 0, idx, "I_SENDMODE", send_mode)
  -- Volume
  local vol_lin
  if volume_db == nil or volume_db <= -150 then
    vol_lin = 0  -- -inf
  else
    vol_lin = 10 ^ (volume_db / 20)
  end
  reaper.SetTrackSendInfo_Value(src_tr, 0, idx, "D_VOL", vol_lin)
  reaper.SetTrackSendInfo_Value(src_tr, 0, idx, "D_PAN", 0)
end

-- ── Trouver une piste par nom dans un dossier ─────────────────
local function find_child_by_name(folder_tr, name)
  local idx = math.floor(reaper.GetMediaTrackInfo_Value(folder_tr, "IP_TRACKNUMBER")) - 1
  local depth = 0
  for i = idx + 1, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local d  = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    local show = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")
    if show == 1 then
      local _, tname = reaper.GetTrackName(tr)
      if tname == name then return tr end
    end
    depth = depth + d
    if depth < 0 then break end
  end
  return nil
end

-- ── Trouver une piste par nom (global) ───────────────────────
local function find_track_global(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, tname = reaper.GetTrackName(tr)
    if tname == name then return tr end
  end
  return nil
end

-- ── Créer une piste parallèle ────────────────────────────────
local function create_parallel_track(folder_tr, par_cfg, par_color)
  local par_name = par_cfg.name
  if not par_name or par_name == "" then return end

  -- Vérifier si la piste existe déjà
  local existing = find_child_by_name(folder_tr, par_name)
    or find_track_global(par_name)
  if existing then
    -- Appliquer quand même la FXchain si définie
    if par_cfg.fxchain and par_cfg.fxchain ~= "" then
      apply_fxchain(existing, par_cfg.fxchain)
    end
    return existing
  end

  local folder_idx = math.floor(
    reaper.GetMediaTrackInfo_Value(folder_tr, "IP_TRACKNUMBER")) - 1

  local insert_pos
  if par_cfg.position == "internal" then
    -- Trouver la dernière piste dont le parent direct est folder_tr
    local last_visible_idx = folder_idx
    for i = reaper.CountTracks(0) - 1, folder_idx + 1, -1 do
      local tr = reaper.GetTrack(0, i)
      if reaper.GetParentTrack(tr) == folder_tr and
         reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 1 then
        last_visible_idx = i
        break
      end
    end
    insert_pos = last_visible_idx
  else
    -- Externe : juste après DR
    local depth = 1
    insert_pos = folder_idx + 1
    for i = folder_idx + 1, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      local d  = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
      depth = depth + d
      insert_pos = i + 1
      if depth <= 0 then break end
    end
  end

  -- Créer la piste
  reaper.InsertTrackAtIndex(insert_pos, false)
  local par_tr = reaper.GetTrack(0, insert_pos)
  reaper.GetSetMediaTrackInfo_String(par_tr, "P_NAME", par_name, true)

  -- Couleur violet
  if par_color then
    local native = reaper.ColorToNative(par_color[1], par_color[2], par_color[3]) | 0x1000000
    reaper.SetTrackColor(par_tr, native)
  end

  -- Piste externe : volume à -inf + groupée en Volume Follow
  if par_cfg.position == "external" then
    reaper.SetMediaTrackInfo_Value(par_tr, "D_VOL", 0)  -- -inf
    -- Group membership : Volume Follow dans le même groupe que le dossier parent
    -- Le groupe est basé sur l'index du dossier (1-based)
    local folder_group = math.floor(
      reaper.GetMediaTrackInfo_Value(folder_tr, "IP_TRACKNUMBER"))
    -- Limiter au max 32 groupes Reaper
    local group_num = math.min(folder_group, 32)
    -- folder_tr = Volume Lead
    reaper.GetSetTrackGroupMembership(folder_tr, "VOLUME_LEAD",   1 << (group_num-1), 1 << (group_num-1))
    -- par_tr = Volume Follow
    reaper.GetSetTrackGroupMembership(par_tr,    "VOLUME_FOLLOW", 1 << (group_num-1), 1 << (group_num-1))
  end

  -- Volume de la piste elle-même
  if par_cfg.track_volume ~= nil then
    if par_cfg.track_volume <= -150 then
      reaper.SetMediaTrackInfo_Value(par_tr, "D_VOL", 0) -- -inf
    else
      reaper.SetMediaTrackInfo_Value(par_tr, "D_VOL", 1.0) -- 0 dB
    end
  end

  -- FXchain
  if par_cfg.fxchain and par_cfg.fxchain ~= "" then
    apply_fxchain(par_tr, par_cfg.fxchain)
  end

  return par_tr
end

-- ── Créer les envois vers une piste parallèle ────────────────
local function set_group_flags(tr, is_master, group_num)
  local group_flag = 1 << (group_num - 1)
  local _, chunk = reaper.GetTrackStateChunk(tr, "", false)
  local flags = is_master and (group_flag .. " 0") or ("0 " .. group_flag)
  if chunk:find("GROUP_FLAGS") then
    chunk = chunk:gsub("GROUP_FLAGS [^\n]*", "GROUP_FLAGS " .. flags)
  else
    chunk = chunk:gsub("\n>%s*$", "\nGROUP_FLAGS " .. flags .. "\n>")
  end
  reaper.SetTrackStateChunk(tr, chunk, false)
end

local function create_sends_to_parallel(folder_tr, par_tr, par_cfg, H, all_par_names)
  local sources = {}
  if par_cfg.position == "internal" then
    local children = H.get_direct_children(folder_tr)
    for _, child in ipairs(children) do
      if child ~= par_tr then
        local _, cname = reaper.GetTrackName(child)
        local is_parallel = false
        if all_par_names then
          for _, pname in ipairs(all_par_names) do
            if cname == pname then is_parallel = true; break end
          end
        end
        if not is_parallel then
          table.insert(sources, child)
        end
      end
    end
  else
    table.insert(sources, folder_tr)
  end

  for _, src in ipairs(sources) do
    create_send(src, par_tr, par_cfg.prefader, par_cfg.volume or 1.0)
    if par_cfg.group then
      set_group_flags(src,    true,  par_cfg.group)
      set_group_flags(par_tr, false, par_cfg.group)
    end
  end
end

-- ── Fonction principale ───────────────────────────────────────
function FS.apply(cat, folder_tr, folder_cfg, H)
  if not folder_tr or not folder_cfg then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local par_color = { 144, 107, 250 }

  -- 1. FXchain sur le dossier
  if folder_cfg.fxchain and folder_cfg.fxchain ~= "" then
    apply_fxchain(folder_tr, folder_cfg.fxchain)
  end

  -- 2. FXchains sur les sous-bus (DR uniquement)
  if folder_cfg.sub_buses then
    for bus_name, bus_cfg in pairs(folder_cfg.sub_buses) do
      if bus_cfg.fxchain and bus_cfg.fxchain ~= "" then
        local bus_tr = find_child_by_name(folder_tr, bus_name)
        if bus_tr then
          apply_fxchain(bus_tr, bus_cfg.fxchain)
        end
      end
    end
  end

  -- 3. Pistes parallèles
  if folder_cfg.parallel then
    -- Collecter les noms pour exclure les parallèles des sends
    local all_par_names = {}
    for _, pc in ipairs(folder_cfg.parallel) do
      if pc.name and pc.name ~= "" then table.insert(all_par_names, pc.name) end
    end
    local internal_count = 0
    local external_count = 0
    for _, par_cfg in ipairs(folder_cfg.parallel) do
      local par_tr = create_parallel_track(folder_tr, par_cfg, par_color)
      if par_tr then
        create_sends_to_parallel(folder_tr, par_tr, par_cfg, H, all_par_names)
        if par_cfg.position == "internal" then
          internal_count = internal_count + 1
        else
          if external_count > 0 then
            reaper.SetOnlyTrackSelected(par_tr)
            for _ = 1, external_count do
              reaper.Main_OnCommand(43648, 0)
            end
          end
          external_count = external_count + 1
        end
      end
    end
    -- Remonter la dernière piste (OH) au-dessus des pistes internes créées
    if internal_count > 0 then
      local folder_idx2 = math.floor(reaper.GetMediaTrackInfo_Value(folder_tr, "IP_TRACKNUMBER")) - 1
      local last_tr = nil
      for i = reaper.CountTracks(0) - 1, folder_idx2 + 1, -1 do
        local tr = reaper.GetTrack(0, i)
        if reaper.GetParentTrack(tr) == folder_tr and
           reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 1 then
          last_tr = tr
          break
        end
      end
      if last_tr then
        reaper.SetOnlyTrackSelected(last_tr)
        for _ = 1, internal_count do
          reaper.Main_OnCommand(43647, 0)
        end
      end
    end
  end

  -- 4. Triggers BD et SD (DR uniquement)
  if cat == "DR" then
    local TRIGGER_COLOR  = reaper.ColorToNative(230, 190, 50) | 0x1000000
    local BD_TRIG_PLUGIN = reaper.GetExtState("MixAssist", "bd_trig_plugin")
    local SD_TRIG_PLUGIN = reaper.GetExtState("MixAssist", "sd_trig_plugin")
    local BD_TRIG_PRESET = reaper.GetExtState("MixAssist", "bd_trig_preset")
    local SD_TRIG_PRESET = reaper.GetExtState("MixAssist", "sd_trig_preset")
    if BD_TRIG_PLUGIN == "" then BD_TRIG_PLUGIN = "VST3: Trigger 2 (Steven Slate)" end
    if SD_TRIG_PLUGIN == "" then SD_TRIG_PLUGIN = "VST3: Trigger 2 (Steven Slate)" end

    local function find_in_bus(bus_tr, dtype_target)
      if not bus_tr then return nil end
      local bus_idx = math.floor(reaper.GetMediaTrackInfo_Value(bus_tr, "IP_TRACKNUMBER")) - 1
      local depth = 0
      for i = bus_idx + 1, reaper.CountTracks(0) - 1 do
        local tr   = reaper.GetTrack(0, i)
        local d    = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        if reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 1 then
          local dtype = H.drum_classify(({reaper.GetTrackName(tr)})[2])
          if dtype == dtype_target then return tr end
        end
        depth = depth + d
        if depth < 0 then break end
      end
      return nil
    end

    local function setup_trigger(bus_name, trig_name, dtype, plugin, preset)
      local bus_tr = find_child_by_name(folder_tr, bus_name)
      if not bus_tr then return end
      for i = 0, reaper.CountTracks(0) - 1 do
        local _, n = reaper.GetTrackName(reaper.GetTrack(0, i))
        if n == trig_name then return end
      end
      local src_tr = find_in_bus(bus_tr, dtype)

      -- Trouver la dernière piste visible du bus
      local bus_idx2 = math.floor(reaper.GetMediaTrackInfo_Value(bus_tr, "IP_TRACKNUMBER")) - 1
      local last_child_idx = bus_idx2
      local last_child_tr = nil
      local depth2 = 1
      for i = bus_idx2 + 1, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local d  = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        if reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 1 then
          last_child_idx = i
          last_child_tr = tr
        end
        depth2 = depth2 + d
        if depth2 <= 0 then break end
      end

      -- Insérer le trigger avant la dernière piste du bus
      reaper.InsertTrackAtIndex(last_child_idx, false)
      local trig_tr = reaper.GetTrack(0, last_child_idx)
      reaper.GetSetMediaTrackInfo_String(trig_tr, "P_NAME", trig_name, true)
      reaper.SetTrackColor(trig_tr, TRIGGER_COLOR)

      -- Remonter la dernière piste d'un cran pour qu'elle reste dernière
      if last_child_tr then
        reaper.SetOnlyTrackSelected(last_child_tr)
        reaper.Main_OnCommand(43647, 0) -- Track: Move selected tracks up
      end
      reaper.GetSetMediaTrackInfo_String(trig_tr, "P_NAME", trig_name, true)
      reaper.SetTrackColor(trig_tr, TRIGGER_COLOR)
      if src_tr then
        local idx = reaper.CreateTrackSend(src_tr, trig_tr)
        if idx >= 0 then
          reaper.SetTrackSendInfo_Value(src_tr, 0, idx, "I_SENDMODE", 3)
          reaper.SetTrackSendInfo_Value(src_tr, 0, idx, "D_VOL", 1.0)
        end
      end
      if plugin and plugin ~= "" then
        local fx_idx = reaper.TrackFX_AddByName(trig_tr, plugin, false, 1)
        if fx_idx >= 0 and preset and preset ~= "" then
          reaper.TrackFX_SetPreset(trig_tr, fx_idx, preset)
        end
      end
    end

    setup_trigger("BD BUS", "BD Trigger", "BD_IN",  BD_TRIG_PLUGIN, BD_TRIG_PRESET)
    setup_trigger("SD BUS", "SD Trigger", "SD_TOP", SD_TRIG_PLUGIN, SD_TRIG_PRESET)
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("FX Setup - " .. cat, -1)
end

return FS
