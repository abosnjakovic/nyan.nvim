--- nyan.nvim - Animated Nyan Cat statusline component
--- Uses Kitty Graphics Protocol for image rendering with ASCII fallback

local config = require("nyan.config")
local position = require("nyan.position")
local animation = require("nyan.animation")
local render = require("nyan.render")
local kitty = require("nyan.kitty")

local M = {}

-- State
local initialized = false

--- Get plugin directory path
---@return string
local function get_plugin_dir()
  local info = debug.getinfo(1, "S")
  local script_path = info.source:sub(2) -- Remove leading @
  return vim.fn.fnamemodify(script_path, ":h:h:h") -- Go up 3 levels: init.lua -> nyan -> lua -> plugin root
end

--- Setup highlight groups for fallback mode
local function setup_fallback_highlights()
  vim.api.nvim_set_hl(0, "NyanCat", { fg = "#ffaaff", bold = true, default = true })
  vim.api.nvim_set_hl(0, "NyanRainbow1", { fg = "#ff6666", default = true })
  vim.api.nvim_set_hl(0, "NyanRainbow2", { fg = "#ffaa66", default = true })
  vim.api.nvim_set_hl(0, "NyanRainbow3", { fg = "#ffff66", default = true })
  vim.api.nvim_set_hl(0, "NyanRainbow4", { fg = "#66ff66", default = true })
  vim.api.nvim_set_hl(0, "NyanRainbow5", { fg = "#6666ff", default = true })
  vim.api.nvim_set_hl(0, "NyanRainbow6", { fg = "#ff66ff", default = true })
end

--- Setup autocommands
local function setup_autocommands()
  local augroup = vim.api.nvim_create_augroup("NyanNvim", { clear = true })

  -- Maintain highlights after colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = setup_fallback_highlights,
  })

  -- Pause animation on focus lost (save CPU)
  vim.api.nvim_create_autocmd("FocusLost", {
    group = augroup,
    callback = function()
      animation.pause()
    end,
  })

  -- Resume animation on focus gained (respects user's explicit stop)
  vim.api.nvim_create_autocmd("FocusGained", {
    group = augroup,
    callback = function()
      animation.resume()
    end,
  })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      animation.cleanup()
      kitty.delete_all_images()
    end,
  })
end

--- Setup user commands
local function setup_commands()
  vim.api.nvim_create_user_command("NyanToggle", function()
    animation.toggle()
  end, { desc = "Toggle Nyan Cat animation" })

  vim.api.nvim_create_user_command("NyanStart", function()
    animation.start()
  end, { desc = "Start Nyan Cat animation" })

  vim.api.nvim_create_user_command("NyanStop", function()
    animation.stop()
  end, { desc = "Stop Nyan Cat animation" })
end

--- Load and transmit sprite images
---@return boolean success
local function load_sprites()
  config.log("=== Loading sprites ===")
  config.log("Checking Kitty graphics support...")

  if not kitty.is_supported() then
    config.log("Kitty graphics not supported, using fallback")
    return false
  end

  config.log("Kitty graphics supported!")

  local plugin_dir = get_plugin_dir()
  local assets_dir = plugin_dir .. "/assets"
  config.log("Assets directory:", assets_dir)

  -- Check if assets exist
  if vim.fn.isdirectory(assets_dir) == 0 then
    vim.notify("nyan.nvim: Assets directory not found, using ASCII fallback", vim.log.levels.WARN)
    config.log("Assets directory not found!")
    return false
  end

  -- Load rainbow FIRST to test if ID matters
  config.log("Loading rainbow...")
  local rainbow_id
  local rainbow_path = assets_dir .. "/rainbow.png"
  if vim.fn.filereadable(rainbow_path) == 1 then
    config.log("  Found rainbow:", rainbow_path)
    rainbow_id = kitty.transmit_image(rainbow_path)
    if rainbow_id > 0 then
      kitty.create_virtual_placement(rainbow_id, 1, 1) -- 1 column, 1 row
    end
  else
    config.log("  Rainbow not found:", rainbow_path)
  end

  -- Look for cat frames (6 frames from original nyan-mode)
  local cat_ids = {}
  config.log("Loading cat frames...")
  for i = 1, 6 do
    local path = assets_dir .. "/cat_frame_" .. i .. ".png"
    if vim.fn.filereadable(path) == 1 then
      config.log("  Found frame", i, ":", path)
      local id = kitty.transmit_image(path)
      if id > 0 then
        table.insert(cat_ids, id)
        kitty.create_virtual_placement(id, 1, 1)
      end
    else
      config.log("  Frame", i, "not found:", path)
    end
  end

  config.log("Sprite loading complete:")
  config.log("  Cat frames loaded:", #cat_ids)
  config.log("  Cat IDs:", cat_ids)
  config.log("  Rainbow ID:", rainbow_id or "none")

  if #cat_ids > 0 then
    if #cat_ids < 6 then
      vim.notify(string.format("nyan.nvim: Only %d of 6 cat frames loaded", #cat_ids), vim.log.levels.WARN)
    end
    render.init(cat_ids, rainbow_id)
    config.log("Render module initialised with graphics mode")
    return true
  end

  vim.notify("nyan.nvim: No cat frames found, using ASCII fallback", vim.log.levels.WARN)
  config.log("No cat frames found, falling back to ASCII")
  return false
end

--- Setup the plugin
---@param opts NyanConfig?
M.setup = function(opts)
  -- Check Neovim version (require 0.10+ for vim.uv)
  if vim.fn.has("nvim-0.10") == 0 then
    vim.notify("nyan.nvim requires Neovim 0.10 or later", vim.log.levels.ERROR)
    return
  end

  -- Configure
  config.setup(opts)

  local cfg = config.get()
  if cfg.debug then
    vim.notify("[nyan.nvim] Debug logging enabled", vim.log.levels.INFO)
  end

  config.log("=== nyan.nvim setup started ===")
  config.log("Configuration:", cfg)

  -- Setup highlights
  setup_fallback_highlights()
  config.log("Fallback highlights created")

  -- Setup autocommands
  setup_autocommands()
  config.log("Autocommands created")

  -- Setup commands
  setup_commands()
  config.log("User commands created")

  -- Try to load sprites (will use fallback if fails)
  local sprites_loaded = load_sprites()
  config.log("Sprites loaded:", sprites_loaded)

  -- Start animation if enabled
  if cfg.animation.enabled then
    config.log("Starting animation (fps=" .. cfg.animation.fps .. ")")
    animation.start()
  else
    config.log("Animation disabled in config")
  end

  initialized = true
  config.log("=== nyan.nvim setup complete ===")
  config.log("Graphics mode:", render.is_graphics_enabled())
end

--- Get statusline component string
--- This is the main function to use in statusline configuration
---@return string Statusline-compatible string
M.get = function()
  if not initialized then
    return ""
  end
  return render.render()
end

--- Check if component should be displayed
---@return boolean
M.should_display = function()
  local cfg = config.get()
  return position.should_display(cfg.min_buffer_lines)
end

--- Get current scroll percentage (0-100)
---@return number
M.get_percentage = function()
  return math.floor(position.get_scroll_position() * 100)
end

--- Check if animation is running
M.is_animating = animation.is_running

--- Toggle animation on/off
M.toggle = animation.toggle

--- Start animation
M.start = animation.start

--- Stop animation
M.stop = animation.stop

--- Check if using graphics mode
M.is_graphics_mode = render.is_graphics_enabled

return M
