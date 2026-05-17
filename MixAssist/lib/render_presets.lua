-- ============================================================
-- lib/render_presets.lua — ReaOrganizer
-- Apply render presets from reaper-render.ini by patching
-- the project RPP directly before rendering.
-- ============================================================

local RP = {}

local function get_ini_path()
  return reaper.GetResourcePath() .. "/reaper-render.ini"
end

-- ============================================================
-- List available presets
-- ============================================================

function RP.list()
  local presets = {}
  local seen = {}
  local f = io.open(get_ini_path(), "r")
  if not f then return presets end
  local content = f:read("*all")
  f:close()
  for name in content:gmatch('<RENDERPRESET "([^"]+)"') do
    if not seen[name] then
      seen[name] = true
      table.insert(presets, name)
    end
  end
  return presets
end

-- ============================================================
-- Read preset data from ini
-- ============================================================

local function read_preset(preset_name)
  local f = io.open(get_ini_path(), "r")
  if not f then return nil end
  local content = f:read("*all")
  f:close()

  local escaped = preset_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")

  -- Extract blob1 (main format)
  local blob1 = content:match('<RENDERPRESET "' .. escaped .. '"[^\n]*\n%s+([A-Za-z0-9+/=]+)')

  -- Extract blob2 (second format, optional)
  local blob2 = content:match('<RENDERPRESET2 "' .. escaped .. '"[^\n]*\n%s+([A-Za-z0-9+/=]+)')

  -- Extract sample rate and channels
  local srate, nch = content:match('<RENDERPRESET "' .. escaped .. '" (%d+) (%d+)')

  -- Extract normalize settings
  local norm = content:match('RENDERPRESET_EXT "' .. escaped .. '" ([^\n]+)')

  return {
    blob1 = blob1,
    blob2 = blob2,
    srate = tonumber(srate) or 48000,
    nch   = tonumber(nch)   or 2,
    norm  = norm,
  }
end

-- ============================================================
-- Apply preset: patch RPP then configure via API
-- ============================================================

function RP.apply(preset_name, output_path, filename)
  local preset = read_preset(preset_name)
  if not preset or not preset.blob1 then
    return false, "Preset not found: " .. preset_name
  end

  -- 1. Save project to get current RPP on disk
  reaper.Main_OnCommand(40026, 0)

  local proj_path = reaper.GetProjectPath("")
  local proj_name = reaper.GetProjectName(0, "")
  local rpp_path  = proj_path .. "/" .. proj_name

  -- 2. Read RPP
  local f = io.open(rpp_path, "r")
  if not f then return false, "Cannot open RPP" end
  local content = f:read("*all")
  f:close()

  -- 3. Replace RENDER_CFG block with new blob
  local new_cfg = "<RENDER_CFG\n    " .. preset.blob1 .. "\n  >"
  content = content:gsub("<RENDER_CFG.->", new_cfg)

  -- 4. Handle second format (RENDER_CFG2)
  if preset.blob2 then
    local new_cfg2 = "<RENDER_CFG2\n    " .. preset.blob2 .. "\n  >"
    if content:find("<RENDER_CFG2") then
      content = content:gsub("<RENDER_CFG2.->", new_cfg2)
    else
      -- Insert after RENDER_CFG
      content = content:gsub("(<RENDER_CFG.->\n)", "%1  " .. new_cfg2 .. "\n")
    end
  else
    -- Remove RENDER_CFG2 if exists
    content = content:gsub("%s*<RENDER_CFG2.->", "")
  end

  -- 5. Set output path and filename in RPP
  -- Replace RENDER_FILE
  content = content:gsub(
    '(RENDER_FILE ")[^"]*(")',
    '%1' .. output_path .. '/%2')
  -- Replace RENDER_PATTERN (inside RENDER_RANGE line or separate)
  -- Actually set via API after reload

  -- 6. Write patched RPP
  local fw = io.open(rpp_path, "w")
  if not fw then return false, "Cannot write RPP" end
  fw:write(content)
  fw:close()

  -- 7. Configure via API (in-memory)
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    output_path .. "/", true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", filename,           true)
  if preset.srate > 0 then
    reaper.GetSetProjectInfo(0, "RENDER_SRATE", preset.srate, true)
  end
  reaper.GetSetProjectInfo(0, "RENDER_NCHANNELS", preset.nch, true)

  return true, nil
end

-- ============================================================
-- Render with preset
-- ============================================================

function RP.render(preset_name, output_path, filename, start_pos, end_pos)
  -- Set render bounds
  reaper.GetSetProjectInfo(0, "RENDER_STARTPOS",   start_pos, true)
  reaper.GetSetProjectInfo(0, "RENDER_ENDPOS",     end_pos,   true)
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 2,         true)

  -- Apply preset
  local ok, err = RP.apply(preset_name, output_path, filename)
  if not ok then return false, err end

  -- Launch render
  reaper.Main_OnCommand(41824, 0)
  return true, nil
end

return RP
