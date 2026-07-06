--- Health check for nyan.nvim (:checkhealth nyan)
--- The whole support surface for a terminal-graphics plugin is "I installed it
--- and see nothing", so this reports exactly why graphics would or wouldn't show.

local kitty = require("nyan.kitty")
local config = require("nyan.config")

local M = {}

local health = vim.health

--- Report Neovim version (setup() hard-requires 0.10 for vim.uv / vim.base64).
local function check_nvim()
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim 0.10+ required", "nyan.setup() aborts on older versions")
  end
end

--- Report terminal graphics support, and crucially *why*.
local function check_terminal()
  local term = vim.env.TERM or ""
  local term_program = vim.env.TERM_PROGRAM or ""

  health.info("TERM=" .. (term == "" and "(unset)" or term))
  health.info("TERM_PROGRAM=" .. (term_program == "" and "(unset)" or term_program))

  if kitty.is_supported() then
    health.ok("Kitty graphics protocol detected -- cat renders as an image")
  else
    health.warn(
      "No Kitty graphics support detected -- falling back to ASCII/text",
      "Use a terminal that speaks the Kitty graphics protocol (Kitty, Ghostty, WezTerm)"
    )
  end

  if vim.env.TMUX then
    health.info("Inside tmux -- graphics use passthrough wrapping")
    health.warn(
      "tmux requires passthrough to forward graphics escapes",
      "Set: tmux set -g allow-passthrough on (and ensure the OUTER terminal supports Kitty graphics)"
    )
  end
end

--- Report that the sprite assets exist and are readable.
--- Located via the runtime path (cross-platform, cwd-independent) rather than
--- deriving a path from this file -- the plugin root is always on rtp.
local function check_assets()
  local expected = { "rainbow.png" }
  for i = 1, 6 do
    expected[#expected + 1] = "cat_frame_" .. i .. ".png"
  end

  local missing = {}
  for _, name in ipairs(expected) do
    if #vim.api.nvim_get_runtime_file("assets/" .. name, false) == 0 then
      missing[#missing + 1] = name
    end
  end

  if #missing == 0 then
    health.ok(("All %d sprite assets present"):format(#expected))
  elseif #missing < #expected then
    health.warn("Missing sprite assets: " .. table.concat(missing, ", "), "Cat may render partially")
  else
    health.error("No sprite assets found on runtimepath", "Reinstall the plugin")
  end
end

--- Summarise the active configuration.
local function check_config()
  local cfg = config.get()
  health.info("renderer = " .. tostring(cfg.renderer))
  health.info("animation = " .. (cfg.animation.enabled and ("on, fps=" .. cfg.animation.fps) or "off"))
  health.info("fallback = " .. tostring(cfg.fallback))
end

M.check = function()
  health.start("nyan.nvim")
  check_nvim()
  check_terminal()
  check_assets()
  check_config()
end

return M
