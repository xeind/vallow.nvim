-- inspect.lua: `fallow inspect --file <path>` rendered in a float.
local M = {}

-- Project-root-relative path for `path`, or nil when it is outside the root.
M._rel = function(root, path)
  if not path or path == "" then
    return nil
  end
  if path:sub(1, 1) ~= "/" then
    return path
  end
  local rel = path:gsub("^" .. vim.pesc(root) .. "/", "")
  return rel ~= path and rel or nil
end

-- `path` may be absolute or root-relative; defaults to the current buffer.
M.open = function(path)
  local runner = require("vallow.runner")
  local root = runner.find_root()
  if not root then
    vim.notify("vallow: no JS/TS project here", vim.log.levels.WARN)
    return
  end
  local rel = M._rel(root, path or vim.api.nvim_buf_get_name(0))
  if not rel then
    vim.notify("vallow: no file to inspect in this project", vim.log.levels.WARN)
    return
  end
  local bin = runner.resolve_cmd(root)
  if not bin then
    vim.notify(require("vallow.install").instructions(), vim.log.levels.ERROR)
    return
  end

  vim.notify("vallow: inspecting " .. rel .. "…", vim.log.levels.INFO)
  runner._job({ bin, "inspect", "--file", rel, "--format", "json", "--quiet" }, root, function(ok, data)
    vim.schedule(function()
      if not ok or type(data) ~= "table" then
        vim.notify("vallow: inspect failed: " .. tostring(data), vim.log.levels.ERROR)
        return
      end
      M._show(data, root, rel)
    end)
  end)
end

M._show = function(raw, root, rel)
  local float = require("vallow.panel.float")
  local b = float.builder()
  local evidence = raw.evidence or {}
  local function abs(p)
    if not p or p == "" then
      return nil
    end
    return p:sub(1, 1) == "/" and p or (root .. "/" .. p)
  end

  b.push("")

  -- Identity
  local id = raw.identity or {}
  b.push("  " .. rel, "VallowPath", { path = abs(rel), lnum = 1 })
  local facts = {}
  table.insert(facts, id.is_reachable and "reachable" or "unreachable")
  if id.is_entry_point then
    table.insert(facts, "entry point")
  end
  table.insert(facts, (id.export_count or 0) .. " exports")
  table.insert(facts, (id.import_count or 0) .. " imports")
  table.insert(facts, (id.imported_by_count or 0) .. " importers")
  b.push("  " .. table.concat(facts, " · "), "VallowKind")

  -- Exports and importers come from the file trace.
  local trace = (evidence.trace_file or {}).data or {}
  if #(trace.exports or {}) > 0 then
    b.push("")
    b.push("  Exports", "VallowSection")
    for _, e in ipairs(trace.exports) do
      local kind = e.is_type_only and "type" or "value"
      local refs = (e.reference_count or 0) .. " ref" .. ((e.reference_count == 1) and "" or "s")
      b.push(string.format("    %-28s %-6s %s", e.name or "", kind, refs), "VallowName")
    end
  end

  if #(trace.imported_by or {}) > 0 then
    b.push("")
    b.push("  Imported by", "VallowSection")
    for _, p in ipairs(trace.imported_by) do
      b.push("    " .. p, "VallowPath", { path = abs(p), lnum = 1 })
    end
  end

  -- Findings: reuse the normalizer so labels and fields match the panel.
  local runner = require("vallow.runner")
  local normalized = runner._normalize({
    kind = "combined",
    dead_code = (evidence.dead_code or {}).data,
    duplication = (evidence.duplication or {}).data,
    health = (evidence.complexity or {}).data,
  }, root)
  local LABEL = require("vallow.labels").label
  local keys = vim.tbl_keys(normalized.findings)
  table.sort(keys)
  local finding_lines = {}
  for _, key in ipairs(keys) do
    local bucket = normalized.findings[key]
    if type(bucket) == "table" and bucket.items then
      for _, item in ipairs(bucket.items) do
        local text = string.format("    %-22s %s", LABEL[key] or key, item.name or item.relative_path or "")
        if item.lnum then
          text = text .. ":" .. item.lnum
        end
        table.insert(finding_lines, { text = text, target = { path = abs(item.path), lnum = item.lnum } })
      end
    end
  end
  if #finding_lines > 0 then
    b.push("")
    b.push("  Findings", "VallowSection")
    for _, l in ipairs(finding_lines) do
      b.push(l.text, "VallowSevWarn", l.target)
    end
  end

  -- Health
  local complexity = (evidence.complexity or {}).data or {}
  local summary = complexity.summary or {}
  if next(summary) then
    b.push("")
    b.push("  Health", "VallowSection")
    b.push(
      string.format(
        "    %d function(s), %d above threshold (cyclomatic %s, cognitive %s)",
        summary.functions_analyzed or 0,
        summary.functions_above_threshold or 0,
        tostring(summary.max_cyclomatic_threshold or "?"),
        tostring(summary.max_cognitive_threshold or "?")
      ),
      "VallowKind"
    )
  end

  b.push("")
  b.push("  <CR> jump · q close", "VallowFooter")
  float.open({ title = "Vallow Inspect", lines = b.lines, hls = b.hls, targets = b.targets })
end

return M
