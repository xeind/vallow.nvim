# vallow.nvim — Fallow CLI Wrapper Plan

A Neovim panel plugin that wraps the `fallow` CLI to show unused code, duplicate
exports, and dependency issues. The plugin is **pure UI** — fallow does the analysis.

## Why this approach

The existing PLAN.md reimplements fallow's analysis engine in Lua (tree-sitter
queries, import resolution, dependency graph). That is months of work and will
produce worse results than fallow itself.

This plan wraps the fallow CLI instead — same approach Zed took with `fallow-lsp`.
fallow handles the hard parts (tsconfig paths, barrel files, monorepos, re-exports).
The plugin handles the Neovim UI.

**Tradeoff:** Requires `fallow` installed. Only analyzes TS/JS (fallow's scope).

---

## Architecture

```
:Vallow
   │
   ▼
runner.lua
   │  vim.fn.jobstart("fallow --format json")  (async, non-blocking)
   │  vim.schedule → JSON decode → output contract (Lua table)
   ▼
panel/render.lua
   │  Writes to scratch buffer (buftype=nofile)
   │  Extmarks for highlights
   │  line→item map for navigation
   ▼
panel/actions.lua
   │  <CR> → jump to file:line in previous window
   │  r    → re-run fallow
   │  q    → close panel
   │  tab  → fold/unfold category
```

---

## File Tree

```
vallow.nvim/
├── lua/vallow/
│   ├── init.lua          Public API: setup(), toggle(), refresh()
│   ├── config.lua        Defaults + deep merge
│   ├── health.lua        :checkhealth vallow (is fallow in PATH?)
│   ├── runner.lua        Async fallow execution + JSON → output contract
│   └── panel/
│       ├── init.lua      open/close/toggle/refresh lifecycle + state
│       ├── window.lua    Create/destroy split buffer
│       ├── render.lua    Populate buffer: tree, extmarks, folds
│       ├── actions.lua   Keymaps: jump, refresh, close, fold
│       └── highlights.lua  :highlight groups, ColorScheme autocmd
├── plugin/
│   └── vallow.lua        :Vallow, :VallowRefresh commands
├── doc/
│   └── vallow.nvim.txt
└── README.md
```

~600 LOC total.

---

## Output Contract

The runner normalizes fallow's JSON into this shape.
The panel only knows about this — not fallow's raw JSON format.

```lua
---@class VallowResults
---@field repo_root string
---@field duration_ms integer
---@field findings VallowFindings
---@field error string?   Set if fallow failed or is not installed

---@class VallowFindings
---@field unused_exports  VallowCategory
---@field unused_files    VallowCategory
---@field duplicate_exports VallowCategory
---@field unused_deps     VallowCategory
---@field missing_deps    VallowCategory

---@class VallowCategory
---@field count integer
---@field items VallowItem[]

---@class VallowItem
---@field path string           Absolute path
---@field relative_path string  Path relative to repo_root
---@field lnum integer?         1-indexed
---@field col integer?          0-indexed
---@field name string?          Export/symbol name
---@field kind string?          "function"|"class"|"type"|"const"|etc
---@field reason string?        Why it's flagged
---@field locations VallowItem[]? For duplicates: all locations
```

---

## Module Specs

### `runner.lua`

Runs fallow commands and normalizes their output into the contract above.

```lua
-- Runs fallow asynchronously. Calls callback(results: VallowResults).
-- Uses a generation counter to discard stale results.
M.run = function(opts, callback)
  -- 1. Determine workspace root (find .git / package.json upward from cwd)
  -- 2. Build command:
  --    { "fallow", "--format", "json" }  -- runs all checks at once
  --    OR per-command if fallow doesn't have a combined mode:
  --    run dead-code + dupes in parallel, merge results
  -- 3. vim.fn.jobstart(cmd, { on_stdout, on_stderr, on_exit })
  -- 4. Accumulate stdout chunks, JSON decode on exit
  -- 5. Normalize JSON → output contract
  -- 6. vim.schedule → callback(results)
end

-- Detect workspace root
M.find_root = function()
  -- Walk up from vim.fn.getcwd() looking for .git, package.json
  -- Return first match or cwd as fallback
end

-- Normalize raw fallow JSON → output contract
M.normalize = function(raw)
  -- Map fallow's JSON fields to our contract
  -- Handle missing fields gracefully (different fallow versions)
end
```

**Commands to run:**
```sh
fallow dead-code --format json   # unused files, unused exports, unused types
fallow dupes --format json       # duplicate exports
fallow health --format json      # unused deps (package.json)
```

Or if fallow supports a combined command:
```sh
fallow --format json             # all checks
```

Verify which works: `fallow --help`

### `panel/init.lua`

```lua
M.state = {
  buf = nil,
  win = nil,
  results = nil,
  loading = false,
  gen = 0,
}

M.open = function()    end  -- create window + run analysis
M.close = function()   end  -- destroy window
M.toggle = function()  end  -- open if closed, close if open
M.refresh = function() end  -- re-run fallow, re-render
```

### `panel/window.lua`

Creates a split buffer. Position configurable (bottom/top/left/right).

```lua
M.create = function(cfg)
  local buf = vim.api.nvim_create_buf(false, true)  -- scratch, unlisted
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "vallow"
  -- Open split at configured position + size
  -- Register BufWipeout autocmd to clean state
end
```

### `panel/render.lua`

Writes results into the buffer. Stores a line→item map for actions.

```lua
-- Panel layout:
--
-- VALLOW                              127ms
-- ──────────────────────────────────────────
-- ▼ Unused Exports                      (7)
--    src/utils.ts       deadFn      function
--    src/utils.ts       oldHelper   function
--    src/types.ts       OldType     type
-- ▶ Unused Files                        (3)
-- ▶ Duplicate Exports                   (2)
-- ▶ Unused Dependencies                 (1)
-- ──────────────────────────────────────────
-- 13 issues across 4 categories

M.render = function(buf, results)
  -- 1. Set modifiable=true, clear buffer
  -- 2. Write header
  -- 3. For each category (config order):
  --    a. Header line: "▼ Category Name (N)" or "▶ ..." if folded
  --    b. Item lines: path | name | kind (column-aligned)
  -- 4. Write footer
  -- 5. Apply extmarks (highlights per column)
  -- 6. Store line→item map: vim.b[buf].vallow_line_map = { [lnum] = item }
  -- 7. Set modifiable=false
end

-- Column widths: calculate from longest values, cap at window width
M.calc_widths = function(items, win_width) end
```

### `panel/actions.lua`

```lua
M.jump = function()
  local item = M.item_at_cursor()
  if not item then return end
  -- Focus previous window
  vim.cmd("wincmd p")
  -- Open file
  vim.cmd("edit " .. vim.fn.fnameescape(item.path))
  -- Set cursor
  if item.lnum then
    vim.api.nvim_win_set_cursor(0, { item.lnum, item.col or 0 })
    -- Brief highlight on target line
    vim.highlight.on_yank({ higroup = "Search", timeout = 300 })
  end
end

M.item_at_cursor = function()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return vim.b.vallow_line_map and vim.b.vallow_line_map[lnum]
end
```

### `config.lua`

```lua
M.defaults = {
  -- Fallow binary name (override if installed elsewhere)
  fallow_cmd = "fallow",

  -- Window layout
  window = {
    position = "bottom",  -- "bottom"|"top"|"left"|"right"
    size = 0.3,           -- fraction of editor
    border = "rounded",
  },

  -- Category display (order + icons)
  categories = {
    unused_exports =    { icon = "󰘍", label = "Unused Exports",      order = 1 },
    unused_files =      { icon = "󰈔", label = "Unused Files",         order = 2 },
    duplicate_exports = { icon = "󰏗", label = "Duplicate Exports",    order = 3 },
    unused_deps =       { icon = "󰒓", label = "Unused Dependencies",  order = 4 },
    missing_deps =      { icon = "󰌶", label = "Missing Dependencies", order = 5 },
  },

  -- Keymaps inside the panel buffer
  keymaps = {
    jump         = "<CR>",
    refresh      = "r",
    close        = "q",
    toggle_fold  = "<Tab>",
    next_item    = "j",
    prev_item    = "k",
    next_section = "]c",
    prev_section = "[c",
  },
}
```

---

## Build Phases

### Phase 1 — Skeleton (~100 LOC)
- `lua/vallow/init.lua` + `lua/vallow/config.lua` + `plugin/vallow.lua`
- Verify: `:Vallow` doesn't crash. `require("vallow").setup()` works.

### Phase 2 — Runner (~150 LOC)
- `lua/vallow/runner.lua`
- Verify: Open a TS project, call runner, print raw results to `:messages`.
- Confirm JSON fields map correctly.

### Phase 3 — Panel window (~100 LOC)
- `lua/vallow/panel/window.lua` + `lua/vallow/panel/init.lua` (skeleton)
- Verify: `:Vallow` opens a split. `q` closes it.

### Phase 4 — Render (~200 LOC)
- `lua/vallow/panel/render.lua`
- Verify: Panel shows results grouped by category, column-aligned.
- Fold/unfold works with `<Tab>`.

### Phase 5 — Actions + Highlights (~100 LOC)
- `lua/vallow/panel/actions.lua` + `lua/vallow/panel/highlights.lua`
- Verify: `<CR>` jumps to correct file:line. Brief flash on target line.

### Phase 6 — Health + Polish
- `lua/vallow/health.lua`: `:checkhealth vallow` reports fallow install status
- Loading indicator ("Analyzing..." while fallow runs)
- Error state (fallow not found, no package.json, etc.)

---

## lazy.nvim install

```lua
{
  "yourusername/vallow.nvim",
  cmd = { "Vallow", "VallowRefresh" },
  keys = {
    { "<leader>va", "<cmd>Vallow<cr>", desc = "Vallow: toggle panel" },
    { "<leader>vr", "<cmd>VallowRefresh<cr>", desc = "Vallow: refresh" },
  },
  opts = {
    window = { position = "bottom", size = 0.35 },
  },
}
```

---

## Requires

- Neovim >= 0.9
- `fallow` CLI installed (`npm i -g fallow-cli` or `cargo install fallow-cli`)
- A TS/JS project (package.json in root or parent)
