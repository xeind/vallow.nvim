-- trace.lua: `fallow dead-code --trace` / `--trace-dependency` as a tree.
local M = {}

local function run(args, callback)
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
  local cmd = { bin, "dead-code" }
  vim.list_extend(cmd, args)
  vim.list_extend(cmd, { "--format", "json", "--quiet" })
  runner._job(cmd, root, function(ok, data)
    vim.schedule(function()
      if not ok or type(data) ~= "table" then
        vim.notify("vallow: trace failed: " .. tostring(data), vim.log.levels.ERROR)
        return
      end
      callback(data, root)
    end)
  end)
end

-- Trace one export: `--trace <relative path>:<name>`.
M.export = function(rel, name)
  run({ "--trace", rel .. ":" .. name }, function(data, root)
    M._show_export(data, root)
  end)
end

-- Trace one package: `--trace-dependency <name>`.
M.dependency = function(name)
  run({ "--trace-dependency", name }, function(data, root)
    M._show_dependency(data, root)
  end)
end

local function abs(root, p)
  if not p or p == "" then
    return nil
  end
  return p:sub(1, 1) == "/" and p or (root .. "/" .. p)
end

M._show_export = function(data, root)
  local float = require("vallow.panel.float")
  local b = float.builder()

  b.push("")
  b.push("  " .. (data.file or "") .. ":" .. (data.export_name or ""), "VallowName", {
    path = abs(root, data.file),
    lnum = 1,
  })

  local facts = { data.is_used and "used" or "unused" }
  table.insert(facts, data.file_reachable and "file reachable" or "file unreachable")
  if data.is_entry_point then
    table.insert(facts, "entry point")
  end
  if data.namespace then
    table.insert(facts, data.namespace)
  end
  b.push("  ├─ " .. table.concat(facts, " · "), "VallowKind")

  local refs = data.direct_references or {}
  b.push(("  ├─ direct references (%d)"):format(#refs), "VallowSection")
  for _, ref in ipairs(refs) do
    local from = ref.from_file or ""
    b.push(
      ("  │  └─ %s  ·  %s"):format(from, ref.kind or ""),
      "VallowPath",
      { path = abs(root, from), lnum = 1 }
    )
  end

  local chains = data.re_export_chains or {}
  b.push(("  ├─ re-export chains (%d)"):format(#chains), "VallowSection")
  for _, chain in ipairs(chains) do
    local barrel = chain.barrel_file or ""
    b.push(
      ("  │  └─ %s  ·  as %s  ·  %d ref(s)"):format(barrel, chain.exported_as or "", chain.reference_count or 0),
      "VallowPath",
      { path = abs(root, barrel), lnum = 1 }
    )
  end

  if data.reason and data.reason ~= "" then
    b.push("  └─ " .. data.reason, "Comment")
  end
  b.push("")
  b.push("  <CR> jump · q close", "VallowFooter")
  float.open({ title = "Vallow Trace", lines = b.lines, hls = b.hls, targets = b.targets })
end

M._show_dependency = function(data, root)
  local float = require("vallow.panel.float")
  local b = float.builder()

  b.push("")
  b.push("  " .. (data.package_name or ""), "VallowName")
  local facts = { data.is_used and "used" or "unused", (data.import_count or 0) .. " import(s)" }
  if data.used_in_scripts then
    table.insert(facts, "used in package scripts")
  end
  b.push("  ├─ " .. table.concat(facts, " · "), "VallowKind")

  local function branch(prefix, title, paths)
    b.push(("  %s %s (%d)"):format(prefix, title, #paths), "VallowSection")
    for _, p in ipairs(paths) do
      b.push("  │  └─ " .. p, "VallowPath", { path = abs(root, p), lnum = 1 })
    end
  end
  branch("├─", "imported by", data.imported_by or {})
  branch("└─", "type-only importers", data.type_only_imported_by or {})

  b.push("")
  b.push("  <CR> jump · q close", "VallowFooter")
  float.open({ title = "Vallow Trace", lines = b.lines, hls = b.hls, targets = b.targets })
end

return M
