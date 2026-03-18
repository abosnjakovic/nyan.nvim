local space = require("nyan.renderers.space")
local config = require("nyan.config")

describe("renderers.space", function()
  local buf

  before_each(function()
    config.setup({ renderer = "space", width = 22 })
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    -- Ensure highlights exist
    space.setup_highlights()
  end)

  after_each(function()
    vim.diagnostic.reset(nil, buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  describe("render", function()
    it("returns empty string for small buffer", function()
      local small_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(small_buf)
      vim.api.nvim_buf_set_lines(small_buf, 0, -1, false, { "a", "b" })

      local result = space.render()
      assert.equals("", result)

      vim.api.nvim_buf_delete(small_buf, { force = true })
    end)

    it("returns string starting with [ and ending with ]", function()
      local result = space.render()
      -- Strip highlight groups to check raw characters
      local plain = result:gsub("%%#[^#]+#", ""):gsub("%%*", "")
      assert.equals("[", plain:sub(1, 1))
      assert.equals("]", plain:sub(-1))
    end)

    it("contains the ship character", function()
      local result = space.render()
      assert.is_truthy(result:find("▷"))
    end)

    it("contains trail dots for empty cells", function()
      local result = space.render()
      assert.is_truthy(result:find("·"))
    end)

    it("shows diagnostic markers", function()
      local ns = vim.api.nvim_create_namespace("test_space")
      vim.diagnostic.set(ns, buf, {
        { lnum = 49, col = 0, message = "err", severity = vim.diagnostic.severity.ERROR },
      })

      local result = space.render()
      assert.is_truthy(result:find("✕"))
    end)

    it("ship takes priority over markers on same cell", function()
      -- Cursor is at line 1, so ship is at cell 0
      -- Place a diagnostic at line 1 (also cell 0)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local ns = vim.api.nvim_create_namespace("test_ship_priority")
      vim.diagnostic.set(ns, buf, {
        { lnum = 0, col = 0, message = "err", severity = vim.diagnostic.severity.ERROR },
      })

      local result = space.render()
      local plain = result:gsub("%%#[^#]+#", ""):gsub("%%*", "")
      -- First char after '[' should be ship, not diagnostic
      assert.equals("▷", plain:sub(2, 4)) -- ▷ is multi-byte
    end)

    it("renders correctly when all cells have markers", function()
      -- Fill every line with a diagnostic
      local ns = vim.api.nvim_create_namespace("test_full")
      local diags = {}
      for i = 0, 99 do
        table.insert(diags, { lnum = i, col = 0, message = "err", severity = vim.diagnostic.severity.ERROR })
      end
      vim.diagnostic.set(ns, buf, diags)

      local result = space.render()
      -- Ship should still appear
      assert.is_truthy(result:find("▷"))
      -- Brackets should still be there
      local plain = result:gsub("%%#[^#]+#", ""):gsub("%%*", "")
      assert.equals("[", plain:sub(1, 1))
      assert.equals("]", plain:sub(-1))
    end)
  end)

  describe("map_to_cell", function()
    it("maps line 1 to cell 0", function()
      local cell = space.map_to_cell(1, 100, 20)
      assert.equals(0, cell)
    end)

    it("maps last line to last cell", function()
      local cell = space.map_to_cell(100, 100, 20)
      assert.equals(19, cell)
    end)

    it("maps middle line to middle cell", function()
      local cell = space.map_to_cell(50, 100, 20)
      -- (50-1) / (100-1) * 19 = 49/99 * 19 ≈ 9.4 -> 9
      assert.equals(9, cell)
    end)

    it("handles single-line buffer", function()
      local cell = space.map_to_cell(1, 1, 20)
      assert.equals(0, cell)
    end)
  end)

  describe("resolve_collisions", function()
    it("higher priority wins", function()
      -- Priority: error(1) > warn(2) > git(3) > info(4) > hint(5)
      local markers = {
        [5] = { char = "✕", hl = "NyanDiagHint", priority = 5 },
      }
      local new = { char = "✕", hl = "NyanDiagError", priority = 1 }
      space.place_marker(markers, 5, new)
      assert.equals("NyanDiagError", markers[5].hl)
    end)

    it("lower priority does not overwrite", function()
      local markers = {
        [5] = { char = "✕", hl = "NyanDiagError", priority = 1 },
      }
      local new = { char = "│", hl = "NyanGitAdded", priority = 3 }
      space.place_marker(markers, 5, new)
      assert.equals("NyanDiagError", markers[5].hl)
    end)
  end)
end)
