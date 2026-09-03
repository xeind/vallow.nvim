-- fix.lua: preview `fallow fix --dry-run`, apply it only after a confirm.
local M = {}

local BASE = { "fix", "--format", "json", "--quiet", "--no-create-config" }

local TYPE_LABEL = {
  remove_export = "remove export",
  remove_dependency = "remove dependency",
  remove_enum_member = "remove enum member",
}

-- One fix entry → { file = abs path, lnum = number|nil, text = string }
M._entry = function(fix, root)
  local label = TYPE_LABEL[fix.type] or tostring(fix.type or "fix"):gsub("_", " ")
  local file = fix.file or fix.path or ""
  if file ~= "" and file:sub(1, 1) ~= "/" then
    file = root .. "/" .. file
  end
  local what = fix.name or fix.package or fix.member or ""
  if fix.location and fix.location ~= "" then
    what = what .. " (" .. fix.location .. ")"
  end
  return { file = file, lnum = fix.line, text = label .. "  " .. what }
end

-- Float body for a dry run: fixes grouped by file, newest counts last.
-- Returns the builder and the number of fixes.
M._lines = function(data, root)
  local b = require("vallow.panel.float").builder()
  local order, by_file, total = {}, {}, 0
  for _, fix in ipairs(data.fixes or {}) do
    if type(fix) == "table" then
      local e = M._entry(fix, root)
      if not by_file[e.file] then
        by_file[e.file] = {}
        table.insert(order, e.file)
      end
      table.insert(by_file[e.file], e)
      total = total + 1
    end
  end

  if total == 0 then
    b.push("  Nothing to fix.", "Comment")
    return b, 0
  end

  b.push("")
  for _, file in ipairs(order) do
    local rel = file:gsub("^" .. vim.pesc(root) .. "/", "")
    b.push("  " .. (rel ~= "" and rel or "(project)"), "VallowPath")
    for _, e in ipairs(by_file[file]) do
      local where = e.lnum and ("%4d  "):format(e.lnum) or "   -  "
      b.push("    " .. where .. e.text, "VallowName", e.file ~= "" and { path = e.file, lnum = e.lnum } or nil)
    end
    b.push("")
  end
  b.push(("  %d fix%s · fallow rewrites these files"):format(total, total == 1 and "" or "es"), "VallowFooter")
  b.push("")
  return b, total
end

-- Reasons never to apply, even when fallow exited 0.
M._blockers = function(data)
  local out = {}
  local ta = data._meta and data._meta.type_aware
  for _, w in ipairs(ta and ta.warnings or {}) do
    local text = tostring(w)
    if text:lower():find("tim") then
      table.insert(out, "type-aware: " .. text)
    end
  end
  return out
end

-- Preview the fixes, then ask. No confirm, no write.
M.open = function()
  local runner = require("vallow.runner")
  local root = runner.find_root()
  if not root then
    vim.notify("vallow: no JS/TS project here", vim.log.levels.WARN)
    return
  end
  local bin = runner.resolve_cmd(root)
  if not bin then
    vim.notify(require("vallow.install").instructions(), vim.log.levels.ERROR)
    return
  end

  local cmd = { bin }
  vim.list_extend(cmd, BASE)
  table.insert(cmd, "--dry-run")
  runner._job(cmd, root, function(ok, data)
    vim.schedule(function()
      if not ok or type(data) ~= "table" then
        vim.notify("vallow: fallow fix failed — " .. tostring(data), vim.log.levels.ERROR)
        return
      end
      local blockers = M._blockers(data)
      if #blockers > 0 then
        require("vallow.panel.float").open({
          title = "Vallow Fix — not applied",
          lines = vim.list_extend({ "" }, blockers),
        })
        vim.notify("vallow: fallow did not finish its type-aware pass; nothing applied", vim.log.levels.WARN)
        return
      end

      local b, total = M._lines(data, root)
      require("vallow.panel.float").open({
        title = "Vallow Fix (dry run)",
        lines = b.lines,
        hls = b.hls,
        targets = b.targets,
      })
      if total == 0 then
        return
      end
      local prompt = ("Apply %d fix%s? Files are rewritten on disk."):format(total, total == 1 and "" or "es")
      if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
        return
      end
      M._apply(bin, root)
    end)
  end)
end

-- Run the real fix. Only ever called from a confirmed M.open().
M._apply = function(bin, root)
  local cmd = { bin }
  vim.list_extend(cmd, BASE)
  table.insert(cmd, "--yes")
  require("vallow.runner")._job(cmd, root, function(ok, data)
    vim.schedule(function()
      if not ok or type(data) ~= "table" then
        vim.notify("vallow: fallow fix failed — " .. tostring(data), vim.log.levels.ERROR)
        return
      end
      local fixed = data.total_fixed or 0
      local skipped = data.skipped or 0
      vim.notify(
        ("vallow: %d fix%s applied%s"):format(
          fixed,
          fixed == 1 and "" or "es",
          skipped > 0 and (", " .. skipped .. " skipped") or ""
        ),
        vim.log.levels.INFO
      )
      vim.cmd("checktime")
      local panel = require("vallow.panel")
      if panel.state.mode == "audit" and panel._is_open() then
        panel.refresh()
      else
        panel._bg_refresh()
      end
    end)
  end)
end

return M
