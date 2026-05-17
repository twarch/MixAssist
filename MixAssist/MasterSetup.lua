-- ============================================================
-- MasterSetup.lua  v1  — ReaOrganizer
-- Charge Mixbus.rfxchain sur la piste Master.
-- ============================================================

local FXCHAIN_NAME = reaper.GetExtState("MixAssist", "master_fxchain")
if FXCHAIN_NAME == "" then FXCHAIN_NAME = "MASTER.rfxchain" end
local FXCHAINS_PATH = reaper.GetResourcePath() .. "/FXChains/"

-- ============================================================
-- Helpers
-- ============================================================

local function load_fxchain_on_master(filename)
  local path = FXCHAINS_PATH .. filename
  local f = io.open(path, "r")
  if not f then
    reaper.ShowMessageBox(
      "FXchain introuvable :\n" .. path,
      "MasterSetup", 0)
    return false
  end
  local chain_content = f:read("*all"):gsub("\r\n", "\n"):gsub("\r", "\n")
  f:close()

  local master = reaper.GetMasterTrack(0)
  local _, chunk = reaper.GetTrackStateChunk(master, "", false)

  local fxchain_block = "<FXCHAIN\nSHOW 0\nLASTSEL 0\nDOCKED 0\n"
                      .. chain_content
                      .. "\n>"

  if chunk:find("<FXCHAIN") then
    chunk = chunk:gsub("<FXCHAIN.-\n>", fxchain_block)
  else
    chunk = chunk:gsub("\n>%s*$", "\n" .. fxchain_block .. "\n>")
  end

  reaper.SetTrackStateChunk(master, chunk, false)
  return true
end

-- ============================================================
-- MAIN
-- ============================================================

reaper.Undo_BeginBlock()

if load_fxchain_on_master(FXCHAIN_NAME) then
  reaper.UpdateArrange()
end

reaper.Undo_EndBlock("MasterSetup — chargement Mixbus", -1)
