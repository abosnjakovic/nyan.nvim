local config = require("nyan.config")
local position = require("nyan.position")
local diagnostics_provider = require("nyan.providers.diagnostics")
local git_provider = require("nyan.providers.git")

local M = {}

-- Characters
local SHIP = "▷"
local DIAG = "✕"
local GIT = "│"
local TRAIL = "·"
local BRACKET_L = "["
local BRACKET_R = "]"

-- Priority values (lower = higher priority)
local PRIORITY = {
  [vim.diagnostic.severity.ERROR] = 1,
  [vim.diagnostic.severity.WARN] = 2,
  GIT = 3,
  [vim.diagnostic.severity.INFO] = 4,
  [vim.diagnostic.severity.HINT] = 5,
}

-- Severity to highlight group
local DIAG_HL = {
  [vim.diagnostic.severity.ERROR] = "NyanDiagError",
  [vim.diagnostic.severity.WARN] = "NyanDiagWarn",
  [vim.diagnostic.severity.INFO] = "NyanDiagInfo",
  [vim.diagnostic.severity.HINT] = "NyanDiagHint",
}

-- Git type to highlight group
local GIT_HL = {
  add = "NyanGitAdded",
  change = "NyanGitUnstaged",
  delete = "NyanGitRemoved",
}

--- Map a 1-indexed line number to a 0-indexed cell position
---@param line number 1-indexed line number
---@param total_lines number Total lines in buffer
---@param available_width number Number of cells available for markers
---@return number cell 0-indexed cell position
M.map_to_cell = function(line, total_lines, available_width)
  if total_lines <= 1 then
    return 0
  end
  local frac = (line - 1) / (total_lines - 1)
  return math.floor(frac * (available_width - 1))
end

--- Place a marker, respecting collision priority
---@param markers table Cell index -> marker table
---@param cell number 0-indexed cell position
---@param marker { char: string, hl: string, priority: number }
M.place_marker = function(markers, cell, marker)
  if not markers[cell] or marker.priority < markers[cell].priority then
    markers[cell] = marker
  end
end

--- Create highlight groups for the space theme
M.setup_highlights = function()
  vim.api.nvim_set_hl(0, "NyanShip", { fg = "#ffffff", bold = true, default = true })
  vim.api.nvim_set_hl(0, "NyanTrail", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "NyanBracket", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "NyanDiagError", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "NyanDiagWarn", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "NyanDiagInfo", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "NyanDiagHint", { link = "DiagnosticHint", default = true })
  vim.api.nvim_set_hl(0, "NyanGitStaged", { link = "GitSignsAdd", default = true })
  vim.api.nvim_set_hl(0, "NyanGitUnstaged", { link = "GitSignsChange", default = true })
  vim.api.nvim_set_hl(0, "NyanGitAdded", { link = "GitSignsAdd", default = true })
  vim.api.nvim_set_hl(0, "NyanGitRemoved", { link = "GitSignsDelete", default = true })
end

--- Build the statusline string
---@return string Statusline-compatible string
M.render = function()
  local cfg = config.get()

  if not position.should_display(cfg.min_buffer_lines) then
    return ""
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local total_lines = vim.fn.line("$")
  local available_width = cfg.width - 2 -- minus brackets
  local scroll_frac = position.get_scroll_position()
  local ship_cell = math.floor(scroll_frac * (available_width - 1))

  -- Collect markers
  local markers = {}

  -- Diagnostics
  local diags = diagnostics_provider.get(bufnr)
  for _, d in ipairs(diags) do
    local cell = M.map_to_cell(d.line, total_lines, available_width)
    local priority = PRIORITY[d.severity] or 5
    M.place_marker(markers, cell, {
      char = DIAG,
      hl = DIAG_HL[d.severity] or "NyanDiagHint",
      priority = priority,
    })
  end

  -- Git changes
  local git_markers = git_provider.get(bufnr)
  for _, g in ipairs(git_markers) do
    local cell = M.map_to_cell(g.line, total_lines, available_width)
    local hl = GIT_HL[g.type] or "NyanGitUnstaged"
    if g.staged then
      hl = "NyanGitStaged"
    end
    M.place_marker(markers, cell, {
      char = GIT,
      hl = hl,
      priority = PRIORITY.GIT,
    })
  end

  -- Build output
  local parts = {}
  table.insert(parts, string.format("%%#NyanBracket#%s", BRACKET_L))

  for i = 0, available_width - 1 do
    if i == ship_cell then
      table.insert(parts, string.format("%%#NyanShip#%s%%*", SHIP))
    elseif markers[i] then
      table.insert(parts, string.format("%%#%s#%s%%*", markers[i].hl, markers[i].char))
    else
      table.insert(parts, string.format("%%#NyanTrail#%s%%*", TRAIL))
    end
  end

  table.insert(parts, string.format("%%#NyanBracket#%s", BRACKET_R))
  return table.concat(parts)
end

return M
