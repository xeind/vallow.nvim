-- runner.lua: runs fallow CLI async, normalizes JSON → output contract
local M = {}

local _gen = 0

M.find_root = function()
  local markers = { "package.json", ".git" }
  for _, marker in ipairs(markers) do
    local found = vim.fn.findfile(marker, vim.fn.getcwd() .. ";")
    if found == "" then found = vim.fn.finddir(marker, vim.fn.getcwd() .. ";") end
    if found ~= "" then return vim.fn.fnamemodify(found, ":h") end
  end
  return vim.fn.getcwd()
end

M.run = function(callback)
  _gen = _gen + 1
  local gen = _gen
  local cfg  = require("vallow.config").get()
  local root = M.find_root()
  local stdout, stderr = {}, {}

  local cmd = { cfg.fallow_cmd, "--format", "json", "--quiet" }
  for _, a in ipairs(cfg.fallow_args or {}) do table.insert(cmd, a) end

  vim.fn.jobstart(cmd, {
    cwd = root,
    on_stdout = function(_, data)
      for _, l in ipairs(data) do if l ~= "" then table.insert(stdout, l) end end
    end,
    on_stderr = function(_, data)
      for _, l in ipairs(data) do if l ~= "" then table.insert(stderr, l) end end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if gen ~= _gen then return end
        local raw = table.concat(stdout, "")
        if code ~= 0 then
          if raw == "" then M._run_separate(gen, root, cfg, callback)
          else callback({ error = table.concat(stderr, "\n"), findings = M._empty_findings() }) end
          return
        end
        if raw == "" then M._run_separate(gen, root, cfg, callback); return end
        local ok, decoded = pcall(vim.fn.json_decode, raw)
        if not ok then
          callback({ error = "JSON parse failed: " .. tostring(decoded), findings = M._empty_findings() })
          return
        end
        callback(M._normalize(decoded, root))
      end)
    end,
  })
end

M._run_separate = function(gen, root, cfg, callback)
  local results, pending = {}, 2
  local function collect(key)
    return function(ok, data)
      results[key] = { ok = ok, data = data }
      pending = pending - 1
      if pending == 0 then
        vim.schedule(function()
          if gen ~= _gen then return end
          callback(M._merge_separate(results, root))
        end)
      end
    end
  end
  M._job({ cfg.fallow_cmd, "dead-code", "--format", "json", "--quiet" }, root, collect("dead_code"))
  M._job({ cfg.fallow_cmd, "dupes",     "--format", "json", "--quiet" }, root, collect("dupes"))
end

M._job = function(cmd, cwd, callback)
  local stdout, stderr = {}, {}
  vim.fn.jobstart(cmd, {
    cwd = cwd,
    on_stdout = function(_, data)
      for _, l in ipairs(data) do if l ~= "" then table.insert(stdout, l) end end
    end,
    on_stderr = function(_, data)
      for _, l in ipairs(data) do if l ~= "" then table.insert(stderr, l) end end
    end,
    on_exit = function(_, code)
      local raw = table.concat(stdout, "")
      if code ~= 0 or raw == "" then callback(false, table.concat(stderr, "\n")); return end
      local ok, decoded = pcall(vim.fn.json_decode, raw)
      callback(ok, decoded)
    end,
  })
end

-- Normalize fallow JSON → output contract.
-- Combined output: raw.dead_code / raw.duplication / raw.health
-- Separate output: flat at top level (kind != "combined")
M._normalize = function(raw, root)
  local findings = M._empty_findings()
  local elapsed  = raw.elapsed_ms or 0

  local check, dupes_raw, health_raw
  if raw.kind == "combined" then
    check      = raw.dead_code   or raw.check or {}
    dupes_raw  = raw.duplication or raw.dupes  or {}
    health_raw = raw.health or {}
    elapsed    = (check.elapsed_ms or 0) + (dupes_raw.elapsed_ms or 0)
    if elapsed == 0 then elapsed = raw.elapsed_ms or 0 end
  else
    check      = raw
    dupes_raw  = raw
    health_raw = {}
  end

  local function rel(p)
    if not p or p == "" then return "" end
    return p:gsub("^" .. vim.pesc(root) .. "/", "")
  end

  -- unused_exports[], unused_types[], unused_enum_members[], unused_class_members[]
  local function push_export(item, default_kind)
    local name = item.export_name or item.exportName or ""
    local kind = default_kind
    if item.kind == "unused-type" or item.isTypeOnly or item.is_type_only then
      kind = "type"
    end
    local bucket = (kind == "type") and findings.unused_types
        or (kind == "enum")   and findings.unused_enum_members
        or (kind == "member") and findings.unused_class_members
        or findings.unused_exports
    table.insert(bucket.items, {
      path = item.path or "", relative_path = rel(item.path),
      lnum = item.line or 1, col = item.col or 0,
      name = name, kind = kind,
    })
  end
  for _, v in ipairs(check.unused_exports      or {}) do push_export(v, "value")  end
  for _, v in ipairs(check.unused_types        or {}) do push_export(v, "type")   end
  for _, v in ipairs(check.unused_enum_members  or {}) do push_export(v, "enum")   end
  for _, v in ipairs(check.unused_class_members or {}) do push_export(v, "member") end
  findings.unused_exports.count      = #findings.unused_exports.items
  findings.unused_types.count        = #findings.unused_types.items
  findings.unused_enum_members.count  = #findings.unused_enum_members.items
  findings.unused_class_members.count = #findings.unused_class_members.items

  -- unused_files[]
  for _, v in ipairs(check.unused_files or {}) do
    table.insert(findings.unused_files.items, {
      path = v.path or "", relative_path = rel(v.path),
    })
  end
  findings.unused_files.count = #findings.unused_files.items

  -- unused_dependencies[], unused_dev_dependencies[], unused_optional_dependencies[]
  local function push_dep(item, bucket)
    table.insert(bucket.items, {
      name = item.package_name or item.packageName or item.package or "",
      path = item.path or "", relative_path = rel(item.path), lnum = item.line or 1,
    })
  end
  for _, v in ipairs(check.unused_dependencies          or {}) do push_dep(v, findings.unused_deps) end
  for _, v in ipairs(check.unused_dev_dependencies      or {}) do push_dep(v, findings.unused_dev_deps) end
  for _, v in ipairs(check.unused_optional_dependencies or {}) do push_dep(v, findings.unused_optional_deps) end
  findings.unused_deps.count          = #findings.unused_deps.items
  findings.unused_dev_deps.count      = #findings.unused_dev_deps.items
  findings.unused_optional_deps.count = #findings.unused_optional_deps.items

  -- unresolved_imports[], unlisted_dependencies[]
  for _, v in ipairs(check.unresolved_imports    or {}) do
    table.insert(findings.unresolved_imports.items, {
      name = v.specifier or v.import_path or "",
      path = v.path or "", relative_path = rel(v.path), lnum = v.line or 1,
    })
  end
  for _, v in ipairs(check.unlisted_dependencies or {}) do
    table.insert(findings.unlisted_deps.items, {
      name = v.package_name or v.packageName or v.package or "",
      path = v.path or "", relative_path = rel(v.path), lnum = v.line or 1,
    })
  end
  findings.unresolved_imports.count = #findings.unresolved_imports.items
  findings.unlisted_deps.count      = #findings.unlisted_deps.items

  -- duplicate_exports[]
  for _, v in ipairs(check.duplicate_exports or {}) do
    local locs = {{ path = v.path or "", relative_path = rel(v.path), lnum = v.line or 1, col = v.col or 0 }}
    for _, loc in ipairs(v.duplicate_locations or v.duplicateLocations or {}) do
      table.insert(locs, { path = loc.path or "", relative_path = rel(loc.path), lnum = loc.line or 1, col = loc.col or 0 })
    end
    table.insert(findings.duplicate_exports.items, {
      name = v.export_name or v.exportName or "", locations = locs,
    })
  end
  findings.duplicate_exports.count = #findings.duplicate_exports.items

  -- circular_dependencies[]
  for _, v in ipairs(check.circular_dependencies or {}) do
    table.insert(findings.circular_deps.items, {
      path = v.path or "", relative_path = rel(v.path),
      cycle = v.cycle or {},
    })
  end
  findings.circular_deps.count = #findings.circular_deps.items

  -- boundary_violations[]
  for _, v in ipairs(check.boundary_violations or {}) do
    table.insert(findings.boundary_violations.items, {
      path          = v.path or "",
      relative_path = rel(v.path),
      lnum          = v.line or 1,
      col           = v.col  or 0,
      import_path   = v.import_path or v.importPath or "",
      boundary_name = v.boundary_name or v.boundaryName or "",
    })
  end
  findings.boundary_violations.count = #findings.boundary_violations.items

  -- clone_groups[] from dupes
  for _, g in ipairs(dupes_raw.clone_groups or {}) do
    local locs = {}
    for _, inst in ipairs(g.instances or {}) do
      table.insert(locs, {
        path = inst.path or "", relative_path = rel(inst.path),
        lnum = inst.line or 1, end_lnum = inst.lineEnd or inst.line_end, col = inst.col or 0,
      })
    end
    table.insert(findings.clone_groups.items, {
      name      = g.suggested_name or g.suggestedName or ("dup:" .. (g.fingerprint or "?")),
      locations = locs,
      tokens    = g.tokens,
      lines     = g.lines,
    })
  end
  findings.clone_groups.count = #findings.clone_groups.items

  -- health: complexity findings[], hotspots[], targets[]
  for _, v in ipairs(health_raw.findings or {}) do
    table.insert(findings.health_complexity.items, {
      path = v.path or "", relative_path = rel(v.path),
      lnum = v.line or 1, name = v.name or "",
      cyclomatic = v.cyclomatic, cognitive = v.cognitive, exceeded = v.exceeded,
    })
  end
  findings.health_complexity.count = #findings.health_complexity.items

  for _, v in ipairs(health_raw.hotspots or {}) do
    table.insert(findings.health_hotspots.items, {
      path = v.path or "", relative_path = rel(v.path),
      score = v.score, commits = v.commits, trend = v.trend,
    })
  end
  findings.health_hotspots.count = #findings.health_hotspots.items

  for _, v in ipairs(health_raw.targets or {}) do
    table.insert(findings.health_targets.items, {
      path = v.path or "", relative_path = rel(v.path),
      recommendation = v.recommendation, category = v.category, priority = v.priority,
    })
  end
  findings.health_targets.count = #findings.health_targets.items

  if health_raw.health_score then
    findings.health_score = health_raw.health_score
  end

  return { repo_root = root, duration_ms = elapsed, findings = findings, error = nil }
end

M._merge_separate = function(raw, root)
  local merged = { kind = "combined", elapsed_ms = 0 }
  if raw.dead_code and raw.dead_code.ok then
    merged.dead_code  = raw.dead_code.data
    merged.elapsed_ms = raw.dead_code.data.elapsed_ms or 0
  end
  if raw.dupes and raw.dupes.ok then
    merged.duplication = raw.dupes.data
    merged.elapsed_ms  = merged.elapsed_ms + (raw.dupes.data.elapsed_ms or 0)
  end
  local result = M._normalize(merged, root)
  if raw.dead_code and not raw.dead_code.ok then result.error = raw.dead_code.data end
  return result
end

M._empty_findings = function()
  return {
    -- UNUSED CODE
    unused_exports       = { count = 0, items = {} },
    unused_types         = { count = 0, items = {} },
    unused_enum_members  = { count = 0, items = {} },
    unused_class_members = { count = 0, items = {} },
    unused_files         = { count = 0, items = {} },
    unused_deps          = { count = 0, items = {} },
    unused_dev_deps      = { count = 0, items = {} },
    unused_optional_deps = { count = 0, items = {} },
    unresolved_imports   = { count = 0, items = {} },
    unlisted_deps        = { count = 0, items = {} },
    duplicate_exports    = { count = 0, items = {} },
    circular_deps        = { count = 0, items = {} },
    boundary_violations  = { count = 0, items = {} },
    -- DUPLICATES
    clone_groups         = { count = 0, items = {} },
    -- HEALTH
    health_complexity    = { count = 0, items = {} },
    health_hotspots      = { count = 0, items = {} },
    health_targets       = { count = 0, items = {} },
    health_score         = nil,
  }
end

return M
