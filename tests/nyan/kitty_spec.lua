---@diagnostic disable: duplicate-set-field, inject-field
local kitty = require("nyan.kitty")

describe("kitty", function()
  describe("id_to_colour", function()
    it("converts image id 1 to correct hex", function()
      assert.equals("#000001", kitty.id_to_colour(1))
    end)

    it("converts image id 255 to correct hex", function()
      assert.equals("#0000ff", kitty.id_to_colour(255))
    end)

    it("converts larger image ids correctly", function()
      assert.equals("#010000", kitty.id_to_colour(65536))
    end)
  end)

  describe("base64_encode", function()
    it("encodes simple string correctly", function()
      -- "hello" in base64 is "aGVsbG8="
      local encoded = kitty.base64_encode("hello")
      assert.equals("aGVsbG8=", encoded)
    end)

    it("handles empty string", function()
      local encoded = kitty.base64_encode("")
      assert.equals("", encoded)
    end)
  end)

  describe("is_supported", function()
    it("returns boolean", function()
      local result = kitty.is_supported()
      assert.is_boolean(result)
    end)
  end)
end)

describe("kitty (extended)", function()
  local fresh_kitty
  local saved_env
  local original_write
  local original_flush
  local writes
  local original_notify

  local ENV_KEYS = { "TERM", "TERM_PROGRAM", "TMUX", "KITTY_WINDOW_ID", "GHOSTTY_RESOURCES_DIR" }

  before_each(function()
    saved_env = {}
    for _, k in ipairs(ENV_KEYS) do
      saved_env[k] = vim.env[k]
      vim.env[k] = nil
    end

    writes = {}
    original_write = io.write
    original_flush = io.flush
    rawset(io, "write", function(s)
      table.insert(writes, s)
    end)
    rawset(io, "flush", function() end)

    original_notify = vim.notify
    vim.notify = function() end

    package.loaded["nyan.kitty"] = nil
    fresh_kitty = require("nyan.kitty")
  end)

  after_each(function()
    for _, k in ipairs(ENV_KEYS) do
      vim.env[k] = saved_env[k]
    end
    rawset(io, "write", original_write)
    rawset(io, "flush", original_flush)
    vim.notify = original_notify
    package.loaded["nyan.kitty"] = nil
  end)

  describe("is_supported", function()
    it("detects xterm-kitty TERM", function()
      vim.env.TERM = "xterm-kitty"
      assert.is_true(fresh_kitty.is_supported())
    end)

    it("detects ghostty via TERM_PROGRAM", function()
      vim.env.TERM_PROGRAM = "ghostty"
      assert.is_true(fresh_kitty.is_supported())
    end)

    it("detects ghostty via TERM", function()
      vim.env.TERM = "ghostty"
      assert.is_true(fresh_kitty.is_supported())
    end)

    it("detects KITTY_WINDOW_ID", function()
      vim.env.KITTY_WINDOW_ID = "1"
      assert.is_true(fresh_kitty.is_supported())
    end)

    it("detects GHOSTTY_RESOURCES_DIR", function()
      vim.env.GHOSTTY_RESOURCES_DIR = "/somewhere"
      assert.is_true(fresh_kitty.is_supported())
    end)

    it("returns true when inside tmux", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
      assert.is_true(fresh_kitty.is_supported())
    end)

    it("returns false when no markers present", function()
      vim.env.TERM = "dumb"
      assert.is_false(fresh_kitty.is_supported())
    end)
  end)

  describe("read_file", function()
    it("returns contents of an existing file", function()
      local path = vim.fn.tempname()
      local f = assert(io.open(path, "wb"))
      f:write("hello bytes")
      f:close()

      assert.equals("hello bytes", fresh_kitty.read_file(path))
      os.remove(path)
    end)

    it("returns nil for a missing file", function()
      assert.is_nil(fresh_kitty.read_file("/nonexistent/path/" .. tostring(math.random(1e9))))
    end)
  end)

  describe("transmit_image", function()
    local png_path

    before_each(function()
      png_path = vim.fn.tempname()
      local f = assert(io.open(png_path, "wb"))
      f:write("fake png bytes")
      f:close()
    end)

    after_each(function()
      if png_path then
        os.remove(png_path)
      end
    end)

    it("returns 0 and does not write when file missing", function()
      local id = fresh_kitty.transmit_image("/nonexistent/file.png")
      assert.equals(0, id)
      assert.equals(0, #writes)
    end)

    it("assigns sequential image IDs when none provided", function()
      local id1 = fresh_kitty.transmit_image(png_path)
      local id2 = fresh_kitty.transmit_image(png_path)
      assert.equals(1, id1)
      assert.equals(2, id2)
    end)

    it("uses explicit image_id and does not bump the counter", function()
      local id1 = fresh_kitty.transmit_image(png_path, 99)
      local id2 = fresh_kitty.transmit_image(png_path)
      assert.equals(99, id1)
      assert.equals(1, id2)
    end)

    it("emits APC sequence with a=t,f=100 for small payload", function()
      fresh_kitty.transmit_image(png_path, 7)
      local full = table.concat(writes)
      assert.is_truthy(full:find("a=t,f=100,i=7,q=2", 1, true))
      assert.is_truthy(full:find("\027_G", 1, true))
      assert.is_truthy(full:find("\027\\", 1, true))
    end)

    it("chunks large payloads with m=1 then m=0", function()
      local big = vim.fn.tempname()
      local f = assert(io.open(big, "wb"))
      f:write(string.rep("A", 8000))
      f:close()

      fresh_kitty.transmit_image(big, 3)
      local full = table.concat(writes)
      assert.is_truthy(full:find("i=3,m=1", 1, true))
      assert.is_truthy(full:find("m=0", 1, true))
      os.remove(big)
    end)
  end)

  describe("create_virtual_placement", function()
    it("emits a=p,U=1 with image id, cols, rows", function()
      fresh_kitty.create_virtual_placement(42, 5, 2)
      local full = table.concat(writes)
      assert.is_truthy(full:find("a=p,U=1,i=42,c=5,r=2,q=2", 1, true))
    end)
  end)

  describe("delete_image", function()
    it("emits a=d,d=I with image id", function()
      fresh_kitty.delete_image(13)
      local full = table.concat(writes)
      assert.is_truthy(full:find("a=d,d=I,i=13,q=2", 1, true))
    end)
  end)

  describe("delete_all_images", function()
    it("deletes each transmitted id and resets the counter", function()
      local png = vim.fn.tempname()
      local f = assert(io.open(png, "wb"))
      f:write("x")
      f:close()
      fresh_kitty.transmit_image(png)
      fresh_kitty.transmit_image(png)
      writes = {}

      fresh_kitty.delete_all_images()
      local full = table.concat(writes)
      assert.is_truthy(full:find("i=1", 1, true))
      assert.is_truthy(full:find("i=2", 1, true))

      local id_after = fresh_kitty.transmit_image(png)
      assert.equals(1, id_after)
      os.remove(png)
    end)
  end)

  describe("tmux passthrough", function()
    it("wraps writes in \\ePtmux when TMUX env is set", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
      -- is_supported also sets the in_tmux flag
      fresh_kitty.is_supported()
      fresh_kitty.delete_image(5)
      local full = table.concat(writes)
      assert.is_truthy(full:find("\027Ptmux;", 1, true))
      -- ESC chars inside the original sequence should be doubled
      assert.is_truthy(full:find("\027\027_G", 1, true))
    end)
  end)
end)
