---@class NyanAnimationConfig
---@field enabled boolean Enable/disable animation
---@field fps number Frames per second

---@class NyanConfig
---@field width number Total component width in terminal cells
---@field animation NyanAnimationConfig Animation settings
---@field min_buffer_lines number Minimum lines to show component
---@field fallback "ascii"|"none" Fallback mode if graphics not supported
---@field debug boolean Enable debug logging

local M = {}

---@type NyanConfig
M.defaults = {
  width = 20,
  animation = {
    enabled = true,
    fps = 6,
  },
  min_buffer_lines = 10,
  fallback = "ascii",
  debug = false,
}

--- Log a debug message if debug mode is enabled
---@param msg string Message to log
---@param ... any Additional values to include
M.log = function(msg, ...)
  if not M.options.debug then
    return
  end
  local args = { ... }
  if #args > 0 then
    local parts = { msg }
    for _, v in ipairs(args) do
      table.insert(parts, vim.inspect(v))
    end
    msg = table.concat(parts, " ")
  end
  vim.notify("[nyan.nvim] " .. msg, vim.log.levels.DEBUG)
end

---@type NyanConfig
M.options = vim.deepcopy(M.defaults)

---@param opts NyanConfig?
---@return NyanConfig
M.setup = function(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

---@return NyanConfig
M.get = function()
  return M.options
end

return M
