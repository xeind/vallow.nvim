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

## Batch 5 — done

- **Watch mode.** One `fallow watch --format json --quiet --no-clear` per
  project root streams a result on every file change. `:Vallow watch`, or
  `watch = { enabled = true }`. fallow does not write the stream atomically,
  so the parser keeps the text after the last object start and emits it once
  it decodes. watch reports dead code only; the duplicate and health buckets
  of the last full run are carried over. auto-refresh spawns no run while the
  watcher is up.
- **Fix preview.** `:Vallow fix` and `X` render `fallow fix --dry-run` as a
  fix list grouped by file. The confirm defaults to No; only Yes runs
  `--yes`, then checktime and a refresh. Exit 2 or higher, or a type-aware
  timeout, applies nothing.
- **Cancel and debounce.** A new run stops the fallow jobs of the previous
  one. Auto-refresh debounces at 300 ms, and every path that starts a run
  drops the pending timer, so an explicit `r` is no longer overtaken by the
  auto-refresh queued behind it.
- **Extmarks.** The panel and the summary float highlight with
  `nvim_buf_set_extmark` instead of the deprecated `nvim_buf_add_highlight`.
- **Picker.** fzf-lua selections come back through a lookup keyed by the item
  string, so a colon in a path no longer breaks the jump.
- **Ignore writes.** `.fallowrc` files are edited as text: key order,
  formatting and JSONC comments survive, and `.fallowrc.jsonc` is used when
  it exists.

## Batch 6 — done

- **Cursor actions.** `:Vallow action` offers ignore, trace and explain for
  the finding under the cursor in a source buffer. `:Vallow next` / `prev`
  jump between vallow diagnostics only. Diagnostics carry their finding in
  `user_data`.
- **fallow 3.24–3.31 fixes.** The fix preview no longer counts skipped
  fixes. Only notices with `degrades_analysis` are shown. The runner reads
  `dev_dependencies_in_production` and the boundary violation fields
  `from_path`, `from_zone`, `to_zone`, `import_specifier`.
- **New categories.** Package Cycles and Deprecated In Use, in ISSUES and
  as diagnostics.
- **Severity.** fallow's `effective_severity` "warn" caps the default
  diagnostic severity at warn. A severity set in config still wins.
- **checkhealth.** `:checkhealth vallow` runs `fallow doctor` (3.23+).
- **Panel state.** Filter, audit flag and cursor row survive a reopen.
  `follow_buffer = true` filters the panel to the file you enter.
- **CI removed.** The GitHub Action tested against `fallow@latest`, so
  each fallow release could fail it with no change here. `make test` and
  `make lint` run locally.

## Batch 7 — done

- **Unused-file cascade.** fallow 3.33 hides findings inside unused files
  and reports `cascade_hidden`. The panel header shows the count. vallow
  does not pass `--show-cascade`: deleting the file removes those findings.

## Batch 8 — fallow v4 (planned)

- **Trigger.** fallow 3.33 moves cycles and boundaries to `fallow
  architecture` (`kind: "architecture"`, `schema_version` 1). `dead-code`
  and combined runs keep these arrays, unmarked, "until the next major
  version". Start when the v4 notes or `output-contract.d.ts` drop them
  from `CheckOutput`.
- **Fields.** No field is renamed: `circular_dependencies`,
  `package_cycles` and `boundary_violations` (vallow's three) move from
  `check.*` (combined) or the top level (`dead-code`) to the top level of
  the architecture envelope. The item shapes do not change.
- **Runner.** `M.run` and `_run_separate` start `fallow architecture
  --format json --quiet` when the dead-code block has no
  `circular_dependencies` (always present in 3.x). `_normalize` reads the
  three arrays from that envelope when it is given, else from `check`.
  Watch output carries the last full run's arrays, as it does for dupes.
- **Cost.** fallow 3.x spawns no extra process. On v4 each run costs one
  more process and a second module-graph pass; remember the decision per
  root so only the first run waits for both in sequence.
- **Tests.** Hand-built tables through `_normalize`: a dead-code block
  without the arrays plus an architecture envelope fills Circular Deps,
  Package Cycles and Boundary Violations; a 3.x block with the arrays
  starts no architecture job.

## Batch 9 — done

- **Path trace.** `gt` on a boundary violation runs `fallow trace --path`
  from the importing file to `to_path`, so a barrel in between shows as a
  hop. `:Vallow path {file}` traces from the current buffer. Needs fallow
  3.24+. Circular deps keep the K cycle chain: a trace adds nothing there.
- **Incomplete analysis.** Findings with `reachability_caveats` get a dim
  `?` in the panel gutter, " (incomplete analysis)" on the diagnostic, and
  the caveat in the K float.

## Batch 10 — done

- **Stack trace to quickfix.** `:Vallow stacktrace` sends a selection or
  the `+` register through `fallow trace-error` (3.24) and fills the
  quickfix list. Ambiguous frames are marked; dependency frames are
  skipped.
- **Gate results.** The dashboard lists `gate_outcomes` (3.27+). vallow
  runs without `--fail-on-issues`, so gates are dimmed and the heading
  reads "Gates · not enforced" unless one is enforced.
- **Stale Flags.** Add "flags" to `analyses` to run `fallow flags
  --retirement` (3.30+) after each run. Rows show the flag, its age and
  the definition site. Older fallow skips it without a notice.

## Deferred

- **Stable finding ids.** Nothing in vallow needs `finding_id` yet, and
  using it raises the minimum to fallow 3.31. Pick it up with the first
  feature that tracks a finding across runs.
- **Importer counts.** `fallow inspect` gives `reference_count` per export
  but no line, except for unused exports. Matching names against the
  buffer breaks on `export { a, b }`, re-exports and default exports.
  Revisit if fallow adds `line` to `trace_file.exports[]`.
- **Current-buffer health.** `fallow health <path>` (3.25) takes about
  0.1 s on the fixture, the same as a full run, because fallow still
  builds the whole graph. `auto_refresh` already re-runs on save. Revisit
  if a large project shows scoped runs are much faster.
- **Introduced-only diagnostics.** Only audit runs carry `introduced`, and
  audit diagnostics already cover only the changed files.

## Conventions

- stylua on every touched line. Match existing style.
- Every feature: README table row, `doc/vallow.txt` entry, help float row
  if it adds a keymap, and a harness test.
- Unknown JSON arrays or diagnostic kinds must never crash; skip them.
