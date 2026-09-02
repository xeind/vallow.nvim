-- oil.nvim: greys out files fallow reports as unused.
-- oil reads the highlight function from its own setup, so add it there:
--   view_options = { highlight_filename =
--     require("vallow.integrations.oil").highlight_filename }
local M = {}

M.highlight_filename = function(entry)
  local integrations = require("vallow.integrations")
  if not integrations.enabled("oil") then
    return nil
  end
  if not entry or not entry.name or entry.type == "directory" then
    return nil
  end
  local ok, oil = pcall(require, "oil")
  if not ok then
    return nil
  end
  local dir = oil.get_current_dir()
  if not dir or dir == "" then
    return nil
  end
  if integrations.is_unused(dir:gsub("/$", "") .. "/" .. entry.name) then
    return "VallowUnusedFile"
  end
  return nil
end

return M
