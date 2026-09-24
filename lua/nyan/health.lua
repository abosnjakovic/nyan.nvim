--- Health check for nyan.nvim (:checkhealth nyan)
--- The whole support surface for a statusline plugin is "I installed it and see
--- nothing", so this reports exactly why the active renderer would or wouldn't show.

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

--- Report whether setup() has run: until it does, get() returns "" and the
--- statusline is silently empty. setup() creates the NyanNvim augroup once past
--- its version check, so the group stands in for init.lua's private
--- `initialized` flag without exporting it.
local function check_setup()
  if vim.fn.exists("#NyanNvim") == 1 then
    health.ok("setup() has run")
  else
    health.warn("setup() has not run -- the statusline component renders nothing", 'Call require("nyan").setup()')
  end
end

--- Report where git markers come from: gitsigns if it loads (buffers it has
--- not attached to still fall back), else `git diff`. gitsigns holds hunks in
--- memory, so markers follow every edit; the `git diff` fallback only
--- refreshes on write, BufEnter and FocusGained.
local function check_git()
  local ok, err = pcall(require, "gitsigns")
  if ok then
    health.ok("gitsigns found -- git markers update as you edit")
  elseif not tostring(err):find("module 'gitsigns' not found", 1, true) then
    -- Installed but broken: "not found" would tell the user to install it
    health.warn("gitsigns failed to load -- git markers fall back to `git diff`", tostring(err))
  elseif vim.fn.executable("git") == 1 then
    health.ok(
      "gitsigns not found -- git markers use `git diff`, refreshed on write, buffer switch and focus"
        .. " (install gitsigns for live updates)"
    )
  else
    health.warn("Neither gitsigns nor git found -- no git markers", "Install git, or gitsigns.nvim")
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
  if cfg.renderer ~= "space" and cfg.renderer ~= "nyan" then
    -- Works, as the space renderer, but a typo is worth pointing out
    health.warn(
      ("Unknown renderer %q -- using space"):format(tostring(cfg.renderer)),
      'Set renderer = "space" or "nyan"'
    )
  end
  health.info("animation = " .. (cfg.animation.enabled and ("on, fps=" .. cfg.animation.fps) or "off"))
  health.info("fallback = " .. tostring(cfg.fallback))
end

M.check = function()
  health.start("nyan.nvim")
  check_nvim()
  check_setup()
  check_config()

  -- Only the active renderer's dependencies are checked: a Kitty warning is a
  -- false alarm for a space user, and git markers mean nothing to the cat.
  -- Same test as render.lua and init.lua: any non-"nyan" value is space.
  if config.get().renderer == "nyan" then
    health.start("nyan.nvim: nyan renderer")
    check_terminal()
    check_assets()
  else
    health.start("nyan.nvim: space renderer")
    check_git()
  end
end

return M
