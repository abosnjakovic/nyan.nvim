--- Render dispatcher — routes to the active renderer
local config = require("nyan.config")

local M = {}

--- Get the active renderer module
---@return table
local function get_renderer()
  local cfg = config.get()
  if cfg.renderer == "nyan" then
    return require("nyan.renderers.nyan")
  end
  return require("nyan.renderers.space")
end

--- Initialise the nyan renderer (passthrough, only used for nyan mode)
---@param cat_ids number[]
---@param rainbow_id number
M.init = function(cat_ids, rainbow_id)
  local nyan = require("nyan.renderers.nyan")
  nyan.init(cat_ids, rainbow_id)
end

--- Advance animation frame (nyan renderer only)
---@return number
M.next_frame = function()
  local nyan = require("nyan.renderers.nyan")
  return nyan.next_frame()
end

--- Main render function — delegates to active renderer
---@return string
M.render = function()
  return get_renderer().render()
end

--- Check if nyan graphics mode is enabled
---@return boolean
M.is_graphics_enabled = function()
  local nyan = require("nyan.renderers.nyan")
  return nyan.is_graphics_enabled()
end

return M
