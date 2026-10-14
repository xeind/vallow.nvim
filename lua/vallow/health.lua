local M = {}

local DOCTOR_TIMEOUT_MS = 30000
local LEVELS = { pass = "ok", warn = "warn", fail = "error", skipped = "info" }

-- Map `fallow doctor --format json` output to a list of { level, message }.
-- Unknown statuses and malformed entries are skipped.
function M._doctor_report(data)
  local reports = {}
  if type(data) ~= "table" or type(data.checks) ~= "table" then
    return reports
  end
  for _, check in ipairs(data.checks) do
    local level = type(check) == "table" and LEVELS[check.status]
    if level then
      local message = ("%s: %s"):format(tostring(check.id or "check"), tostring(check.message or ""))
      local remediation = type(check.remediation) == "table" and check.remediation.command
      if remediation and level ~= "ok" then
        message = ("%s (run: %s)"):format(message, remediation)
      end
      reports[#reports + 1] = { level = level, message = message }
    end
  end
  return reports
end

-- Run `fallow doctor` synchronously in root. Exit code 2 (a required check
-- failed) is a result. Returns the decoded table, or nil and a reason.
function M._run_doctor(cmd, root)
  local ok, proc = pcall(vim.system, { cmd, "doctor", "--format", "json", "--quiet" }, { cwd = root, text = true })
  if not ok then
    return nil, tostring(proc)
  end
  local res = proc:wait(DOCTOR_TIMEOUT_MS)
  if res.code == 124 or res.signal ~= 0 then
    return nil, "timed out"
  end
  local decoded, data = pcall(vim.json.decode, res.stdout or "")
  if not decoded or type(data) ~= "table" or data.kind ~= "doctor" then
    return nil, "no doctor output (exit " .. tostring(res.code) .. ")"
  end
  return data
end

local function doctor_supported(version)
  local major, minor = version:match("(%d+)%.(%d+)%.%d+")
  major, minor = tonumber(major), tonumber(minor)
  return major ~= nil and (major > 3 or (major == 3 and minor >= 23))
end

function M.check()
  vim.health.start("vallow.nvim")

  -- Neovim version
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok(("Neovim %d.%d"):format(vim.version().major, vim.version().minor))
  else
    vim.health.error("Neovim >= 0.10 required")
    return
  end

  -- fallow binary
  local runner = require("vallow.runner")
  local root = runner.find_root()
  local install = require("vallow.install")
  local cmd, source = runner.resolve_cmd(root)
  if cmd then
    local version = vim.fn.system(vim.fn.shellescape(cmd) .. " --version 2>&1"):gsub("\n", "")
    local found = ("fallow: %s (%s: %s)"):format(version, source, cmd)
    local major, minor, patch = version:match("(%d+)%.(%d+)%.(%d+)")
    local want = { install.MIN_VERSION:match("(%d+)%.(%d+)%.(%d+)") }
    local below = major
      and (
        tonumber(major) < tonumber(want[1])
        or (major == want[1] and tonumber(minor) < tonumber(want[2]))
        or (major == want[1] and minor == want[2] and tonumber(patch) < tonumber(want[3]))
      )
    if below then
      vim.health.warn(("%s — %s or newer recommended; run :VallowUpdate"):format(found, install.MIN_VERSION))
    else
      vim.health.ok(found)
    end
  else
    vim.health.error("fallow not found — run :VallowInstall, or install with: npm i -g fallow")
  end

  -- package.json / .fallowrc.json reachable from cwd
  if root then
    vim.health.ok(("project root: %s"):format(vim.fn.fnamemodify(root, ":~")))
  else
    vim.health.warn("No package.json or .fallowrc.json found from cwd — fallow requires a JS/TS project")
  end

  -- fallow doctor (fallow >= 3.23)
  if cmd and root then
    local version = vim.fn.system(vim.fn.shellescape(cmd) .. " --version 2>&1"):gsub("\n", "")
    if not doctor_supported(version) then
      vim.health.info("fallow doctor needs fallow 3.23 or newer; skipped")
    else
      local data, reason = M._run_doctor(cmd, root)
      if data then
        for _, r in ipairs(M._doctor_report(data)) do
          vim.health[r.level](r.message)
        end
      else
        vim.health.info("fallow doctor skipped: " .. reason)
      end
    end
  else
    vim.health.info("fallow doctor skipped: needs fallow and a project root")
  end

  -- fallow-lsp (optional, for LSP integration)
  local lsp = vim.fn.executable("fallow-lsp") == 1 and "fallow-lsp" or install.path("fallow-lsp")
  if vim.fn.executable(lsp) == 1 then
    local v = vim.fn.system(vim.fn.shellescape(lsp) .. " --version 2>&1"):gsub("\n", "")
    vim.health.ok(("fallow-lsp: %s (LSP diagnostics + code actions available)"):format(v))
  else
    vim.health.ok("fallow-lsp not found — run :VallowInstall lsp to enable LSP integration (optional)")
  end
end

return M
