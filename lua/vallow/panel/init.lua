local M = {}

M.state = {
  buf = nil,
  win = nil,
  results = nil,
  current_section = nil, -- nil = ALL tabs visible
  -- Fold state persisted across panel closes (buffer variables are wiped with the buffer)
  fold_secs = {},
  fold_cats = {},
  fold_full = {},
}

-- Debounce timer for auto-refresh
local _refresh_timer = nil

M.open = function()
  if M._is_open() then
    vim.api.nvim_set_current_win(M.state.win)
    return
  end

  local handles = require("vallow.panel.window").create()
  M.state.buf = handles.buf
  M.state.win = handles.win

  -- Clean up state when buffer is closed
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = M.state.buf,
    once = true,
    callback = function()
      require("vallow.panel.render").clear(M.state.buf)
      M.state.buf = nil
      M.state.win = nil
    end,
  })

  -- Restore fold state from previous session
  vim.b[M.state.buf].vallow_open_secs = M.state.fold_secs
  vim.b[M.state.buf].vallow_open_cats = M.state.fold_cats
  vim.b[M.state.buf].vallow_cats_full = M.state.fold_full

  require("vallow.panel.actions").setup(M.state.buf)

  -- Auto-refresh on save (opt-in via config.auto_refresh)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("VallowAutoRefresh", { clear = true }),
    pattern = { "*.ts", "*.tsx", "*.js", "*.jsx", "*.mjs", "*.cjs", "package.json" },
    callback = function(ev)
      if not require("vallow.config").get().auto_refresh then
        return
      end
      -- Only refresh if the saved file belongs to the current project root
      local root = M.state.results and M.state.results.repo_root
      if root then
        local saved = vim.api.nvim_buf_get_name(ev.buf)
        if saved == "" or not saved:find(root, 1, true) then
          return
        end
      end
      -- Debounce: cancel any pending refresh before starting a new one
      if _refresh_timer then
        _refresh_timer:stop()
        _refresh_timer:close()
        _refresh_timer = nil
      end
      _refresh_timer = vim.uv.new_timer()
      _refresh_timer:start(500, 0, vim.schedule_wrap(function()
        _refresh_timer:close()
        _refresh_timer = nil
        M._bg_refresh()
      end))
    end,
  })

  -- Clear stale results when the working directory changes to a different project
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("VallowDirChanged", { clear = true }),
    callback = function()
      local runner = require("vallow.runner")
      local new_root = runner.find_root()
      local old_root = M.state.results and M.state.results.repo_root
      if new_root ~= old_root then
        M.state.results = nil
        -- Re-prefetch for the new directory
        runner.run(function(results)
          M.state.results = results
          if M._is_open() then
            require("vallow.panel.render").render(M.state.buf, results, M.state.win)
            require("vallow.panel.tabs").set_winbar(
              M.state.win,
              M.state.current_section,
              results,
              require("vallow.config").get()
            )
          end
          require("vallow.diagnostics").apply(results.findings)
        end)
      end
    end,
  })

  -- Re-apply diagnostics when a new buffer is opened after analysis ran
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("VallowDiagBufEnter", { clear = true }),
    callback = function(ev)
      if M.state.results and M.state.results.findings then
        require("vallow.diagnostics").apply_buf(ev.buf, M.state.results.findings)
      end
    end,
  })

  if M.state.results then
    -- Results already cached (prefetched) — render immediately, then refresh silently
    local render = require("vallow.panel.render")
    render.render(M.state.buf, M.state.results, M.state.win)
    require("vallow.panel.tabs").set_winbar(
      M.state.win,
      M.state.current_section,
      M.state.results,
      require("vallow.config").get()
    )
    M._bg_refresh()
  else
    M.refresh()
  end
end

M.close = function()
  -- Close orphaned filter search window if open
  local actions = require("vallow.panel.actions")
  if actions._search_win and vim.api.nvim_win_is_valid(actions._search_win) then
    pcall(vim.api.nvim_win_close, actions._search_win, true)
    actions._search_win = nil
  end
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    vim.api.nvim_win_close(M.state.win, true)
  end
  M.state.win = nil
  M.state.buf = nil
end

M.toggle = function()
  if M._is_open() then
    M.close()
  else
    M.open()
  end
end

M.refresh = function()
  if not M._is_open() then
    return
  end

  local render = require("vallow.panel.render")

  -- Show loading state immediately
  render.render(M.state.buf, { _loading = true }, M.state.win)
  require("vallow.panel.tabs").set_winbar(M.state.win, M.state.current_section, nil, require("vallow.config").get())

  require("vallow.runner").run(function(results)
    M.state.results = results
    if M._is_open() then
      render.render(M.state.buf, results, M.state.win)
      require("vallow.panel.tabs").set_winbar(
        M.state.win,
        M.state.current_section,
        results,
        require("vallow.config").get()
      )
    end
    -- Push findings as inline diagnostics to open buffers
    require("vallow.diagnostics").apply(results.findings)
  end)
end

-- Silent background run — updates results and re-renders if panel is open.
-- Used when opening with cached results (stale-while-revalidate), and by the
-- debounced auto-refresh path. Re-entrant: cancels any running timer.
M._bg_refresh = function()
  -- Cancel pending debounce timer if called directly (e.g. stale-while-revalidate on open)
  if _refresh_timer then
    _refresh_timer:stop()
    _refresh_timer:close()
    _refresh_timer = nil
  end
  require("vallow.runner").run(function(results)
    M.state.results = results
    if M._is_open() then
      require("vallow.panel.render").render(M.state.buf, results, M.state.win)
      require("vallow.panel.tabs").set_winbar(
        M.state.win,
        M.state.current_section,
        results,
        require("vallow.config").get()
      )
    end
    require("vallow.diagnostics").apply(results.findings)
  end)
end

-- Run fallow in the background without opening the panel.
-- Called on startup so the first open is instant.
M.prefetch = function()
  require("vallow.runner").run(function(results)
    M.state.results = results
    require("vallow.diagnostics").apply(results.findings)
  end)
end

M._is_open = function()
  return M.state.win
    and vim.api.nvim_win_is_valid(M.state.win)
    and M.state.buf
    and vim.api.nvim_buf_is_valid(M.state.buf)
end

return M
