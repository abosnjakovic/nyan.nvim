local M = {}

--- Get git change markers for a buffer
---@param bufnr number Buffer number
---@return { line: number, type: string, staged: boolean }[]
M.get = function(bufnr)
  local ok, gitsigns = pcall(require, "gitsigns")
  if not ok then
    return {}
  end

  local hunks_ok, hunks = pcall(gitsigns.get_hunks, bufnr)
  if not hunks_ok or not hunks then
    return {}
  end

  -- Build set of staged hunk start lines
  local staged_lines = {}
  local staged_ok, staged_hunks = pcall(gitsigns.get_hunks, bufnr, { staged = true })
  if staged_ok and staged_hunks then
    for _, h in ipairs(staged_hunks) do
      local line = h.added and h.added.start or h.removed and h.removed.start
      if line and line > 0 then
        staged_lines[line] = true
      end
    end
  end

  local result = {}
  for _, h in ipairs(hunks) do
    local line = h.added and h.added.start or 0
    if h.type == "delete" then
      line = h.removed and h.removed.start or 0
    end
    if line > 0 then
      table.insert(result, {
        line = line,
        type = h.type,
        staged = staged_lines[line] == true,
      })
    end
  end
  return result
end

return M
