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
  local cfg = require("vallow.config").get()
  local cmd = cfg.fallow_cmd
  if vim.fn.executable(cmd) == 1 then
    local version = vim.fn.system(cmd .. " --version 2>&1"):gsub("\n", "")
    vim.health.ok(("fallow: %s"):format(version))
  else
    vim.health.error(("fallow not found (%q) — install with: npm i -g fallow"):format(cmd))
  end

  -- package.json / .fallowrc.json reachable from cwd
  local root = require("vallow.runner").find_root()
  if root then
    vim.health.ok(("project root: %s"):format(vim.fn.fnamemodify(root, ":~")))
  else
    vim.health.warn("No package.json or .fallowrc.json found from cwd — fallow requires a JS/TS project")
  end

  -- fallow-lsp (optional, for LSP integration)
  if vim.fn.executable("fallow-lsp") == 1 then
    local v = vim.fn.system("fallow-lsp --version 2>&1"):gsub("\n", "")
    vim.health.ok(("fallow-lsp: %s (LSP diagnostics + code actions available)"):format(v))
  else
    vim.health.ok("fallow-lsp not found — install fallow to enable LSP integration (optional)")
  end
end

return M
