-- dashboard.lua: the health score, its penalties, vital signs and trend,
-- rendered in one centred float. `:Vallow dashboard` or `D` in the panel.
local M = {}

local GAUGE_W = 30
local BARS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

-- Score band → severity highlight group.
M._band = function(score)
  if score >= 80 then
    return "VallowSevHint"
  elseif score >= 60 then
    return "VallowSevWarn"
  end
  return "VallowSevError"
end

M._gauge = function(score)
  local filled = math.floor((math.max(0, math.min(100, score)) / 100) * GAUGE_W + 0.5)
  return string.rep("█", filled) .. string.rep("░", GAUGE_W - filled)
end

-- Block sparkline over a list of numbers. Equal values render mid-height.
M._sparkline = function(values)
  local lo, hi = math.huge, -math.huge
  for _, v in ipairs(values) do
    lo = math.min(lo, v)
    hi = math.max(hi, v)
  end
  local out = {}
  for _, v in ipairs(values) do
    local idx = (hi > lo) and math.floor((v - lo) / (hi - lo) * (#BARS - 1) + 0.5) or 3
    table.insert(out, BARS[idx + 1])
  end
  return table.concat(out)
end

-- Penalty keys read as snake_case; show them as words.
local function words(key)
  return (tostring(key):gsub("_", " "))
end

local function num(v)
  if type(v) ~= "number" then
    return tostring(v)
  end
  if v == math.floor(v) then
    return tostring(math.floor(v))
  end
  return string.format("%.1f", v)
end

-- Two-column row: label left, value right-aligned in a 34-wide block.
local function row(label, value)
  local pad = math.max(1, 34 - vim.fn.strdisplaywidth(label) - vim.fn.strdisplaywidth(value))
  return "    " .. label .. string.rep(" ", pad) .. value
end

M._lines = function(findings)
  local b = require("vallow.panel.float").builder()
  local score = findings and findings.health_score

  if not vim.tbl_contains(require("vallow.config").get().analyses or {}, "health") then
    b.push("")
    b.push('  Health is not in config.analyses — add "health" to see the score.', "VallowKind")
    b.push("")
    return b
  end
  if not score or type(score.score) ~= "number" then
    b.push("")
    b.push("  No health score yet — run :Vallow refresh.", "VallowKind")
    b.push("")
    return b
  end

  b.push("")
  local head = "  " .. M._gauge(score.score) .. "  " .. num(score.score)
  if score.grade and score.grade ~= "" then
    head = head .. "  " .. score.grade
  end
  b.push(head, M._band(score.score))
  b.push("")

  -- Penalties, largest first.
  local pens = {}
  for key, value in pairs(score.penalties or {}) do
    if type(value) == "number" and value > 0 then
      table.insert(pens, { key = key, value = value })
    end
  end
  table.sort(pens, function(x, y)
    if x.value ~= y.value then
      return x.value > y.value
    end
    return x.key < y.key
  end)
  b.push("  Penalties", "VallowSection")
  if #pens == 0 then
    b.push("    none", "VallowKind")
  end
  for _, p in ipairs(pens) do
    b.push(row(words(p.key), "-" .. num(p.value)), "Comment")
  end

  -- Vital signs: one row of the metrics that drive the score.
  local vs = findings.vital_signs
  if type(vs) == "table" then
    local parts = {}
    local function add(label, value, unit)
      if type(value) == "number" then
        table.insert(parts, label .. " " .. num(value) .. (unit or ""))
      end
    end
    add("dead files", vs.dead_file_pct, "%")
    add("dead exports", vs.dead_export_pct, "%")
    add("duplication", vs.duplication_pct, "%")
    add("avg cyclomatic", vs.avg_cyclomatic)
    add("maintainability", vs.maintainability_avg)
    add("cycles", vs.circular_dep_count)
    add("hotspots", vs.hotspot_count)
    if #parts > 0 then
      b.push("")
      b.push("  Vital signs", "VallowSection")
      b.push("    " .. table.concat(parts, " · "), "Comment")
    end
  end

  -- Trend: only present once a snapshot exists (fallow health --save-snapshot).
  local trend = findings.health_trend
  if type(trend) == "table" and type(trend.metrics) == "table" then
    b.push("")
    local head_text = "  Trend"
    local cmp = trend.compared_to or {}
    if cmp.timestamp then
      head_text = head_text .. " vs " .. tostring(cmp.timestamp)
    end
    b.push(head_text, "VallowSection")
    for _, m in ipairs(trend.metrics) do
      if type(m.previous) == "number" and type(m.current) == "number" then
        local spark = M._sparkline({ m.previous, m.current })
        local unit = m.unit or ""
        local value = num(m.previous) .. unit .. " → " .. num(m.current) .. unit
        b.push(row((m.label or m.name or "?") .. "  " .. spark, value), "Comment")
      end
    end
  end

  b.push("")
  return b
end

M.open = function()
  local results = require("vallow.panel").state.results
  local b = M._lines(results and results.findings)
  return require("vallow.panel.float").open({ title = "Vallow Health", lines = b.lines, hls = b.hls })
end

return M
