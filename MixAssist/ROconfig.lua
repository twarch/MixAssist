-- ============================================================
-- ROConfig.lua  v1  — ReaOrganizer
-- Interface de configuration : catégories, couleurs, mots-clés.
-- Sauvegarde dans UserConfig.lua (Config.lua reste intact).
-- Nécessite : ReaImGui + Config.lua dans le même dossier
-- ============================================================

-- ============================================================
-- Chargement de la configuration
-- ============================================================

local script_path = ({ reaper.get_action_context() })[2]:match("(.+[\\/])")

local function load_config()
  local user_path = script_path .. "UserConfig.lua"
  local f = io.open(user_path, "r")
  if f then f:close(); return dofile(user_path) end
  return dofile(script_path .. "Config.lua")
end

-- Deep copy d'une table
local function deep_copy(orig)
  local copy = {}
  for k, v in pairs(orig) do
    copy[k] = (type(v) == "table") and deep_copy(v) or v
  end
  return copy
end

-- ============================================================
-- Vérification ReaImGui
-- ============================================================

if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox(
    "Ce script nécessite l'extension ReaImGui.\nInstallez-la via ReaPack.",
    "MixAssist", 0)
  return
end

-- ============================================================
-- État de l'application
-- ============================================================

local cfg_ref  = load_config()           -- config chargée (référence)
local folders  = deep_copy(cfg_ref.FOLDERS)  -- état de travail
local fx_color = deep_copy(cfg_ref.FX_COLOR)

local selected_cat  = 1                  -- index de la catégorie sélectionnée
local dirty         = false              -- modifications non sauvegardées
local status_msg    = ""                 -- message de statut en bas
local status_timer  = 0

-- Mots-clés : table séparée indexée par cat pour l'édition
-- Chargés depuis ReaOrganize.lua (les KEYWORDS hardcodés)
-- On les stocke ici pour l'édition et la sauvegarde dans UserConfig

local DEFAULT_KEYWORDS = {
  DR  = {
    "kick","kik"," bd ","bass drum","grosse caisse",
    "kick in","kick out","kick top","kick bot",
    "sub kick","bd in","bd out",
    "snare","caisse claire","snr"," sd "," sn ",
    "sd top","sd bot","sd rim","snare top","snare bot",
    "sn top","sn bot","sn t","sn b",
    "snare rim","rimshot","rim shot"," clap",
    "hihat","hi-hat","hi hat"," hh ","ohh","chh",
    "open hat","closed hat"," hat ",
    " tom","floor tom"," ft ","rack tom",
    "tom hi","tom lo","tom mid"," rack"," floor",
    " t1 "," t2 "," t3 "," t4 ",
    "ride","crash","cymbal","cymbale"," cym",
    "splash","china cym","overhead","ovhd"," ovh",
    "oh's","oh s"," oh ","ohl","ohr",
    "room","drum room","ambiance batt","drum amb","kit amb",
    "drum","drums","batterie","batt","trigger","sample dr","drm",
  },
  PE  = {
    "perc","percussion","conga","bongo","djembe",
    "shaker","tambourin","tamb","pandeiro",
    "cajon","claves","woodblock","wood block",
    "cowbell","cow bell","triangle","agogo","cabasa","maracas",
    "tabla","darbuka","riq","bendir","body perc","timbale","timb",
    "timpani","tymp","timp","crotale","glock","glockenspiel",
    "sleigh","windchime","guiro","cloche",
  },
  BA  = {
    "bass guitar","bass gtr","bgtr","b.gtr",
    "basse elec","basse electrique","electric bass",
    "bass di","bass amp","bass cab","bass mic",
    "bassdi","bassmic","bassamp","elec bass","el bass",
    "contrebasse","upright bass","double bass",
    "upright","db bass","acoustic bass",
    "808","sub bass","subbass","sub synth","low end",
    " bass ","basse ",
  },
  AG  = {
    "acoustic guitar","guitare acoustique",
    "acoustic gtr","ac. guitar","ac guitar","ac.gtr","ac gtr",
    "acgtr","a. guitar","a.guitar","a guitar"," ag "," acg ",
    "folk guitar","nylon guitar","classical guitar","spanish guitar",
    "fingerpick","fingerstyle","12 string","12-string",
    "mandolin","mandoline"," mand","banjo"," bj ",
    "ukulele","ukelele"," uke","dobro","resonator",
    "harp","harpe","luth","lute","sitar",
    "acoustic "," aco","aco "," acst","acst ",
  },
  EG  = {
    "electric guitar","guitare electrique","guitare elec",
    "electric gtr","elec guitar","elec gtr",
    "el. guitar","el.gtr","el gtr","e. guitar","e.gtr",
    " eg "," elg ","egtr","e gtr","elecgtr","elec_gtr",
    "lead gtr","rhythm gtr","lead guitar","rhythm guitar",
    "gtr lead","gtr rhyt","distortion gtr","crunch gtr","clean gtr",
    "slide guitar","slide solo","steel guitar","pedal steel","stg",
    "strat","telecaster","tele","les paul","sg gtr","riff gtr"," el ",
    " gtr","guitar","guitare"," elect","elect "," steel","steel ",
  },
  KB  = {
    "piano","grand piano","upright piano","a. piano","e. piano"," pno",
    "rhodes","wurlitzer","wurli","elec piano","el piano",
    "electric piano","e-piano","epiano","clavinet","clavi",
    "organ","orgue","hammond"," b3 ","leslie","electric organ","pipe organ",
    "keyboard","claviers"," keys"," key "," kb "," kbd",
    "harpsichord","clavecin","celeste"," cel ",
    "vibraphone"," vib "," vibe","vibraharp","vbh",
    "marimba"," mar ","xylophone"," xyl","glockenspiel"," glsp",
    "tubular bell","chimes","accordion","accordeon",
  },
  SY  = {
    "synth","synthesizer","synthe","synthi"," snt",
    "syn pad","syn lead","syn bass","syn arp","syn seq",
    "trance lead","tr ld","poly synth","mono synth",
    "wavetable","fm synth","analog synth",
    "moog","prophet","juno","dx7","oberheim","minimoog",
    "ms-20","arp synth","seq synth"," pad "," arp ","pluck synth",
  },
  ST  = {
    "strings","string ","cordes",
    "violin","violon"," vln"," vn ",
    "viola"," va "," vla","cello","violoncelle"," vc ",
    "contrabass str","string bass",
    "orchestra str","orch str","orchestre cordes",
    "chamber str","string quartet","quartet str",
    "pizz"," arco","tremolo str","ensemble str",
  },
  BR  = {
    "brass","cuivre","trumpet","trompette"," tpt",
    "trombone"," tbn"," trbn","french horn","cor anglais"," hn ",
    " horn","horns"," tuba","flugelhorn","flugel horn"," flhn",
    "bugle","cornet","euphonium",
    " sax","saxophone","saxo",
    "alto sax","tenor sax","bari sax","soprano sax",
    " asax"," tsax"," bsax"," ssax",
    "oboe","hautbois","clarinet","clarinette"," cl ",
    "bassoon","basson","flute","flûte","piccolo",
  },
  LV  = {
    "lead voc","lead vocal","lead voice",
    "lead vox","vox lead","vocal lead",
    "voix lead","voix principale",
    "chant lead","chanteur","chanteuse",
    "main voc","main vocal","topline","top line",
    "lvox","l vox","ld vox"," lv ","leadvox","lead_vox"," voc ",
  },
  BV  = {
    "backing voc","backing vocal","backing voice",
    "bg voc","bg vocal"," bgv","bkg voc",
    "bvox","b vox","bg vox","backingvox","backing_vox",
    "adlib","ad lib","ad-lib","choir","choeur","chorus voc",
    "gang vocal","shout voc","harmony voc","harmonie voc",
    "vox harm","voc harm","bv1","bv2","bv3"," bv ",
  },
  DV  = {
    "double voc","double vocal","dbl voc",
    "vox double","vocal double","voix double",
    "voc dbl","dbl vox"," dv ",
  },
  SP  = { "sample" },
  FX  = {
    "reverb","revb","delay","echo",
    " fx ","fx bus","fx send","fx ret",
    " send","return"," aux ",
    "bus rev","bus del","bus fx",
    "parallel comp","comp par","parallel",
    "room verb","hall verb","plate verb",
  },
  SFX = {
    " sfx","sound fx","sound effect",
    "riser","impact","whoosh","foley","noise sfx",
    "sweep","downlifter","uplifter",
    "transition fx","transition sfx","stab sfx","hit sfx",
  },
  UNK = {},
}

-- Charger les keywords depuis UserConfig si présents, sinon defaults
local keywords = {}
if cfg_ref.KEYWORDS then
  keywords = deep_copy(cfg_ref.KEYWORDS)
else
  keywords = deep_copy(DEFAULT_KEYWORDS)
end

-- S'assurer que chaque catégorie a une entrée keywords
for _, def in ipairs(folders) do
  if not keywords[def.cat] then keywords[def.cat] = {} end
end

-- ============================================================
-- Sauvegarde dans UserConfig.lua
-- ============================================================

local function escape_lua_string(s)
  return s:gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function save_user_config()
  local path = script_path .. "UserConfig.lua"
  local f = io.open(path, "w")
  if not f then
    status_msg = "❌ Impossible d'écrire UserConfig.lua"
    status_timer = 180
    return
  end

  f:write("-- ============================================================\n")
  f:write("-- UserConfig.lua  — ReaOrganizer\n")
  f:write("-- Généré automatiquement par ReaConfig. Ne pas éditer à la main.\n")
  f:write("-- Pour réinitialiser : supprimez ce fichier.\n")
  f:write("-- ============================================================\n\n")
  f:write("local cfg = {}\n\n")

  -- FOLDERS
  f:write("cfg.FOLDERS = {\n")
  for _, def in ipairs(folders) do
    f:write(string.format(
      '  { cat = "%s", name = "%s", label = "%s", color = {%d, %d, %d} },\n',
      def.cat,
      escape_lua_string(def.name),
      escape_lua_string(def.label),
      def.color[1], def.color[2], def.color[3]))
  end
  f:write("}\n\n")

  -- FX_COLOR
  f:write(string.format(
    "cfg.FX_COLOR = {%d, %d, %d}\n\n",
    fx_color[1], fx_color[2], fx_color[3]))

  -- KEYWORDS
  f:write("cfg.KEYWORDS = {\n")
  for _, def in ipairs(folders) do
    local cat = def.cat
    local kws = keywords[cat] or {}
    f:write('  ' .. cat .. ' = {\n')
    for _, kw in ipairs(kws) do
      f:write(string.format('    "%s",\n', escape_lua_string(kw)))
    end
    f:write('  },\n')
  end
  -- FX keywords (pas dans FOLDERS mais dans KEYWORDS)
  if keywords["FX"] then
    f:write('  FX = {\n')
    for _, kw in ipairs(keywords["FX"]) do
      f:write(string.format('    "%s",\n', escape_lua_string(kw)))
    end
    f:write('  },\n')
  end
  f:write("}\n\n")

  -- Helpers
  f:write("cfg.BY_CAT = {}\n")
  f:write("for _, def in ipairs(cfg.FOLDERS) do cfg.BY_CAT[def.cat] = def end\n")
  f:write("cfg.BY_NAME = {}\n")
  f:write("for _, def in ipairs(cfg.FOLDERS) do cfg.BY_NAME[def.name] = def end\n\n")
  f:write("return cfg\n")

  f:close()
  dirty = false
  status_msg = "✓ UserConfig.lua saved"
  reaper.SetExtState("MixAssist", "config_dirty", "1", false)
  status_timer = 180
end

-- ============================================================
-- Interface ImGui
-- ============================================================

local ctx = reaper.ImGui_CreateContext("MixAssist")

local WINDOW_FLAGS = reaper.ImGui_WindowFlags_NoCollapse()

-- Dimensions
local WIN_W, WIN_H   = 920, 640
local LEFT_W         = 290
local RIGHT_W        = WIN_W - LEFT_W - 24

-- Input buffers
local buf_name  = reaper.ImGui_CreateBuffer and reaper.ImGui_CreateBuffer(128) or nil
local buf_label = reaper.ImGui_CreateBuffer and reaper.ImGui_CreateBuffer(128) or nil
local buf_kw    = ""   -- buffer pour nouveau mot-clé (string Lua)
local buf_new_cat    = ""
local buf_new_label  = ""
local buf_new_name   = ""

local done = false

-- ── Helpers ImGui couleurs ──────────────────────────────────

-- Pour PushStyleColor : format 0xRRGGBBAA
local function c_to_imgui(c, a)
  a = a or 255
  return ((c[1] & 0xFF) << 24) | ((c[2] & 0xFF) << 16) | ((c[3] & 0xFF) << 8) | (a & 0xFF)
end

-- Pour ColorEdit4 avec NoAlpha : format 0x00RRGGBB
local function c_to_imgui_edit(c)
  return ((c[1] & 0xFF) << 16) | ((c[2] & 0xFF) << 8) | (c[3] & 0xFF)
end

local function imgui_to_c(col)
  return {
    (col >> 16) & 0xFF,
    (col >> 8)  & 0xFF,
     col        & 0xFF,
  }
end

-- ── Rendu de la colonne gauche (liste des catégories) ───────

local function render_left()
  reaper.ImGui_BeginChild(ctx, "left_panel", LEFT_W, WIN_H - 80)

  reaper.ImGui_Text(ctx, "Categories")
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  for i, def in ipairs(folders) do
    -- Pastille couleur
    local col = c_to_imgui(def.color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  col)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   col)
    reaper.ImGui_Button(ctx, "##dot" .. i, 14, 14)
    reaper.ImGui_PopStyleColor(ctx, 3)
    reaper.ImGui_SameLine(ctx)

    -- Sélection
    local label = def.name .. "  " .. def.label
    if reaper.ImGui_Selectable(ctx, label .. "##" .. i, selected_cat == i) then
      selected_cat = i
      buf_kw = ""
    end

    -- Boutons monter/descendre sur hover
    if selected_cat == i then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetCursorPosX(ctx, LEFT_W - 44)

      -- Monter
      local can_up = i > 1
      if not can_up then
        reaper.ImGui_BeginDisabled(ctx)
      end
      if reaper.ImGui_SmallButton(ctx, "▲##up" .. i) and can_up then
        folders[i], folders[i-1] = folders[i-1], folders[i]
        selected_cat = i - 1
        dirty = true
      end
      if not can_up then reaper.ImGui_EndDisabled(ctx) end

      reaper.ImGui_SameLine(ctx)

      -- Descendre
      local can_down = i < #folders
      if not can_down then reaper.ImGui_BeginDisabled(ctx) end
      if reaper.ImGui_SmallButton(ctx, "▼##dn" .. i) and can_down then
        folders[i], folders[i+1] = folders[i+1], folders[i]
        selected_cat = i + 1
        dirty = true
      end
      if not can_down then reaper.ImGui_EndDisabled(ctx) end
    end
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- ── Add a new category ─────────────────────────────────
  reaper.ImGui_Text(ctx, "New category")
  reaper.ImGui_SetNextItemWidth(ctx, LEFT_W - 8)
  local c2, v2 = reaper.ImGui_InputTextWithHint(ctx, "##newlabel", "Label (e.g. Electric Guitar)", buf_new_label, 256)
  if c2 then buf_new_label = v2 end
  reaper.ImGui_SetNextItemWidth(ctx, LEFT_W - 8)
  local c3, v3 = reaper.ImGui_InputTextWithHint(ctx, "##newname", "Folder name (e.g. [EG])", buf_new_name, 256)
  if c3 then buf_new_name = v3 end

  -- Auto-derive cat code from folder name: [EG] → EG
  buf_new_cat = buf_new_name:match("^%[(.+)%]$") or buf_new_name:upper()

  local can_add = buf_new_label ~= "" and buf_new_name ~= ""
  if not can_add then reaper.ImGui_BeginDisabled(ctx) end
  if reaper.ImGui_Button(ctx, "Add##addcat", LEFT_W - 8, 0) and can_add then
    table.insert(folders, {
      cat   = buf_new_cat:upper(),
      name  = buf_new_name,
      label = buf_new_label,
      color = {120, 120, 120},
    })
    keywords[buf_new_cat:upper()] = {}
    selected_cat = #folders
    buf_new_cat, buf_new_label, buf_new_name = "", "", ""
    dirty = true
  end
  if not can_add then reaper.ImGui_EndDisabled(ctx) end

  -- ── Supprimer la catégorie sélectionnée ───────────────
  reaper.ImGui_Spacing(ctx)
  local protected = { DR=true, UNK=true }
  local cur_cat = folders[selected_cat] and folders[selected_cat].cat or ""
  if protected[cur_cat] then reaper.ImGui_BeginDisabled(ctx) end
  if reaper.ImGui_Button(ctx, "Delete##delcat", LEFT_W - 8, 0) then
    keywords[cur_cat] = nil
    table.remove(folders, selected_cat)
    selected_cat = math.max(1, selected_cat - 1)
    dirty = true
  end
  if protected[cur_cat] then reaper.ImGui_EndDisabled(ctx) end

  reaper.ImGui_EndChild(ctx)
end

-- ── Rendu de la colonne droite (détails + mots-clés) ────────

local function render_right()
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_BeginChild(ctx, "right_panel", RIGHT_W, WIN_H - 80)

  local def = folders[selected_cat]
  if not def then
    reaper.ImGui_Text(ctx, "Sélectionnez une catégorie")
    reaper.ImGui_EndChild(ctx)
    return
  end

  -- ── Infos de la catégorie ──────────────────────────────
  reaper.ImGui_Text(ctx, "Category: " .. def.cat)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- Nom du dossier
  reaper.ImGui_Text(ctx, "Folder name")
  reaper.ImGui_SetNextItemWidth(ctx, 120)
  local cn, vn = reaper.ImGui_InputText(ctx, "##dname", def.name, 256)
  if cn and vn ~= def.name then def.name = vn; dirty = true end

  reaper.ImGui_SameLine(ctx)

  -- Label lisible
  reaper.ImGui_Text(ctx, "  Label")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 180)
  local cl, vl = reaper.ImGui_InputText(ctx, "##dlabel", def.label, 256)
  if cl and vl ~= def.label then def.label = vl; dirty = true end

  reaper.ImGui_Spacing(ctx)

  -- Color picker
  reaper.ImGui_Text(ctx, "Color")
  reaper.ImGui_SameLine(ctx)
  local col32 = c_to_imgui_edit(def.color)
  local cp_flags = reaper.ImGui_ColorEditFlags_NoAlpha()
                 | reaper.ImGui_ColorEditFlags_NoInputs()
  local cc, new_col = reaper.ImGui_ColorEdit4(ctx, "##col" .. def.cat, col32, cp_flags)
  if cc then
    def.color = imgui_to_c(new_col)
    dirty = true
  end

  -- Couleur FX (section spéciale)
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "   FX tracks color:")
  reaper.ImGui_SameLine(ctx)
  local fx32 = c_to_imgui_edit(fx_color)
  local cfx, new_fx = reaper.ImGui_ColorEdit4(ctx, "##colfx", fx32, cp_flags)
  if cfx then
    fx_color = imgui_to_c(new_fx)
    dirty = true
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- ── Mots-clés ─────────────────────────────────────────
  reaper.ImGui_Text(ctx, "Keywords (" .. def.cat .. ")")
  reaper.ImGui_Spacing(ctx)

  local kws = keywords[def.cat] or {}

  -- Liste des mots-clés
  local to_delete = nil
  reaper.ImGui_BeginChild(ctx, "kw_list", RIGHT_W - 16, WIN_H - 330)
  for j, kw in ipairs(kws) do
    -- Selectable pour le surlignage au survol
    reaper.ImGui_Selectable(ctx, kw .. "##kwsel" .. j, false)
    reaper.ImGui_SameLine(ctx)
    local avail = reaper.ImGui_GetContentRegionAvail(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + avail - 24)
    -- Croix rouge au survol
    local bx, by = reaper.ImGui_GetCursorScreenPos(ctx)
    local hovered = reaper.ImGui_IsMouseHoveringRect(ctx, bx, by, bx + 20, by + 16)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),
      hovered and 0xFF4444FF or 0x88888888)
    reaper.ImGui_Text(ctx, "✕")
    reaper.ImGui_PopStyleColor(ctx, 1)
    if hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
      to_delete = j
      dirty = true
    end
  end
  reaper.ImGui_EndChild(ctx)

  if to_delete then
    table.remove(kws, to_delete)
    keywords[def.cat] = kws
  end

  reaper.ImGui_Spacing(ctx)

  -- Ajouter un mot-clé
  reaper.ImGui_Text(ctx, "Add")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, RIGHT_W - 130)
  local ck, vk = reaper.ImGui_InputText(ctx, "##newkw", buf_kw, 256)
  if ck then buf_kw = vk end

  -- Valider avec Entrée ou bouton
  local add_kw = reaper.ImGui_IsItemFocused(ctx)
               and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Add##kwadd") or add_kw then
    local trimmed = buf_kw:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      table.insert(kws, trimmed)
      keywords[def.cat] = kws
      buf_kw = ""
      dirty = true
    end
  end

  reaper.ImGui_EndChild(ctx)
end

-- ── Barre de bas de fenêtre ─────────────────────────────────

local function render_footer()
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- Statut
  if status_timer > 0 then
    reaper.ImGui_Text(ctx, status_msg)
    status_timer = status_timer - 1
  else
    reaper.ImGui_TextDisabled(ctx, dirty and "● Unsaved changes" or "✓ Up to date")
  end

  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetCursorPosX(ctx, WIN_W - 280)

  -- Réinitialiser
  if reaper.ImGui_Button(ctx, "Reset##reset", 120, 0) then
    local user_path = script_path .. "UserConfig.lua"
    os.remove(user_path)
    local base = dofile(script_path .. "Config.lua")
    folders    = deep_copy(base.FOLDERS)
    fx_color   = deep_copy(base.FX_COLOR)
    keywords   = deep_copy(DEFAULT_KEYWORDS)
    dirty      = false
    status_msg = "✓ Reset from Config.lua"
    status_timer = 180
  end

  reaper.ImGui_SameLine(ctx)

  -- Sauvegarder
  local was_dirty = dirty
  if not was_dirty then reaper.ImGui_BeginDisabled(ctx) end
  if reaper.ImGui_Button(ctx, "Save##save", 130, 0) then
    save_user_config()
  end
  if not was_dirty then reaper.ImGui_EndDisabled(ctx) end
end

-- ── Boucle principale ────────────────────────────────────────

local function loop()
  if done then return end

  reaper.ImGui_SetNextWindowSize(ctx, WIN_W, WIN_H,
    reaper.ImGui_Cond_FirstUseEver())

  local title = "MixAssist — Categories & Keywords##roconfig"
  local visible, open = reaper.ImGui_Begin(ctx, title, true, WINDOW_FLAGS)

  -- Recalculer RIGHT_W selon la taille réelle de la fenêtre
  local actual_w, actual_h = reaper.ImGui_GetWindowSize(ctx)
  RIGHT_W = actual_w - LEFT_W - 24

  if not open then
    if dirty then
      local choice = reaper.ShowMessageBox(
        "You have unsaved changes.\nSave before closing?",
        "MixAssist", 3)
      if choice == 6 then save_user_config() end
      if choice == 2 then
        -- Annuler la fermeture
        reaper.defer(loop)
        reaper.ImGui_End(ctx)
        return
      end
    end
    done = true
    reaper.ImGui_End(ctx)
    return
  end

  if visible then
    render_left()
    render_right()
    render_footer()
  end

  reaper.ImGui_End(ctx)
  if not done then reaper.defer(loop) end
end

reaper.defer(loop)