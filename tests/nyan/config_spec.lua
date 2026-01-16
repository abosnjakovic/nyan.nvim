local config = require("nyan.config")

describe("config", function()
  before_each(function()
    -- Reset config to defaults before each test
    config.setup({})
  end)

  describe("defaults", function()
    it("has correct default width", function()
      assert.equals(20, config.get().width)
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
  end)

  describe("log", function()
    it("does nothing when debug is false", function()
      config.setup({ debug = false })
      -- Should not throw
      config.log("test message")
    end)
  end)
end)
