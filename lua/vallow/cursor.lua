-- cursor.lua: act on the vallow finding under the cursor in a source buffer,
-- and move between vallow diagnostics. Works without the panel open.
local M = {}

-- Findings on the cursor line, read back from the diagnostics vallow set.
-- Each entry: { category = key, item = finding, message = text }.
M.findings = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local list = {}
  for _, d in ipairs(vim.diagnostic.get(bufnr, { namespace = require("vallow.diagnostics").ns, lnum = row })) do
    local data = d.user_data and d.user_data.vallow
    if data and data.item then
      table.insert(list, { category = data.category, item = data.item, message = d.message })
    end
  end
  return list
end

-- The choices for one finding. prefix names the finding when the line has several.
local function choices_for(f, prefix)
  local actions = require("vallow.panel.actions")
  local list = {
    {
      label = prefix .. "Ignore…",
      run = function()
        actions.ignore_item(f.item, f.category)
      end,
    },
  }
  if actions.traceable(f.item, f.category) then
    table.insert(list, {
      label = prefix .. "Trace",
      run = function()
        actions.trace_item(f.item, f.category)
      end,
    })
  end
  if require("vallow.explain").issue_type(f.category) then
    table.insert(list, {
      label = prefix .. "Explain",
      run = function()
        require("vallow.explain").open(f.category)
      end,
    })
  end
  return list
end

-- :Vallow action — pick ignore, trace or explain for the finding under the cursor.
M.action = function()
  local found = M.findings()
  if #found == 0 then
    vim.notify("vallow: no finding on this line", vim.log.levels.INFO)
    return
  end
  local choices = {}
  for _, f in ipairs(found) do
    local prefix = #found > 1 and (f.message .. " · ") or ""
    vim.list_extend(choices, choices_for(f, prefix))
  end
  vim.ui.select(choices, {
    prompt = "vallow: " .. (#found == 1 and found[1].message or "findings on this line"),
    format_item = function(choice)
      return choice.label
    end,
  }, function(choice)
    if choice then
      choice.run()
    end
  end)
end

-- Move to the next (direction 1) or previous (-1) vallow diagnostic,
-- skipping LSP and linter diagnostics. Takes a count.
M.jump = function(direction, count)
  count = (count or vim.v.count1) * direction
  local ns = require("vallow.diagnostics").ns
  if vim.diagnostic.jump then
    vim.diagnostic.jump({ count = count, namespace = ns, float = true })
    return
  end
  -- Neovim 0.10 has no vim.diagnostic.jump.
  local step = direction > 0 and vim.diagnostic.goto_next or vim.diagnostic.goto_prev
  for _ = 1, math.abs(count) do
    step({ namespace = ns, float = true })
  end
end

return M
