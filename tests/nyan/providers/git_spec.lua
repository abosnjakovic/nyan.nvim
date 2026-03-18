local git = require("nyan.providers.git")

describe("providers.git", function()
  it("returns empty list when gitsigns not available and no git repo", function()
    local result = git.get(0)
    assert.is_table(result)
  end)

  describe("hunk header parsing", function()
    it("parses an add hunk", function()
      local hunk = git._parse_hunk_header("@@ -10,0 +11,3 @@ some context")
      assert.equals(11, hunk.line)
      assert.equals("add", hunk.type)
    end)

    it("parses a delete hunk", function()
      local hunk = git._parse_hunk_header("@@ -10,3 +9,0 @@ some context")
      assert.equals(9, hunk.line)
      assert.equals("delete", hunk.type)
    end)

    it("parses a change hunk", function()
      local hunk = git._parse_hunk_header("@@ -10,3 +10,5 @@ some context")
      assert.equals(10, hunk.line)
      assert.equals("change", hunk.type)
    end)

    it("parses hunk with no count (single line)", function()
      local hunk = git._parse_hunk_header("@@ -10 +10 @@")
      assert.equals(10, hunk.line)
      assert.equals("change", hunk.type)
    end)

    it("returns nil for invalid header", function()
      local hunk = git._parse_hunk_header("not a hunk header")
      assert.is_nil(hunk)
    end)
  end)

  describe("with mock gitsigns", function()
    before_each(function()
      package.loaded["gitsigns"] = {
        get_hunks = function(bufnr, opts)
          if opts and opts.staged then
            return {
              { added = { start = 20, count = 3 }, removed = { start = 0, count = 0 }, type = "add" },
            }
          end
          return {
            { added = { start = 10, count = 5 }, removed = { start = 0, count = 0 }, type = "add" },
            { added = { start = 50, count = 0 }, removed = { start = 50, count = 3 }, type = "delete" },
            { added = { start = 80, count = 2 }, removed = { start = 80, count = 2 }, type = "change" },
          }
        end,
      }
    end)

    after_each(function()
      package.loaded["gitsigns"] = nil
    end)

    it("returns markers from unstaged hunks", function()
      local result = git.get(0)
      assert.equals(3, #result)
      assert.equals(10, result[1].line)
      assert.equals("add", result[1].type)
      assert.is_false(result[1].staged)
      assert.equals(50, result[2].line)
      assert.equals("delete", result[2].type)
      assert.equals(80, result[3].line)
      assert.equals("change", result[3].type)
    end)

    it("marks staged hunks when lines overlap", function()
      package.loaded["gitsigns"] = {
        get_hunks = function(bufnr, opts)
          if opts and opts.staged then
            return {
              { added = { start = 10, count = 3 }, removed = { start = 0, count = 0 }, type = "add" },
            }
          end
          return {
            { added = { start = 10, count = 5 }, removed = { start = 0, count = 0 }, type = "add" },
            { added = { start = 50, count = 0 }, removed = { start = 50, count = 3 }, type = "delete" },
          }
        end,
      }

      local result = git.get(0)
      assert.equals(2, #result)
      assert.equals(10, result[1].line)
      assert.is_true(result[1].staged)
      assert.equals(50, result[2].line)
      assert.is_false(result[2].staged)
    end)
  end)

  describe("cache", function()
    it("invalidate clears cache for buffer", function()
      -- Should not error
      git.invalidate(0)
      git.invalidate_all()
    end)
  end)
end)
