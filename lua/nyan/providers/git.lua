local M = {}

-- Completed results per buffer: bufnr -> { filepath, result }
local cache = {}
-- In-flight refreshes: bufnr -> token. Guards against the statusline
-- spawning a fresh batch of git processes on every redraw.
local pending = {}
local next_token = 0

--- Parse a git diff unified format hunk header
--- Format: @@ -old_start[,old_count] +new_start[,new_count] @@
---@param header string The @@ line
---@return { line: number, type: string, old_start: number, old_count: number, new_count: number }?
local function parse_hunk_header(header)
  local old_start, old_count, new_start, new_count = header:match("@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not new_start then
    return nil
  end

  old_start = tonumber(old_start)
  old_count = tonumber(old_count) or 1
  new_count = tonumber(new_count) or 1
  new_start = tonumber(new_start)

  local hunk_type
  if old_count == 0 then
    hunk_type = "add"
  elseif new_count == 0 then
    hunk_type = "delete"
  else
    hunk_type = "change"
  end

  local line = new_start
  if hunk_type == "delete" and new_count == 0 then
    line = new_start
  end

  return { line = line, type = hunk_type, old_start = old_start, old_count = old_count, new_count = new_count }
end

--- Parse every hunk header in a diff
---@param diff_output string[]
---@return table[] hunks In file order
local function parse_hunks(diff_output)
  local hunks = {}
  for _, line in ipairs(diff_output) do
    local hunk = line:match("^@@") and parse_hunk_header(line)
    if hunk then
      table.insert(hunks, hunk)
    end
  end
  return hunks
end

--- Move an index line number onto the working tree (the buffer, once saved).
--- `git diff --cached` numbers lines against the index, so every unstaged
--- hunk above a staged one shifts where it appears in the buffer.
---@param line number Line in the index
---@param unstaged table[] Hunks from `git diff`, whose old side is the index
---@return number line Line in the working tree
local function index_to_worktree(line, unstaged)
  local offset = 0
  for _, hunk in ipairs(unstaged) do
    -- A pure insertion (old_count 0) sits after old_start; anything else
    -- covers old_start .. old_start + old_count - 1.
    if line < hunk.old_start + math.max(hunk.old_count, 1) then
      if hunk.old_count > 0 and line >= hunk.old_start then
        -- Rewritten again since it was staged. The rewrite may be shorter, so
        -- keep the line inside it rather than spilling onto lines below.
        return math.min(line + offset, hunk.line + math.max(hunk.new_count, 1) - 1)
      end
      break
    end
    offset = offset + hunk.new_count - hunk.old_count
  end
  return line + offset
end

--- Merge unstaged and staged diff output into markers
---@param diff_output string[] Lines of `git diff`
---@param staged_output string[] Lines of `git diff --cached`
---@return { line: number, type: string, staged: boolean }[]
local function build_markers(diff_output, staged_output)
  local unstaged = parse_hunks(diff_output)

  -- Staged hunks moved onto buffer lines, so they compare with unstaged ones
  local staged = {}
  local staged_lines = {}
  for _, hunk in ipairs(parse_hunks(staged_output)) do
    hunk.line = index_to_worktree(hunk.line, unstaged)
    if hunk.line > 0 then
      table.insert(staged, hunk)
      staged_lines[hunk.line] = true
    end
  end

  local result = {}
  local present = {}
  for _, hunk in ipairs(unstaged) do
    if hunk.line > 0 then
      table.insert(result, {
        line = hunk.line,
        type = hunk.type,
        staged = staged_lines[hunk.line] == true,
      })
      present[hunk.line] = true
    end
  end

  -- Also add staged-only hunks (not in unstaged diff)
  for _, hunk in ipairs(staged) do
    if not present[hunk.line] then
      table.insert(result, { line = hunk.line, type = hunk.type, staged = true })
    end
  end

  return result
end

--- Store a finished refresh and repaint, unless it was superseded
--- Runs on the main loop: vim.system callbacks land in a fast event context
--- where the Nvim API is off limits.
---@param bufnr number
---@param token number Token this refresh was started with
---@param filepath string
---@param result { line: number, type: string, staged: boolean }[]
local function finish(bufnr, token, filepath, result)
  vim.schedule(function()
    -- invalidate() drops the token, so a result that raced a write is discarded
    -- rather than reinstating pre-write markers.
    if pending[bufnr] ~= token then
      return
    end
    pending[bufnr] = nil
    cache[bufnr] = { filepath = filepath, result = result }
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.cmd("redrawstatus")
    end
  end)
end

--- Kick off a background `git diff` for a buffer
---@param bufnr number
---@param filepath string
local function refresh(bufnr, filepath)
  if pending[bufnr] then
    return
  end
  next_token = next_token + 1
  local token = next_token
  pending[bufnr] = token

  local dir = vim.fn.fnamemodify(filepath, ":h")

  -- vim.system raises if git is missing; a throw here would break the
  -- statusline that called us.
  local ok = pcall(vim.system, { "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }, function(root)
    local git_root = root.code == 0 and vim.trim(root.stdout or "") or ""
    if git_root == "" then
      -- Cache the miss too: without this, every statusline redraw of a non-git
      -- buffer shells out to `git rev-parse` again. Invalidation autocmds
      -- (write/enter/focus) still clear it, so repo-init is picked up.
      return finish(bufnr, token, filepath, {})
    end

    local out = {}
    local remaining = 2
    local function collect(key)
      return function(obj)
        out[key] = obj.code == 0 and vim.split(obj.stdout or "", "\n") or {}
        remaining = remaining - 1
        if remaining == 0 then
          finish(bufnr, token, filepath, build_markers(out.unstaged, out.staged))
        end
      end
    end

    vim.system({ "git", "-C", git_root, "diff", "--unified=0", "--", filepath }, { text = true }, collect("unstaged"))
    vim.system(
      { "git", "-C", git_root, "diff", "--unified=0", "--cached", "--", filepath },
      { text = true },
      collect("staged")
    )
  end)

  if not ok then
    finish(bufnr, token, filepath, {})
  end
end

--- Get git hunks from gitsigns (fast path)
---@param bufnr number Buffer number
---@return { line: number, type: string, staged: boolean }[]?
local function get_from_gitsigns(bufnr)
  local ok, gitsigns = pcall(require, "gitsigns")
  if not ok then
    return nil
  end

  local hunks_ok, hunks = pcall(gitsigns.get_hunks, bufnr)
  if not hunks_ok or not hunks then
    return nil
  end

  -- get_hunks() diffs the buffer against gitsigns' base (the index by
  -- default), so every hunk is unstaged. It takes no options: asking it for
  -- staged hunks returns these same ones.
  local result = {}
  for _, h in ipairs(hunks) do
    local line = h.added and h.added.start or 0
    if h.type == "delete" then
      line = h.removed and h.removed.start or 0
    end
    if line > 0 then
      table.insert(result, {
        line = line,
        type = h.type,
        staged = false,
      })
    end
  end
  return result
end

--- Get git change markers for a buffer
--- Uses gitsigns when available (fast, in-memory), otherwise returns the last
--- cached `git diff` result and refreshes it in the background. Never blocks:
--- the first call for a buffer returns an empty list and repaints when the
--- diff lands.
---@param bufnr number Buffer number
---@return { line: number, type: string, staged: boolean }[]
M.get = function(bufnr)
  local result = get_from_gitsigns(bufnr)
  if result then
    return result
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    return {}
  end

  local buf_cache = cache[bufnr]
  local for_this_file = buf_cache ~= nil and buf_cache.filepath == filepath
  if not (for_this_file and not buf_cache.stale) then
    refresh(bufnr, filepath)
  end
  -- Stale markers are served while the refresh runs, so a write does not blink
  -- the whole column off and back on.
  return for_this_file and buf_cache.result or {}
end

--- Mark a buffer's cached diff stale, so the next get() refreshes it
---@param bufnr number Buffer number
M.invalidate = function(bufnr)
  local buf_cache = cache[bufnr]
  if buf_cache then
    buf_cache.stale = true
  end
  pending[bufnr] = nil
end

--- Mark every cached diff stale
M.invalidate_all = function()
  for _, buf_cache in pairs(cache) do
    buf_cache.stale = true
  end
  pending = {}
end

--- Exposed for testing
M._parse_hunk_header = parse_hunk_header
M._build_markers = build_markers

return M
