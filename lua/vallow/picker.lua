-- picker.lua: open all findings in telescope / fzf-lua / vim.ui.select
local M = {}

-- Flatten all findings into a list of entries for the picker
local function flatten(results)
  if not results or not results.findings then
    return {}
  end
  local entries = {}

  local LABEL = require("vallow.labels").label
  local cfg = require("vallow.config").get()

  -- Use _resolve_findings so "sources" categories (unused_members etc.) are merged
  local render = require("vallow.panel.render")
  for cat_key, cat_cfg in pairs(cfg.categories or {}) do
    local d = render._resolve_findings(cat_key, cat_cfg, results.findings)
    if d and d.items then
      local lbl = cat_cfg.label or LABEL[cat_key] or cat_key
      for _, item in ipairs(d.items) do
        local lnum = item.lnum or 1
        local name = item.name or ""
        local rel_path = item.relative_path or ""
        -- Show line number so entries from the same file are distinct
        local loc = rel_path ~= "" and (rel_path .. ":" .. lnum) or ""
        local display = string.format("%-18s  %-45s  %s", lbl, loc, name)
        table.insert(entries, {
          display = display,
          path = item.path,
          lnum = lnum,
          col = item.col or 0,
          cat = cat_key,
          label = lbl,
          name = name,
          rel_path = rel_path,
        })
      end
    end
  end

  -- Sort to match the panel tree: section order → category order → file → line
  local sec_order = {}
  for key, sec_cfg in pairs(cfg.sections or {}) do
    sec_order[key] = sec_cfg.order or 99
  end
  local cat_sort_key = {} -- cat_key → global sort int (sec_order * 100 + cat_order)
  for key, cat_cfg in pairs(cfg.categories or {}) do
    local s = sec_order[cat_cfg.section or ""] or 99
    cat_sort_key[key] = s * 100 + (cat_cfg.order or 99)
  end

  table.sort(entries, function(a, b)
    local ka = cat_sort_key[a.cat] or 9999
    local kb = cat_sort_key[b.cat] or 9999
    if ka ~= kb then
      return ka < kb
    end
    if a.rel_path ~= b.rel_path then
      return a.rel_path < b.rel_path
    end
    return (a.lnum or 0) < (b.lnum or 0)
  end)

  return entries
end

local function jump(entry)
  if not entry or not entry.path or entry.path == "" then
    return
  end
  local cur = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if win ~= cur and vim.bo[buf].filetype ~= "vallow" then
      vim.api.nvim_set_current_win(win)
      break
    end
  end
  local ok = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(entry.path))
  if not ok then
    return
  end
  if entry.lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, entry.lnum), math.max(0, entry.col or 0) })
    vim.cmd("normal! zz")
    vim.highlight.on_yank({ higroup = "Search", timeout = 250 })
  end
end

-- ── Telescope ────────────────────────────────────────────────────────
local function open_telescope(entries)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Vallow Findings",
      previewer = conf.file_previewer({}),
      finder = finders.new_table({
        results = entries,
        entry_maker = function(e)
          return {
            value = e,
            display = e.display,
            ordinal = e.cat .. " " .. e.rel_path .. " " .. e.name,
            -- These fields drive the file previewer to the right line:
            filename = e.path,
            lnum = e.lnum,
            col = e.col,
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
    })
    :find()
end

-- ── fzf-lua ──────────────────────────────────────────────────────────
local function open_fzf(entries)
  local fzf = require("fzf-lua")

  -- Format: "abs_path:lnum:col: display_text"
  -- fzf-lua's builtin previewer recognises this grep-output format and opens
  -- the file at the correct line. --with-nth hides the path prefix from the
  -- visible list while the previewer still reads the full original string.
  local items = {}
  for i, e in ipairs(entries) do
    items[i] = string.format("%s:%d:%d: %s", e.path or "", e.lnum or 1, (e.col or 0) + 1, e.display)
  end

  fzf.fzf_exec(items, {
    prompt = "Vallow> ",
    previewer = "builtin",
    fzf_opts = {
      ["--delimiter"] = ":",
      ["--with-nth"] = "4..", -- show only the display part in the list
    },
    actions = {
      ["default"] = function(selected)
        if not selected or not selected[1] then
          return
        end
        -- fzf returns the original full string; parse path and lnum back out
        local path, lnum_s = selected[1]:match("^([^:]+):(%d+):%d+:")
        if path then
          jump({ path = path, lnum = tonumber(lnum_s) or 1 })
        end
      end,
    },
  })
end

-- ── Snacks ───────────────────────────────────────────────────────────
local function open_snacks(entries)
  local items = {}
  for _, e in ipairs(entries) do
    table.insert(items, {
      text = e.display,
      file = e.path,
      pos = { e.lnum or 1, (e.col or 0) + 1 },
      _e = e,
    })
  end
  require("snacks").picker.pick({
    title = "Vallow Findings",
    items = items,
    preview = "file",
    confirm = function(picker, item)
      picker:close()
      if item then
        jump(item._e)
      end
    end,
  })
end

-- ── vim.ui.select fallback ───────────────────────────────────────────
local function open_select(entries)
  vim.ui.select(entries, {
    prompt = "Vallow findings",
    format_item = function(e)
      return e.display
    end,
  }, function(e)
    if e then
      jump(e)
    end
  end)
end

-- ── Public entry point ───────────────────────────────────────────────
M.open = function(results)
  local entries = flatten(results)
  if #entries == 0 then
    vim.notify("vallow: no findings to search", vim.log.levels.INFO)
    return
  end

  local ok_snacks, snacks = pcall(require, "snacks")
  if ok_snacks and snacks.picker then
    open_snacks(entries)
  elseif pcall(require, "telescope") then
    open_telescope(entries)
  elseif pcall(require, "fzf-lua") then
    open_fzf(entries)
  else
    open_select(entries)
  end
end

return M
