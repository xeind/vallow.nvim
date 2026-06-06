-- picker.lua: open all findings in telescope / fzf-lua / vim.ui.select
local M = {}

-- Flatten all findings into a list of entries for the picker
local function flatten(results)
  if not results or not results.findings then return {} end
  local entries = {}

  local LABEL = require("vallow.labels").label

  for cat_key, bucket in pairs(results.findings) do
    if type(bucket) == "table" and bucket.items then
      local lbl = LABEL[cat_key] or cat_key
      for _, item in ipairs(bucket.items) do
        local display = string.format("%-18s  %-40s  %s",
          lbl,
          item.relative_path or "",
          item.name or "")
        table.insert(entries, {
          display  = display,
          path     = item.path,
          lnum     = item.lnum or 1,
          col      = item.col  or 0,
          cat      = cat_key,
          label    = lbl,
          name     = item.name or "",
          rel_path = item.relative_path or "",
        })
      end
    end
  end

  table.sort(entries, function(a, b)
    if a.cat ~= b.cat then return a.cat < b.cat end
    return (a.rel_path or "") < (b.rel_path or "")
  end)

  return entries
end

local function jump(entry)
  if not entry or not entry.path or entry.path == "" then return end
  -- Jump to the previous (non-vallow) window
  local cur = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if win ~= cur and vim.bo[buf].filetype ~= "vallow" then
      vim.api.nvim_set_current_win(win)
      break
    end
  end
  local ok = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(entry.path))
  if not ok then return end
  if entry.lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, entry.lnum), math.max(0, entry.col or 0) })
    vim.cmd("normal! zz")
    vim.highlight.on_yank({ higroup = "Search", timeout = 250 })
  end
end

-- ── Telescope ────────────────────────────────────────────────────────
local function open_telescope(entries)
  local pickers     = require("telescope.pickers")
  local finders     = require("telescope.finders")
  local conf        = require("telescope.config").values
  local actions     = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Vallow Findings",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(e)
        return {
          value   = e,
          display = e.display,
          ordinal = e.cat .. " " .. e.rel_path .. " " .. e.name,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        jump(action_state.get_selected_entry().value)
      end)
      return true
    end,
  }):find()
end

-- ── fzf-lua ──────────────────────────────────────────────────────────
local function open_fzf(entries)
  local fzf = require("fzf-lua")
  local items = {}
  local map   = {}
  for _, e in ipairs(entries) do
    local key = e.display
    items[#items + 1] = key
    map[key] = e
  end
  fzf.fzf_exec(items, {
    prompt  = "Vallow> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then jump(map[selected[1]]) end
      end,
    },
  })
end

-- ── vim.ui.select fallback ───────────────────────────────────────────
local function open_select(entries)
  vim.ui.select(entries, {
    prompt    = "Vallow findings",
    format_item = function(e) return e.display end,
  }, function(e)
    if e then jump(e) end
  end)
end

-- ── Public entry point ───────────────────────────────────────────────
M.open = function(results)
  local entries = flatten(results)
  if #entries == 0 then
    vim.notify("vallow: no findings to search", vim.log.levels.INFO)
    return
  end

  if pcall(require, "telescope") then
    open_telescope(entries)
  elseif pcall(require, "fzf-lua") then
    open_fzf(entries)
  else
    open_select(entries)
  end
end

return M
