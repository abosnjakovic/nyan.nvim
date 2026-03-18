local M = {}

-- Cache for git diff results per buffer
local cache = {}

--- Parse a git diff unified format hunk header
--- Format: @@ -old_start[,old_count] +new_start[,new_count] @@
---@param header string The @@ line
---@return { line: number, type: string }?
local function parse_hunk_header(header)
  local old_start, old_count, new_start, new_count = header:match("@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not new_start then
    return nil
  end

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

  return { line = line, type = hunk_type }
end

--- Get git hunks by shelling out to git diff
---@param bufnr number Buffer number
---@return { line: number, type: string, staged: boolean }[]
local function get_from_git_diff(bufnr)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    return {}
  end

  -- Check cache
  local buf_cache = cache[bufnr]
  if buf_cache and buf_cache.filepath == filepath then
    return buf_cache.result
  end

  -- Get the git root for this file
  local dir = vim.fn.fnamemodify(filepath, ":h")
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel")
  if vim.v.shell_error ~= 0 or #git_root == 0 then
    return {}
  end

  -- Get unstaged diff
  local diff_output = vim.fn.systemlist(
    "git -C " .. vim.fn.shellescape(git_root[1]) .. " diff --unified=0 -- " .. vim.fn.shellescape(filepath)
  )
  if vim.v.shell_error ~= 0 then
    diff_output = {}
  end

  -- Get staged diff
  local staged_output = vim.fn.systemlist(
    "git -C " .. vim.fn.shellescape(git_root[1]) .. " diff --unified=0 --cached -- " .. vim.fn.shellescape(filepath)
  )
  if vim.v.shell_error ~= 0 then
    staged_output = {}
  end

  -- Parse staged lines into a set
  local staged_lines = {}
  for _, line in ipairs(staged_output) do
    if line:match("^@@") then
      local hunk = parse_hunk_header(line)
      if hunk and hunk.line > 0 then
        staged_lines[hunk.line] = true
      end
    end
  end

  -- Parse unstaged hunks
  local result = {}
  for _, line in ipairs(diff_output) do
    if line:match("^@@") then
      local hunk = parse_hunk_header(line)
      if hunk and hunk.line > 0 then
        table.insert(result, {
          line = hunk.line,
          type = hunk.type,
          staged = staged_lines[hunk.line] == true,
        })
      end
    end
  end

  -- Also add staged-only hunks (not in unstaged diff)
  for _, line in ipairs(staged_output) do
    if line:match("^@@") then
      local hunk = parse_hunk_header(line)
      if hunk and hunk.line > 0 then
        local already_present = false
        for _, r in ipairs(result) do
          if r.line == hunk.line then
            already_present = true
            break
          end
        end
        if not already_present then
          table.insert(result, {
            line = hunk.line,
            type = hunk.type,
            staged = true,
          })
        end
      end
    end
  end

  -- Cache the result
  cache[bufnr] = { filepath = filepath, result = result }
  return result
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

  -- Build set of staged hunk start lines
  local staged_lines = {}
  local staged_ok, staged_hunks = pcall(gitsigns.get_hunks, bufnr, { staged = true })
  if staged_ok and staged_hunks then
    for _, h in ipairs(staged_hunks) do
      local line = h.added and h.added.start or h.removed and h.removed.start
      if line and line > 0 then
        staged_lines[line] = true
      end
    end
  end

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
        staged = staged_lines[line] == true,
      })
    end
  end
  return result
end

--- Get git change markers for a buffer
--- Uses gitsigns when available (fast, in-memory), falls back to git diff
---@param bufnr number Buffer number
---@return { line: number, type: string, staged: boolean }[]
M.get = function(bufnr)
  local result = get_from_gitsigns(bufnr)
  if result then
    return result
  end
  return get_from_git_diff(bufnr)
end

--- Invalidate cache for a buffer
---@param bufnr number Buffer number
M.invalidate = function(bufnr)
  cache[bufnr] = nil
end

--- Invalidate all cached data
M.invalidate_all = function()
  cache = {}
end

--- Exposed for testing
M._parse_hunk_header = parse_hunk_header

return M
