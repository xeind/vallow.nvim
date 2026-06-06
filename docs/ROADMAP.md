# vallow.nvim — Improvement Roadmap

## Phase 1 — Polish (current sprint)

### 1. `?` Help Popup
**File:** `lua/vallow/panel/actions.lua` + new `lua/vallow/panel/help.lua`
**Keymap:** `?`
**Behavior:** Opens a centered floating window listing all active keybinds. Closes with `q`, `?`, or `<Esc>`. Reads from `cfg.keymaps` so it's always in sync.

```
╭─────────── Vallow Help ────────────╮
│                                     │
│  Navigation                         │
│  <CR>      jump to file             │
│  o         open in split            │
│  v         open in vsplit           │
│  t         open in new tab          │
│  P         preview (float)          │
│  ]c / [c   next / prev section      │
│                                     │
│  Folds                              │
│  za / <Tab>  toggle fold            │
│  zo          open fold              │
│  zc          close fold             │
│  zR          open all               │
│  zM          close all              │
│                                     │
│  Actions                            │
│  r         refresh                  │
│  f         filter                   │
│  F         clear filter             │
│  gf        open picker              │
│  Q         send to quickfix         │
│  y         yank path:line           │
│  q         close panel              │
│                                     │
╰─────────────────────────────────────╯
```

**Implementation:**
- `help.lua` builds lines from a hardcoded sections table (not dynamic from cfg — cleaner layout)
- `vim.api.nvim_open_win` centered float, `style = "minimal"`, `border = "rounded"`
- Single keymap `q` / `?` / `<Esc>` closes it
- Called from `actions.setup(buf)` via `map("?", ...)`

---

### 2. Multiple Jump Modes
**File:** `lua/vallow/panel/actions.lua`
**Keymaps:** `o` split, `v` vsplit, `t` tab
**Behavior:** Same as `<CR>` jump but opens the file differently. Does NOT close panel.

```lua
-- Current (only mode):
<CR>  →  edit {path}          -- replaces current file in prev window

-- New:
o    →  split {path}          -- horizontal split in prev window area
v    →  vsplit {path}         -- vertical split in prev window area
t    →  tabedit {path}        -- new tab
```

**Implementation:**
- Extract `M._do_jump(item, cmd)` from existing `M.jump`
- `cmd` is `"edit"` / `"split"` / `"vsplit"` / `"tabedit"`
- `wincmd p` before opening (to land in the right window area)
- For `tabedit`, skip `wincmd p` since it opens in a new tab anyway
- Add to `actions.setup`: `map("o", ...) map("v", ...) map("t", ...)`

---

### 3. Quickfix Export
**File:** `lua/vallow/panel/actions.lua`
**Keymap:** `Q`
**Behavior:** Dumps all visible findings (respecting active filter) into Vim's quickfix list, then opens it with `:copen`.

```
|| vallow: unused export   mobile/features/auth/hooks/useAuth.ts|12| useRegister
|| vallow: unused export   mobile/features/auth/hooks/useAuth.ts|15| useLogin
|| vallow: unused file     mobile/legacy/old-utils.ts|1|
```

**Implementation:**
```lua
M.send_to_qf = function(results, filter_query)
  local items = {}
  -- iterate all finding buckets
  -- for each item: { filename, lnum, col, text = "cat_label: name" }
  vim.fn.setqflist({}, "r", { title = "Vallow", items = items })
  vim.cmd("copen")
end
```
- Respects active `vim.b[buf].vallow_filter` — only exports what's visible
- `setqflist({}, "r", ...)` replaces the list (not appends) each time
- Title shows `Vallow [filter: auth]` when filter is active
- After `copen`, focus stays in qf list (standard Vim behavior)
- Users then get `:cn`/`:cp`, `]q`/`[q`, trouble.nvim qf mode, etc. for free

---

### 4. Yank Path
**File:** `lua/vallow/panel/actions.lua`
**Keymap:** `y`
**Behavior:** Copies `relative_path:lnum` of item under cursor to system clipboard (`+` register). Shows a brief notification.

```
-- On an item row:
y  →  yanks "mobile/features/auth/hooks/useAuth.ts:12"

-- On a category/section header:
y  →  yanks nothing (shows "nothing to yank" notification)
```

**Implementation:**
```lua
M.yank_path = function(buf)
  local item = M._item_at_cursor(buf)
  if not item or item._type then  -- skip headers
    vim.notify("vallow: nothing to yank", vim.log.levels.INFO)
    return
  end
  local text = (item.relative_path or item.path or "")
  if item.lnum then text = text .. ":" .. item.lnum end
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify('vallow: yanked "' .. text .. '"', vim.log.levels.INFO)
end
```

---

### 5. Architecture Boundaries Section
**Files:** `lua/vallow/runner.lua`, `lua/vallow/config.lua`, `lua/vallow/panel/highlights.lua`
**Behavior:** New 4th section in the panel for architecture violations.

```
▼ ARCHITECTURE                    8
  ▶ 󰑷 Boundary Violations         8
```

When expanded:
```
  ▼ 󰑷 Boundary Violations         8
      src/components/Button.tsx:3   src/api/database   Frontend
      src/pages/Home.tsx:8          src/domain/auth    Pages
```
Columns: `file:line`, `imported_path`, `boundary_name`

**runner.lua changes:**
- Add `boundary_violations = { count = 0, items = {} }` to `_empty_findings()`
- Normalize `check.boundary_violations[]`:
  ```lua
  { path, relative_path, lnum, col, import_path, boundary_name }
  ```

**config.lua changes:**
- New section: `architecture = { label = "ARCHITECTURE", order = 4 }`
- New category: `boundary_violations = { icon = "󰑷", label = "Boundary Violations", section = "architecture", order = 1 }`

**render.lua changes:**
- New branch in `_render_items` for `"boundary_violations"`:
  ```
  path:lnum   import_path   boundary_name
  ```

**highlights.lua changes:**
- Add `VallowIconBoundary = { link = "DiagnosticError" }`
- Add `boundary_violations = "VallowIconBoundary"` to `icon_hl`

---

### 6. Statusline Component
**File:** `lua/vallow/init.lua` (expose public API)
**Usage:**
```lua
-- lualine
{ require("vallow").statusline }

-- manual statusline
vim.o.statusline = "%{%v:lua.require('vallow').statusline()%}"
```

**Output examples:**
```
" 1202"          -- neutral, issues exist
" 0"             -- clean (could use different color)
" ..."           -- analysis running
""               -- fallow not run yet / panel never opened
```

**Implementation:**
```lua
-- lua/vallow/init.lua
M.statusline = function()
  local state = require("vallow.panel").state
  if not state.results then return "" end
  if state.results._loading then return "  …" end
  if state.results.error then return "  !" end
  local total = 0
  for _, b in pairs(state.results.findings or {}) do
    if type(b) == "table" and b.count then
      total = total + b.count
    end
  end
  return "  " .. total
end

-- Also expose for lualine component
M.get_counts = function()
  local state = require("vallow.panel").state
  if not state.results or not state.results.findings then
    return { total = 0, loading = false }
  end
  local total = 0
  for _, b in pairs(state.results.findings or {}) do
    if type(b) == "table" and b.count then total = total + b.count end
  end
  return { total = total, loading = state.results._loading or false }
end
```

**Lualine integration example (for README):**
```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      { require("vallow").statusline, color = { fg = "#f9c74f" } }
    }
  }
})
```

---

## Phase 2 — Power Features (next sprint)

### Baseline workflow
- `:VallowBaseline` — save current counts to `~/.local/share/vallow/{project}.json`
- Subsequent runs pass `--baseline` flag
- Footer shows `+3 new  -12 fixed since baseline`
- `:VallowBaseline clear` removes it

### Audit mode
- `:VallowAudit` or `A` key — runs `fallow audit --format json`
- Shows only findings in changed files (vs `main`)
- Panel header: `VALLOW AUDIT  ✓ pass` / `✗ fail` / `⚠ warn`
- Same panel structure, different data source

### Fix from panel
- `x` on item → `fallow fix --dry-run` for that file → show diff in split below
- `y`/`n` in diff view to apply or cancel
- Risk: writes to files, needs careful confirmation UX

### Auto-refresh on save
- `auto_refresh = false` config option
- When `true`: `BufWritePost` on `*.ts`, `*.tsx`, `*.js`, `*.jsx` triggers debounced refresh
- Debounce: 2000ms (configurable)
- Shows loading state in panel while re-running

### Group by file mode
- `g` key toggles between "by category" (current) and "by file" views
- By file: each file is a header, all its issues nested under it
- Better for fixing one file at a time
- State persists per panel session

### Preview float
- `P` key on item → floating window showing file context around `lnum`
- 15 lines of context centered on the finding
- Updates as cursor moves through items
- `P` again or moving away closes it

---

## Keybind Summary (after Phase 1)

| Key | Action |
|---|---|
| `<CR>` | Jump to file (edit) |
| `o` | Jump: horizontal split |
| `v` | Jump: vertical split |
| `t` | Jump: new tab |
| `za` / `<Tab>` | Toggle fold |
| `zo` | Open fold |
| `zc` | Close fold |
| `zR` | Open all |
| `zM` | Close all |
| `]c` / `[c` | Next / prev section |
| `r` | Refresh |
| `f` | Filter (inline search bar) |
| `F` | Clear filter |
| `gf` | Open picker (telescope/fzf-lua) |
| `Q` | Send to quickfix list |
| `y` | Yank path:line to clipboard |
| `q` | Close panel |
| `?` | Show help popup |
