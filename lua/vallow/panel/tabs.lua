-- Winbar tab strip for the vallow panel.
local M = {}

-- Ordered section keys — defines cycling order and tab display order
M.order = { "unused_code", "issues", "duplicates", "health", "architecture" }

local SHORT = {
  unused_code  = "UNUSED",
  issues       = "ISSUES",
  duplicates   = "DUPES",
  health       = "HEALTH",
  architecture = "ARCH",
}

local function tab(text, hl)
  return "%#" .. hl .. "#" .. text .. "%*"
end

M.set_winbar = function(win, current_section, results, cfg)
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  local render   = require("vallow.panel.render")
  local findings = results
    and not results._loading
    and not results.error
    and results.findings

  -- Compute per-section totals
  local counts = {}
  if findings and cfg then
    for _, sec in ipairs(render._build_sections(cfg)) do
      local total = 0
      for _, cat in ipairs(sec.cats) do
        local d = render._resolve_findings(cat.key, cat.cfg, findings)
        if d then total = total + d.count end
      end
      counts[sec.key] = total
    end
  end

  local sep  = tab(" │ ", "VallowTabSep")
  local parts = {}

  -- ALL tab
  local all_hl = current_section == nil and "VallowTabActive" or "VallowTabInactive"
  table.insert(parts, tab(" ALL ", all_hl))

  for _, key in ipairs(M.order) do
    local label = SHORT[key] or key:upper()
    local cnt   = counts[key]
    local text  = cnt and cnt > 0
      and (" " .. label .. " " .. cnt .. " ")
      or  (" " .. label .. " ")
    local hl    = current_section == key and "VallowTabActive" or "VallowTabInactive"
    table.insert(parts, tab(text, hl))
  end

  vim.api.nvim_set_option_value("winbar", table.concat(parts, sep), { win = win })
end

-- Returns the next section key (nil = ALL)
M.next = function(current)
  if current == nil then return M.order[1] end
  for i, key in ipairs(M.order) do
    if key == current then
      return M.order[i + 1]  -- nil when at last → wraps to ALL
    end
  end
  return nil
end

-- Returns the previous section key (nil = ALL)
M.prev = function(current)
  if current == nil then return M.order[#M.order] end
  for i, key in ipairs(M.order) do
    if key == current then
      return i > 1 and M.order[i - 1] or nil  -- nil when at first → wraps to ALL
    end
  end
  return nil
end

return M
