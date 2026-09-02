-- ignore.lua: write suppressions to .fallowrc.json, or insert the inline
-- comment fallow suggests.
local M = {}

M.config_path = function(root)
  return root .. "/.fallowrc.json"
end

local _empty_dict_mt = getmetatable(vim.empty_dict())

-- JSON with 2-space indent. Object keys are sorted, so an existing file comes
-- back with the same content in a stable order.
M.encode = function(value, indent)
  indent = indent or ""
  if type(value) ~= "table" then
    return vim.json.encode(value)
  end
  local pad = indent .. "  "
  if vim.tbl_isempty(value) then
    return getmetatable(value) == _empty_dict_mt and "{}" or "[]"
  end
  local parts = {}
  if vim.islist(value) then
    for _, v in ipairs(value) do
      table.insert(parts, pad .. M.encode(v, pad))
    end
    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
  end
  local keys = vim.tbl_keys(value)
  table.sort(keys)
  for _, k in ipairs(keys) do
    table.insert(parts, pad .. vim.json.encode(tostring(k)) .. ": " .. M.encode(value[k], pad))
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

M.read = function(path)
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok or type(decoded) ~= "table" then
    return nil, "cannot parse " .. path
  end
  return decoded
end

-- Ask, then rewrite the config with `mutate` applied. Returns true on write.
M._write = function(root, summary, mutate)
  local path = M.config_path(root)
  local existing, err = M.read(path)
  if not existing then
    vim.notify("vallow: " .. err, vim.log.levels.ERROR)
    return false
  end
  local verb = vim.fn.filereadable(path) == 1 and "Update" or "Create"
  if vim.fn.confirm(("%s %s?\n%s"):format(verb, path, summary), "&Yes\n&No", 2) ~= 1 then
    return false
  end
  mutate(existing)
  vim.fn.writefile(vim.split(M.encode(existing), "\n", { plain = true }), path)
  vim.notify("vallow: " .. summary .. " → " .. path, vim.log.levels.INFO)
  return true
end

-- ignoreFindings: project-root-relative globs whose findings are hidden.
M.add_finding = function(root, glob)
  return M._write(root, ('Add "%s" to ignoreFindings'):format(glob), function(cfg)
    cfg.ignoreFindings = cfg.ignoreFindings or {}
    if not vim.tbl_contains(cfg.ignoreFindings, glob) then
      table.insert(cfg.ignoreFindings, glob)
    end
  end)
end

-- ignoreExports: [{ file = <glob>, exports = { <name>, ... } }]
M.add_export = function(root, file, name)
  return M._write(root, ('Add "%s" in %s to ignoreExports'):format(name, file), function(cfg)
    cfg.ignoreExports = cfg.ignoreExports or {}
    for _, rule in ipairs(cfg.ignoreExports) do
      if type(rule) == "table" and rule.file == file then
        rule.exports = rule.exports or {}
        if not vim.tbl_contains(rule.exports, name) then
          table.insert(rule.exports, name)
        end
        return
      end
    end
    table.insert(cfg.ignoreExports, { file = file, exports = { name } })
  end)
end

-- Insert fallow's own suppression comment and save the file.
-- `action` is the finding action carrying `.comment`.
M.insert_comment = function(path, lnum, action)
  local comment = action.comment
  if not comment or comment == "" then
    return false
  end
  local file_level = action.type == "suppress-file"
  local at = file_level and 1 or math.max(1, lnum or 1)
  if vim.fn.confirm(("Insert %q above %s:%d?"):format(comment, path, at), "&Yes\n&No", 2) ~= 1 then
    return false
  end
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  local target = vim.api.nvim_buf_get_lines(buf, at - 1, at, false)[1] or ""
  local indent = file_level and "" or (target:match("^%s*") or "")
  vim.api.nvim_buf_set_lines(buf, at - 1, at - 1, false, { indent .. comment })
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent write")
  end)
  vim.notify("vallow: suppression added to " .. path, vim.log.levels.INFO)
  return true
end

return M
