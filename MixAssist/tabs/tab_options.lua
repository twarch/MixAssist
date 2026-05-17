-- ============================================================
-- MixAssist — Suite de scripts pour Reaper
-- Conçu et développé par Gaëtan Bonnard (Le Mixoir)
-- Développement assisté par Claude (Anthropic)
-- ============================================================

-- ============================================================
-- tabs/tab_options.lua — MixAssist
-- Options tab avec sous-onglets : Organise | QB | FX | Export | Theme
-- ============================================================

local T = {}

function T.render(ctx, state)
  local btn_w       = state.btn_w
  local H           = state.H
  local TH          = state.TH
  local theme       = state.theme
  local set_log     = state.set_log
  local script_path = state.script_path
  local spacing     = 4

  reaper.ImGui_Spacing(ctx)

  if not reaper.ImGui_BeginTabBar(ctx, "##options_tabs") then return end

  -- ══════════════════════════════════════════════════════════
  -- Onglet Organise
  -- ══════════════════════════════════════════════════════════
  if reaper.ImGui_BeginTabItem(ctx, "Organise") then
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, "⚙  Categories & keywords", btn_w, 30) then
      H.run_script(script_path, "ROConfig.lua")
      set_log("ROConfig opened")
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    reaper.ImGui_TextDisabled(ctx, "TOM BUS gate plugin")
    reaper.ImGui_Spacing(ctx)
    local tom_plugin = reaper.GetExtState("MixAssist", "tom_gate_plugin")
    if tom_plugin == "" then tom_plugin = "VST: ReaGate (Cockos)" end
    reaper.ImGui_SetNextItemWidth(ctx, btn_w - 30)
    local cp, vp = reaper.ImGui_InputText(ctx, "##tom_gate_plugin", tom_plugin, 256)
    if cp then reaper.SetExtState("MixAssist", "tom_gate_plugin", vp, true) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "…##br_tom") and state.open_fx_browser then
      state.open_fx_browser(function(v) reaper.SetExtState("MixAssist", "tom_gate_plugin", v, true) end, 1)
    end

    reaper.ImGui_EndTabItem(ctx)
  end

  -- ══════════════════════════════════════════════════════════
  -- Onglet FX
  -- ══════════════════════════════════════════════════════════
  if reaper.ImGui_BeginTabItem(ctx, "FX") then
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, "⚙  FX Chains & Parallel tracks", btn_w, 30) then
      if state.open_fxconfig then state.open_fxconfig() end
      set_log("FXConfig opened")
    end
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    reaper.ImGui_TextDisabled(ctx, "Master FX")
    reaper.ImGui_Spacing(ctx)
    local master_chain = reaper.GetExtState("MixAssist", "master_fxchain")
    if master_chain == "" then master_chain = "MASTER.rfxchain" end
    reaper.ImGui_SetNextItemWidth(ctx, btn_w - 30)
    local cmc, vmc = reaper.ImGui_InputText(ctx, "##master_fxchain", master_chain, 256)
    if cmc then reaper.SetExtState("MixAssist", "master_fxchain", vmc, true) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "…##br_master") and state.open_fx_browser then
      state.open_fx_browser(function(v) reaper.SetExtState("MixAssist", "master_fxchain", v, true) end, 0)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    reaper.ImGui_TextDisabled(ctx, "Trigger plugin (BD & SD)")
    reaper.ImGui_Spacing(ctx)

    local function trig_field(label, plugin_key, preset_key, default_plugin)
      local plugin = reaper.GetExtState("MixAssist", plugin_key)
      if plugin == "" then plugin = default_plugin end
      local preset = reaper.GetExtState("MixAssist", preset_key)

      reaper.ImGui_Text(ctx, label .. " plugin")
      reaper.ImGui_SetNextItemWidth(ctx, btn_w - 30)
      local cp2, vp2 = reaper.ImGui_InputText(ctx, "##" .. plugin_key, plugin, 256)
      if cp2 then reaper.SetExtState("MixAssist", plugin_key, vp2, true) end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "…##br_" .. plugin_key) and state.open_fx_browser then
        local pk = plugin_key
        state.open_fx_browser(function(v) reaper.SetExtState("MixAssist", pk, v, true) end, 1)
      end

      reaper.ImGui_Text(ctx, label .. " preset")
      reaper.ImGui_SetNextItemWidth(ctx, btn_w)
      local cr, vr = reaper.ImGui_InputText(ctx, "##" .. preset_key, preset, 256)
      if cr then reaper.SetExtState("MixAssist", preset_key, vr, true) end
      reaper.ImGui_Spacing(ctx)
    end

    trig_field("BD", "bd_trig_plugin", "bd_trig_preset", "VST3: Trigger 2 (Steven Slate)")
    trig_field("SD", "sd_trig_plugin", "sd_trig_preset", "VST3: Trigger 2 (Steven Slate)")

    reaper.ImGui_EndTabItem(ctx)
  end

  -- ══════════════════════════════════════════════════════════
  -- Onglet Export
  -- ══════════════════════════════════════════════════════════
  if reaper.ImGui_BeginTabItem(ctx, "Export") then
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextDisabled(ctx, "Export options coming soon")
    reaper.ImGui_EndTabItem(ctx)
  end

  -- ══════════════════════════════════════════════════════════
  -- Onglet Theme
  -- ══════════════════════════════════════════════════════════
  if reaper.ImGui_BeginTabItem(ctx, "Theme") then
    reaper.ImGui_Spacing(ctx)

    local label_w = 100
    local picker_w = btn_w - label_w - 8

    local COLOR_FIELDS = {
      { key = "bg",          label = "Background"   },
      { key = "accent",      label = "Accent"       },
      { key = "tab_active",  label = "Active tab"   },
      { key = "text",        label = "Text"         },
      { key = "text_dim",    label = "Dimmed text"  },
      { key = "frame_bg",    label = "Input bg"     },
      { key = "separator",   label = "Separator"    },
    }

    reaper.ImGui_SeparatorText(ctx, "Boutons")
    reaper.ImGui_Spacing(ctx)

    local BTN_FIELDS = {
      { key = "btn_primary",  label = "Principal"   },
      { key = "btn_done",     label = "Fait (vert)" },
      { key = "btn_default",  label = "Défaut"      },
      { key = "btn_danger",   label = "Danger"      },
      { key = "btn_ara",      label = "ARA"         },
      { key = "btn_commit",   label = "Commit"      },
      { key = "btn_master",   label = "Master"      },
      { key = "btn_progress", label = "Progression" },
    }

    local changed = false

    reaper.ImGui_SeparatorText(ctx, "Interface")
    reaper.ImGui_Spacing(ctx)

    local function color_picker(fields)
      for _, f in ipairs(fields) do
        local c = theme[f.key]
        if not c then goto skip end
        reaper.ImGui_Text(ctx, f.label)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, label_w)
        reaper.ImGui_SetNextItemWidth(ctx, picker_w)
        local flags = 0
        if reaper.ImGui_ColorEditFlags_NoInputs then
          flags = reaper.ImGui_ColorEditFlags_NoInputs()
        end
        local packed = TH.to_imgui(c)
        local ok, new_packed = reaper.ImGui_ColorEdit4(ctx, "##" .. f.key, packed, flags)
        if ok then
          local r = ((new_packed >> 24) & 0xFF) / 255.0
          local g = ((new_packed >> 16) & 0xFF) / 255.0
          local b = ((new_packed >> 8)  & 0xFF) / 255.0
          local a = ( new_packed        & 0xFF) / 255.0
          theme[f.key] = { r, g, b, a }
          if f.key == "accent" then
            theme.accent_hov = { math.min(1,r+0.1), math.min(1,g+0.1), math.min(1,b+0.1), a }
            theme.tab_active = { r, g, b, a }
          end
          if f.key == "bg" then
            theme.bg_child = { math.max(0,r-0.02), math.max(0,g-0.02), math.max(0,b-0.02), a }
            theme.header   = { math.min(1,r+0.05), math.min(1,g+0.05), math.min(1,b+0.05), a }
          end
          changed = true
        end
        ::skip::
      end
    end

    color_picker(COLOR_FIELDS)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_SeparatorText(ctx, "Boutons")
    reaper.ImGui_Spacing(ctx)
    color_picker(BTN_FIELDS)

    if changed then TH.save(theme) end

    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_Button(ctx, "Reset to defaults", btn_w, 0) then
      TH.reset(theme)
      set_log("Theme reset to defaults")
    end

    reaper.ImGui_EndTabItem(ctx)
  end

  reaper.ImGui_EndTabBar(ctx)
end

return T
