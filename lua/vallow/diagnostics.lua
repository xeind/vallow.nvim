-- diagnostics.lua: push fallow findings as Neovim diagnostics into open buffers
-- Shows inline hints like LSP — e.g. "󰘍 unused export" greyed out on the line
local M = {}

local ns = vim.api.nvim_create_namespace("vallow_diag")
-- Complexity virtual lines and hotspot signs are extmarks, not diagnostics,
-- so they live in their own namespace.
local virt_ns = vim.api.nvim_create_namespace("vallow_virt")

-- Returns true if the fallow LSP is attached to the buffer — in that case
-- the LSP owns inline diagnostics and we skip ours to avoid duplicates.
local function lsp_active(bufnr)
  return #vim.lsp.get_clients({ bufnr = bufnr, name = "fallow" }) > 0
end

-- Finding categories that have per-line path+lnum info
local LINE_CATS = {
  "unused_exports",
  "unused_types",
  "unused_enum_members",
  "unused_class_members",
  "unresolved_imports",
  "unlisted_deps",
  "duplicate_exports",
  "circular_deps",
  "health_complexity",
  "dev_dep_in_prod",
  "css_token_drift",
  "raw_style_value",
}

-- Severity per finding category
local SEVERITY = {
  unused_exports = vim.diagnostic.severity.HINT,
  unused_types = vim.diagnostic.severity.HINT,
  unused_enum_members = vim.diagnostic.severity.HINT,
  unused_class_members = vim.diagnostic.severity.HINT,
  unused_files = vim.diagnostic.severity.INFO,
  unused_deps = vim.diagnostic.severity.WARN,
  unused_dev_deps = vim.diagnostic.severity.HINT,
  unused_optional_deps = vim.diagnostic.severity.HINT,
  unresolved_imports = vim.diagnostic.severity.ERROR,
  unlisted_deps = vim.diagnostic.severity.WARN,
  duplicate_exports = vim.diagnostic.severity.WARN,
  circular_deps = vim.diagnostic.severity.WARN,
  clone_groups = vim.diagnostic.severity.HINT,
  health_complexity = vim.diagnostic.severity.WARN,
  dev_dep_in_prod = vim.diagnostic.severity.ERROR,
  css_token_drift = vim.diagnostic.severity.WARN,
  raw_style_value = vim.diagnostic.severity.HINT,
}

local SEVERITY_BY_NAME = {
  error = vim.diagnostic.severity.ERROR,
  warn = vim.diagnostic.severity.WARN,
  info = vim.diagnostic.severity.INFO,
  hint = vim.diagnostic.severity.HINT,
}

-- Severity for a category after config.diagnostics.categories overrides.
-- Returns nil when the category is turned off.
local function severity_for(cat_key, dcfg)
  local cat = (dcfg.categories or {})[cat_key]
  if cat and cat.enabled == false then
    return nil
  end
  local name = cat and cat.severity
  return (name and SEVERITY_BY_NAME[tostring(name):lower()]) or SEVERITY[cat_key] or vim.diagnostic.severity.HINT
end

-- Virtual text is a namespace option, so it applies to our diagnostics only.
local function apply_ns_opts(dcfg)
  vim.diagnostic.config({ virtual_text = dcfg.virtual_text ~= false }, ns)
end

local LABEL = require("vallow.labels").label

-- Draw the complexity virtual lines and hotspot signs for one buffer.
-- Always clears first, so turning the option off removes them on the next run.
M.apply_virt = function(bufnr, findings, dcfg)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, virt_ns, 0, -1)
  if not dcfg.virtual_lines then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if not path or path == "" then
    return
  end
  local last = vim.api.nvim_buf_line_count(bufnr)

  local complexity = findings.health_complexity
  for _, item in ipairs(complexity and complexity.items or {}) do
    local lnum = math.max(1, item.lnum or 1)
    if item.path == path and lnum <= last then
      local text = ("ƒ cyclomatic %s · cognitive %s"):format(item.cyclomatic or "?", item.cognitive or "?")
      -- Line up with the function's own indent.
      local src = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
      local indent = src:match("^%s*") or ""
      pcall(vim.api.nvim_buf_set_extmark, bufnr, virt_ns, lnum - 1, 0, {
        virt_lines = { { { indent .. text, "VallowKind" } } },
        virt_lines_above = true,
      })
    end
  end

  -- Hotspots name a file, not a line; the sign goes on its first line.
  local hotspots = findings.health_hotspots
  for _, item in ipairs(hotspots and hotspots.items or {}) do
    if item.path == path then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, virt_ns, 0, 0, {
        sign_text = "󱐋",
        sign_hl_group = "VallowKind",
      })
    end
  end
end

-- Apply diagnostics for all open buffers that have findings
M.apply = function(findings)
  if not findings then
    return
  end
  local cfg = require("vallow.config").get()
  if not cfg.diagnostics or not cfg.diagnostics.enabled then
    return
  end
  local dcfg = cfg.diagnostics
  apply_ns_opts(dcfg)

  -- Clear stale diagnostics from all loaded buffers before reapplying
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      vim.diagnostic.reset(ns, bufnr)
    end
  end

  -- Collect all diagnostics keyed by absolute path
  local diags_by_path = {}

  local function add(path, lnum, col, message, severity)
    if not path or path == "" then
      return
    end
    if not diags_by_path[path] then
      diags_by_path[path] = {}
    end
    table.insert(diags_by_path[path], {
      lnum = math.max(0, (lnum or 1) - 1), -- 0-indexed
      col = col or 0,
      message = message,
      severity = severity,
      source = "fallow",
    })
  end

  -- Per-line finding categories (have path + line)
  for _, cat_key in ipairs(LINE_CATS) do
    local bucket = findings[cat_key]
    local sev = severity_for(cat_key, dcfg)
    if bucket and bucket.count > 0 and sev then
      local lbl = LABEL[cat_key] or cat_key
      for _, item in ipairs(bucket.items) do
        local msg = (item.name and item.name ~= "") and (lbl .. ": " .. item.name) or lbl
        add(item.path, item.lnum, item.col or 0, msg, sev)
      end
    end
  end

  -- unused_deps: show on package.json line
  for _, cat_key in ipairs({ "unused_deps", "unused_dev_deps", "unused_optional_deps" }) do
    local bucket = findings[cat_key]
    local sev = severity_for(cat_key, dcfg)
    if bucket and bucket.count > 0 and sev then
      local lbl = LABEL[cat_key] or cat_key
      for _, item in ipairs(bucket.items) do
        add(item.path, item.lnum, 0, lbl .. ": " .. (item.name or ""), sev)
      end
    end
  end

  -- Now push to open buffers (skip any where the fallow LSP is active)
  local only = dcfg.current_buffer_only and vim.api.nvim_get_current_buf() or nil
  for path, diags in pairs(diags_by_path) do
    local bufnr = vim.fn.bufnr(path)
    if only and bufnr ~= only then
      bufnr = -1
    end
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) and not lsp_active(bufnr) then
      vim.diagnostic.set(ns, bufnr, diags, {})
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and (not only or bufnr == only) then
      M.apply_virt(bufnr, findings, dcfg)
    end
  end
end

-- Clear all vallow diagnostics from all buffers
M.clear = function()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.diagnostic.reset(ns, bufnr)
      vim.api.nvim_buf_clear_namespace(bufnr, virt_ns, 0, -1)
    end
  end
end

-- Refresh diagnostics for a single buffer (e.g. on BufEnter)
-- called with the current results if the panel has run
M.apply_buf = function(bufnr, findings)
  if not findings then
    return
  end
  local cfg = require("vallow.config").get()
  if not cfg.diagnostics or not cfg.diagnostics.enabled then
    return
  end
  local dcfg = cfg.diagnostics
  apply_ns_opts(dcfg)

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if dcfg.current_buffer_only and bufnr ~= vim.api.nvim_get_current_buf() then
    return
  end
  if lsp_active(bufnr) then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if not path or path == "" then
    return
  end

  local diags = {}

  for _, cat_key in ipairs(LINE_CATS) do
    local bucket = findings[cat_key]
    local sev = severity_for(cat_key, dcfg)
    if bucket and bucket.count > 0 and sev then
      local lbl = LABEL[cat_key] or cat_key
      for _, item in ipairs(bucket.items) do
        if item.path == path then
          local msg = (item.name and item.name ~= "") and (lbl .. ": " .. item.name) or lbl
          table.insert(diags, {
            lnum = math.max(0, (item.lnum or 1) - 1),
            col = item.col or 0,
            message = msg,
            severity = sev,
            source = "fallow",
          })
        end
      end
    end
  end

  for _, cat_key in ipairs({ "unused_deps", "unused_dev_deps", "unused_optional_deps" }) do
    local bucket = findings[cat_key]
    local sev = severity_for(cat_key, dcfg)
    if bucket and bucket.count > 0 and sev then
      local lbl = LABEL[cat_key] or cat_key
      for _, item in ipairs(bucket.items) do
        if item.path == path then
          table.insert(diags, {
            lnum = math.max(0, (item.lnum or 1) - 1),
            col = 0,
            message = lbl .. ": " .. (item.name or ""),
            severity = sev,
            source = "fallow",
          })
        end
      end
    end
  end

  vim.diagnostic.set(ns, bufnr, diags, {})
  M.apply_virt(bufnr, findings, dcfg)
end

return M
