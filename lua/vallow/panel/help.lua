local M = {}

local SECTIONS = {
  {
    title = "Navigation",
    keys = {
      { key = "<CR>", desc = "jump to file (edit)" },
      { key = "o", desc = "jump: horizontal split" },
      { key = "v", desc = "jump: vertical split" },
      { key = "t", desc = "jump: new tab" },
      { key = "L / H", desc = "next / prev tab (section)" },
      { key = "]c / [c", desc = "next / prev section" },
    },
  },
  {
    title = "Folds",
    keys = {
      { key = "za / <Tab>", desc = "toggle fold" },
      { key = "zo", desc = "open fold" },
      { key = "zc", desc = "close fold" },
      { key = "zR", desc = "open all" },
      { key = "zM", desc = "close all" },
    },
  },
  {
    title = "Search",
    keys = {
      { key = "f", desc = "filter by file/name/category" },
      { key = "F", desc = "clear filter" },
      { key = "gf", desc = "open picker" },
    },
  },
  {
    title = "Actions",
    keys = {
      { key = "P", desc = "peek code in float" },
      { key = "K", desc = "detail / fix suggestions" },
      { key = "ga", desc = "LSP code action (fallow-lsp)" },
      { key = "%", desc = "filter: current file" },
      { key = "r", desc = "refresh" },
      { key = "Q", desc = "send to quickfix list" },
      { key = "y", desc = "yank path:line" },
      { key = "yn", desc = "yank finding name/symbol" },
      { key = "q", desc = "close panel" },
      { key = "?", desc = "this help" },
    },
  },
}

M.open = function()
  -- Build lines
  local lines = { "" }
  local key_col = 14 -- width reserved for key column

  for _, sec in ipairs(SECTIONS) do
    table.insert(lines, "  " .. sec.title)
    for _, entry in ipairs(sec.keys) do
      local pad = key_col - #entry.key
      table.insert(lines, string.format("  %s%s  %s", entry.key, string.rep(" ", math.max(1, pad)), entry.desc))
    end
    table.insert(lines, "")
  end

  local width = 44
  local height = #lines

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "vallow_help"

  -- Center in the editor
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Vallow Keybinds ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = false

  -- Highlights
  local ns = vim.api.nvim_create_namespace("vallow_help")
  for i, line in ipairs(lines) do
    local lnum = i - 1
    -- Section titles: bold/title highlight
    if line:match("^  %u") and not line:match("^  %S.*  ") then
      vim.api.nvim_buf_add_highlight(buf, ns, "Title", lnum, 2, -1)
    -- Key column: special highlight
    elseif line:match("^  %S") then
      local key_end = line:find("  %S", 3)
      if key_end then
        vim.api.nvim_buf_add_highlight(buf, ns, "Special", lnum, 2, key_end - 1)
        vim.api.nvim_buf_add_highlight(buf, ns, "Comment", lnum, key_end + 1, -1)
      end
    end
  end

  -- Close on any of these keys
  for _, key in ipairs({ "q", "?", "<Esc>", "<CR>" }) do
    vim.keymap.set("n", key, function()
      pcall(vim.api.nvim_win_close, win, true)
    end, { buffer = buf, nowait = true, silent = true })
  end
end

return M
