-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- Config.lua  — twarch
-- Configuration centralisée pour OrganisePistes et MoveToFolder
-- Modifiez ce fichier pour personnaliser couleurs et noms.
-- ============================================================

local cfg = {}

-- ============================================================
-- CATÉGORIES
-- Chaque entrée définit :
--   cat   : identifiant interne (ne pas modifier)
--   name  : nom du dossier dans Reaper (modifiable)
--   color : couleur RGB 0-255 (modifiable)
--   label : nom affiché dans MoveToFolder (modifiable)
-- L'ordre ici détermine l'ordre des dossiers dans le projet.
-- ============================================================

cfg.FOLDERS = {
  { cat = "DR",  name = "[DR]",  label = "Drums",            color = {212, 160,  23} },
  { cat = "PE",  name = "[PE]",  label = "Percussions",      color = {184, 134,  11} },
  { cat = "BA",  name = "[BA]",  label = "Bass",             color = {194,  81,  26} },
  { cat = "AG",  name = "[AG]",  label = "Acoustic Guitar",  color = { 91, 155, 213} },
  { cat = "EG",  name = "[EG]",  label = "Electric Guitar",  color = { 31,  78, 121} },
  { cat = "KB",  name = "[KB]",  label = "Keys",             color = { 46, 125,  50} },
  { cat = "SY",  name = "[SY]",  label = "Synths",           color = {102, 187, 106} },
  { cat = "ST",  name = "[ST]",  label = "Strings",          color = {123,  79,  46} },
  { cat = "BR",  name = "[BR]",  label = "Brass",            color = {139, 105,  20} },
  { cat = "WW",  name = "[WW]",  label = "Woodwinds",        color = {161, 136,  60} },
  { cat = "LV",  name = "[LV]",  label = "Lead Vocals",      color = {173,  20,  87} },
  { cat = "BV",  name = "[BV]",  label = "Backing Vocals",   color = {233,  30, 140} },
  { cat = "DV",  name = "[DV]",  label = "Double Vocals",    color = {244, 143, 177} },
  { cat = "SP",  name = "[SP]",  label = "Samples",          color = { 55,  71,  79} },
  { cat = "SFX", name = "[SFX]", label = "Sound FX",         color = { 69,  39, 160} },
  { cat = "FX",  name = "[FX]",  label = "FX",               color = {149, 117, 205} },
  { cat = "UNK", name = "[?]",   label = "Non classé",       color = {100, 100, 100} },
}

-- ============================================================
-- COULEUR DES PISTES FX (colorées seulement, pas déplacées)
-- ============================================================

cfg.FX_COLOR = {149, 117, 205}

-- ============================================================
-- Helpers — construits automatiquement à partir de cfg.FOLDERS
-- Ne pas modifier
-- ============================================================

-- Map cat → définition complète
cfg.BY_CAT = {}
for _, def in ipairs(cfg.FOLDERS) do
  cfg.BY_CAT[def.cat] = def
end

-- Map name → définition complète (pour la détection des dossiers existants)
cfg.BY_NAME = {}
for _, def in ipairs(cfg.FOLDERS) do
  cfg.BY_NAME[def.name] = def
end

return cfg
