# Fallow API Reference

> Source: https://github.com/fallow-rs/fallow
> Observed on: fallow 3.29.0 (latest release: 3.33.1)
> Schema versions on 3.29.0: combined 12, dead-code 9, dupes 10, health 11
> Last researched: 2026-10-14
> Used by: `lua/vallow/runner.lua`

---

## Installation

```sh
npm install -g fallow          # global
npm install --save-dev fallow  # local project
cargo install fallow           # via cargo
```

Binaries shipped: `fallow`, `fallow-lsp`, `fallow-mcp`
Platforms: darwin-arm64, darwin-x64, linux-x64, linux-arm64, win32-x64, win32-arm64

---

## CLI Commands

| Command | Description |
|---|---|
| `fallow` | Full pipeline: dead-code + dupes + health |
| `fallow dead-code` | Unused exports, files, types, members, deps, cycles |
| `fallow dupes` | Code duplication (clone detection) |
| `fallow health` | Complexity, hotspots, refactoring targets, coverage gaps |
| `fallow audit` | PR risk gate — changed files only, verdict pass/warn/fail |
| `fallow security` | Security findings (client-server leak, tainted sinks) |
| `fallow fix` | Auto-fix findings (`--dry-run` to preview) |
| `fallow watch` | Re-analyze on file changes |
| `fallow flags` | Feature flag detection |
| `fallow init` | Create `.fallowrc.json` |
| `fallow list` | List entry points, files, plugins, workspaces |
| `fallow explain ISSUE_TYPE` | Explain an issue type without running analysis |
| `fallow doctor` | Check project readiness (root, config, workspaces, plugins, `node_modules`, caches). No analysis, no writes. `--format json` gives `kind: "doctor"` |
| `fallow architecture` | Import cycles, boundary violations and rule-pack policy violations in one run (3.33). `--cycles`, `--boundaries`, `--policy` pick one kind |
| `fallow guard FILES` | Show which architecture rules apply to files before an edit |
| `fallow workspaces` | Show monorepo workspace discovery diagnostics |

Since 3.33, `fallow dead-code --circular-deps`, `--re-export-cycles`,
`--package-cycles`, `--boundary-violations` and `--policy-violations` are
deprecated aliases of the `fallow architecture` flags. They still work and
`dead-code` still reports these findings.

All commands support `--format json`. Use `--quiet` to suppress progress output.

---

## Global Flags (all commands)

```
--root PATH              Project root
--config PATH            Config file path
--format VALUE           Output format (default: human)
--quiet                  Suppress progress output
--no-cache               Disable incremental cache
--threads N              Parser thread count
--production             Exclude test/dev files
--fail-on-issues         Exit 1 if any issues
--changed-since REF      Only files changed since git ref
--diff-file PATH         Unified diff for line-level scoping
--baseline PATH          Compare against saved baseline
--save-baseline PATH     Save current as baseline
--group-by VALUE         Group output: owner|directory|package|section
--workspace PATTERN      Scope to matching workspaces
--score                  Compute 0-100 health score
--show-cascade           List findings inside unused files (hidden by default since 3.33)
--finding-id ID          dead-code only (3.31): report only these finding ids
--ci                     CI mode: --format sarif --fail-on-issues --quiet
```

---

## JSON Output Structure

### `kind` discriminator

Every JSON object has a top-level `kind`. Branch on it.

```
"dead-code"      fallow dead-code --format json
"dupes"          fallow dupes --format json
"health"         fallow health --format json
"audit"          fallow audit --format json
"combined"       fallow --format json  (wraps all three)
"security"       fallow security --format json
"architecture"   fallow architecture --format json  (3.33, schema_version 1)
"doctor"         fallow doctor --format json
```

A failure with `--format json` is an object with `error: true` and no `kind`.
`fallow fix` output has no `kind` (see Fix Output).

### Combined output (`fallow --format json`)

Real output from `tests/fixture`, trimmed:

```json
{
  "kind": "combined",
  "schema_version": 12,
  "version": "3.29.0",
  "elapsed_ms": 85,
  "gate_outcomes": {
    "error-severity-findings": { "status": "fail", "enforced": false },
    "health-findings": { "status": "pass", "enforced": false }
  },
  "check":  { ...DeadCodeOutput },
  "dupes":  { ...DupesOutput },
  "health": { ...HealthOutput },
  "workspace_diagnostics": [],
  "next_steps": [],
  "_meta": { "telemetry": {} }
}
```

**IMPORTANT**: Sub-keys are `check`, `dupes` and `health`. The fallow 2.x
names `dead_code` and `duplication` no longer appear.

`check` keeps its own `schema_version` (9). `dupes` and `health` had none
inside the combined output. `workspace_diagnostics` sits at the top level of
the combined output, not inside `check`.

### Gate outcomes

`gate_outcomes` maps a gate name to `{ "status": "pass"|"fail", "enforced": bool }`.
Gates seen: `error-severity-findings`, `health-findings`. `status` says what
the findings imply. `enforced` says whether the exit code uses it. Standalone
`fallow dead-code` and `fallow health` reported `enforced: true`. Combined
output reported `enforced: false`. Tolerate unknown gate names.

### Workspace diagnostics

`workspace_diagnostics[]` has `path`, `kind`, `message`, and optionally
`degrades_analysis: true`. Only entries with `degrades_analysis` make results
less trustworthy (for example false "unused" findings). Others are
informational.

```json
{ "path": "node_modules", "kind": "node-modules-missing", "degrades_analysis": true,
  "message": "'node_modules' does not exist. ..." }
{ "path": ".", "kind": "boundaries-not-configured",
  "message": "No architecture boundaries are configured, so the boundary detector did not run ..." }
```

Kinds seen: `skipped-source-dotdir` (degrades), `node-modules-missing`
(degrades), `boundaries-not-configured`, `rule-packs-not-configured`. A
finding that rests on incomplete evidence carries
`reachability_caveats: ["incomplete-import-graph"]`, and its `remove-*`
action has `auto_fixable: false` with a `note`.

---

## Casing Rules

| Context | Convention |
|---|---|
| JSON output — top-level array names | `snake_case` (`unused_files`, `clone_groups`) |
| JSON output — finding-level fields | `snake_case` (`export_name`, `package_name`, `from_path`) |
| Config file fields (`.fallowrc.json`) | `camelCase` |
| CLI flags | `--kebab-case` |
| `kind` / action `type` / rule names | `"kebab-case"` (`"dead-code"`, `"remove-export"`, `"unused-export"`) |
| `fallow fix` item `type` | `snake_case` (`remove_export`, `remove_dependency`) |

---

## Dead-Code Output (`kind: "dead-code"`)

Top-level keys on 3.29.0, trimmed:

```json
{
  "kind": "dead-code",
  "schema_version": 9,
  "version": "3.29.0",
  "elapsed_ms": 12,
  "total_issues": 4,
  "entry_points": { "total": 1, "sources": { "package.json": 1 } },
  "summary": { "total_issues": 4, "unused_exports": 1, "unused_types": 1, "unused_dependencies": 1, "unresolved_imports": 1 },
  "unused_files": [],
  "unused_exports": [],
  "unused_types": [],
  "private_type_leaks": [],
  "deprecated_exports_in_use": [],
  "unused_dependencies": [],
  "unused_dev_dependencies": [],
  "unused_optional_dependencies": [],
  "unused_enum_members": [],
  "unused_class_members": [],
  "unresolved_imports": [],
  "unlisted_dependencies": [],
  "duplicate_exports": [],
  "type_only_dependencies": [],
  "test_only_dependencies": [],
  "dev_dependencies_in_production": [],
  "circular_dependencies": [],
  "re_export_cycles": [],
  "boundary_violations": [],
  "boundary_coverage_violations": [],
  "boundary_call_violations": [],
  "policy_violations": [],
  "stale_suppressions": [],
  "gate_outcomes": { "error-severity-findings": { "status": "fail", "enforced": true } },
  "workspace_diagnostics": [],
  "next_steps": [],
  "_meta": {}
}
```

Also present, all arrays: `unused_catalog_entries`, `empty_catalog_groups`,
`unresolved_catalog_references`, `unused_dependency_overrides`,
`misconfigured_dependency_overrides`, `invalid_client_exports`,
`mixed_client_server_barrels`, `misplaced_directives`, `route_collisions`,
`dynamic_segment_name_conflicts`. `summary` also counts framework buckets
(Vue, Svelte, Angular, SvelteKit).

The key is `dev_dependencies_in_production` (plural). The `baseline` key
is absent when no baseline is in use.

Changes after 3.29.0, from the release notes (not run here):

- 3.31: every dead-code finding has `finding_id`, for example
  `dc1:unused-export:81a349a3b9ea3b15`. It comes from rule, root-relative
  path and symbol, not from line or column, so it survives line shifts.
  `fallow dead-code --finding-id ID` filters to given ids and adds
  `finding_id_query`.
- 3.31: new `package_cycles[]` for dependency cycles between workspace
  packages (rule `package-cycle`). Fields: `packages`, `package_roots`,
  `edges` (one example import per hop, `type_only: true` when a hop has
  only type imports).
- 3.32: the schema versions of dead-code, audit and combined output
  advance (a new policy rule kind). Do not pin `schema_version`.
- 3.33: an unused file hides the findings inside it (unused exports,
  types, class members, enum members). The output has `cascade_hidden`
  with the count. `--show-cascade`, config `showCascade` or MCP
  `show_cascade` list them. Health vital signs still count them.
- 3.33: `fallow architecture` reports the cycle, boundary and policy
  arrays under `kind: "architecture"`.

---

## Finding Shapes

On 3.29.0, `path` values are relative to the project root (see Paths).
Findings have no `kind` or `introduced` field. Most carry `actions[]` and
`effective_severity` (`"error"`, ...). Some carry `reachability_caveats[]`.

### `unused_exports[]` / `unused_types[]`

Real output, trimmed:

```json
{
  "path": "src/a.ts",
  "export_name": "unusedFn",
  "is_type_only": false,
  "line": 7,
  "col": 16,
  "span_start": 102,
  "is_re_export": false,
  "actions": [
    { "type": "remove-export", "auto_fixable": false, "description": "Remove the unused export from the public API", "note": "Evidence is incomplete: ..." },
    { "type": "suppress-line", "auto_fixable": false, "comment": "// fallow-ignore-next-line unused-export" }
  ],
  "effective_severity": "error",
  "reachability_caveats": ["incomplete-import-graph"]
}
```

**vallow.nvim mapping:**
- `export_name` → `item.name`
- `line` → `item.lnum`
- the `unused_types` bucket (or `is_type_only`) → `item.kind = "type"`

### `unused_enum_members[]` / `unused_class_members[]`

From `output-contract.d.ts` (the fixtures have none): `path`,
`parent_name`, `member_name`, `kind`, `line`, `col`, `actions`. The name is
in `member_name`. There is no `export_name`.

### `unused_files[]`

From `output-contract.d.ts`:

```json
{ "path": "src/legacy.ts", "actions": [] }
```

No name or line number. Since 3.33 the findings inside these files are
hidden by default.

### `duplicate_exports[]`

From `output-contract.d.ts`. The finding has no top-level `path` or `line`.
Every location, including the first, is in `locations[]`:

```json
{
  "export_name": "formatDate",
  "locations": [
    { "path": "src/a.ts", "line": 10, "col": 0 },
    { "path": "src/b.ts", "line": 55, "col": 0 }
  ],
  "actions": []
}
```

`duplicate_locations` does not exist in 3.x.

**vallow.nvim mapping:** `export_name` → `item.name`; `locations[]` → all
locations.

### `unused_dependencies[]` / `unused_dev_dependencies[]` / `unused_optional_dependencies[]`

Real output, trimmed:

```json
{
  "package_name": "lodash",
  "location": "dependencies",
  "path": "package.json",
  "line": 7,
  "actions": [
    { "type": "remove-dependency", "auto_fixable": false },
    { "type": "add-to-config", "config_key": "ignoreDependencies", "value": "lodash" }
  ],
  "effective_severity": "error"
}
```

### `unresolved_imports[]`

Real output, trimmed:

```json
{
  "path": "src/index.ts",
  "specifier": "./nope",
  "line": 1,
  "col": 9,
  "specifier_col": 24,
  "actions": [{ "type": "resolve-import", "auto_fixable": false }],
  "effective_severity": "error"
}
```

### `unlisted_dependencies[]`

From `output-contract.d.ts`: `package_name` and `imported_from[]` (import
sites). No top-level `path` or `line`.

### `dev_dependencies_in_production[]`

From `output-contract.d.ts`: `package_name`, `path`, `line`, `actions`.
The key is plural. `dev_dependency_in_production` does not exist.

### `circular_dependencies[]`

Real output (`tests/fixture-health`), trimmed:

```json
{
  "files": ["src/a.ts", "src/b.ts"],
  "length": 2,
  "line": 1,
  "col": 9,
  "edges": [
    { "path": "src/a.ts", "line": 1, "col": 9 },
    { "path": "src/b.ts", "line": 1, "col": 9 }
  ],
  "actions": [{ "type": "refactor-cycle", "auto_fixable": false }],
  "effective_severity": "error"
}
```

There is no top-level `path` and no `cycle`. Use `files`, or `edges[].path`
for a location per hop.

### `boundary_violations[]`

From `output-contract.d.ts` (the fixtures configure no boundaries):

```json
{
  "from_path": "src/components/Button.tsx",
  "to_path": "src/api/database.ts",
  "from_zone": "frontend",
  "to_zone": "backend",
  "import_specifier": "../api/database",
  "line": 3,
  "col": 0,
  "actions": []
}
```

The location is `from_path` plus `line`/`col`. The names `path`,
`import_path` and `boundary_name` do not exist. Without configured
`boundaries` the array is empty and `workspace_diagnostics` has
`boundaries-not-configured`.

### `stale_suppressions[]`

From `output-contract.d.ts`: `path`, `line`, `col`, `origin`. Not observed
on the fixtures. Check the `origin` subfields against a real run before
relying on them.

---

## Dupes Output (`kind: "dupes"`)

Real output (`tests/fixture-health`), trimmed:

```json
{
  "kind": "dupes",
  "schema_version": 10,
  "version": "3.29.0",
  "elapsed_ms": 4,
  "clone_groups": [],
  "clone_families": [],
  "stats": {
    "total_files": 5,
    "files_with_clones": 3,
    "total_lines": 138,
    "duplicated_lines": 84,
    "clone_groups": 1,
    "clone_families": 1,
    "clone_instances": 3,
    "duplication_percentage": 60.86956521739131
  },
  "clone_groups_shown": 1,
  "clone_groups_omitted": 0,
  "clone_families_shown": 1,
  "clone_families_omitted": 0,
  "workspace_diagnostics": [],
  "_meta": {}
}
```

`duplication_percentage` is under `stats`. `total_issues`,
`mirrored_directories` and `grouped_by` are not in this output.

### `clone_groups[]`

Real output, trimmed. `fragment` holds the cloned source text and can be
large.

```json
{
  "instances": [
    { "file": "src/clone-one.ts", "start_line": 1, "end_line": 28, "start_col": 32, "end_col": 23, "fragment": "..." },
    { "file": "src/clone-two.ts", "start_line": 1, "end_line": 28, "start_col": 32, "end_col": 23, "fragment": "..." }
  ],
  "token_count": 203,
  "line_count": 28,
  "fingerprint": "dup:6f87acd9",
  "spread": 0,
  "suggested_name": "push",
  "actions": [
    { "type": "extract-shared", "auto_fixable": false },
    { "type": "suppress-line", "comment": "// fallow-ignore-next-line code-duplication" }
  ]
}
```

Instances use `file`, `start_line`, `end_line`, `start_col`, `end_col`.
The names `path`, `line`, `lineEnd` and `colEnd` do not exist. Groups that
share a file set also appear in `clone_families[]`.

**vallow.nvim mapping:**
- `instances[].file` → `loc.path`
- `instances[].start_line` → `loc.lnum`
- `instances[].end_line` → `loc.end_lnum`
- `suggested_name` → `item.name` (fallback: `fingerprint`)

---

## Health Output (`kind: "health"`)

Real output of `fallow health --score --format json` (`tests/fixture-health`),
trimmed:

```json
{
  "kind": "health",
  "schema_version": 11,
  "version": "3.29.0",
  "elapsed_ms": 0,
  "findings": [],
  "summary": {
    "files_analyzed": 7,
    "functions_analyzed": 8,
    "functions_above_threshold": 4,
    "max_cyclomatic_threshold": 20,
    "max_cognitive_threshold": 15,
    "max_crap_threshold": 30.0,
    "severity_critical_count": 1,
    "severity_high_count": 3,
    "severity_moderate_count": 0
  },
  "health_score": {
    "formula_version": 2,
    "score": 62.5,
    "grade": "C",
    "penalties": { "dead_exports": 2.5, "circular_deps": 25.0, "duplication": 10.0 }
  },
  "gate_outcomes": { "health-findings": { "status": "pass", "enforced": true } },
  "workspace_diagnostics": [],
  "_meta": {}
}
```

With `--score`, `findings` was empty although `functions_above_threshold`
was 4. Use plain `fallow health` or the combined output to get findings.
Combined `health` also has `file_scores`, `vital_signs`, `targets`,
`target_thresholds` and `hotspot_summary`. The fixtures produce no
`hotspots[]` entry, so that shape is unverified.

### Complexity Finding (`findings[]`)

Real output (combined `health`), trimmed:

```json
{
  "path": "src/complex.ts",
  "name": "classify",
  "line": 1,
  "col": 7,
  "cyclomatic": 21,
  "cognitive": 35,
  "line_count": 42,
  "param_count": 4,
  "exceeded": "all",
  "severity": "critical",
  "effective_severity": "error",
  "crap": 462.0,
  "coverage_tier": "none",
  "coverage_source": "estimated",
  "actions": [{ "type": "refactor-function", "auto_fixable": false }]
}
```

`exceeded` was `"all"` here. Older docs list `"cyclomatic"`, `"cognitive"`,
`"both"` and `"crap"`. Treat it as an open string.

### Refactoring target (`targets[]`)

Real output, trimmed:

```json
{
  "path": "src/b.ts",
  "priority": 20.3,
  "recommendation": "Break import cycle to reduce change cascade risk",
  "category": "break_circular_dependency",
  "effort": "low",
  "confidence": "high"
}
```

### Hotspot (`hotspots[]`)

Not observed in the fixtures. The shape below comes from the older docs.

```json
{
  "path": "src/core/processor.ts",
  "score": 92,
  "commits": 47,
  "complexity_density": 0.89,
  "fan_in": 3,
  "trend": "Accelerating",
  "bus_factor": 2,
  "top_contributor": { "identifier": "alice", "share": 0.55 }
}
```

---

## Fix Output (`fallow fix --dry-run --format json --quiet --no-create-config`)

Always pass `--dry-run` when exploring. Without it, `fallow fix` edits files.
The output has no `kind` and no `schema_version`. Real output, trimmed:

```json
{
  "dry_run": true,
  "fixes": [
    { "type": "remove_export", "path": "src/b.ts", "line": 7, "name": "useA" },
    { "type": "remove_dependency", "package": "lodash", "location": "dependencies", "file": "package.json",
      "applied": false, "skipped": true, "skip_reason": "low_confidence_incomplete_analysis",
      "reachability_caveats": ["incomplete-import-graph"] },
    { "type": "skipped", "path": "src/a.ts", "skipped": true,
      "skip_reason": "low_confidence_incomplete_analysis",
      "reachability_caveats": ["incomplete-import-graph"] }
  ],
  "total_fixed": 0,
  "skipped": 0,
  "skipped_content_changed": 0,
  "skipped_mixed_line_endings": 0,
  "skipped_low_confidence_exports": 1,
  "skipped_low_confidence_dependencies": 1,
  "skipped_low_confidence_members": 0
}
```

- An item with `skipped: true` and a `skip_reason` will not be applied.
  Do not count it as a fix.
- Each skip reason has its own counter: `skipped_content_changed`,
  `skipped_mixed_line_endings`, `skipped_low_confidence_exports`,
  `skipped_low_confidence_dependencies`, `skipped_low_confidence_members`.
  In the sample above, the two low-confidence items did not add to the
  top-level `skipped`, which stayed 0.
- Item shapes differ per `type`. A dependency item uses `package`, `file`
  and `location`. An export item uses `path`, `line` and `name`. A skipped
  export uses `type: "skipped"` and `path`.
- Items become low confidence when analysis is incomplete, for example
  when `node_modules` is missing.

---

## Doctor Output (`fallow doctor --format json`)

Keys: `kind` (`"doctor"`), `schema_version` (2), `version`, `root`,
`status`, `summary`, `checks[]`. Trimmed:

```json
{
  "kind": "doctor",
  "schema_version": 2,
  "checks": [
    { "id": "root", "category": "project", "status": "pass", "required": true, "message": "Project root is an accessible directory." },
    { "id": "config", "category": "configuration", "status": "pass", "required": true, "message": "Zero-config defaults resolved successfully." }
  ]
}
```

---

## Actions Array

Every finding has `actions: IssueAction[]`:

```json
{ "type": "remove-export", "auto_fixable": true, "description": "Remove export" }
```

Common `type` values:
```
remove-export      remove-file        remove-dependency
move-dependency    suppress-line      suppress-file
add-to-config      extract-shared     refactor-cycle
resolve-import     refactor-function  add-tests
apply-refactoring  apply-suggestion
```

`auto_fixable: true` → `fallow fix` handles it automatically. Some actions
carry `note`, `comment` (the suppression text), `config_key` and `value`.
When analysis is incomplete, `remove-*` actions report `auto_fixable: false`.

---

## Suppression Comments

```ts
// fallow-ignore-next-line unused-export
export function keepForExternalUse() {}

// fallow-ignore-next-line unused-export, complexity
export const complexPublicFn = () => {};

// fallow-ignore-file  (at top of file — suppresses all findings)
```

---

## Configuration (`.fallowrc.json`)

Config file lookup (first match wins):
1. `.fallowrc.json`
2. `.fallowrc.jsonc`
3. `fallow.toml`
4. `.fallow.toml`

```json
{
  "$schema": "https://raw.githubusercontent.com/fallow-rs/fallow/main/schema.json",
  "entry": ["src/index.ts", "bin/**/*.js"],
  "ignorePatterns": ["**/*.test.ts", "dist/**"],
  "ignoreExports": [{ "file": "src/utils.ts", "exports": ["internalHelper"] }],
  "ignoreDependencies": ["typescript"],
  "rules": {
    "unused-export": "error",
    "unused-file": "warn",
    "circular-dependency": "warn",
    "complexity": "off"
  },
  "boundaries": [
    {
      "name": "Frontend",
      "from": "src/components/**",
      "allow": ["src/utils/**"]
    }
  ],
  "duplicates": {
    "enabled": true,
    "mode": "mild",
    "minTokens": 50,
    "minLines": 5,
    "minOccurrences": 2
  },
  "health": {
    "maxCyclomatic": 10,
    "maxCognitive": 15,
    "maxCrap": 30.0
  },
  "workspaces": {
    "globs": ["packages/*/package.json"],
    "ignore": ["packages/playground"]
  }
}
```

---

## Paths

On 3.29.0, `path`, `file`, `from_path` and `to_path` are **relative to the
project root**. Older versions emitted absolute paths. vallow.nvim should
join relative paths with the root and leave absolute paths unchanged. To
derive `relative_path` from an absolute path, strip the root prefix:

```lua
local function rel(abs_path)
  return abs_path:gsub("^" .. vim.pesc(root) .. "/", "")
end
```

---

## Notes for vallow.nvim

1. **Combined output key names**: `raw.check`, `raw.dupes`, `raw.health`
   on 3.x. Keep `dead_code` and `duplication` as fallbacks for fallow 2.x.

2. **Field casing**: all finding-level fields are `snake_case`. Keep
   `camelCase` variants as fallbacks for older versions only.

3. **Member findings** use `member_name` and `parent_name`, not
   `export_name`. The normalizer merges `unused_enum_members` and
   `unused_class_members` into the `unused_exports` bucket with
   `kind = "enum"` / `kind = "member"`.

4. **`unresolved_imports` + `unlisted_dependencies`** → `missing_deps`
   bucket. `unlisted_dependencies` has `package_name` and `imported_from[]`.

5. **`duplicate_exports`** has `locations[]` and no top-level `path`/`line`.

6. **`workspace_diagnostics`**: show only entries with
   `degrades_analysis: true` as warnings. Others are informational.

7. **`schema_version`**: 12 for combined output on 3.29.0. It rose in
   3.32. Do not pin it. Per-command versions differ (see header).

8. **Unused-file cascade (3.33)**: exports inside an unused file are
   hidden by default. The plugin shows fewer findings than on 3.29.0
   unless it passes `--show-cascade`.

9. **`finding_id` (3.31)** gives a stable key per dead-code finding. Use it
   for dismissals instead of `path:line`.

10. **`fallow fix --dry-run --format json`** returns the fix list above.
    Skip items with `skipped: true`.

11. **`fallow watch`** could drive auto-refresh in a future version.

12. **Unverified**: only 3.29.0 is installed. `finding_id`,
    `package_cycles`, `cascade_hidden` and `fallow architecture` come from
    the 3.30 to 3.33.1 release notes, not from a run.
