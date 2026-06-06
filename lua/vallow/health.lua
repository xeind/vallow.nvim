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
    vim.health.error(
      ("fallow not found (%q) — install with: npm i -g fallow"):format(cmd)
    )
  end

  -- package.json reachable from cwd
  local pkg = vim.fn.findfile("package.json", vim.fn.getcwd() .. ";")
  if pkg ~= "" then
    vim.health.ok(("package.json: %s"):format(vim.fn.fnamemodify(pkg, ":~")))
  else
    vim.health.warn("No package.json found from cwd — fallow requires a JS/TS project")
  end
end

return M
