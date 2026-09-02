-- lualine.lua: a lualine component with per-severity finding counts.
--   require("lualine").setup({
--     sections = { lualine_x = { require("vallow").lualine() } },
--   })
local M = {}

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local SEV_ORDER = { "error", "warn", "hint" }
local SEV_LETTER = { error = "E", warn = "W", hint = "H" }

-- Findings grouped by the severity each display category declares.
M.counts = function(findings)
  local cfg = require("vallow.config").get()
  local out = { error = 0, warn = 0, hint = 0 }
  for cat_key, cat_cfg in pairs(cfg.categories or {}) do
    local sev = cat_cfg.severity or "hint"
    if out[sev] then
      for _, key in ipairs(cat_cfg.sources or { cat_key }) do
        local bucket = findings[key]
        if type(bucket) == "table" and bucket.count then
          out[sev] = out[sev] + bucket.count
        end
      end
    end
  end
  return out
end

-- Statusline string: a spinner while fallow runs, "✓" when clean, otherwise
-- "E:2 W:5 H:40" with one highlight group per severity.
M.status = function()
  local cfg = require("vallow.config").get().statusline or {}
  local prefix = cfg.prefix ~= nil and cfg.prefix or "vallow "
  local state = require("vallow.panel").state
  if not state.results then
    return ""
  end
  if state.results._loading then
    local frame = SPINNER[(math.floor(vim.uv.now() / 100) % #SPINNER) + 1]
    return prefix .. frame
  end
  if state.results.error then
    return prefix .. "%#VallowSevError#!%*"
  end
  if not state.results.findings then
    return ""
  end

  local counts = M.counts(state.results.findings)
  local parts = {}
  local sev_hl = require("vallow.panel.highlights").sev_hl
  for _, sev in ipairs(SEV_ORDER) do
    if counts[sev] > 0 then
      table.insert(parts, ("%%#%s#%s:%d%%*"):format(sev_hl[sev], SEV_LETTER[sev], counts[sev]))
    end
  end
  if #parts == 0 then
    return prefix .. "✓"
  end
  return prefix .. table.concat(parts, " ")
end

M.component = function()
  return {
    function()
      return M.status()
    end,
  }
end

return M
