-- Canonical human-readable labels for finding bucket keys.
-- Used by diagnostics.lua, picker.lua, and panel/actions.lua (quickfix).
local M = {}

M.label = {
  unused_exports = "unused export",
  unused_types = "unused type",
  unused_enum_members = "unused enum member",
  unused_class_members = "unused class member",
  unused_files = "unused file",
  unused_deps = "unused dep",
  unused_dev_deps = "unused dev dep",
  unused_optional_deps = "unused optional dep",
  type_only_deps = "type-only dep",
  test_only_deps = "test-only dep",
  unresolved_imports = "unresolved import",
  unlisted_deps = "unlisted dep",
  duplicate_exports = "duplicate export",
  circular_deps = "circular dep",
  package_cycles = "package cycle",
  deprecated_exports_in_use = "deprecated export in use",
  boundary_violations = "boundary violation",
  clone_groups = "clone",
  health_complexity = "high complexity",
  health_hotspots = "hotspot",
  health_targets = "refactor target",
  stale_flags = "stale flag",
  dev_dep_in_prod = "dev dep in production",
  css_token_drift = "CSS token drift",
  raw_style_value = "raw style value",
  stale_suppressions = "stale suppression",
}

return M
