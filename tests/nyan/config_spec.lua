local config = require("nyan.config")

describe("config", function()
  before_each(function()
    -- Reset config to defaults before each test
    config.setup({})
  end)

  describe("defaults", function()
    it("has correct default width", function()
      assert.equals(45, config.get().width)
    end)

    it("has animation enabled by default", function()
      assert.is_true(config.get().animation.enabled)
    end)

    it("has correct default fps", function()
      assert.equals(6, config.get().animation.fps)
    end)

    it("has correct default min_buffer_lines", function()
      assert.equals(10, config.get().min_buffer_lines)
    end)

    it("has ascii fallback by default", function()
      assert.equals("ascii", config.get().fallback)
    end)

    it("has debug disabled by default", function()
      assert.is_false(config.get().debug)
    end)

    it("has classic theme by default", function()
      assert.equals("classic", config.get().theme)
    end)

    it("has transparent disabled by default", function()
      assert.is_false(config.get().transparent)
    end)

    it("has space renderer by default", function()
      assert.equals("space", config.get().renderer)
    end)

    it("has search markers enabled by default", function()
      assert.is_true(config.get().search)
    end)
  end)

  describe("setup", function()
    it("merges user config with defaults", function()
      config.setup({ width = 30 })
      assert.equals(30, config.get().width)
      -- Other defaults should remain
      assert.equals(6, config.get().animation.fps)
    end)

    it("merges nested config", function()
      config.setup({ animation = { fps = 10 } })
      assert.equals(10, config.get().animation.fps)
      -- Other animation defaults should remain
      assert.is_true(config.get().animation.enabled)
    end)

    it("returns the merged config", function()
      local result = config.setup({ width = 25 })
      assert.equals(25, result.width)
    end)

    it("can enable debug mode", function()
      config.setup({ debug = true })
      assert.is_true(config.get().debug)
    end)

    it("can set dark theme", function()
      config.setup({ theme = "dark" })
      assert.equals("dark", config.get().theme)
    end)

    it("can enable transparency", function()
      config.setup({ transparent = true })
      assert.is_true(config.get().transparent)
    end)
  end)

  describe("log", function()
    local notifications
    local orig_notify

    before_each(function()
      notifications = {}
      orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
    end)

    after_each(function()
      vim.notify = orig_notify
    end)

    it("does nothing when debug is false", function()
      config.setup({ debug = false })
      config.log("test message")
      assert.equals(0, #notifications)
    end)

    it("notifies with a prefix when debug is true", function()
      config.setup({ debug = true })
      config.log("hello")

      assert.equals(1, #notifications)
      assert.equals("[nyan.nvim] hello", notifications[1].msg)
      assert.equals(vim.log.levels.DEBUG, notifications[1].level)
    end)

    it("appends inspected values when extra arguments are given", function()
      config.setup({ debug = true })
      config.log("count:", 42)

      assert.equals(1, #notifications)
      assert.equals("[nyan.nvim] count: 42", notifications[1].msg)
    end)

    it("inspects table arguments", function()
      config.setup({ debug = true })
      config.log("cfg:", { a = 1 })

      assert.is_truthy(notifications[1].msg:find("a = 1", 1, true))
    end)
  end)
end)
