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

  it("sets an unknown renderer up fully as space, since render.lua draws it as space", function()
    -- A typo once got the space bar without its git refresh autocmds
    require("nyan").setup({ renderer = "minimap" })
    local autocmds = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "BufWritePost" })
    assert.is_true(#autocmds > 0)
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

describe("setup wiring", function()
  it("bails out and notifies on Neovim older than 0.10", function()
    local orig_has = vim.fn.has
    local orig_notify = vim.notify
    local notified

    vim.fn.has = function(feature)
      if feature == "nvim-0.10" then
        return 0
      end
      return orig_has(feature)
    end
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end

    require("nyan").setup({ renderer = "space" })

    vim.fn.has = orig_has
    vim.notify = orig_notify

    assert.is_truthy(notified)
    assert.equals("nyan.nvim requires Neovim 0.10 or later", notified.msg)
    assert.equals(vim.log.levels.ERROR, notified.level)
  end)

  it("registers the three user commands", function()
    require("nyan").setup({ renderer = "space" })
    local commands = vim.api.nvim_get_commands({})

    assert.is_truthy(commands.NyanStart)
    assert.is_truthy(commands.NyanStop)
    assert.is_truthy(commands.NyanToggle)
  end)

  it("wires diagnostic and git autocommands for the space renderer", function()
    require("nyan").setup({ renderer = "space" })

    local diag = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "DiagnosticChanged" })
    local write = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "BufWritePost" })
    assert.is_true(#diag > 0)
    assert.is_true(#write > 0)
  end)

  it("wires focus and exit autocommands for the nyan renderer", function()
    -- The nyan branch calls load_sprites(), which transmits real PNGs to stdout
    -- when kitty.is_supported() is true. Neutralise the terminal detection so
    -- the test does not spray graphics escape sequences into the test output
    -- for anyone running the suite inside Kitty or Ghostty.
    local saved = { vim.env.TERM, vim.env.TERM_PROGRAM, vim.env.KITTY_WINDOW_ID }
    vim.env.TERM = "dumb"
    vim.env.TERM_PROGRAM = ""
    vim.env.KITTY_WINDOW_ID = nil

    require("nyan").setup({ renderer = "nyan", animation = { enabled = false } })

    vim.env.TERM, vim.env.TERM_PROGRAM, vim.env.KITTY_WINDOW_ID = saved[1], saved[2], saved[3]

    local leave = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "VimLeavePre" })
    local diag = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "DiagnosticChanged" })
    assert.is_true(#leave > 0)
    -- The nyan branch must not install the space renderer's autocommands.
    assert.equals(0, #diag)
  end)

  it("always wires the ColorScheme autocommand", function()
    require("nyan").setup({ renderer = "space" })
    local cs = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "ColorScheme" })
    assert.is_true(#cs > 0)
  end)
end)
