-- exporter.lua: converts vallow results into external formats.
local M = {}

-- Returns a list of lines representing the findings as GitHub-flavoured markdown.
M.to_markdown = function(results)
  local lines = {}
  local function push(l)
    table.insert(lines, l or "")
  end

  local cfg = require("vallow.config").get()
  local LABEL = require("vallow.labels").label

  -- Total count
  local total = 0
  for _, b in pairs(results.findings or {}) do
    if type(b) == "table" and b.count then
      total = total + b.count
    end
  end

  push("# Vallow Report")
  push("")
  local root_display = results.repo_root and results.repo_root:match("([^/]+)$") or "project"
  push(string.format("**%d issue%s** · `%s`", total, total == 1 and "" or "s", root_display))
  if results.duration_ms and results.duration_ms > 0 then
    push(string.format("*Analyzed in %d ms*", results.duration_ms))
  end
  if results.findings and results.findings.health_score then
    local hs = results.findings.health_score
    local sc = hs.score and math.floor((hs.score or 0) + 0.5) or "?"
    local gr = hs.grade and (" · grade **" .. hs.grade .. "**") or ""
    push(string.format("Health score: **%s/100**%s", sc, gr))
  end
  push("")

  -- Build ordered sections
  local sections = {}
  for s_key, s_cfg in pairs(cfg.sections or {}) do
    table.insert(sections, { key = s_key, cfg = s_cfg })
  end
  table.sort(sections, function(a, b)
    return a.cfg.order < b.cfg.order
  end)

  for _, sec in ipairs(sections) do
    -- Collect categories for this section that have findings
    local cats = {}
    for c_key, c_cfg in pairs(cfg.categories or {}) do
      if c_cfg.section == sec.key then
        local d
        if c_cfg.sources then
          d = { count = 0, items = {} }
          for _, src in ipairs(c_cfg.sources) do
            local b = results.findings and results.findings[src]
            if b then
              d.count = d.count + (b.count or 0)
              for _, item in ipairs(b.items or {}) do
                table.insert(d.items, item)
              end
            end
          end
          if d.count == 0 then
            d = nil
          end
        else
          d = results.findings and results.findings[c_key]
        end
        if d and d.count and d.count > 0 then
          table.insert(cats, { key = c_key, cfg = c_cfg, d = d })
        end
      end
    end

    if #cats > 0 then
      table.sort(cats, function(a, b)
        return a.cfg.order < b.cfg.order
      end)
      push("## " .. sec.cfg.label)
      push("")
      for _, cat in ipairs(cats) do
        push("### " .. (LABEL[cat.key] or cat.key) .. " (" .. cat.d.count .. ")")
        push("")
        local items = cat.d.items or {}
        -- Show up to 50 items per category to keep the report readable
        local shown = math.min(#items, 50)
        for i = 1, shown do
          local item = items[i]
          local loc = item.relative_path or item.path or ""
          if item.lnum and item.lnum > 1 then
            loc = loc .. ":" .. item.lnum
          end
          local name = item.name and item.name ~= "" and (" `" .. item.name .. "`") or ""
          push("- `" .. loc .. "`" .. name)
        end
        if #items > shown then
          push(string.format("- *… and %d more*", #items - shown))
        end
        push("")
      end
    end
  end

  return lines
end

return M
