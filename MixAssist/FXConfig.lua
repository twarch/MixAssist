-- FXConfig.lua — MixAssist
-- Configuration des FXchains et pistes parallèles par dossier
-- Ce fichier est généré par FXConfig_UI et peut être édité manuellement
-- Ne pas modifier la structure, seulement les valeurs

local cfg = {}

-- Couleur des pistes parallèles (violet)
cfg.PARALLEL_COLOR = { 144, 107, 250 }

-- ── Configuration par catégorie ───────────────────────────────
-- fxchain    : nom du fichier .rfxchain dans le dossier Reaper/FXChains/
-- sub_buses  : FXchains sur les sous-bus (DR uniquement)
-- parallel   : pistes parallèles à créer
--   name     : nom de la piste
--   position : "internal" (dans le dossier) ou "external" (hors dossier)
--   prefader : true = pre-fader, false = post-fader
--   volume   : volume du send en dB (-math.huge = -inf, 0 = 0dB)
--   fxchain  : FXchain à charger sur la piste parallèle (ou "" pour aucune)

cfg.FOLDERS = {

  DR = {
    fxchain  = "",
    sub_buses = {
      ["BD BUS"]   = { fxchain = "" },
      ["SD BUS"]   = { fxchain = "" },
      ["TOM BUS"]  = { fxchain = "" },
      ["OH BUS"]   = { fxchain = "" },
      ["ROOM BUS"] = { fxchain = "" },
    },
    parallel = {},
  },

  BA = {
    fxchain  = "",
    parallel = {},
  },

  EG = {
    fxchain  = "",
    parallel = {},
  },

  AG = {
    fxchain  = "",
    parallel = {},
  },

  KB = {
    fxchain  = "",
    parallel = {},
  },

  SY = {
    fxchain  = "",
    parallel = {},
  },

  ST = {
    fxchain  = "",
    parallel = {},
  },

  BR = {
    fxchain  = "",
    parallel = {},
  },

  WW = {
    fxchain  = "",
    parallel = {},
  },

  LV = {
    fxchain  = "",
    parallel = {},
  },

  BV = {
    fxchain  = "",
    parallel = {},
  },

  DV = {
    fxchain  = "",
    parallel = {},
  },

  PE = {
    fxchain  = "",
    parallel = {},
  },

  SP = {
    fxchain  = "",
    parallel = {},
  },

  FX = {
    fxchain  = "",
    parallel = {},
  },

}

return cfg
