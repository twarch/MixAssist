-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- ReaOrganize.lua  v6  — ReaOrganizer
-- Classe, colorie et ordonne automatiquement les pistes.
-- Réutilise les dossiers [XX] existants si présents.
-- Nécessite : Config.lua dans le même dossier
-- ============================================================

-- ============================================================
-- Chargement de la configuration centralisée
-- UserConfig.lua est prioritaire sur Config.lua
-- ============================================================

local script_path = ({ reaper.get_action_context() })[2]:match("(.+[\\/])")
local function load_config()
  local user_path = script_path .. "UserConfig.lua"
  local f = io.open(user_path, "r")
  if f then f:close(); return dofile(user_path) end
  return dofile(script_path .. "Config.lua")
end
local cfg = load_config()

-- ============================================================
-- DICTIONNAIRE DE MOTS-CLÉS (classification par catégorie)
-- ============================================================

local KEYWORDS = {

  DR = {
    "kick", "kik", " bd ", "bass drum", "grosse caisse",
    "kick in", "kick out", "kick top", "kick bot",
    "sub kick", "bd in", "bd out",
    "snare", "caisse claire", "snr", " sd ", " sn ",
    "sd top", "sd bot", "sd rim", "snare top", "snare bot",
    "sn top", "sn bot", "sn t", "sn b",
    "snare rim", "rimshot", "rim shot",
    " clap",
    "hihat", "hi-hat", "hi hat",
    " hh ", "ohh", "chh",
    "open hat", "closed hat", " hat", "hat",
    " tom", "floor tom", " ft ", "rack tom",
    "tom hi", "tom lo", "tom mid",
    " rack", " floor",
    " t1 ", " t2 ", " t3 ", " t4 ",
    "ride", "crash", "cymbal", "cymbale", " cym",
    "splash", "china cym",
    "overhead", "overheads", "over head", "over heads", "ovhd", " ovh",
    "oh's", "oh s", " oh ", "ohl", "ohr",
    "room", "drum room", "ambiance batt",
    "drum amb", "kit amb",
    "drum", "drums", "batterie", "batt",
    "trigger", "sample dr", "drm",
  },

  PE = {
    "perc", "percussion",
    "conga", "bongo", "djembe",
    "shaker", "tambourin", "tamb", "pandeiro",
    "cajon", "claves", "woodblock", "wood block",
    "cowbell", "cow bell",
    "triangle", "agogo", "cabasa", "maracas",
    "tabla", "darbuka", "riq", "bendir",
    "body perc", "timbale", "timb",
    "timpani", "tymp", "timp",
    "crotale", "glock", "glockenspiel",
    "sleigh", "windchime", "guiro", "cloche",
  },

  BA = {
    "bass guitar", "bass gtr", "bgtr", "b.gtr",
    "basse elec", "basse electrique", "electric bass",
    "bass di", "bass amp", "bass cab", "bass mic",
    "bassdi", "bassmic", "bassamp",
    "elec bass", "el bass",
    "contrebasse", "upright bass", "double bass",
    "upright", "db bass", "acoustic bass",
    "808", "sub bass", "subbass", "sub synth",
    "low end",
    " bass ", "basse ",
  },

  AG = {
    "acoustic guitar", "guitare acoustique",
    "acoustic gtr", "ac. guitar", "ac guitar", "ac.gtr", "ac gtr",
    "acgtr", "a. guitar", "a.guitar", "a guitar",
    " ag ", " acg ",
    "folk guitar", "nylon guitar", "classical guitar", "spanish guitar",
    "fingerpick", "fingerstyle",
    "12 string", "12-string",
    "mandolin", "mandoline", " mand",
    "banjo", " bj ",
    "ukulele", "ukelele", " uke",
    "dobro", "resonator",
    "harp", "harpe", "luth", " lute", "sitar",
    "acoustic ", " aco", "aco ", " acst", "acst ",
  },

  EG = {
    "electric guitar", "guitare electrique", "guitare elec",
    "electric gtr", "elec guitar", "elec gtr",
    "el. guitar", "el.gtr", "el gtr",
    "e. guitar", "e.gtr",
    " eg ", " elg ", "egtr", "e gtr", "elecgtr", "elec_gtr",
    "lead gtr", "rhythm gtr", "lead guitar", "rhythm guitar",
    "gtr lead", "gtr rhyt",
    "distortion gtr", "crunch gtr", "clean gtr",
    "slide guitar", "slide solo", "steel guitar", "pedal steel", "stg",
    "strat", "telecaster", "tele", "les paul", "sg gtr",
    "riff gtr", " el ",
    " gtr", "guitar", "guitare",
    " elect", "elect ", " steel", "steel ",
  },

  KB = {
    "piano", "grand piano", "upright piano", "a. piano", "e. piano",
    " pno",
    "rhodes", "wurlitzer", "wurli", "elec piano", "el piano",
    "electric piano", "e-piano", "epiano",
    "clavinet", "clavi",
    "organ", "orgue", "hammond", " b3 ", "leslie",
    "electric organ", "pipe organ",
    "keyboard", "claviers", " keys", " key ", " kb ", " kbd",
    "harpsichord", "clavecin", "celeste", " cel ",
    "vibraphone", " vib ", " vibe", "vibraharp", "vbh",
    "marimba", " mar ", "xylophone", " xyl",
    "glockenspiel", " glsp",
    "tubular bell", "chimes",
    "accordion", "accordeon",
  },

  SY = {
    "synth", "synthesizer", "synthe", "synthi", " snt",
    "syn pad", "syn lead", "syn bass",
    "syn arp", "syn seq",
    "trance lead", "tr ld",
    "poly synth", "mono synth",
    "wavetable", "fm synth", "analog synth",
    "moog", "prophet", "juno", "dx7", "oberheim", "minimoog",
    "ms-20", "arp synth", "seq synth",
    " pad ", " arp ", "pluck synth",
  },

  ST = {
    "strings", "string ",
    "cordes",
    "violin", "violon", " vln", " vn ",
    "viola", " va ", " vla",
    "cello", "violoncelle", " vc ",
    "contrabass str", "string bass",
    "orchestra str", "orch str", "orchestre cordes",
    "chamber str", "string quartet", "quartet str",
    "pizz", " arco", "tremolo str", "ensemble str",
  },

  BR = {
    "brass", "cuivre",
    "trumpet", "trompette", " tpt",
    "trombone", " tbn", " trbn",
    "french horn", "cor ", " hn ",
    " horn", "horns",
    " tuba", "flugelhorn", "flugel horn", " flhn",
    "bugle", "cornet", "euphonium",
  },

  WW = {
    "woodwind", "bois ",
    " sax", "saxophone", "saxo",
    "alto sax", "tenor sax", "bari sax", "soprano sax",
    " asax", " tsax", " bsax", " ssax",
    "oboe", "hautbois",
    "clarinet", "clarinette", " cl ",
    "bassoon", "basson",
    "flute", "flûte", "piccolo",
    "recorder", "flageolet",
  },

  LV = {
    "lead voc", "lead vocal", "lead voice",
    "lead vox", "vox lead", "vocal lead",
    "voix lead", "voix principale",
    "chant lead", "chanteur", "chanteuse",
    "main voc", "main vocal",
    "topline", "top line",
    "lvox", "l vox", "ld vox", " lv ",
    "leadvox", "lead_vox",
    " voc ",
  },

  BV = {
    "backing voc", "backing vocal", "backing voice", "backing vox",
    "background voc", "background vocal", "background voice",
    "bg voc", "bg vocal", " bgv", "bkg voc",
    "bvox", "b vox", "bg vox",
    "backingvox", "backing_vox",
    "adlib", "ad lib", "ad-lib",
    "choir", "choeur", "chorus voc",
    "gang vocal", "shout voc",
    "harmony voc", "harmonie voc",
    "vox harm", "voc harm",
    "bv1", "bv2", "bv3", " bv ",
  },

  DV = {
    "double voc", "double vocal", "dbl voc",
    "vox double", "vocal double", "voix double",
    "voc dbl", "dbl vox", " dv ",
    "vox dt", "vocal dt", "lead dt", "ld dt", " lv dt",
  },

  SP = {
    "sample",
  },

  FX = {
    "reverb", "revb", "delay", "echo",
    " fx ", "fx bus", "fx send", "fx ret",
    " send", "return", " aux ",
    "bus rev", "bus del", "bus fx",
    "parallel comp", "comp par", "parallel",
    "room verb", "hall verb", "plate verb",
  },

  SFX = {
    " sfx", "sound fx", "sound effect",
    "riser", "impact", "whoosh",
    "foley", "noise sfx",
    "sweep", "downlifter", "uplifter",
    "transition fx", "transition sfx",
    "stab sfx", "hit sfx",
  },
}

-- Si UserConfig contient des KEYWORDS personnalisés, on les fusionne
if cfg.KEYWORDS then
  for cat, kws in pairs(cfg.KEYWORDS) do
    if not KEYWORDS[cat] then
      KEYWORDS[cat] = kws
    else
      -- Ajouter les keywords custom sans dupliquer
      local existing = {}
      for _, kw in ipairs(KEYWORDS[cat]) do existing[kw] = true end
      for _, kw in ipairs(kws) do
        if not existing[kw] then
          table.insert(KEYWORDS[cat], kw)
        end
      end
    end
  end
end

-- ============================================================
-- RANG DRUMS
-- ============================================================

local function drum_rank(name)
  local n = " " .. name:lower():gsub("[_%-%.]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "") .. " "
  local function has(kw) return n:find(kw, 1, true) ~= nil end

  if has("kick") or has(" kik") or has(" bd ") or has("bass drum") or has("grosse caisse") then
    if has("sample") or has("trig") or has("smpl") or has("sub kick") then return 30 end
    if has(" out") or has("ext") or has("outside") or has("front") then return 20 end
    return 10
  end

  if has("snare") or has(" snr") or has(" sd ") or has(" sn ") or has("caisse claire") then
    if has("sample") or has("trig") or has("smpl") then return 60 end
    if has("bot") or has("btm") or has("bottom") or has("down") or has(" bt ")
    or n:match(" bt$") or has(" b ") or n:match(" sd b$") or n:match(" snare b$")
    or n:match("sd_b ") or n:match("snare_b ") or n:match("snare_bt ")
    or n:match(" snare bt$") or n:match(" sn b$") or n:match(" sn bt$")
    or has("sn bot") or has("sn b ") then return 50 end
    return 40
  end

  if has(" clap") then return 60 end

  if has("floor") or has(" ft ") or has("tom floor") or has("tom lo")
  or has("tom low") or n:match(" t4 ") or n:match(" tom 4 ") then return 100 end

  local tom_num = n:match(" t(%d+) ") or n:match(" tom (%d+) ")
                  or n:match("tomh") and "1"
                  or n:match("tomm") and "2"
  if tom_num then return 70 + tonumber(tom_num) end

  if has(" rack") or has("rack tom") then return 75 end
  if has(" tom") then return 76 end

  if has("hihat") or has("hi-hat") or has("hi hat")
  or has(" hh ") or has("chh") or has("ohh")
  or has("open hat") or has("closed hat") or has(" hat ") or n:match("hat%d") then return 110 end

  if has("ride") then return 120 end

  if has("crash") or has("splash") or has("china")
  or has("cymbal") or has("cymbale") or has(" cym") then return 130 end

  if has("overhead") or has("ovhd") or has(" ovh")
  or has("oh's") or has(" oh ") or has(" ohl") or has(" ohr")
  or n:match(" oh ") then return 140 end

  if has("room") or has("drum room") or has("ambiance")
  or has("drum amb") or has("kit amb") then return 160 end

  return 500
end

-- ============================================================
-- OFFSET TRI L/R
-- Retourne un fine offset (0=L, 0.5=neutre, 1=R)
-- utilisé uniquement comme critère secondaire de départage
-- au sein de pistes ayant le même index de base.
-- ============================================================

local function sort_offset(name)
  local n = name:lower():gsub("_", " "):gsub("-", " "):gsub("%s+", " ")
                        :gsub("^%s+", ""):gsub("%s+$", "")

  -- Suffixe L ou Left
  if n:match("%s+l$") or n:match("%s+left$") or n:match("%.l$") then return 0 end

  -- Suffixe R ou Right
  if n:match("%s+r$") or n:match("%s+right$") or n:match("%.r$") then return 1 end

  -- Suffixe numérique → utiliser comme fine offset
  local num = n:match("%s+(%d+)%s*$")
  if num then return tonumber(num) * 0.1 end

  return -0.5  -- pistes sans suffixe → avant L
end

-- ============================================================
-- Helpers
-- ============================================================

local function rgb_to_native(r, g, b)
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function get_color(cat)
  local fx_c = cfg.FX_COLOR
  if cat == "FX" then return rgb_to_native(fx_c[1], fx_c[2], fx_c[3]) end
  local def = cfg.BY_CAT[cat]
  if def then return rgb_to_native(def.color[1], def.color[2], def.color[3]) end
  return rgb_to_native(100, 100, 100)
end

local function get_folder_name(cat)
  local def = cfg.BY_CAT[cat]
  return def and def.name or ("[" .. cat .. "]")
end

local function normalize(name)
  local s = name
  -- Split CamelCase avant normalisation
  s = s:gsub("(%l)(%u)", "%1 %2")
  s = s:gsub("(%a)(%d)", "%1 %2")
  s = s:gsub("(%d)(%a)", "%1 %2")
  s = s:lower():gsub("_", " "):gsub("-", " "):gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("%s+", " ")
  return " " .. s .. " "
end

local function str_contains(str, kw)
  return str:find(kw, 1, true) ~= nil
end

local function already_in_folder(tr)
  local parent = reaper.GetParentTrack(tr)
  if not parent then return false end
  local _, pname = reaper.GetTrackName(parent)
  if pname == cfg.BY_CAT["UNK"].name then return false end
  return pname:match("^%[.+%]$") ~= nil
end

-- ============================================================
-- Classification
-- ============================================================

local PRIORITY = {
  "DR","PE","BA","AG","EG","KB","SY","ST","BR","WW",
  "LV","BV","DV","SP","FX","SFX"
}

-- Ajouter les catégories custom de UserConfig à PRIORITY
for _, def in ipairs(cfg.FOLDERS) do
  local already = false
  for _, cat in ipairs(PRIORITY) do
    if cat == def.cat then already = true; break end
  end
  if not already and def.cat ~= "UNK" then
    table.insert(PRIORITY, def.cat)
  end
end

local function classify(name)
  local n = normalize(name)
  for _, cat in ipairs(PRIORITY) do
    local kws = KEYWORDS[cat]
    if kws then
      for _, kw in ipairs(kws) do
        if str_contains(n, kw) then return cat end
      end
    end
  end
  return "UNK"
end

-- ============================================================
-- Insérer un dossier
-- ============================================================

local function insert_folder(idx, label, color, depth)
  reaper.InsertTrackAtIndex(idx, false)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", label, true)
  reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", depth or 1)
  reaper.SetTrackColor(tr, color)
  return tr
end

-- ============================================================
-- Scanner les dossiers existants dans le projet
-- ============================================================

local function scan_existing_folders()
  local existing = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if depth >= 1 and cfg.BY_NAME[name] then
      existing[cfg.BY_NAME[name].cat] = tr
    end
  end
  return existing
end

-- ============================================================
-- MAIN
-- ============================================================

local total = reaper.CountTracks(0)
if total == 0 then
  reaper.ShowMessageBox("Aucune piste dans le projet.", "OrganisePistes", 0)
  return
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Ordre des catégories depuis cfg
local FOLDER_ORDER = {}
for _, def in ipairs(cfg.FOLDERS) do
  table.insert(FOLDER_ORDER, def.cat)
end

-- ── 1. Snapshot ──────────────────────────────────────────────
local tracks = {}
for i = 0, total - 1 do
  local tr = reaper.GetTrack(0, i)
  local _, name = reaper.GetTrackName(tr)
  if not name:match("^%[.+%]$") and not already_in_folder(tr) then
    local cat = classify(name)
    -- Pour DR : rang drum précis + offset L/R
    -- Pour les autres : index original * 10 + offset L/R
    -- L'index original préserve l'ordre d'arrivée des pistes
    -- L'offset L/R (0/0.5/1) sert uniquement à grouper les paires
    local rank
    if cat == "DR" then
      rank = drum_rank(name) + sort_offset(name)
    else
      rank = i * 10 + sort_offset(name)
    end
    table.insert(tracks, { track = tr, name = name, cat = cat, rank = rank, orig_idx = i })
  end
end

-- ── 2. Colorier FX sans déplacer ─────────────────────────────
-- (FX maintenant déplacé dans [FX] comme les autres catégories)

-- ── 3. Catégories nécessaires ────────────────────────────────
local needed = {}
for _, info in ipairs(tracks) do
  if not info.done then needed[info.cat] = true end
end

-- ── 4. Dossiers existants + création si nécessaire ───────────
local folder_tracks = scan_existing_folders()

for _, cat in ipairs(FOLDER_ORDER) do
  if cat == "UNK" then goto continue end
  if not needed[cat] then goto continue end
  if folder_tracks[cat] then goto continue end

  local base_idx = reaper.CountTracks(0)
  local folder = insert_folder(base_idx, get_folder_name(cat), get_color(cat), 1)
  folder_tracks[cat] = folder

  -- Closer temporaire pour éviter que le dossier suivant tombe dedans
  reaper.InsertTrackAtIndex(base_idx + 1, false)
  local closer = reaper.GetTrack(0, base_idx + 1)
  reaper.GetSetMediaTrackInfo_String(closer, "P_NAME", "__closer__", true)
  reaper.SetMediaTrackInfo_Value(closer, "I_FOLDERDEPTH", -1)
  reaper.SetMediaTrackInfo_Value(closer, "B_SHOWINTCP", 0)
  reaper.SetMediaTrackInfo_Value(closer, "B_SHOWINMIXER", 0)
  local show_check = reaper.GetMediaTrackInfo_Value(closer, "B_SHOWINTCP")
  local d_check = reaper.GetMediaTrackInfo_Value(closer, "I_FOLDERDEPTH")
  local _, n_check = reaper.GetTrackName(closer)

  ::continue::
end

-- Créer [?] en dernier
if needed["UNK"] and not folder_tracks["UNK"] then
  local base_idx = reaper.CountTracks(0)
  local folder = insert_folder(base_idx, get_folder_name("UNK"), get_color("UNK"), 1)
  folder_tracks["UNK"] = folder
  reaper.InsertTrackAtIndex(base_idx + 1, false)
  local closer = reaper.GetTrack(0, base_idx + 1)
  reaper.GetSetMediaTrackInfo_String(closer, "P_NAME", "__closer__", true)
  reaper.SetMediaTrackInfo_Value(closer, "I_FOLDERDEPTH", -1)
  reaper.SetMediaTrackInfo_Value(closer, "B_SHOWINTCP", 0)
  reaper.SetMediaTrackInfo_Value(closer, "B_SHOWINMIXER", 0)
end

-- ── 5. Déplacer les pistes ───────────────────────────────────
local H = dofile(script_path .. "lib/helpers.lua")


local function move_track_after(tr, folder_tr)
  local dest_idx = math.floor(
    reaper.GetMediaTrackInfo_Value(folder_tr, "IP_TRACKNUMBER"))
  reaper.SetOnlyTrackSelected(tr)
  reaper.ReorderSelectedTracks(dest_idx, 2)
end

-- Drums : tri décroissant par rang (kick déplacé en dernier → apparaît en tête)
local drum_tracks = {}
for _, info in ipairs(tracks) do
  if not info.done and info.cat == "DR" then
    table.insert(drum_tracks, info)
  end
end
table.sort(drum_tracks, function(a, b)
  if a.rank == b.rank then return a.name:lower() > b.name:lower() end
  return a.rank > b.rank
end)

local dr_folder = folder_tracks["DR"]
if dr_folder then
  for _, info in ipairs(drum_tracks) do
    move_track_after(info.track, dr_folder)
    reaper.SetTrackColor(info.track, get_color("DR"))
    info.done = true
  end
  local nc = 0
  for i = 0, reaper.CountTracks(0)-1 do
    local _, n = reaper.GetTrackName(reaper.GetTrack(0,i))
    if n == "__closer__" then nc = nc + 1 end
  end
end

-- Toutes les autres catégories — triées par sort_offset (L avant R, Mic 1 avant Mic 2)
for _, cat in ipairs(FOLDER_ORDER) do
  if cat == "DR" or cat == "UNK" then goto continue end

  local cat_tracks = {}
  for _, info in ipairs(tracks) do
    if not info.done and info.cat == cat then
      table.insert(cat_tracks, info)
    end
  end

  table.sort(cat_tracks, function(a, b)
    if a.rank == b.rank then return a.name:lower() > b.name:lower() end
    return a.rank > b.rank
  end)

  local folder = folder_tracks[cat]
  if folder then
    for _, info in ipairs(cat_tracks) do
      move_track_after(info.track, folder)
      reaper.SetTrackColor(info.track, get_color(cat))
      info.done = true
    end
    -- Compter les closers restants
    local nc = 0
    for i = 0, reaper.CountTracks(0)-1 do
      local _, n = reaper.GetTrackName(reaper.GetTrack(0,i))
      if n == "__closer__" then nc = nc + 1 end
    end
      -- Fixer depth=-1 sur le dernier enfant immédiatement
    local children = H.get_direct_children(folder)
    if #children > 0 then
      reaper.SetMediaTrackInfo_Value(children[#children], "I_FOLDERDEPTH", -1)
    end
  end

  ::continue::
end

-- Non identifiées → [?]
for _, info in ipairs(tracks) do
  if not info.done then
    local folder = folder_tracks["UNK"]
    if folder then
      move_track_after(info.track, folder)
      reaper.SetTrackColor(info.track, get_color("UNK"))
      info.done = true
    end
  end
end
local nc = 0
for i = 0, reaper.CountTracks(0)-1 do
  local _, n = reaper.GetTrackName(reaper.GetTrack(0,i))
  if n == "__closer__" then nc = nc + 1 end
end

-- ── 6. Post-organisation optionnelle ─────────────────────────

-- Supprimer les closers avant Undo_EndBlock
-- Pour chaque closer, la piste juste au-dessus prend depth-1
for i = reaper.CountTracks(0) - 1, 0, -1 do
  local tr  = reaper.GetTrack(0, i)
  local _, name = reaper.GetTrackName(tr)
  if name == "__closer__" then
    -- Trouver la piste visible juste au-dessus
    for j = i - 1, 0, -1 do
      local above = reaper.GetTrack(0, j)
      if reaper.GetMediaTrackInfo_Value(above, "B_SHOWINTCP") == 1 then
        local above_d = reaper.GetMediaTrackInfo_Value(above, "I_FOLDERDEPTH")
        reaper.SetMediaTrackInfo_Value(above, "I_FOLDERDEPTH", above_d - 1)
        break
      end
    end
    reaper.DeleteTrack(tr)
  end
end

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("ReaOrganize — classification automatique", -1)

-- DR Bus Setup si case cochée
local create_bus = reaper.GetExtState("MixAssist", "create_drum_bus") ~= "false"
if create_bus then
  local dr_setup = script_path .. "DR_Bus_Setup.lua"
  local f = io.open(dr_setup, "r")
  if f then f:close(); dofile(dr_setup) end
end

-- AutoGroup si case cochée
local auto_group = reaper.GetExtState("MixAssist", "auto_group") == "true"
if auto_group then
  local ag = script_path .. "AutoGroup.lua"
  local f = io.open(ag, "r")
  if f then f:close(); dofile(ag) end
end

-- Supprimer les closers : avant suppression, décrémenter le depth de la piste du dessus
for i = 0, reaper.CountTracks(0) - 1 do
  local tr   = reaper.GetTrack(0, i)
  local show = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")
  local d    = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
  local _, name = reaper.GetTrackName(tr)
  if show < 1 and name == "__closer__" and d <= -1 then
    local parent = reaper.GetParentTrack(tr)
    local _, pname = parent and reaper.GetTrackName(parent) or nil, "ROOT"
    if not parent then pname = "ROOT" else pname = ({reaper.GetTrackName(parent)})[2] end
    end
end
for i = reaper.CountTracks(0) - 1, 0, -1 do
  local tr   = reaper.GetTrack(0, i)
  local show = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")
  local d    = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
  local _, name = reaper.GetTrackName(tr)
  if show < 1 and name == "__closer__" and d <= -1 then
    -- La piste juste au-dessus doit absorber ce niveau de fermeture
    if i > 0 then
      local above = reaper.GetTrack(0, i - 1)
      local above_d = reaper.GetMediaTrackInfo_Value(above, "I_FOLDERDEPTH")
      reaper.SetMediaTrackInfo_Value(above, "I_FOLDERDEPTH", above_d - 1)
    end
    reaper.DeleteTrack(tr)
  end
end

-- Nettoyer [?] si vide
H.cleanup_unk_folder(cfg)