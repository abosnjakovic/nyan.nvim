local M = {}

--- Calculate scroll percentage (0.0 to 1.0)
--- At line 1, returns 0. At last line, returns 1.
---@return number position Scroll position as fraction (0-1)
M.get_scroll_position = function()
  local current_line = vim.fn.line(".")
  local total_lines = vim.fn.line("$")

  if total_lines <= 1 then
    return 0
  end

  local position = (current_line - 1) / (total_lines - 1)
  return math.max(0, math.min(1, position))
end

--- Check if component should be displayed based on buffer size
---@param min_lines number? Minimum lines threshold (default 10)
---@return boolean
M.should_display = function(min_lines)
  min_lines = min_lines or 10
  return vim.fn.line("$") >= min_lines
end

return M
