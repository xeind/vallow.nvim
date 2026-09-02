-- cache.lua: persist the last normalized results per project root so the
-- panel can show something the moment it opens, while a fresh run proceeds.
local M = {}

local function dir()
  return vim.fn.stdpath("cache") .. "/vallow"
end

-- find_root may return a relative path ("."), so resolve before hashing.
M.path = function(root)
  if not root or root == "" then
    return nil
  end
  local abs = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
  return dir() .. "/" .. vim.fn.sha256(abs) .. ".json"
end

M.save = function(results)
  local cfg = require("vallow.config").get()
  if cfg.cache == false then
    return
  end
  if not results or results.error or results._loading or not results.findings then
    return
  end
  local path = M.path(results.repo_root)
  if not path then
    return
  end
  local ok, encoded = pcall(vim.json.encode, results)
  if not ok then
    return
  end
  vim.fn.mkdir(dir(), "p")
  pcall(vim.fn.writefile, { encoded }, path)
end

-- Returns the cached results for a root, marked stale, or nil.
M.load = function(root)
  local cfg = require("vallow.config").get()
  if cfg.cache == false then
    return nil
  end
  local path = M.path(root)
  if not path or vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), ""))
  if not ok or type(decoded) ~= "table" or type(decoded.findings) ~= "table" then
    return nil
  end
  decoded.stale = true
  return decoded
end

return M
