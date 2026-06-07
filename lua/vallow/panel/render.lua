local M = {}

local ns = vim.api.nvim_create_namespace("vallow")

-- Optional nvim-web-devicons integration
local _dv_ok, _dv = pcall(require, "nvim-web-devicons")

local function file_icon(path)
  if not _dv_ok then
    return ""
  end
  local fname = (path or ""):match("([^/\\]+)$") or path or ""
  local ext = fname:match("%.([^%.]+)$")
  local icon = _dv.get_icon(fname, ext, { default = false })
  return icon and (icon .. " ") or ""
end

-- Module-level store: avoids vim.b integer-key roundtrip bug
local _line_maps = {}

M.get_line_map = function(buf)
  return _line_maps[buf] or {}
end
M.clear = function(buf)
  _line_maps[buf] = nil
end

M.render = function(buf, results, win)
  local cfg = require("vallow.config").get()
  local lines, line_map, hl_queue = {}, {}, {}

  -- Save cursor so fold toggles and refreshes don't jump the view
  local saved_cursor
  if win and vim.api.nvim_win_is_valid(win) then
    saved_cursor = vim.api.nvim_win_get_cursor(win)
  end

  local win_width = 80
  if win and vim.api.nvim_win_is_valid(win) then
    win_width = vim.api.nvim_win_get_width(win)
  end

  local function push(line, hs, he, hg, me)
    table.insert(lines, line)
    if me then
      line_map[#lines] = me
    end
    if hg then
      table.insert(hl_queue, { #lines - 1, hs, he, hg })
    end
  end

  local function hl_last(cs, ce, grp)
    table.insert(hl_queue, { #lines - 1, cs, ce, grp })
  end

  -- label + right-aligned count (uses display width so NF icons align)
  local function labeled_row(label, count_str)
    local dw = vim.fn.strdisplaywidth(label)
    local pad = math.max(1, win_width - dw - #count_str)
    return label .. string.rep(" ", pad) .. count_str
  end

  -- ── Header ──────────────────────────────────────────────────────────
  push("  VALLOW", 2, 8, "VallowHeader")
  push(string.rep("─", win_width), 0, -1, "VallowBorder")

  if results._loading then
    push("  Analyzing…", 2, -1, "VallowLoading")
    M._flush(buf, lines, hl_queue)
    _line_maps[buf] = line_map
    return
  end

  if results.error and results.error ~= "" then
    push("  Error: " .. tostring(results.error), 2, -1, "VallowError")
    M._flush(buf, lines, hl_queue)
    _line_maps[buf] = line_map
    return
  end

  -- ── Active filter ───────────────────────────────────────────────────
  local filter_query = (vim.b[buf].vallow_filter or ""):lower()
  local function matches(item)
    if filter_query == "" then
      return true
    end
    return (item.relative_path or ""):lower():find(filter_query, 1, true) ~= nil
      or (item.name or ""):lower():find(filter_query, 1, true) ~= nil
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
  local hls = require("vallow.panel.highlights")

  -- ── Build ordered sections ──────────────────────────────────────────
  local sections = M._build_sections(cfg)
  local current_section = require("vallow.panel").state.current_section
  local total_issues = 0

  for _, sec in ipairs(sections) do
    if current_section == nil or sec.key == current_section then
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

      local has_score = sec.key == "health" and results.findings and results.findings.health_score

      if sec_total > 0 or has_score then
        total_issues = total_issues + sec_total

        -- Blank separator before each section for visual breathing room
        if #lines > 2 then
          push("", 0, 0, nil, nil)
        end

        local sec_open = open_secs[sec.key] ~= false -- nil → open

        -- Section header row
        local fold = sec_open and "▼" or "▶"
        local sec_lbl = string.format("  %s %s", fold, sec.cfg.label)
        local cnt_str = sec_total > 0 and tostring(sec_total) or ""
        local sec_padded = M._dpad(sec_lbl, 26)
        local sec_line = sec_padded .. cnt_str
        push(sec_line, 2, #sec_lbl, "VallowSection", { _type = "section", key = sec.key })
        if cnt_str ~= "" then
          hl_last(#sec_padded, #sec_line, "VallowCount")
        end

        if sec_open then
          -- Health score (shown before categories, no fold needed)
          if has_score then
            local hs = results.findings.health_score
            local sc = hs.score and math.floor((hs.score or 0) + 0.5) or "?"
            local gr = hs.grade and (" · " .. hs.grade) or ""
            push(string.format("    Score  %s/100%s", sc, gr), 4, -1, "VallowFooter")
          end

          -- Categories
          for _, cat in ipairs(sec.cats) do
            local d = M._resolve_findings(cat.key, cat.cfg, results.findings)
            if d and d.count > 0 then
              -- Apply filter to items
              local items = d.items
              if filter_query ~= "" then
                items = vim.tbl_filter(matches, items)
              end

              if #items > 0 then
                local cat_open = open_cats[cat.key] == true -- nil → closed
                local cat_fold = cat_open and "▼" or "▶"
                local sev_hl = hls.sev_hl[cat.cfg.severity] or "VallowHeader"

                -- Show filtered count vs total when filter active
                local cat_cnt = filter_query ~= "" and (tostring(#items) .. "/" .. tostring(d.count))
                  or tostring(d.count)
                local cat_lbl = string.format("    %s %s %s", cat_fold, cat.cfg.icon, cat.cfg.label)
                local cat_padded = M._dpad(cat_lbl, 34)
                local cat_line = cat_padded .. cat_cnt
                push(cat_line, 4, #cat_lbl, sev_hl, { _type = "header", key = cat.key })
                hl_last(#cat_padded, #cat_padded + #cat_cnt, sev_hl)

                if cat_open then
                  local max = cfg.max_items or 30
                  local full = (vim.b[buf].vallow_cats_full or {})[cat.key]
                  local shown = (full or #items <= max) and items or vim.list_slice(items, 1, max)
                  M._render_items(cat.key, shown, push, hl_last, lines, win_width)
                  if not full and #items > max then
                    local more_line = string.format("      ▶ %d more…", #items - max)
                    push(more_line, 6, #more_line, "VallowKind", { _type = "more", key = cat.key })
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- ── Footer ──────────────────────────────────────────────────────────
  push(string.rep("─", win_width), 0, -1, "VallowBorder")
  local ms = results.duration_ms and results.duration_ms > 0 and ("  " .. results.duration_ms .. "ms") or ""
  push(string.format("  %d issue%s%s", total_issues, total_issues == 1 and "" or "s", ms), 0, -1, "VallowFooter")

  -- Key hint bar
  local hints = {
    { "za", "fold" },
    { "<CR>", "jump" },
    { "P", "peek" },
    { "f", "filter" },
    { "%", "cur file" },
    { "r", "refresh" },
    { "?", "help" },
  }
  local hint_parts = {}
  for _, h in ipairs(hints) do
    table.insert(hint_parts, h[1] .. " " .. h[2])
  end
  local hint_line = "  " .. table.concat(hint_parts, "  ·  ")
  push(hint_line, 0, -1, "VallowFooter")

  M._flush(buf, lines, hl_queue)
  _line_maps[buf] = line_map

  -- Restore cursor position (clamped to new line count)
  if saved_cursor and win and vim.api.nvim_win_is_valid(win) then
    local nlines = vim.api.nvim_buf_line_count(buf)
    pcall(vim.api.nvim_win_set_cursor, win, { math.min(math.max(1, saved_cursor[1]), nlines), saved_cursor[2] })
  end
end

-- Render items for a category into the running push/hl_last closures
M._render_items = function(cat_key, items, push, hl_last, lines, win_width)
  local indent = "      " -- 6 spaces under category

  if
    cat_key == "unused_exports"
    or cat_key == "unused_types"
    or cat_key == "unused_enum_members"
    or cat_key == "unused_class_members"
    or cat_key == "unused_members"
  then
    local path_w, name_w = M._col_widths(items, win_width - 12)
    do
      local hdr = indent .. M._dpad("file", path_w) .. "  " .. M._dpad("export", name_w) .. "  " .. "kind"
      push(hdr, 0, -1, "VallowKind", nil)
    end
    for _, item in ipairs(items) do
      local rel = M._truncate(item.relative_path or "", path_w)
      local name = item.name or ""
      local kind = item.kind or ""
      -- Use display-width padding so multi-byte chars (…) don't shift columns
      local row = indent .. M._dpad(rel, path_w) .. "  " .. M._dpad(name, name_w) .. "  " .. kind
      push(row, #indent, #indent + #rel, "VallowPath", item)
      local n0 = #indent + #M._dpad(rel, path_w) + 2
      hl_last(n0, n0 + #name, "VallowName")
      local k0 = n0 + #M._dpad(name, name_w) + 2
      hl_last(k0, k0 + #kind, "VallowKind")
    end
  elseif cat_key == "unused_files" then
    for _, item in ipairs(items) do
      local p = item.relative_path or ""
      local icon = file_icon(p)
      push(indent .. icon .. p, #indent, #indent + #icon + #p, "VallowPath", item)
    end
  elseif
    cat_key == "unused_deps"
    or cat_key == "unused_dev_deps"
    or cat_key == "unused_optional_deps"
    or cat_key == "unused_all_deps"
  then
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
      push(indent .. n, #indent, #indent + #n, "VallowSymbol", item)
      for _, loc in ipairs(item.locations or {}) do
        local rp = loc.relative_path or ""
        local ln = loc.lnum and (":" .. loc.lnum) or ""
        local row = "        " .. rp .. ln
        push(row, 8, 8 + #rp, "VallowPath", loc)
      end
    end
  elseif cat_key == "circular_deps" then
    local function basename(p)
      if type(p) ~= "string" or p == "" then
        return nil
      end
      return p:match("([^/\\]+)$") or p
    end
    for _, item in ipairs(items) do
      local cycle = item.cycle or {}
      -- Build chain from cycle array if it has at least 2 distinct entries
      local chain
      if #cycle >= 2 then
        local parts = {}
        for _, p in ipairs(cycle) do
          local name = basename(p)
          if name and name ~= "" then
            table.insert(parts, name)
          end
        end
        if #parts >= 2 then
          table.insert(parts, parts[1]) -- close the loop visually
          chain = table.concat(parts, " → ")
        end
      end
      -- Fall back to just showing the entry file
      if chain then
        local row = indent .. chain
        push(row, 0, 0, nil, item)
        -- highlight filenames as VallowPath, " → " separators as VallowBorder
        local sep = " → "
        local segs = vim.split(chain, sep, { plain = true })
        local pos = #indent
        for i, seg in ipairs(segs) do
          hl_last(pos, pos + #seg, "VallowPath")
          pos = pos + #seg
          if i < #segs then
            -- " → ": dim the arrow so filenames stand out
            hl_last(pos, pos + #sep, "NonText")
            pos = pos + #sep
          end
        end
      else
        local row = indent .. (item.relative_path or item.path or "")
        push(row, #indent, -1, "VallowPath", item)
      end
    end
  elseif cat_key == "boundary_violations" then
    local path_w = 28
    do
      local hdr = indent .. M._dpad("file", path_w) .. "  " .. M._dpad("import", 22) .. "  " .. "boundary"
      push(hdr, 0, -1, "VallowKind", nil)
    end
    for _, item in ipairs(items) do
      local p = M._truncate(item.relative_path or "", path_w)
      local imp = M._truncate(item.import_path or "", 22)
      local bnd = item.boundary_name or ""
      local row = indent .. M._dpad(p, path_w) .. "  " .. M._dpad(imp, 22) .. "  " .. bnd
      push(row, #indent, #indent + #p, "VallowPath", item)
      local i0 = #indent + #M._dpad(p, path_w) + 2
      hl_last(i0, i0 + #imp, "VallowKind")
      local b0 = i0 + #M._dpad(imp, 22) + 2
      hl_last(b0, b0 + #bnd, "VallowName")
    end
  elseif cat_key == "clone_groups" then
    local sub = "        " -- 8-space indent for location sub-rows

    -- Pre-pass: compute actual display names and find max width
    local function clone_disp(item)
      local nm = item.name or ""
      if nm:match("^dup:") then
        local f = (item.locations or {})[1]
        if f then
          local rp = f.relative_path or f.path or ""
          nm = rp:match("([^/\\]+)$") or nm
        end
      end
      return nm
    end
    local name_col_w = 0
    for _, it in ipairs(items) do
      name_col_w = math.max(name_col_w, #clone_disp(it))
    end
    name_col_w = math.min(name_col_w, 28)

    do
      local hdr = indent .. M._dpad("name", name_col_w) .. "   " .. M._dpad("size", 7) .. "   " .. "copies"
      push(hdr, 0, -1, "VallowKind", nil)
    end
    for _, item in ipairs(items) do
      local locs = item.locations or {}
      local n_inst = #locs
      local first = locs[1]

      local disp = M._truncate(clone_disp(item), name_col_w)

      -- Size: lines is the most meaningful metric
      local size_s = item.lines and (item.lines .. " ln") or ""
      local size_n = tonumber(item.lines) or 0
      local size_hl = size_n >= 50 and "VallowSevWarn" or size_n >= 20 and "VallowSevHint" or "VallowKind"

      -- Instance count: × prefix reads more naturally than "N inst"
      local cnt_s = n_inst > 0 and ("\xc3\x97" .. n_inst) or "" -- × U+00D7
      local cnt_hl = n_inst >= 5 and "VallowSevWarn" or n_inst >= 3 and "VallowSevHint" or "VallowKind"

      -- Header row: name · size · count
      local name_padded = M._dpad(disp, name_col_w)
      local gap = "   "
      local row = indent .. name_padded .. gap
      local sz_pos = #row
      row = row .. M._dpad(size_s, 7) .. gap
      local cn_pos = #row
      row = row .. cnt_s

      push(row, 0, 0, nil, first and { path = first.path, lnum = first.lnum } or item)
      hl_last(#indent, #indent + #disp, "VallowName")
      if size_s ~= "" then
        hl_last(sz_pos, sz_pos + #size_s, size_hl)
      end
      if cnt_s ~= "" then
        hl_last(cn_pos, cn_pos + #cnt_s, cnt_hl)
      end

      -- Location sub-rows — each clickable, this is what "inst" actually means
      for _, loc in ipairs(locs) do
        local icon = file_icon(loc.relative_path or "")
        local rp = M._truncate(loc.relative_path or "", win_width - #sub - #icon - 6)
        local ln = loc.lnum and (":" .. loc.lnum) or ""
        local sub_row = sub .. icon .. rp .. ln
        push(sub_row, #sub, #sub + #icon + #rp, "VallowPath", { path = loc.path, lnum = loc.lnum })
        if ln ~= "" then
          hl_last(#sub + #icon + #rp, #sub + #icon + #rp + #ln, "VallowKind")
        end
      end
    end
  elseif cat_key == "health_complexity" then
    -- Cyclomatic: industry thresholds 1-10 fine, 11-20 moderate, 21-50 high, >50 critical
    -- Cognitive: tighter scale — SonarQube-ish: >7 hint, >15 warn, >30 error
    local function cyc_hl(n)
      n = tonumber(n) or 0
      if n > 50 then
        return "VallowSevError"
      elseif n > 20 then
        return "VallowSevWarn"
      elseif n > 10 then
        return "VallowSevHint"
      else
        return "VallowKind"
      end
    end
    local function cog_hl(n)
      n = tonumber(n) or 0
      if n > 30 then
        return "VallowSevError"
      elseif n > 15 then
        return "VallowSevWarn"
      elseif n > 7 then
        return "VallowSevHint"
      else
        return "VallowKind"
      end
    end

    -- Single-line: name | basename | cyc | cog
    -- Full path accessible via K or <CR>. Columns sized from data.
    local function basename(p)
      return (p or ""):match("([^/\\]+)$") or p or ""
    end

    local name_w, file_w, cyc_w, cog_w = 0, 0, 0, 0
    for _, it in ipairs(items) do
      local nm = it.name == "<arrow>" and "λ" or (it.name or "")
      name_w = math.max(name_w, #nm)
      file_w = math.max(file_w, #basename(it.relative_path))
      if it.cyclomatic then
        cyc_w = math.max(cyc_w, #tostring(it.cyclomatic))
      end
      if it.cognitive then
        cog_w = math.max(cog_w, #tostring(it.cognitive))
      end
    end
    -- Cap and ensure header labels fit
    name_w = math.max(math.min(name_w, 28), 4) -- "name"
    file_w = math.max(math.min(file_w, 30), 4) -- "file"
    cyc_w = math.max(cyc_w, 3) -- "cyc"
    cog_w = math.max(cog_w, 3) -- "cog"

    local gap = "  "
    do
      local hdr = indent
        .. M._dpad("name", name_w)
        .. gap
        .. M._dpad("file", file_w)
        .. gap
        .. M._dpad("cyc", cyc_w)
        .. gap
        .. "cog"
      push(hdr, 0, -1, "VallowKind", nil)
    end

    for _, item in ipairs(items) do
      local name = item.name == "<arrow>" and "λ" or (item.name or "")
      local file = basename(item.relative_path)
      local cyc_s = item.cyclomatic and tostring(item.cyclomatic) or ""
      local cog_s = item.cognitive and tostring(item.cognitive) or ""

      local row = indent .. M._dpad(name, name_w) .. gap
      local file_pos = #row
      row = row .. M._dpad(file, file_w) .. gap
      local cyc_pos = #row
      row = row .. M._dpad(cyc_s, cyc_w) .. gap
      local cog_pos = #row
      row = row .. cog_s

      push(row, #indent, #indent + #name, "VallowName", item)
      hl_last(file_pos, file_pos + #file, "VallowPath")
      if cyc_s ~= "" then
        hl_last(cyc_pos, cyc_pos + #cyc_s, cyc_hl(item.cyclomatic))
      end
      if cog_s ~= "" then
        hl_last(cog_pos, cog_pos + #cog_s, cog_hl(item.cognitive))
      end
    end
  elseif cat_key == "health_hotspots" then
    -- Pre-compute column widths and max score (for relative coloring) in one pass.
    local max_score_num = 0
    local score_col_w, commits_col_w = 0, 0
    for _, it in ipairs(items) do
      local n = tonumber(it.score)
      if n and n > max_score_num then
        max_score_num = n
      end
      if it.score ~= nil then
        score_col_w = math.max(score_col_w, #tostring(it.score))
      end
      if it.commits ~= nil then
        commits_col_w = math.max(commits_col_w, #tostring(it.commits))
      end
    end

    local path_w = math.min(36, math.floor((win_width - #indent) * 0.55))
    -- Ensure column widths fit their header labels
    score_col_w = math.max(score_col_w, 5) -- "score"
    commits_col_w = math.max(commits_col_w, 7) -- "commits"
    local gap = "   " -- 3-space column separator

    do
      local hdr = indent
        .. M._dpad("file", path_w)
        .. gap
        .. M._dpad("score", score_col_w)
        .. gap
        .. M._dpad("commits", commits_col_w)
        .. gap
        .. "trend"
      push(hdr, 0, -1, "VallowKind", nil)
    end

    for _, item in ipairs(items) do
      local p = M._truncate(item.relative_path or "", path_w)
      local score_s = item.score ~= nil and tostring(item.score) or ""
      local commits_s = item.commits ~= nil and tostring(item.commits) or ""
      local trend_s = (item.trend and item.trend ~= "") and item.trend or ""

      -- Score: relative to batch max so the gradient means something per-project
      local score_hl = "VallowKind"
      local sn = tonumber(item.score)
      if sn and max_score_num > 0 then
        local r = sn / max_score_num
        if r >= 0.7 then
          score_hl = "VallowSevError"
        elseif r >= 0.35 then
          score_hl = "VallowSevWarn"
        else
          score_hl = "VallowSevHint"
        end
      end

      -- Trend: semantic direction coloring
      local trend_hl = "VallowKind"
      if trend_s == "heating" then
        trend_hl = "VallowSevError"
      elseif trend_s == "stable" then
        trend_hl = "VallowSevWarn"
      elseif trend_s == "cooling" then
        trend_hl = "VallowSevHint"
      end

      -- Fixed-width columns so values line up regardless of digit count
      local p_padded = M._dpad(p, path_w)
      local sc_padded = M._dpad(score_s, score_col_w)
      local cm_padded = M._dpad(commits_s, commits_col_w)

      local row = indent .. p_padded .. gap
      local sc_pos = #row
      row = row .. sc_padded .. gap
      local cm_pos = #row
      row = row .. cm_padded .. gap
      local tr_pos = #row
      row = row .. trend_s

      push(row, 0, 0, nil, item)
      hl_last(#indent, #indent + #p, "VallowPath")
      if score_s ~= "" then
        hl_last(sc_pos, sc_pos + #score_s, score_hl)
      end
      if commits_s ~= "" then
        hl_last(cm_pos, cm_pos + #commits_s, "VallowCount")
      end
      if trend_s ~= "" then
        hl_last(tr_pos, tr_pos + #trend_s, trend_hl)
      end
    end
  elseif cat_key == "health_targets" then
    -- Map a priority value to a diagnostic highlight group.
    -- Uses DiagnosticError/Warn/Hint — always themed by the active colorscheme.
    -- Refactoring is advisory — no red. Scale is warn (notable) → hint (mild) → dim.
    local function pri_hl(item)
      local pri = item.priority
      if type(pri) == "number" then
        if pri >= 7 then
          return "VallowSevWarn"
        elseif pri >= 4 then
          return "VallowSevHint"
        else
          return "VallowKind"
        end
      end
      if type(pri) == "string" then
        local s = pri:lower()
        if s == "high" or s == "critical" then
          return "VallowSevWarn"
        elseif s == "medium" or s == "moderate" then
          return "VallowSevHint"
        elseif s == "low" or s == "minor" then
          return "VallowKind"
        end
      end
      -- Fallback: extract percentage from "reduce surface area (75% dead)" style text
      local pct = tonumber((item.recommendation or ""):match("%((%d+)%%"))
      if pct then
        if pct >= 75 then
          return "VallowSevWarn"
        elseif pct >= 40 then
          return "VallowSevHint"
        else
          return "VallowKind"
        end
      end
      return "VallowKind"
    end

    local extra = "        " -- 8 spaces: one extra level of indent
    for _, item in ipairs(items) do
      local icon = file_icon(item.relative_path or "")
      local p = M._truncate(item.relative_path or "", win_width - #indent - #icon - 2)
      local rec = item.recommendation or item.category or ""
      push(indent .. icon .. p, #indent, #indent + #icon + #p, "VallowPath", item)
      if rec ~= "" then
        push(extra .. rec, #extra, -1, pri_hl(item), item)
      end
    end
  end
end

-- Resolve findings for a category.
-- cat_key: the category key; cat_cfg: the category config table (may have .sources).
M._resolve_findings = function(cat_key, cat_cfg, findings)
  if not findings then
    return nil
  end
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
    if not by_section[s] then
      by_section[s] = {}
    end
    table.insert(by_section[s], { key = c_key, cfg = c_cfg })
  end
  local out = {}
  for s_key, s_cfg in pairs(cfg.sections or {}) do
    local cats = by_section[s_key] or {}
    table.sort(cats, function(a, b)
      return a.cfg.order < b.cfg.order
    end)
    table.insert(out, { key = s_key, cfg = s_cfg, cats = cats })
  end
  table.sort(out, function(a, b)
    return a.cfg.order < b.cfg.order
  end)
  return out
end

M._flush = function(buf, lines, hl_queue)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, h in ipairs(hl_queue) do
    local lnum0, cs, ce, grp = h[1], h[2], h[3], h[4]
    if ce == -1 then
      ce = #(lines[lnum0 + 1] or "")
    end
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
  return math.min(max_path, math.floor(available * 0.55)), math.min(max_name, math.floor(available * 0.25))
end

M._truncate = function(s, max)
  if max <= 0 or #s <= max then
    return s
  end
  return "…" .. s:sub(#s - max + 4)
end

-- Pad string to display-width `w` (accounts for multi-byte chars like …)
M._dpad = function(s, w)
  local dw = vim.fn.strdisplaywidth(s)
  return s .. string.rep(" ", math.max(0, w - dw))
end

return M
