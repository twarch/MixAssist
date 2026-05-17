-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- tabs/tab_export.lua — ReaOrganizer
-- Export tab: WAV + MP3 bounce from Full Song region,
-- semantic versioning, RPP snapshots, version history.
-- ============================================================

local T = {}

local EXT = "SessionPrepare_Export"

-- ============================================================
-- Settings
-- ============================================================

local function load_settings()
  local s = {}
  s.name_format = reaper.GetExtState(EXT, "name_format")
  s.subfolder   = reaper.GetExtState(EXT, "subfolder")
  if s.name_format == "" then s.name_format = "{artist} - {title} {version}" end
  if s.subfolder   == "" then s.subfolder   = "_exports" end
  return s
end

local function save_settings(s)
  reaper.SetExtState(EXT, "name_format", s.name_format, true)
  reaper.SetExtState(EXT, "subfolder",   s.subfolder,   true)
end

-- ============================================================
-- Versioning
-- ============================================================

-- Parse "v1.2" → {1,2,nil}, "v1.2.3" → {1,2,3}, "v0.1" → {0,1,nil}
local function parse_version(v)
  if not v or v == "" then return 1, 0, nil end
  local a, b, c = v:match("^v?(%d+)%.(%d+)%.(%d+)$")
  if a then return tonumber(a), tonumber(b), tonumber(c) end
  local a2, b2 = v:match("^v?(%d+)%.(%d+)$")
  if a2 then return tonumber(a2), tonumber(b2), nil end
  local n = v:match("^v?(%d+)$")
  if n then return tonumber(n), 0, nil end
  return 1, 0, nil
end

local function fmt_ver(a, b, c)
  if c then return string.format("v%d.%d.%d", a, b, c) end
  return string.format("v%d.%d", a, b)
end

-- Has this project ever been exported?
local function has_been_exported(versions_path)
  local f = io.open(versions_path .. "/index.txt", "r")
  if not f then return false end
  local content = f:read("*all")
  f:close()
  return content ~= ""
end

-- ============================================================
-- File helpers
-- ============================================================

local function resolve_name(fmt, meta, version)
  local s = fmt
  s = s:gsub("{artist}",  meta.artist ~= "" and meta.artist or "Unknown")
  s = s:gsub("{title}",   meta.title  ~= "" and meta.title  or "Untitled")
  s = s:gsub("{version}", version)
  s = s:gsub('[\\/:*?"<>|]', "_")
  return s
end

local function find_full_song_region()
  local i = 0
  repeat
    local retval, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and isrgn and name == "Full Song" then return pos, rgnend end
    i = i + 1
  until retval == 0
  return nil, nil
end

local function ensure_dir(path)
  if reaper.GetOS():find("Win") then
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

local function copy_file(src, dst)
  local f = io.open(src, "rb")
  if not f then return false end
  local data = f:read("*all"); f:close()
  local g = io.open(dst, "wb")
  if not g then return false end
  g:write(data); g:close()
  return true
end

-- Snapshots RPP next to the project file (not in export subfolder)
local function get_snapshots_path(proj_path)
  return proj_path .. "/_versions"
end

-- Export audio files path
local function get_export_path(proj_path, subfolder)
  return proj_path .. "/" .. subfolder
end

-- History index stored in snapshots folder
local function get_history_path(snapshots_path)
  return snapshots_path .. "/index.txt"
end

-- ============================================================
-- History
-- ============================================================

local function load_history(snapshots_path)
  local entries = {}
  local f = io.open(get_history_path(snapshots_path), "r")
  if not f then return entries end
  for line in f:lines() do
    local ver, date, fname, note = line:match("^([^|]+)|([^|]+)|([^|]+)|(.*)$")
    if ver then
      table.insert(entries, { version=ver, date=date, filename=fname, note=note })
    end
  end
  f:close()
  return entries
end

local function save_history_entry(snapshots_path, entry)
  local entries = load_history(snapshots_path)
  table.insert(entries, 1, entry)
  local f = io.open(get_history_path(snapshots_path), "w")
  if not f then return end
  for _, e in ipairs(entries) do
    f:write(string.format("%s|%s|%s|%s\n",
      e.version, e.date, e.filename, e.note or ""))
  end
  f:close()
end

local function has_been_exported(snapshots_path)
  local f = io.open(get_history_path(snapshots_path), "r")
  if not f then return false end
  local content = f:read("*all"); f:close()
  return content ~= ""
end

-- Find next derived version from history (e.g. v1.0 → v1.0.1 or v1.0.2)
local function next_derived_from_history(base_version, snapshots_path)
  local bj, bn, _ = parse_version(base_version)
  local max_patch = 0
  local hist = load_history(snapshots_path)
  for _, e in ipairs(hist) do
    local ej, en, ep = parse_version(e.version)
    if ej == bj and en == bn and ep and ep > max_patch then
      max_patch = ep
    end
  end
  return fmt_ver(bj, bn, max_patch + 1)
end

-- ============================================================
-- Render
-- ============================================================

local function do_render(filepath, start_pos, end_pos, is_mp3, wav_bits)
  reaper.GetSetProjectInfo(0, "RENDER_STARTPOS",   start_pos, true)
  reaper.GetSetProjectInfo(0, "RENDER_ENDPOS",     end_pos,   true)
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 2,         true)
  local path = filepath:match("^(.*[\\/])")
  local name = filepath:match("[^\\/]+$"):gsub("%.[^%.]+$", "")
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    path, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", name, true)
  if is_mp3 then
    reaper.GetSetProjectInfo(0, "RENDER_FORMAT",  101, true)
    reaper.GetSetProjectInfo(0, "RENDER_FORMAT2", 320, true)
  else
    reaper.GetSetProjectInfo(0, "RENDER_FORMAT", 0, true)
    local bits = tonumber(wav_bits) or 24
    local bd = bits == 32 and 4 or (bits == 16 and 1 or 3)
    reaper.GetSetProjectInfo(0, "RENDER_FORMAT2", bd, true)
  end
  reaper.Main_OnCommand(41824, 0)
end

-- ============================================================
-- Module state
-- ============================================================

local settings      = load_settings()
local buf_format    = settings.name_format
local buf_subfolder = settings.subfolder
local buf_note      = ""
local buf_suffix    = ""
local is_draft      = false

-- ============================================================
-- Tab render
-- ============================================================

function T.render(ctx, state)
  local btn_w   = state.btn_w
  local H       = state.H
  local M       = state.M
  local set_log = state.set_log
  local meta    = state.meta_bufs
  local spacing = 8
  local alt     = state.export_alt  -- persistent alt state

  -- Aliases for readability
  local buf_suffix    = alt.buf_suffix
  local alt_instru    = alt.alt_instru
  local alt_acapella  = alt.alt_acapella
  local alt_live      = alt.alt_live
  local alt_custom    = alt.alt_custom
  local is_previewing = alt.is_previewing
  local preview_muted = alt.preview_muted

  reaper.ImGui_Spacing(ctx)

  local proj_path   = reaper.GetProjectPath("")
  local proj_name   = reaper.GetProjectName(0, "")
  local has_project = proj_path ~= ""

  local start_pos, end_pos = find_full_song_region()
  local has_region = start_pos ~= nil

  local export_path     = has_project and (proj_path .. "/" .. buf_subfolder) or ""
  local snapshots_path  = has_project and get_snapshots_path(proj_path) or ""
  local exported_once   = has_project and has_been_exported(snapshots_path)

  -- ── Current version + next versions ─────────────────────
  local cur_version  = meta.version      ~= "" and meta.version      or "v1.0"
  local base_version = meta.base_version ~= "" and meta.base_version or nil

  local mj, mn, mp = parse_version(cur_version)
  cur_version = fmt_ver(mj, mn, mp)

  -- Determine export version
  local export_version
  if not exported_once then
    export_version = is_draft and "v0.1" or "v1.0"
  elseif base_version then
    -- Read history to find correct next derived version
    export_version = next_derived_from_history(base_version, snapshots_path)
  end

  -- ── Preview ──────────────────────────────────────────────
  local preview_ver = export_version or fmt_ver(mj, mn + 1, mp)
  local preview     = resolve_name(buf_format, meta, preview_ver)

  reaper.ImGui_Text(ctx, "Version: " .. cur_version)
  if base_version then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextDisabled(ctx, "  (snapshot: " .. base_version .. ")")
  end
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_TextDisabled(ctx, preview .. ".wav")
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- ── Settings ─────────────────────────────────────────────
  reaper.ImGui_Text(ctx, "Settings")
  reaper.ImGui_Spacing(ctx)

  local lw = 65
  local fw = btn_w - lw - spacing

  -- Name format
  reaper.ImGui_Text(ctx, "Name")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)
  reaper.ImGui_SetNextItemWidth(ctx, fw)
  local cn, vn = reaper.ImGui_InputText(ctx, "##namefmt", buf_format, 256)
  if cn then buf_format = vn; settings.name_format = vn; save_settings(settings) end
  reaper.ImGui_TextDisabled(ctx, "  {artist} {title} {version}")
  reaper.ImGui_Spacing(ctx)

  -- Subfolder
  reaper.ImGui_Text(ctx, "Folder")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)
  reaper.ImGui_SetNextItemWidth(ctx, fw)
  local cs, vs = reaper.ImGui_InputText(ctx, "##subfolder", buf_subfolder, 256)
  if cs then buf_subfolder = vs; settings.subfolder = vs; save_settings(settings) end
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- Note
  reaper.ImGui_Text(ctx, "Note")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)
  reaper.ImGui_SetNextItemWidth(ctx, fw)
  local cn2, vn2 = reaper.ImGui_InputText(ctx, "##note", buf_note, 256)
  if cn2 then buf_note = vn2 end
  reaper.ImGui_Spacing(ctx)

  -- Draft checkbox
  local cd, draft_val = reaper.ImGui_Checkbox(ctx, "Draft (v0.x)##draft", is_draft)
  if cd then is_draft = draft_val end
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- ── Warnings ─────────────────────────────────────────────
  if not has_region then
    reaper.ImGui_TextDisabled(ctx, "⚠ No 'Full Song' region")
    reaper.ImGui_Spacing(ctx)
  end
  if not has_project then
    reaper.ImGui_TextDisabled(ctx, "⚠ Save project first")
    reaper.ImGui_Spacing(ctx)
  end

  local can_export = has_region and has_project

  -- ── Export buttons ───────────────────────────────────────
  local half_w = math.floor((btn_w - spacing) / 2)

  local function export_btn(label, id, col, ver)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
      H.rgb_to_imgui(col[1], col[2], col[3]))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
      H.lighten(H.rgb_to_imgui(col[1], col[2], col[3]), 30))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
      H.rgb_to_imgui(col[1], col[2], col[3]))
    local clicked = reaper.ImGui_Button(ctx,
      label .. "\n" .. ver .. "##" .. id, half_w, 36)
    reaper.ImGui_PopStyleColor(ctx, 3)
    return clicked
  end

  if not can_export then reaper.ImGui_BeginDisabled(ctx) end

  local clicked_ver = nil

  if not exported_once or export_version then
    -- First export or derived from snapshot: single button
    local ver = export_version or (is_draft and "v0.1" or "v1.0")
    local label = not exported_once and "⬇ Export" or "⬇ Export"
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
      H.rgb_to_imgui(35, 90, 45))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
      H.rgb_to_imgui(50, 115, 60))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
      H.rgb_to_imgui(30, 75, 38))
    if reaper.ImGui_Button(ctx, label .. "\n" .. ver .. "##first", btn_w, 36) then
      clicked_ver = ver
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
  else
    -- Normal: Revision + New version
    local next_rev = fmt_ver(mj, mn + 1)
    local next_maj = fmt_ver(mj + 1, 0)
    if export_btn("↑ Revision", "rev", { 35, 75, 120 }, next_rev) then
      clicked_ver = next_rev
    end
    reaper.ImGui_SameLine(ctx)
    if export_btn("⟳ New version", "maj", { 100, 60, 20 }, next_maj) then
      clicked_ver = next_maj
    end
  end

  if not can_export then reaper.ImGui_EndDisabled(ctx) end

  -- ── Alternative exports ───────────────────────────────────
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Alternative export")
  reaper.ImGui_Spacing(ctx)

  -- Checkboxes — mute/solo applied immediately on change
  local VOCAL_CATS = { LV=true, BV=true, DV=true, VX=true }

  local function apply_alt(instru, acapella, live)
    -- First restore everything
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 0)
      reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
    end
    -- Then apply new state
    if not instru and not acapella and not live then return end
    local cfg = state.cfg
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      local _, tname = reaper.GetTrackName(tr)
      local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
      if depth >= 1 then
        for _, def in ipairs(cfg.FOLDERS) do
          if def.name == tname then
            local is_vocal = VOCAL_CATS[def.cat]
            if (instru and is_vocal) or (live and def.cat == "LV") then
              reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 1)
            end
            if acapella and is_vocal then
              reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", 1)
            end
            break
          end
        end
      end
    end
  end

  local c1, v1 = reaper.ImGui_Checkbox(ctx, "Instru##alt_instru", alt_instru)
  if c1 then
    alt.alt_instru = v1
    if v1 then alt.alt_acapella = false; alt.alt_live = false end
    apply_alt(alt.alt_instru, alt.alt_acapella, alt.alt_live)
    if alt.is_previewing and not v1 then
      alt.is_previewing = false
      reaper.Main_OnCommand(1016, 0)
    end
  end
  reaper.ImGui_SameLine(ctx)
  local c2, v2 = reaper.ImGui_Checkbox(ctx, "Acapella##alt_acap", alt_acapella)
  if c2 then
    alt.alt_acapella = v2
    if v2 then alt.alt_instru = false; alt.alt_live = false end
    apply_alt(alt.alt_instru, alt.alt_acapella, alt.alt_live)
    if alt.is_previewing and not v2 then
      alt.is_previewing = false
      reaper.Main_OnCommand(1016, 0)
    end
  end
  reaper.ImGui_SameLine(ctx)
  local c3, v3 = reaper.ImGui_Checkbox(ctx, "Live##alt_live", alt_live)
  if c3 then
    alt.alt_live = v3
    if v3 then alt.alt_instru = false; alt.alt_acapella = false; alt.alt_custom = false end
    apply_alt(alt.alt_instru, alt.alt_acapella, alt.alt_live)
    if alt.is_previewing and not v3 then
      alt.is_previewing = false
      reaper.Main_OnCommand(1016, 0)
    end
  end
  reaper.ImGui_SameLine(ctx)
  local c4, v4 = reaper.ImGui_Checkbox(ctx, "Custom##alt_custom", alt_custom)
  if c4 then
    alt.alt_custom = v4
    if v4 then alt.alt_instru = false; alt.alt_acapella = false; alt.alt_live = false end
    apply_alt(false, false, false)
    if alt.is_previewing and not v4 then
      alt.is_previewing = false
      reaper.Main_OnCommand(1016, 0)
    end
  end
  if alt_custom then
    reaper.ImGui_SetNextItemWidth(ctx, btn_w)
    local cc, vc = reaper.ImGui_InputText(ctx, "##alt_custom_label", alt.buf_custom_label or "", 256)
    if cc then alt.buf_custom_label = vc end
  end

  reaper.ImGui_Spacing(ctx)

  local alt_label = (alt_instru   and "Instrumental")
    or (alt_acapella and "Acapella")
    or (alt_live     and "Live")
    or (alt_custom   and (alt.buf_custom_label ~= "" and alt.buf_custom_label or "Custom"))
    or nil

  if alt_label then
    local alt_preview = resolve_name(buf_format, meta, cur_version)
      .. " (" .. alt_label .. ")"
    reaper.ImGui_TextDisabled(ctx, "→ " .. alt_preview .. ".wav")
    reaper.ImGui_Spacing(ctx)
  end

  local can_alt     = can_export and (alt_instru or alt_acapella or alt_live or alt_custom)
  local can_preview = alt_instru or alt_acapella or alt_live or alt_custom

  -- Preview button — just play/stop, mute/solo handled by checkboxes
  if can_preview then
    local preview_label = alt.is_previewing and "■ Stop" or "▶ Preview"
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
      alt.is_previewing and H.rgb_to_imgui(80, 40, 40) or H.rgb_to_imgui(40, 55, 40))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
      alt.is_previewing and H.rgb_to_imgui(105, 55, 55) or H.rgb_to_imgui(55, 75, 55))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
      alt.is_previewing and H.rgb_to_imgui(70, 35, 35) or H.rgb_to_imgui(35, 48, 35))
    if reaper.ImGui_Button(ctx, preview_label .. "##preview", btn_w, 24) then
      if not alt.is_previewing then
        reaper.Main_OnCommand(1007, 0)
        alt.is_previewing = true
        set_log("Preview: " .. (alt_label or "alternative"))
      else
        reaper.Main_OnCommand(1016, 0)
        alt.is_previewing = false
        set_log("Preview stopped")
      end
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    reaper.ImGui_Spacing(ctx)
  end

  if not can_alt then reaper.ImGui_BeginDisabled(ctx) end

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
    H.rgb_to_imgui(65, 55, 30))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
    H.rgb_to_imgui(90, 78, 42))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
    H.rgb_to_imgui(55, 46, 25))

  local btn_label = alt_label and ("⬇ Export (" .. alt_label .. ")") or "⬇ Export alternative"
  if reaper.ImGui_Button(ctx, btn_label, btn_w, 30) and can_alt then
    local cfg   = state.cfg
    local label = alt_label or "Alternative"
    local filename = resolve_name(buf_format, meta, cur_version)
      .. " (" .. label .. ")"

    -- Determine which categories to mute/solo
    local VOCAL_CATS  = { LV=true, BV=true, DV=true, VX=true }
    local tracks_to_mute = {}
    local tracks_to_solo = {}

    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      local _, tname = reaper.GetTrackName(tr)
      local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
      if depth >= 1 then
        for _, def in ipairs(cfg.FOLDERS) do
          if def.name == tname then
            local is_vocal = VOCAL_CATS[def.cat]
            if (alt_instru and is_vocal) or (alt_live and def.cat == "LV") then
              table.insert(tracks_to_mute, tr)
            end
            if alt_acapella and is_vocal then
              table.insert(tracks_to_solo, tr)
            end
            break
          end
        end
      end
    end

    -- Stop preview if active
    if alt.is_previewing then
      for _, entry in ipairs(alt.preview_muted) do
        if entry.type == "mute" then
          reaper.SetMediaTrackInfo_Value(entry.tr, "B_MUTE", 0)
        else
          reaper.SetMediaTrackInfo_Value(entry.tr, "I_SOLO", 0)
        end
      end
      alt.preview_muted = {}
      alt.is_previewing = false
    end

    -- Apply mutes and solos
    for _, tr in ipairs(tracks_to_mute) do
      reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 1)
    end
    for _, tr in ipairs(tracks_to_solo) do
      reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", 1)
    end

    -- Render
    ensure_dir(export_path)
    reaper.Main_OnCommand(40026, 0)
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    export_path .. "/", true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", filename,           true)
    reaper.GetSetProjectInfo(0, "RENDER_STARTPOS",   start_pos, true)
    reaper.GetSetProjectInfo(0, "RENDER_ENDPOS",     end_pos,   true)
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 2,         true)
    reaper.Main_OnCommand(41824, 0)

    -- Restore mutes and solos
    for _, tr in ipairs(tracks_to_mute) do
      reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 0)
    end
    for _, tr in ipairs(tracks_to_solo) do
      reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
    end

    -- Add to history
    save_history_entry(snapshots_path, {
      version  = cur_version,
      date     = os.date("%Y-%m-%d %H:%M"),
      filename = filename,
      note     = label,
    })

    set_log("Exported: " .. filename)
  end

  reaper.ImGui_PopStyleColor(ctx, 3)
  if not can_alt then reaper.ImGui_EndDisabled(ctx) end

  -- ── Handle export ─────────────────────────────────────────
  if clicked_ver and can_export then
    ensure_dir(export_path)
    local filename = resolve_name(buf_format, meta, clicked_ver)

    -- Save project, set render params, launch render
    reaper.Main_OnCommand(40026, 0)
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    export_path .. "/", true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", filename,           true)
    reaper.GetSetProjectInfo(0, "RENDER_STARTPOS",   start_pos, true)
    reaper.GetSetProjectInfo(0, "RENDER_ENDPOS",     end_pos,   true)
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 2,         true)
    reaper.Main_OnCommand(41824, 0)

    -- Only update version if file was actually created
    local wav_path = export_path .. "/" .. filename .. ".wav"
    local f_check  = io.open(wav_path, "r")
    if not f_check then
      set_log("Export cancelled — version not updated")
      return
    end
    local f_size = f_check:seek("end")
    f_check:close()
    if f_size == 0 then
      os.remove(wav_path)
      set_log("Export cancelled — version not updated")
      return
    end

    -- RPP snapshot next to project file
    copy_file(proj_path .. "/" .. proj_name,
              snapshots_path .. "/" .. filename .. ".RPP")

    -- Update metadata
    meta.version      = clicked_ver
    meta.base_version = ""
    M.save(meta)

    -- History
    save_history_entry(snapshots_path, {
      version  = clicked_ver,
      date     = os.date("%Y-%m-%d %H:%M"),
      filename = filename,
      note     = buf_note,
    })
    buf_note = ""
    is_draft = false
    set_log("Exported: " .. filename)
  end

  -- ── History ───────────────────────────────────────────────
  if has_project then
    local hist = load_history(snapshots_path)
    if #hist > 0 then
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Text(ctx, "Version history")
      reaper.ImGui_Spacing(ctx)
      for idx, e in ipairs(hist) do
        -- Open RPP button
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
          H.rgb_to_imgui(40, 40, 65))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
          H.rgb_to_imgui(60, 60, 95))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
          H.rgb_to_imgui(40, 40, 65))
        if reaper.ImGui_SmallButton(ctx, e.version .. "##open_" .. idx) then
          local rpp = snapshots_path .. "/" .. e.filename .. ".RPP"
          meta.base_version = e.version
          M.save(meta)
          reaper.Main_openProject(rpp)
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_BeginTooltip(ctx)
          reaper.ImGui_Text(ctx, "Open RPP snapshot")
          reaper.ImGui_EndTooltip(ctx)
        end

        -- Delete button
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
          H.rgb_to_imgui(80, 30, 30))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
          H.rgb_to_imgui(110, 40, 40))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
          H.rgb_to_imgui(70, 25, 25))
        if reaper.ImGui_SmallButton(ctx, "✕##del_" .. idx) then
          alt.pending_delete = { version = e.version, filename = e.filename }
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_BeginTooltip(ctx)
          reaper.ImGui_Text(ctx, "Delete this version")
          reaper.ImGui_EndTooltip(ctx)
        end

        -- Info
        reaper.ImGui_SameLine(ctx)
        local info = e.date
        if e.note ~= "" then info = info .. "  — " .. e.note end
        reaper.ImGui_TextDisabled(ctx, info)
      end
    end
  end

  -- ── Handle pending deletion (outside ImGui render) ───────
  if alt.pending_delete then
    local pd = alt.pending_delete
    alt.pending_delete = nil
    local confirm = reaper.ShowMessageBox(
      "Delete version " .. pd.version .. " ?\n\n" ..
      "This will remove:\n" ..
      "  " .. pd.filename .. ".wav\n" ..
      "  " .. pd.filename .. ".RPP\n" ..
      "  History entry",
      "Confirm deletion", 4)
    if confirm == 6 then
      os.remove(export_path .. "/" .. pd.filename .. ".wav")
      os.remove(snapshots_path .. "/" .. pd.filename .. ".RPP")
      local hist2 = load_history(snapshots_path)
      local new_entries = {}
      for _, entry in ipairs(hist2) do
        if entry.version ~= pd.version or entry.filename ~= pd.filename then
          table.insert(new_entries, entry)
        end
      end
      local fw = io.open(snapshots_path .. "/index.txt", "w")
      if fw then
        for _, entry in ipairs(new_entries) do
          fw:write(string.format("%s|%s|%s|%s\n",
            entry.version, entry.date, entry.filename, entry.note or ""))
        end
        fw:close()
      end
      set_log("Deleted: " .. pd.version)
    end
  end
end

return T
