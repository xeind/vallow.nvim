# Fallow API Reference

> Source: https://github.com/fallow-rs/fallow
> Schema version: 7 (fallow 2.x)
> Last researched: 2026-06-06
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
--ci                     CI mode: --format sarif --fail-on-issues --quiet
```

---

## JSON Output Structure

### `kind` discriminator

Every JSON response has a top-level `kind`:

```
"dead-code"     fallow dead-code --format json
"dupes"         fallow dupes --format json
"health"        fallow health --format json
"audit"         fallow audit --format json
"combined"      fallow --format json  (wraps all)
"security"      fallow security --format json
```

### Combined output (`fallow --format json`)

```json
{
  "kind": "combined",
  "schema_version": 7,
  "version": "2.89.0",
  "elapsed_ms": 234,
  "dead_code":   { ...DeadCodeOutput },
  "duplication": { ...DupesOutput },
  "health":      { ...HealthOutput }
}
```

**IMPORTANT**: Sub-keys are `dead_code` and `duplication` (not `check`/`dupes`).

---

## Casing Rules

| Context | Convention |
|---|---|
| JSON output — top-level array names | `snake_case` (`unused_files`, `clone_groups`) |
| JSON output — finding-level fields | `snake_case` (`export_name`, `package_name`, `duplicate_locations`) |
| Config file fields (`.fallowrc.json`) | `camelCase` |
| CLI flags | `--kebab-case` |
| `kind` / finding type values | `"kebab-case"` (`"unused-export"`, `"dead-code"`) |

---

## Dead-Code Output (`kind: "dead-code"`)

```json
{
  "kind": "dead-code",
  "schema_version": 7,
  "elapsed_ms": 234,
  "total_issues": 12,
  "unused_exports": [],
  "unused_files": [],
  "unused_types": [],
  "unused_dependencies": [],
  "unused_dev_dependencies": [],
  "unused_optional_dependencies": [],
  "unused_enum_members": [],
  "unused_class_members": [],
  "duplicate_exports": [],
  "unresolved_imports": [],
  "unlisted_dependencies": [],
  "circular_dependencies": [],
  "boundary_violations": [],
  "re_export_cycles": [],
  "private_type_leaks": [],
  "stale_suppressions": [],
  "workspace_diagnostics": [],
  "baseline": null
}
```

---

## Finding Shapes

### `unused_exports[]` / `unused_types[]` / `unused_enum_members[]` / `unused_class_members[]`

Same shape, `snake_case` field names:

```json
{
  "path": "/abs/path/src/utils.ts",
  "line": 42,
  "col": 0,
  "export_name": "deadFunction",
  "kind": "unused-export",
  "actions": [
    { "type": "remove-export", "auto_fixable": true, "description": "..." }
  ],
  "introduced": null
}
```

**vallow.nvim mapping:**
- `export_name` → `item.name` (fallback: `exportName`)
- `line` → `item.lnum`
- `kind == "unused-type"` → `item.kind = "type"`

### `unused_files[]`

```json
{
  "path": "/abs/path/src/legacy.ts",
  "kind": "unused-file",
  "actions": [],
  "introduced": null
}
```

No name or line number — just path.

### `duplicate_exports[]`

```json
{
  "path": "/abs/path/src/a.ts",
  "line": 10,
  "col": 0,
  "export_name": "formatDate",
  "duplicate_locations": [
    { "path": "/abs/path/src/b.ts", "line": 55, "col": 0 },
    { "path": "/abs/path/src/c.ts", "line": 88, "col": 0 }
  ],
  "kind": "duplicate-export",
  "actions": [],
  "introduced": null
}
```

**vallow.nvim mapping:**
- `export_name` → `item.name`
- `path + line` → primary location
- `duplicate_locations` → other locations (combine with primary for full list)

### `unused_dependencies[]` / `unused_dev_dependencies[]` / `unused_optional_dependencies[]`

```json
{
  "package_name": "lodash",
  "kind": "unused-dependency",
  "path": "/abs/path/package.json",
  "line": 12,
  "actions": [
    { "type": "remove-dependency", "auto_fixable": true }
  ],
  "introduced": null
}
```

**vallow.nvim mapping:**
- `package_name` → `item.name` (fallback: `packageName`, `package`)

### `unresolved_imports[]` / `unlisted_dependencies[]`

```json
{
  "path": "/abs/path/src/file.ts",
  "line": 3,
  "col": 0,
  "specifier": "some-missing-pkg",
  "kind": "unresolved-import",
  "actions": []
}
```

### `circular_dependencies[]`

```json
{
  "path": "/abs/path/src/a.ts",
  "cycle": ["/abs/path/src/a.ts", "/abs/path/src/b.ts", "/abs/path/src/a.ts"],
  "kind": "circular-dependency",
  "actions": []
}
```

### `boundary_violations[]`

```json
{
  "path": "/abs/path/src/components/Button.tsx",
  "line": 3,
  "col": 0,
  "import_path": "src/api/database",
  "boundary_name": "Frontend",
  "kind": "boundary-violation",
  "actions": []
}
```

### `stale_suppressions[]`

```json
{
  "path": "/abs/path/src/utils.ts",
  "line": 10,
  "col": 0,
  "origin": {
    "type": "ignore-next-line",
    "issue_type": "unused-export",
    "export_name": "myExport"
  },
  "kind": "stale-suppression"
}
```

---

## Dupes Output (`kind: "dupes"`)

```json
{
  "kind": "dupes",
  "schema_version": 7,
  "elapsed_ms": 89,
  "total_issues": 3,
  "clone_groups": [],
  "mirrored_directories": [],
  "duplication_percentage": 4.2,
  "grouped_by": null
}
```

### `clone_groups[]`

```json
{
  "fingerprint": "dup:a1b2c3d4",
  "suggested_name": "handleRequest",
  "kind": "code-duplication",
  "instances": [
    { "path": "/abs/path/src/a.ts", "line": 10, "col": 0, "lineEnd": 25, "colEnd": 1 },
    { "path": "/abs/path/src/b.ts", "line": 40, "col": 0, "lineEnd": 55, "colEnd": 1 }
  ],
  "tokens": 120,
  "lines": 15,
  "severity": "moderate",
  "actions": [],
  "introduced": null
}
```

**vallow.nvim mapping:**
- `instances[].line` → `loc.lnum`
- `instances[].lineEnd` → `loc.end_lnum`
- `suggested_name` → `item.name` (fallback: `"dup:" + fingerprint`)

---

## Health Output (`kind: "health"`)

```json
{
  "kind": "health",
  "schema_version": 3,
  "elapsed_ms": 320,
  "findings": [],
  "hotspots": [],
  "targets": [],
  "file_scores": [],
  "vital_signs": {},
  "health_score": {}
}
```

### Complexity Finding (`findings[]`)

```json
{
  "path": "src/file.ts",
  "name": "functionName",
  "line": 48,
  "col": 0,
  "cyclomatic": 67,
  "cognitive": 138,
  "line_count": 290,
  "exceeded": "both"
}
```

`exceeded` values: `"cyclomatic"`, `"cognitive"`, `"both"`, `"crap"`

### Hotspot (`hotspots[]`)

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
```

`auto_fixable: true` → `fallow fix` handles it automatically.

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

All `path` fields in fallow output are **absolute**. vallow.nvim derives
`relative_path` by stripping the root prefix:

```lua
local function rel(abs_path)
  return abs_path:gsub("^" .. vim.pesc(root) .. "/", "")
end
```

---

## Notes for vallow.nvim

1. **Combined output key names**: `raw.dead_code` (not `raw.check`) and
   `raw.duplication` (not `raw.dupes`). Keep old names as fallbacks.

2. **Field casing**: ALL finding-level fields are `snake_case` in fallow 2.x
   output: `export_name`, `package_name`, `duplicate_locations`. Keep
   `camelCase` variants as fallbacks for older versions.

3. **`unused_enum_members` / `unused_class_members`**: Same shape as
   `unused_exports`. Normalizer merges them into the `unused_exports` bucket
   with `kind = "enum"` / `kind = "member"`.

4. **`unresolved_imports` + `unlisted_dependencies`** → `missing_deps` bucket.

5. **`duplicate_exports`** finding already contains `duplicate_locations[]` —
   no manual grouping needed.

6. **`workspace_diagnostics`** non-empty means config/discovery errors.

7. **`schema_version: 7`** is current as of fallow 2.x.

8. **`fallow watch`** could drive auto-refresh in a future version.

9. **`fallow fix --dry-run --format json`** returns same shapes with
   `auto_fixable: true` — future suppress/fix action.
