local M = {}

-- Create the panel split buffer + window. Returns { buf, win }.
M.create = function()
  local cfg = require("vallow.config").get().window
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_name(buf, "vallow://panel")

  local win = M._open_split(cfg, buf)

  vim.wo[win].number = false
  vim.wo[win].relativenumber = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].wrap = false
  vim.wo[win].list = false
  vim.wo[win].winfixheight = cfg.position == "bottom" or cfg.position == "top"
  vim.wo[win].winfixwidth = cfg.position == "left" or cfg.position == "right"
  vim.wo[win].cursorline = true
  vim.wo[win].scrolloff = 3

  vim.bo[buf].filetype = "vallow"

  return { buf = buf, win = win }
end

M._open_split = function(cfg, buf)
  local pos = cfg.position or "bottom"
  local size = math.max(0.1, math.min(0.9, cfg.size or 0.35))

  local split_cmd
  if pos == "top" then
    local height = math.floor(vim.o.lines * size)
    split_cmd = "topleft " .. height .. "split"
  elseif pos == "right" then
    local width = math.floor(vim.o.columns * size)
    split_cmd = "botright " .. width .. "vsplit"
  elseif pos == "left" then
    local width = math.floor(vim.o.columns * size)
    split_cmd = "topleft " .. width .. "vsplit"
  else
    -- "bottom" or any unrecognised value falls back to bottom split
    local height = math.floor(vim.o.lines * size)
    split_cmd = "botright " .. height .. "split"
  end

  vim.cmd(split_cmd)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  return win
end

return M
