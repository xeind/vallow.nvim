-- diagnostics.lua: push fallow findings as Neovim diagnostics into open buffers
-- Shows inline hints like LSP — e.g. "󰘍 unused export" greyed out on the line
local M = {}

local ns = vim.api.nvim_create_namespace("vallow_diag")

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
}

local LABEL = require("vallow.labels").label

-- Apply diagnostics for all open buffers that have findings
M.apply = function(findings)
  if not findings then
    return
  end
  local cfg = require("vallow.config").get()
  if not cfg.diagnostics or not cfg.diagnostics.enabled then
    return
  end

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
    if bucket and bucket.count > 0 then
      local sev = SEVERITY[cat_key] or vim.diagnostic.severity.HINT
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
    if bucket and bucket.count > 0 then
      local sev = SEVERITY[cat_key] or vim.diagnostic.severity.HINT
      local lbl = LABEL[cat_key] or cat_key
      for _, item in ipairs(bucket.items) do
        add(item.path, item.lnum, 0, lbl .. ": " .. (item.name or ""), sev)
      end
    end
  end

  -- Now push to open buffers (skip any where the fallow LSP is active)
  for path, diags in pairs(diags_by_path) do
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) and not lsp_active(bufnr) then
      vim.diagnostic.set(ns, bufnr, diags, {})
    end
  end
end

-- Clear all vallow diagnostics from all buffers
M.clear = function()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.diagnostic.reset(ns, bufnr)
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

  if not vim.api.nvim_buf_is_valid(bufnr) then
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
    if bucket and bucket.count > 0 then
      local sev = SEVERITY[cat_key] or vim.diagnostic.severity.HINT
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
    if bucket and bucket.count > 0 then
      local sev = SEVERITY[cat_key] or vim.diagnostic.severity.HINT
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
end

return M
