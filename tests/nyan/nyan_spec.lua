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

describe("space renderer integration", function()
  it("setup with space renderer creates space highlights", function()
    require("nyan").setup({ renderer = "space" })
    local hl = vim.api.nvim_get_hl(0, { name = "NyanShip" })
    assert.is_not.same({}, hl)
  end)
end)

describe("search command-line wiring", function()
  local orig_getcmdtype, orig_getcmdline

  before_each(function()
    orig_getcmdtype = vim.fn.getcmdtype
    orig_getcmdline = vim.fn.getcmdline
    require("nyan.providers.search").clear_live()
  end)

  after_each(function()
    vim.fn.getcmdtype = orig_getcmdtype
    vim.fn.getcmdline = orig_getcmdline
    require("nyan.providers.search").clear_live()
  end)

  it("registers cmdline autocommands for the space renderer", function()
    require("nyan").setup({ renderer = "space" })

    local changed = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "CmdlineChanged" })
    local left = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "CmdlineLeave" })
    assert.is_true(#changed > 0)
    assert.is_true(#left > 0)
  end)

  it("registers no cmdline autocommands when search is disabled", function()
    require("nyan").setup({ renderer = "space", search = false })

    local changed = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "CmdlineChanged" })
    assert.equals(0, #changed)
  end)

  it("pushes the typed pattern into the provider while searching", function()
    require("nyan").setup({ renderer = "space" })
    local search = require("nyan.providers.search")
    search.invalidate_all()

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "needle", "gamma" })

    vim.fn.getcmdtype = function()
      return "/"
    end
    vim.fn.getcmdline = function()
      return "needle"
    end
    vim.api.nvim_exec_autocmds("CmdlineChanged", { group = "NyanNvim" })

    local result = search.get(buf)
    assert.equals(1, #result)
    assert.equals(2, result[1].line)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("ignores non-search command lines", function()
    require("nyan").setup({ renderer = "space" })
    local search = require("nyan.providers.search")
    search.invalidate_all()
    vim.o.hlsearch = true
    vim.v.hlsearch = 0

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "needle", "gamma" })

    vim.fn.getcmdtype = function()
      return ":"
    end
    vim.fn.getcmdline = function()
      return "needle"
    end
    vim.api.nvim_exec_autocmds("CmdlineChanged", { group = "NyanNvim" })

    -- No live pattern was set, and hlsearch is off, so nothing is marked.
    assert.same({}, search.get(buf))

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("clears the live pattern when the command line closes", function()
    require("nyan").setup({ renderer = "space" })
    local search = require("nyan.providers.search")
    search.invalidate_all()
    vim.o.hlsearch = true
    vim.v.hlsearch = 0

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "needle", "gamma" })

    search.set_live("needle")
    assert.equals(1, #search.get(buf))

    vim.api.nvim_exec_autocmds("CmdlineLeave", { group = "NyanNvim" })
    assert.same({}, search.get(buf))

    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
