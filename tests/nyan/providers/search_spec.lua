local search = require("nyan.providers.search")

describe("providers.search", function()
  local buf

  before_each(function()
    search.clear_live()
    search.invalidate_all()
    search._scan_count = 0

    -- Start from a known option state; individual tests override as needed.
    vim.o.hlsearch = true
    vim.o.ignorecase = false
    vim.o.smartcase = false
    vim.v.hlsearch = 0
    vim.fn.setreg("/", "")

    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    -- Lines 1..100. "target" appears on lines 3 and 7 only.
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    lines[3] = "target here"
    lines[7] = "another target"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end)

  after_each(function()
    search.clear_live()
    search.invalidate_all()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  describe("pattern resolution", function()
    it("returns empty list when no pattern is set", function()
      assert.same({}, search.get(buf))
    end)

    it("returns empty list when hlsearch is off, even with a register pattern", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 0
      assert.same({}, search.get(buf))
    end)

    it("returns 1-indexed matching lines from the register when hlsearch is on", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 1

      local result = search.get(buf)
      assert.equals(2, #result)
      assert.equals(3, result[1].line)
      assert.equals(7, result[2].line)
    end)

    it("set_live overrides the register pattern", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 1
      search.set_live("line 42")

      local result = search.get(buf)
      assert.equals(1, #result)
      assert.equals(42, result[1].line)
    end)

    it("clear_live restores register behaviour", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 1
      search.set_live("line 42")
      search.get(buf)

      search.clear_live()
      local result = search.get(buf)
      assert.equals(2, #result)
      assert.equals(3, result[1].line)
    end)

    it("an empty live pattern marks nothing and does not fall back to the register", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 1
      search.set_live("")

      assert.same({}, search.get(buf))
    end)
  end)

  describe("invalid patterns", function()
    it("returns empty list instead of throwing on a half-typed regex", function()
      search.set_live("target\\(")

      local result
      assert.has_no.errors(function()
        result = search.get(buf)
      end)
      assert.same({}, result)
    end)
  end)

  describe("case sensitivity", function()
    before_each(function()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "lower target", "UPPER TARGET" })
    end)

    it("is case-sensitive when ignorecase is off", function()
      vim.o.ignorecase = false
      search.set_live("TARGET")

      local result = search.get(buf)
      assert.equals(1, #result)
      assert.equals(2, result[1].line)
    end)

    it("is case-insensitive when ignorecase is on and smartcase is off", function()
      vim.o.ignorecase = true
      vim.o.smartcase = false
      search.set_live("TARGET")

      assert.equals(2, #search.get(buf))
    end)

    it("stays case-insensitive with smartcase on and an all-lowercase pattern", function()
      vim.o.ignorecase = true
      vim.o.smartcase = true
      search.set_live("target")

      assert.equals(2, #search.get(buf))
    end)

    it("becomes case-sensitive with smartcase on and an uppercase pattern", function()
      vim.o.ignorecase = true
      vim.o.smartcase = true
      search.set_live("TARGET")

      local result = search.get(buf)
      assert.equals(1, #result)
      assert.equals(2, result[1].line)
    end)

    it("does not treat a backslash-escaped uppercase as a smartcase trigger", function()
      vim.o.ignorecase = true
      vim.o.smartcase = true
      -- \V is very-nomagic, not an uppercase letter in the user's pattern.
      search.set_live("\\Vtarget")

      assert.equals(2, #search.get(buf))
    end)
  end)

  describe("caching", function()
    it("scans once for repeated calls on an unchanged buffer", function()
      search.set_live("target")

      search.get(buf)
      search.get(buf)
      search.get(buf)

      assert.equals(1, search._scan_count)
    end)

    it("rescans after the buffer changes", function()
      search.set_live("target")
      search.get(buf)

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "target", "target", "target" })
      local result = search.get(buf)

      assert.equals(2, search._scan_count)
      assert.equals(3, #result)
    end)

    it("rescans after invalidate", function()
      search.set_live("target")
      search.get(buf)

      search.invalidate(buf)
      search.get(buf)

      assert.equals(2, search._scan_count)
    end)

    it("rescans after invalidate_all", function()
      search.set_live("target")
      search.get(buf)

      search.invalidate_all()
      search.get(buf)

      assert.equals(2, search._scan_count)
    end)

    it("rescans when the pattern changes", function()
      search.set_live("target")
      search.get(buf)

      search.set_live("line 42")
      search.get(buf)

      assert.equals(2, search._scan_count)
    end)
  end)

  describe("limits", function()
    it("returns empty list for a buffer over the scan cap", function()
      local big = vim.api.nvim_create_buf(false, true)
      local lines = {}
      for i = 1, 20001 do
        lines[i] = "target"
      end
      vim.api.nvim_buf_set_lines(big, 0, -1, false, lines)
      search.set_live("target")

      assert.same({}, search.get(big))

      vim.api.nvim_buf_delete(big, { force = true })
    end)

    it("skips lines too long to match safely, keeping hits on the rest", function()
      -- A backtracking pattern on one long blob line (minified, base64) can
      -- freeze the statusline for seconds, so such lines are not matched.
      local long = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(long, 0, -1, false, { "target", string.rep("x", 1001) .. "target", "target" })
      search.set_live("target")

      assert.same({ { line = 1 }, { line = 3 } }, search.get(long))

      vim.api.nvim_buf_delete(long, { force = true })
    end)

    it("gives up and marks nothing when a scan overruns its time budget", function()
      -- Slow patterns across many lines add up to a stalled keystroke. Each
      -- clock read here jumps 200 ms, so the scan is over budget at once.
      local real_hrtime = vim.uv.hrtime
      local now = 0
      vim.uv.hrtime = function()
        now = now + 200e6
        return now
      end
      search.set_live("target")
      local ok, result = pcall(search.get, buf)
      vim.uv.hrtime = real_hrtime

      assert.is_true(ok)
      assert.same({}, result)
    end)

    it("returns empty list for an invalid buffer", function()
      search.set_live("target")
      assert.same({}, search.get(99999))
    end)
  end)
end)
