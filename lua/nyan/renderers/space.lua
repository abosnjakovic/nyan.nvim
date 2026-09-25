local config = require("nyan.config")
local position = require("nyan.position")
local diagnostics_provider = require("nyan.providers.diagnostics")
local git_provider = require("nyan.providers.git")
local search_provider = require("nyan.providers.search")

local M = {}

-- Characters
local SHIP = "▷"
local DIAG = "✕"
local GIT = "│"
local TRAIL = "·"
local SEARCH = "/"
local BRACKET_L = "["
local BRACKET_R = "]"

-- Priority values (lower = higher priority)
local PRIORITY = {
  SEARCH = 0,
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
  -- Normal's text colour stands out from Comment in most colourschemes. fg
  -- only (GUI and cterm): Normal's bg would fill the cell.
  local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.api.nvim_set_hl(0, "NyanViewport", { fg = normal_hl.fg, ctermfg = normal_hl.ctermfg, default = true })
  vim.api.nvim_set_hl(0, "NyanBracket", { link = "Comment", default = true })
  -- Search hits borrow the colourscheme's search colour as a *foreground*.
  -- Linking to Search would drag in its background too, turning every hit into
  -- a filled block that dominates the bar. Search.bg is the accent colour in
  -- practice; fg is the readable-text colour picked to sit on top of it.
  local search_hl = vim.api.nvim_get_hl(0, { name = "Search", link = false })
  vim.api.nvim_set_hl(0, "NyanSearch", {
    fg = search_hl.bg or search_hl.fg,
    ctermfg = search_hl.ctermbg or search_hl.ctermfg,
    bold = true,
    default = true,
  })
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
--- Reads the current buffer/cursor — call only from active-window statusline
--- content (see nyan.position).
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
  -- Same mapping as the markers, so the thumb's edges line up with them.
  local view_top = M.map_to_cell(vim.fn.line("w0"), total_lines, available_width)
  local view_bottom = M.map_to_cell(vim.fn.line("w$"), total_lines, available_width)

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

  -- Search hits
  if cfg.search then
    for _, s in ipairs(search_provider.get(bufnr)) do
      local cell = M.map_to_cell(s.line, total_lines, available_width)
      M.place_marker(markers, cell, {
        char = SEARCH,
        hl = "NyanSearch",
        priority = PRIORITY.SEARCH,
      })
    end
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
      -- Colour-only thumb: keeping the trail character holds the bar layout steady.
      local hl = (i >= view_top and i <= view_bottom) and "NyanViewport" or "NyanTrail"
      table.insert(parts, string.format("%%#%s#%s%%*", hl, TRAIL))
    end
  end

  table.insert(parts, string.format("%%#NyanBracket#%s", BRACKET_R))
  return table.concat(parts)
end

return M
