-- manifest.lua: end-of-line virtual text on the dependency lines of an open
-- package.json — unused, type-only, test-only, dev dep in prod, unlisted.
local M = {}

local ns = vim.api.nvim_create_namespace("vallow_manifest")

local BLOCKS = {
  dependencies = true,
  devDependencies = true,
  optionalDependencies = true,
  peerDependencies = true,
}

-- findings key → label, the package.json block it belongs to, highlight
local OVERLAY = {
  unused_deps = { text = "unused", block = "dependencies", hl = "VallowSevWarn" },
  unused_dev_deps = { text = "unused (dev)", block = "devDependencies", hl = "VallowSevHint" },
  unused_optional_deps = { text = "unused (optional)", block = "optionalDependencies", hl = "VallowSevHint" },
  type_only_deps = { text = "type-only", block = "dependencies", hl = "VallowSevHint" },
  test_only_deps = { text = "test-only", block = "dependencies", hl = "VallowSevHint" },
  dev_dep_in_prod = { text = "dev dep in prod", block = "dependencies", hl = "VallowSevError" },
}

-- Map every dependency block of a package.json to its member lines and its
-- closing brace. Line numbers are 1-based.
--   { dependencies = { names = { lodash = 7 }, close = 8 } }
M._scan = function(lines)
  local blocks = {}
  local current, indent = nil, nil
  for i, line in ipairs(lines) do
    if current then
      if line:match("^" .. indent .. "}") then
        blocks[current].close = i
        current, indent = nil, nil
      else
        local name = line:match('^%s*"([^"]+)"%s*:')
        if name then
          blocks[current].names[name] = i
        end
      end
    else
      local ws, key = line:match('^(%s*)"([^"]+)"%s*:%s*{')
      if key and BLOCKS[key] then
        current, indent = key, ws
        blocks[key] = { names = {}, close = nil }
      end
    end
  end
  return blocks
end

M.clear = function(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

-- Draw the overlay for one package.json buffer.
M.apply_buf = function(bufnr, findings)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  M.clear(bufnr)
  if not findings or require("vallow.config").get().manifest_overlay == false then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if vim.fn.fnamemodify(path, ":t") ~= "package.json" then
    return
  end
  local root = require("vallow.panel").state.results
  root = root and root.repo_root
  if root and root ~= "" and not path:find(root, 1, true) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = M._scan(lines)
  local marks = {} -- lnum → { { text, hl }, ... }

  local function mark(lnum, text, hl)
    if not lnum then
      return
    end
    marks[lnum] = marks[lnum] or {}
    table.insert(marks[lnum], { text, hl })
  end

  for key, spec in pairs(OVERLAY) do
    local bucket = findings[key]
    for _, item in ipairs(bucket and bucket.items or {}) do
      if not item.path or item.path == "" or item.path == path then
        local name = item.name or ""
        -- Look in the block the finding belongs to, then anywhere else: a
        -- package may sit in a section fallow did not name.
        local lnum = (blocks[spec.block] or { names = {} }).names[name]
        if not lnum then
          for _, block in pairs(blocks) do
            lnum = lnum or block.names[name]
          end
        end
        mark(lnum or item.lnum, spec.text, spec.hl)
      end
    end
  end

  -- Unlisted packages have no line of their own: name them all on the closing
  -- brace of the dependencies block.
  local unlisted = {}
  for _, item in ipairs((findings.unlisted_deps or {}).items or {}) do
    if item.name and item.name ~= "" then
      table.insert(unlisted, item.name)
    end
  end
  if #unlisted > 0 then
    local close = (blocks.dependencies or {}).close
    if close then
      table.sort(unlisted)
      mark(close, "unlisted: " .. table.concat(unlisted, ", "), "VallowSevWarn")
    end
  end

  local last = #lines
  for lnum, chunks in pairs(marks) do
    if lnum >= 1 and lnum <= last then
      local virt = {}
      for i, chunk in ipairs(chunks) do
        table.insert(virt, { (i == 1 and "  " or " · ") .. chunk[1], chunk[2] })
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum - 1, 0, {
        virt_text = virt,
        virt_text_pos = "eol",
      })
    end
  end
end

-- Redraw every open package.json buffer.
M.apply = function(findings)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.apply_buf(bufnr, findings)
    end
  end
end

return M
