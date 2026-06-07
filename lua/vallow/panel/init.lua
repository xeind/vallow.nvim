local M = {}

M.state = {
  buf             = nil,
  win             = nil,
  results         = nil,
  current_section = nil,  -- nil = ALL tabs visible
}


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
    once   = true,
    callback = function()
      require("vallow.panel.render").clear(M.state.buf)
      M.state.buf = nil
      M.state.win = nil
    end,
  })

  require("vallow.panel.actions").setup(M.state.buf)

  -- Re-apply diagnostics when a new buffer is opened after analysis ran
  vim.api.nvim_create_autocmd("BufEnter", {
    group    = vim.api.nvim_create_augroup("VallowDiagBufEnter", { clear = true }),
    callback = function(ev)
      if M.state.results and M.state.results.findings then
        require("vallow.diagnostics").apply_buf(ev.buf, M.state.results.findings)
      end
    end,
  })

  M.refresh()
end

M.close = function()
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
  if not M._is_open() then return end

  local render = require("vallow.panel.render")

  -- Show loading state immediately
  render.render(M.state.buf, { _loading = true }, M.state.win)
  require("vallow.panel.tabs").set_winbar(
    M.state.win, M.state.current_section, nil, require("vallow.config").get())

  require("vallow.runner").run(function(results)
    M.state.results = results
    if M._is_open() then
      render.render(M.state.buf, results, M.state.win)
      require("vallow.panel.tabs").set_winbar(
        M.state.win, M.state.current_section, results, require("vallow.config").get())
    end
    -- Push findings as inline diagnostics to open buffers
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
