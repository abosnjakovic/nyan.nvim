local position = require("nyan.position")

describe("position", function()
  describe("get_scroll_position", function()
    it("returns 0 at top of buffer", function()
      -- Create a buffer with 100 lines
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      local lines = {}
      for i = 1, 100 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      -- Go to first line
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local pos = position.get_scroll_position()
      assert.equals(0, pos)

      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns 1 at bottom of buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      local lines = {}
      for i = 1, 100 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      -- Go to last line
      vim.api.nvim_win_set_cursor(0, { 100, 0 })

      local pos = position.get_scroll_position()
      assert.equals(1, pos)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns approximately 0.5 at middle of buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      local lines = {}
      for i = 1, 101 do -- 101 lines so middle is exactly line 51
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      -- Go to middle line
      vim.api.nvim_win_set_cursor(0, { 51, 0 })

      local pos = position.get_scroll_position()
      assert.equals(0.5, pos)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns 0 for single-line buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "single line" })

      local pos = position.get_scroll_position()
      assert.equals(0, pos)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("should_display", function()
    it("returns false for buffer under min_lines", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      local lines = {}
      for i = 1, 5 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      assert.is_false(position.should_display(10))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns true for buffer at or over min_lines", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      local lines = {}
      for i = 1, 20 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      assert.is_true(position.should_display(10))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

end)
