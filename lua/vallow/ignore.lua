-- ignore.lua: write suppressions to .fallowrc.json, or insert the inline
-- comment fallow suggests.
local M = {}

M.config_path = function(root)
  local jsonc = root .. "/.fallowrc.jsonc"
  if vim.fn.filereadable(jsonc) == 1 then
    return jsonc
  end
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

-- ── Text editing ─────────────────────────────────────────────────────
-- An existing config is edited as text, never decoded and re-encoded: that
-- would sort the keys and drop the comments of a .jsonc file.

-- Index of the bracket closing the one at `open`. Strings and comments are
-- skipped, so a brace inside either does not count. nil when unbalanced.
M._match = function(text, open)
  local pair = { ["{"] = "}", ["["] = "]" }
  local closer = pair[text:sub(open, open)]
  if not closer then
    return nil
  end
  local depth, i, n = 0, open, #text
  while i <= n do
    local c = text:sub(i, i)
    if c == '"' then
      i = i + 1
      while i <= n do
        local d = text:sub(i, i)
        if d == "\\" then
          i = i + 1
        elseif d == '"' then
          break
        end
        i = i + 1
      end
    elseif c == "/" and text:sub(i + 1, i + 1) == "/" then
      i = text:find("\n", i) or n
    elseif c == "/" and text:sub(i + 1, i + 1) == "*" then
      i = (text:find("*/", i + 2, true) or n) + 1
    elseif c == "{" or c == "[" then
      depth = depth + 1
    elseif c == "}" or c == "]" then
      depth = depth - 1
      if depth == 0 then
        return c == closer and i or nil
      end
    end
    i = i + 1
  end
  return nil
end

-- Index of the "[" of the array member `key`, searched from `from`.
M._array_at = function(text, key, from)
  local _, stop = text:find('"' .. key .. '"%s*:%s*%[', from or 1)
  return stop
end

-- Indent of the line holding index `at`.
local function _indent_of(text, at)
  local bol = (text:sub(1, at):find("[^\n]*$")) or at
  return text:sub(bol, at):match("^%s*") or ""
end

-- Put `entry` (JSON text) last in the array whose "[" is at `open`.
M._insert_into = function(text, open, entry)
  local close = M._match(text, open)
  if not close then
    return nil
  end
  local body = text:sub(open + 1, close - 1)
  -- Already listed: leave the file untouched.
  if body:find(entry, 1, true) then
    return text
  end
  local indent = _indent_of(text, close) .. "  "
  if body:match("^%s*$") then
    return text:sub(1, open) .. "\n" .. indent .. entry .. "\n" .. _indent_of(text, close) .. text:sub(close)
  end
  local last = #body - (#body:match("%s*$"))
  local sep = body:sub(last, last) == "," and "" or ","
  local at = open + last
  -- An array written on one line stays on one line.
  local break_line = body:find("\n") and ("\n" .. indent) or " "
  return text:sub(1, at) .. sep .. break_line .. entry .. text:sub(at + 1)
end

-- Put `"key": [entry]` last in the top-level object.
M._insert_key = function(text, key, entry)
  local open = text:find("{")
  local close = open and M._match(text, open)
  if not close then
    return nil
  end
  local body = text:sub(open + 1, close - 1)
  local indent = _indent_of(text, close) .. "  "
  local member = ('"%s": [\n%s  %s\n%s]'):format(key, indent, entry, indent)
  if body:match("^%s*$") then
    return text:sub(1, open) .. "\n" .. indent .. member .. "\n" .. _indent_of(text, close) .. text:sub(close)
  end
  local last = #body - (#body:match("%s*$"))
  local sep = body:sub(last, last) == "," and "" or ","
  local at = open + last
  return text:sub(1, at) .. sep .. "\n" .. indent .. member .. text:sub(at + 1)
end

-- Add `entry` to the top-level array `key`, creating the key when missing.
M.add_to_array = function(text, key, entry)
  local open = M._array_at(text, key)
  if open then
    return M._insert_into(text, open, entry)
  end
  return M._insert_key(text, key, entry)
end

-- Add `name` to the exports of the ignoreExports rule for `file`, adding the
-- rule, and the key, when either is missing.
M.add_export_text = function(text, file, name)
  local rules = M._array_at(text, "ignoreExports")
  local rule = ('{ "file": %s, "exports": [%s] }'):format(vim.json.encode(file), vim.json.encode(name))
  if not rules then
    return M._insert_key(text, "ignoreExports", rule)
  end
  local close = M._match(text, rules)
  if not close then
    return nil
  end
  local _, at = text:find('"file"%s*:%s*' .. vim.pesc(vim.json.encode(file)), rules)
  if at and at < close then
    local exports = M._array_at(text, "exports", at)
    if exports and exports < close then
      return M._insert_into(text, exports, vim.json.encode(name))
    end
  end
  return M._insert_into(text, rules, rule)
end

-- Ask, then write `edit(text)` back. `edit` gets the file as text, or nil when
-- there is no config yet, and returns the new text. Returns true on write.
M._write = function(root, summary, edit)
  local path = M.config_path(root)
  local exists = vim.fn.filereadable(path) == 1
  local text = exists and table.concat(vim.fn.readfile(path), "\n") or nil
  local verb = exists and "Update" or "Create"
  if vim.fn.confirm(("%s %s?\n%s"):format(verb, path, summary), "&Yes\n&No", 2) ~= 1 then
    return false
  end
  local out = edit(text)
  if not out then
    vim.notify("vallow: cannot find where to insert in " .. path, vim.log.levels.ERROR)
    return false
  end
  vim.fn.writefile(vim.split(out, "\n", { plain = true }), path)
  vim.notify("vallow: " .. summary .. " → " .. path, vim.log.levels.INFO)
  return true
end

-- ignoreFindings: project-root-relative globs whose findings are hidden.
M.add_finding = function(root, glob)
  return M._write(root, ('Add "%s" to ignoreFindings'):format(glob), function(text)
    if not text then
      return M.encode({ ignoreFindings = { glob } })
    end
    return M.add_to_array(text, "ignoreFindings", vim.json.encode(glob))
  end)
end

-- ignoreExports: [{ file = <glob>, exports = { <name>, ... } }]
M.add_export = function(root, file, name)
  return M._write(root, ('Add "%s" in %s to ignoreExports'):format(name, file), function(text)
    if not text then
      return M.encode({ ignoreExports = { { file = file, exports = { name } } } })
    end
    return M.add_export_text(text, file, name)
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
