-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- lib/helpers.lua — ReaOrganizer
-- Fonctions utilitaires partagées entre tous les modules.
-- ============================================================

local H = {}

-- ============================================================
-- Couleurs ImGui
-- ============================================================

function H.rgb_to_imgui(r, g, b, a)
  a = a or 255
  return ((r & 0xFF) << 24) | ((g & 0xFF) << 16) | ((b & 0xFF) << 8) | (a & 0xFF)
end

function H.native_to_imgui(native)
  native = native & 0xFFFFFF
  local r = (native >> 16) & 0xFF
  local g = (native >> 8)  & 0xFF
  local b =  native        & 0xFF
  return H.rgb_to_imgui(r, g, b, 255)
end

function H.lighten(c, amt)
  local r = math.min(255, ((c >> 24) & 0xFF) + amt)
  local g = math.min(255, ((c >> 16) & 0xFF) + amt)
  local b = math.min(255, ((c >> 8)  & 0xFF) + amt)
  return H.rgb_to_imgui(r, g, b, 255)
end

function H.color_for_cat(cfg, cat)
  local def = cfg.BY_CAT and cfg.BY_CAT[cat]
  if def then return H.rgb_to_imgui(def.color[1], def.color[2], def.color[3]) end
  return H.rgb_to_imgui(100, 100, 100)
end

-- ============================================================
-- Helpers projet
-- ============================================================

function H.find_track(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, n = reaper.GetTrackName(tr)
    if n == name then return tr end
  end
  return nil
end

function H.find_track_containing(kw)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, n = reaper.GetTrackName(tr)
    if n:lower():find(kw, 1, true) then return tr end
  end
  return nil
end

function H.is_folder(tr)
  local _, name = reaper.GetTrackName(tr)
  local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
  return name:match("^%[.+%]$") and depth >= 1
end

function H.get_project_folders()
  local folders = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if name:match("^%[.+%]$") and depth >= 1 then
      local color = reaper.GetTrackColor(tr)
      table.insert(folders, { name = name, track = tr, color = color })
    end
  end
  return folders
end

function H.child_exists_in(folder_name, child_name)
  local folder = H.find_track(folder_name)
  if not folder then return false end
  local folder_idx = math.floor(reaper.GetMediaTrackInfo_Value(folder, "IP_TRACKNUMBER")) - 1
  local total = reaper.CountTracks(0)
  local level = 1
  for i = folder_idx + 1, total - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, n = reaper.GetTrackName(tr)
    local d = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if n == child_name then return true end
    level = level + d
    if level <= 0 then break end
  end
  return false
end

function H.master_has_fx()
  local master = reaper.GetMasterTrack(0)
  return reaper.TrackFX_GetCount(master) > 0
end

function H.run_script(script_path, filename)
  local path = script_path .. filename
  local f = io.open(path, "r")
  if not f then
    reaper.ShowConsoleMsg("Script introuvable : " .. path .. "\n")
    return false
  end
  f:close()
  dofile(path)
  return true
end

-- ============================================================
-- Nettoyage dossier [?]
-- ============================================================

function H.cleanup_unk_folder(cfg)
  local unk_name = cfg.BY_CAT and cfg.BY_CAT["UNK"] and cfg.BY_CAT["UNK"].name or "[?]"
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if name == unk_name and depth >= 1 then
      local has_children = false
      local total = reaper.CountTracks(0)
      local level = 1
      for j = i + 1, total - 1 do
        local child = reaper.GetTrack(0, j)
        local d     = reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
        local show  = reaper.GetMediaTrackInfo_Value(child, "B_SHOWINTCP")
        if show == 1 then has_children = true; break end
        level = level + d
        if level <= 0 then break end
      end
      if not has_children then
        local to_delete = {}
        local lvl = 1
        for j = i + 1, reaper.CountTracks(0) - 1 do
          local child = reaper.GetTrack(0, j)
          local d = reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
          table.insert(to_delete, child)
          lvl = lvl + d
          if lvl <= 0 then break end
        end
        for k = #to_delete, 1, -1 do
          reaper.DeleteTrack(to_delete[k])
        end
        reaper.DeleteTrack(tr)
      end
      break
    end
  end
end

-- ============================================================
-- Déplacement de pistes vers un dossier
-- ============================================================

function H.move_selected_to_folder(folder_tr, native_color)
  local sel_trs = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    table.insert(sel_trs, reaper.GetSelectedTrack(0, i))
  end

  -- Filtrer : ne garder que les pistes dont le parent n'est pas aussi sélectionné
  -- (évite de déplacer les enfants séparément quand leur dossier est sélectionné)
  local sel_set = {}
  for _, tr in ipairs(sel_trs) do sel_set[tostring(tr)] = true end

  local roots = {}
  for _, tr in ipairs(sel_trs) do
    local parent = reaper.GetParentTrack(tr)
    if not parent or not sel_set[tostring(parent)] then
      table.insert(roots, tr)
    end
  end

  -- Trouver la position de fin du dossier cible
  local folder_idx = math.floor(
    reaper.GetMediaTrackInfo_Value(folder_tr, "IP_TRACKNUMBER")) - 1
  local depth = 0
  local end_idx = folder_idx + 1
  for i = folder_idx + 1, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local d  = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    depth = depth + d
    if depth < 0 then end_idx = i; break end
    end_idx = i + 1
  end

  reaper.Undo_BeginBlock()

  -- Séparer les pistes simples des dossiers
  local simple_tracks = {}
  local folder_tracks = {}
  for _, tr in ipairs(roots) do
    if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") >= 1 then
      table.insert(folder_tracks, tr)
    else
      table.insert(simple_tracks, tr)
    end
  end

  -- Déplacer d'abord les pistes simples
  for _, tr in ipairs(simple_tracks) do
    reaper.SetOnlyTrackSelected(tr)
    reaper.ReorderSelectedTracks(end_idx, 2)
    reaper.SetTrackColor(tr, native_color)
    local new_idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
    end_idx = new_idx + 1
  end

  -- Déplacer ensuite les dossiers (avec leurs enfants)
  for _, tr in ipairs(folder_tracks) do
    reaper.SetOnlyTrackSelected(tr)
    local tr_idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
    local lvl = 0
    for i = tr_idx + 1, reaper.CountTracks(0) - 1 do
      local child = reaper.GetTrack(0, i)
      local d = reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
      reaper.SetTrackSelected(child, true)
      lvl = lvl + d
      if lvl < 0 then break end
    end
    reaper.ReorderSelectedTracks(end_idx, 2)
    reaper.SetTrackColor(tr, native_color)
    local new_idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
    -- Avancer end_idx après ce dossier et ses enfants
    lvl = 0
    for i = new_idx + 1, reaper.CountTracks(0) - 1 do
      local child = reaper.GetTrack(0, i)
      local d = reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
      lvl = lvl + d
      end_idx = i + 1
      if lvl < 0 then break end
    end
  end
  reaper.Main_OnCommand(40297, 0)
  for _, tr in ipairs(sel_trs) do reaper.SetTrackSelected(tr, true) end
  reaper.Undo_EndBlock("MoveToFolder", -1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

-- ============================================================
-- Création d'un dossier à la bonne position
-- ============================================================

function H.create_folder(cfg, def)
  local c = def.color
  local native_color = reaper.ColorToNative(c[1], c[2], c[3]) | 0x1000000

  -- Trouver la bonne position selon l'ordre logique
  local insert_idx = reaper.CountTracks(0)
  local new_rank = 0
  for i, d in ipairs(cfg.FOLDERS) do
    if d.cat == def.cat then new_rank = i; break end
  end
  for i = new_rank + 1, #cfg.FOLDERS do
    local d = cfg.FOLDERS[i]
    local existing = H.find_track(d.name)
    if existing then
      insert_idx = math.floor(
        reaper.GetMediaTrackInfo_Value(existing, "IP_TRACKNUMBER")) - 1
      break
    end
  end

  -- Créer le dossier
  reaper.InsertTrackAtIndex(insert_idx, false)
  local folder_tr = reaper.GetTrack(0, insert_idx)
  reaper.GetSetMediaTrackInfo_String(folder_tr, "P_NAME", def.name, true)
  reaper.SetMediaTrackInfo_Value(folder_tr, "I_FOLDERDEPTH", 1)
  reaper.SetTrackColor(folder_tr, native_color)

  -- Piste de fermeture masquée
  reaper.InsertTrackAtIndex(insert_idx + 1, false)
  local closer = reaper.GetTrack(0, insert_idx + 1)
  reaper.GetSetMediaTrackInfo_String(closer, "P_NAME", "", true)
  reaper.SetMediaTrackInfo_Value(closer, "I_FOLDERDEPTH", -1)
  reaper.SetTrackColor(closer, native_color)
  reaper.SetMediaTrackInfo_Value(closer, "B_SHOWINTCP",   0)
  reaper.SetMediaTrackInfo_Value(closer, "B_SHOWINMIXER", 0)

  return folder_tr, native_color
end


-- ============================================================
-- Utilitaires pistes partagés
-- ============================================================

-- Enfants directs d'un dossier (pistes visibles, 1 niveau)
function H.get_direct_children(folder_track)
  local result = {}
  local idx    = math.floor(reaper.GetMediaTrackInfo_Value(folder_track, "IP_TRACKNUMBER")) - 1
  local depth  = 0
  for i = idx + 1, reaper.CountTracks(0) - 1 do
    local tr   = reaper.GetTrack(0, i)
    local d    = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    local show = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")
    -- Enfant direct = parent immédiat est folder_track
    if show == 1 and reaper.GetParentTrack(tr) == folder_track then
      table.insert(result, tr)
    end
    depth = depth + d
    if depth < 0 then break end
  end
  return result
end

-- Pistes feuilles d'une liste (descend dans les sous-dossiers)
function H.get_leaf_tracks(tracks)
  local leaves = {}
  for _, tr in ipairs(tracks) do
    if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") >= 1 then
      for _, c in ipairs(H.get_direct_children(tr)) do
        table.insert(leaves, c)
      end
    else
      table.insert(leaves, tr)
    end
  end
  return leaves
end

-- Vérifie si une piste a du contenu audio réel
function H.has_audio(tr)
  for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local item = reaper.GetTrackMediaItem(tr, j)
    local take = reaper.GetActiveTake(item)
    if take then
      local src = reaper.GetMediaItemTake_Source(take)
      if reaper.GetMediaSourceFileName(src, "") ~= "" then return true end
    end
  end
  return false
end

-- Insère une piste à l'index donné avec nom/depth/couleur
function H.insert_track_at(idx, name, depth, hidden, volume, color)
  reaper.InsertTrackAtIndex(idx, false)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", depth or 0)
  reaper.SetMediaTrackInfo_Value(tr, "D_VOL", volume or 1.0)
  if color then reaper.SetTrackColor(tr, color) end
  if hidden then
    reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP",   0)
    reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)
  end
  return tr
end

-- Détecte pan L/C/R depuis le nom d'une piste
function H.detect_lr_pan(name)
  local n = " " .. name:lower():gsub("_", " ") .. " "
  if n:find(" r ") or n:find(" right ") or n:find("%.r ") then return  1.0 end
  if n:find(" l ") or n:find(" left ")  or n:find("%.l ") then return -1.0 end
  if n:find(" c ") or n:find(" center ") or n:find(" centre ") then return 0.0 end
  if name:match("%d+R$") or name:match("[a-zA-Z]R$") then return  1.0 end
  if name:match("%d+L$") or name:match("[a-zA-Z]L$") then return -1.0 end
  if name:match("%d+C$") or name:match("[a-zA-Z]C$") then return  0.0 end
  return nil
end

-- Convertisseurs dB ↔ linéaire
function H.lin_to_db(v)
  if v <= 0 then return -math.huge end
  return 20 * math.log(v) / math.log(10)
end

function H.db_to_lin(db)
  return 10 ^ (db / 20)
end

-- Déplace une piste à une position (mode 0 = sans changer la parenté)
function H.move_track_to(tr, pos)
  reaper.SetOnlyTrackSelected(tr)
  reaper.ReorderSelectedTracks(pos, 0)
  return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
end

-- ============================================================
-- Classification drum partagée
-- ============================================================

function H.drum_classify(name)
  local n = name:lower()
  n = n:gsub("(%l)(%u)", "%1 %2")
  n = n:gsub("(%a)(%d)", "%1 %2")
  n = n:gsub("(%d)(%a)", "%1 %2")
  n = n:gsub("_", " ")
  n = n:gsub("-", " ")
  n = n:gsub("^%s+", "")
  n = n:gsub("%s+$", "")
  n = " " .. n .. " "
  local function has(kw) return n:find(kw, 1, true) ~= nil end

  if has("kick") or has(" kik ") or has(" bd ") or has("bass drum") or has("grosse caisse") then
    if has("sample") or has("trig") or has("smpl") then return "BD_TRIGGER" end
    if has(" sub ") then return "BD_SUB" end
    if has(" out ") or has("ext") or has("outside") or has("front") then return "BD_OUT" end
    return "BD_IN"
  end

  if has("snare") or has(" snr ") or has(" sd ") or has(" sn ") or has("caisse claire") then
    if has("sample") or has("trig") or has("smpl") then return "SD_TRIGGER" end
    if has("bot") or has("btm") or has("bottom") or has("down") or has(" bt ")
    or n:match(" bt$") or n:match(" sn b") or n:match(" sd b") then return "SD_BOT" end
    return "SD_TOP"
  end

  if has("clap") or has("rimshot") or has("rim shot") then return "CLAP" end

  if has(" tom") or has(" rack") or has(" floor") or has(" ft ")
  or n:match(" t%d ") then return "TOM" end

  if has("hihat") or has("hi hat") or has("hi-hat")
  or has(" hh ") or has("ohh") or has("chh")
  or has("open hat") or has("closed hat") or has(" hat") then return "HAT" end

  if has("overhead") or has("overheads") or has("over head") or has("over heads")
  or has("ovhd") or has(" ovh")
  or has("oh's") or has(" oh ") or has("ohl") or has("ohr") then return "OH" end

  if has("ride") or has("crash") or has("china")
  or has("splash") or has("cymbal") or has("cymbale") then return "CYM" end

  if has("room") or has("drum room") or has("ambiance")
  or has("drum amb") or has("kit amb") then return "ROOM" end

  return "OTHER"
end


return H
