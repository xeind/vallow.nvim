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

-- Focus the vallow panel window from any buffer.
-- Bind to whatever key you like, e.g.:
--   vim.keymap.set("n", "<leader>vv", require("vallow").focus)
-- <C-w>p also works natively since the panel is the previous window after a jump.
M.focus = function()
  local panel = require("vallow.panel")
  if panel._is_open() then
    vim.api.nvim_set_current_win(panel.state.win)
  end
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

-- Export current findings as markdown into a new scratch buffer.
M.export = function()
  local state = require("vallow.panel").state
  if not state.results or not state.results.findings then
    vim.notify("vallow: no results — open :Vallow first", vim.log.levels.WARN)
    return
  end
  local md_lines = require("vallow.exporter").to_markdown(state.results)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, md_lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.api.nvim_buf_set_name(buf, "vallow://report.md")
  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.notify("vallow: report opened — yank or :w to save", vim.log.levels.INFO)
end

-- Show a compact summary float with per-category counts.
M.summary = function()
  local state = require("vallow.panel").state
  if not state.results then
    vim.notify("vallow: no results yet — open :Vallow first", vim.log.levels.WARN)
    return
  end

  local cfg = require("vallow.config").get()
  local lines = { "" }
  local hls = {}
  local function push(text, hl)
    table.insert(lines, text)
    if hl then
      table.insert(hls, { hl = hl, lnum = #lines - 1 })
    end
  end

  local total = 0
  -- Build ordered sections
  local sections = {}
  for s_key, s_cfg in pairs(cfg.sections or {}) do
    table.insert(sections, { key = s_key, cfg = s_cfg })
  end
  table.sort(sections, function(a, b)
    return a.cfg.order < b.cfg.order
  end)

  for _, sec in ipairs(sections) do
    local sec_total = 0
    local cat_rows = {}
    for c_key, c_cfg in pairs(cfg.categories or {}) do
      if c_cfg.section == sec.key then
        local count = 0
        if c_cfg.sources then
          for _, src in ipairs(c_cfg.sources) do
            local b = state.results.findings and state.results.findings[src]
            if b then
              count = count + (b.count or 0)
            end
          end
        else
          local b = state.results.findings and state.results.findings[c_key]
          count = b and b.count or 0
        end
        if count > 0 then
          sec_total = sec_total + count
          table.insert(cat_rows, { label = c_cfg.label, count = count, order = c_cfg.order })
        end
      end
    end
    if sec_total > 0 then
      total = total + sec_total
      table.sort(cat_rows, function(a, b)
        return a.order < b.order
      end)
      push("  " .. (sec.cfg.icon or "") .. " " .. sec.cfg.label, "VallowSection")
      for _, row in ipairs(cat_rows) do
        local lbl = "    " .. row.label
        local cnt = tostring(row.count)
        local pad = math.max(1, 32 - vim.fn.strdisplaywidth(lbl) - #cnt)
        push(lbl .. string.rep(" ", pad) .. cnt, "Comment")
      end
    end
  end

  if total == 0 then
    push("  ✓ No issues found", "VallowFooter")
  end
  push("")
  push(string.format("  %d issue%s total", total, total == 1 and "" or "s"), "VallowFooter")
  if state.results.duration_ms and state.results.duration_ms > 0 then
    lines[#lines] = lines[#lines] .. string.format("  (%dms)", state.results.duration_ms)
  end
  push("")

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.max(36, math.min(width + 4, vim.o.columns - 8))

  local fbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, lines)
  vim.bo[fbuf].modifiable = false

  local row = math.floor((vim.o.lines - #lines) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local fwin = vim.api.nvim_open_win(fbuf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = " Vallow Summary ",
    title_pos = "center",
  })
  vim.wo[fwin].cursorline = false

  local ns = vim.api.nvim_create_namespace("vallow_summary")
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(fbuf, ns, h.hl, h.lnum, 0, -1)
  end

  -- Close on any key
  for _, k in ipairs({ "q", "<Esc>", "<CR>", "<Space>" }) do
    vim.keymap.set("n", k, function()
      pcall(vim.api.nvim_win_close, fwin, true)
      pcall(vim.api.nvim_buf_delete, fbuf, { force = true })
    end, { buffer = fbuf, nowait = true, silent = true })
  end
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
