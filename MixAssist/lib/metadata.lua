-- ============================================================
-- lib/metadata.lua — ReaOrganizer
-- Artist → PROJECT_AUTHOR (native Reaper)
-- Title  → PROJECT_TITLE  (native Reaper)
-- BPM    → native tempo
-- Key, Version, Base version → project notes
-- ============================================================

local M = {}

local META_PREFIX = "REAORGANIZER_META:"

function M.parse(notes)
  local meta = { key = "", version = "", base_version = "" }
  for line in notes:gmatch("[^\n]+") do
    if line:match("^" .. META_PREFIX) then
      local data = line:sub(#META_PREFIX + 1)
      for k, v in data:gmatch("([%w_]+)=([^|]*)") do
        meta[k] = v
      end
    end
  end
  return meta
end

function M.load()
  -- Native fields
  local _, artist = reaper.GetSetProjectInfo_String(0, "PROJECT_AUTHOR", "", false)
  local _, title  = reaper.GetSetProjectInfo_String(0, "PROJECT_TITLE",  "", false)
  local bpm       = string.format("%.2f", reaper.Master_GetTempo())

  -- Time signature from Reaper
  local ts_num, ts_den = reaper.TimeMap_GetTimeSigAtTime(0, 0)

  -- Notes fields
  local notes  = reaper.GetSetProjectNotes(0, false, "") or ""
  local meta   = M.parse(notes)

  meta.artist = artist or ""
  meta.title  = title  or ""
  meta.bpm    = bpm
  if not meta.genre  then meta.genre  = "" end
  if not meta.album  then meta.album  = "" end
  if not meta.ts_num then meta.ts_num = ts_num or 4 end
  if not meta.ts_den then meta.ts_den = ts_den or 4 end

  return meta
end

function M.save(meta)
  -- Save native fields
  if meta.artist then
    reaper.GetSetProjectInfo_String(0, "PROJECT_AUTHOR", meta.artist, true)
  end
  if meta.title then
    reaper.GetSetProjectInfo_String(0, "PROJECT_TITLE", meta.title, true)
  end
  if meta.bpm then
    local bpm_val = tonumber(meta.bpm)
    if bpm_val and bpm_val > 0 then
      reaper.SetCurrentBPM(0, bpm_val, true)
    end
  end
  -- Save time signature
  if meta.ts_num and meta.ts_den then
    local n = tonumber(meta.ts_num)
    local d = tonumber(meta.ts_den)
    if n and d and n > 0 and d > 0 then
      reaper.SetTempoTimeSigMarker(0, -1, 0, -1, -1, 0, n, d, false)
    end
  end

  -- Save notes fields
  local notes = reaper.GetSetProjectNotes(0, false, "") or ""
  notes = notes:gsub(META_PREFIX .. "[^\n]*\n?", "")
  local line = META_PREFIX
    .. "key="          .. (meta.key          or "") .. "|"
    .. "version="      .. (meta.version      or "") .. "|"
    .. "base_version=" .. (meta.base_version or "") .. "|"
    .. "genre="        .. (meta.genre        or "") .. "|"
    .. "album="        .. (meta.album        or "") .. "|"
    .. "ts_num="       .. (meta.ts_num       or 4)  .. "|"
    .. "ts_den="       .. (meta.ts_den       or 4)
  notes = notes .. "\n" .. line
  reaper.GetSetProjectNotes(0, true, notes)
end

return M
