# Roadmap

Work runs in batches. Each batch is one commit series on `main`, verified
by the headless test harness before it lands. fallow 3.22+ is the target.

## Batch 0 — done

- Tolerate exit 1, surface fallow's JSON error message.
- Show fallow version, elapsed time, workspace and type-aware notices.
- `timeout_ms` and `env` config.

## Batch 1 — done

- **Tests and CI.** `tests/` with a fixture JS/TS project and a headless
  harness (`nvim --headless -l`) that runs the runner in combined and
  separate mode, renders the panel, and asserts counts and header lines.
  `make test`. GitHub Action: stylua --check + tests on macOS and Linux.
- **Result cache.** Write the last normalized results per project root to
  `stdpath("cache")/vallow/<hash>.json`. On open, render cached results
  marked `(stale)` in the header while a fresh run proceeds.
- **Command arguments.** `:Vallow health` opens on that tab. `:Vallow
  production` toggles the flag. `:Vallow refresh`, `:Vallow search`.
  Completion for all arguments. Existing commands stay as aliases.
- **Per-category diagnostics config.** `diagnostics.categories = { key =
  { enabled, severity } }`, `diagnostics.virtual_text`, and
  `diagnostics.current_buffer_only`.

## Batch 2 — done

- **Installer and binary resolution.** `runner.resolve_cmd` picks the fallow
  binary: configured command, `node_modules/.bin`, PATH, then the copy under
  `stdpath("data")`. `:VallowInstall [lsp] [version]` and `:VallowUpdate`
  download the standalone release asset with curl. Signatures are not
  verified. `:checkhealth vallow` names the source and warns below 3.22.0.
- **Audit mode.** `:Vallow audit [ref]` runs `fallow audit --base <ref>
  --format json`. Panel shows only changed files; `introduced` findings get
  a marker and a toggle hides inherited ones. Header names the base ref.
- **Inspect float.** `:VallowInspect` (and `gi` in the panel on a file row)
  runs `fallow inspect --file <path> --format json` for the current buffer
  and renders exports, importers, findings, and health in a float.
- **Ignore actions.** `x` on a finding offers, via `vim.ui.select`: add to
  `ignoreFindings` / `ignoreExports` in `.fallowrc.json`, or insert the
  suppression comment fallow documents. Confirm before writing. A
  `stale_suppressions` category lists suppressions that no longer fire.
- **Explain.** `ge` on a category header or finding, and a paragraph in the
  K detail float, show `fallow explain <issue-type>` output, cached per type
  (`?` stays the keymap help).
- **Trace.** `gt` on an unused export or dependency runs `--trace` /
  `--trace-dependency` and renders the evidence as an indented tree.

## Batch 3 — done

- **Health dashboard.** `D` in the panel or `:Vallow dashboard`: centered
  float with a block-character score gauge, `health_score.penalties`
  breakdown, vital signs, and a `health_trend` sparkline when present.
- **Virtual lines.** Dim `virt_lines` above functions flagged by health
  findings showing cyclomatic and cognitive scores; gutter sign for
  hotspots. Config toggle under `diagnostics`.
- **Clone diff.** `d` on a clone group opens the two largest instances in a
  vertical split with `diffthis`, scrolled to the matching ranges.
- **Cycle chain.** Circular-dependency detail float renders `files[]` and
  `edges[]` as a chain with the import line of each hop.
- **Peek ranges.** P highlights the full start–end range for clone groups
  and large functions.

## Batch 4 — done

- **Explorer decorations.** Unused files greyed out in nvim-tree, neo-tree,
  and oil. Each explorer reads its hooks from its own setup, so vallow
  exposes one hook per explorer, guarded by `pcall`. Runs end in
  `panel._on_results`, which also fires `User VallowResults`.
- **Lualine component.** `require("vallow").lualine()`: per-severity counts,
  a spinner while fallow runs, a check mark when clean.
- **Picker extensions.** `:Telescope vallow` and `Snacks.picker.vallow()`,
  both previewing the file at the finding line.
- **package.json overlay.** Virtual text per dependency line: unused,
  type-only, test-only, dev in prod, unlisted. The runner keeps fallow's
  `type_only_dependencies` and `test_only_dependencies` as the Misplaced
  Deps category.

## Conventions

- stylua on every touched line. Match existing style.
- Every feature: README table row, `doc/vallow.txt` entry, help float row
  if it adds a keymap, and a harness test.
- Unknown JSON arrays or diagnostic kinds must never crash; skip them.
