--- Render module for building statusline strings
--- Handles both image-based and ASCII fallback rendering

local config = require("nyan.config")
local position = require("nyan.position")
local kitty = require("nyan.kitty")

-- Track render calls for debug logging (don't spam every frame)
local render_log_count = 0

local M = {}

-- Unicode placeholder character for Kitty graphics
local PLACEHOLDER = "\u{10EEEE}"

-- Diacritics for multi-cell images (Kitty graphics protocol)
-- Format: PLACEHOLDER + row_diacritic + column_diacritic
-- Encoding: 0=U+0305, 1=U+0306, 2=U+0307, ... (sequential from U+0305)
local ROW = {
  [0] = "\u{0305}",
}
local COL = {
  [0] = "\u{0305}",
  [1] = "\u{0306}",
  [2] = "\u{0307}",
}

-- ASCII cat frames for fallback mode
local ASCII_CAT = {
  "^._.^=",
  "^._.^~",
}

-- ASCII rainbow characters
local ASCII_RAINBOW = { "=", "-", "~" }

-- State
local current_frame = 1
local image_ids = {}
local graphics_enabled = false

--- Initialise renderer with image IDs
---@param cat_ids number[] Array of cat frame image IDs
---@param rainbow_id number Rainbow segment image ID
M.init = function(cat_ids, rainbow_id)
  config.log("=== Render init ===")
  image_ids.cat = cat_ids or {}
  image_ids.rainbow = rainbow_id
  graphics_enabled = kitty.is_supported() and #image_ids.cat > 0

  config.log("  Cat frame IDs:", image_ids.cat)
  config.log("  Rainbow ID:", image_ids.rainbow)
  config.log("  Graphics enabled:", graphics_enabled)

  -- Create highlight groups for image IDs
  if graphics_enabled then
    config.log("Creating highlight groups:")
    for i, id in ipairs(image_ids.cat) do
      local colour = kitty.id_to_colour(id)
      config.log("  NyanCat" .. i .. " -> fg=" .. colour .. " (ID " .. id .. ")")
      vim.api.nvim_set_hl(0, "NyanCat" .. i, { fg = colour })
    end
    if image_ids.rainbow then
      local colour = kitty.id_to_colour(image_ids.rainbow)
      config.log("  NyanRainbow -> fg=" .. colour .. " (ID " .. image_ids.rainbow .. ")")
      vim.api.nvim_set_hl(0, "NyanRainbow", { fg = colour })
    end
  end
  config.log("=== Render init complete ===")
end

--- Advance to next frame
---@return number New frame index
M.next_frame = function()
  local num_frames = graphics_enabled and #image_ids.cat or #ASCII_CAT
  current_frame = (current_frame % num_frames) + 1
  return current_frame
end

--- Build statusline string with Unicode placeholders (graphics mode)
---@param rainbow_length number Number of rainbow cells to show
---@return string Statusline-compatible string
local function render_graphics(rainbow_length)
  local cfg = config.get()
  local cat_width = 1 -- Cat takes 1 cell
  local padding = cfg.width - rainbow_length - cat_width

  local result = {}

  -- Rainbow trail
  if rainbow_length > 0 and image_ids.rainbow then
    -- Each rainbow cell needs row/column diacritics for proper rendering
    local rainbow_cell = PLACEHOLDER .. ROW[0] .. COL[0]
    local rainbow_str = string.rep(rainbow_cell, rainbow_length)
    table.insert(result, string.format("%%#NyanRainbow#%s%%*", rainbow_str))
  end

  -- Cat (1 cell)
  local cat_hl = "NyanCat" .. current_frame
  local cat_str = PLACEHOLDER .. ROW[0] .. COL[0]
  table.insert(result, string.format("%%#%s#%s%%*", cat_hl, cat_str))

  -- Padding
  if padding > 0 then
    table.insert(result, string.rep(" ", padding))
  end

  return table.concat(result)
end

--- Build statusline string with ASCII art (fallback mode)
---@param rainbow_length number Number of rainbow cells to show
---@return string Statusline-compatible string
local function render_ascii(rainbow_length)
  local cfg = config.get()
  local cat = ASCII_CAT[current_frame] or ASCII_CAT[1]
  local cat_width = vim.fn.strdisplaywidth(cat)
  local padding = cfg.width - rainbow_length - cat_width

  local result = {}

  -- Rainbow trail
  if rainbow_length > 0 then
    local rainbow_char = ASCII_RAINBOW[(current_frame % #ASCII_RAINBOW) + 1]
    table.insert(result, string.rep(rainbow_char, rainbow_length))
  end

  -- Cat
  table.insert(result, cat)

  -- Padding
  if padding > 0 then
    table.insert(result, string.rep(" ", padding))
  end

  return table.concat(result)
end

--- Main render function - returns statusline string
---@return string Statusline-compatible string
M.render = function()
  local cfg = config.get()

  -- Check minimum lines
  if not position.should_display(cfg.min_buffer_lines) then
    return ""
  end

  -- Calculate position
  local pos = position.get_scroll_position()
  local cat_width = graphics_enabled and 1 or vim.fn.strdisplaywidth(ASCII_CAT[1])
  local available_width = cfg.width - cat_width
  local rainbow_length = math.floor(pos * available_width)

  -- Log first render call only (to avoid spam)
  if render_log_count < 1 then
    render_log_count = render_log_count + 1
    config.log("=== First render call ===")
    config.log("  Graphics enabled:", graphics_enabled)
    config.log("  Scroll position:", pos)
    config.log("  Cat width:", cat_width)
    config.log("  Available width:", available_width)
    config.log("  Rainbow length:", rainbow_length)
    config.log("  Current frame:", current_frame)
    if graphics_enabled then
      config.log("  Cat highlight: NyanCat" .. current_frame)
      config.log("  Cat IDs:", image_ids.cat)
      config.log("  Rainbow ID:", image_ids.rainbow)
    end
  end

  -- Render based on mode
  if graphics_enabled then
    return render_graphics(rainbow_length)
  elseif cfg.fallback == "ascii" then
    return render_ascii(rainbow_length)
  end

  return ""
end

--- Check if graphics mode is enabled
---@return boolean
M.is_graphics_enabled = function()
  return graphics_enabled
end

return M
