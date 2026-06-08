local M = {}

M.setup = function(opts)
  require("vallow.config").setup(opts)
  require("vallow.panel.highlights").setup()
end

M.open = function()
  require("vallow.panel").open()
end

M.close = function()
  require("vallow.panel").close()
end

M.toggle = function()
  require("vallow.panel").toggle()
end

M.refresh = function()
  require("vallow.panel").refresh()
end

M.prefetch = function()
  require("vallow.panel").prefetch()
end

-- Open the panel (if not open) and filter findings to the current file.
-- Bind this to whatever key you like:
--   vim.keymap.set("n", "%", require("vallow").filter_current_file)
M.filter_current_file = function()
  local panel = require("vallow.panel")
  local path = vim.api.nvim_buf_get_name(0)
  if not path or path == "" then
    return
  end

  -- Open panel first if it isn't up
  if not panel._is_open() then
    panel.open()
  end

  local pbuf = panel.state.buf
  if not pbuf then
    return
  end

  local root = panel.state.results and panel.state.results.repo_root
  local rel = root and path:gsub("^" .. vim.pesc(root) .. "/", "") or vim.fn.fnamemodify(path, ":.")

  -- Toggle: pressing again on the same file clears the filter
  if (vim.b[pbuf].vallow_filter or "") == rel then
    vim.b[pbuf].vallow_filter = ""
    vim.notify("vallow: filter cleared", vim.log.levels.INFO)
  else
    vim.b[pbuf].vallow_filter = rel
    vim.notify("vallow: filter → " .. rel, vim.log.levels.INFO)
  end

  if panel.state.results then
    require("vallow.panel.render").render(pbuf, panel.state.results, panel.state.win)
  end
end

-- Returns a statusline string showing the current finding count.
-- Works without Nerd Font by default. Override prefix via setup:
--   require("vallow").setup({ statusline = { prefix = " " } })
--
-- Examples:
--   lualine:  { require("vallow").statusline, color = { fg = "#f9c74f" } }
--   raw:      %{%v:lua.require('vallow').statusline()%}
M.statusline = function()
  local cfg = (require("vallow.config").get().statusline or {})
  local prefix = cfg.prefix ~= nil and cfg.prefix or "vallow "
  local state = require("vallow.panel").state
  if not state.results then
    return ""
  end
  if state.results._loading then
    return prefix .. "…"
  end
  if state.results.error then
    return prefix .. "!"
  end
  if not state.results.findings then
    return ""
  end
  local total = 0
  for _, b in pairs(state.results.findings) do
    if type(b) == "table" and b.count then
      total = total + b.count
    end
  end
  return prefix .. (total > 0 and tostring(total) or "✓")
end

-- Structured counts for custom integrations.
M.get_counts = function()
  local state = require("vallow.panel").state
  if not state.results or not state.results.findings then
    return { total = 0, loading = false, error = false }
  end
  if state.results._loading then
    return { total = 0, loading = true, error = false }
  end
  if state.results.error then
    return { total = 0, loading = false, error = true }
  end
  local total = 0
  for _, b in pairs(state.results.findings) do
    if type(b) == "table" and b.count then
      total = total + b.count
    end
  end
  return { total = total, loading = false, error = false }
end

return M
