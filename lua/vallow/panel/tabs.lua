-- Winbar tab strip for the vallow panel.
local M = {}

-- Cycling order — rebuilt from config each time set_winbar is called.
-- Only sections with findings (or the active section) are included.
M.order = {}

-- Derive a short tab label from a section label string ("UNUSED CODE" → "UNUSED")
local function short_label(label)
  return (label or ""):match("^(%S+)") or label or "?"
end

local function tab(text, hl)
  return "%#" .. hl .. "#" .. text .. "%*"
end

M.set_winbar = function(win, current_section, results, cfg)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local render = require("vallow.panel.render")
  local findings = results and not results._loading and not results.error and results.findings

  -- Build ordered section list from config (not hardcoded)
  local ordered = {}
  for key, sec_cfg in pairs(cfg and cfg.sections or {}) do
    table.insert(ordered, { key = key, icon = sec_cfg.icon or "", label = sec_cfg.label or key, order = sec_cfg.order or 99 })
  end
  table.sort(ordered, function(a, b)
    return a.order < b.order
  end)

  -- Compute per-section totals
  local counts = {}
  if findings and cfg then
    for _, sec in ipairs(render._build_sections(cfg)) do
      local total = 0
      for _, cat in ipairs(sec.cats) do
        local d = render._resolve_findings(cat.key, cat.cfg, findings)
        if d then
          total = total + d.count
        end
      end
      counts[sec.key] = total
    end
  end

  -- Rebuild M.order from sections that have findings or are active
  M.order = {}
  for _, sec in ipairs(ordered) do
    local cnt = counts[sec.key] or 0
    if cnt > 0 or sec.key == current_section then
      table.insert(M.order, sec.key)
    end
  end

  local sep = tab(" │ ", "VallowTabSep")
  local parts = {}

  -- ALL tab
  local all_hl = current_section == nil and "VallowTabActive" or "VallowTabInactive"
  table.insert(parts, tab(" ALL ", all_hl))

  for _, sec in ipairs(ordered) do
    local cnt = counts[sec.key] or 0
    -- Only show tab if it has findings or is currently active
    if cnt > 0 or sec.key == current_section then
      local icon = sec.icon or ""
      local label = short_label(sec.label)
      local text = cnt > 0 and (" " .. icon .. " " .. label .. " " .. cnt .. " ") or (" " .. icon .. " " .. label .. " ")
      local hl = current_section == sec.key and "VallowTabActive" or "VallowTabInactive"
      table.insert(parts, tab(text, hl))
    end
  end

  vim.api.nvim_set_option_value("winbar", table.concat(parts, sep), { win = win })
end

-- Returns the next section key (nil = ALL)
M.next = function(current)
  if current == nil then
    return M.order[1]
  end
  for i, key in ipairs(M.order) do
    if key == current then
      return M.order[i + 1] -- nil when at last → wraps to ALL
    end
  end
  return nil
end

-- Returns the previous section key (nil = ALL)
M.prev = function(current)
  if current == nil then
    return M.order[#M.order]
  end
  for i, key in ipairs(M.order) do
    if key == current then
      return i > 1 and M.order[i - 1] or nil -- nil when at first → wraps to ALL
    end
  end
  return nil
end

return M
