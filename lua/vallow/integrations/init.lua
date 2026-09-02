-- integrations/init.lua: shared state for the file-explorer decorations.
-- Every explorer module asks here whether a path is an unused file.
local M = {}

-- Cache the path set per results table, so a decorator called once per node
-- does not rebuild it every time.
local cached_for, cached_set = nil, {}

M.enabled = function(name)
  local cfg = require("vallow.config").get().integrations or {}
  return cfg[name] ~= false
end

-- Absolute paths of every file in the unused_files bucket.
M.unused_files = function()
  local results = require("vallow.panel").state.results
  if results == cached_for then
    return cached_set
  end
  local set = {}
  local bucket = results and results.findings and results.findings.unused_files
  for _, item in ipairs(bucket and bucket.items or {}) do
    if item.path and item.path ~= "" then
      set[item.path] = true
    end
  end
  cached_for, cached_set = results, set
  return set
end

M.is_unused = function(path)
  if not path or path == "" then
    return false
  end
  return M.unused_files()[path] == true
end

-- Redraw the open explorers. Called after every run; each call is guarded
-- because none of these plugins is a dependency.
M.refresh = function()
  cached_for, cached_set = nil, {}

  if M.enabled("nvim_tree") then
    pcall(function()
      local api = require("nvim-tree.api")
      if api.tree.is_visible() then
        api.tree.reload()
      end
    end)
  end

  if M.enabled("neo_tree") then
    pcall(function()
      require("neo-tree.sources.manager").refresh("filesystem")
    end)
  end

  if M.enabled("oil") then
    pcall(function()
      if vim.bo.filetype == "oil" then
        require("oil.actions").refresh.callback()
      end
    end)
  end
end

return M
