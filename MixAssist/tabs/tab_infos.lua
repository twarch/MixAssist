-- ============================================================
-- tabs/tab_infos.lua — ReaOrganizer
-- Infos tab: project metadata.
-- Artist/Title → native Reaper fields
-- BPM → native tempo + Tap BPM
-- Key → selector (note + major/minor)
-- ============================================================

local T = {}

local NOTES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local MODES = { "Major", "Minor" }

-- Upvalues persistantes entre les frames
local nf_note = tonumber(reaper.GetExtState("MixAssist", "nf_note")) or 0
local nf_oct  = tonumber(reaper.GetExtState("MixAssist", "nf_oct"))  or 4

-- Parse key string "C# Minor" → note_idx=2, mode_idx=2
local function parse_key(key_str)
  if not key_str or key_str == "" then return 1, 1 end
  for i, n in ipairs(NOTES) do
    for j, m in ipairs(MODES) do
      if key_str == n .. " " .. m then return i, j end
    end
  end
  return 1, 1
end

function T.render(ctx, state)
  local btn_w   = state.btn_w
  local H       = state.H
  local M       = state.M
  local set_log = state.set_log
  local bufs    = state.meta_bufs
  local tap     = state.tap_bpm
  local spacing = 8

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Project metadata")
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  local lw = 70
  local fw = btn_w - lw - spacing

  -- Artist
  reaper.ImGui_Text(ctx, "Artist")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)
  reaper.ImGui_SetNextItemWidth(ctx, fw)
  local ca, va = reaper.ImGui_InputText(ctx, "##artist", bufs.artist or "", 256)
  if ca then bufs.artist = va end
  reaper.ImGui_Spacing(ctx)

  -- Title
  reaper.ImGui_Text(ctx, "Title")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)
  reaper.ImGui_SetNextItemWidth(ctx, fw)
  local ct, vt = reaper.ImGui_InputText(ctx, "##title", bufs.title or "", 256)
  if ct then bufs.title = vt end
  reaper.ImGui_Spacing(ctx)

  -- BPM + Tap
  reaper.ImGui_Text(ctx, "BPM")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)
  local tap_w = 60
  reaper.ImGui_SetNextItemWidth(ctx, fw - tap_w - spacing)
  local cb, vb = reaper.ImGui_InputText(ctx, "##bpm", bufs.bpm or "", 256)
  if cb then bufs.bpm = vb end
  reaper.ImGui_SameLine(ctx)

  -- Désactiver l'écoute si inactivité > 3s
  local now = reaper.time_precise()
  if tap.listening and #tap.taps > 0 and (now - tap.taps[#tap.taps]) > 3.0 then
    tap.listening = false
    tap.taps = {}
    tap.last_bpm = nil
  end

  local function do_tap()
    local t = reaper.time_precise()
    if #tap.taps > 0 and (t - tap.taps[#tap.taps]) > 3.0 then
      tap.taps = {}
    end
    tap.listening = true
    table.insert(tap.taps, t)
    if #tap.taps >= 2 then
      local total = 0
      for i = 2, #tap.taps do
        total = total + (tap.taps[i] - tap.taps[i-1])
      end
      local avg_interval = total / (#tap.taps - 1)
      tap.last_bpm = math.floor(60.0 / avg_interval * 2 + 0.5) / 2
      local fmt = tap.last_bpm == math.floor(tap.last_bpm) and "%.0f" or "%.1f"
      bufs.bpm = string.format(fmt, tap.last_bpm)
    end
    while #tap.taps > 8 do table.remove(tap.taps, 1) end
  end

  -- Écouter la barre d'espace si en mode listening
  if tap.listening and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
    do_tap()
  end

  -- Tap BPM button
  local tap_label = tap.listening and "●Tap" or "Tap"
  if tap.last_bpm and not tap.listening then
    tap_label = string.format("%.0f", tap.last_bpm)
  end

  local col_btn = tap.listening
    and H.rgb_to_imgui(80, 50, 50)
    or  H.rgb_to_imgui(50, 70, 50)
  local col_hov = tap.listening
    and H.rgb_to_imgui(105, 70, 70)
    or  H.rgb_to_imgui(70, 95, 70)
  local col_act = tap.listening
    and H.rgb_to_imgui(65, 40, 40)
    or  H.rgb_to_imgui(40, 60, 40)

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col_btn)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  col_hov)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   col_act)
  if reaper.ImGui_Button(ctx, tap_label .. "##tap", tap_w, 0) then
    do_tap()
  end
  reaper.ImGui_PopStyleColor(ctx, 3)
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    if not tap.listening then
      reaper.ImGui_Text(ctx, "Click or press Space to start tapping")
    elseif #tap.taps < 2 then
      reaper.ImGui_Text(ctx, "Keep tapping... (Space or click)")
    else
      reaper.ImGui_Text(ctx, string.format("%.1f BPM (%d taps)", tap.last_bpm or 0, #tap.taps))
      reaper.ImGui_Text(ctx, "Space or click to refine, wait 3s to reset")
    end
    reaper.ImGui_EndTooltip(ctx)
  end

  -- Reset taps button (small x)
  if #tap.taps > 0 then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
      H.rgb_to_imgui(60, 35, 35))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
      H.rgb_to_imgui(85, 50, 50))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),
      H.rgb_to_imgui(50, 30, 30))
    if reaper.ImGui_SmallButton(ctx, "✕##tapreset") then
      tap.taps    = {}
      tap.last_bpm = nil
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
  end

  reaper.ImGui_Spacing(ctx)

  -- Key selector
  local note_idx, mode_idx = parse_key(bufs.key)
  reaper.ImGui_Text(ctx, "Key")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)

  local note_w = 45
  local mode_w = 60

  -- Note combo
  reaper.ImGui_SetNextItemWidth(ctx, note_w)
  local note_ok = reaper.ImGui_BeginCombo(ctx, "##keynote", NOTES[note_idx])
  if note_ok then
    for i, n in ipairs(NOTES) do
      if reaper.ImGui_Selectable(ctx, n, i == note_idx) then
        note_idx = i
        bufs.key = NOTES[note_idx] .. " " .. MODES[mode_idx]
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end

  reaper.ImGui_SameLine(ctx)

  -- Mode combo
  reaper.ImGui_SetNextItemWidth(ctx, mode_w)
  local mode_ok = reaper.ImGui_BeginCombo(ctx, "##keymode", MODES[mode_idx])
  if mode_ok then
    for i, m in ipairs(MODES) do
      if reaper.ImGui_Selectable(ctx, m, i == mode_idx) then
        mode_idx = i
        bufs.key = NOTES[note_idx] .. " " .. MODES[mode_idx]
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end

  reaper.ImGui_Spacing(ctx)

  -- Genre
  reaper.ImGui_Text(ctx, "Genre")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)
  reaper.ImGui_SetNextItemWidth(ctx, fw)
  local cg, vg = reaper.ImGui_InputText(ctx, "##genre", bufs.genre or "", 256)
  if cg then bufs.genre = vg end
  reaper.ImGui_Spacing(ctx)

  -- Album / EP
  reaper.ImGui_Text(ctx, "Album/EP")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)
  reaper.ImGui_SetNextItemWidth(ctx, fw)
  local cal, val = reaper.ImGui_InputText(ctx, "##album", bufs.album or "", 256)
  if cal then bufs.album = val end
  reaper.ImGui_Spacing(ctx)

  -- Time Signature
  reaper.ImGui_Text(ctx, "Time sig")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)

  local ts_num, ts_den = 4, 4
  do
    local num, den = reaper.TimeMap_GetTimeSigAtTime(0, 0)
    ts_num = num; ts_den = den
  end

  -- Lire depuis bufs ou Reaper
  if not bufs.ts_num then bufs.ts_num = ts_num end
  if not bufs.ts_den then bufs.ts_den = ts_den end

  local num_w = 30
  local den_w = 30
  local sl_w  = 10

  reaper.ImGui_SetNextItemWidth(ctx, num_w)
  local ctn, vtn = reaper.ImGui_InputText(ctx, "##ts_num", tostring(bufs.ts_num), 256)
  if ctn then bufs.ts_num = tonumber(vtn) or bufs.ts_num end

  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, "/")
  reaper.ImGui_SameLine(ctx)

  reaper.ImGui_SetNextItemWidth(ctx, den_w)
  local ctd, vtd = reaper.ImGui_InputText(ctx, "##ts_den", tostring(bufs.ts_den), 256)
  if ctd then bufs.ts_den = tonumber(vtd) or bufs.ts_den end

  reaper.ImGui_Spacing(ctx)

  -- Version (read-only)
  reaper.ImGui_Text(ctx, "Version")
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetCursorPosX(ctx, lw)
  reaper.ImGui_TextDisabled(ctx,
    bufs.version ~= "" and bufs.version or "Not exported yet")
  reaper.ImGui_Spacing(ctx)

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  if reaper.ImGui_Button(ctx, "Save", btn_w, 0) then
    M.save(bufs)
    set_log("Metadata saved")
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_TextDisabled(ctx,
    string.format("Current BPM: %.2f", reaper.Master_GetTempo()))

  -- ── Calculateur Tempo ─────────────────────────────────────
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Tempo Calculator")
  reaper.ImGui_Spacing(ctx)

  local bpm = tonumber(bufs.bpm) or reaper.Master_GetTempo()
  if bpm <= 0 then bpm = 120 end
  local beat_ms = 60000 / bpm

  -- Lignes : { base_label, mult_normal, mult_triplet, mult_dotted }
  local rows = {
    { "1/1",   4,        4/1.5,        6         },
    { "1/2",   2,        2/1.5,        3         },
    { "1/4",   1,        1/1.5,        1.5       },
    { "1/8",   0.5,      0.5/1.5,      0.75      },
    { "1/16",  0.25,     0.25/1.5,     0.375     },
    { "1/32",  0.125,    0.125/1.5,    0.1875    },
    { "1/64",  0.0625,   0.0625/1.5,   0.09375   },
    { "1/128", 0.03125,  0.03125/1.5,  0.046875  },
  }

  local cw = math.floor((btn_w - 16) / 3)  -- largeur de chaque colonne

  -- Header
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), H.rgb_to_imgui(130, 130, 130))
  reaper.ImGui_Text(ctx, string.format("%-6s%-7s", "", "ms"))
  reaper.ImGui_SameLine(ctx, cw + 8)
  reaper.ImGui_Text(ctx, string.format("%-6s%-7s", "T", "ms"))
  reaper.ImGui_SameLine(ctx, cw * 2 + 16)
  reaper.ImGui_Text(ctx, string.format("%-6s%-7s", ".", "ms"))
  reaper.ImGui_PopStyleColor(ctx, 1)

  local C_NORMAL_LBL  = H.rgb_to_imgui(130, 130, 130)  -- label note normal (gris)
  local C_NORMAL_VAL  = H.rgb_to_imgui(220, 220, 220)  -- valeur ms normal (blanc)
  local C_TRIPLET_LBL = H.rgb_to_imgui(100, 100, 170)  -- label triolet (bleu sombre)
  local C_TRIPLET_VAL = H.rgb_to_imgui(160, 160, 230)  -- valeur ms triolet (bleu clair)
  local C_DOTTED_LBL  = H.rgb_to_imgui(100, 150, 100)  -- label pointé (vert sombre)
  local C_DOTTED_VAL  = H.rgb_to_imgui(160, 210, 140)  -- valeur ms pointé (vert clair)

  for _, row in ipairs(rows) do
    local label, mn, mt, md = row[1], row[2], row[3], row[4]

    -- Colonne normale
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_NORMAL_LBL)
    reaper.ImGui_Text(ctx, string.format("%-6s", label))
    reaper.ImGui_PopStyleColor(ctx, 1)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_NORMAL_VAL)
    reaper.ImGui_Text(ctx, string.format("%.1f", beat_ms * mn))
    reaper.ImGui_PopStyleColor(ctx, 1)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, string.format("%.3f Hz", 1000 / (beat_ms * mn)))
      reaper.ImGui_EndTooltip(ctx)
    end

    -- Colonne triolet
    reaper.ImGui_SameLine(ctx, cw + 8)
    if mt then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_TRIPLET_LBL)
      reaper.ImGui_Text(ctx, string.format("%-6s", label .. "T"))
      reaper.ImGui_PopStyleColor(ctx, 1)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_TRIPLET_VAL)
      reaper.ImGui_Text(ctx, string.format("%.1f", beat_ms * mt))
      reaper.ImGui_PopStyleColor(ctx, 1)
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, string.format("%.3f Hz", 1000 / (beat_ms * mt)))
        reaper.ImGui_EndTooltip(ctx)
      end
    else
      reaper.ImGui_TextDisabled(ctx, "—")
    end

    -- Colonne pointé
    reaper.ImGui_SameLine(ctx, cw * 2 + 16)
    if md then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_DOTTED_LBL)
      reaper.ImGui_Text(ctx, string.format("%-6s", label .. "."))
      reaper.ImGui_PopStyleColor(ctx, 1)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_DOTTED_VAL)
      reaper.ImGui_Text(ctx, string.format("%.1f", beat_ms * md))
      reaper.ImGui_PopStyleColor(ctx, 1)
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, string.format("%.3f Hz", 1000 / (beat_ms * md)))
        reaper.ImGui_EndTooltip(ctx)
      end
    else
      reaper.ImGui_TextDisabled(ctx, "—")
    end
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), H.rgb_to_imgui(100, 100, 100))
  reaper.ImGui_Text(ctx, "T = triplet   . = dotted")
  reaper.ImGui_PopStyleColor(ctx, 1)

  -- ── Note → Frequency ──────────────────────────────────────
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Note → Frequency")
  reaper.ImGui_Spacing(ctx)

  -- État persistant dans state
  if state.nf_note == nil then
    state.nf_note = tonumber(reaper.GetExtState("MixAssist", "nf_note")) or 0
  end
  if state.nf_oct == nil then
    state.nf_oct = tonumber(reaper.GetExtState("MixAssist", "nf_oct")) or 4
  end

  local note_w = 46
  local oct_w  = 36
  local gap    = 6

  -- Sélecteur note
  reaper.ImGui_SetNextItemWidth(ctx, note_w)
  local note_ok = reaper.ImGui_BeginCombo(ctx, "##nf_note", NOTES[nf_note + 1])
  if note_ok then
    for i, n in ipairs(NOTES) do
      if reaper.ImGui_Selectable(ctx, n, i - 1 == nf_note) then
        nf_note = i - 1
        reaper.SetExtState("MixAssist", "nf_note", tostring(nf_note), true)
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end

  reaper.ImGui_SameLine(ctx)

  -- Sélecteur octave
  reaper.ImGui_SetNextItemWidth(ctx, oct_w)
  local oct_ok = reaper.ImGui_BeginCombo(ctx, "##nf_oct", tostring(nf_oct))
  if oct_ok then
    for o = 0, 8 do
      if reaper.ImGui_Selectable(ctx, tostring(o), o == nf_oct) then
        nf_oct = o
        reaper.SetExtState("MixAssist", "nf_oct", tostring(nf_oct), true)
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end

  reaper.ImGui_SameLine(ctx)

  -- Calcul fréquence : MIDI note = (octave+1)*12 + note_idx
  local midi = (nf_oct + 1) * 12 + nf_note
  local freq = 440 * 2 ^ ((midi - 69) / 12)

  -- Affichage fréquence
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), H.rgb_to_imgui(220, 200, 120))
  reaper.ImGui_Text(ctx, string.format("→  %.2f Hz", freq))
  reaper.ImGui_PopStyleColor(ctx, 1)

  -- Tooltip : longueur d'onde
  if reaper.ImGui_IsItemHovered(ctx) then
    local wavelength_cm = (34300 / freq)  -- vitesse du son ~343 m/s
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, string.format("λ = %.1f cm", wavelength_cm))
    if wavelength_cm >= 100 then
      reaper.ImGui_Text(ctx, string.format("  = %.2f m", wavelength_cm / 100))
    end
    reaper.ImGui_EndTooltip(ctx)
  end
end

return T
