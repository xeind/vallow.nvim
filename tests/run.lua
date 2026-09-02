-- Headless test harness. Run it from the fixture project:
--   cd tests/fixture && nvim --headless -u NONE -l ../run.lua
-- or just `make test` from the repo root.
local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local repo = vim.fn.fnamemodify(script, ":h:h")
vim.opt.rtp:prepend(repo)

local failed = 0

local function ok(name, cond, detail)
  if cond then
    print("ok   " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. (detail and ("  — " .. detail) or ""))
  end
end

local function eq(name, got, want)
  ok(name, got == want, "got " .. vim.inspect(got) .. ", want " .. vim.inspect(want))
end

local function count(results, key)
  local b = results.findings and results.findings[key]
  return b and b.count or -1
end

-- Render into a scratch buffer and return the lines.
local function render_lines(results)
  local buf = vim.api.nvim_create_buf(false, true)
  require("vallow.panel.render").render(buf, results, nil)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  require("vallow.panel.render").clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  return lines
end

local function has_line(lines, pat)
  for _, l in ipairs(lines) do
    if l:find(pat) then
      return true
    end
  end
  return false
end

local steps = {}

-- 1. Combined run: counts, version, notices, header lines.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  require("vallow.runner").run(function(results)
    ok("combined: no error", not results.error, tostring(results.error))
    eq("combined: unused_exports", count(results, "unused_exports"), 1)
    eq("combined: unused_types", count(results, "unused_types"), 1)
    eq("combined: unused_deps", count(results, "unused_deps"), 1)
    eq("combined: unresolved_imports", count(results, "unresolved_imports"), 1)
    ok("combined: version", (results.version or ""):match("^3%.%d+%.") ~= nil, tostring(results.version))
    eq("combined: notices", #(results.notices or {}), 1)
    ok(
      "combined: repo_root",
      vim.fn.fnamemodify(results.repo_root or "", ":p"):find("tests/fixture", 1, true) ~= nil,
      tostring(results.repo_root)
    )

    local lines = render_lines(results)
    eq("render: header", lines[1], "  VALLOW")
    ok("render: version line", has_line(lines, "fallow 3%.%d+%.%d+ ·"), lines[3])
    ok("render: notice line", has_line(lines, "⚠"))
    ok("render: section header", has_line(lines, "UNUSED CODE%s+3"))
    ok("render: unused exports category", has_line(lines, "Unused Exports%s+1"))
    ok("render: unresolved imports category", has_line(lines, "Unresolved Imports%s+1"))
    ok("render: footer", has_line(lines, "4 issues"))
    next_step()
  end)
end)

-- 2. Separate mode: the shim gives no combined output, so the runner falls
-- back to one job per analysis.
table.insert(steps, function(next_step)
  require("vallow").setup({ fallow_cmd = repo .. "/tests/bin/fallow-no-combined" })
  require("vallow.runner").run(function(results)
    ok("separate: no error", not results.error, tostring(results.error))
    eq("separate: unused_exports", count(results, "unused_exports"), 1)
    eq("separate: unused_types", count(results, "unused_types"), 1)
    eq("separate: unresolved_imports", count(results, "unresolved_imports"), 1)
    ok("separate: version", (results.version or ""):match("^3%.%d+%.") ~= nil, tostring(results.version))
    ok("separate: renders", has_line(render_lines(results), "Unused Exports"))
    next_step()
  end)
end)

-- 3. Unknown flag: fallow fails, the panel shows the error instead of crashing.
table.insert(steps, function(next_step)
  require("vallow").setup({ fallow_args = { "--no-such-flag" } })
  require("vallow.runner").run(function(results)
    ok("error: reported", results.error ~= nil and results.error ~= "")
    local lines = render_lines(results)
    ok("error: rendered", has_line(lines, "Error:"), vim.inspect(lines))
    next_step()
  end)
end)

-- 4. Result cache: a run writes it, load returns it marked stale.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  local cache = require("vallow.cache")
  local runner = require("vallow.runner")
  local path = cache.path(runner.find_root())
  vim.fn.delete(path)
  runner.run(function(results)
    ok("cache: file written", vim.fn.filereadable(path) == 1, tostring(path))
    local cached = cache.load(runner.find_root())
    ok("cache: loads", cached ~= nil)
    if cached then
      eq("cache: unused_exports", count(cached, "unused_exports"), count(results, "unused_exports"))
      eq("cache: stale", cached.stale, true)
      ok("cache: stale in header", has_line(render_lines(cached), "%(stale%)"))
    end
    vim.fn.delete(path)

    -- cache = false disables both ends.
    require("vallow").setup({ cache = false })
    cache.save(results)
    ok("cache: disabled by config", vim.fn.filereadable(path) == 0)
    next_step()
  end)
end)

-- 5. :Vallow arguments and completion. -u NONE skips plugin files, so source
-- the command definitions by hand.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  vim.cmd("source " .. repo .. "/plugin/vallow.lua")
  local panel = require("vallow.panel")
  local runner = require("vallow.runner")
  runner.run(function(results)
    panel.state.results = results
    vim.cmd("Vallow health")
    eq("command: section opened", panel.state.current_section, "health")
    ok("command: panel is open", panel._is_open() == true)

    local complete = vim.api.nvim_get_commands({})["Vallow"] ~= nil
    ok("command: registered", complete)
    local comp = vim.fn.getcompletion("Vallow ", "cmdline")
    for _, want in ipairs({
      "health",
      "issues",
      "duplicates",
      "unused_code",
      "architecture",
      "production",
      "refresh",
      "search",
    }) do
      ok("complete: " .. want, vim.tbl_contains(comp, want), vim.inspect(comp))
    end
    ok("complete: prefix filter", vim.deep_equal(vim.fn.getcompletion("Vallow pro", "cmdline"), { "production" }))

    panel.state.production = false
    vim.cmd("Vallow production")
    eq("command: production toggled", panel.state.production, true)
    panel.state.production = false

    vim.cmd("Vallow nonsense") -- unknown argument must not raise
    ok("command: unknown argument survives", true)
    panel.close()
    panel.state.current_section = nil
    next_step()
  end)
end)

-- 6. Per-category diagnostics config.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  require("vallow.runner").run(function(results)
    local diag = require("vallow.diagnostics")
    local ns = vim.api.nvim_create_namespace("vallow_diag")
    local function fallow_diags(buf)
      return vim.diagnostic.get(buf, { namespace = ns })
    end

    vim.cmd("edit src/a.ts")
    local a_buf = vim.api.nvim_get_current_buf()
    diag.apply(results.findings)
    local d = fallow_diags(a_buf)
    eq("diag: default count", #d, 2)
    ok("diag: default severity", d[1].severity == vim.diagnostic.severity.HINT, vim.inspect(d[1]))

    require("vallow").setup({ diagnostics = { categories = { unused_exports = { severity = "error" } } } })
    diag.apply(results.findings)
    local sevs = {}
    for _, x in ipairs(fallow_diags(a_buf)) do
      sevs[x.severity] = true
    end
    ok("diag: severity override", sevs[vim.diagnostic.severity.ERROR] == true, vim.inspect(sevs))

    require("vallow").setup({ diagnostics = { categories = { unused_exports = { enabled = false } } } })
    diag.apply(results.findings)
    eq("diag: category disabled", #fallow_diags(a_buf), 1)

    require("vallow").setup({ diagnostics = { virtual_text = false } })
    diag.apply(results.findings)
    eq("diag: virtual_text off", vim.diagnostic.config(nil, ns).virtual_text, false)

    require("vallow").setup({ diagnostics = { current_buffer_only = true } })
    vim.cmd("edit src/index.ts")
    local i_buf = vim.api.nvim_get_current_buf()
    diag.apply(results.findings)
    eq("diag: current buffer only, other buffer", #fallow_diags(a_buf), 0)
    ok("diag: current buffer only, this buffer", #fallow_diags(i_buf) > 0)

    diag.clear()
    require("vallow").setup({})
    next_step()
  end)
end)

-- 7. resolve_cmd order: config override, node_modules/.bin, PATH.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  local runner = require("vallow.runner")
  local tmp = vim.fn.tempname()
  local bin_dir = tmp .. "/node_modules/.bin"
  vim.fn.mkdir(bin_dir, "p")
  local local_bin = bin_dir .. "/fallow"
  vim.fn.writefile({ "#!/bin/sh", "echo local" }, local_bin)
  vim.uv.fs_chmod(local_bin, 493)

  eq("resolve: node_modules wins over PATH", runner.resolve_cmd(tmp), local_bin)
  eq("resolve: falls back to PATH", runner.resolve_cmd(vim.fn.tempname()), "fallow")

  require("vallow").setup({ fallow_cmd = "/custom/fallow" })
  eq("resolve: config wins", runner.resolve_cmd(tmp), "/custom/fallow")

  require("vallow").setup({})
  vim.fn.delete(tmp, "rf")
  next_step()
end)

-- 8. Audit mode against a throwaway git repo: base ref, introduced marker,
-- inherited toggle.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  local runner = require("vallow.runner")
  local fixture = vim.fn.getcwd()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  vim.fn.system({ "cp", "-r", fixture .. "/package.json", fixture .. "/tsconfig.json", fixture .. "/src", tmp })
  local function git(...)
    vim.fn.system({ "git", "-C", tmp, "-c", "user.email=t@t", "-c", "user.name=t", ... })
  end
  git("init", "-q")
  git("add", "-A")
  git("commit", "-qm", "init")
  vim.fn.writefile({ "export function brandNew() {", "  return 1;", "}" }, tmp .. "/src/b.ts")
  git("add", "-A")
  git("commit", "-qm", "second")

  vim.cmd("enew")
  vim.cmd("cd " .. tmp)
  git("branch", "-M", "master")
  eq("audit: default base falls back to master", runner.default_base(tmp), "master")
  git("branch", "-M", "main")
  eq("audit: default base prefers main", runner.default_base(tmp), "main")

  runner.run_audit("HEAD~1", function(results)
    ok("audit: no error", not results.error, tostring(results.error))
    ok("audit: envelope", results.audit ~= nil)
    eq("audit: base ref", results.audit and results.audit.base_ref, "HEAD~1")
    eq("audit: unused files", count(results, "unused_files"), 1)
    local item = results.findings.unused_files.items[1]
    eq("audit: introduced flag", item and item.introduced, true)

    local buf = vim.api.nvim_create_buf(false, true)
    local render = require("vallow.panel.render")
    vim.b[buf].vallow_open_cats = { unused_files = true, unused_all_deps = true }
    render.render(buf, results, nil)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    ok("audit: header names the ref", has_line(lines, "audit vs HEAD~1"), vim.inspect(lines))
    ok("audit: introduced marker", has_line(lines, "^    %+ .*b%.ts"), vim.inspect(lines))

    -- `i` hides inherited findings; the unused dependency is inherited.
    vim.b[buf].vallow_hide_inherited = true
    render.render(buf, results, nil)
    local narrowed = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    ok("audit: new-only header", has_line(narrowed, "new only %(i%)"), vim.inspect(narrowed))
    ok("audit: inherited hidden", not has_line(narrowed, "lodash"), vim.inspect(narrowed))
    render.clear(buf)
    vim.api.nvim_buf_delete(buf, { force = true })

    vim.cmd("cd " .. fixture)
    vim.fn.delete(tmp, "rf")
    next_step()
  end)
end)

-- 9. Inspect float: real `fallow inspect` envelope rendered with jump targets.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  local runner = require("vallow.runner")
  local root = runner.find_root()
  local bin = runner.resolve_cmd(root)
  runner._job({ bin, "inspect", "--file", "src/a.ts", "--format", "json", "--quiet" }, root, function(job_ok, data)
    vim.schedule(function()
      ok("inspect: envelope", job_ok and type(data) == "table", vim.inspect(data))
      require("vallow.inspect")._show(data, root, "src/a.ts")
      local fbuf = vim.api.nvim_get_current_buf()
      local lines = vim.api.nvim_buf_get_lines(fbuf, 0, -1, false)
      ok("inspect: identity line", has_line(lines, "1 importers"), vim.inspect(lines))
      ok("inspect: exports section", has_line(lines, "  Exports"), vim.inspect(lines))
      ok("inspect: export row", has_line(lines, "unusedFn%s+value%s+0 refs"), vim.inspect(lines))
      ok("inspect: importers", has_line(lines, "src/index%.ts"), vim.inspect(lines))
      ok("inspect: findings", has_line(lines, "unused export%s+unusedFn"), vim.inspect(lines))
      vim.api.nvim_win_close(0, true)
      next_step()
    end)
  end)
end)

-- 10. Ignore actions: JSON writing, and the stale_suppressions category.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  local ignore = require("vallow.ignore")

  eq(
    "ignore: 2-space indent",
    ignore.encode({ ignoreFindings = { "src/a.ts" } }),
    '{\n  "ignoreFindings": [\n    "src/a.ts"\n  ]\n}'
  )

  local fixture = vim.fn.getcwd()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  vim.fn.system({ "cp", "-r", fixture .. "/package.json", fixture .. "/tsconfig.json", fixture .. "/src", tmp })
  local cfg_path = ignore.config_path(tmp)
  vim.fn.writefile({ '{ "entry": ["src/index.ts"] }' }, cfg_path)

  -- confirm() cannot prompt in a headless run.
  local real_confirm = vim.fn.confirm
  vim.fn.confirm = function()
    return 1
  end

  ok("ignore: add_finding writes", ignore.add_finding(tmp, "src/a.ts"))
  ok("ignore: add_export writes", ignore.add_export(tmp, "src/a.ts", "unusedFn"))
  ok("ignore: add_export merges", ignore.add_export(tmp, "src/a.ts", "Dead"))
  local written = ignore.read(cfg_path)
  ok("ignore: keeps existing keys", vim.deep_equal(written.entry, { "src/index.ts" }), vim.inspect(written))
  ok("ignore: ignoreFindings", vim.deep_equal(written.ignoreFindings, { "src/a.ts" }), vim.inspect(written))
  eq("ignore: one export rule", #written.ignoreExports, 1)
  ok(
    "ignore: exports merged into the rule",
    vim.deep_equal(written.ignoreExports[1], { file = "src/a.ts", exports = { "unusedFn", "Dead" } }),
    vim.inspect(written.ignoreExports)
  )
  vim.fn.confirm = real_confirm

  -- A marker over a used export is stale; fallow reports it, the panel shows it.
  vim.fn.delete(cfg_path)
  local index = tmp .. "/src/index.ts"
  local body = vim.fn.readfile(index)
  table.insert(body, 1, "// fallow-ignore-next-line unused-export")
  vim.fn.writefile(body, index)

  vim.cmd("enew")
  vim.cmd("cd " .. tmp)
  require("vallow.runner").run(function(results)
    eq("stale: counted", count(results, "stale_suppressions"), 1)
    eq("stale: issue kind", results.findings.stale_suppressions.items[1].name, "unused-export")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].vallow_open_cats = { stale_suppressions = true }
    require("vallow.panel.render").render(buf, results, nil)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    ok("stale: category rendered", has_line(lines, "Stale Suppressions%s+1"), vim.inspect(lines))
    require("vallow.panel.render").clear(buf)
    vim.api.nvim_buf_delete(buf, { force = true })

    vim.cmd("cd " .. fixture)
    vim.fn.delete(tmp, "rf")
    next_step()
  end)
end)

local done = false
local function run_step(i)
  if i > #steps then
    done = true
    return
  end
  steps[i](function()
    run_step(i + 1)
  end)
end
run_step(1)

vim.wait(90000, function()
  return done
end, 100)

if not done then
  failed = failed + 1
  print("FAIL harness timed out")
end

print(failed == 0 and "\nall tests passed" or ("\n" .. failed .. " test(s) failed"))
vim.cmd(failed == 0 and "cq 0" or "cq 1")
