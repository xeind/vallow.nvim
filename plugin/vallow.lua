if vim.v.vim_did_enter == 0 then
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("VallowStartup", {}),
    once = true,
    callback = function()
      require("vallow").setup()
      require("vallow").prefetch()
    end,
  })
end

local function search()
  local results = require("vallow.panel").state.results
  if not results or results._loading then
    vim.notify("vallow: still analyzing, try again in a moment", vim.log.levels.WARN)
    return
  end
  require("vallow.picker").open(results)
end

-- :Vallow arguments: the section keys from config, plus these verbs.
local verbs = { "audit", "production", "refresh", "search" }

local function candidates()
  local list = vim.deepcopy(verbs)
  for key in pairs(require("vallow.config").get().sections or {}) do
    table.insert(list, key)
  end
  table.sort(list)
  return list
end

vim.api.nvim_create_user_command("Vallow", function(opts)
  local arg = vim.trim(opts.args or "")
  local verb, rest = arg:match("^(%S+)%s*(.*)$")
  if arg == "" then
    -- Plain :Vallow leaves audit mode and shows the normal run.
    local panel = require("vallow.panel")
    if panel.state.mode == "audit" then
      panel.normal()
    else
      require("vallow").toggle()
    end
  elseif verb == "audit" then
    require("vallow.panel").audit(rest)
  elseif arg == "refresh" then
    require("vallow").refresh()
  elseif arg == "search" then
    search()
  elseif arg == "production" then
    require("vallow.panel").toggle_production()
  elseif (require("vallow.config").get().sections or {})[arg] then
    require("vallow").open_section(arg)
  else
    vim.notify("vallow: unknown argument '" .. arg .. "'", vim.log.levels.WARN)
  end
end, {
  nargs = "*",
  complete = function(lead)
    return vim.tbl_filter(function(c)
      return c:find(lead, 1, true) == 1
    end, candidates())
  end,
  desc = "Toggle the vallow panel, or open a section: :Vallow health",
})

vim.api.nvim_create_user_command("VallowRefresh", function()
  require("vallow").refresh()
end, {})

vim.api.nvim_create_user_command(
  "VallowSearch",
  search,
  { desc = "Search vallow findings with snacks/telescope/fzf-lua" }
)

vim.api.nvim_create_user_command("VallowExport", function()
  require("vallow").export()
end, { desc = "Export vallow findings as markdown in a new buffer" })

vim.api.nvim_create_user_command("VallowSummary", function()
  require("vallow").summary()
end, { desc = "Show a compact findings summary float" })

vim.api.nvim_create_user_command("VallowInspect", function()
  require("vallow.inspect").open()
end, { desc = "Inspect the current file with fallow inspect" })

vim.api.nvim_create_user_command("VallowInstall", function(opts)
  local args = vim.split(vim.trim(opts.args or ""), "%s+")
  local binary = "fallow"
  if args[1] == "lsp" then
    binary = "fallow-lsp"
    table.remove(args, 1)
  end
  local version = args[1] ~= "" and args[1] or nil
  require("vallow.install").install({ binary = binary, version = version }, function(ok, msg)
    if not ok then
      vim.notify(msg, vim.log.levels.ERROR)
    end
  end)
end, {
  nargs = "*",
  complete = function(lead)
    return vim.tbl_filter(function(c)
      return c:find(lead, 1, true) == 1
    end, { "lsp" })
  end,
  desc = "Download the fallow binary: :VallowInstall [lsp] [version]",
})

vim.api.nvim_create_user_command("VallowUpdate", function()
  require("vallow.install").install({}, function(ok, msg)
    if not ok then
      vim.notify(msg, vim.log.levels.ERROR)
    end
  end)
end, { desc = "Download the latest fallow binary" })
