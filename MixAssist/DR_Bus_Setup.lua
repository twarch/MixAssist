-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- DR_Bus_Setup.lua — MixAssist
-- Crée les sous-bus dans [DR]
-- Appelé par ReaOrganize.lua si case cochée
-- ============================================================

local script_path = ({reaper.get_action_context()})[2]:match("^(.*[\\/])")
local H = dofile(script_path .. "lib/helpers.lua")

-- ── Config ───────────────────────────────────────────────────
local DR_FOLDER_NAME  = "[DR]"
local TOM_GATE_ENABLED = reaper.GetExtState("MixAssist", "tom_gate") == "true"
local TOM_GATE_PLUGIN  = reaper.GetExtState("MixAssist", "tom_gate_plugin")
if TOM_GATE_PLUGIN == "" then TOM_GATE_PLUGIN = "VST: ReaGate (Cockos)" end

local BUS_ORDER = { "BD", "SD", "TOM" }

local BUS_DEFS = {
  BD   = { name = "BD BUS",  min_tracks = 1 },
  SD   = { name = "SD BUS",  min_tracks = 1 },
  TOM  = { name = "TOM BUS", min_tracks = 1 },
  OH   = { name = "OH BUS",  min_tracks = 2 },
  ROOM = { name = "ROOM BUS",min_tracks = 2 },
}

-- ── Classification ───────────────────────────────────────────
local function bus_for_type(dtype)
  if dtype == "BD_IN" or dtype == "BD_OUT" or dtype == "BD_SUB" or dtype == "BD_TRIGGER" then return "BD" end
  if dtype == "SD_TOP" or dtype == "SD_BOT" or dtype == "SD_TRIGGER" then return "SD" end
  if dtype == "TOM"  then return "TOM" end
  if dtype == "OH"   then return "OH" end
  if dtype == "ROOM" then return "ROOM" end
  return nil
end

-- ── Tri ──────────────────────────────────────────────────────
local function tom_order(name)
  local n = name:lower()
  if n:find("floor") or n:find(" ft ") or n:find(" fl ") then return 100 end
  local num = n:match("tom%s*(%d+)") or n:match("rack%s*(%d+)") or n:match(" t(%d+) ")
  if num then return tonumber(num) end
  if n:find("high") or n:find("hi ") then return 1 end
  if n:find("mid")  then return 2 end
  if n:find("low")  then return 3 end
  return 50
end

local function bd_order(dtype)
  if dtype == "BD_IN"      then return 1 end
  if dtype == "BD_OUT"     then return 2 end
  if dtype == "BD_SUB"     then return 3 end
  if dtype == "BD_TRIGGER" then return 4 end
  return 5
end

local function other_subtype(name)
  local n = name:lower()
  if n:find("clap") or n:find("rimshot") or n:find("rim shot") then return "CLAP" end
  if n:find("hat") or n:find("hh") then return "HAT" end
  if n:find("cymbal") or n:find("ride") or n:find("crash")
  or n:find("china") or n:find("splash") then return "CYM" end
  if n:find("overhead") or n:find("overh") then return "OH" end
  if n:find("room") or n:find("ambient") then return "ROOM_SGL" end
  return "OTHER"
end

-- ── Helpers locaux ───────────────────────────────────────────
local function find_dr_folder()
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if name == DR_FOLDER_NAME and depth >= 1 then return tr, i end
  end
  return nil, nil
end

local function get_visible_children(folder_idx)
  local children = {}
  local level = 1
  for i = folder_idx + 1, reaper.CountTracks(0) - 1 do
    local tr   = reaper.GetTrack(0, i)
    local d    = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    local show = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")
    if show == 1 then table.insert(children, tr) end
    level = level + d
    if level <= 0 then break end
  end
  return children
end

-- ── Main ─────────────────────────────────────────────────────
local dr_folder, dr_idx = find_dr_folder()
if not dr_folder then return end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- 1. Classer les pistes
local drum_tracks     = get_visible_children(dr_idx)
local by_bus          = { BD={}, SD={}, TOM={}, OH={}, ROOM={}, OTHER={} }
local by_bus_dtype    = { BD={} }

for _, tr in ipairs(drum_tracks) do
  local _, name = reaper.GetTrackName(tr)
  local dtype   = H.drum_classify(name)
  local bus     = bus_for_type(dtype) or "OTHER"
  table.insert(by_bus[bus], tr)
  if bus == "BD" then
    table.insert(by_bus_dtype.BD, { tr=tr, dtype=dtype })
  end
end

-- Trier BD : In → Out → Sub → Trigger
table.sort(by_bus_dtype.BD, function(a, b) return bd_order(a.dtype) < bd_order(b.dtype) end)
by_bus.BD = {}
for _, item in ipairs(by_bus_dtype.BD) do table.insert(by_bus.BD, item.tr) end

-- Trier TOM : aigu → grave
table.sort(by_bus.TOM, function(a, b)
  local _, na = reaper.GetTrackName(a)
  local _, nb = reaper.GetTrackName(b)
  return tom_order(na) < tom_order(nb)
end)

-- ── Helper : créer un sous-dossier avec 42785 ────────────────
local function make_subfolder(tracks_list, folder_name, color)
  if #tracks_list == 0 then return nil end
  -- Trier L avant R selon leur position actuelle
  table.sort(tracks_list, function(a, b)
    local _, na = reaper.GetTrackName(a)
    local _, nb = reaper.GetTrackName(b)
    local pan_a = H.detect_lr_pan(na)
    local pan_b = H.detect_lr_pan(nb)
    -- L (-1.0) avant R (1.0), nil au milieu
    local va = pan_a or 0
    local vb = pan_b or 0
    return va < vb
  end)
  -- Réordonner les pistes dans le projet (L d'abord, puis R)
  -- On déplace chaque piste à la bonne position
  local min_idx = math.huge
  for _, tr in ipairs(tracks_list) do
    local idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
    if idx < min_idx then min_idx = idx end
  end
  -- Déplacer dans l'ordre voulu
  local insert_at = min_idx
  for _, tr in ipairs(tracks_list) do
    local cur_idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
    if cur_idx ~= insert_at then
      reaper.SetOnlyTrackSelected(tr)
      reaper.ReorderSelectedTracks(insert_at, 0)
    end
    insert_at = insert_at + 1
  end
  -- Trouver l'index minimum des pistes à grouper
  local min_idx = math.huge
  for _, tr in ipairs(tracks_list) do
    local idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
    if idx < min_idx then min_idx = idx end
  end
  -- Sélectionner les pistes
  reaper.Main_OnCommand(40297, 0)
  for _, tr in ipairs(tracks_list) do
    reaper.SetTrackSelected(tr, true)
  end
  -- Créer le dossier — il sera inséré à min_idx
  reaper.Main_OnCommand(42785, 0)
  -- Le nouveau dossier est à min_idx (les pistes ont été décalées d'un index)
  local folder_tr = reaper.GetTrack(0, min_idx)
  if folder_tr then
    reaper.GetSetMediaTrackInfo_String(folder_tr, "P_NAME", folder_name, true)
    if color then reaper.SetTrackColor(folder_tr, color) end
  end
  return folder_tr
end

-- 2. Construire les BUS avec 42785
local DR_COLOR = reaper.GetTrackColor(find_dr_folder())

for _, bus_key in ipairs(BUS_ORDER) do
  local def    = BUS_DEFS[bus_key]
  local tracks = by_bus[bus_key]
  if #tracks < (def.min_tracks or 1) then goto continue end

  local bus_tr = make_subfolder(tracks, def.name, DR_COLOR)

  if bus_key == "TOM" and TOM_GATE_ENABLED and bus_tr then
    local fx_idx = reaper.TrackFX_AddByName(bus_tr, TOM_GATE_PLUGIN, false, 1)
    if fx_idx < 0 then
      reaper.ShowConsoleMsg("Gate TOM BUS: plugin '" .. TOM_GATE_PLUGIN .. "' introuvable\n")
    end
  end

  ::continue::
end

-- 3. OTHER + OH BUS + ROOM BUS
local OTHER_BEFORE_ROOM = { "CLAP", "HAT", "CYM", "OH" }
local OTHER_AFTER_ROOM  = { "ROOM_SGL", "OTHER" }
local by_other = { CLAP={}, HAT={}, CYM={}, OH={}, ROOM_SGL={}, OTHER={} }
for _, tr in ipairs(by_bus.OTHER) do
  local _, name = reaper.GetTrackName(tr)
  table.insert(by_other[other_subtype(name)], tr)
end

-- Pistes libres avant OH BUS (CLAP, HAT, CYM, OH simples)
-- Déjà dans [DR] — rien à faire, leur ordre vient de ReaOrganize

-- OH BUS
local oh_tracks = by_bus["OH"]
if #oh_tracks >= (BUS_DEFS["OH"].min_tracks or 2) then
  local bus_tr = make_subfolder(oh_tracks, BUS_DEFS["OH"].name, DR_COLOR)
  if bus_tr then
    for _, tr in ipairs(oh_tracks) do
      local _, tname = reaper.GetTrackName(tr)
      local pan = H.detect_lr_pan(tname)
      if pan then reaper.SetMediaTrackInfo_Value(tr, "D_PAN", pan) end
    end
  end
else
  -- Pas assez → laisser les pistes libres dans [DR]
end

-- ROOM BUS
local room_tracks = by_bus["ROOM"]
if #room_tracks >= (BUS_DEFS["ROOM"].min_tracks or 2) then
  local bus_tr = make_subfolder(room_tracks, BUS_DEFS["ROOM"].name, DR_COLOR)
  if bus_tr then
    for _, tr in ipairs(room_tracks) do
      local _, tname = reaper.GetTrackName(tr)
      local pan = H.detect_lr_pan(tname)
      if pan then reaper.SetMediaTrackInfo_Value(tr, "D_PAN", pan) end
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()

-- Normaliser les depths dans [DR]

reaper.Undo_EndBlock("DR Bus Setup", -1)
