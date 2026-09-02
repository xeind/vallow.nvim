local M = {}

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
