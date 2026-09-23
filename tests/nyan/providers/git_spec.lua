local git = require("nyan.providers.git")

describe("providers.git", function()
  it("returns empty list when gitsigns not available and no git repo", function()
    local result = git.get(0)
    assert.is_table(result)
  end)

  it("caches the miss for non-git files instead of shelling out per redraw", function()
    -- Force the git-diff fallback path
    package.loaded["gitsigns"] = nil
    package.preload["gitsigns"] = function()
      error("gitsigns disabled for this test")
    end

    local buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".txt")
    git.invalidate(buf)

    local count = 0
    local orig = vim.system
    vim.system = function(cmd, opts, cb)
      if type(cmd) == "table" and cmd[1] == "git" then
        count = count + 1
      end
      return orig(cmd, opts, cb)
    end

    -- A burst of statusline redraws before the first diff lands must not queue
    -- a spawn each: the in-flight guard collapses them into one.
    for _ = 1, 10 do
      git.get(buf)
    end
    local during_flight = count

    -- A cached result is returned by identity; an uncached path builds a fresh
    -- empty table every call. Same table twice means the miss is now cached.
    local settled = vim.wait(5000, function()
      return git.get(buf) == git.get(buf)
    end, 10)

    for _ = 1, 10 do
      git.get(buf)
    end
    local after_settle = count

    vim.system = orig
    package.preload["gitsigns"] = nil
    vim.api.nvim_buf_delete(buf, { force = true })

    assert.equals(1, during_flight)
    assert.is_true(settled)
    assert.equals(1, after_settle)
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

    it("places a top-of-file deletion on line 1", function()
      -- new_start 0 means "before line 1"; line 0 would fall off the bar
      local hunk = git._parse_hunk_header("@@ -1,2 +0,0 @@")
      assert.equals(1, hunk.line)
      assert.equals("delete", hunk.type)
    end)

    it("returns nil for invalid header", function()
      local hunk = git._parse_hunk_header("not a hunk header")
      assert.is_nil(hunk)
    end)
  end)

  describe("staged line mapping", function()
    -- Staged hunks are numbered against the index; the markers must land on
    -- buffer lines, shifted by whatever unstaged hunks sit above them.
    local function staged_at(unstaged, staged)
      local out = {}
      for _, m in ipairs(git._build_markers(unstaged, staged)) do
        if m.staged then
          table.insert(out, m.line)
        end
      end
      return out
    end

    it("pulls a staged hunk up by an unstaged deletion above, ignoring hunks below", function()
      -- Index lines 3-4 deleted (-2); the insertion at index 40 is below and must not count
      assert.same({ 8 }, staged_at({ "@@ -3,2 +2,0 @@", "@@ -40,0 +39,4 @@" }, { "@@ -10 +10 @@" }))
    end)

    it("sums every unstaged hunk above, not only the last", function()
      assert.same({ 21 }, staged_at({ "@@ -0,0 +1,3 @@", "@@ -5,2 +7,0 @@" }, { "@@ -20 +20 @@" }))
      -- A header with no count is one line: one line becoming three is +2
      assert.same({ 22 }, staged_at({ "@@ -5 +5,3 @@" }, { "@@ -20 +20 @@" }))
    end)

    it("does not move a staged line for an insertion directly below it", function()
      assert.same({ 20 }, staged_at({ "@@ -20,0 +21,2 @@" }, { "@@ -20 +20 @@" }))
      assert.same({ 22 }, staged_at({ "@@ -19,0 +20,2 @@" }, { "@@ -20 +20 @@" }))
    end)

    it("keeps a staged line inside the unstaged rewrite that swallowed it", function()
      -- Index 10-19 rewritten as buffer 10-11. Unshifted, staged index 17 would
      -- land on buffer 17: the unrelated unstaged edit of index 25.
      assert.same({ 11 }, staged_at({ "@@ -10,10 +10,2 @@", "@@ -25 +17 @@" }, { "@@ -17 +17 @@" }))
    end)
  end)

  describe("with mock gitsigns", function()
    before_each(function()
      package.loaded["gitsigns"] = {
        get_hunks = function()
          return {
            { added = { start = 10, count = 5 }, removed = { start = 0, count = 0 }, type = "add" },
            -- added.start is the buffer line, removed.start the index line: they
            -- differ once earlier hunks shift the file, and only added.start is
            -- where the buffer shows the deletion.
            { added = { start = 47, count = 0 }, removed = { start = 50, count = 3 }, type = "delete" },
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
      assert.equals(47, result[2].line)
      assert.equals("delete", result[2].type)
      assert.equals(80, result[3].line)
      assert.equals("change", result[3].type)
    end)

    it("draws a top-of-file deletion on line 1 instead of dropping it", function()
      package.loaded["gitsigns"] = {
        get_hunks = function()
          return { { added = { start = 0, count = 0 }, removed = { start = 1, count = 2 }, type = "delete" } }
        end,
      }
      local result = git.get(0)
      assert.equals(1, #result)
      assert.equals(1, result[1].line)
    end)

    it("never marks gitsigns hunks staged", function()
      -- gitsigns.get_hunks(bufnr) diffs the buffer against the index, so every
      -- hunk it returns is unstaged. It takes no options: a { staged = true }
      -- argument is ignored and returns these same hunks, which once coloured
      -- every marker as staged.
      local result = git.get(0)
      assert.equals(3, #result)
      for _, r in ipairs(result) do
        assert.is_false(r.staged)
      end
    end)
  end)

  describe("cache", function()
    it("invalidate and invalidate_all do not error", function()
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

--- git.get() never blocks, so poll it until the background diff lands
---@param buf number
---@return { line: number, type: string, staged: boolean }[]
local function await_markers(buf)
  local result = {}
  vim.wait(10000, function()
    result = git.get(buf)
    return #result > 0
  end, 10)
  return result
end

--- Poll until git.get() serves a cached table rather than a fresh empty one
---@param buf number
---@return boolean settled
local function await_settled(buf)
  return vim.wait(10000, function()
    return git.get(buf) == git.get(buf)
  end, 10)
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
    assert.is_true(await_settled(buf))
    assert.same({}, git.get(buf))
    os.remove(path)
  end)

  it("returns markers only after the background diff lands", function()
    local path = repo .. "/file.txt"
    write_file(path, "a\nb\nc\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")
    write_file(path, "a\nb\nc\nd\n")

    local buf = open_buf(path)
    -- The statusline must get an answer without waiting on three git spawns
    assert.same({}, git.get(buf))
    assert.is_true(#await_markers(buf) >= 1)
  end)

  it("detects an unstaged addition", function()
    local path = repo .. "/file.txt"
    write_file(path, "line1\nline2\nline3\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")
    write_file(path, "line1\nline2\nline3\nline4\nline5\n")

    local buf = open_buf(path)
    local result = await_markers(buf)
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
    local result = await_markers(buf)
    assert.is_true(#result >= 1)
    assert.equals("change", result[1].type)
  end)

  it("reads hunks despite an external diff tool or forced colour", function()
    -- Both are common global settings (difftastic sets diff.external). Either
    -- one hides the @@ headers, and with them every marker.
    git_run(repo, "config", "diff.external", "true")
    git_run(repo, "config", "color.diff", "always")
    local path = repo .. "/file.txt"
    write_file(path, "a\nb\nc\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")
    write_file(path, "a\nB\nc\n")

    local buf = open_buf(path)
    local result = await_markers(buf)
    assert.equals(1, #result)
    assert.equals(2, result[1].line)
  end)

  it("marks staged hunks via staged flag", function()
    local path = repo .. "/file.txt"
    write_file(path, "a\nb\nc\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")

    write_file(path, "a\nb\nc\nd\n")
    git_run(repo, "add", "file.txt")

    local buf = open_buf(path)
    local result = await_markers(buf)
    assert.is_true(#result >= 1)
    local found_staged = false
    for _, r in ipairs(result) do
      if r.staged then
        found_staged = true
      end
    end
    assert.is_true(found_staged)
  end)

  it("places a staged hunk on its buffer line when unstaged edits shift it", function()
    local path = repo .. "/file.txt"
    local lines = {}
    for i = 1, 30 do
      lines[i] = tostring(i)
    end
    write_file(path, table.concat(lines, "\n") .. "\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")

    -- Stage a change to line 20, then insert five unstaged lines above it.
    -- The index still numbers the change 20; the buffer shows it on line 25.
    lines[20] = "twenty"
    write_file(path, table.concat(lines, "\n") .. "\n")
    git_run(repo, "add", "file.txt")
    write_file(path, "a\nb\nc\nd\ne\n" .. table.concat(lines, "\n") .. "\n")

    local buf = open_buf(path)
    local staged_at = {}
    for _, r in ipairs(await_markers(buf)) do
      if r.staged then
        table.insert(staged_at, r.line)
      end
    end
    assert.same({ 25 }, staged_at)
  end)

  it("caches results across calls until invalidated", function()
    local path = repo .. "/file.txt"
    write_file(path, "a\n")
    git_run(repo, "add", "file.txt")
    git_run(repo, "commit", "-q", "-m", "init")
    write_file(path, "a\nb\n")

    local buf = open_buf(path)
    local first = await_markers(buf)
    assert.is_true(#first >= 1)

    -- Mutate on disk; the cache still answers, no re-spawn
    write_file(path, "a\n")
    assert.equals(#first, #git.get(buf))

    -- Invalidation serves the stale markers while the refresh runs, so the
    -- column does not blink empty on every write, then converges on the truth
    git.invalidate(buf)
    assert.equals(#first, #git.get(buf))
    vim.wait(10000, function()
      return #git.get(buf) == 0
    end, 10)
    assert.equals(0, #git.get(buf))
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
