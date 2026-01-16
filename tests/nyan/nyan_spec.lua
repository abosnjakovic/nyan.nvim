local nyan = require("nyan")

describe("nyan", function()
  before_each(function()
    -- Note: setup creates autocommands and commands
    -- We can't easily reset state between tests
  end)

  describe("setup", function()
    it("does not error with default config", function()
      assert.has_no.errors(function()
        nyan.setup()
      end)
    end)

    it("does not error with custom config", function()
      assert.has_no.errors(function()
        nyan.setup({
          width = 30,
          animation = { enabled = false },
        })
      end)
    end)
  end)

  describe("get", function()
    it("returns a string", function()
      nyan.setup()
      local result = nyan.get()
      assert.is_string(result)
    end)
  end)

  describe("should_display", function()
    it("returns a boolean", function()
      nyan.setup()
      local result = nyan.should_display()
      assert.is_boolean(result)
    end)
  end)

  describe("get_percentage", function()
    it("returns a number between 0 and 100", function()
      nyan.setup()

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      local lines = {}
      for i = 1, 100 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local pct = nyan.get_percentage()
      assert.is_number(pct)
      assert.is_true(pct >= 0 and pct <= 100)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("animation controls", function()
    it("toggle changes animation state", function()
      nyan.setup({ animation = { enabled = true } })
      local initial = nyan.is_animating()
      nyan.toggle()
      assert.is_not.equals(initial, nyan.is_animating())
    end)

    it("start and stop work", function()
      nyan.setup({ animation = { enabled = true } })
      nyan.start()
      assert.is_true(nyan.is_animating())
      nyan.stop()
      assert.is_false(nyan.is_animating())
    end)
  end)

  describe("is_graphics_mode", function()
    it("returns a boolean", function()
      nyan.setup()
      local result = nyan.is_graphics_mode()
      assert.is_boolean(result)
    end)
  end)
end)
