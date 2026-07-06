---@diagnostic disable: duplicate-set-field, inject-field
--- Stubs vim.health.* to capture what the check reports, then drives it under
--- controlled env. Asserts the *reason* the plugin surfaces, not just that it
--- runs -- a green cat on an unsupported terminal is exactly the bug this guards.

local ENV_KEYS = { "TERM", "TERM_PROGRAM", "TMUX", "KITTY_WINDOW_ID", "GHOSTTY_RESOURCES_DIR" }
local HEALTH_FNS = { "start", "ok", "info", "warn", "error" }

describe("health", function()
  local health = require("nyan.health")
  local calls
  local saved_env
  local saved_health

  -- health.* fields are captured by reference in health.lua, so stub the
  -- fields in place rather than replacing the vim.health table.
  before_each(function()
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

  it("reports ok on a Kitty-capable terminal", function()
    vim.env.TERM_PROGRAM = "ghostty"
    health.check()
    assert.is_true(reported("ok", "Kitty graphics"))
    assert.is_false(reported("warn", "falling back"))
  end)

  it("warns and does not claim graphics on an unsupported terminal", function()
    vim.env.TERM = "dumb"
    health.check()
    assert.is_true(reported("warn", "falling back"))
    assert.is_false(reported("ok", "Kitty graphics"))
  end)

  it("warns about tmux passthrough when inside tmux", function()
    vim.env.TERM_PROGRAM = "ghostty"
    vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
    health.check()
    assert.is_true(reported("warn", "passthrough"))
  end)

  it("confirms the bundled sprite assets are present", function()
    health.check()
    assert.is_true(reported("ok", "sprite assets"))
  end)
end)
