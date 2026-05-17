-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- tabs/tab_quickbalance.lua — MixAssist
-- Onglet Quick Balance : bouton + sliders de niveaux cibles
-- QB intégré avec progression frame par frame via defer
-- ============================================================

local T = {}

-- ── État QB (upvalue de module) ───────────────────────────────
local _qb = {
  running     = false,
  done        = false,
  folders     = {},
  current     = 0,
  total       = 0,
  label       = "",
  set_log     = nil,
  H           = nil,
  initialized = false,
}

local NS = "MixAssist_QB"
local function qb_get(key, default)
  local v = tonumber(reaper.GetExtState(NS, key))
  return v ~= nil and v or default
end

local function get_targets()
  return {
    BD   = qb_get("target_BD",   -5),
    SD   = qb_get("target_SD",   -5),
    TOM  = qb_get("target_TOM",  -5),
    CLP  = qb_get("target_CLP",  -5),
    CYM  = qb_get("target_CYM",  -25),
    HH   = qb_get("target_HH",   -20),
    OH   = qb_get("target_OH",   -20),
    ROOM = qb_get("target_ROOM", -30),
    BA   = qb_get("target_BA",   -12.5),
    EG   = qb_get("target_EG",   -20),
    AG   = qb_get("target_AG",   -17),
    PL   = qb_get("target_AG",   -17),
    KB   = qb_get("target_KB",   -20),
    SY   = qb_get("target_SY",   -20),
    PE   = qb_get("target_PE",   -25),
    BR   = qb_get("target_BR",   -20),
    ST   = qb_get("target_BR",   -20),
    WW   = qb_get("target_WW",   -20),
    FX   = qb_get("target_FX",   -25),
    LV   = qb_get("target_LV",   -10),
    BV   = qb_get("target_BV",   -15),
    DV   = qb_get("target_BV",   -15),
    VX   = qb_get("target_BV",   -15),
  }
end

local BUS_CAT = {
  ["BD BUS"]   = "BD",
  ["SD BUS"]   = "SD",
  ["TOM BUS"]  = "TOM",
  ["OH BUS"]   = "OH",
  ["ROOM BUS"] = "ROOM",
}

local function lin_to_db(v)
  if v <= 0 then return -150 end
  return 20 * math.log(v) / math.log(10)
end

local function db_to_lin(db)
  if db <= -150 then return 0 end
  return 10 ^ (db / 20)
end

local function measure_tracks_peak(tracks)
  local bsize   = 4096
  local silence = db_to_lin(-30)
  local peaks   = {}
  for _, tr in ipairs(tracks) do
    local nch = math.max(1, reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN"))
    for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local item = reaper.GetTrackMediaItem(tr, j)
      local take = reaper.GetActiveTake(item)
      if take then
        local src   = reaper.GetMediaItemTake_Source(take)
        local fname = reaper.GetMediaSourceFileName(src, "")
        if fname ~= "" then
          local acc     = reaper.CreateTakeAudioAccessor(take)
          local sr      = reaper.GetMediaSourceSampleRate(src)
          local len     = reaper.GetMediaSourceLength(src)
          local block_s = bsize / sr
          local buf     = reaper.new_array(bsize * nch)
          local pos     = 0
          while pos < len do
            if reaper.GetAudioAccessorSamples(acc, sr, nch, pos, bsize, buf) == 1 then
              local blk = 0
              for i = 1, bsize * nch do
                local v = math.abs(buf[i])
                if v > blk then blk = v end
              end
              if blk > silence then table.insert(peaks, blk) end
            end
            pos = pos + block_s
          end
          reaper.DestroyAudioAccessor(acc)
        end
      end
    end
  end
  if #peaks == 0 then return nil end
  table.sort(peaks, function(a, b) return a > b end)
  local n   = math.max(1, math.floor(#peaks * 0.10))
  local sum = 0
  for i = 1, n do sum = sum + peaks[i] end
  return sum / n
end

local function measure_tracks_max(tracks)
  local max_peak = 0
  for _, tr in ipairs(tracks) do
    local peak = measure_tracks_peak({ tr })
    if peak and peak > max_peak then max_peak = peak end
  end
  return max_peak > 0 and max_peak or nil
end

local function apply_gain(tracks, gain_db)
  local gl = db_to_lin(gain_db)
  for _, tr in ipairs(tracks) do
    local cur = reaper.GetMediaTrackInfo_Value(tr, "D_VOL")
    reaper.SetMediaTrackInfo_Value(tr, "D_VOL", cur * gl)
  end
end

local function quick_balance_folder(folder_name, folder_cat, H, TARGETS, SDB_OFFSET)
  local folder = H.find_track(folder_name)
  if not folder then return end
  local children = H.get_direct_children(folder)
  if #children == 0 then return end

  local already_adjusted = {}
  reaper.Undo_BeginBlock()

  for _, child in ipairs(children) do
    local _, child_name = reaper.GetTrackName(child)
    local is_bus  = reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH") >= 1
    local bus_cat = BUS_CAT[child_name]
    if already_adjusted[tostring(child)] then goto continue end

    local target
    if bus_cat then
      target = TARGETS[bus_cat]
    elseif folder_cat == "DR" then
      local dtype = H.drum_classify(child_name)
      if     dtype == "ROOM"    then target = TARGETS.ROOM
      elseif dtype == "OH"      then target = TARGETS.OH
      elseif dtype == "HAT"     then target = TARGETS.HH
      elseif dtype == "TOM"     then target = TARGETS.TOM
      elseif dtype == "CLAP"    then target = TARGETS.CLP
      elseif dtype == "CYM"     then target = TARGETS.CYM
      elseif dtype == "SD_TOP" or dtype == "SD_BOT" or dtype == "SD_TRIGGER" then
        target = TARGETS.SD
      else target = TARGETS.BD end
    else
      target = TARGETS[folder_cat] or -20
    end

    local to_measure, to_adjust
    if is_bus then
      local leaves = H.get_leaf_tracks(H.get_direct_children(child))
      local audio_leaves, all_audio = {}, {}
      for _, tr in ipairs(leaves) do
        if H.has_audio(tr) then
          table.insert(all_audio, tr)
          if bus_cat == "SD" then
            local _, tname = reaper.GetTrackName(tr)
            if H.drum_classify(tname) ~= "SD_BOT" then
              table.insert(audio_leaves, tr)
            end
          else
            table.insert(audio_leaves, tr)
          end
        end
      end
      to_measure = audio_leaves
      to_adjust  = all_audio
    else
      if not H.has_audio(child) then goto continue end
      to_measure = { child }
      to_adjust  = { child }
    end

    local peak
    if is_bus then
      peak = measure_tracks_max(to_measure)
      local n = #to_measure
      if n > 1 then target = target - 10 * math.log(n) / math.log(10) end
    else
      peak = measure_tracks_peak(to_measure)
    end

    if peak and peak > 0 then
      local peak_db = lin_to_db(peak)
      local gain_db = target - peak_db
      apply_gain(to_adjust, gain_db)
      if bus_cat == "SD" then
        for _, tr in ipairs(to_adjust) do
          local _, tname = reaper.GetTrackName(tr)
          if H.drum_classify(tname) == "SD_BOT" then
            local cur = reaper.GetMediaTrackInfo_Value(tr, "D_VOL")
            reaper.SetMediaTrackInfo_Value(tr, "D_VOL", cur * db_to_lin(SDB_OFFSET))
          end
        end
      end
      if is_bus then
        for _, tr in ipairs(to_adjust) do
          already_adjusted[tostring(tr)] = true
        end
      end
    end
    ::continue::
  end

  reaper.Undo_EndBlock("Quick Balance: " .. folder_name, -1)
  reaper.UpdateArrange()
end

local function apply_headroom(H, headroom)
  local headroom_lin = db_to_lin(headroom)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr    = reaper.GetTrack(0, i)
    local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    local show  = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")
    if show == 1 and depth < 1 and H.has_audio(tr) then
      local cur = reaper.GetMediaTrackInfo_Value(tr, "D_VOL")
      reaper.SetMediaTrackInfo_Value(tr, "D_VOL", cur * headroom_lin)
    end
  end
end

-- ── API publique ──────────────────────────────────────────────

function T.is_running() return _qb.running end

function T.progress() return _qb.current, _qb.total, _qb.label end

function T.tick()
  if not _qb.running then return end
  local H = _qb.H
  if _qb.current <= _qb.total then
    local f = _qb.folders[_qb.current]
    if f then
      _qb.label = f[1]
      local TARGETS    = get_targets()
      local SDB_OFFSET = qb_get("sdb_offset", -15)
      quick_balance_folder(f[1], f[2], H, TARGETS, SDB_OFFSET)
      _qb.current = _qb.current + 1
    else
      _qb.current = _qb.current + 1
    end
  else
    apply_headroom(H, qb_get("headroom", -1.5))
    reaper.SetProjExtState(0, "MixAssist_QB", "status", "done")
    _qb.running = false
    _qb.done    = true
    _qb.label   = ""
  end
end

local _qb_start_state = nil

local function qb_defer_tick()
  if not _qb.running then return end

  -- Premier appel : juste laisser l'UI se redessiner
  if not _qb.initialized then
    _qb.initialized = true
    reaper.defer(qb_defer_tick)
    return
  end

  -- Deuxième appel : initialiser les dossiers
  if _qb_start_state then
    local state       = _qb_start_state
    _qb_start_state   = nil
    local cfg         = state.cfg
    local cfg_folders = (cfg and cfg.FOLDERS) or {}
    local folders = {}
    for _, def in ipairs(cfg_folders) do
      if def.cat ~= "UNK" and def.name and _qb.H.find_track(def.name) then
        table.insert(folders, { def.name, def.cat })
      end
    end
    if #folders == 0 then
      _qb.running = false
      if _qb.set_log then _qb.set_log("QB: aucun dossier trouvé") end
      return
    end
    _qb.folders = folders
    _qb.total   = #folders
    _qb.current = 1
    _qb.label   = folders[1][1]
    reaper.defer(qb_defer_tick)
    return
  end

  T.tick()
  if _qb.running then
    reaper.defer(qb_defer_tick)
  end
end

-- ── Render ────────────────────────────────────────────────────

function T.render(ctx, state)
  local btn_w   = state.btn_w
  local H       = state.H
  local set_log = state.set_log

  reaper.ImGui_Spacing(ctx)

  -- Bouton QB
  local running  = _qb.running
  local _TH2 = nil
  local sp2 = ({reaper.get_action_context()})[2]:match("^(.*[\\/])")
  if sp2 then pcall(function() _TH2 = dofile(sp2 .. "lib/theme.lua") end) end
  local th = state.theme or {}

  local col_qb   = running and H.rgb_to_imgui(50, 50, 50)
    or (_TH2 and _TH2.btn(th, "btn_primary") or H.rgb_to_imgui(40, 80, 140))
  local col_qb_h = running and H.rgb_to_imgui(50, 50, 50)
    or (_TH2 and _TH2.btn_hov(th, "btn_primary") or H.rgb_to_imgui(55, 100, 170))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),       col_qb)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_qb_h)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  col_qb)
  if running then reaper.ImGui_BeginDisabled(ctx) end
  if reaper.ImGui_Button(ctx, "⚡  Quick Balance", btn_w, 36) then
    _qb.running     = true
    _qb.done        = false
    _qb.current     = 0
    _qb.total       = 1
    _qb.label       = "Initialisation..."
    _qb.H           = state.H
    _qb.set_log     = state.set_log
    _qb.initialized = false
    _qb_start_state = state
    reaper.defer(qb_defer_tick)
  end
  if running then reaper.ImGui_EndDisabled(ctx) end
  reaper.ImGui_PopStyleColor(ctx, 3)

  -- Barre de progression ou message done
  if _qb.running then
    local cur, total, label = T.progress()
    local fraction = total > 0 and math.max(0, math.min(1, (cur - 1) / total)) or 0
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, string.format("⏳ %s (%d/%d)", label, math.max(0, cur - 1), total))
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local cx, cy = reaper.ImGui_GetCursorScreenPos(ctx)
    local bar_h, bar_w, radius = 10, btn_w, 4
    local bar_color = _TH2 and _TH2.btn(th, "btn_progress") or 0x4A9B5AFF
    reaper.ImGui_DrawList_AddRectFilled(draw_list, cx, cy, cx + bar_w, cy + bar_h, 0x222222FF, radius)
    if fraction > 0 then
      local fill_w = math.max(radius * 2, bar_w * fraction)
      reaper.ImGui_DrawList_AddRectFilled(draw_list, cx, cy, cx + fill_w, cy + bar_h, bar_color, radius)
    end
    reaper.ImGui_DrawList_AddRect(draw_list, cx, cy, cx + bar_w, cy + bar_h, 0x666666FF, radius)
    reaper.ImGui_Dummy(ctx, bar_w, bar_h)
    reaper.ImGui_Spacing(ctx)
  elseif _qb.done then
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),
      _TH2 and _TH2.btn(th, "btn_progress") or 0x4A9B5AFF)
    reaper.ImGui_Text(ctx, "✓ Quick Balance done")
    reaper.ImGui_PopStyleColor(ctx, 1)
    reaper.ImGui_Spacing(ctx)
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  local function qb_slider(label, key, default, min, max, fmt)
    local val = tonumber(reaper.GetExtState(NS, key)) or default
    reaper.ImGui_SetNextItemWidth(ctx, btn_w - 110)
    local ch, nv = reaper.ImGui_SliderDouble(
      ctx, "##qb_" .. key, val, min, max, fmt or "%.1f dB")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, label)
    if ch then reaper.SetExtState(NS, key, tostring(nv), true) end
    return nv
  end

  reaper.ImGui_TextDisabled(ctx, "Drums")
  qb_slider("Kick",               "target_BD",   -5,    -30, 0)
  qb_slider("Snare",              "target_SD",   -5,    -30, 0)
  qb_slider("Toms",               "target_TOM",  -5,    -30, 0)
  qb_slider("Clap / Rimshot",     "target_CLP",  -5,    -30, 0)
  qb_slider("Crash / Ride / Cym","target_CYM",  -25,   -40, 0)
  qb_slider("Hi-hats",            "target_HH",   -20,   -40, 0)
  qb_slider("Overheads",          "target_OH",   -20,   -40, 0)
  qb_slider("Room",               "target_ROOM", -30,   -50, 0)
  qb_slider("Snare bottom offset","sdb_offset",  -15,   -30, 0)
  qb_slider("Percussions",        "target_PE",   -25,   -30, 0)

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_TextDisabled(ctx, "Instruments")
  qb_slider("Bass",               "target_BA",  -12.5, -30, 0)
  qb_slider("Electric Guitar",    "target_EG",  -20,   -30, 0)
  qb_slider("Acoustic Guitar",    "target_AG",  -17,   -30, 0)
  qb_slider("Keys / Piano",       "target_KB",  -20,   -30, 0)
  qb_slider("Synth",              "target_SY",  -20,   -30, 0)
  qb_slider("Brass / Horns",      "target_BR",  -20,   -30, 0)
  qb_slider("Woodwinds",          "target_WW",  -20,   -30, 0)
  qb_slider("FX",                 "target_FX",  -25,   -30, 0)

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_TextDisabled(ctx, "Vocals")
  qb_slider("Lead Vocals",        "target_LV",  -10,   -30, 0)
  qb_slider("Backing / Double",   "target_BV",  -15,   -30, 0)

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_TextDisabled(ctx, "Global")
  qb_slider("Headroom",           "headroom",   -1.5,  -6,  0)

  reaper.ImGui_Spacing(ctx)
  if reaper.ImGui_Button(ctx, "Reset to defaults", btn_w, 0) then
    local defaults = {
      target_BD=-5, target_SD=-5, target_TOM=-5, target_CLP=-5, target_CYM=-25,
      target_HH=-20, target_OH=-20, target_ROOM=-30, sdb_offset=-15,
      target_BA=-12.5, target_EG=-20, target_AG=-17, target_KB=-20,
      target_SY=-20, target_BR=-20, target_WW=-20, target_PE=-25,
      target_FX=-25, target_LV=-10, target_BV=-15, headroom=-1.5,
    }
    for k, v in pairs(defaults) do
      reaper.SetExtState(NS, k, tostring(v), true)
    end
    set_log("Quick Balance reset to defaults")
  end
end

return T