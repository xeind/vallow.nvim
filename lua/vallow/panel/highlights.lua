local M = {}

local groups = {
  VallowHeader   = { link = "Title" },
  VallowSection  = { link = "Title", bold = true },
  VallowBorder   = { link = "FloatBorder" },
  VallowPath     = { link = "Directory" },
  VallowName     = { link = "Function" },
  VallowKind     = { link = "Comment" },
  VallowCount    = { link = "Special" },
  VallowFooter   = { link = "Comment" },
  VallowLoading  = { link = "WarningMsg" },
  VallowError    = { link = "DiagnosticError" },
  -- Severity groups — used for category icons and counts
  VallowSevError = { link = "DiagnosticError" },
  VallowSevWarn  = { link = "DiagnosticWarn"  },
  VallowSevHint  = { link = "DiagnosticHint"  },
}

M.setup = function()
  for name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, name, opts)
  end
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("VallowHighlights", { clear = true }),
    callback = function()
      for name, opts in pairs(groups) do
        vim.api.nvim_set_hl(0, name, opts)
      end
    end,
  })
end

-- Severity → highlight group (used by render.lua for icons and counts)
M.sev_hl = {
  error = "VallowSevError",
  warn  = "VallowSevWarn",
  hint  = "VallowSevHint",
}

return M
