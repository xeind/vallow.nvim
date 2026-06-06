# vallow.nvim

A code quality panel for Neovim. Surfaces unused exports, unused files,
duplicate code, dependency issues, complexity hotspots, and architecture
violations in a fast, navigable split — with one keypress to jump to any issue.

Powered by [fallow](https://github.com/fallow-rs/fallow) — a zero-config,
sub-second static analysis engine for JS/TS.

```
  VALLOW
  ──────────────────────────────────────────────────────────────────
  ▼ UNUSED CODE                                                   24
    ▼ 󰘍 Unused Exports                                            7
        src/utils.ts            formatDate          value
        src/utils.ts            oldHelper           value
        src/types.ts            LegacyUser          type
      ▶ 󰈔 Unused Files                                            3
      ▶ T  Unused Types                                           5
      ▶ •  Unused Members                                         9
  ▼ ISSUES                                                         2
      ▶ 󰌶 Unresolved Imports                                      1
      ▶ 󰑷 Circular Deps                                           1
  ──────────────────────────────────────────────────────────────────
  26 issues  312ms
```

---

## Requirements

- **Neovim** >= 0.10
- **[fallow](https://github.com/fallow-rs/fallow)** CLI — the analysis engine
- A **TypeScript or JavaScript** project with a `package.json`
- A **[Nerd Font](https://www.nerdfonts.com/)** for category icons (optional)

---

## Install fallow

vallow.nvim is a UI wrapper — fallow does the actual analysis. Install it once:

```sh
# npm — recommended
npm install -g fallow

# local to your project
npm install --save-dev fallow

# cargo
cargo install fallow
```

Verify it works:

```sh
fallow --version
fallow dead-code --format json | head -5
```

---

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim) (recommended)

```lua
{
  "yourusername/vallow.nvim",
  cmd = { "Vallow", "VallowRefresh", "VallowSearch" },
  keys = {
    { "<leader>va", "<cmd>Vallow<cr>",        desc = "Vallow: toggle" },
    { "<leader>vr", "<cmd>VallowRefresh<cr>", desc = "Vallow: refresh" },
    { "<leader>vs", "<cmd>VallowSearch<cr>",  desc = "Vallow: search findings" },
  },
  opts = {},
}
```

### [rocks.nvim](https://github.com/nvim-neorocks/rocks.nvim)

```vim
:Rocks install vallow.nvim
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'yourusername/vallow.nvim'
```

```lua
-- init.lua, after plug#end()
require("vallow").setup()
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yourusername/vallow.nvim",
  config = function()
    require("vallow").setup()
  end,
}
```

### [mini.deps](https://github.com/echasnovski/mini.deps)

```lua
MiniDeps.add("yourusername/vallow.nvim")
require("vallow").setup()
```

### Native packages (no plugin manager)

```sh
mkdir -p ~/.local/share/nvim/site/pack/plugins/start
cd ~/.local/share/nvim/site/pack/plugins/start
git clone https://github.com/yourusername/vallow.nvim
```

```lua
-- init.lua
require("vallow").setup()
```

---

## Quick start

Open any TypeScript or JavaScript project, then:

```
:Vallow
```

The panel opens, runs `fallow` in the background, and renders results.
Press `<CR>` on any issue to jump directly to the file and line.

---

## Commands

| Command | Description |
|---|---|
| `:Vallow` | Toggle the panel open / closed |
| `:VallowRefresh` | Re-run fallow and update the panel |
| `:VallowSearch` | Fuzzy search all findings (telescope / fzf-lua / vim.ui.select) |

---

## Panel keymaps

| Key | Action |
|---|---|
| `<CR>` | Jump to the issue (current window) |
| `o` | Jump in a horizontal split |
| `v` | Jump in a vertical split |
| `t` | Jump in a new tab |
| `<Tab>` / `za` | Toggle fold under cursor |
| `zo` / `zc` | Open / close fold |
| `zR` / `zM` | Open / close all folds |
| `r` | Re-run fallow (refresh) |
| `q` | Close the panel |
| `]c` / `[c` | Jump to next / previous section |
| `f` | Filter findings by path or name |
| `F` | Clear filter |
| `gf` | Fuzzy search all findings |
| `Q` | Send visible findings to quickfix |
| `y` | Yank path:line of item under cursor |
| `?` | Show keymap help |

All keymaps are configurable — see [Configuration](#configuration).

---

## Panel structure

Findings are organized into sections. Only sections with issues are shown.

| Section | Categories |
|---|---|
| **UNUSED CODE** | Unused Exports, Unused Files, Unused Types, Unused Members, Dependencies, Unlisted Deps |
| **ISSUES** | Unresolved Imports, Circular Deps, Duplicate Exports |
| **DUPLICATES** | Clone Groups |
| **HEALTH** | Complexity, Hotspot Candidates, Refactoring |
| **ARCHITECTURE** | Boundary Violations |

Severity is color-coded: errors (red), warnings (yellow), hints (grey).

---

## Configuration

Call `setup()` with any options you want to override. Everything has a default.

```lua
require("vallow").setup({
  -- fallow binary — change if not in PATH or using a local install
  fallow_cmd  = "fallow",
  fallow_args = {},  -- extra CLI flags, e.g. {"--score", "--hotspots"}

  window = {
    position = "right",  -- "bottom" | "top" | "left" | "right"
    size     = 0.5,      -- fraction of editor width (left/right) or height (top/bottom)
  },

  -- Max items shown per category before a "N more…" row appears.
  -- Press <Tab> or <CR> on the row to expand.
  max_items = 30,

  -- Inline diagnostics in open buffers (like LSP hints)
  diagnostics = {
    enabled  = true,
    severity = vim.diagnostic.severity.HINT,
  },

  -- Statusline integration (see below)
  statusline = {
    prefix = "vallow ",  -- change to " " for a Nerd Font icon
  },

  -- Keymaps inside the panel buffer
  keymaps = {
    close        = "q",
    jump         = "<CR>",
    refresh      = "r",
    toggle_fold  = "<Tab>",
    next_section = "]c",
    prev_section = "[c",
    filter       = "f",
    clear_filter = "F",
    pick         = "gf",
  },
})
```

### Local fallow install

```lua
require("vallow").setup({
  fallow_cmd = "./node_modules/.bin/fallow",
})
```

### Statusline integration

```lua
-- lualine
require("lualine").setup({
  sections = {
    lualine_x = {
      { require("vallow").statusline, color = { fg = "#f9c74f" } },
    },
  },
})

-- raw statusline
vim.o.statusline = "%{%v:lua.require('vallow').statusline()%}"
```

Displays `vallow 42` when issues exist, `vallow ✓` when clean, empty when not run.
Change the prefix via `setup({ statusline = { prefix = " " } })`.

---

## Health check

```
:checkhealth vallow
```

```
vallow.nvim
  OK  Neovim 0.10
  OK  fallow: fallow 2.89.0
  OK  package.json: ~/projects/my-app/package.json
```

Common issues it catches: `fallow` not in PATH, no `package.json` reachable
from the current directory.

---

## Highlight groups

vallow.nvim links all groups to standard Neovim groups by default,
so they work with any colorscheme.

```lua
vim.api.nvim_set_hl(0, "VallowHeader",   { fg = "#bb9af7", bold = true })
vim.api.nvim_set_hl(0, "VallowPath",     { fg = "#7aa2f7" })
vim.api.nvim_set_hl(0, "VallowName",     { fg = "#9ece6a", bold = true })
vim.api.nvim_set_hl(0, "VallowSevError", { fg = "#f7768e" })
vim.api.nvim_set_hl(0, "VallowSevWarn",  { fg = "#e0af68" })
vim.api.nvim_set_hl(0, "VallowSevHint",  { fg = "#565f89" })
```

| Group | Default | Used for |
|---|---|---|
| `VallowHeader` | `Title` | Panel title |
| `VallowSection` | `Title` bold | Section headers (UNUSED CODE, ISSUES…) |
| `VallowBorder` | `FloatBorder` | Separator lines |
| `VallowPath` | `Directory` | File paths |
| `VallowName` | `Function` | Export / symbol names |
| `VallowKind` | `Comment` | Kind labels (`value`, `type`) |
| `VallowCount` | `Special` | Section issue counts |
| `VallowFooter` | `Comment` | Footer (total + timing) |
| `VallowLoading` | `WarningMsg` | "Analyzing…" state |
| `VallowError` | `DiagnosticError` | Error state (fallow not found) |
| `VallowSevError` | `DiagnosticError` | Category icon/count — error severity |
| `VallowSevWarn` | `DiagnosticWarn` | Category icon/count — warn severity |
| `VallowSevHint` | `DiagnosticHint` | Category icon/count — hint severity |

---

## Configuring fallow

vallow.nvim passes your project root to fallow and lets it handle the rest.
fallow reads `.fallowrc.json` (or `.fallowrc.jsonc` / `fallow.toml`) from
your project root.

Create one with:

```sh
fallow init
```

Common options:

```json
{
  "$schema": "https://raw.githubusercontent.com/fallow-rs/fallow/main/schema.json",
  "entry": ["src/index.ts"],
  "ignorePatterns": ["**/*.test.ts", "dist/**"],
  "ignoreDependencies": ["typescript"],
  "rules": {
    "unused-export": "error",
    "unused-file": "warn",
    "circular-dependency": "warn"
  }
}
```

See the [fallow docs](https://github.com/fallow-rs/fallow) for the full
reference — workspace/monorepo support, architecture boundaries, complexity
thresholds, and 118 framework plugins (Next.js, Nuxt, Remix, Vite, etc).

### Suppression comments

Suppress specific findings inline without touching config:

```ts
// fallow-ignore-next-line unused-export
export function keepThisPublic() {}

// fallow-ignore-next-line unused-export, unused-type
export type LegacyShape = { id: string }

// fallow-ignore-file  ← suppress all findings in this file
```

---

## How it works

vallow.nvim is a thin UI wrapper. It shells out to fallow, parses the JSON
output, and renders it in a Neovim scratch buffer. No tree-sitter, no LSP,
no language parsing on the Neovim side — fallow handles all of that.

```
:Vallow
  └─ panel/init.lua        open split, show "Analyzing…"
       └─ runner.lua       vim.fn.jobstart("fallow --format json")  [async]
            └─ on_exit     JSON decode → normalize → output contract
                 └─ panel/render.lua    write lines + extmarks to buffer
                      └─ panel/actions.lua
                           <CR>   wincmd p → edit path → cursor → flash
                           r      re-run runner
                           q      close window
```

The panel buffer (`buftype=nofile`) never modifies your files.

---

## Contributing

Issues and PRs welcome.

```sh
git clone https://github.com/yourusername/vallow.nvim
cd vallow.nvim
```

Point lazy.nvim at your local clone for development:

```lua
{ dir = "~/path/to/vallow.nvim", opts = {} }
```

File layout:

```
lua/vallow/
  init.lua          Public API: setup, toggle, open, close, refresh, statusline
  config.lua        Defaults + deep merge
  health.lua        :checkhealth vallow
  runner.lua        Async fallow execution + JSON normalizer
  labels.lua        Shared bucket key → human label map
  diagnostics.lua   Inline LSP-style diagnostics from findings
  picker.lua        Telescope / fzf-lua / vim.ui.select integration
  panel/
    init.lua        Window lifecycle + state
    window.lua      Split buffer creation
    render.lua      Tree rendering + extmarks + severity highlights
    actions.lua     Keymaps: jump, fold, filter, quickfix, yank
    highlights.lua  Highlight group definitions
    help.lua        Floating keymap reference popup
plugin/
  vallow.lua        :Vallow / :VallowRefresh / :VallowSearch commands
```

---

## License

[MIT](LICENSE)
