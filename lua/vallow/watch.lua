-- watch.lua: one long-lived `fallow watch` per project root, streaming results.
local M = {}

M._job = nil
M._root = nil
M._buf = ""

-- Every analysis starts a new JSON object with this key first.
local MARKER = '{"kind":'

-- fallow watch does not write atomically: a new object can start in the middle
-- of an unfinished one, and progress lines land on the same stream. Keep only
-- the text from the last object start, and emit it once it decodes. A partial
-- object never decodes, because its outer brace is still open.
M._feed = function(chunk, on_object)
  M._buf = M._buf .. chunk
  local last, at = nil, 1
  while true do
    local found = M._buf:find(MARKER, at, true)
    if not found then
      break
    end
    last, at = found, found + 1
  end
  if not last then
    -- Nothing but noise so far; hold back enough for a marker split in two.
    M._buf = M._buf:sub(-#MARKER)
    return
  end
  local candidate = M._buf:sub(last)
  local close = candidate:match("^.*()}")
  if not close then
    M._buf = candidate
    return
  end
  local ok, decoded = pcall(vim.json.decode, candidate:sub(1, close))
  if ok and type(decoded) == "table" then
    M._buf = ""
    on_object(decoded)
  else
    M._buf = candidate
  end
end

-- watch streams the dead-code analysis only. Carry the duplicate and health
-- buckets of the last full run over, so those tabs do not empty out.
local CARRY = {
  "clone_groups",
  "health_complexity",
  "health_hotspots",
  "health_targets",
  "health_score",
  "vital_signs",
  "health_trend",
}

M._carry = function(results, previous)
  local from = previous and previous.findings
  if not from or not results.findings then
    return results
  end
  for _, key in ipairs(CARRY) do
    if from[key] ~= nil then
      results.findings[key] = from[key]
    end
  end
  return results
end

M.is_active = function()
  return M._job ~= nil
end

-- Start watching `root` (default: the detected project root). Every analysis
-- fallow reports is normalized and handed to `on_results`.
M.start = function(on_results)
  local runner = require("vallow.runner")
  local root = runner.find_root()
  if not root then
    vim.notify("vallow: no JS/TS project here", vim.log.levels.WARN)
    return false
  end
  local bin = runner.resolve_cmd(root)
  if not bin then
    vim.notify(require("vallow.install").instructions(), vim.log.levels.ERROR)
    return false
  end
  M.stop()

  local cfg = require("vallow.config").get()
  local cmd = { bin, "watch", "--format", "json", "--quiet", "--no-clear" }
  if require("vallow.panel").state.production then
    table.insert(cmd, "--production")
  end
  for _, a in ipairs(cfg.fallow_args or {}) do
    table.insert(cmd, a)
  end

  M._root = root
  M._buf = ""
  local job = vim.fn.jobstart(cmd, {
    cwd = root,
    env = next(cfg.env or {}) and cfg.env or nil,
    on_stdout = function(_, data)
      M._feed(table.concat(data, "\n"), function(decoded)
        vim.schedule(function()
          if not M._job then
            return
          end
          local panel = require("vallow.panel")
          on_results(M._carry(runner._normalize(decoded, root), panel.state.results))
        end)
      end)
    end,
    on_exit = function(_, code)
      local was = M._job
      M._job = nil
      M._buf = ""
      if was and code ~= 0 then
        vim.schedule(function()
          vim.notify(("vallow: fallow watch exited with code %d"):format(code), vim.log.levels.ERROR)
        end)
      end
    end,
  })
  if job <= 0 then
    vim.notify("vallow: failed to start '" .. bin .. " watch'", vim.log.levels.ERROR)
    return false
  end
  M._job = job

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("VallowWatch", { clear = true }),
    callback = function()
      M.stop()
    end,
  })
  return true
end

M.stop = function()
  if M._job then
    local job = M._job
    M._job = nil
    M._buf = ""
    pcall(vim.fn.jobstop, job)
  end
  M._root = nil
end

-- Restart the watcher on the current root. Used when the root changes.
M.restart = function(on_results)
  if not M._job then
    return false
  end
  M.stop()
  return M.start(on_results)
end

M.toggle = function()
  local panel = require("vallow.panel")
  if M.is_active() then
    M.stop()
    vim.notify("vallow: watch off", vim.log.levels.INFO)
    return false
  end
  if M.start(panel._accept) then
    vim.notify("vallow: watch on — fallow re-runs on every file change", vim.log.levels.INFO)
    return true
  end
  return false
end

return M
