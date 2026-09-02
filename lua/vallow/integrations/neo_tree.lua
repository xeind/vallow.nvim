-- neo-tree: greys out files fallow reports as unused.
-- neo-tree resolves components from its own setup, so override the name
-- component there:
--   components = { name = require("vallow.integrations.neo_tree").name }
local M = {}

M.name = function(config, node, state)
  local common = require("neo-tree.sources.common.components")
  local res = common.name(config, node, state)
  local integrations = require("vallow.integrations")
  if not integrations.enabled("neo_tree") then
    return res
  end
  if node and node.type == "file" and integrations.is_unused(node.path) then
    if type(res) == "table" and res.text ~= nil then
      res.highlight = "VallowUnusedFile"
    end
  end
  return res
end

return M
