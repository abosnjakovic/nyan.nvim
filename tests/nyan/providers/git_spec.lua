local git = require("nyan.providers.git")

describe("providers.git", function()
  it("returns empty list when gitsigns not available", function()
    -- In test env, gitsigns is not installed
    local result = git.get(0)
    assert.same({}, result)
  end)

  describe("with mock gitsigns", function()
    local original_require

    before_each(function()
      -- Mock gitsigns module in package.loaded
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
      -- Override mock so staged hunk shares a line with an unstaged hunk
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
      -- Line 10 appears in both unstaged and staged, so staged = true
      assert.equals(10, result[1].line)
      assert.is_true(result[1].staged)
      -- Line 50 is not staged
      assert.equals(50, result[2].line)
      assert.is_false(result[2].staged)
    end)
  end)
end)
