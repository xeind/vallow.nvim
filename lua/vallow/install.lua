-- install.lua: download the standalone fallow binary into stdpath("data").
-- Signatures (.sig assets) are published but not verified here.
local M = {}

-- Pinned fallback when the GitHub API is unreachable, and the floor
-- :checkhealth warns below.
M.MIN_VERSION = "3.22.0"

local REPO = "fallow-rs/fallow"

M.dir = function()
  return vim.fn.stdpath("data") .. "/vallow/bin"
end

-- Path the binary is installed to. `name` is "fallow" or "fallow-lsp".
M.path = function(name)
  local exe = vim.fn.has("win32") == 1 and ".exe" or ""
  return M.dir() .. "/" .. (name or "fallow") .. exe
end

local function is_musl()
  if vim.fn.filereadable("/etc/alpine-release") == 1 then
    return true
  end
  return (vim.fn.system("ldd --version 2>&1") or ""):lower():find("musl") ~= nil
end

-- Release asset suffix for this machine, or nil when there is no build for it.
M.platform = function()
  local uname = vim.uv.os_uname()
  local machine = (uname.machine or ""):lower()
  local arm = machine:find("arm") ~= nil or machine:find("aarch64") ~= nil
  local arch = arm and "arm64" or "x64"
  if vim.fn.has("win32") == 1 then
    return "win32-" .. arch .. "-msvc.exe"
  end
  local sys = (uname.sysname or ""):lower()
  if sys == "darwin" then
    return "darwin-" .. arch
  end
  if sys == "linux" then
    return "linux-" .. arch .. "-" .. (is_musl() and "musl" or "gnu")
  end
  return nil
end

-- Latest published version, blocking for at most `timeout` ms.
-- Falls back to MIN_VERSION when offline.
M.latest_version = function(timeout)
  local url = ("https://api.github.com/repos/%s/releases/latest"):format(REPO)
  local ok, res = pcall(function()
    return vim.system({ "curl", "-fsSL", url }, { text = true }):wait(timeout or 5000)
  end)
  if ok and res and res.code == 0 then
    local decoded_ok, decoded = pcall(vim.json.decode, res.stdout or "")
    if decoded_ok and type(decoded) == "table" and type(decoded.tag_name) == "string" then
      return (decoded.tag_name:gsub("^v", ""))
    end
  end
  return M.MIN_VERSION
end

-- Download one asset. opts: { binary = "fallow"|"fallow-lsp", version = "3.22.0" }
-- callback(ok, message) runs on the main loop.
M.install = function(opts, callback)
  opts = opts or {}
  callback = callback or function() end
  local binary = opts.binary or "fallow"
  local plat = M.platform()
  if not plat then
    callback(false, "vallow: no fallow build for this platform — install with: npm i -g fallow")
    return
  end
  local version = opts.version or M.latest_version()
  local asset = binary .. "-" .. plat
  local url = ("https://github.com/%s/releases/download/v%s/%s"):format(REPO, version, asset)
  local dest = M.path(binary)
  local tmp = dest .. ".download"

  vim.fn.mkdir(M.dir(), "p")
  vim.notify("vallow: downloading " .. asset .. " " .. version .. "…", vim.log.levels.INFO)

  vim.system({ "curl", "-fL", "--retry", "2", "-o", tmp, url }, { text = true }, function(dl)
    vim.schedule(function()
      if dl.code ~= 0 then
        vim.fn.delete(tmp)
        callback(false, "vallow: download failed: " .. vim.trim(dl.stderr or ("curl exit " .. dl.code)))
        return
      end
      vim.uv.fs_chmod(tmp, 493) -- 0755
      local renamed, rename_err = vim.uv.fs_rename(tmp, dest)
      if not renamed then
        vim.fn.delete(tmp)
        callback(false, "vallow: cannot write " .. dest .. ": " .. tostring(rename_err))
        return
      end
      vim.system({ dest, "--version" }, { text = true }, function(check)
        vim.schedule(function()
          if check.code ~= 0 then
            callback(false, "vallow: " .. dest .. " does not run: " .. vim.trim(check.stderr or ""))
            return
          end
          local reported = vim.trim((check.stdout or ""):match("^[^\n]*") or "")
          vim.notify("vallow: installed " .. reported .. " → " .. dest, vim.log.levels.INFO)
          callback(true, dest)
        end)
      end)
    end)
  end)
end

-- Text shown when fallow is missing and the user declines the download.
M.instructions = function()
  return table.concat({
    "fallow not found.",
    "Install it with one of:",
    "  :VallowInstall            (standalone binary into " .. M.dir() .. ")",
    "  npm i -g fallow",
    "  npm i -D fallow           (resolved from node_modules/.bin)",
  }, "\n")
end

-- Asked at most once per session so a missing binary cannot nag on every run.
local _asked = false

-- Offer the download. callback(installed) runs after the answer (and the
-- install, when accepted).
M.prompt = function(callback)
  if _asked then
    callback(false)
    return
  end
  _asked = true
  local version = M.latest_version(3000)
  local answer = vim.fn.confirm("fallow not found. Download " .. version .. " now?", "&Yes\n&No", 2)
  if answer ~= 1 then
    callback(false)
    return
  end
  M.install({ version = version }, function(ok, msg)
    if not ok then
      vim.notify(msg, vim.log.levels.ERROR)
    end
    callback(ok)
  end)
end

return M
