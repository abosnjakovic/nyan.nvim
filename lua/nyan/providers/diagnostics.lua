local M = {}

--- Get LSP diagnostics for a buffer
---@param bufnr number Buffer number
---@return { line: number, severity: number }[]
M.get = function(bufnr)
  local ok, diags = pcall(vim.diagnostic.get, bufnr)
  if not ok or not diags then
    return {}
  end

  local result = {}
  for _, d in ipairs(diags) do
    table.insert(result, {
      line = d.lnum + 1, -- convert 0-indexed to 1-indexed
      severity = d.severity,
    })
  end
  return result
end

return M
