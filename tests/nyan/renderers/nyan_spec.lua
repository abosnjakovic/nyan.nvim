---@diagnostic disable: duplicate-set-field
local config = require("nyan.config")
local kitty = require("nyan.kitty")
local position = require("nyan.position")

local function reset_module()
  package.loaded["nyan.renderers.nyan"] = nil
  return require("nyan.renderers.nyan")
end

describe("renderers.nyan", function()
  local nyan
  local original_kitty_is_supported
  local original_kitty_id_to_colour
  local original_position_should_display
  local original_position_get_scroll
  local original_set_hl
  local set_hl_calls

  before_each(function()
    original_kitty_is_supported = kitty.is_supported
    original_kitty_id_to_colour = kitty.id_to_colour
    original_position_should_display = position.should_display
    original_position_get_scroll = position.get_scroll_position
    original_set_hl = vim.api.nvim_set_hl

    set_hl_calls = {}
    kitty.id_to_colour = function()
      return "#ff00ff"
    end
    position.should_display = function()
      return true
    end
    position.get_scroll_position = function()
      return 0.0
    end
    vim.api.nvim_set_hl = function(ns, name, opts)
      table.insert(set_hl_calls, { ns = ns, name = name, opts = opts })
      return original_set_hl(ns, name, opts)
    end

    config.setup({ width = 20, fallback = "ascii", min_buffer_lines = 1 })
    nyan = reset_module()
  end)

  after_each(function()
    kitty.is_supported = original_kitty_is_supported
    kitty.id_to_colour = original_kitty_id_to_colour
    position.should_display = original_position_should_display
    position.get_scroll_position = original_position_get_scroll
    vim.api.nvim_set_hl = original_set_hl
  end)

  describe("init", function()
    it("enables graphics when kitty supported and cat_ids non-empty", function()
      kitty.is_supported = function()
        return true
      end
      nyan.init({ 1, 2, 3 }, 99)
      assert.is_true(nyan.is_graphics_enabled())
    end)

    it("disables graphics when kitty unsupported", function()
      kitty.is_supported = function()
        return false
      end
      nyan.init({ 1, 2, 3 }, 99)
      assert.is_false(nyan.is_graphics_enabled())
    end)

    it("disables graphics when cat_ids empty", function()
      kitty.is_supported = function()
        return true
      end
      nyan.init({}, 99)
      assert.is_false(nyan.is_graphics_enabled())
    end)

    it("creates NyanCat<n> and NyanRainbow highlight groups in graphics mode", function()
      kitty.is_supported = function()
        return true
      end
      nyan.init({ 10, 20, 30 }, 99)
      local names = {}
      for _, call in ipairs(set_hl_calls) do
        names[call.name] = true
      end
      assert.is_true(names["NyanCat1"])
      assert.is_true(names["NyanCat2"])
      assert.is_true(names["NyanCat3"])
      assert.is_true(names["NyanRainbow"])
    end)

    it("does not create cat highlight groups when graphics disabled", function()
      kitty.is_supported = function()
        return false
      end
      nyan.init({ 1, 2 }, 99)
      for _, call in ipairs(set_hl_calls) do
        assert.is_nil(call.name:match("^NyanCat%d"))
        assert.is_not.equals("NyanRainbow", call.name)
      end
    end)
  end)

  describe("next_frame", function()
    it("cycles 1..#cat_ids and wraps back to 1 in graphics mode", function()
      kitty.is_supported = function()
        return true
      end
      nyan.init({ 1, 2, 3 }, 99)
      assert.equals(2, nyan.next_frame())
      assert.equals(3, nyan.next_frame())
      assert.equals(1, nyan.next_frame())
    end)

    it("cycles 1..2 in ascii mode", function()
      kitty.is_supported = function()
        return false
      end
      nyan.init({}, nil)
      assert.equals(2, nyan.next_frame())
      assert.equals(1, nyan.next_frame())
    end)

    it("returns a positive number", function()
      kitty.is_supported = function()
        return false
      end
      nyan.init({}, nil)
      local f = nyan.next_frame()
      assert.is_number(f)
      assert.is_true(f >= 1)
    end)
  end)

  describe("is_graphics_enabled", function()
    it("returns boolean matching init state", function()
      kitty.is_supported = function()
        return true
      end
      nyan.init({ 1 }, 2)
      assert.is_boolean(nyan.is_graphics_enabled())
      assert.is_true(nyan.is_graphics_enabled())
    end)
  end)

  describe("render", function()
    it("returns empty string when should_display is false", function()
      position.should_display = function()
        return false
      end
      kitty.is_supported = function()
        return false
      end
      nyan.init({}, nil)
      assert.equals("", nyan.render())
    end)

    it("graphics mode emits NyanCat<frame> highlight and placeholder", function()
      kitty.is_supported = function()
        return true
      end
      nyan.init({ 1, 2 }, 99)
      local out = nyan.render()
      assert.is_truthy(out:find("NyanCat1", 1, true))
      assert.is_truthy(out:find("\u{10EEEE}", 1, true))
    end)

    it("ascii mode emits NyanCat highlight and ascii cat frame", function()
      kitty.is_supported = function()
        return false
      end
      nyan.init({}, nil)
      local out = nyan.render()
      assert.is_truthy(out:find("NyanCat", 1, true))
      assert.is_truthy(out:find("^._.^=", 1, true))
    end)

    it("rainbow length is zero at scroll position 0.0 (ascii)", function()
      kitty.is_supported = function()
        return false
      end
      position.get_scroll_position = function()
        return 0.0
      end
      nyan.init({}, nil)
      local out = nyan.render()
      assert.is_nil(out:find("NyanRainbow1", 1, true))
    end)

    it("rainbow trail fills available width at scroll position 1.0 (ascii)", function()
      kitty.is_supported = function()
        return false
      end
      position.get_scroll_position = function()
        return 1.0
      end
      config.setup({ width = 20, fallback = "ascii", min_buffer_lines = 1 })
      nyan.init({}, nil)
      local out = nyan.render()
      assert.is_truthy(out:find("NyanRainbow1", 1, true))
      assert.is_truthy(out:find("NyanRainbow6", 1, true))
    end)

    it("ascii rainbow cycles 6 colour highlight groups", function()
      kitty.is_supported = function()
        return false
      end
      position.get_scroll_position = function()
        return 1.0
      end
      config.setup({ width = 20, fallback = "ascii", min_buffer_lines = 1 })
      nyan.init({}, nil)
      local out = nyan.render()
      for i = 1, 6 do
        assert.is_truthy(out:find("NyanRainbow" .. i, 1, true))
      end
    end)

    it("graphics mode emits NyanRainbow at scroll position 1.0", function()
      kitty.is_supported = function()
        return true
      end
      position.get_scroll_position = function()
        return 1.0
      end
      nyan.init({ 1 }, 99)
      local out = nyan.render()
      assert.is_truthy(out:find("NyanRainbow", 1, true))
    end)

    it("output is padded to configured width (ascii, no rainbow)", function()
      kitty.is_supported = function()
        return false
      end
      position.get_scroll_position = function()
        return 0.0
      end
      config.setup({ width = 30, fallback = "ascii", min_buffer_lines = 1 })
      nyan.init({}, nil)
      local out = nyan.render()
      local plain = out:gsub("%%#[^#]+#", ""):gsub("%%%*", "")
      assert.equals(30, vim.fn.strdisplaywidth(plain))
    end)

    it("returns empty string when graphics disabled and fallback is not ascii", function()
      kitty.is_supported = function()
        return false
      end
      config.setup({ width = 20, fallback = "none", min_buffer_lines = 1 })
      nyan.init({}, nil)
      assert.equals("", nyan.render())
    end)
  end)
end)
