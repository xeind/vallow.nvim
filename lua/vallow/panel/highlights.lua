local M = {}

-- Read a group's resolved colors and add bold on top.
-- This is the pattern used by neo-tree/trouble for "link + bold" combos:
-- it re-reads the live theme on every ColorScheme so nothing is snapshot.
local function with_bold(group)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  local attrs  = (ok and type(hl) == "table") and vim.tbl_extend("keep", {}, hl) or {}
  attrs.link   = nil   -- strip residual link field so nvim_set_hl doesn't chain
  attrs.bold   = true
  return attrs
end

local function apply()
  local defs = {
    -- ── Window chrome ───────────────────────────────────────────────────
    -- Pure links to Neovim's own float/ui groups — present since nvim 0.8,
    -- defined by every colorscheme, always stay live without re-reading.
    VallowHeader  = { link = "Title"           },
    VallowBorder  = { link = "FloatBorder"     },
    VallowKind    = { link = "Comment"         },
    VallowFooter  = { link = "Comment"         },
    VallowLoading = { link = "WarningMsg"      },
    VallowError   = { link = "DiagnosticError" },

    -- ── Semantic ────────────────────────────────────────────────────────
    -- Pure links: no bold/italic needed, so we let the live theme do the work.
    -- Canonical mappings from folke/trouble, folke/snacks, telescope, neo-tree:
    --
    --   Title      — bold heading color, present in every colorscheme
    --   Directory  — file/path color (blue in ~every dark theme)
    --   Function   — distinct accent for names/symbols
    --   Number     — numeric color (yellow/orange in ~every dark theme)
    VallowSection = { link = "Title"     },
    VallowPath    = { link = "Directory" },
    VallowName    = { link = "Function"  },
    VallowCount   = { link = "Number"    },

    -- Type names (duplicate-export symbols, type labels): Type color + bold.
    -- with_bold() re-reads "Type" fg/bg live on each ColorScheme event.
    VallowSymbol  = with_bold("Type"),

    -- ── Severity ────────────────────────────────────────────────────────
    -- Neovim diagnostic groups exist since nvim 0.6.
    VallowSevError = { link = "DiagnosticError" },
    VallowSevWarn  = { link = "DiagnosticWarn"  },
    VallowSevHint  = { link = "DiagnosticHint"  },

    -- ── Tab strip ───────────────────────────────────────────────────────
    VallowTabActive   = { link = "TabLineSel"  },
    VallowTabInactive = { link = "TabLine"     },
    VallowTabSep      = { link = "TabLineFill" },
  }

  for name, opts in pairs(defs) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

M.setup = function()
  apply()

  -- Kill treesitter / syntax on vallow buffers AFTER plugins attach.
  -- FileType fires after nvim-treesitter's own handler, so this wins.
  vim.api.nvim_create_autocmd("FileType", {
    pattern  = "vallow",
    group    = vim.api.nvim_create_augroup("VallowNoSyntax", { clear = true }),
    callback = function(ev)
      vim.bo[ev.buf].syntax = ""
      pcall(vim.treesitter.stop, ev.buf)
    end,
  })

  -- Re-apply on colorscheme change so with_bold() picks up new theme colors.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("VallowHighlights", { clear = true }),
    callback = apply,
  })
end

-- Severity → highlight group (used by render.lua)
M.sev_hl = {
  error = "VallowSevError",
  warn  = "VallowSevWarn",
  hint  = "VallowSevHint",
}

return M
