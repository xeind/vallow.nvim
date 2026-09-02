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
      "dashboard",
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

-- 11. Explain: issue-type mapping, the float, and the per-session cache.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  local explain = require("vallow.explain")
  eq("explain: category maps", explain.issue_type("unused_exports"), "unused-export")
  eq("explain: merged category maps", explain.issue_type("unused_all_deps"), "unused-dependency")
  eq("explain: unmapped category", explain.issue_type("health_hotspots"), nil)

  explain._cache = {}
  explain.get("unused-export", function(data, err)
    ok("explain: fetched", data ~= nil, tostring(err))
    eq("explain: id", data and data.id, "fallow/unused-export")
    ok("explain: cached", explain._cache["unused-export"] ~= nil)

    local cached = false
    explain.get("unused-export", function()
      cached = true
    end)
    ok("explain: second call is synchronous", cached)

    explain._show(data)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    ok("explain: title", has_line(lines, "Unused Exports"), vim.inspect(lines))
    ok("explain: rationale section", has_line(lines, "Why it matters"), vim.inspect(lines))
    ok("explain: docs link", has_line(lines, "docs%.fallow%.tools"), vim.inspect(lines))
    vim.api.nvim_win_close(0, true)
    next_step()
  end)
end)

-- 12. Trace: the export and dependency envelopes, rendered as a tree.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  local runner = require("vallow.runner")
  local root = runner.find_root()
  local bin = runner.resolve_cmd(root)
  local trace = require("vallow.trace")

  runner._job(
    { bin, "dead-code", "--trace", "src/a.ts:unusedFn", "--format", "json", "--quiet" },
    root,
    function(job_ok, data)
      vim.schedule(function()
        ok("trace: export envelope", job_ok and data and data.kind == "trace", vim.inspect(data))
        trace._show_export(data, root)
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        ok("trace: export head", has_line(lines, "src/a%.ts:unusedFn"), vim.inspect(lines))
        ok("trace: unused fact", has_line(lines, "├─ unused · file reachable"), vim.inspect(lines))
        ok("trace: reference branch", has_line(lines, "direct references %(0%)"), vim.inspect(lines))
        ok("trace: reason", has_line(lines, "No references found"), vim.inspect(lines))
        vim.api.nvim_win_close(0, true)

        runner._job(
          { bin, "dead-code", "--trace-dependency", "lodash", "--format", "json", "--quiet" },
          root,
          function(dep_ok, dep)
            vim.schedule(function()
              ok("trace: dependency envelope", dep_ok and dep and dep.package_name == "lodash", vim.inspect(dep))
              trace._show_dependency(dep, root)
              local dep_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
              ok("trace: dependency head", has_line(dep_lines, "  lodash"), vim.inspect(dep_lines))
              ok("trace: importers branch", has_line(dep_lines, "imported by %(0%)"), vim.inspect(dep_lines))
              vim.api.nvim_win_close(0, true)
              next_step()
            end)
          end
        )
      end)
    end
  )
end)

-- 13. Health dashboard: gauge, penalties, vital signs, and the trend sparkline.
table.insert(steps, function(next_step)
  require("vallow").setup({})
  local fixture = vim.fn.getcwd()
  local health_dir = repo .. "/tests/fixture-health"
  vim.cmd("enew")
  vim.cmd("cd " .. health_dir)
  vim.fn.delete(health_dir .. "/.fallow", "rf")

  local dash = require("vallow.dashboard")
  eq("dashboard: gauge full", dash._gauge(100), string.rep("█", 30))
  eq("dashboard: gauge empty", dash._gauge(0), string.rep("░", 30))
  eq("dashboard: band A", dash._band(91), "VallowSevHint")
  eq("dashboard: band C", dash._band(62), "VallowSevWarn")
  eq("dashboard: band F", dash._band(20), "VallowSevError")
  eq("dashboard: sparkline", dash._sparkline({ 1, 2, 3 }), "▁▅█")

  local runner = require("vallow.runner")
  local bin = runner.resolve_cmd(health_dir)
  -- A snapshot is what makes fallow emit health_trend on the next run.
  runner._job({ bin, "health", "--format", "json", "--quiet", "--score", "--save-snapshot" }, health_dir, function()
    vim.schedule(function()
      runner.run(function(results)
        local f = results.findings
        ok("dashboard: score present", type(f.health_score) == "table", vim.inspect(results.error))
        ok("dashboard: penalties present", type(f.health_score.penalties) == "table")
        ok("dashboard: vital signs present", type(f.vital_signs) == "table")
        ok("dashboard: trend present", type(f.health_trend) == "table", vim.inspect(f.health_trend))

        local lines = dash._lines(f).lines
        ok("dashboard: gauge line", has_line(lines, "░  %d"), vim.inspect(lines))
        ok("dashboard: penalties heading", has_line(lines, "  Penalties"), vim.inspect(lines))
        ok("dashboard: circular penalty", has_line(lines, "circular deps%s+%-25"), vim.inspect(lines))
        ok("dashboard: vital signs", has_line(lines, "duplication %d"), vim.inspect(lines))
        ok("dashboard: trend heading", has_line(lines, "  Trend vs "), vim.inspect(lines))
        ok("dashboard: trend sparkline", has_line(lines, "Health Score  [▁▂▃▄▅▆▇█]+"), vim.inspect(lines))

        -- Penalties sorted largest first.
        local order = {}
        for _, l in ipairs(lines) do
          local key, value = l:match("^    (%a[%a ]-)%s+%-(%d[%d%.]*)$")
          if key then
            table.insert(order, tonumber(value))
          end
        end
        ok("dashboard: penalties sorted", #order > 1 and order[1] >= order[2], vim.inspect(order))

        -- Health switched off: one line says so.
        require("vallow").setup({ analyses = { "dead-code" } })
        local off = dash._lines(f).lines
        ok("dashboard: health off", has_line(off, "not in config%.analyses"), vim.inspect(off))
        require("vallow").setup({})
        local none = dash._lines({}).lines
        ok("dashboard: no score", has_line(none, "No health score yet"), vim.inspect(none))

        vim.fn.delete(health_dir .. "/.fallow", "rf")
        vim.cmd("cd " .. fixture)
        next_step()
      end)
    end)
  end)
end)

-- 14. Virtual lines above complex functions and the hotspot gutter sign.
table.insert(steps, function(next_step)
  local fixture = vim.fn.getcwd()
  local health_dir = repo .. "/tests/fixture-health"
  vim.cmd("enew")
  vim.cmd("cd " .. health_dir)
  require("vallow").setup({ diagnostics = { virtual_lines = true } })

  require("vallow.runner").run(function(results)
    local diag = require("vallow.diagnostics")
    local virt_ns = vim.api.nvim_create_namespace("vallow_virt")
    vim.cmd("edit src/complex.ts")
    local buf = vim.api.nvim_get_current_buf()
    local findings = results.findings

    eq("virt: complexity findings", count(results, "health_complexity"), 4)
    local item = findings.health_complexity.items[1]
    ok("virt: absolute path", (item.path or ""):sub(1, 1) == "/", tostring(item.path))
    eq("virt: end line", findings.health_complexity.items[1].end_lnum ~= nil, true)

    diag.apply_buf(buf, findings)
    local marks = vim.api.nvim_buf_get_extmarks(buf, virt_ns, 0, -1, { details = true })
    local text
    for _, m in ipairs(marks) do
      local vl = m[4] and m[4].virt_lines
      if vl then
        text = vl[1][1][1]
        eq("virt: above the function", m[4].virt_lines_above, true)
        eq("virt: highlight", vl[1][1][2], "VallowKind")
      end
    end
    ok("virt: line text", text ~= nil and text:match("ƒ cyclomatic %d+ · cognitive %d+") ~= nil, vim.inspect(text))

    -- Hotspots need git churn, which the fixture has none of; the sign path
    -- is exercised with one synthetic entry on this file.
    findings.health_hotspots = { count = 1, items = { { path = vim.api.nvim_buf_get_name(buf) } } }
    diag.apply_buf(buf, findings)
    local sign
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, virt_ns, 0, -1, { details = true })) do
      sign = sign or (m[4] and m[4].sign_text)
    end
    ok("virt: hotspot sign", sign ~= nil and vim.trim(sign) == "󱐋", vim.inspect(sign))

    require("vallow").setup({})
    diag.apply_buf(buf, findings)
    eq("virt: off by default", #vim.api.nvim_buf_get_extmarks(buf, virt_ns, 0, -1, {}), 0)

    diag.clear()
    vim.cmd("cd " .. fixture)
    next_step()
  end)
end)

-- 15. Clone diff: instances sorted by size, two largest opened side by side.
table.insert(steps, function(next_step)
  local fixture = vim.fn.getcwd()
  local health_dir = repo .. "/tests/fixture-health"
  vim.cmd("enew")
  vim.cmd("cd " .. health_dir)
  require("vallow").setup({})

  require("vallow.runner").run(function(results)
    eq("diff: clone group found", count(results, "clone_groups"), 1)
    local group = results.findings.clone_groups.items[1]
    eq("diff: three instances", #group.locations, 3)
    ok("diff: instance end line", group.locations[1].end_lnum == 28, vim.inspect(group.locations[1]))

    -- The panel rows carry the instances so `d` can reach them.
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].vallow_open_cats = { clone_groups = true }
    require("vallow.panel.render").render(buf, results, nil)
    local with_locs = 0
    for _, entry in pairs(require("vallow.panel.render").get_line_map(buf)) do
      if type(entry) == "table" and entry.locations then
        with_locs = with_locs + 1
      end
    end
    eq("diff: rows carry instances", with_locs, 4)
    require("vallow.panel.render").clear(buf)
    vim.api.nvim_buf_delete(buf, { force = true })

    local actions = require("vallow.panel.actions")
    local sorted = actions._sort_instances({
      { path = "/b.ts", lnum = 5, end_lnum = 9 },
      { path = "/a.ts", lnum = 1, end_lnum = 40 },
      { path = "/c.ts", lnum = 2, end_lnum = 6 },
    })
    eq("diff: largest first", sorted[1].path, "/a.ts")
    eq("diff: ties by path", sorted[2].path, "/b.ts")

    local tabs_before = #vim.api.nvim_list_tabpages()
    local notified = {}
    local real_notify = vim.notify
    vim.notify = function(msg)
      table.insert(notified, msg)
    end
    actions._open_clone_diff(group.locations)
    vim.notify = real_notify

    eq("diff: new tab", #vim.api.nvim_list_tabpages(), tabs_before + 1)
    local wins = vim.api.nvim_tabpage_list_wins(0)
    eq("diff: two windows", #wins, 2)
    local diffs, names = 0, {}
    for _, win in ipairs(wins) do
      if vim.wo[win].diff then
        diffs = diffs + 1
      end
      table.insert(names, vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)))
      eq("diff: cursor at instance start", vim.api.nvim_win_get_cursor(win)[1], 1)
    end
    eq("diff: both in diff mode", diffs, 2)
    ok("diff: two different files", names[1] ~= names[2], vim.inspect(names))
    ok("diff: extra instance named", (notified[1] or ""):match("1 more instance") ~= nil, vim.inspect(notified))

    vim.cmd("tabclose")
    vim.cmd("cd " .. fixture)
    next_step()
  end)
end)

-- 16. Cycle chain in the K detail float.
table.insert(steps, function(next_step)
  local fixture = vim.fn.getcwd()
  local health_dir = repo .. "/tests/fixture-health"
  vim.cmd("enew")
  vim.cmd("cd " .. health_dir)
  require("vallow").setup({})

  require("vallow.runner").run(function(results)
    eq("cycle: found", count(results, "circular_deps"), 1)
    local item = results.findings.circular_deps.items[1]
    eq("cycle: two edges", #(item.edges or {}), 2)
    ok("cycle: edge path absolute", (item.edges[1].path or ""):sub(1, 1) == "/", vim.inspect(item.edges[1]))

    local lines = require("vallow.panel.actions")._detail_lines(item)
    ok("cycle: heading", has_line(lines, "  Cycle"), vim.inspect(lines))
    ok("cycle: first hop", has_line(lines, "src/a%.ts:%d+ → src/b%.ts"), vim.inspect(lines))
    ok("cycle: closes the loop", has_line(lines, "src/b%.ts:%d+ → src/a%.ts"), vim.inspect(lines))
    ok("cycle: suggestions kept", has_line(lines, "  Suggestions"), vim.inspect(lines))

    local plain = require("vallow.panel.actions")._detail_lines({ relative_path = "src/a.ts", lnum = 3 })
    ok("cycle: no chain without edges", not has_line(plain, "  Cycle"), vim.inspect(plain))

    vim.cmd("cd " .. fixture)
    next_step()
  end)
end)

-- 17. Peek highlights the whole range of a clone instance or a function.
table.insert(steps, function(next_step)
  local fixture = vim.fn.getcwd()
  local health_dir = repo .. "/tests/fixture-health"
  vim.cmd("enew")
  vim.cmd("cd " .. health_dir)
  require("vallow").setup({})

  require("vallow.runner").run(function(results)
    local actions = require("vallow.panel.actions")
    local render = require("vallow.panel.render")
    local peek_ns = vim.api.nvim_create_namespace("vallow_peek")

    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].vallow_open_cats = { clone_groups = true, health_complexity = true }
    render.render(buf, results, nil)
    vim.api.nvim_win_set_buf(0, buf)

    -- Find a row whose item spans more than one line, and a single-line row.
    local ranged_line, plain_line, ranged
    for lnum, entry in pairs(render.get_line_map(buf)) do
      if type(entry) == "table" and not entry._type and entry.path and entry.path ~= "" then
        if entry.end_lnum and entry.end_lnum > entry.lnum then
          ranged_line, ranged = lnum, entry
        elseif not entry.end_lnum then
          plain_line = lnum
        end
      end
    end
    ok("peek: ranged row found", ranged ~= nil, "no row with an end line")

    vim.api.nvim_win_set_cursor(0, { ranged_line, 0 })
    actions.peek(buf)
    local fbuf = vim.fn.bufnr(ranged.path)
    local marks = vim.api.nvim_buf_get_extmarks(fbuf, peek_ns, 0, -1, { details = true })
    eq("peek: one mark per line", #marks, ranged.end_lnum - ranged.lnum + 1)
    eq("peek: range highlight", marks[1] and marks[1][4].line_hl_group, "Visual")
    eq("peek: starts at the instance", marks[1] and marks[1][2] + 1, ranged.lnum)
    vim.api.nvim_buf_clear_namespace(fbuf, peek_ns, 0, -1)

    if plain_line then
      local plain = render.get_line_map(buf)[plain_line]
      vim.api.nvim_win_set_cursor(0, { plain_line, 0 })
      actions.peek(buf)
      local pbuf = vim.fn.bufnr(plain.path)
      local pmarks = vim.api.nvim_buf_get_extmarks(pbuf, peek_ns, 0, -1, { details = true })
      eq("peek: single line stays one mark", #pmarks, 1)
      ok(
        "peek: single line uses CurSearch",
        pmarks[1] and pmarks[1][4].hl_group == "CurSearch",
        vim.inspect(pmarks[1])
      )
      vim.api.nvim_buf_clear_namespace(pbuf, peek_ns, 0, -1)
    end

    render.clear(buf)
    vim.cmd("cd " .. fixture)
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
