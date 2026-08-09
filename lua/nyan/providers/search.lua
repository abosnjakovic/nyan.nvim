local M = {}

-- ponytail: whole-buffer scan, capped at 20k lines. Make the cap configurable
-- or scan incrementally only if someone actually hits it on a real file.
local MAX_LINES = 20000

-- bufnr -> { key = string, result = table }
local cache = {}

-- Pattern currently being typed in the search command line, or nil when the
-- command line is closed. An empty string is meaningful: it means the user has
-- opened `/` but typed nothing, which should mark nothing.
local live_pattern = nil

-- Number of real buffer scans performed. Exposed for tests to assert the cache
-- works; nothing outside tests reads it.
M._scan_count = 0

--- Record the pattern being typed in the search command line
---@param pattern string
M.set_live = function(pattern)
  live_pattern = pattern
end

--- Forget the live pattern (search command line closed)
M.clear_live = function()
  live_pattern = nil
end

--- Decide which pattern to mark: the one being typed, else the last search
--- while 'hlsearch' is active.
---@return string? pattern nil when nothing should be marked
local function resolve_pattern()
  local pattern = live_pattern
  if pattern == nil then
    if vim.v.hlsearch == 0 then
      return nil
    end
    pattern = vim.fn.getreg("/")
  end
  if pattern == "" then
    return nil
  end
  return pattern
end

--- Apply the 'smartcase' semantics that vim.fn.match() does not implement.
--- match() honours 'ignorecase' but never 'smartcase', so the two disagree in
--- exactly one case: both options on and the pattern contains an uppercase
--- character. A real search is case-sensitive there, so force it with \C.
---@param pattern string
---@return string pattern Possibly \C-prefixed
local function apply_case(pattern)
  if vim.o.ignorecase and vim.o.smartcase then
    -- Strip backslash escapes first, so \V and friends do not read as
    -- uppercase. This is the same rule Vim itself applies.
    if pattern:gsub("\\.", ""):find("%u") then
      return "\\C" .. pattern
    end
  end
  return pattern
end

--- Scan every line of a buffer for a Vim regex
---@param bufnr number Buffer number
---@param pattern string Vim regex
---@return { line: number }[]
local function scan(bufnr, pattern)
  local read_ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not read_ok or #lines > MAX_LINES then
    return {}
  end

  M._scan_count = M._scan_count + 1

  local effective = apply_case(pattern)
  local result = {}
  -- A half-typed pattern such as "foo\(" makes match() throw E54. Every
  -- keystroke passes through states like that, so this is the common path,
  -- not a defensive edge case.
  local match_ok = pcall(function()
    for i, text in ipairs(lines) do
      if vim.fn.match(text, effective) >= 0 then
        table.insert(result, { line = i })
      end
    end
  end)
  if not match_ok then
    return {}
  end
  return result
end

--- Get search-hit markers for a buffer
---@param bufnr number Buffer number
---@return { line: number }[] Matching lines, 1-indexed
M.get = function(bufnr)
  local pattern = resolve_pattern()
  if not pattern then
    return {}
  end

  local tick_ok, changedtick = pcall(vim.api.nvim_buf_get_changedtick, bufnr)
  if not tick_ok then
    return {}
  end

  local key = pattern .. "\0" .. changedtick
  local entry = cache[bufnr]
  if entry and entry.key == key then
    return entry.result
  end

  local result = scan(bufnr, pattern)
  cache[bufnr] = { key = key, result = result }
  return result
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

return M
