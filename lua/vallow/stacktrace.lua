-- stacktrace.lua: `fallow trace-error` (3.24+) fills the quickfix list with
-- the frames of a pasted stack trace that name project source.
local M = {}

-- `fallow trace-error` arrived in 3.24.0.
local MIN_VERSION = { 3, 24, 0 }

-- False when the last analysis ran an older fallow than 3.24. An unknown
-- version passes; the job then reports the unknown subcommand.
local function supported()
  local results = require("vallow.panel").state.results
  local parsed = results and results.version and vim.version.parse(tostring(results.version))
  return not parsed or vim.version.cmp(parsed, MIN_VERSION) >= 0
end

-- Map the `trace-error` JSON to quickfix items. A frame with a file that
-- fallow resolved or found ambiguous becomes one item at the frame's own
-- line and column. Other frames are skipped: not_found, not_attempted,
-- dependency and runtime-internal frames name no file to open.
M._items = function(data, root)
  local items = {}
  for _, frame in ipairs(type(data) == "table" and data.frames or {}) do
    local file = type(frame) == "table" and frame.file
    if type(file) == "string" and (frame.resolution == "resolved" or frame.resolution == "ambiguous") then
      local candidate = type(frame.candidates) == "table" and frame.candidates[1] or {}
      local text = type(frame["function"]) == "string" and frame["function"] or frame.raw or ""
      if frame.resolution == "ambiguous" then
        text = text .. " (ambiguous)"
      end
      table.insert(items, {
        filename = file:sub(1, 1) == "/" and file or (root .. "/" .. file),
        lnum = tonumber(frame.line) or tonumber(candidate.line) or 1,
        col = tonumber(frame.column) or 1,
        text = text,
      })
    end
  end
  return items
end

M._fill = function(data, root)
  local items = M._items(data, root)
  if #items == 0 then
    vim.notify("vallow: no stack frame names project source", vim.log.levels.WARN)
    return
  end
  vim.fn.setqflist({}, " ", { title = "vallow stacktrace", items = items })
  vim.cmd("copen")
end

-- Trace the lines of `text`, a stack trace.
M.trace = function(text)
  if not supported() then
    vim.notify("vallow: stacktrace needs fallow 3.24 or newer", vim.log.levels.WARN)
    return
  end
  if vim.trim(text) == "" then
    vim.notify("vallow: no stack trace in the selection or register", vim.log.levels.WARN)
    return
  end
  local runner = require("vallow.runner")
  local root = runner.find_root()
  if not root then
    vim.notify("vallow: no JS/TS project here", vim.log.levels.WARN)
    return
  end
  local bin = runner.resolve_cmd(root)
  if not bin then
    vim.notify(require("vallow.install").instructions(), vim.log.levels.ERROR)
    return
  end
  -- runner._job gives the child no stdin, so pass the trace as a file.
  local file = vim.fn.tempname()
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), file)
  runner._job({ bin, "trace-error", file, "--format", "json", "--quiet" }, root, function(ok, data)
    os.remove(file)
    vim.schedule(function()
      if not ok or type(data) ~= "table" then
        vim.notify("vallow: stacktrace failed: " .. tostring(data), vim.log.levels.ERROR)
        return
      end
      M._fill(data, root)
    end)
  end)
end

-- Entry for `:Vallow stacktrace`. With a range, read those lines; otherwise
-- read the `+` register, then the unnamed register.
M.open = function(line1, line2)
  local text
  if line1 and line2 then
    text = table.concat(vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false), "\n")
  else
    text = vim.fn.getreg("+")
    if vim.trim(text) == "" then
      text = vim.fn.getreg('"')
    end
  end
  M.trace(text)
end

return M
