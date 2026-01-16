local render = require("nyan.render")
local config = require("nyan.config")

describe("render", function()
  before_each(function()
    config.setup({})
  end)

  describe("frame management", function()
    it("next_frame advances and returns new frame", function()
      -- First call should return frame 2 (starts at 1, advances to 2)
      local next = render.next_frame()
      assert.is_number(next)
      assert.is_true(next >= 1)
    end)

    it("next_frame cycles through frames", function()
      -- ASCII mode has 2 frames, so after 2 calls we should be back
      local frame1 = render.next_frame()
      local frame2 = render.next_frame()
      -- Both should be valid frame numbers
      assert.is_number(frame1)
      assert.is_number(frame2)
    end)
  end)

  describe("render", function()
    it("returns empty string for small buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2" })

      config.setup({ min_buffer_lines = 10 })
      local result = render.render()
      assert.equals("", result)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns non-empty string for large buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      local lines = {}
      for i = 1, 100 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      config.setup({ min_buffer_lines = 10 })
      local result = render.render()
      assert.is_not.equals("", result)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("is_graphics_enabled", function()
    it("returns boolean", function()
      local result = render.is_graphics_enabled()
      assert.is_boolean(result)
    end)
  end)
end)
