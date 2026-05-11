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

local function git_run(dir, ...)
  local cmd = { "git", "-C", dir }
  for _, a in ipairs({ ... }) do
    table.insert(cmd, a)
  end
  return vim.fn.system(cmd)
end

local function write_file(path, content)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

local function make_repo()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  git_run(dir, "init", "-q", "-b", "main")
  git_run(dir, "config", "user.email", "test@example.com")
  git_run(dir, "config", "user.name", "test")
  git_run(dir, "config", "commit.gpgsign", "false")
  return dir
end

local function open_buf(path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

describe("providers.git (git diff path)", function()
  local repo
  local cleanup = {}

  before_each(function()
    -- Ensure gitsigns mock from previous describes is unloaded
    package.loaded["gitsigns"] = nil
    git.invalidate_all()
    repo = make_repo()
    table.insert(cleanup, repo)
  end)

  after_each(function()
    git.invalidate_all()
    -- Best effort cleanup; tempname dirs are small
    for _, dir in ipairs(cleanup) do
      vim.fn.delete(dir, "rf")
    end
    cleanup = {}
  end)

  it("returns empty list for unnamed buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    assert.same({}, git.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns empty list for a file outside any git repo", function()
    local path = vim.fn.tempname()
    write_file(path, "no repo here\n")
    local buf = open_buf(path)
    assert.same({}, git.get(buf))
    os.remove(path)
  end)

  it("detects an unstaged addition", function()
    local path = repo .. "/file.txt"
    write_file(path, "line1\nline2\nline3\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")
    write_file(path, "line1\nline2\nline3\nline4\nline5\n")

    local buf = open_buf(path)
    local result = git.get(buf)
    assert.is_true(#result >= 1)
    assert.equals("add", result[1].type)
    assert.is_false(result[1].staged)
  end)

  it("detects an unstaged change", function()
    local path = repo .. "/file.txt"
    write_file(path, "a\nb\nc\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")
    write_file(path, "a\nB\nc\n")

    local buf = open_buf(path)
    local result = git.get(buf)
    assert.is_true(#result >= 1)
    assert.equals("change", result[1].type)
  end)

  it("marks staged hunks via staged flag", function()
    local path = repo .. "/file.txt"
    write_file(path, "a\nb\nc\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")

    write_file(path, "a\nb\nc\nd\n")
    git_run(repo, "add", "file.txt")

    local buf = open_buf(path)
    local result = git.get(buf)
    assert.is_true(#result >= 1)
    local found_staged = false
    for _, r in ipairs(result) do
      if r.staged then
        found_staged = true
      end
    end
    assert.is_true(found_staged)
  end)

  it("caches results across calls until invalidated", function()
    local path = repo .. "/file.txt"
    write_file(path, "a\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")
    write_file(path, "a\nb\n")

    local buf = open_buf(path)
    local first = git.get(buf)
    -- Mutate on disk; cache should still return the original result
    write_file(path, "a\n")
    local second = git.get(buf)
    assert.equals(#first, #second)

    git.invalidate(buf)
    local third = git.get(buf)
    assert.equals(0, #third)
  end)
end)

describe("providers.git (gitsigns fallback)", function()
  before_each(function()
    git.invalidate_all()
  end)

  after_each(function()
    package.loaded["gitsigns"] = nil
    git.invalidate_all()
  end)

  it("falls through to git diff when gitsigns.get_hunks errors", function()
    package.loaded["gitsigns"] = {
      get_hunks = function()
        error("boom")
      end,
    }
    -- Unnamed buffer means git diff path returns empty — not an error
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local result = git.get(buf)
    assert.is_table(result)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("falls through to git diff when gitsigns.get_hunks returns nil", function()
    package.loaded["gitsigns"] = {
      get_hunks = function()
        return nil
      end,
    }
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    assert.is_table(git.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
