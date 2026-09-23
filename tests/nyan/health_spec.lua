---@diagnostic disable: duplicate-set-field, inject-field
--- Stubs vim.health.* to capture what the check reports, then drives it under
--- controlled env. Asserts the *reason* the plugin surfaces, not just that it
--- runs -- a green cat on an unsupported terminal is exactly the bug this guards.

local ENV_KEYS = { "TERM", "TERM_PROGRAM", "TMUX", "KITTY_WINDOW_ID", "GHOSTTY_RESOURCES_DIR" }
local HEALTH_FNS = { "start", "ok", "info", "warn", "error" }

describe("health", function()
  local health = require("nyan.health")
  local config = require("nyan.config")
  local calls
  local saved_env
  local saved_health
  local saved_options
  local saved_executable

  -- health.* fields are captured by reference in health.lua, so stub the
  -- fields in place rather than replacing the vim.health table.
  before_each(function()
    saved_options = config.options
    saved_executable = vim.fn.executable
    saved_env = {}
    for _, k in ipairs(ENV_KEYS) do
      saved_env[k] = vim.env[k]
      vim.env[k] = nil
    end

    calls = {}
    saved_health = {}
    for _, name in ipairs(HEALTH_FNS) do
      saved_health[name] = vim.health[name]
      vim.health[name] = function(msg, advice)
        table.insert(calls, { level = name, msg = msg, advice = advice })
      end
    end
  end)

  after_each(function()
    config.options = saved_options
    vim.fn.executable = saved_executable
    package.loaded.gitsigns = nil
    package.preload.gitsigns = nil
    for _, k in ipairs(ENV_KEYS) do
      vim.env[k] = saved_env[k]
    end
    for _, name in ipairs(HEALTH_FNS) do
      vim.health[name] = saved_health[name]
    end
  end)

  -- Did any captured call at `level` contain `substr` in its message?
  local function reported(level, substr)
    for _, c in ipairs(calls) do
      if c.level == level and type(c.msg) == "string" and c.msg:find(substr, 1, true) then
        return true
      end
    end
    return false
  end

  it("opens a nyan.nvim health section", function()
    health.check()
    assert.is_true(reported("start", "nyan.nvim"))
  end)

  it("warns until setup() has run, since get() renders nothing before it", function()
    pcall(vim.api.nvim_del_augroup_by_name, "NyanNvim")
    health.check()
    assert.is_true(reported("warn", "setup() has not run"))

    calls = {}
    require("nyan").setup()
    health.check()
    assert.is_true(reported("ok", "setup() has run"))
    assert.is_false(reported("warn", "setup() has not run"))
  end)

  it("errors on an unknown renderer, which setup() only half configures", function()
    config.setup({ renderer = "minimap" })
    health.check()
    assert.is_true(reported("error", 'Unknown renderer "minimap"'))
  end)

  -- Graphics only matter to the cat: a Kitty warning would be a false alarm
  -- for the default space renderer.
  it("skips the graphics checks under the space renderer", function()
    vim.env.TERM = "dumb"
    health.check()
    assert.is_true(reported("start", "space renderer"))
    assert.is_false(reported("warn", "falling back"))
    assert.is_false(reported("ok", "sprite assets"))
  end)

  describe("git markers (space renderer)", function()
    -- Make require("gitsigns") raise `msg`, regardless of what is on rtp.
    -- "module 'gitsigns' not found" is what require says when it is absent.
    local function gitsigns_errors(msg)
      package.loaded.gitsigns = nil
      package.preload.gitsigns = function()
        error(msg, 0)
      end
    end

    it("reports live updates when gitsigns is available", function()
      package.loaded.gitsigns = {}
      health.check()
      assert.is_true(reported("ok", "gitsigns found"))
      assert.is_false(reported("warn", "no git markers"))
    end)

    it("warns, rather than claiming it is missing, when gitsigns fails to load", function()
      -- Telling someone with a broken gitsigns to install it sends them the
      -- wrong way; the load error is what they need.
      gitsigns_errors("boom")
      health.check()
      assert.is_true(reported("warn", "gitsigns failed to load"))
      assert.is_false(reported("ok", "gitsigns not found"))
    end)

    it("reports the git diff fallback without gitsigns", function()
      gitsigns_errors("module 'gitsigns' not found")
      vim.fn.executable = function(bin)
        return bin == "git" and 1 or 0
      end
      health.check()
      assert.is_true(reported("ok", "git diff"))
      assert.is_false(reported("ok", "gitsigns found"))
      assert.is_false(reported("warn", "no git markers"))
    end)

    it("warns that there are no git markers without gitsigns or git", function()
      gitsigns_errors("module 'gitsigns' not found")
      vim.fn.executable = function()
        return 0
      end
      health.check()
      assert.is_true(reported("warn", "no git markers"))
      assert.is_false(reported("ok", "git diff"))
    end)

    it("is not checked under the nyan renderer", function()
      config.setup({ renderer = "nyan" })
      package.loaded.gitsigns = {}
      health.check()
      assert.is_false(reported("ok", "gitsigns found"))
    end)
  end)

  it("reports ok on a Kitty-capable terminal", function()
    config.setup({ renderer = "nyan" })
    vim.env.TERM_PROGRAM = "ghostty"
    health.check()
    assert.is_true(reported("ok", "Kitty graphics"))
    assert.is_false(reported("warn", "falling back"))
  end)

  it("warns and does not claim graphics on an unsupported terminal", function()
    config.setup({ renderer = "nyan" })
    vim.env.TERM = "dumb"
    health.check()
    assert.is_true(reported("warn", "falling back"))
    assert.is_false(reported("ok", "Kitty graphics"))
  end)

  it("warns about tmux passthrough when inside tmux", function()
    config.setup({ renderer = "nyan" })
    vim.env.TERM_PROGRAM = "ghostty"
    vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
    health.check()
    assert.is_true(reported("warn", "passthrough"))
  end)

  it("confirms the bundled sprite assets are present", function()
    config.setup({ renderer = "nyan" })
    health.check()
    assert.is_true(reported("ok", "sprite assets"))
  end)
end)
