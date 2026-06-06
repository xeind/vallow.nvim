local M = {}

local ns = vim.api.nvim_create_namespace("vallow")

-- Module-level store: avoids vim.b integer-key roundtrip bug
local _line_maps = {}

M.get_line_map = function(buf) return _line_maps[buf] or {} end
M.clear        = function(buf) _line_maps[buf] = nil end

M.render = function(buf, results, win)
  local cfg = require("vallow.config").get()
  local lines, line_map, hl_queue = {}, {}, {}

  local win_width = 80
  if win and vim.api.nvim_win_is_valid(win) then
    win_width = vim.api.nvim_win_get_width(win)
  end

  local function push(line, hs, he, hg, me)
    table.insert(lines, line)
    if me  then line_map[#lines] = me end
    if hg  then table.insert(hl_queue, { #lines - 1, hs, he, hg }) end
  end

  local function hl_last(cs, ce, grp)
    table.insert(hl_queue, { #lines - 1, cs, ce, grp })
  end

  -- label + right-aligned count (uses display width so NF icons align)
  local function labeled_row(label, count_str)
    local dw  = vim.fn.strdisplaywidth(label)
    local pad = math.max(1, win_width - dw - #count_str)
    return label .. string.rep(" ", pad) .. count_str
  end

  -- ── Header ──────────────────────────────────────────────────────────
  push("  VALLOW", 2, 8, "VallowHeader")
  push(string.rep("─", win_width), 0, -1, "VallowBorder")

  if results._loading then
    push("  Analyzing…", 2, -1, "VallowLoading")
    M._flush(buf, lines, hl_queue); _line_maps[buf] = line_map; return
  end

  if results.error then
    push("  Error: " .. tostring(results.error), 2, -1, "VallowError")
    M._flush(buf, lines, hl_queue); _line_maps[buf] = line_map; return
  end

  -- ── Active filter ───────────────────────────────────────────────────
  local filter_query = (vim.b[buf].vallow_filter or ""):lower()
  local function matches(item)
    if filter_query == "" then return true end
    return (item.relative_path or ""):lower():find(filter_query, 1, true) ~= nil
        or (item.name          or ""):lower():find(filter_query, 1, true) ~= nil
  end

  -- Show active filter in header
  if filter_query ~= "" then
    local filter_line = string.format("  filter: %s  (F to clear)", filter_query)
    push(filter_line, 2, 10 + #filter_query, "VallowLoading")
  end

  -- ── Fold state (string keys → vim.b roundtrip is safe) ──────────────
  -- Sections: nil / true = open, false = closed
  -- Categories: nil / false = closed, true = open
  local open_secs = vim.b[buf].vallow_open_secs or {}
  local open_cats = vim.b[buf].vallow_open_cats or {}
  local hls       = require("vallow.panel.highlights")

  -- ── Build ordered sections ──────────────────────────────────────────
  local sections        = M._build_sections(cfg)
  local current_section = require("vallow.panel").state.current_section
  local total_issues    = 0


  for _, sec in ipairs(sections) do
    if current_section and sec.key ~= current_section then goto next_sec end
    -- Sum counts for this section (filtered if query active)
    local sec_total = 0
    for _, cat in ipairs(sec.cats) do
      local d = M._resolve_findings(cat.key, cat.cfg, results.findings)
      if d then
        if filter_query ~= "" then
          sec_total = sec_total + #vim.tbl_filter(matches, d.items)
        else
          sec_total = sec_total + (d.count or 0)
        end
      end
    end

    local has_score = sec.key == "health"
      and results.findings and results.findings.health_score

    if sec_total == 0 and not has_score then goto next_sec end

    total_issues = total_issues + sec_total
    local sec_open = open_secs[sec.key] ~= false  -- nil → open

    -- Section header row
    local fold     = sec_open and "▼" or "▶"
    local sec_lbl  = string.format("  %s %s", fold, sec.cfg.label)
    local cnt_str  = sec_total > 0 and tostring(sec_total) or ""
    local sec_line = cnt_str ~= "" and labeled_row(sec_lbl, cnt_str) or sec_lbl
    push(sec_line, 2, #sec_lbl, "VallowSection",
      { _type = "section", key = sec.key })
    if cnt_str ~= "" then
      hl_last(#sec_line - #cnt_str, #sec_line, "VallowCount")
    end

    if not sec_open then goto next_sec end

    -- Health score (shown before categories, no fold needed)
    if has_score then
      local hs  = results.findings.health_score
      local sc  = hs.score and math.floor((hs.score or 0) + 0.5) or "?"
      local gr  = hs.grade and (" · " .. hs.grade) or ""
      push(string.format("    Score  %s/100%s", sc, gr), 4, -1, "VallowFooter")
    end

    -- Categories
    for _, cat in ipairs(sec.cats) do
      local d = M._resolve_findings(cat.key, cat.cfg, results.findings)
      if not d or d.count == 0 then goto next_cat end

      -- Apply filter to items
      local items = d.items
      if filter_query ~= "" then
        items = vim.tbl_filter(matches, items)
        if #items == 0 then goto next_cat end
      end

      local cat_open = open_cats[cat.key] == true  -- nil → closed
      local cat_fold = cat_open and "▼" or "▶"
      local sev_hl   = hls.sev_hl[cat.cfg.severity] or "VallowHeader"

      -- Show filtered count vs total when filter active
      local cat_cnt = filter_query ~= ""
        and (tostring(#items) .. "/" .. tostring(d.count))
        or  tostring(d.count)
      local cat_lbl  = string.format("    %s %s %s", cat_fold, cat.cfg.icon, cat.cfg.label)
      local cat_line = labeled_row(cat_lbl, cat_cnt)
      push(cat_line, 4, #cat_lbl, sev_hl,
        { _type = "header", key = cat.key })
      hl_last(#cat_line - #cat_cnt, #cat_line, sev_hl)

      if cat_open then
        local max   = cfg.max_items or 30
        local full  = (vim.b[buf].vallow_cats_full or {})[cat.key]
        local shown = (full or #items <= max) and items
                      or vim.list_slice(items, 1, max)
        M._render_items(cat.key, shown, push, hl_last, lines, win_width)
        if not full and #items > max then
          local more_line = string.format("      ▶ %d more…", #items - max)
          push(more_line, 6, #more_line, "VallowKind",
            { _type = "more", key = cat.key })
        end
      end

      ::next_cat::
    end

    ::next_sec::
  end

  -- ── Footer ──────────────────────────────────────────────────────────
  push(string.rep("─", win_width), 0, -1, "VallowBorder")
  local ms = results.duration_ms and results.duration_ms > 0
    and ("  " .. results.duration_ms .. "ms") or ""
  push(string.format("  %d issue%s%s",
    total_issues, total_issues == 1 and "" or "s", ms), 0, -1, "VallowFooter")

  M._flush(buf, lines, hl_queue)
  _line_maps[buf] = line_map
end

-- Render items for a category into the running push/hl_last closures
M._render_items = function(cat_key, items, push, hl_last, lines, win_width)
  local indent = "      "  -- 6 spaces under category

  if cat_key == "unused_exports" or cat_key == "unused_types"
      or cat_key == "unused_enum_members" or cat_key == "unused_class_members"
      or cat_key == "unused_members" then
    local path_w, name_w = M._col_widths(items, win_width - 12)
    for _, item in ipairs(items) do
      local rel  = M._truncate(item.relative_path or "", path_w)
      local name = item.name or ""
      local kind = item.kind or ""
      -- Use display-width padding so multi-byte chars (…) don't shift columns
      local row  = indent .. M._dpad(rel, path_w) .. "  " .. M._dpad(name, name_w) .. "  " .. kind
      push(row, #indent, #indent + #rel, "VallowPath", item)
      local n0 = #indent + #M._dpad(rel, path_w) + 2
      hl_last(n0, n0 + #name, "VallowName")
      local k0 = n0 + #M._dpad(name, name_w) + 2
      hl_last(k0, k0 + #kind, "VallowKind")
    end

  elseif cat_key == "unused_files" then
    for _, item in ipairs(items) do
      local p = item.relative_path or ""
      push(indent .. p, #indent, #indent + #p, "VallowPath", item)
    end

  elseif cat_key == "unused_deps" or cat_key == "unused_dev_deps"
      or cat_key == "unused_optional_deps" or cat_key == "unused_all_deps" then
    for _, item in ipairs(items) do
      local n = item.name or ""
      push(indent .. n, #indent, #indent + #n, "VallowName", item)
    end

  elseif cat_key == "unresolved_imports" or cat_key == "unlisted_deps" then
    for _, item in ipairs(items) do
      local n = item.name ~= "" and item.name or (item.relative_path or "")
      push(indent .. n, #indent, #indent + #n, "VallowName", item)
    end

  elseif cat_key == "duplicate_exports" then
    for _, item in ipairs(items) do
      local n = item.name or ""
      push(indent .. n, #indent, #indent + #n, "VallowName", item)
      for _, loc in ipairs(item.locations or {}) do
        local rp  = loc.relative_path or ""
        local ln  = loc.lnum and (":" .. loc.lnum) or ""
        local row = "        " .. rp .. ln
        push(row, 8, 8 + #rp, "VallowPath", loc)
      end
    end

  elseif cat_key == "circular_deps" then
    for _, item in ipairs(items) do
      local p = item.relative_path or ""
      push(indent .. p, #indent, #indent + #p, "VallowPath", item)
    end

  elseif cat_key == "boundary_violations" then
    local path_w = 28
    for _, item in ipairs(items) do
      local p   = M._truncate(item.relative_path or "", path_w)
      local imp = M._truncate(item.import_path   or "", 22)
      local bnd = item.boundary_name or ""
      local row = indent .. M._dpad(p, path_w) .. "  " .. M._dpad(imp, 22) .. "  " .. bnd
      push(row, #indent, #indent + #p, "VallowPath", item)
      local i0 = #indent + #M._dpad(p, path_w) + 2
      hl_last(i0, i0 + #imp, "VallowKind")
      local b0 = i0 + #M._dpad(imp, 22) + 2
      hl_last(b0, b0 + #bnd, "VallowName")
    end

  elseif cat_key == "clone_groups" then
    for _, item in ipairs(items) do
      local name  = M._truncate(item.name or "", 22)
      local parts = {}
      if item.lines  then table.insert(parts, item.lines  .. " ln")  end
      if item.tokens then table.insert(parts, item.tokens .. " tok") end
      local n_inst = #(item.locations or {})
      if n_inst > 0 then table.insert(parts, n_inst .. " inst") end
      local meta = table.concat(parts, " · ")
      local row  = "    " .. M._dpad(name, 22) .. "  " .. meta
      -- jump to first instance on <CR>
      local dest = item.locations and item.locations[1]
      push(row, 4, 4 + #name, "VallowName",
        dest and { path = dest.path, lnum = dest.lnum } or item)
    end

  elseif cat_key == "health_complexity" then
    for _, item in ipairs(items) do
      local p    = M._truncate(item.relative_path or "", 28)
      local name = M._truncate(item.name or "", 16)
      local cyc  = item.cyclomatic and ("cyc:" .. item.cyclomatic) or ""
      local cog  = item.cognitive  and ("cog:" .. item.cognitive)  or ""
      local row  = indent .. M._dpad(p, 28) .. "  " .. M._dpad(name, 16) .. "  " .. cyc .. "  " .. cog
      push(row, #indent, #indent + #p, "VallowPath", item)
      local n0 = #indent + #M._dpad(p, 28) + 2
      hl_last(n0, n0 + #name, "VallowName")
    end

  elseif cat_key == "health_hotspots" then
    for _, item in ipairs(items) do
      local p    = M._truncate(item.relative_path or "", 32)
      local info = ""
      if item.score   then info = info .. "score:"   .. item.score end
      if item.commits then
        if info ~= "" then info = info .. "  " end
        info = info .. "commits:" .. item.commits
      end
      if item.trend and item.trend ~= "" then info = info .. "  " .. item.trend end
      push(indent .. M._dpad(p, 32) .. "  " .. info,
        #indent, #indent + #p, "VallowPath", item)
    end

  elseif cat_key == "health_targets" then
    for _, item in ipairs(items) do
      local p   = M._truncate(item.relative_path or "", 30)
      local rec = M._truncate(item.recommendation or item.category or "", 28)
      push(indent .. M._dpad(p, 30) .. "  " .. rec,
        #indent, #indent + #p, "VallowPath", item)
    end
  end
end

-- Resolve findings for a category.
-- cat_key: the category key; cat_cfg: the category config table (may have .sources).
M._resolve_findings = function(cat_key, cat_cfg, findings)
  if not findings then return nil end
  if cat_cfg.sources then
    local merged = { count = 0, items = {} }
    for _, src in ipairs(cat_cfg.sources) do
      local b = findings[src]
      if b then
        merged.count = merged.count + (b.count or 0)
        for _, item in ipairs(b.items or {}) do
          table.insert(merged.items, item)
        end
      end
    end
    return merged.count > 0 and merged or nil
  end
  return findings[cat_key]
end

-- Group categories by section, sorted
M._build_sections = function(cfg)
  local by_section = {}
  for c_key, c_cfg in pairs(cfg.categories or {}) do
    local s = c_cfg.section or "unused_code"
    if not by_section[s] then by_section[s] = {} end
    table.insert(by_section[s], { key = c_key, cfg = c_cfg })
  end
  local out = {}
  for s_key, s_cfg in pairs(cfg.sections or {}) do
    local cats = by_section[s_key] or {}
    table.sort(cats, function(a, b) return a.cfg.order < b.cfg.order end)
    table.insert(out, { key = s_key, cfg = s_cfg, cats = cats })
  end
  table.sort(out, function(a, b) return a.cfg.order < b.cfg.order end)
  return out
end

M._flush = function(buf, lines, hl_queue)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, h in ipairs(hl_queue) do
    local lnum0, cs, ce, grp = h[1], h[2], h[3], h[4]
    if ce == -1 then ce = #(lines[lnum0 + 1] or "") end
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, grp, lnum0, cs, ce)
  end
  vim.bo[buf].modifiable = false
end

M._col_widths = function(items, available)
  local max_path, max_name = 0, 0
  for _, item in ipairs(items) do
    max_path = math.max(max_path, #(item.relative_path or ""))
    max_name = math.max(max_name, #(item.name or ""))
  end
  return math.min(max_path, math.floor(available * 0.55)),
         math.min(max_name, math.floor(available * 0.25))
end

M._truncate = function(s, max)
  if max <= 0 or #s <= max then return s end
  return "…" .. s:sub(#s - max + 4)
end

-- Pad string to display-width `w` (accounts for multi-byte chars like …)
M._dpad = function(s, w)
  local dw = vim.fn.strdisplaywidth(s)
  return s .. string.rep(" ", math.max(0, w - dw))
end

return M
