-- float.lua: read-only centred float used by inspect, explain, and trace.
local M = {}

local ns = vim.api.nvim_create_namespace("vallow_float")

-- opts:
--   title    string
--   lines    string[]
--   hls      { { hl = group, lnum = 0-based line, col = start col } }
--   targets  { [1-based line] = { path = abs, lnum = number } }  -- <CR> jumps
-- Returns the buffer handle, or nil when there is nothing to show.
M.open = function(opts)
  local lines = opts.lines or {}
  if #lines == 0 then
    return nil
  end

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.max(40, math.min(width + 4, vim.o.columns - 8))
  local height = math.max(1, math.min(#lines, vim.o.lines - 6))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "vallow_float"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. (opts.title or "Vallow") .. " ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false

  for _, h in ipairs(opts.hls or {}) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, h.hl, h.lnum, h.col or 0, -1)
  end

  local function close()
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, close, { buffer = buf, nowait = true, silent = true })
  end

  local targets = opts.targets or {}
  vim.keymap.set("n", "<CR>", function()
    local target = targets[vim.api.nvim_win_get_cursor(win)[1]]
    if not target or not target.path or target.path == "" then
      return
    end
    close()
    -- Closing the float returns focus to the previous window; never edit into
    -- the panel itself.
    if vim.api.nvim_get_current_win() == require("vallow.panel").state.win then
      vim.cmd("wincmd p")
    end
    local opened = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(target.path))
    if opened then
      pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, target.lnum or 1), 0 })
      vim.cmd("normal! zz")
    end
  end, { buffer = buf, nowait = true, silent = true })

  return buf
end

-- Small builder shared by the callers: collects lines, highlights and jump
-- targets in one place.
M.builder = function()
  local b = { lines = {}, hls = {}, targets = {} }
  function b.push(text, hl, target)
    table.insert(b.lines, text)
    if hl then
      table.insert(b.hls, { hl = hl, lnum = #b.lines - 1, col = 0 })
    end
    if target then
      b.targets[#b.lines] = target
    end
  end
  return b
end

return M
