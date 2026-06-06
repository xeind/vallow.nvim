local M = {}

M.setup = function(buf)
  local cfg   = require("vallow.config").get().keymaps
  local panel = require("vallow.panel")

  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
  end

  map(cfg.close,        function() panel.close() end)
  map(cfg.refresh,      function() panel.refresh() end)
  map(cfg.next_tab,     function() M.switch_tab(buf, 1)  end)
  map(cfg.prev_tab,     function() M.switch_tab(buf, -1) end)
  map(cfg.toggle_fold,  function() M.toggle_fold(buf) end)
  map(cfg.next_section, function() M.move_section(buf, 1) end)
  map(cfg.prev_section, function() M.move_section(buf, -1) end)
  map(cfg.filter,       function() M.filter(buf) end)
  map(cfg.clear_filter, function() M.clear_filter(buf) end)
  map(cfg.pick,         function() require("vallow.picker").open(panel.state.results) end)

  -- Jump modes
  map(cfg.jump, function() M._do_jump(buf, "edit") end)
  map("o",      function() M._do_jump(buf, "split") end)
  map("v",      function() M._do_jump(buf, "vsplit") end)
  map("t",      function() M._do_jump(buf, "tabedit") end)

  -- Vim-native fold keys
  map("za", function() M.toggle_fold(buf) end)
  map("zo", function() M.set_fold(buf, true) end)
  map("zc", function() M.set_fold(buf, false) end)
  map("zR", function() M.set_all_folds(buf, true) end)
  map("zM", function() M.set_all_folds(buf, false) end)

  -- Actions
  map("Q", function() M.send_to_qf(buf) end)
  map("y", function() M.yank_path(buf) end)
  map("?", function() require("vallow.panel.help").open() end)
end

-- ── Jump ─────────────────────────────────────────────────────────────

M._do_jump = function(buf, cmd)
  local item = M._item_at_cursor(buf)
  if not item then return end

  -- Headers / more rows → fold action
  if item._type == "section" or item._type == "header" or item._type == "more" then
    M.toggle_fold(buf)
    return
  end

  local path = item.path
  if not path or path == "" then return end

  if cmd == "tabedit" then
    pcall(vim.cmd, "tabedit " .. vim.fn.fnameescape(path))
  else
    vim.cmd("wincmd p")
    local ok = pcall(vim.cmd, cmd .. " " .. vim.fn.fnameescape(path))
    if not ok then return end
  end

  if item.lnum then
    pcall(vim.api.nvim_win_set_cursor, 0,
      { math.max(1, item.lnum), math.max(0, item.col or 0) })
    vim.cmd("normal! zz")
    vim.highlight.on_yank({ higroup = "Search", timeout = 250 })
  end
end

-- ── Folds ────────────────────────────────────────────────────────────

M.toggle_fold = function(buf)
  local item = M._item_at_cursor(buf)
  if not item then return end

  if item._type == "more" then
    local full = vim.b[buf].vallow_cats_full or {}
    full[item.key] = true
    vim.b[buf].vallow_cats_full = full

  elseif item._type == "section" then
    local s = vim.b[buf].vallow_open_secs or {}
    s[item.key] = not (s[item.key] ~= false)
    vim.b[buf].vallow_open_secs = s

  elseif item._type == "header" then
    local c = vim.b[buf].vallow_open_cats or {}
    c[item.key] = not (c[item.key] == true)
    vim.b[buf].vallow_open_cats = c

  else
    return
  end

  local panel = require("vallow.panel")
  if panel.state.results then
    require("vallow.panel.render").render(buf, panel.state.results, panel.state.win)
  end
end

M.set_fold = function(buf, open)
  local item = M._item_at_cursor(buf)
  if not item then return end

  if item._type == "section" then
    local s = vim.b[buf].vallow_open_secs or {}
    s[item.key] = open
    vim.b[buf].vallow_open_secs = s
  elseif item._type == "header" then
    local c = vim.b[buf].vallow_open_cats or {}
    c[item.key] = open
    vim.b[buf].vallow_open_cats = c
  else
    return
  end

  local panel = require("vallow.panel")
  if panel.state.results then
    require("vallow.panel.render").render(buf, panel.state.results, panel.state.win)
  end
end

M.set_all_folds = function(buf, open)
  local cfg  = require("vallow.config").get()
  local secs = {}
  local cats = {}
  for key in pairs(cfg.sections   or {}) do secs[key] = open end
  for key in pairs(cfg.categories or {}) do cats[key] = open end
  vim.b[buf].vallow_open_secs = secs
  vim.b[buf].vallow_open_cats = cats

  local panel = require("vallow.panel")
  if panel.state.results then
    require("vallow.panel.render").render(buf, panel.state.results, panel.state.win)
  end
end

-- ── Tab switching ─────────────────────────────────────────────────────

M.switch_tab = function(buf, direction)
  local panel = require("vallow.panel")
  local tabs  = require("vallow.panel.tabs")
  local cur   = panel.state.current_section

  panel.state.current_section = direction > 0 and tabs.next(cur) or tabs.prev(cur)

  if panel.state.results then
    require("vallow.panel.render").render(buf, panel.state.results, panel.state.win)
    tabs.set_winbar(panel.state.win, panel.state.current_section,
      panel.state.results, require("vallow.config").get())
  end

  -- Reset cursor to top of content
  pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
end

M.move_section = function(buf, direction)
  local line_map  = require("vallow.panel.render").get_line_map(buf)
  local cur       = vim.api.nvim_win_get_cursor(0)[1]
  local sec_lines = {}
  for lnum, item in pairs(line_map) do
    if type(item) == "table" and item._type == "section" then
      table.insert(sec_lines, lnum)
    end
  end
  table.sort(sec_lines)

  local target = nil
  if direction > 0 then
    for _, lnum in ipairs(sec_lines) do
      if lnum > cur then target = lnum; break end
    end
  else
    for i = #sec_lines, 1, -1 do
      if sec_lines[i] < cur then target = sec_lines[i]; break end
    end
  end
  if target then vim.api.nvim_win_set_cursor(0, { target, 0 }) end
end

-- ── Quickfix export ──────────────────────────────────────────────────

M.send_to_qf = function(buf)
  local panel  = require("vallow.panel")
  local results = panel.state.results
  if not results or not results.findings then
    vim.notify("vallow: no findings — run :Vallow first", vim.log.levels.WARN)
    return
  end

  local filter = (vim.b[buf].vallow_filter or ""):lower()
  local function matches(item)
    if filter == "" then return true end
    return (item.relative_path or ""):lower():find(filter, 1, true) ~= nil
        or (item.name          or ""):lower():find(filter, 1, true) ~= nil
  end

  local LABEL = require("vallow.labels").label

  local qf_items = {}
  for cat_key, bucket in pairs(results.findings) do
    if type(bucket) == "table" and bucket.items then
      local lbl = LABEL[cat_key] or cat_key
      for _, item in ipairs(bucket.items) do
        if item.path and item.path ~= "" and matches(item) then
          table.insert(qf_items, {
            filename = item.path,
            lnum     = item.lnum or 1,
            col      = (item.col or 0) + 1,
            text     = lbl .. (item.name and item.name ~= "" and (": " .. item.name) or ""),
            type     = "W",
          })
        end
      end
    end
  end

  if #qf_items == 0 then
    vim.notify("vallow: no items to send to quickfix", vim.log.levels.INFO)
    return
  end

  table.sort(qf_items, function(a, b)
    if a.filename ~= b.filename then return a.filename < b.filename end
    return (a.lnum or 0) < (b.lnum or 0)
  end)

  local title = "Vallow" .. (filter ~= "" and (" [" .. filter .. "]") or "")
  vim.fn.setqflist({}, "r", { title = title, items = qf_items })
  vim.cmd("copen")
  vim.notify(string.format("vallow: %d items → quickfix", #qf_items), vim.log.levels.INFO)
end

-- ── Yank path ────────────────────────────────────────────────────────

M.yank_path = function(buf)
  local item = M._item_at_cursor(buf)
  if not item or item._type then
    vim.notify("vallow: nothing to yank", vim.log.levels.INFO)
    return
  end
  local text = item.relative_path or item.path or ""
  if item.lnum then text = text .. ":" .. item.lnum end
  if text == "" then
    vim.notify("vallow: no path on this item", vim.log.levels.INFO)
    return
  end
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify('vallow: copied "' .. text .. '"', vim.log.levels.INFO)
end

-- ── Filter ───────────────────────────────────────────────────────────

M.filter = function(buf)
  local panel     = require("vallow.panel")
  local panel_win = panel.state.win
  if not panel_win or not vim.api.nvim_win_is_valid(panel_win) then return end

  if M._search_win and vim.api.nvim_win_is_valid(M._search_win) then
    vim.api.nvim_set_current_win(M._search_win)
    return
  end

  local function rerender(query)
    vim.b[buf].vallow_filter = query
    if panel.state.results then
      require("vallow.panel.render").render(buf, panel.state.results, panel_win)
    end
  end

  vim.api.nvim_set_current_win(panel_win)
  vim.cmd("botright 2split")
  local swin = vim.api.nvim_get_current_win()
  local sbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(swin, sbuf)
  M._search_win = swin

  vim.wo[swin].number         = false
  vim.wo[swin].relativenumber = false
  vim.wo[swin].signcolumn     = "no"
  vim.wo[swin].foldcolumn     = "0"
  vim.wo[swin].wrap           = false
  vim.wo[swin].list           = false
  vim.wo[swin].cursorline     = false
  vim.wo[swin].winfixheight   = true
  vim.wo[swin].statusline     = "  󰍉 Filter  (Enter confirm · Esc clear)"

  local current = vim.b[buf].vallow_filter or ""
  vim.api.nvim_buf_set_lines(sbuf, 0, -1, false, { "  " .. current })
  vim.api.nvim_win_set_cursor(swin, { 1, #("  " .. current) })
  vim.bo[sbuf].filetype = "vallow_search"
  vim.cmd("startinsert!")

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer   = sbuf,
    callback = function()
      local line = vim.api.nvim_buf_get_lines(sbuf, 0, 1, false)[1] or ""
      rerender(line:gsub("^%s+", ""))
    end,
  })

  local function close()
    vim.cmd("stopinsert")
    M._search_win = nil
    pcall(vim.api.nvim_win_close, swin, true)
    pcall(vim.api.nvim_set_current_win, panel_win)
  end

  vim.keymap.set("i", "<CR>",  close,
    { buffer = sbuf, nowait = true, silent = true })
  vim.keymap.set("i", "<Esc>", function() rerender(""); close() end,
    { buffer = sbuf, nowait = true, silent = true })

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = sbuf, once = true,
    callback = function()
      M._search_win = nil
      pcall(vim.api.nvim_win_close, swin, true)
    end,
  })
end

M.clear_filter = function(buf)
  if (vim.b[buf].vallow_filter or "") == "" then return end
  vim.b[buf].vallow_filter = ""
  local panel = require("vallow.panel")
  if panel.state.results then
    require("vallow.panel.render").render(buf, panel.state.results, panel.state.win)
  end
end

-- ── Internal ─────────────────────────────────────────────────────────

M._item_at_cursor = function(buf)
  local lnum     = vim.api.nvim_win_get_cursor(0)[1]
  local line_map = require("vallow.panel.render").get_line_map(buf)
  return line_map[lnum]
end

return M
