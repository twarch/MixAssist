-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- AutoGroup.lua — MixAssist
-- Regroupe les pistes stéréo (L/R) et multi-micros en
-- sous-dossiers dans chaque [XX] sauf [DR]
-- Appelé par ReaOrganize.lua si case cochée
-- ============================================================

local script_path = ({reaper.get_action_context()})[2]:match("^(.*[\\/])")
local H = dofile(script_path .. "lib/helpers.lua")

local cfg_ok, cfg = pcall(dofile, script_path .. "UserConfig.lua")
if not cfg_ok then cfg_ok, cfg = pcall(dofile, script_path .. "Config.lua") end
local cfg_folders = (cfg_ok and cfg and cfg.FOLDERS) or {}

local EXCLUDED = { ["[DR]"] = true }

-- ── Tokens de micro/stéréo à ignorer ─────────────────────────
local MIC_SUFFIXES = {
  ["l"]=true, ["r"]=true, ["c"]=true, ["dt"]=true,
  ["left"]=true, ["right"]=true, ["center"]=true, ["centre"]=true, ["middle"]=true,
  ["mid"]=true, ["side"]=true,
  ["mic"]=true, ["mike"]=true,
  ["di"]=true, ["amp"]=true, ["reamp"]=true,
  ["in"]=true, ["out"]=true,
  ["close"]=true, ["far"]=true,
  ["top"]=true, ["bottom"]=true, ["bot"]=true, ["btm"]=true,
  ["room"]=true, ["ambient"]=true,
  -- Note: neck/bridge/body/clean/dirty/wet/dry retirés car trop ambigus
}

-- ── Tokenisation ──────────────────────────────────────────────
local function tokenize(name)
  local n = name
  n = n:gsub("(%l)(%u)", "%1 %2")
  n = n:gsub("(%a)(%d)", "%1 %2")
  n = n:gsub("(%d)(%a)", "%1 %2")
  n = n:gsub("[_%-%.]+", " ")
  local tokens = {}
  for token in n:gmatch("%S+") do
    table.insert(tokens, token)
  end
  return tokens
end

-- ── Nom de base (sans numéro de piste ni suffixes mic) ────────
local function get_base_name(name)
  local tokens = tokenize(name)
  local result = {}

  -- Retirer le numéro de piste en début
  if tokens[1] and tokens[1]:match("^%d+$") then
    table.remove(tokens, 1)
  end

  -- Trouver le dernier token suffixe mic
  local last_mic_idx = nil
  for i, t in ipairs(tokens) do
    if MIC_SUFFIXES[t:lower()] then last_mic_idx = i end
  end

  -- Pas de suffixe mic → retourner le nom complet sans numéro de piste
  if not last_mic_idx then
    return table.concat(tokens, " "):match("^%s*(.-)%s*$")
  end

  -- Collecter les tokens avant le dernier suffixe mic
  for j = 1, last_mic_idx - 1 do
    local t = tokens[j]
    if not MIC_SUFFIXES[t:lower()] then
      table.insert(result, t)
    end
  end

  return table.concat(result, " "):match("^%s*(.-)%s*$")
end

-- ── Détecte suffixe explicite de multi-mic ou stéréo ─────────
local function has_explicit_suffix(name)
  local n = name
  n = n:gsub("(%l)(%u)", "%1 %2")
  n = n:gsub("(%a)(%d)", "%1 %2")
  n = n:gsub("(%d)(%a)", "%1 %2")
  n = n:gsub("^%d+[%s_]+", "")
  n = " " .. n:lower():gsub("[_%-%.]+", " ") .. " "

  if n:find(" l ", 1, true) or n:find(" r ", 1, true) or n:find(" c ", 1, true) then return true end
  if n:match(" [lrc]%d+ ") or n:match(" [lrc]%d+$") then return true end
  -- DT (doubled track)
  if n:find(" dt ", 1, true) or n:match(" dt$") or n:find("_dt ") or n:match("_dt$") then return true end

  local long_suffixes = {
    "mic", "mike", "di", "amp", "reamp",
    "close", "far", "top", "bottom", "bot", "btm",
    "left", "right", "center", "centre", "middle",
    "inside", "outside", "front", "back",
  }
  for _, s in ipairs(long_suffixes) do
    if n:find(" " .. s .. " ", 1, true) then return true end
    if n:match(" " .. s .. "%d*%s") then return true end
    if n:match(" " .. s .. "%d*$") then return true end
  end
  return false
end


local function auto_group_folder(folder_name, folder_color)
  local folder = H.find_track(folder_name)
  if not folder then return end

  local children = H.get_direct_children(folder)
  if #children == 0 then return end

  -- Étape 1 : calculer base et suffixe pour chaque piste
  local track_bases   = {}
  local track_suffix  = {}
  local all_tracks    = {}

  for _, tr in ipairs(children) do
    local is_bus = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") >= 1
    if is_bus then goto skip end
    if not H.has_audio(tr) then goto skip end

    local _, name = reaper.GetTrackName(tr)
    local base = get_base_name(name)
    if base == "" then base = name end

    table.insert(all_tracks, tr)
    track_bases[tr]  = base
    track_suffix[tr] = has_explicit_suffix(name)

    ::skip::
  end

  -- Étape 2 : trouver les bases qui ont au moins une piste avec suffixe explicite
  local bases_with_suffix = {}
  for _, tr in ipairs(all_tracks) do
    if track_suffix[tr] then
      bases_with_suffix[track_bases[tr]] = true
    end
  end

  -- Étape 3 : grouper toutes les pistes dont la base a au moins un suffixe
  local groups      = {}
  local group_order = {}
  for _, tr in ipairs(all_tracks) do
    local base = track_bases[tr]
    if bases_with_suffix[base] then
      if not groups[base] then
        groups[base] = {}
        table.insert(group_order, base)
      end
      table.insert(groups[base], tr)
    end
  end

  local grouped = 0
  for _, base in ipairs(group_order) do
    local group = groups[base]
    if #group >= 2 then
      -- Appliquer pan L/R avant de créer le dossier
      for _, tr in ipairs(group) do
        local _, tname = reaper.GetTrackName(tr)
        local pan = H.detect_lr_pan(tname)
        if pan == nil then
          local tn = tname:lower()
          if tn:match("dt$") or tn:match(" dt ") or tn:match("_dt") then
            pan = 1.0
          elseif bases_with_suffix[track_bases[tr]] and not track_suffix[tr] then
            local has_dt_sibling = false
            for _, tr2 in ipairs(group) do
              local _, tn2 = reaper.GetTrackName(tr2)
              if tn2:lower():match("dt$") or tn2:lower():match("_dt") then
                has_dt_sibling = true; break
              end
            end
            if has_dt_sibling then pan = -1.0 end
          end
        end
        if pan then reaper.SetMediaTrackInfo_Value(tr, "D_PAN", pan) end
      end

      -- Trier L avant R dans le projet
      table.sort(group, function(a, b)
        local _, na = reaper.GetTrackName(a)
        local _, nb = reaper.GetTrackName(b)
        local pan_a = H.detect_lr_pan(na) or 0
        local pan_b = H.detect_lr_pan(nb) or 0
        return pan_a < pan_b
      end)
      -- Réordonner dans le projet
      local min_idx = math.huge
      for _, tr in ipairs(group) do
        local idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
        if idx < min_idx then min_idx = idx end
      end
      local insert_at = min_idx
      for _, tr in ipairs(group) do
        local cur_idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
        if cur_idx ~= insert_at then
          reaper.SetOnlyTrackSelected(tr)
          reaper.ReorderSelectedTracks(insert_at, 0)
        end
        insert_at = insert_at + 1
      end

      -- Trouver l'index minimum du groupe
      local min_idx = math.huge
      for _, tr in ipairs(group) do
        local idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
        if idx < min_idx then min_idx = idx end
      end

      -- Sélectionner les pistes et créer le dossier
      reaper.Main_OnCommand(40297, 0)
      for _, tr in ipairs(group) do
        reaper.SetTrackSelected(tr, true)
      end
      reaper.Main_OnCommand(42785, 0)

      -- Le dossier est à min_idx
      local bus_tr = reaper.GetTrack(0, min_idx)
      if bus_tr then
        reaper.GetSetMediaTrackInfo_String(bus_tr, "P_NAME", base, true)
        if folder_color and folder_color ~= 0 then
          reaper.SetTrackColor(bus_tr, folder_color)
        end
      end

      grouped = grouped + #group
    end
  end

  return grouped
end

-- ── Main ──────────────────────────────────────────────────────
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for i = 0, reaper.CountTracks(0) - 1 do
  local tr = reaper.GetTrack(0, i)
  local _, name = reaper.GetTrackName(tr)
  if name:match("^%[.+%]$") and not EXCLUDED[name] then
    local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if depth >= 1 then
      local color = reaper.GetTrackColor(tr)
      auto_group_folder(name, color)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("AutoGroup — stereo & multi-mic", -1)
