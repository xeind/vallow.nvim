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
