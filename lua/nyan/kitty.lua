--- Kitty Graphics Protocol implementation
--- See: https://sw.kovidgoyal.net/kitty/graphics-protocol/

local M = {}

local ESC = "\027"
local APC = ESC .. "_G"
local ST = ESC .. "\\"

-- Track assigned image IDs
local next_image_id = 1

-- Track if we're running inside tmux (set during is_supported check)
local in_tmux = false

--- Wrap escape sequence for tmux passthrough
--- Tmux requires special wrapping: \ePtmux;\e<escape>\e\\
--- Also need to double any ESC characters inside the sequence
---@param seq string The escape sequence to wrap
---@return string The wrapped sequence (or original if not in tmux)
local function wrap_for_tmux(seq)
  if not in_tmux then
    return seq
  end
  -- Double all ESC characters and wrap in tmux passthrough
  local doubled = seq:gsub(ESC, ESC .. ESC)
  return ESC .. "Ptmux;" .. doubled .. ESC .. "\\"
end

--- Write escape sequence (handles tmux passthrough automatically)
---@param seq string The escape sequence to write
local function write_escape(seq)
  io.write(wrap_for_tmux(seq))
  io.flush()
end

--- Check if terminal supports Kitty graphics protocol
---@return boolean
M.is_supported = function()
  local term = vim.env.TERM or ""
  local term_program = vim.env.TERM_PROGRAM or ""

  -- Detect tmux first
  in_tmux = vim.env.TMUX ~= nil

  -- Kitty terminal (direct)
  if term:match("xterm%-kitty") then
    return true
  end

  -- Ghostty supports Kitty graphics protocol (direct)
  if term_program:match("ghostty") or term:match("ghostty") then
    return true
  end

  -- Check for KITTY_WINDOW_ID (set by Kitty)
  if vim.env.KITTY_WINDOW_ID then
    return true
  end

  -- Check for GHOSTTY_RESOURCES_DIR (set by Ghostty)
  if vim.env.GHOSTTY_RESOURCES_DIR then
    return true
  end

  -- Inside tmux - assume outer terminal supports graphics
  -- Modern terminals like Ghostty, Kitty, WezTerm all support it
  -- User can disable via config if needed
  if in_tmux then
    return true
  end

  return false
end

--- Encode data as base64
---@param data string Binary data to encode
---@return string Base64 encoded string
M.base64_encode = function(data)
  -- Use vim's built-in base64 if available (Neovim 0.10+)
  if vim.base64 then
    return vim.base64.encode(data)
  end

  -- Fallback: shell out to base64 command
  local handle = io.popen("echo -n '" .. data:gsub("'", "'\\''") .. "' | base64 | tr -d '\\n'")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result
  end

  return ""
end

--- Read file contents
---@param path string Path to file
---@return string? contents File contents or nil on error
M.read_file = function(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

--- Transmit an image to the terminal
--- Uses quiet mode (q=2) so terminal doesn't respond
---@param path string Path to PNG image
---@param image_id number? Optional specific image ID to use
---@return number image_id The assigned image ID
M.transmit_image = function(path, image_id)
  local content = M.read_file(path)
  if not content then
    vim.notify("nyan.nvim: Failed to read image: " .. path, vim.log.levels.ERROR)
    return 0
  end

  local id = image_id or next_image_id
  if not image_id then
    next_image_id = next_image_id + 1
  end

  local encoded = M.base64_encode(content)
  local chunk_size = 4096

  -- If data fits in one chunk
  -- Use a=t (lowercase) to transmit without displaying - we use Unicode placeholders for display
  if #encoded <= chunk_size then
    local cmd = string.format("%sa=t,f=100,i=%d,q=2;%s%s", APC, id, encoded, ST)
    write_escape(cmd)
  else
    -- Chunked transmission
    local offset = 1
    local first = true
    while offset <= #encoded do
      local chunk = encoded:sub(offset, offset + chunk_size - 1)
      local more = (offset + chunk_size <= #encoded) and 1 or 0

      local cmd
      if first then
        cmd = string.format("%sa=t,f=100,i=%d,m=%d,q=2;%s%s", APC, id, more, chunk, ST)
        first = false
      else
        cmd = string.format("%sm=%d;%s%s", APC, more, chunk, ST)
      end

      write_escape(cmd)
      offset = offset + chunk_size
    end
  end

  return id
end

--- Create a virtual placement for Unicode placeholders
---@param image_id number The image ID
---@param cols number Number of columns
---@param rows number Number of rows
M.create_virtual_placement = function(image_id, cols, rows)
  local cmd = string.format("%sa=p,U=1,i=%d,c=%d,r=%d,q=2%s", APC, image_id, cols, rows, ST)
  write_escape(cmd)
end

--- Delete an image from terminal memory
---@param image_id number The image ID to delete
M.delete_image = function(image_id)
  local cmd = string.format("%sa=d,d=I,i=%d,q=2%s", APC, image_id, ST)
  write_escape(cmd)
end

--- Delete all images transmitted by this plugin
M.delete_all_images = function()
  -- Delete by ID range (assumes we started at 1)
  for id = 1, next_image_id - 1 do
    M.delete_image(id)
  end
  next_image_id = 1
end

--- Convert image ID to RGB hex colour for highlight group
--- The image ID is encoded in the RGB value
---@param image_id number Image ID (1-16777215)
---@return string hex Hex colour string like "#000001"
M.id_to_colour = function(image_id)
  return string.format("#%06x", image_id)
end

return M
