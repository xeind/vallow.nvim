-- explain.lua: `fallow explain <issue-type>`, cached for the session.
local M = {}

-- Panel category / findings key → fallow issue type. Hotspots, refactoring
-- targets and raw style values have no explanation of their own.
M.ISSUE_TYPE = {
  unused_exports = "unused-export",
  unused_types = "unused-type",
  unused_files = "unused-file",
  unused_enum_members = "unused-enum-member",
  unused_class_members = "unused-class-member",
  unused_members = "unused-class-member",
  unused_deps = "unused-dependency",
  unused_dev_deps = "unused-dependency",
  unused_optional_deps = "unused-dependency",
  unused_all_deps = "unused-dependency",
  unlisted_deps = "unlisted-dependency",
  unresolved_imports = "unresolved-import",
  duplicate_exports = "duplicate-export",
  circular_deps = "circular-dependency",
  boundary_violations = "boundary-violation",
  clone_groups = "code-duplication",
  health_complexity = "complexity",
  dev_dep_in_prod = "dev-dependency-in-production",
  css_token_drift = "css-token-drift",
  stale_suppressions = "stale-suppression",
}

M.issue_type = function(key)
  return key and M.ISSUE_TYPE[key] or nil
end

M._cache = {}

-- callback(data, err) with fallow's explain envelope.
M.get = function(issue_type, callback)
  if M._cache[issue_type] then
    callback(M._cache[issue_type])
    return
  end
  local runner = require("vallow.runner")
  local root = runner.find_root() or vim.fn.getcwd()
  local bin = runner.resolve_cmd(root)
  if not bin then
    callback(nil, require("vallow.install").instructions())
    return
  end
  runner._job({ bin, "explain", issue_type, "--format", "json", "--quiet" }, root, function(ok, data)
    vim.schedule(function()
      if ok and type(data) == "table" and data.id then
        M._cache[issue_type] = data
        callback(data)
      else
        callback(nil, "vallow: cannot explain " .. issue_type .. ": " .. tostring(data))
      end
    end)
  end)
end

-- Show the explanation for a category or findings key in a float.
M.open = function(key)
  local issue_type = M.issue_type(key)
  if not issue_type then
    vim.notify("vallow: fallow has no explanation for " .. tostring(key), vim.log.levels.INFO)
    return
  end
  M.get(issue_type, function(data, err)
    if not data then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end
    M._show(data)
  end)
end

M._show = function(data)
  local float = require("vallow.panel.float")
  local wrap = require("vallow.panel.render")._wrap
  local b = float.builder()
  local width = math.min(76, vim.o.columns - 12)

  b.push("")
  b.push("  " .. (data.name or data.id or ""), "VallowSection")
  b.push("  " .. (data.id or ""), "VallowKind")
  if data.summary and data.summary ~= "" then
    b.push("")
    b.push("  " .. data.summary, "VallowName")
  end
  local function paragraph(title, text)
    if not text or text == "" then
      return
    end
    b.push("")
    b.push("  " .. title, "VallowSection")
    for _, seg in ipairs(wrap(text, width - 4)) do
      b.push("    " .. seg, "Comment")
    end
  end
  paragraph("Why it matters", data.rationale)
  paragraph("Example", data.example)
  paragraph("How to fix", data.how_to_fix)
  if data.docs and data.docs ~= "" then
    b.push("")
    b.push("  " .. data.docs, "VallowPath")
  end
  b.push("")
  float.open({ title = "Vallow Explain", lines = b.lines, hls = b.hls })
end

return M
