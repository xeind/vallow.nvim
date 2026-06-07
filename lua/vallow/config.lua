local M = {}

M.defaults = {
  fallow_cmd  = "fallow",
  fallow_args = {},  -- extra args, e.g. {"--score", "--hotspots", "--targets"}

  statusline = {
    prefix = "vallow ",  -- change to " " for Nerd Font icon
  },

  window = {
    position = "right",
    size     = 0.5,
  },

  sections = {
    unused_code  = { label = "UNUSED CODE",  order = 1 },
    issues       = { label = "ISSUES",       order = 2 },
    duplicates   = { label = "DUPLICATES",   order = 3 },
    health       = { label = "HEALTH",       order = 4 },
    architecture = { label = "ARCHITECTURE", order = 5 },
  },

  -- severity: "error" | "warn" | "hint"
  -- sources: list of findings keys to merge into this display category
  categories = {
    -- UNUSED CODE (dead code — hint severity)
    unused_exports  = { icon = "󰘍", label = "Unused Exports", section = "unused_code", order = 1, severity = "hint" },
    unused_files    = { icon = "󰈔", label = "Unused Files",   section = "unused_code", order = 2, severity = "hint" },
    unused_types    = { icon = "T",  label = "Unused Types",   section = "unused_code", order = 3, severity = "hint" },
    unused_members  = { icon = "•",  label = "Unused Members", section = "unused_code", order = 4, severity = "hint",
                        sources = { "unused_enum_members", "unused_class_members" } },
    unused_all_deps = { icon = "󰒓", label = "Dependencies",   section = "unused_code", order = 5, severity = "hint",
                        sources = { "unused_deps", "unused_dev_deps", "unused_optional_deps" } },
    unlisted_deps   = { icon = "󰌶", label = "Unlisted Deps",  section = "unused_code", order = 6, severity = "warn" },
    -- ISSUES (actual bugs — error/warn severity)
    unresolved_imports = { icon = "󰌶", label = "Unresolved Imports", section = "issues", order = 1, severity = "error" },
    circular_deps      = { icon = "󰑷", label = "Circular Deps",      section = "issues", order = 2, severity = "warn"  },
    duplicate_exports  = { icon = "󰏗", label = "Duplicate Exports",  section = "issues", order = 3, severity = "warn"  },
    -- DUPLICATES
    clone_groups = { icon = "󰏗", label = "Clone Groups", section = "duplicates", order = 1, severity = "hint" },
    -- HEALTH
    health_complexity = { icon = "ƒ",  label = "Complexity",         section = "health", order = 1, severity = "warn" },
    health_hotspots   = { icon = "󱐋", label = "Hotspot Candidates", section = "health", order = 2, severity = "hint" },
    health_targets    = { icon = "↑",  label = "Refactoring",        section = "health", order = 3, severity = "hint" },
    -- ARCHITECTURE
    boundary_violations = { icon = "󰑷", label = "Boundary Violations", section = "architecture", order = 1, severity = "error" },
  },

  -- Max items shown per category before a "N more…" expand row appears.
  -- Press <Tab> or <CR> on the "more" row to show all.
  max_items = 30,

  -- Inline diagnostics in open buffers (like LSP hints)
  diagnostics = {
    enabled   = true,
    severity  = vim.diagnostic.severity.HINT,  -- severity for unused export hints
  },

  keymaps = {
    close        = "q",
    jump         = "<CR>",
    refresh      = "r",
    toggle_fold  = nil,       -- no default: za/zo/zc are always available
    next_section = "]c",
    prev_section = "[c",
    next_tab     = "L",
    prev_tab     = "H",
    filter       = "f",
    clear_filter = "F",
    pick         = "gf",
  },
}

M.options = {}

local function deep_merge(target, source)
  local result = vim.deepcopy(target)
  for k, v in pairs(source or {}) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

function M.setup(opts)
  M.options = deep_merge(M.defaults, opts or {})
end

function M.get()
  if next(M.options) == nil then return M.defaults end
  return M.options
end

return M
