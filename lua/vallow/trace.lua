-- trace.lua: `fallow dead-code --trace` / `--trace-dependency` and
-- `fallow trace --path` (3.24+) as a tree.
local M = {}

-- `fallow trace --path` arrived in 3.24.0.
local PATH_MIN_VERSION = { 3, 24, 0 }

local function run(sub, args, callback)
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
  local cmd = { bin, sub }
  vim.list_extend(cmd, args)
  vim.list_extend(cmd, { "--format", "json", "--quiet" })
  runner._job(cmd, root, function(ok, data)
    vim.schedule(function()
      if not ok or type(data) ~= "table" then
        local msg = tostring(data)
        if sub == "trace" and (msg:find("unrecognized") or msg:find("unexpected argument")) then
          vim.notify("vallow: path trace needs fallow 3.24 or newer", vim.log.levels.WARN)
        else
          vim.notify("vallow: trace failed: " .. msg, vim.log.levels.ERROR)
        end
        return
      end
      callback(data, root)
    end)
  end)
end

-- Trace one export: `--trace <relative path>:<name>`.
M.export = function(rel, name)
  run("dead-code", { "--trace", rel .. ":" .. name }, function(data, root)
    M._show_export(data, root)
  end)
end

-- Trace one package: `--trace-dependency <name>`.
M.dependency = function(name)
  run("dead-code", { "--trace-dependency", name }, function(data, root)
    M._show_dependency(data, root)
  end)
end

-- False when the last analysis ran an older fallow than 3.24. An unknown
-- version passes; `run` then catches the unknown flag.
local function path_supported()
  local results = require("vallow.panel").state.results
  local parsed = results and results.version and vim.version.parse(tostring(results.version))
  return not parsed or vim.version.cmp(parsed, PATH_MIN_VERSION) >= 0
end

-- Trace the shortest import path between two root-relative files:
-- `fallow trace --path <from> <to>`.
M.path = function(from, to)
  if not path_supported() then
    vim.notify("vallow: path trace needs fallow 3.24 or newer", vim.log.levels.WARN)
    return
  end
  run("trace", { "--path", from, to }, function(data, root)
    M._show_path(data, root)
  end)
end

-- Trace from the current buffer to a file given as absolute or cwd-relative.
M.between_files = function(target)
  local from = vim.api.nvim_buf_get_name(0)
  if from == "" or target == "" then
    vim.notify("vallow: usage :Vallow path {file}, from a named buffer", vim.log.levels.WARN)
    return
  end
  local root = require("vallow.runner").find_root()
  if not root then
    vim.notify("vallow: no JS/TS project here", vim.log.levels.WARN)
    return
  end
  local prefix = root .. "/"
  local rels = {}
  for _, p in ipairs({ from, vim.fn.fnamemodify(target, ":p") }) do
    if p:sub(1, #prefix) ~= prefix then
      vim.notify("vallow: " .. p .. " is outside the project root", vim.log.levels.WARN)
      return
    end
    table.insert(rels, p:sub(#prefix + 1))
  end
  M.path(rels[1], rels[2])
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

-- Shortest import path: one line per hop, jumping to the import line.
M._show_path = function(data, root)
  local float = require("vallow.panel.float")
  local b = float.builder()

  b.push("")
  b.push("  " .. (data.from or ""), "VallowName", { path = abs(root, data.from), lnum = 1 })
  local hops = data.path or {}
  for i, hop in ipairs(hops) do
    local facts = { "line " .. (hop.import_line or "?") }
    if hop.type_only then
      table.insert(facts, "type-only")
    elseif hop.dynamic then
      table.insert(facts, "dynamic")
    end
    local last = i == #hops
    b.push(
      ("  %s %s  ·  %s"):format(last and "└─" or "├─", hop.to or "", table.concat(facts, " · ")),
      "VallowPath",
      { path = abs(root, hop.from), lnum = hop.import_line or 1 }
    )
  end

  if #hops == 0 then
    b.push("  └─ " .. (data.reason or "no import path"), "Comment")
  elseif data.reason and data.reason ~= "" then
    b.push("     " .. data.reason, "Comment")
  end
  b.push("")
  b.push("  <CR> jump to the import · q close", "VallowFooter")
  float.open({ title = "Vallow Trace", lines = b.lines, hls = b.hls, targets = b.targets })
end

return M
