-- nvim-tree decorator: greys out files fallow reports as unused.
-- nvim-tree only renders decorators it was given in its own setup, so add it
-- there:
--   renderer = { decorators = { "Git", "Open", "Hidden", "Modified",
--     "Bookmark", "Diagnostics", "Copied", "Cut",
--     require("vallow.integrations.nvim_tree").decorator } }
local M = {}

local ok, api = pcall(require, "nvim-tree.api")
if ok and api and api.decorator and api.decorator.UserDecorator then
  local Decorator = api.decorator.UserDecorator:extend()

  function Decorator:new()
    self.enabled = true
    self.highlight_range = "name"
    self.icon_placement = "none"
  end

  function Decorator:highlight_group(node)
    local integrations = require("vallow.integrations")
    if not integrations.enabled("nvim_tree") then
      return nil
    end
    if node and node.absolute_path and integrations.is_unused(node.absolute_path) then
      return "VallowUnusedFile"
    end
    return nil
  end

  M.decorator = Decorator
end

return M
